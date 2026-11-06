// Versioned multi-day orchestration. Shared money, tax, fills and risk helpers
// remain the frozen reference implementation. No end-of-session liquidation.
import {BY_SYMBOL} from './catalogue.js';
import {iso,day,fx,equity,runOpen,HISTORY_LIMIT,validQuote,assess,entryBudget,sectorAllowed,decisionContext,purchaseRationale,fill} from './engine.js';
function event(out,kind,reason,time,symbol='',data={}){out.events.push({time:iso(time),kind,symbol,reason,data});}
function queue(s,out,k,side,time,reason,risk_exit=false,learningContext=null,rationale=null){
  const existing=s.pending.find(x=>x.symbol===k);if(existing){if(risk_exit&&existing.side==='verkoop')Object.assign(existing,{risk_exit,reason});return;}
  const o={symbol:k,side,tick:s.tick,time:iso(time),reason,risk_exit};s.pending.push(o);event(out,'besluit',reason,time,k,o);
  if(learningContext)o.learning_context=learningContext;
  if(rationale)o.purchase_rationale=rationale;
}
export function tickMultiday(input,batch,time=Date.now(),options={}) {
  const s=structuredClone(input),out={state:s,trades:[],events:[],observations:[],equity:null};
  if(!s.running)return out;
  if(!runOpen(s,time)){s.running=false;s.error='Proefeindtijd bereikt.';return out;}
  for(const k of Object.keys(s.history))s.history[k]=s.history[k].slice(-HISTORY_LIMIT);
  const before=equity(s);s.multi_market.expected_open=batch.expected_open||[];s.multi_market.closed_symbols=batch.closed_symbols||[];
  const quotes={};for(const[k,q]of Object.entries(batch.quotes||{}))if(validQuote(k,q,time))quotes[k]=q;
  const venues={};
  for(const k of new Set(batch.expected_open||[])){
    const venue=BY_SYMBOL[k]?.exchange;if(!venue)continue;
    venues[venue]||={expected:0,fresh:0};venues[venue].expected++;if(quotes[k])venues[venue].fresh++;
  }
  out.quality={day:new Date(time).toISOString().slice(0,10),expected:Object.values(venues).reduce((n,v)=>n+v.expected,0),fresh:Object.values(venues).reduce((n,v)=>n+v.fresh,0),venues};
  s.multi_market.entry_symbols=Object.keys(quotes);
  // Also expose the current batch when no executable quotes were received.
  s.data_info={source:'Yahoo Finance',indicative:true,assumed_spread_bps:10,checked_at:iso(time),fx:batch.fx||null,quote_errors:batch.errors||{},fresh_symbols:Object.keys(quotes).length,multi_market:true,closed_symbols:s.multi_market.closed_symbols};
  if(!Object.keys(quotes).length){s.error=batch.error||'Geen verse koersen van open markten; geen uitvoering.';event(out,'wacht',s.error,time);return out;}
  if(!Number.isFinite(batch.fx?.usd_per_eur)||batch.fx.usd_per_eur<=0)throw Error('Ongeldige ECB-koers.');
  s.usd_per_eur=batch.fx.usd_per_eur;s.fx_time=batch.fx.date;
  s.error=Object.keys(batch.errors||{}).length?'Onvolledige actuele koersdekking; alleen verse kandidaten en uitvoeringen.':null;s.tick++;s.last_update=iso(time);
  for(const[k,q]of Object.entries(quotes)){
    s.prices[k]=(q.bid+q.ask)/2;s.price_fx[k]=q.fx_per_eur;s.last_observation[k]={time:q.time,delay_seconds:(time-Date.parse(q.time))/1000,indicative:true};
    const h=s.history[k]||(s.history[k]=[]);if(!h.length||Math.floor(Date.parse(h.at(-1).time)/300000)<Math.floor(time/300000)){h.push({time:iso(time),price:s.prices[k],quote_time:q.time});s.history[k]=h.slice(-HISTORY_LIMIT);}
    out.observations.push({received:iso(time),symbol:k,source:'yahoo',quote_time:q.time,payload:q,fx:batch.fx});
  }
  let guard=assess(s,time,quotes,before);const remaining=[];
  for(const order of s.pending){
    guard=assess(s,time,quotes,before);
    if(order.side==='koop'&&options.entryGate){let allowed=false;try{allowed=options.entryGate({symbol:order.symbol,context:order.learning_context,state:s,time,pending:true})===true;}catch{}
      if(!allowed){event(out,'leerfilter','Kooporder door het actieve leerfilter tegengehouden.',time,order.symbol);continue;}}
    if(order.side==='koop'&&((time-Date.parse(order.time))/60000>s.risk.config.order_ttl_minutes||guard.block||entryBudget(s,order.symbol,time)<10)){event(out,'geannuleerd','Kooporder verlopen of door risico geblokkeerd.',time,order.symbol);continue;}
    if(order.side==='koop'&&day(order.time,BY_SYMBOL[order.symbol].timezone)!==day(time,BY_SYMBOL[order.symbol].timezone)){event(out,'vervallen','Order van een eerdere lokale handelsdag.',time,order.symbol);continue;}
    if(!quotes[order.symbol]||!fill(s,order,quotes[order.symbol],time,out))remaining.push(order);
  }
  s.pending=remaining;guard=assess(s,time,quotes,before);
  const closing=k=>quotes[k]&&time>=Date.parse(quotes[k].session_end)-600000;
  for(const[k,p]of Object.entries(s.positions)){
    if(!quotes[k])continue;const price=s.prices[k]/fx(s,k);
    if(guard.exitAll||price<=p.stop||price>=p.target){const protective=guard.exitAll||price<=p.stop;
      queue(s,out,k,'verkoop',time,guard.exitAll?'Risicostop: '+guard.reasons.join(' '):price<=p.stop?'Stopverlies van 1,5% bereikt.':'Kostenbewust winstdoel bereikt.',protective);}
  }
  if(!s.last_decision||time-Date.parse(s.last_decision)>=300000){
    s.last_decision=iso(time);const candidates=[];
    if(!guard.block)for(const[k,h]of Object.entries(s.history)){
      if(!quotes[k]||closing(k)||h.length<6||time-Date.parse(h.at(-6).time)>1800000||s.positions[k]||s.pending.some(o=>o.symbol===k))continue;
      const avg=h.slice(-6,-1).reduce((v,x)=>v+x.price,0)/5,signal=h.at(-1).price/avg-1;if(signal>.002)candidates.push([signal,k]);
    }
    const slots=Math.max(0,s.risk.config.max_positions-Object.keys(s.positions).length-s.pending.filter(o=>o.side==='koop').length);
    let available=s.cash-s.risk.config.min_cash_eur-100*s.pending.filter(o=>o.side==='koop').length,count=0;
    candidates.sort((a,b)=>b[0]-a[0]||b[1].localeCompare(a[1]));
    for(const[signal,k]of candidates){if(count>=slots||available<100)break;if(!sectorAllowed(s,k)||entryBudget(s,k,time)<100-1e-8)continue;
      let context=decisionContext(s,k,quotes[k],time);if(context&&options.contextTag)context={...context,...options.contextTag};
      if(options.entryGate){let allowed=false;try{allowed=options.entryGate({symbol:k,context,state:s,time,signal,pending:false})===true;}catch{}
        if(!allowed){event(out,'leerfilter','Koopkandidaat door het leerfilter tegengehouden.',time,k);continue;}}
      const rationale=purchaseRationale(s,k,quotes[k],time,signal,context);
      rationale.decision.rank_among_candidates=candidates.findIndex(x=>x[1]===k)+1;rationale.decision.candidate_count=candidates.length;
      rationale.decision.leading_candidates=candidates.slice(0,5).map(([value,symbol])=>({symbol,signal_fraction:value}));
      queue(s,out,k,'koop',time,`Koers ${(signal*100).toFixed(2)}% boven het gemiddelde van de vorige 5 metingen. Budget EUR100; stop -1,5%; kostenbewust doel.`,false,context,rationale);available-=100;count++;}
    if(!count)event(out,'wacht','Geen koopsignaal binnen saldo-, kosten- en risicoregels.',time);
  }
  if(!s.benchmark_units&&quotes.AAPL){s.benchmark_started_at=iso(time);s.benchmark_units=500/(quotes.AAPL.ask*1.0005/s.usd_per_eur*1.001);s.benchmark_cash=0;}
  const eq=equity(s);s.peak=Math.max(s.peak,eq);s.max_drawdown=Math.max(s.max_drawdown,(s.peak-eq)/s.peak*100);
  if(quotes.AAPL)s.benchmark_last_value=s.benchmark_units*quotes.AAPL.bid*.9995/s.usd_per_eur*.999;
  s.benchmark_stale=!quotes.AAPL;out.equity={time:iso(time),value:eq,benchmark:s.benchmark_last_value??s.benchmark_cash};return out;
}

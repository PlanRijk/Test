// Deterministic paper engine. No broker endpoints or AI calls.
import { COMPANIES, BY_SYMBOL } from './catalogue.js';
export const VERSION = 'global-paper-v1';
// Six samples drive the strategy; twelve retain an hour of decision context.
export const HISTORY_LIMIT = 12;
export const FEATURE_SCHEMA='decision-net-v1';
export const FEATURE_NAMES=['return_1','return_5','volatility_5','signal','cost_drag','quote_age','session_remaining'];
const formatters = new Map();
export const iso = ms => new Date(ms).toISOString();
export function localParts(time, zone) {
  if(!zone)throw Error('Expliciete beurstijdzone ontbreekt.');
  if (!formatters.has(zone)) formatters.set(zone, new Intl.DateTimeFormat('en-GB', {
    timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23',weekday:'short'
  }));
  return Object.fromEntries(formatters.get(zone).formatToParts(new Date(time)).map(p=>[p.type,p.value]));
}
export function day(time, zone='Europe/Brussels') { const p=localParts(time,zone); return `${p.year}-${p.month}-${p.day}`; }
export function possibleSession(item,time) {
  const p=localParts(time,item.timezone); if(['Sat','Sun'].includes(p.weekday)) return false;
  const minute=Number(p.hour)*60+Number(p.minute);
  const windows={XNYS:[570,960],XNAS:[570,960],XLON:[480,990],XHEL:[600,1110],XOSL:[540,990],XCSE:[540,1020]};
  const [a,b]=windows[item.exchange]||[540,1050]; return a<=minute&&minute<b;
}
export function currency(symbol) { return BY_SYMBOL[symbol]?.currency||'USD'; }
export function fx(s,symbol) {
  const c=currency(symbol),rate=s.price_fx?.[symbol]||(c==='EUR'?1:c==='USD'?s.usd_per_eur:0);
  if (!Number.isFinite(rate)||rate<=0) throw Error('Ontbrekende positie-wisselkoers.'); return rate;
}
export function equity(s) { return s.cash+Object.entries(s.positions).reduce((sum,[k,p])=>sum+p.qty*s.prices[k]/fx(s,k),0); }
function commission(s,k,gross) { const c=s.multi_market.cost_assumptions; return Math.max(gross*c.commission_rate,currency(k)==='USD'?c.us_minimum_commission_usd/s.usd_per_eur:c.other_minimum_commission_eur); }
function tob(s,gross) { const c=s.belgian_tax.config; return s.belgian_tax.enabled?Math.min(gross*c.transaction_tax_rate,c.transaction_tax_cap_eur):0; }
function extra(s,k,gross,qty,buy) {
  const c=s.multi_market.cost_assumptions;
  return {foreign_tax_reserve_eur:buy&&!['US','BE'].includes(BY_SYMBOL[k].country)?gross*c.foreign_buy_reserve_rate:0,
    adr_reserve_eur:buy&&['TSM','TM'].includes(k)?qty*c.adr_buy_reserve_usd_per_share/s.usd_per_eur:0};
}
export function purchase(s,k,price,budget) {
  const costs=g=>{const e=extra(s,k,g,g/price,true);return g+commission(s,k,g)+tob(s,g)+e.foreign_tax_reserve_eur+e.adr_reserve_eur;};
  let lo=0,hi=budget;for(let i=0;i<60;i++){const m=(lo+hi)/2;if(costs(m)>budget)hi=m;else lo=m;}
  return {qty:lo/price,fee:commission(s,k,lo),tax:{transaction_tax_eur:tob(s,lo),capital_gains_reserve_eur:0,...extra(s,k,lo,lo/price,true)}};
}
export function sale(s,k,p,price) {
  const gross=p.qty*price,entry=p.entry_gross_eur??p.qty*p.entry,gain=Math.max(0,gross-entry);
  const tax={gross_eur:gross,commission_eur:commission(s,k,gross),transaction_tax_eur:tob(s,gross),
    capital_gains_reserve_eur:s.belgian_tax.enabled?gain*s.belgian_tax.config.capital_gains_reserve_rate:0,
    taxable_gain_eur:gain,entry_gross_eur:entry,...extra(s,k,gross,p.qty,false)};
  tax.net_pnl_eur=gross-tax.commission_eur-tax.transaction_tax_eur-tax.capital_gains_reserve_eur-tax.foreign_tax_reserve_eur-tax.adr_reserve_eur-p.cost;
  return tax;
}
export function profitTarget(s,k,p) {
  const minimum=s.belgian_tax.config.minimum_net_profit_eur;let lo=p.entry*1.025,hi=lo;
  for(let i=0;i<20&&sale(s,k,p,hi).net_pnl_eur<minimum;i++)hi*=1.25;
  if(sale(s,k,p,hi).net_pnl_eur<minimum)throw Error('Geen eindig winstdoel.');
  for(let i=0;i<60;i++){const m=(lo+hi)/2;if(sale(s,k,p,m).net_pnl_eur>=minimum)hi=m;else lo=m;}
  return hi;
}
export function sectorAllowed(s,k,includePending=true) {
  const occupied=new Set([...Object.keys(s.positions),...(includePending?s.pending.filter(o=>o.side==='koop').map(o=>o.symbol):[])]);
  return [...occupied].filter(x=>BY_SYMBOL[x]?.sector===BY_SYMBOL[k]?.sector).length<(s.catalogue.max_positions_per_sector||1);
}
export function assess(s,time,quotes,previousEquity=equity(s)) {
  const r=s.risk,c=r.config,value=equity(s),today=day(time); if(!Number.isFinite(value)||value<0)throw Error('Ongeldige portefeuillewaarde.');
  if(r.day!==today)Object.assign(r,{day:today,day_start_equity:previousEquity,daily_halted:false,buys_today:0});
  r.data_complete=!Object.keys(s.positions).some(k=>s.multi_market.expected_open.includes(k)&&!quotes[k]);
  s.peak=Math.max(s.peak||500,value);
  if(r.day_start_equity-value>=c.daily_loss_eur-1e-9)r.daily_halted=true;
  if(s.peak-value>=c.max_drawdown_eur-1e-9){r.global_halted=true;r.global_reason='Daling vanaf hoogste portefeuillewaarde bereikt; handmatige beoordeling nodig.';}
  const reasons=[];if(r.daily_halted)reasons.push('Dagverliesgrens bereikt.');if(r.global_halted)reasons.push(r.global_reason);
  for(const [k,q]of Object.entries(quotes)){
    const price=(q.bid+q.ask)/2,old=r.previous_quotes[k],elapsed=old?(time-Date.parse(old.time))/1000:0;
    if(old&&elapsed>0&&elapsed<=600&&price/old.price-1<=-c.shock_drop_fraction)r.cooldowns[k]=iso(time+c.shock_pause_minutes*60000);
    r.previous_quotes[k]={time:iso(time),price};
  }
  const exitAll=Boolean(reasons.length);if(!r.data_complete)reasons.push('Ontbrekende verse koers voor een open positie.');
  return {block:reasons.length>0||r.buys_today>=c.max_buys_per_day,exitAll,reasons};
}
export function entryBudget(s,k,time) {
  const r=s.risk,c=r.config;if(!s.universe.includes(k)||!s.multi_market.entry_symbols.includes(k)||!sectorAllowed(s,k,false)||r.daily_halted||r.global_halted||r.data_complete===false||r.buys_today>=c.max_buys_per_day||s.positions[k])return 0;
  if(r.cooldowns[k]&&time<Date.parse(r.cooldowns[k]))return 0;if(Object.keys(s.positions).length>=c.max_positions)return 0;
  const gross=Object.entries(s.positions).reduce((v,[x,p])=>v+p.qty*s.prices[x]/fx(s,x),0);
  return Math.max(0,Math.min(100,s.cash-c.min_cash_eur,equity(s)*c.max_exposure_fraction-gross));
}
function affordable(s,k,price,budget) {
  const buy=purchase(s,k,price,budget),gross=buy.qty*price,cost=gross+buy.fee+Object.values(buy.tax).reduce((a,b)=>a+b,0);
  const p={qty:buy.qty,entry:price,entry_gross_eur:gross,cost},loss=Math.max(0,-sale(s,k,p,price*.998).net_pnl_eur);
  let exits=0;for(const [x,pos]of Object.entries(s.positions)){const d=sale(s,x,pos,s.prices[x]/fx(s,x)*.999);exits+=Math.max(0,d.gross_eur-(pos.cost+d.net_pnl_eur));}
  const value=equity(s),c=s.risk.config;
  return loss<=Math.min(c.daily_loss_eur-Math.max(0,(s.risk.day_start_equity??value)-value)-exits,c.max_drawdown_eur-Math.max(0,s.peak-value)-exits)+1e-9;
}
export function profile(s){return `${s.risk.version}+${s.belgian_tax.version}+${s.catalogue.version}+${s.multi_market.version}`;}
function event(out,kind,reason,time,symbol='',data={}){out.events.push({time:iso(time),kind,symbol,reason,data});}
export function validQuote(k,q,time) {
  if(!BY_SYMBOL[k]||!q)return false;
  const age=time-Date.parse(q.time);
  return [q.bid,q.ask,q.fx_per_eur].every(x=>Number.isFinite(x)&&x>0)&&q.bid<=q.ask&&q.currency===currency(k)&&
    (q.currency!=='EUR'||Math.abs(q.fx_per_eur-1)<1e-12)&&age>=0&&age<=120000&&
    Date.parse(q.session_start)<=time&&time<Date.parse(q.session_end)&&possibleSession(BY_SYMBOL[k],time);
}
export function decisionContext(s,k,q,time){
  const h=s.history[k]?.slice(-6);if(!validQuote(k,q,time)||!h||h.length!==6)return null;
  const stamps=h.map(x=>Date.parse(x.time));if(stamps.some((x,i)=>!Number.isFinite(x)||x>time||(i&&x<=stamps[i-1]))||time-stamps[0]>1800000)return null;
  const prices=h.map(x=>x.price);if(prices.some(x=>!Number.isFinite(x)||x<=0))return null;
  const returns=prices.slice(1).map((v,i)=>v/prices[i]-1),avg=returns.reduce((a,b)=>a+b,0)/5;
  const volatility=Math.sqrt(returns.reduce((a,b)=>a+(b-avg)**2,0)/5),signal=prices[5]/(prices.slice(0,5).reduce((a,b)=>a+b,0)/5)-1;
  const entry=q.ask*1.0005/q.fx_per_eur,buy=purchase(s,k,entry,100),p={qty:buy.qty,cost:100,entry,entry_gross_eur:buy.qty*entry};
  const cost=-sale(s,k,p,q.bid*.9995/q.fx_per_eur).net_pnl_eur/100;
  const features=[returns[4],prices[5]/prices[0]-1,volatility,signal,cost,(time-Date.parse(q.time))/120000,(Date.parse(q.session_end)-time)/23400000];
  if(features.some(x=>!Number.isFinite(x)))return null;
  return {schema:FEATURE_SCHEMA,features,symbol:k,venue:BY_SYMBOL[k].exchange,decision_time:iso(time),quote_time:q.time};
}
export function purchaseRationale(s,k,q,time,signal,context){
 const h=s.history[k].slice(-6),average=h.slice(0,5).reduce((n,x)=>n+x.price,0)/5;
 const entry=q.ask*1.0005/q.fx_per_eur,buy=purchase(s,k,entry,100),position={qty:buy.qty,cost:100,entry,entry_gross_eur:buy.qty*entry};
 const flat=sale(s,k,position,q.bid*.9995/q.fx_per_eur),target=profitTarget(s,k,position);
 return {schema:'purchase-rationale-v1',id:k+'|'+iso(time),recorded_at:iso(time),profile:profile(s),
  decision:{time:iso(time),symbol:k,company:BY_SYMBOL[k].name,sector:BY_SYMBOL[k].sector,exchange:BY_SYMBOL[k].exchange,
   statement:`De laatste koers ligt ${(signal*100).toFixed(3)}% boven het gemiddelde van de vijf voorgaande metingen. Dit overschrijdt de vaste drempel van 0,2%. De aankoop wordt alleen op een latere verse koers uitgevoerd als saldo, kosten en risico dat nog toelaten.`,
   signal_fraction:signal,threshold_fraction:.002,previous_five_average:average,latest_mid:(q.bid+q.ask)/2,currency:q.currency,
   observations:h.map(x=>({time:x.time,quote_time:x.quote_time||null,price:x.price})),quote_time:q.time,quote_age_seconds:(time-Date.parse(q.time))/1000,
   features:context?.features||null,feature_schema:context?.schema||null,model:context?.model_evaluation||null,policy:context?.policy||'baseline',
   additional_rule:context?.policy==='low_turnover'?'Minstens 0,4% signaal en maximaal één nieuw koopbesluit per uur.':context?.model_evaluation?'Modelkans moet minstens 60% zijn binnen de getoetste beurzen.':'Vaste referentieregels.'},
  cost_estimate:{budget_eur:100,commission_eur:buy.fee,buy_taxes_and_reserves:buy.tax,flat_round_trip_loss_eur:-flat.net_pnl_eur,
   gross_target_price_eur:target,minimum_net_profit_eur:s.belgian_tax.config.minimum_net_profit_eur,assumed_spread_bps:10,slippage_bps_each_side:5,
   note:'Proefkosten en voorlopige belastingreserves; geen bevestigde persoonlijke belasting of brokerfee.'},
  risk_at_decision:{cash_eur:s.cash,equity_eur:equity(s),open_positions:Object.keys(s.positions).length,pending_buys:s.pending.filter(x=>x.side==='koop').length,
   buys_today:s.risk.buys_today,config:structuredClone(s.risk.config),sector_available:sectorAllowed(s,k),data_complete:s.risk.data_complete,daily_halted:s.risk.daily_halted,global_halted:s.risk.global_halted},
  limitations:['Dit is een regelgestuurde paperbeslissing, geen voorspelling van zekere winst.','Er is geen volledige bedrijfswaardering of causale nieuwsinterpretatie voor deze aankoop uitgevoerd.','Stop- en verliesdrempels garanderen geen uitvoeringsprijs of maximaal verlies.']};
}
export function fill(s,order,q,time,out) {
  const k=order.symbol;if(!validQuote(k,q,time)||Date.parse(q.time)<=Date.parse(order.time))return false;
  const buy=order.side==='koop',price=(buy?q.ask*1.0005:q.bid*.9995),eur=price/q.fx_per_eur;
  s.price_fx[k]=q.fx_per_eur;s.prices[k]=(q.bid+q.ask)/2;s.last_observation[k]={time:q.time,indicative:true};
  let qty,fee,tax,pnl=0,learningContext=order.learning_context||null,rationale=order.purchase_rationale||null;
  if(buy){
    if(s.positions[k])return true;const budget=entryBudget(s,k,time);
    if(budget<10||!affordable(s,k,eur,budget)){event(out,'kostenrem','Aankoop past niet binnen het risico-/kostenbudget.',time,k);return true;}
    ({qty,fee,tax}=purchase(s,k,eur,budget));const cost=qty*eur+fee+Object.values(tax).reduce((a,b)=>a+b,0);s.cash-=cost;if(s.cash<0&&s.cash>-1e-8)s.cash=0;
    if(learningContext)learningContext={...learningContext,entry_time:iso(time)};
    if(!rationale)rationale={schema:'purchase-rationale-v1',id:k+'|'+order.time,recorded_at:iso(time),profile:profile(s),
      decision:{time:order.time,symbol:k,statement:order.reason,detail_unavailable:true,note:'Deze order bestond al voor de uitgebreide motivatie; ontbrekende beslisgegevens zijn niet achteraf verzonnen.'}};
    rationale=structuredClone(rationale);rationale.execution={time:iso(time),decision_time:order.time,quote_time:q.time,quote_age_seconds:(time-Date.parse(q.time))/1000,
     statement:'Virtuele aankoop op een latere verse bronkoers; saldo-, sector-, kosten- en risicocontroles bij uitvoering geslaagd.',
     price_local:price,currency:q.currency,fx_per_eur:q.fx_per_eur,quantity:qty,commission_eur:fee,taxes_and_reserves:tax,cost_eur:cost,cash_after_eur:s.cash};
    const p={qty,cost,entry_gross_eur:qty*eur,entry:eur,time:iso(time),stop:eur*.985,target:eur*1.025,currency:currency(k)};
    if(learningContext)p.learning_context=learningContext;
    // The immutable full explanation lives in the buy receipt; carry its ID to exit.
    p.purchase_rationale={schema:rationale.schema,id:rationale.id,decision:{time:rationale.decision.time,symbol:k,statement:rationale.decision.statement}};
    p.target=profitTarget(s,k,p);s.positions[k]=p;s.risk.buys_today++;
  }else{
    const p=s.positions[k];if(!p)return true;
    learningContext=p.learning_context||null;
    rationale=p.purchase_rationale||null;
    tax=sale(s,k,p,eur);
    const protective=order.risk_exit||eur<=p.stop||s.risk.daily_halted||s.risk.global_halted;
    if(!protective&&tax.net_pnl_eur<s.belgian_tax.config.minimum_net_profit_eur){event(out,'belastingfilter','Gewone verkoop onvoldoende netto positief.',time,k);return true;}
    qty=p.qty;fee=tax.commission_eur;pnl=tax.net_pnl_eur;s.cash+=tax.gross_eur-fee-tax.transaction_tax_eur-tax.capital_gains_reserve_eur-tax.foreign_tax_reserve_eur-tax.adr_reserve_eur;s.realized+=pnl;delete s.positions[k];
    if(pnl<0)s.risk.cooldowns[k]=iso(time+s.risk.config.loss_cooldown_minutes*60000);
  }
  s.fees+=fee;s.belgian_tax.transaction_tax_eur+=tax.transaction_tax_eur;s.belgian_tax.capital_gains_reserve_eur+=tax.capital_gains_reserve_eur;
  for(const key of ['foreign_tax_reserve_eur','adr_reserve_eur'])s.multi_market[key]+=tax[key]||0;
  const snapshot={strategy_version:profile(s),transport_version:'supabase-v1',tax_scenario:true,tax_config:s.belgian_tax.config,tax_detail:tax,risk_config:s.risk.config,multi_market_config:s.multi_market.cost_assumptions,
    cash:s.cash,equity:equity(s),fx:q.fx_per_eur,currency:currency(k),price_local:price,price_usd:currency(k)==='USD'?price:null,history:s.history[k].slice(-40),quote:q,mode:'yahoo',reason:order.reason,decision_time:order.time,qty,side:order.side,symbol:k,time:iso(time),learning_context:learningContext,purchase_rationale:rationale};
  out.trades.push({time:iso(time),symbol:k,side:order.side,qty,price,fee,pnl,reason:order.reason,snapshot});event(out,'uitvoering','Virtuele uitvoering op latere verse koers.',time,k);return true;
}
function queue(s,out,k,side,time,reason,risk_exit=false,learningContext=null,rationale=null){
  const existing=s.pending.find(x=>x.symbol===k);if(existing){if(risk_exit&&existing.side==='verkoop')Object.assign(existing,{risk_exit,reason});return;}
  const o={symbol:k,side,tick:s.tick,time:iso(time),reason,risk_exit};s.pending.push(o);event(out,'besluit',reason,time,k,o);
  if(learningContext)o.learning_context=learningContext;
  if(rationale)o.purchase_rationale=rationale;
}
export function tick(input,batch,time=Date.now(),options={}) {
  const s=structuredClone(input),out={state:s,trades:[],events:[],observations:[],equity:null};
  if(!s.running)return out;
  if(!s.run_until||time>=Date.parse(s.run_until)){s.running=false;s.error='Proefeindtijd bereikt.';return out;}
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
    if(day(order.time,BY_SYMBOL[order.symbol].timezone)!==day(time,BY_SYMBOL[order.symbol].timezone)){event(out,'vervallen','Order van een eerdere lokale handelsdag.',time,order.symbol);continue;}
    if(!quotes[order.symbol]||!fill(s,order,quotes[order.symbol],time,out))remaining.push(order);
  }
  s.pending=remaining;guard=assess(s,time,quotes,before);
  const closing=k=>quotes[k]&&time>=Date.parse(quotes[k].session_end)-600000;
  for(const[k,p]of Object.entries(s.positions)){
    if(!quotes[k])continue;const price=s.prices[k]/fx(s,k);
    if(guard.exitAll||closing(k)||price<=p.stop||price>=p.target){const protective=guard.exitAll||closing(k)||price<=p.stop;
      queue(s,out,k,'verkoop',time,guard.exitAll?'Risicostop: '+guard.reasons.join(' '):closing(k)?'Dagsluiting van de eigen beurs.':price<=p.stop?'Stopverlies van 1,5% bereikt.':'Kostenbewust winstdoel bereikt.',protective);}
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

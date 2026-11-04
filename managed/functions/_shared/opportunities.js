// Observational study only. No orders, account debits or training labels.
import {BY_SYMBOL} from './catalogue.js';
import {day,decisionContext,entryBudget,equity,fx,purchase,sale,sectorAllowed,validQuote} from './engine.js';
import {sha} from './learner.js';
export const STUDY={version:'opportunity-study-v1',budget_eur:100,horizons_minutes:[30,120],entry_ttl_minutes:10,exit_tolerance_minutes:10,max_active:200,
 cohorts:['momentum','control'],signal:.002,control_after_minutes:30,
 basket:['AAPL','CAT','JNJ','JPM','NEE','LIN','XOM','KO','AMZN','GOOGL','PLD'],basket_budget_eur:400};
const stamp=t=>new Date(t).toISOString(),clone=structuredClone;
const epoch=t=>Math.floor(t/300000);
export async function studyFingerprint(s){return sha({study:STUDY,risk:s.risk.config,tax:s.belgian_tax.config,costs:s.multi_market.cost_assumptions,universe:s.universe});}
function mainReasons(s,k){
 const r=s.risk,c=r.config,a=[];
 if(s.pending.some(x=>x.side==='koop'&&x.symbol===k))return ['queued_in_main'];
 if(s.positions[k])return ['already_held'];
 if(r.daily_halted||r.global_halted)a.push('risk_pause');if(r.data_complete===false)a.push('missing_position_quote');
 if(r.buys_today>=c.max_buys_per_day)a.push('daily_limit');
 if(Object.keys(s.positions).length+s.pending.filter(x=>x.side==='koop').length>=c.max_positions)a.push('position_limit');
 if(!sectorAllowed(s,k))a.push('sector_limit');if(entryBudget(s,k,Date.parse(s.data_info.checked_at))<100-1e-8)a.push('budget_or_risk_constraint');
 return a.length?a:['not_queued_or_other_filter'];
}
function liquidation(s){let total=s.cash;for(const[k,p]of Object.entries(s.positions)){if(!Number.isFinite(s.prices[k]))return null;const t=sale(s,k,p,s.prices[k]/fx(s,k)*.9995**2);total+=p.cost+t.net_pnl_eur;}return total;}
function basketStep(b,s,quotes,time){
 b||={stage:'waiting',symbols:STUDY.basket};
 const all=STUDY.basket.every(k=>quotes[k]),sameSession=all&&STUDY.basket.every(k=>Date.parse(quotes[k].session_end)-time>600000);
 if(b.stage==='waiting'&&sameSession){b={stage:'pending',symbols:STUDY.basket,decision_at:stamp(time),decision_quotes:Object.fromEntries(STUDY.basket.map(k=>[k,quotes[k].time]))};return b;}
 if(b.stage==='pending'){
  if(time-Date.parse(b.decision_at)>600000)return {stage:'waiting',symbols:STUDY.basket};
  if(all&&STUDY.basket.every(k=>Date.parse(quotes[k].time)>Date.parse(b.decision_at)&&Date.parse(quotes[k].time)>Date.parse(b.decision_quotes[k]))){
   const positions={},prices={},fees=[];
   for(const k of STUDY.basket){const q=quotes[k],price=q.ask*1.0005/q.fx_per_eur,buy=purchase(s,k,price,STUDY.basket_budget_eur/11);positions[k]={qty:buy.qty,cost:STUDY.basket_budget_eur/11,entry:price,entry_gross_eur:buy.qty*price};prices[k]=(q.bid+q.ask)/2/q.fx_per_eur;fees.push(buy.fee);}
   b={stage:'holding',symbols:STUDY.basket,started_at:stamp(time),cash:100,positions,prices,fees_eur:fees.reduce((a,v)=>a+v,0),main_anchor:liquidation(s),initial_eur:500};
  }else return b;
 }
 if(b.stage==='holding'){
  for(const k of STUDY.basket)if(quotes[k]){const price=(quotes[k].bid+quotes[k].ask)/2/quotes[k].fx_per_eur;
   if(Math.abs(price/b.prices[k]-1)>.3){b.stage='review_required';b.message='Grote koers-/valutawijziging; mogelijke corporate action. Waardering geblokkeerd tot herbeoordeling.';return b;}b.prices[k]=price;}
  const value=100+STUDY.basket.reduce((v,k)=>{const t=sale(s,k,b.positions[k],b.prices[k]*.9995**2);return v+b.positions[k].cost+t.net_pnl_eur;},0);
  b.liquidation_estimate_eur=value;b.return_percent=(value/500-1)*100;b.fresh_symbols=STUDY.basket.filter(k=>quotes[k]).length;b.current=all;b.last_check=stamp(time);
  const marked=liquidation(s);b.main_return_since_anchor_percent=marked!=null&&b.main_anchor>0?(marked/b.main_anchor-1)*100:null;
 }
 return b;
}
export async function stepOpportunities(payload,market,batch,time=Date.now()){
 if(!payload?.enabled)return null;
 const s=clone(payload.state||{}),fingerprint=await studyFingerprint(market),records=[],updates=[];
 if(!s.fingerprint)Object.assign(s,{fingerprint,started_at:stamp(time),active:{},seen:{},rounds:0,skipped_capacity:0});
 if(s.fingerprint!==fingerprint)return {revision:payload.revision,state:{...s,status:'profile_changed',message:'Kosten- of onderzoeksprotocol gewijzigd; geen gemengde uitkomsten.'},records,updates};
 const quotes=Object.fromEntries(Object.entries(batch.quotes||{}).filter(([k,q])=>validQuote(k,q,time)));
 const today=stamp(time).slice(0,10);s.seen=Object.fromEntries(Object.entries(s.seen).filter(([k])=>k.includes('|'+today+'|')));
 const patch=(r,p)=>updates.push({id:r.id,...p});
 for(const [id,r]of Object.entries(s.active)){
  const q=quotes[r.symbol],same=q&&q.session_start===r.session_start&&q.session_end===r.session_end;
  if(!r.entry){
   if(time>Date.parse(r.decision_at)+600000||time>=Date.parse(r.session_end)){patch(r,{status:'expired',finished_at:stamp(time),reason:'Geen latere verse instapquote binnen tien minuten en dezelfde sessie.'});delete s.active[id];continue;}
   if(!same||Date.parse(q.time)<=Date.parse(r.decision_at)||Date.parse(q.time)<=Date.parse(r.decision_quote_time))continue;
   const price=q.ask*1.0005/q.fx_per_eur,buy=purchase(market,r.symbol,price,100);
   const entry={time:stamp(time),quote_time:q.time,price_eur:price,price_local:q.ask*1.0005,fx:q.fx_per_eur,qty:buy.qty,cost:100,entry_gross_eur:buy.qty*price,commission_eur:buy.fee,taxes:buy.tax};
   patch(r,{entry});r.entry={time:entry.time,quote_time:entry.quote_time,price_eur:price,qty:buy.qty,cost:100,entry_gross_eur:buy.qty*price};
   r.remaining=[30,120];
  }
  const outcomes={};
  for(const minutes of [...r.remaining]){
   const due=Date.parse(r.entry.time)+minutes*60000,latest=Math.min(due+600000,Date.parse(r.session_end));let result;
   if(due>=Date.parse(r.session_end))result={status:'missing',reason:'Te weinig resterende reguliere sessietijd.'};
   else if(time>latest||time>=Date.parse(r.session_end))result={status:'missing',reason:'Geen verse meetquote binnen de vooraf vastgelegde meetperiode.'};
   else if(time>=due&&same&&Date.parse(q.time)>=due&&Date.parse(q.time)>Date.parse(r.entry.quote_time)){
    const price=q.bid*.9995/q.fx_per_eur,t=sale(market,r.symbol,r.entry,price);
    result={status:'observed',time:stamp(time),quote_time:q.time,actual_minutes:(time-Date.parse(r.entry.time))/60000,price_local:q.bid*.9995,fx:q.fx_per_eur,net_eur:t.net_pnl_eur,gross_move_percent:(price/r.entry.price_eur-1)*100,exit_costs:t};
   }
   if(result){outcomes[String(minutes)]=result;r.remaining=r.remaining.filter(v=>v!==minutes);}
  }
  if(Object.keys(outcomes).length)patch(r,{outcomes});
  if(!r.remaining.length){patch(r,{status:'complete',finished_at:stamp(time)});delete s.active[id];}
 }
 for(const[k,q]of Object.entries(quotes).sort(([a],[b])=>a.localeCompare(b))){
  if(!market.universe.includes(k)||Date.parse(q.session_end)-time<=600000)continue;
  const context=decisionContext(market,k,q,time);if(!context)continue;
  const localDay=day(time,BY_SYMBOL[k].timezone),signal=context.features[3];
  for(const cohort of STUDY.cohorts){
   if(cohort==='momentum'&&signal<=.002||cohort==='control'&&time<Date.parse(q.session_start)+1800000)continue;
   const key=k+'|'+localDay+'|'+cohort;if(s.seen[key])continue;
   if(Object.keys(s.active).length>=200){s.skipped_capacity++;continue;}
   const id='op-'+(await sha(s.started_at+'|'+fingerprint+'|'+key)).slice(0,24),reasons=mainReasons(market,k);
   const statement=cohort==='momentum'?`Eerste verse momentumkans van deze beursdag: ${(signal*100).toFixed(3)}% boven het gemiddelde van vijf eerdere metingen. Onafhankelijke waarneming, ook bij ontbrekende ruimte in de hoofdproef.`:'Eerste bruikbare controlemoment vanaf dertig minuten na beursopening, gekozen zonder eis aan de richting van het koopsignaal.';
   const row={id,protocol:STUDY.version,fingerprint,day:localDay,symbol:k,venue:BY_SYMBOL[k].exchange,sector:BY_SYMBOL[k].sector,cohort,decision_at:stamp(time),decision_quote_time:q.time,
    session_start:q.session_start,session_end:q.session_end,status:'watching',statement,main_reasons:reasons,context,observations:market.history[k].slice(-6),budget_eur:100,
    cost_estimate:{flat_round_trip_loss_eur:context.features[4]*100,tax_config:clone(market.belgian_tax.config),cost_config:clone(market.multi_market.cost_assumptions)},
    limitations:['Hypothetische onafhankelijke kans; geen uitgevoerde order of portefeuillewinst.','Vaste meetperioden zonder stoporders; geen simulatie van een volledige handelsstrategie.','Controlemomenten en momentumkansen kunnen verschillen in timing. Samenhang bewijst geen oorzaak.'],outcomes:{}};
   records.push(row);s.active[id]={id,symbol:k,decision_at:row.decision_at,decision_quote_time:q.time,session_start:q.session_start,session_end:q.session_end};s.seen[key]=true;
  }
 }
 s.basket=basketStep(s.basket,market,quotes,time);
 if(s.last_bucket!==epoch(time)){s.rounds++;s.last_bucket=epoch(time);}
 s.last_check=stamp(time);s.last_fresh=Object.keys(quotes).length;s.last_expected=batch.expected_open?.length||0;s.status='collecting';
 s.message='Losse kansen en vaste controlewaarnemingen verzamelen gegevens; hoofdorders en trainingslabels blijven afzonderlijk.';
 return {revision:payload.revision,state:s,records,updates};
}

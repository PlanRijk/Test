import {DAILY_COMPANIES,DAILY_INDICES} from './daily-catalogue.js';
import {liveSeries,forwardHistory} from './history-forward.js';
import {historyFeatures,historyPredict,verifyHistory,stableOrder,utcDay} from './history-model.js';
import {HISTORY_IMPLEMENTATION_SHA} from './history-implementation.js';
import {BREADTH_IMPLEMENTATION_SHA} from './breadth-implementation.js';
export const BREADTH_POLICY={version:'breadth-study-v1',implementation_sha256:BREADTH_IMPLEMENTATION_SHA,reference_implementation:HISTORY_IMPLEMENTATION_SHA,
 max_new:150,max_active:5000,max_records:50000,detail_per_day:40,detail_records:3500,compact_days:365,detail_days:90,
 soft_bytes:24000000,max_bytes:32000000,max_database_bytes:150000000,max_month_bytes:1500000000,
 note:'Aanvullend verkennend onderzoek; geen uitbreiding van het vaste bevestigingsvak of echte orders.'};
const iso=t=>new Date(t).toISOString(),epoch=d=>d?Date.parse(d+'T00:00:00Z'):null,date=n=>n==null?null:utcDay(n),ms=t=>t?Date.parse(t):null;
const statusNames=['pending','following','complete','missing'],items=Object.fromEntries(DAILY_COMPANIES.map(x=>[x.symbol,x]));
export function encodeEntry(e){return !e?null:[ms(e.open_time),ms(e.known_at),epoch(e.day),e.close,e.fx,epoch(e.fx_date),e.price_eur,e.qty,e.gross_eur,e.commission_eur,e.buy_costs_eur,e.budget_eur];}
export function decodeEntry(a){return !a?null:{open_time:iso(a[0]),known_at:iso(a[1]),day:date(a[2]),close:a[3],fx:a[4],fx_date:date(a[5]),price_eur:a[6],qty:a[7],gross_eur:a[8],commission_eur:a[9],buy_costs_eur:a[10],budget_eur:a[11]};}
export function encodeOutcome(o){return !o?null:o.status!=='observed'?[2]:[1,epoch(o.day),ms(o.known_at),o.close,o.fx,epoch(o.fx_date),o.net_eur,o.stressed_net_eur,o.gross_move_percent,o.exit_costs_eur];}
export function decodeOutcome(a,reason){return !a?null:a[0]===2?{status:'missing',reason}:{status:'observed',day:date(a[1]),known_at:iso(a[2]),close:a[3],fx:a[4],fx_date:date(a[5]),net_eur:a[6],stressed_net_eur:a[7],gross_move_percent:a[8],exit_costs_eur:a[9]};}
// Read codec: symbol, decision day/time, known day, probability, features,
// status, entry, outcome, reason. Model/profile are stored once in the lease.
export function decodeCase(a,model){return {id:a[0]+'|'+a[1],model_id:model,symbol:a[0],decision_day:a[1],decision_at:iso(a[2]),known_day:a[3],probability:a[4],features:a[5],status:statusNames[a[6]],entry:decodeEntry(a[7]),outcome:decodeOutcome(a[8],a[9]),reason:a[9]};}
export function decodeBars(rows){return (rows||[]).map(a=>({symbol:a[0],day:a[1],close:a[3],record:{day:a[1],open_time:iso(a[2]),close:a[3],volume:a[4],fx:a[5],fx_date:a[6],observed_at:iso(a[7]),session_starts:a[8]||[],actions:a[9]?[{type:'splits'}]:[]}}));}
function knownTime(b,symbol,input){return Math.max(ms(b.observed_at)||0,ms((input.tails||[]).find(s=>s.symbol===symbol)?.created_at)||0)||null;}
function indexWindow(series,symbol,day){const b=series[symbol]||[];let n=b.length-1;while(n>=0&&b[n].day>day)n--;return b.slice(Math.max(0,n-5),n+1);}
function evidence(c,series,input,time){
 const prices=series[c.item.symbol].slice(-21).map(b=>[ms(b.open_time),b.close,b.volume,knownTime(b,c.item.symbol,input)]),indices={};
 for(const index of DAILY_INDICES)indices[index.symbol]=indexWindow(series,index.symbol,c.last.day).map(b=>[ms(b.open_time),b.close,knownTime(b,index.symbol,input)]);
 return {codec:1,recorded_at:iso(time),prices,indices,
  snapshot_hashes:(input.tails||[]).filter(s=>s.symbol===c.item.symbol||DAILY_INDICES.some(x=>x.symbol===s.symbol)).map(s=>({symbol:s.symbol,hash:s.hash})),
  statement:'Vooraf gekozen op bedrijf/dag en sector, onafhankelijk van kans of latere winst. Voorspelling en bekende invoer bevroren; dezelfde hypothetische twintig-sessiemeting als het dagmodel.'};
}
export async function stepBreadth(input,{time=Date.now()}={}){
 if(input.reference_implementation!==HISTORY_IMPLEMENTATION_SHA||!await verifyHistory(input.artifact))throw Error('Frozen reference differs');
 const model=input.artifact.id,today=utcDay(time),bars=decodeBars(input.bars),active=(input.active||[]).map(a=>decodeCase(a,model)),market={...input,bars,active,max_new_records:0};
 const followed=await forwardHistory(market,{time}),updates=followed.updates.map(r=>{const [symbol,day]=r.id.split('|');return [symbol,day,statusNames.indexOf(r.status),encodeEntry(r.entry),encodeOutcome(r.outcome),r.reason];});
 const series=liveSeries(market),candidates=[],excluded={},reference=new Set(input.reference_symbols||[]),seen=new Set(input.seen||[]);
 const reject=reason=>excluded[reason]=(excluded[reason]||0)+1;
 for(const item of DAILY_COMPANIES){
  const b=series[item.symbol],last=b?.at(-1);
  if(!input.artifact.symbols.includes(item.symbol)){reject('outside_frozen_model');continue;}
  if(!last||!last.fx||last.day>=today||Date.parse(today)-Date.parse(last.day)>4*86400000){reject('missing_price_or_fx');continue;}
  if((input.revised_symbols||[]).includes(item.symbol)){reject('revised_source');continue;}
  const windows=[...b.slice(-21).map(x=>[x,item.symbol]),...DAILY_INDICES.flatMap(i=>indexWindow(series,i.symbol,last.day).map(x=>[x,i.symbol]))];
  if(windows.some(([x,k])=>!Number.isFinite(knownTime(x,k,input))||knownTime(x,k,input)>time)){reject('unknown_or_future_source_time');continue;}
  const features=historyFeatures(b,b.length-1,series),prediction=features&&historyPredict(input.artifact,features);
  if(!prediction||prediction.outliers>2){reject('missing_features_or_outlier');continue;}
  candidates.push({item,last,features,probability:prediction.probability,order:stableOrder(BREADTH_POLICY.version+'|'+model+'|'+today+'|'+item.symbol)});
 }
 candidates.sort((a,b)=>a.order-b.order||a.item.symbol.localeCompare(b.item.symbol));
 const eligible=candidates.length,extra=candidates.filter(c=>!reference.has(c.item.symbol)&&!seen.has(c.item.symbol));
 const room=[0,6].includes(new Date(time).getUTCDay())?0:Math.max(0,Math.min(input.max_new??0,BREADTH_POLICY.max_new,BREADTH_POLICY.max_active-active.length));
 const chosen=extra.slice(0,room),detailed=[],sectors=new Set(),traceLimit=Math.max(0,Math.min(input.max_details??0,BREADTH_POLICY.detail_per_day));
 for(const c of chosen)if(!sectors.has(c.item.sector)){detailed.push(c);sectors.add(c.item.sector);}
 for(const c of chosen)if(!detailed.includes(c))detailed.push(c);
 const traces=detailed.slice(0,traceLimit).map(c=>({symbol:c.item.symbol,day:today,record:evidence(c,series,input,time)}));
 const records=chosen.map(c=>[c.item.symbol,today,time,c.last.day,c.probability,c.features,c.item.sector,c.item.exchange]);
 return {protocol:BREADTH_POLICY.version,model_id:model,records,updates,traces,
  summary:{checked_at:iso(time),catalogue:DAILY_COMPANIES.length,eligible,reference:reference.size,new_compact:records.length,new_detailed:traces.length,
   eligible_additional:extra.length,not_admitted:Math.max(0,extra.length-records.length),excluded,
   note:'Compacte en uitgebreide dossiers volgen dezelfde hypothetische uitkomst. Uitgebreide dossiers zijn een subset. De vaste referentiegroep wordt niet dubbel geteld.'}};
}

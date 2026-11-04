import {HISTORY_PROTOCOL as P} from './history-data.js';
import {DAILY_COMPANIES,DAILY_INDICES} from './daily-catalogue.js';
import {dailyEntry,dailyOutcome} from './daily-study.js';
import {historySeries,historyFeatures,historyPredict,verifyHistory,stableOrder,utcDay,historyScore} from './history-model.js';
import {sha} from './learner.js';
const stamp=t=>new Date(t).toISOString(),items=Object.fromEntries(DAILY_COMPANIES.map(x=>[x.symbol,x]));
export function liveSeries(input){
 const series={};for(const s of input.tails||[])if(s.status==='available')series[s.symbol]=historySeries(s.data);
 for(const b of input.bars||[]){const list=series[b.symbol]||[],at=list.findIndex(x=>x.day===b.day),row={...b.record,day:b.day,close:b.close};
  if(at>=0){if(row.volume==null&&Math.abs(row.close/list[at].close-1)<.00001)row.volume=list[at].volume;list[at]=row;}else list.push(row);series[b.symbol]=list;}
 for(const k of Object.keys(series))series[k].sort((a,b)=>a.day.localeCompare(b.day));return series;
}
export async function forwardHistory(input,{time=Date.now()}={}){
 const artifact=input.artifact;if(!await verifyHistory(artifact))throw Error('Invalid historical artifact');
 const series=liveSeries(input),updates=[],records=[],today=utcDay(time),active=input.active||[];
 for(const r of active){const b=series[r.symbol]||[],last=b.at(-1),item=items[r.symbol],patch={id:r.id};let entry=r.entry,outcome=r.outcome,status=r.status,reason=r.reason;
  const revised=(input.revised_symbols||[]).includes(r.symbol);
  if(revised){status='missing';reason='Herziene bronprijs of corporate action vereist herbeoordeling.';}
  else if(!entry&&last&&last.day>r.known_day&&Date.parse(last.open_time)>Date.parse(r.decision_at)){
   const next=(last.session_starts||[]).find(t=>t*1000>Date.parse(r.decision_at));
   if(!next||utcDay(next*1000)!==last.day||!last.fx){status='missing';reason='Eerste toekomstige instap gemist of FX ontbreekt.';}
   else{entry={...dailyEntry(input.config,item,last),known_at:last.observed_at};status='following';}
  }
  if(entry&&status!=='missing'&&last){
   const calendar=last.session_starts||[],at=calendar.findIndex(t=>utcDay(t*1000)===entry.day),span=b.filter(x=>x.day>=entry.day),target=calendar[at+20];
   if(at<0||span.some((x,i,a)=>i&&Math.abs(x.close/a[i-1].close-1)>.3)||span.some(x=>(x.actions||[]).some(a=>a.type==='splits'))){status='missing';reason='Splitsing, koerssprong of instapbron ontbreekt.';}
   else if(target){
    if(utcDay(target*1000)!==last.day||!last.fx){status='missing';reason='Doelsessie niet op tijd geobserveerd of FX ontbreekt.';}
    else{outcome={...dailyOutcome(input.config,item,entry,last),known_at:last.observed_at};status='complete';}
   }
  }
  if(time-Date.parse(r.decision_at)>55*86400000&&status!=='complete'){status='missing';reason='Meettermijn verlopen zonder geldige toekomstige uitkomst.';}
  if(status==='missing'&&!outcome)outcome={status:'missing',reason};
  if(JSON.stringify({entry,outcome,status,reason})!==JSON.stringify({entry:r.entry,outcome:r.outcome,status:r.status,reason:r.reason}))updates.push({...patch,entry,outcome,status,reason:reason||null});
 }
 const candidates=[];
 for(const item of DAILY_COMPANIES){const b=series[item.symbol],last=b?.at(-1);
  if(!last||!last.fx||Date.parse(today)-Date.parse(last.day)>4*86400000||!artifact.symbols.includes(item.symbol)||(input.revised_symbols||[]).includes(item.symbol))continue;
  const features=historyFeatures(b,b.length-1,series),prediction=features&&historyPredict(artifact,features);
  if(!prediction||prediction.outliers>2)continue;
  candidates.push({item,last,features,prediction,order:stableOrder(artifact.id+'|'+today+'|'+item.symbol)});
 }
 candidates.sort((a,b)=>a.order-b.order||a.item.symbol.localeCompare(b.item.symbol));const chosen=[],sectors=new Set();
 for(const c of candidates)if(!sectors.has(c.item.sector)){chosen.push(c);sectors.add(c.item.sector);}
 for(const c of candidates)if(!chosen.includes(c))chosen.push(c);
 const room=[0,6].includes(new Date(time).getUTCDay())?0:Math.max(0,Math.min(input.max_new_records??0,P.forward_per_day,P.max_forward_active-active.length));
 for(const c of chosen.slice(0,room)){
  const id='hf-'+(await sha(artifact.id+'|'+today+'|'+c.item.symbol)).slice(0,24),context=(input.context||[]).filter(x=>x.status==='available'&&Date.parse(x.known_at)<=time);
  records.push({id,model_id:artifact.id,symbol:c.item.symbol,venue:c.item.exchange,sector:c.item.sector,decision_at:stamp(time),decision_day:today,known_day:c.last.day,
   features:c.features,probability:c.prediction.probability,selected:c.prediction.probability>=artifact.threshold,status:'pending',entry:null,outcome:null,reason:null,
   context,origin:'prospective_hypothetical',note:'Bevroren dagmodel versus dezelfde toekomstige controlewaarnemingen; geen orders of voorspelde zekere winst.'});
 }
 return {records,updates,eligible_candidates:candidates.length,protocol:P.version,checked_at:stamp(time)};
}
export function forwardReport(artifact,records,time=Date.now()){
 const before=records.filter(r=>r.model_id===artifact.id&&Date.parse(r.decision_at)>Date.parse(artifact.created_at)&&Date.parse(r.decision_at)<time);
 const byDay=new Map();for(const r of before){const group=byDay.get(r.decision_day)||[];group.push(r);byDay.set(r.decision_day,group);}
 const window=[...byDay.entries()].sort(([a],[b])=>a.localeCompare(b)).slice(0,60),first=window.filter(([,rows])=>rows.every(r=>['complete','missing'].includes(r.status))),all=first.flatMap(([,r])=>r),observed=all.filter(r=>r.status==='complete'&&r.outcome?.status==='observed'),blocked=[];
 if(first.length<60)blocked.push('Zestig nieuwe volledig afgeronde besluitdagen nodig.');
 if(observed.length<300||new Set(observed.map(r=>r.symbol)).size<10||new Set(observed.map(r=>r.sector)).size<5)blocked.push('Minstens 300 uitkomsten over tien bedrijven en vijf sectoren nodig.');
 if(!all.length||observed.length/all.length<.9)blocked.push('Minstens negentig procent toekomstige uitkomstdekking nodig.');
 const rows=observed.map(r=>({date:r.decision_day,features:r.features,net:r.outcome.net_eur,stress:r.outcome.stressed_net_eur,y:r.outcome.net_eur>0?1:0})),metrics=historyScore(artifact,rows,{unit:'day'});
 if(!artifact.offline_pass)blocked.push('Historische onafhankelijke toetsen niet geslaagd.');
 if(metrics.brier>=metrics.prior_brier||metrics.logloss>metrics.prior_logloss||metrics.selected<100||!(metrics.selected_mean_stress>0&&metrics.lower_short>0&&metrics.lower_long>0))blocked.push('Nieuwe gegevens tonen onvoldoende gekalibreerd netto voordeel na kosten.');
 return {status:first.length>=60?'final':'collecting_forward',days:first.length,observed:observed.length,missing:all.length-observed.length,metrics,blocked,
  research_supported:blocked.length===0,automatic_trading_approval:false,note:'Een vaste, eenmalige beoordeling van de eerste zestig afgeronde besluitdagen; geen toelating tot de hoofdportefeuille.'};
}

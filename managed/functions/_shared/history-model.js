import {HISTORY_PROTOCOL as P,HISTORY_ITEMS} from './history-data.js';
import {DAILY_COMPANIES,DAILY_INDICES} from './daily-catalogue.js';
import {dailyEntry,dailyOutcome,companyWeek} from './daily-study.js';
import {sha} from './learner.js';
import {blockBounds} from './reliability.js';
const clamp=(x,a,b)=>Math.max(a,Math.min(b,x)),avg=a=>a.reduce((s,x)=>s+x,0)/(a.length||1),iso=t=>new Date(t).toISOString();
export const utcDay=t=>iso(t).slice(0,10);
export function stableOrder(text){let hash=2166136261;for(let i=0;i<text.length;i++)hash=Math.imul(hash^text.charCodeAt(i),16777619)>>>0;return hash;}
export function historySeries(snapshot){return snapshot.timestamps.map((t,i)=>({day:utcDay(t*1000),open_time:iso(t*1000),close:snapshot.closes[i],volume:snapshot.volumes?.[i]??null})).filter(b=>snapshot.symbol?.startsWith('^')||Number.isFinite(b.volume)&&b.volume>0);}
export function rateMap(base){return new Map(base.fx.rows.map(r=>[r[0],Object.fromEntries(base.fx.columns.map((k,i)=>[k,r[i+1]]))]));}
export function datedRate(map,date,currency){
 if(currency==='EUR')return {fx:1,fx_date:date};
 for(let n=0;n<=4;n++){const d=utcDay(Date.parse(date+'T00:00:00Z')-n*86400000),v=map.get(d)?.[currency];if(Number.isFinite(v)&&v>0)return {fx:v,fx_date:d};}return {fx:null,fx_date:null};
}
export function historyFeatures(series,at,indices){
 if(at<20)return null;const w=series.slice(at-20,at+1),last=w.at(-1),p=last.close,returns=w.slice(1).map((b,i)=>b.close/w[i].close-1);
 if(returns.some(r=>!Number.isFinite(r)||Math.abs(r)>.3)||w.some((b,i)=>i&&Date.parse(b.day)-Date.parse(w[i-1].day)>7*86400000))return null;
 const mean=avg(returns),volumes=w.slice(0,-1).map(b=>b.volume).filter(v=>Number.isFinite(v)&&v>0);
 if(volumes.length<15||!Number.isFinite(last.volume)||last.volume<=0)return null;
 const x=[p/w.at(-2).close-1,p/w.at(-6).close-1,p/w[0].close-1,Math.sqrt(avg(returns.map(r=>(r-mean)**2))),Math.log(last.volume/avg(volumes))];
 for(const idx of DAILY_INDICES){const s=indices[idx.symbol];if(!s)return null;let lo=0,hi=s.length;while(lo<hi){const mid=(lo+hi)>>>1;if(s[mid].day<=last.day)lo=mid+1;else hi=mid;}const n=lo-1;
  if(n<5||Date.parse(last.day)-Date.parse(s[n].day)>4*86400000)return null;x.push(s[n].close/s[n-5].close-1);}
 return x.every(Number.isFinite)?x:null;
}
export function buildHistorical(input){
 const available=(input.snapshots||[]).filter(x=>x.status==='available'),base=available.find(x=>x.symbol==='__base__')?.data;
 if(!base)throw Error('Historical base missing');const rates=rateMap(base),series={},sources={};
 for(const s of available)if(s.data.timestamps){sources[s.symbol]=s;if(DAILY_INDICES.some(x=>x.symbol===s.symbol))series[s.symbol]=historySeries(s.data);}
 const candidates=[];let sourceCandidates=0;
 for(const item of DAILY_COMPANIES){const source=sources[item.symbol];if(!source)continue;const b=historySeries(source.data),company=[];let week='';
  for(let i=20;i+21<b.length;i++){const bucket=companyWeek(b[i].day);if(bucket===week)continue;week=bucket;sourceCandidates++;
   company.push({symbol:item.symbol,i,id:item.symbol+'|'+b[i].day,order:stableOrder(item.symbol+'|'+b[i].day)});}
  company.sort((a,b)=>a.order-b.order||a.id.localeCompare(b.id));candidates.push(...company.slice(0,P.max_company_samples));
 }
 candidates.sort((a,b)=>a.order-b.order||a.id.localeCompare(b.id));const selected=candidates.slice(0,P.max_samples).sort((a,b)=>a.symbol.localeCompare(b.symbol)||a.i-b.i),rows=[],excluded={};let cachedSymbol='',cachedSeries;
 const fail=r=>excluded[r]=(excluded[r]||0)+1;
 for(const candidate of selected){const item=DAILY_COMPANIES.find(x=>x.symbol===candidate.symbol),i=candidate.i,source=sources[item.symbol];
  if(cachedSymbol!==item.symbol){cachedSymbol=item.symbol;cachedSeries=historySeries(source.data);}const b=cachedSeries;
  // Per-share ADR reserves cannot be reconstructed from retrospectively
  // split-adjusted prices. Keep these unsupported cases in the denominator.
  if(['TSM','TM'].includes(item.symbol)){fail('adr_basis_unverified');continue;}
  if(source.data.actions.some(a=>a.type==='splits'&&a.day>=b[i-20].day&&a.day<=b[i+21].day)){fail('split_window');continue;}
  const features=historyFeatures(b,i,series);if(!features){fail('features_or_index_missing');continue;}
  const decision=Date.parse(b[i].day+'T00:00:00Z')+86400000+380*60000;
  if(Date.parse(b[i+1].open_time)<=decision){fail('entry_before_decision');continue;}
  const enter={...b[i+1],...datedRate(rates,b[i+1].day,item.currency)},exit={...b[i+21],...datedRate(rates,b[i+21].day,item.currency)};
  if(!enter.fx||!exit.fx){fail('missing_dated_fx');continue;}
  if(b.slice(i+1,i+22).some((v,j,a)=>j&&Math.abs(v.close/a[j-1].close-1)>.3)){fail('price_jump');continue;}
  const position=dailyEntry(input.config,item,enter),out=dailyOutcome(input.config,item,position,exit);
  const available=Date.parse(exit.day+'T00:00:00Z')+86400000+380*60000;
  if(!Number.isFinite(out.net_eur)||out.net_eur< -100||available>=Date.parse(input.cutoff+'T00:00:00Z')){fail('invalid_or_unavailable_label');continue;}
  rows.push({id:candidate.id,symbol:item.symbol,venue:item.exchange,sector:item.sector,date:utcDay(decision),decision,entry:Date.parse(enter.open_time),available,
   features,net:out.net_eur,stress:out.stressed_net_eur,y:out.net_eur>0?1:0,origin:'historically_simulated',dividend_cash_credit:0});
 }
 rows.sort((a,b)=>a.decision-b.decision||a.id.localeCompare(b.id));
 return {rows,source_candidates:sourceCandidates,sampled_candidates:selected.length,excluded,source_count:available.filter(x=>x.data.timestamps).length};
}
export function historySplit(rows){
 const dates=[...new Set(rows.map(r=>r.date))].sort(),a=dates[Math.floor(dates.length*.6)],b=dates[Math.floor(dates.length*.8)],boundary=d=>Date.parse(d+'T00:00:00Z');
 return {train:rows.filter(r=>r.date<a&&r.available<boundary(a)),validation:rows.filter(r=>r.date>=a&&r.date<b&&r.available<boundary(b)),test:rows.filter(r=>r.date>=b),
  windows:{validation_start:a,test_start:b},dates:dates.length};
}
function fit(rows){
 const n=P.features.length,mean=Array(n).fill(0),scale=Array(n).fill(0);for(const r of rows)r.features.forEach((v,i)=>mean[i]+=v/rows.length);
 for(const r of rows)r.features.forEach((v,i)=>scale[i]+=(v-mean[i])**2/rows.length);for(let i=0;i<n;i++)scale[i]=Math.max(1e-6,Math.sqrt(scale[i]));
 const normalized=rows.map(r=>({x:r.features.map((v,i)=>clamp((v-mean[i])/scale[i],-6,6)),y:r.y})),weights=Array(n).fill(0);let bias=0;
 for(let epoch=0;epoch<P.epochs;epoch++){const g=Array(n).fill(0);let gb=0;
  for(const r of normalized){const z=clamp(bias+r.x.reduce((s,v,i)=>s+v*weights[i],0),-30,30),error=1/(1+Math.exp(-z))-r.y;gb+=error;for(let i=0;i<n;i++)g[i]+=error*r.x[i];}
  bias=clamp(bias-P.step*gb/rows.length,-12,12);for(let i=0;i<n;i++)weights[i]=clamp(weights[i]-P.step*(g[i]/rows.length+P.l2*weights[i]),-12,12);
 }return {mean,scale,weights,bias};
}
export function historyPredict(a,x){
 if(!Array.isArray(x)||x.length!==P.features.length||x.some(v=>!Number.isFinite(v)))return null;
 const z=x.map((v,i)=>(v-a.mean[i])/a.scale[i]),score=clamp(a.bias+z.reduce((s,v,i)=>s+clamp(v,-6,6)*a.weights[i],0),-30,30);
 return {probability:1/(1+Math.exp(-score)),outliers:z.filter(v=>Math.abs(v)>3).length};
}
export async function verifyHistory(a){
 if(!a||a.protocol!==P.version||a.feature_names?.join('|')!==P.features.join('|')||a.threshold!==.6||!['mean','scale','weights'].every(k=>a[k]?.length===P.features.length&&a[k].every(Number.isFinite))||a.scale.some(v=>v<1e-6)||a.weights.some(v=>Math.abs(v)>12)||!Number.isFinite(a.bias)||Math.abs(a.bias)>12)return false;
 const {integrity_hash,...body}=a;return await sha(body)===integrity_hash;
}
export function historyScore(a,rows,{unit='week'}={}){
 const selected=[],weeks=new Map();let brier=0,priorBrier=0,loss=0,priorLoss=0;
 for(const r of rows){const p=clamp(historyPredict(a,r.features).probability,.001,.999),base=clamp(a.prior,.001,.999);brier+=(p-r.y)**2;priorBrier+=(base-r.y)**2;loss-=r.y*Math.log(p)+(1-r.y)*Math.log(1-p);priorLoss-=r.y*Math.log(base)+(1-r.y)*Math.log(1-base);
  const w=unit==='day'?r.date:companyWeek(r.date),g=weeks.get(w)||{all:[],chosen:[]};g.all.push(r.stress);if(p>=a.threshold){selected.push(r);g.chosen.push(r.stress);}weeks.set(w,g);}
 const paired=[...weeks.entries()].sort(([a],[b])=>a.localeCompare(b)).map(([,g])=>(g.chosen.length?avg(g.chosen):0)-avg(g.all));
 return {rows:rows.length,dates:new Set(rows.map(x=>x.date)).size,positive:rows.filter(r=>r.y).length,brier:brier/(rows.length||1),prior_brier:priorBrier/(rows.length||1),logloss:loss/(rows.length||1),prior_logloss:priorLoss/(rows.length||1),
  selected:selected.length,selected_mean_net:selected.length?avg(selected.map(x=>x.net)):null,selected_mean_stress:selected.length?avg(selected.map(x=>x.stress)):null,
  matched_mean:avg(paired),clusters:paired.length,block_unit:unit,block_lengths:unit==='day'?[20,40]:[5,10],lower_short:blockBounds(paired,unit==='day'?20:5)?.lower??null,lower_long:blockBounds(paired,unit==='day'?40:10)?.lower??null,
  note:'Selectiediagnose met weekblokken; geen eindige-kapitaalportefeuille of uitvoerbewijs.'};
}
export async function trainHistory(input,{time=Date.now()}={}){
 const prepared=input.prepared||buildHistorical(input),split=historySplit(prepared.rows),blocked=[];
 const seen=new Set(),cutoff=Date.parse(input.cutoff+'T00:00:00Z');
 for(const r of prepared.rows){const item=DAILY_COMPANIES.find(x=>x.symbol===r.symbol);
  if(seen.has(r.id)||!item||r.venue!==item.exchange||r.sector!==item.sector||r.origin!=='historically_simulated'||r.date!==utcDay(r.decision)
   ||!(r.decision<r.entry&&r.entry<r.available&&r.available<cutoff)||r.features.length!==P.features.length||r.features.some(x=>!Number.isFinite(x))
   ||!Number.isFinite(r.net)||!Number.isFinite(r.stress)||r.stress>r.net||r.y!==(r.net>0?1:0))throw Error('Invalid or noncausal historical example');seen.add(r.id);
 }
 if(prepared.rows.length<1500||split.dates<250||new Set(prepared.rows.map(r=>r.symbol)).size<40||new Set(prepared.rows.map(r=>r.sector)).size<8)blocked.push('Minstens 1.500 bruikbare voorbeelden, 250 besluitdatums, 40 bedrijven en acht sectoren nodig.');
 if(split.train.length<800||split.validation.length<150||split.test.length<150)blocked.push('Te weinig gescheiden trainings-, validatie- en testvoorbeelden.');
 for(const k of ['train','validation','test'])if(split[k].filter(r=>r.y).length<30||split[k].filter(r=>!r.y).length<30)blocked.push('Te weinig positieve of negatieve voorbeelden in '+k+'.');
 if(blocked.length)return {status:'waiting_history',blocked,counts:{samples:prepared.rows.length,candidates:prepared.sampled_candidates,excluded:prepared.excluded}};
 const dataset=prepared.rows.map(r=>[r.symbol,r.venue,r.sector,r.decision,r.entry,r.available,...r.features,r.net,r.stress]);
 const dataset_hash=await sha(dataset),body={id:'hm-'+dataset_hash.slice(0,24),protocol:P.version,feature_names:P.features,algorithm:'fixed-day-logit-v1',...fit(split.train),
  threshold:.6,prior:avg(split.train.map(r=>r.y)),created_at:iso(time),training_cutoff:input.cutoff,fingerprint:input.profile,dataset_hash,
  source_manifest:(input.snapshots||[]).map(s=>({symbol:s.symbol,status:s.status,hash:s.hash})).sort((a,b)=>a.symbol.localeCompare(b.symbol)),
  symbols:[...new Set(prepared.rows.map(r=>r.symbol))].sort(),windows:split.windows,limitations:P.limitations,
  counts:{samples:prepared.rows.length,dates:split.dates,candidates:prepared.sampled_candidates,source_candidates:prepared.source_candidates,sources:prepared.source_count,excluded:prepared.excluded,train:split.train.length,validation:split.validation.length,test:split.test.length}};
 body.metrics={validation:historyScore(body,split.validation),test:historyScore(body,split.test)};
 const v=body.metrics.validation,t=body.metrics.test,gates=[];
 if(v.brier>=v.prior_brier||t.brier>=t.prior_brier||t.logloss>t.prior_logloss)gates.push('Geen consistente verbetering van kalibratie ten opzichte van de trainingsprior.');
 if(t.selected<100||t.selected_mean_stress<=0||!(t.lower_short>0&&t.lower_long>0))gates.push('Onvoldoende onafhankelijk netto voordeel in het aparte historische toetsvak.');
 if(prepared.rows.length/prepared.sampled_candidates<.8)gates.push('Meer dan twintig procent van de vooraf gekozen voorbeelden ontbreekt.');
 body.offline_pass=gates.length===0;body.offline_blockers=gates;body.automatic_trading_approval=false;body.integrity_hash=await sha(body);
 return {status:'historical_model_frozen',artifact:body,dataset,counts:body.counts};
}

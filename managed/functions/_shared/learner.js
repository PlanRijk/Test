import {FEATURE_NAMES,FEATURE_SCHEMA} from './engine.js';
export const LEARNER_VERSION='net-logit-v1';
export const REQUIREMENTS={samples:100,days:20,train:50,validation:10,test:10,forward_days:20,forward_closes:30};
const finite=x=>typeof x==='number'&&Number.isFinite(x);
const clamp=(x,a,b)=>Math.max(a,Math.min(b,x));
export function canonical(value){
 if(Array.isArray(value))return '['+value.map(canonical).join(',')+']';
 if(value&&typeof value==='object')return '{'+Object.keys(value).sort().map(k=>JSON.stringify(k)+':'+canonical(value[k])).join(',')+'}';
 return JSON.stringify(value);
}
export async function sha(value){return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(typeof value==='string'?value:canonical(value))))].map(x=>x.toString(16).padStart(2,'0')).join('');}
export function featureVector(x){return Array.isArray(x)&&x.length===FEATURE_NAMES.length&&x.every(v=>finite(v)&&Math.abs(v)<1000000);}
export function validArtifact(a){
 return !!a&&a.algorithm===LEARNER_VERSION&&a.feature_schema===FEATURE_SCHEMA&&canonical(a.feature_names)===canonical(FEATURE_NAMES)&&
  ['weights','mean','scale'].every(k=>featureVector(a[k]))&&a.scale.every(x=>x>=1e-6)&&a.weights.every(x=>Math.abs(x)<=12)&&finite(a.bias)&&Math.abs(a.bias)<=12&&
  Array.isArray(a.venues)&&a.venues.every(x=>/^[A-Z]{4}$/.test(x))&&a.threshold===.6&&Number.isFinite(Date.parse(a.created_at))&&/^[a-f0-9]{64}$/.test(a.integrity_hash||'')&&canonical(a).length<=16000;
}
export async function verifyArtifact(a){if(!validArtifact(a))return false;const {integrity_hash,...body}=a;return await sha(body)===integrity_hash;}
export function predict(a,x){
 if(!validArtifact(a)||!featureVector(x))return null;
 const z=x.map((v,i)=>(v-a.mean[i])/a.scale[i]),outliers=z.filter(v=>Math.abs(v)>3).length;
 const logit=a.bias+z.reduce((sum,v,i)=>sum+clamp(v,-6,6)*a.weights[i],0);
 return {probability:1/(1+Math.exp(-clamp(logit,-30,30))),outliers};
}
export function prepareSamples(rows,cutoff,fingerprint){
 const seen=new Set(),valid=[];
 for(const r of rows){
  if(seen.has(r.id))throw Error('Duplicate training sample');seen.add(r.id);
  const decision=Date.parse(r.decision_time),entry=Date.parse(r.entry_time),available=Date.parse(r.available_at);
  if(typeof r.id!=='string'||!r.id||r.id.length>180||!(/^[A-Z]{4}$/).test(r.venue||'')||r.schema!==FEATURE_SCHEMA||r.fingerprint!==fingerprint||!featureVector(r.features)||!finite(r.net_eur)||![decision,entry,available].every(Number.isFinite)||decision>=entry||entry>=available||available>=cutoff)continue;
  if(new Date(decision).toISOString().slice(0,10)!==new Date(available).toISOString().slice(0,10))continue;
  valid.push({...r,date:r.available_at.slice(0,10),y:r.net_eur>0?1:0});
 }
 return valid.sort((a,b)=>a.available_at.localeCompare(b.available_at)||a.id.localeCompare(b.id));
}
export function chronologicalSplit(rows){
 const dates=[...new Set(rows.map(r=>r.date))].sort(),a=Math.floor(dates.length*.6),b=Math.floor(dates.length*.8);
 const trainDates=dates.slice(0,a),validationDates=dates.slice(a+1,b),testDates=dates.slice(b+1);
 return {dates,train:rows.filter(r=>trainDates.includes(r.date)),validation:rows.filter(r=>validationDates.includes(r.date)),test:rows.filter(r=>testDates.includes(r.date)),
  windows:{train:trainDates,validation:validationDates,test:testDates,embargo:[dates[a],dates[b]].filter(Boolean)}};
}
function fit(rows){
 const n=FEATURE_NAMES.length,mean=Array(n).fill(0),scale=Array(n).fill(0);
 for(const r of rows)r.features.forEach((x,i)=>mean[i]+=x/rows.length);
 for(const r of rows)r.features.forEach((x,i)=>scale[i]+=(x-mean[i])**2/rows.length);
 for(let i=0;i<n;i++)scale[i]=Math.max(1e-6,Math.sqrt(scale[i]));
 const data=rows.map(r=>({x:r.features.map((x,i)=>clamp((x-mean[i])/scale[i],-6,6)),y:r.y}));
 const weights=Array(n).fill(0);let bias=0;
 // Fixed, preregistered optimiser: no validation/test labels or parameter search.
 for(let epoch=0;epoch<160;epoch++){
  const gradient=Array(n).fill(0);let db=0;
  for(const r of data){const p=1/(1+Math.exp(-clamp(bias+r.x.reduce((s,x,i)=>s+x*weights[i],0),-30,30))),error=p-r.y;db+=error;
   for(let i=0;i<n;i++)gradient[i]+=error*r.x[i];}
  bias=clamp(bias-.08*db/data.length,-12,12);
  for(let i=0;i<n;i++)weights[i]=clamp(weights[i]-.08*(gradient[i]/data.length+.01*weights[i]),-12,12);
 }
 return {weights,bias,mean,scale};
}
function score(a,rows,prior){
 let brier=0,baseBrier=0,logloss=0,baseLogloss=0,net=0;const selected=[];
 for(const r of rows){const p=clamp(predict(a,r.features).probability,.001,.999);
  brier+=(p-r.y)**2;baseBrier+=(prior-r.y)**2;logloss-=r.y*Math.log(p)+(1-r.y)*Math.log(1-p);baseLogloss-=r.y*Math.log(prior)+(1-r.y)*Math.log(1-prior);
  if(p>=.6){selected.push(r);net+=r.net_eur;}}
 const n=rows.length||1;
 return {rows:rows.length,days:new Set(rows.map(x=>x.date)).size,brier:brier/n,prior_brier:baseBrier/n,logloss:logloss/n,prior_logloss:baseLogloss/n,
  selected: selected.length,selected_net_eur:net,selected_mean_net_eur:selected.length?net/selected.length:null,note:'Trade-level diagnostic; forward portfolio comparison is still required.'};
}
export async function trainCandidate(rows,{time=Date.now(),fingerprint,previousCutoff=null}={}){
 const cutoff=Date.parse(new Date(time).toISOString().slice(0,10)+'T00:00:00Z'),samples=prepareSamples(rows,cutoff,fingerprint),split=chronologicalSplit(samples);
 const blocked=[];
 if(samples.length<REQUIREMENTS.samples)blocked.push('Minstens 100 afgesloten referentietrades nodig.');
 if(split.dates.length<REQUIREMENTS.days)blocked.push('Minstens 20 afzonderlijke handelsdagen nodig.');
 if(split.train.length<REQUIREMENTS.train||split.validation.length<10||split.test.length<10)blocked.push('Te weinig afzonderlijke train-, validatie- of testvoorbeelden.');
 const positives=split.train.filter(r=>r.y).length;if(positives<10||split.train.length-positives<10)blocked.push('Trainingsvak vereist minstens tien positieve en tien negatieve voorbeelden.');
 if(previousCutoff){
  if(split.dates.filter(d=>d>previousCutoff).length<20||[...split.windows.validation,...split.windows.test].some(d=>d<=previousCutoff))blocked.push('Wacht op twintig nieuwe dagen en volledig nieuw validatie-/testvak; oude toetsvakken niet opnieuw gebruiken.');
 }
 if(blocked.length)return {status:'waiting_data',blocked,samples:samples.length,days:split.dates.length};
 const venues=[...new Set(split.train.map(r=>r.venue))].filter(v=>split.train.filter(r=>r.venue===v).length>=10&&split.validation.filter(r=>r.venue===v).length>=3&&split.test.filter(r=>r.venue===v).length>=3).sort();
 if(!venues.length)return {status:'waiting_data',blocked:['Te weinig aparte trainings-, validatie- en testvoorbeelden per beurs.'],samples:samples.length,days:split.dates.length};
 const fitted=fit(split.train),datasetHash=await sha(samples.map(r=>({id:r.id,features:r.features,y:r.y,net:r.net_eur,available:r.available_at})));
 const body={id:'lr-'+datasetHash.slice(0,24),algorithm:LEARNER_VERSION,feature_schema:FEATURE_SCHEMA,feature_names:FEATURE_NAMES,
  ...fitted,created_at:new Date(time).toISOString(),fingerprint,dataset_hash:datasetHash,training_cutoff:split.dates.at(-1),windows:split.windows,
  venues,threshold:.6,integrity_hash:'0'.repeat(64)};
 const prior=clamp(positives/split.train.length,.01,.99),validation=score(body,split.validation.filter(r=>venues.includes(r.venue)),prior),test=score(body,split.test.filter(r=>venues.includes(r.venue)),prior),gates=[];
 if(validation.rows<10||test.rows<10)gates.push('Onvoldoende afzonderlijke voorbeelden binnen de getoetste beursdekking.');
 if(validation.brier>validation.prior_brier-.005)gates.push('Validatie-Brier verbetert onvoldoende tegenover de vaste trainingsprior.');
 if(test.brier>=test.prior_brier||test.logloss>test.prior_logloss)gates.push('Apart testvak verbetert de kalibratiereferentie niet.');
 if(test.selected<10||test.selected_mean_net_eur<=0)gates.push('Onvoldoende netto positieve geselecteerde testvoorbeelden.');
 body.metrics={validation,test};body.offline_pass=gates.length===0;body.offline_blockers=gates;body.protocol='paper-learning-v1';
 delete body.integrity_hash;body.integrity_hash=await sha(body);
 return {status:'trained',artifact:body,samples:samples.length,days:split.dates.length};
}
export function forwardVerdict(artifact,days,closes){
 const eligible=days.filter(d=>d.complete&&d.model_id===artifact.id&&d.date>artifact.training_cutoff&&d.date>artifact.created_at.slice(0,10)&&
  ![0,6].includes(new Date(d.date+'T12:00:00Z').getUTCDay())&&finite(d.excess_eur)&&finite(d.matched_excess_eur)),seen=new Set();
 const complete=eligible.filter(d=>{if(seen.has(d.date))return false;seen.add(d.date);return true;});
 const blocked=[];if(complete.length!==eligible.length)blocked.push('Dubbele voorwaartse handelsdagen afgewezen.');
 if(!artifact.offline_pass)blocked.push(...(artifact.offline_blockers||['Offline toetsen niet geslaagd.']));
 if(complete.length<20)blocked.push('Minstens twintig volledig nieuwe, gepaarde schaduwhandelsdagen nodig.');
 if(closes<30)blocked.push('Minstens dertig afgesloten model-schaduwposities nodig.');
 const excess=complete.map(d=>d.excess_eur),matched=complete.map(d=>d.matched_excess_eur),sum=x=>x.reduce((a,b)=>a+b,0);
 let lower=null;
 if(complete.length>=20){
  // Deterministic day-block bootstrap, one-sided 99% lower bound; no iid trade test.
  let seed=1729;const random=()=>{seed=(1664525*seed+1013904223)>>>0;return seed/4294967296;},draws=[];
  for(let b=0;b<400;b++){let net=0;for(let i=0;i<complete.length;i++)net+=matched[Math.floor(random()*matched.length)];draws.push(net/complete.length);}
  draws.sort((a,b)=>a-b);lower=draws[Math.floor(draws.length*.01)];
  if(lower<=0||sum(excess)<=0)blocked.push('Geen positief gepaard netto voordeel met een positieve 99%-bootstrapondergrens na blootstellingscorrectie.');
 }
 if(complete.some(d=>d.model_drawdown_eur>d.reference_drawdown_eur+5))blocked.push('Model overschrijdt de toegestane extra schaduwdrawdown van EUR5.');
 return {eligible:blocked.length===0,blocked,forward_days:complete.length,last_date:complete.map(d=>d.date).sort().at(-1)||null,closed_positions:closes,net_excess_eur:sum(excess),matched_excess_eur:sum(matched),lower99_mean_eur:lower,
  note:'Preregistered engineering gate; no guarantee of future profitability or protection against every research-selection bias.'};
}

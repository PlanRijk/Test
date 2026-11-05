import {CANDIDATE_IMPLEMENTATION_SHA} from './candidate-implementation.js';
import {sha} from './learner.js';
import {blockBounds} from './reliability.js';
export const CANDIDATE_POLICY={version:'candidate-comparison-v1',variants:[{id:'shrinkage',name:'Sterkere regularisatie',l2:.1,mask:[0,1,2,3,4,5,6,7]},{id:'context',name:'Marktcontext en volatiliteit',l2:.01,mask:[3,5,6,7]}],epochs:100,step:.08,threshold:.6,primary_days:60,min_outcomes:300,min_selected:100,min_coverage:.9,max_daily:150,max_records:25000,max_active:4000,retention_days:90,max_bytes:24000000,max_database_bytes:120000000,max_month_bytes:1200000000,automatic_trading_approval:false};
const clamp=(v,a,b)=>Math.max(a,Math.min(b,v)),mean=a=>a.length?a.reduce((s,v)=>s+v,0)/a.length:null,day=t=>new Date(t).toISOString().slice(0,10),finite=x=>typeof x==='number'&&Number.isFinite(x);
export function candidatePredict(a,x){if(!Array.isArray(x)||x.length!==8||x.some(v=>!finite(v)))return null;const z=x.map((v,i)=>(v-a.mean[i])/a.scale[i]);return 1/(1+Math.exp(-clamp(a.bias+z.reduce((s,v,i)=>s+clamp(v,-6,6)*a.weights[i],0),-30,30)));}
export async function verifyCandidate(a){
 const variant=CANDIDATE_POLICY.variants.find(v=>v.id===a?.variant);if(!variant||a.protocol!==CANDIDATE_POLICY.version||a.threshold!==.6||a.l2!==variant.l2||JSON.stringify(a.mask)!==JSON.stringify(variant.mask)||a.automatic_trading_approval!==false||!['mean','scale','weights'].every(k=>a[k]?.length===8&&a[k].every(finite))||a.scale.some(v=>v<1e-6)||a.weights.some((v,i)=>Math.abs(v)>12||!variant.mask.includes(i)&&v!==0)||!finite(a.bias)||Math.abs(a.bias)>12)return false;
 const {integrity_hash,...body}=a;return await sha(body)===integrity_hash;
}
export async function trainCandidates(input,{time=Date.now()}={}){
 const rows=input.training||[],cutoff=Date.parse(input.training_boundary+'T00:00:00Z'),seen=new Set();
 for(const r of rows){const key=r[0]+'|'+r[3];if(r.length!==16||seen.has(key)||!r.slice(3).every(finite)||!(r[3]<r[4]&&r[4]<r[5]&&r[5]<cutoff)||day(r[3])>=input.training_boundary||r[15]>r[14])throw Error('Invalid or leaking candidate training row');seen.add(key);}
 if(rows.length<800||rows.filter(r=>r[14]>0).length<30||rows.filter(r=>r[14]<=0).length<30)throw Error('Insufficient candidate training data');
 const data=rows.map(r=>({x:r.slice(6,14),y:r[14]>0?1:0})),mu=Array(8).fill(0),scale=Array(8).fill(0);
 for(const r of data)r.x.forEach((x,i)=>mu[i]+=x/data.length);for(const r of data)r.x.forEach((x,i)=>scale[i]+=(x-mu[i])**2/data.length);for(let i=0;i<8;i++)scale[i]=Math.max(1e-6,Math.sqrt(scale[i]));
 const norm=data.map(r=>({x:r.x.map((x,i)=>clamp((x-mu[i])/scale[i],-6,6)),y:r.y})),models=[];
 for(const variant of CANDIDATE_POLICY.variants){const weights=Array(8).fill(0);let bias=0;
  for(let epoch=0;epoch<CANDIDATE_POLICY.epochs;epoch++){const gradient=Array(8).fill(0);let gb=0;for(const r of norm){const p=1/(1+Math.exp(-clamp(bias+r.x.reduce((s,x,i)=>s+x*weights[i],0),-30,30))),error=p-r.y;gb+=error;for(const i of variant.mask)gradient[i]+=error*r.x[i];}
   bias=clamp(bias-.08*gb/norm.length,-12,12);for(const i of variant.mask)weights[i]=clamp(weights[i]-.08*(gradient[i]/norm.length+variant.l2*weights[i]),-12,12);
  }
  const body={id:'cm-'+(await sha([input.reference_id,input.training_hash,variant,CANDIDATE_POLICY.version])).slice(0,24),protocol:CANDIDATE_POLICY.version,variant:variant.id,name:variant.name,l2:variant.l2,mask:variant.mask,threshold:.6,mean:mu,scale,weights,bias,
   source_model:input.reference_id,source_hash:input.reference_hash,training_hash:input.training_hash,training_boundary:input.training_boundary,training_rows:rows.length,prior:mean(data.map(r=>r.y)),created_at:new Date(time).toISOString(),automatic_trading_approval:false};
  models.push({...body,integrity_hash:await sha(body)});
 }return models;
}
export async function candidateBatch(input,{time=Date.now()}={}){
 const models=input.models||[];if(models.length!==2||!await Promise.all(models.map(verifyCandidate)).then(x=>x.every(Boolean)))throw Error('Candidate artifacts differ');
 const today=day(time),admit=new Date(time).getUTCHours()<7&&![0,6].includes(new Date(time).getUTCDay())&&models.every(m=>m.created_at.slice(0,10)<today);
 const records=[];if(admit)for(const r of (input.sources||[]).slice(0,input.max_new||0)){
  if(r.day!==today||r.status!==0||Date.parse(r.decision_at)>time||Date.parse(r.known_day+'T00:00:00Z')>=Date.parse(today+'T00:00:00Z'))continue;
  const probabilities=models.map(a=>candidatePredict(a,r.features));if(probabilities.some(x=>x==null))continue;
  records.push({source:r.source,symbol:r.symbol,day:r.day,feature_hash:r.feature_hash,probabilities});
 }return {records,report:candidateReport(models,input.cases||[],{time}),protocol:CANDIDATE_POLICY.version};
}
export function candidateReport(models,cases,{time=Date.now()}={}){
 const primary=cases.filter(r=>r.primary),dates=[...new Set(primary.map(r=>r.day))].sort().slice(0,60),rows=primary.filter(r=>dates.includes(r.day)),closed=rows.filter(r=>r.status===2&&finite(r.net)&&finite(r.stress)),settled=dates.filter(d=>rows.filter(r=>r.day===d).every(r=>r.status>=2)),mature=dates.length===60&&settled.length===60,coverage=rows.length?closed.length/rows.length:null;
 const comparisons=models.map((a,i)=>{const groups=new Map(),selected=closed.filter(r=>r.probabilities[i]>=.6),brier=mean(closed.map(r=>(r.probabilities[i]-(r.net>0?1:0))**2)),reference=mean(closed.map(r=>(r.reference_probability-(r.net>0?1:0))**2));
  for(const r of closed){const g=groups.get(r.day)||[];g.push(r);groups.set(r.day,g);}
  const pairedNet=[],pairedBrier=[];for(const date of dates){const g=groups.get(date)||[],chosen=g.filter(r=>r.probabilities[i]>=.6),base=g.filter(r=>r.reference_probability>=.6);if(!g.length)continue;
   pairedNet.push((chosen.length?mean(chosen.map(r=>r.stress)):0)-(base.length?mean(base.map(r=>r.stress)):0));pairedBrier.push(mean(g.map(r=>(r.reference_probability-(r.net>0?1:0))**2-(r.probabilities[i]-(r.net>0?1:0))**2)));
  }
  const blockers=[];if(!mature)blockers.push('Eerste zestig besluitdagen moeten volledig afgerond zijn.');if(closed.length<300)blockers.push('Minstens 300 gedeelde toekomstige uitkomsten nodig.');if(!(coverage>=.9))blockers.push('Minstens 90% uitkomstdekking nodig.');if(new Set(closed.map(r=>r.symbol)).size<10||new Set(closed.map(r=>r.sector)).size<5)blockers.push('Minstens tien bedrijven en vijf sectoren nodig.');
  if(rows.some(r=>r.status===3))blockers.push('Ontbrekende gedeelde uitkomsten vereisen afzonderlijke beoordeling.');
  if(closed.filter(r=>r.net>0).length<30||closed.filter(r=>r.net<=0).length<30)blockers.push('Minstens dertig positieve en dertig niet-positieve toekomstige uitkomsten nodig.');
  if(selected.length<100)blockers.push('Minstens honderd geselecteerde toekomstige gevallen nodig.');
  // One final look only; 2 candidates x 2 metrics x 2 block lengths.
  const bounds=mature?{net:[20,40].map(b=>blockBounds(pairedNet,b,.01/8)),brier:[20,40].map(b=>blockBounds(pairedBrier,b,.01/8))}:null;
  if(mature&&(!(mean(selected.map(r=>r.stress))>0)||!bounds.net.every(b=>b?.lower>0)||!bounds.brier.every(b=>b?.lower>0)))blockers.push('Geen overtuigend gezamenlijk kans- en nettovoordeel na kosten, overlap en meervoudig toetsen.');
  return {id:a.id,name:a.name,brier,reference_brier:reference,selected:selected.length,selected_mean_net:mean(selected.map(r=>r.net)),selected_mean_stress:mean(selected.map(r=>r.stress)),mean_paired_stress_difference:mean(pairedNet),bounds,blockers,research_supported:mature&&blockers.length===0};
 });
 return {version:CANDIDATE_POLICY.version,checked_at:new Date(time).toISOString(),status:mature?'final':'collecting',decision_days:dates.length,settled_days:settled.length,observed:closed.length,missing:rows.filter(r=>r.status===3).length,coverage,comparisons,automatic_trading_approval:false,note:'Gedeelde hypothetische EUR100-uitkomsten; geen eindige-kapitaalportefeuille. Dagelijkse tussenstanden zijn beschrijvend; alleen de eerste zestig afgeronde besluitdagen krijgen een vaste eindtoets. Geen automatische modelpromotie.'};
}
export async function runCandidates(rpc){let input;try{
 input=await rpc('paper_candidates_claim');if(!input)return {status:'waiting_or_budget'};if(input.policy?.implementation_sha256!==CANDIDATE_IMPLEMENTATION_SHA)throw Error('Candidate implementation differs');
 let output;if(input.stage==='train'){const models=await trainCandidates(input);output={models,report:candidateReport(models,[])};}else output=await candidateBatch(input);
 const saved=await rpc('paper_candidates_commit',{p_token:input.token,p_output:output});return {status:saved?(input.stage==='train'?'trained':'observing'):'superseded',models:output.models?.length,forecasts:output.records?.length};
 }catch{if(input?.token)try{await rpc('paper_candidates_fail',{p_token:input.token});}catch{}return {status:'error',automatic_trading_approval:false};}}

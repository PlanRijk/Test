import {constantEqual,env,reply,requestBody,rpc} from '../_shared/platform.js';
import {historyBase,historyBatch,publicContext,optionalChecks,connections} from '../_shared/history-data.js';
import {trainHistory,buildHistorical} from '../_shared/history-model.js';
import {forwardHistory,forwardReport} from '../_shared/history-forward.js';
import {HISTORY_IMPLEMENTATION_SHA} from '../_shared/history-implementation.js';
export async function handler(request){
 const secret=env('PAPERLAB_CRON_TOKEN');if(!secret||!constantEqual(request.headers.get('X-PaperLab-Cron')||'',secret))return reply({error:'Niet toegestaan.'},401);
 if(request.method!=='POST')return reply({error:'POST vereist.'},405);
 let input;
 try{
  await requestBody(request);input=await rpc('paper_history_claim');if(!input)return reply({status:'paused_budget_busy_or_daily_limit'});
  if(input.protocol?.implementation_sha256!==HISTORY_IMPLEMENTATION_SHA)throw Error('Frozen historical implementation differs');
  let output;
  if(input.stage==='base')output={snapshots:[await historyBase(input.cutoff)]};
  else if(input.stage==='collect')output={snapshots:await historyBatch(input.symbols,input.cutoff)};
  else if(input.stage==='derive'){
   const derived=buildHistorical(input),stocks=input.snapshots.filter(s=>s.status==='available'&&s.symbol!=='__base__'&&!s.symbol.startsWith('^'));
   output={derived:stocks.map((s,i)=>({symbol:s.symbol,examples:derived.rows.filter(r=>r.symbol===s.symbol),counts:i===0?{source_candidates:derived.source_candidates,sampled_candidates:derived.sampled_candidates,excluded:derived.excluded}:null}))};
  }
  else if(input.stage==='train'){
   const rows=(input.snapshots||[]).flatMap(s=>s.examples||[]),excluded={};let source_candidates=0,sampled_candidates=0;
   for(const s of input.snapshots||[]){source_candidates+=s.counts?.source_candidates||0;sampled_candidates+=s.counts?.sampled_candidates||0;for(const [k,v]of Object.entries(s.counts?.excluded||{}))excluded[k]=(excluded[k]||0)+v;}
   rows.sort((a,b)=>a.decision-b.decision||a.id.localeCompare(b.id));
   output=await trainHistory({...input,prepared:{rows,excluded,source_candidates,sampled_candidates,source_count:input.snapshots.filter(s=>s.status==='available'&&s.symbol!=='__base__').length}});
  }
  else if(input.stage==='forward'){
   const targets=input.us_symbols||[],index=Math.floor(Date.now()/86400000)%Math.max(1,targets.length),symbols=[targets[index],targets[(index+1)%targets.length]].filter(Boolean);
   const context=await publicContext(input.base,symbols),checks=await optionalChecks();
   output=await forwardHistory({...input,context:[...context,...checks]});output.context=context;output.checks=checks;output.connections=connections();
   const updated=new Map((input.reports||[]).map(r=>[r.id,r]));for(const r of output.updates)updated.set(r.id,{...updated.get(r.id),...r});
   output.report=forwardReport(input.artifact,[...updated.values(),...output.records]);
  }else throw Error('Unknown history stage');
  output.stage=input.stage;output.connections=connections();
  const saved=await rpc('paper_history_commit',{p_token:input.token,p_output:output});
  return reply({status:saved?(output.status||'stored'):'superseded',stage:input.stage,sources:output.snapshots?.length,counts:output.counts,
   new_forecasts:saved?output.records?.length:0,real_trading:false});
 }catch{if(input?.token)try{await rpc('paper_history_fail',{p_token:input.token});}catch{}return reply({error:'Gecombineerd onderzoek niet voltooid; geen nieuwe handelsgoedkeuring.'},503);}
}
if(globalThis.Deno?.serve)Deno.serve(handler);

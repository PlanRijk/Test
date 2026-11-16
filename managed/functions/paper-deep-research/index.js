import {constantEqual,env,reply,rpc}from'../_shared/platform.js';
import {discoverDeep,processDeepModel,deepFailure}from'../_shared/deep-research.js';
export async function handler(request){const cron=env('PAPERLAB_CRON_TOKEN');if(!cron||!constantEqual(request.headers.get('X-PaperLab-Cron')||'',cron))return reply({error:'Niet toegestaan.'},401);if(request.method!=='POST')return reply({error:'POST vereist.'},405);
 try{const claim=await rpc('paper_deep_claim');if(!claim)return reply({status:'waiting_for_work_or_free_capacity'});let result,calls=0;
  try{if(claim.job.stage==='discover'){result=await discoverDeep(claim.input,{cron,pdfURL:env('PAPERLAB_PDF_URL'),reserveTransfer:bytes=>rpc('paper_deep_reserve_transfer',{p_token:claim.token,p_bytes:bytes}),ingest:(rows,gaps)=>rpc('paper_deep_ingest',{p_token:claim.token,p_rows:rows,p_gaps:gaps})});await rpc('paper_deep_ingest',{p_token:claim.token,p_rows:[],p_gaps:result.discovery_gaps});}else{const key=env('GEMINI_API_KEY');if(!key)throw Error('missing_key');result=await processDeepModel(claim.job,claim.input,key,{onModelCall:()=>calls++});}}catch(error){result=deepFailure(error,calls);}
  result.attempted_calls=calls;const saved=await rpc('paper_deep_commit',{p_token:claim.token,p_result:result});return reply({status:saved?result.status:'superseded',symbol:claim.job.symbol,stage:claim.job.stage,model:claim.job.model,trade_changes:false});
 }catch{return reply({status:'deep_research_not_confirmed',trade_changes:false},503);}}
if(globalThis.Deno?.serve)Deno.serve(handler);

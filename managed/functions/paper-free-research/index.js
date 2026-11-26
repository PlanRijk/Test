import{constantEqual,env,reply,rpc}from'../_shared/platform.js';
import{replayCached}from'../_shared/research-replay.js';
export async function handler(request){const token=env('PAPERLAB_CRON_TOKEN');if(!token||!constantEqual(token,request.headers.get('X-PaperLab-Cron')||''))return reply({error:'Niet toegestaan.'},401);if(request.method!=='POST')return reply({error:'POST vereist.'},405);
 try{const c=await rpc('paper_free_research_claim');if(!c)return reply({status:'waiting_cached_work_or_budget',paid_services:false});const result=replayCached(c.input);const saved=await rpc('paper_free_research_commit',{p_token:c.token,p_result:result});return reply({status:saved?result.status:'superseded',symbol:c.input.symbol,model_calls:0,external_downloads:0,trade_changes:false});}catch{return reply({status:'free_research_not_confirmed'},503);}}
if(globalThis.Deno?.serve)Deno.serve(handler);

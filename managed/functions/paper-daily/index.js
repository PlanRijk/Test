import {constantEqual,env,reply,requestBody,rpc} from '../_shared/platform.js';
import {collectDaily,stepDaily} from '../_shared/daily-study.js';
export async function handler(request){
 const secret=env('PAPERLAB_CRON_TOKEN');if(!secret||!constantEqual(request.headers.get('X-PaperLab-Cron')||'',secret))return reply({error:'Niet toegestaan.'},401);
 if(request.method!=='POST')return reply({error:'POST vereist.'},405);
 let input;
 try{
  await requestBody(request);input=await rpc('paper_daily_claim');if(!input)return reply({status:'paused_budget_busy_or_daily_limit'});
  const batch=await collectDaily(),output=await stepDaily(input,batch),saved=await rpc('paper_daily_commit',{p_token:input.token,p_output:output});
  return reply({status:saved?'observed':'superseded',usable_companies:output.quality.filter(q=>q.status==='usable').length,new_observations:saved?output.records.length:0,source_requests:batch.requests,orders:0});
 }catch{if(input?.token)try{await rpc('paper_daily_fail',{p_token:input.token});}catch{}return reply({error:'Dagonderzoek niet voltooid; geen koers of rendement aangevuld.'},503);}
}
if(globalThis.Deno?.serve)Deno.serve(handler);

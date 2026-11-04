import {constantEqual,env,reply,requestBody,rpc} from '../_shared/platform.js';
import {stepBreadth,BREADTH_POLICY} from '../_shared/breadth-study.js';
export async function handler(request){
 const secret=env('PAPERLAB_CRON_TOKEN');if(!secret||!constantEqual(request.headers.get('X-PaperLab-Cron')||'',secret))return reply({error:'Niet toegestaan.'},401);
 if(request.method!=='POST')return reply({error:'POST vereist.'},405);
 let input;
 try{
  await requestBody(request);input=await rpc('paper_breadth_claim');if(!input)return reply({status:'waiting_reference_busy_budget_or_daily_limit'});
  if(input.policy?.implementation_sha256!==BREADTH_POLICY.implementation_sha256)throw Error('Exploratory policy differs');
  const output=await stepBreadth(input),saved=await rpc('paper_breadth_commit',{p_token:input.token,p_output:output});
  return reply({status:saved?'stored':'superseded',eligible:output.summary.eligible,new_compact:saved?output.records.length:0,new_detailed:saved?output.traces.length:0,extra_market_downloads:0,real_orders:0});
 }catch{if(input?.token)try{await rpc('paper_breadth_fail',{p_token:input.token});}catch{}return reply({error:'Uitgebreide registratie niet voltooid; geen nieuwe uitvoering bevestigd.'},503);}
}
if(globalThis.Deno?.serve)Deno.serve(handler);

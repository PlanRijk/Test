import {constantEqual,env,reply,requestBody,rpc} from '../_shared/platform.js';
import {readDaily} from '../_shared/reading-study.js';
import {READING_IMPLEMENTATION_SHA} from '../_shared/reading-implementation.js';
export async function handler(request){
 const secret=env('PAPERLAB_CRON_TOKEN');if(!secret||!constantEqual(request.headers.get('X-PaperLab-Cron')||'',secret))return reply({error:'Niet toegestaan.'},401);
 if(request.method!=='POST')return reply({error:'POST vereist.'},405);
 let input;try{
  await requestBody(request);input=await rpc('paper_reading_claim');if(!input)return reply({status:'daily_done_paused_busy_or_budget'});
  if(input.policy.implementation_sha256!==READING_IMPLEMENTATION_SHA)throw Error('Reading implementation differs');
  const result=await readDaily(input),saved=await rpc('paper_reading_commit',{p_token:input.token,p_report:result});
  return reply({status:saved?result.status:'superseded',card_id:result.card_id,whole_book_read:false,model_changes:false});
 }catch{if(input?.token)try{await rpc('paper_reading_fail',{p_token:input.token});}catch{}return reply({error:'Leesronde niet voltooid; geen analyse of regelwijziging bevestigd.'},503);}
}
if(globalThis.Deno?.serve)Deno.serve(handler);

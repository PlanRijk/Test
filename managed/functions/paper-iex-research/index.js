import {constantEqual,env,reply,requestBody,rpc} from '../_shared/platform.js';
import {IEX_IMPLEMENTATION_SHA} from '../_shared/iex-implementation.js';
import {collectIex,IEX_POLICY} from '../_shared/iex-study.js';
export async function handler(request){
 const token=env('PAPERLAB_CRON_TOKEN');if(!token||!constantEqual(request.headers.get('X-PaperLab-Cron')||'',token))return reply({error:'Niet toegestaan.'},401);
 if(request.method!=='POST')return reply({error:'POST vereist.'},405);
 let lease;
 try{
  await requestBody(request);lease=await rpc('paper_iex_claim');if(!lease)return reply({status:'outside_session_paused_busy_or_budget'});
  if(lease.implementation_sha256!==IEX_IMPLEMENTATION_SHA)throw Error('research_profile_changed');
  const started=Date.now(),data=await collectIex(env('ALPACA_API_KEY_ID').trim(),env('ALPACA_API_SECRET_KEY').trim());
  const output={version:IEX_POLICY.version,points:data.points,source_bytes:data.source_bytes,source_calls:data.source_calls,checked_at:new Date().toISOString(),duration_ms:Date.now()-started};
  const saved=await rpc('paper_iex_commit',{p_token:lease.token,p_output:output});return reply({status:saved?'observed':'superseded',companies:53,orders:0});
 }catch{if(lease)try{await rpc('paper_iex_fail',{p_token:lease.token});}catch{}return reply({error:'IEX-onderzoek niet voltooid; geen prijzen of uitkomsten aangevuld.'},503);}
}
if(globalThis.Deno?.serve)Deno.serve(handler);

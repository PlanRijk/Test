import {constantEqual,env,reply,requestBody,rpc} from '../_shared/platform.js';
import {verifyArtifact} from '../_shared/learner.js';
import {pairedDays} from '../_shared/learning-runtime.js';
import {modelAudit,epochAudit} from '../_shared/reliability.js';
export async function handler(request){
 const secret=env('PAPERLAB_CRON_TOKEN');if(!secret||!constantEqual(request.headers.get('X-PaperLab-Cron')||'',secret))return reply({error:'Niet toegestaan.'},401);
 if(request.method!=='POST')return reply({error:'POST vereist.'},405);
 let input;
 try{
  await requestBody(request);input=await rpc('paper_audit_input');if(!input)return reply({status:'paused_budget_busy_or_cooldown'});
  const result={models:[],epochs:[]};
  for(const m of input.models||[]){
   if(!await verifyArtifact(m.artifact))continue;
   const report=await modelAudit(m.artifact,pairedDays(m.records||[],m.artifact.id),m.meta||{});
   if(report.status==='final')result.models.push(report);
  }
  for(const e of input.epochs||[]){const report=await epochAudit(e);if(report.status==='final')result.epochs.push(report);}
  const saved=await rpc('paper_audit_store',{p_token:input.token,p_result:result});
  return reply({status:saved?'audited':'superseded',model_assessments:result.models.length,released_epochs:result.epochs.length,real_trading:false});
 }catch{if(input?.token)try{await rpc('paper_audit_fail',{p_token:input.token});}catch{}return reply({error:'Onafhankelijke beoordeling niet voltooid; geen nieuw bewijs of handelsgoedkeuring bevestigd.'},503);}
}
if(globalThis.Deno?.serve)Deno.serve(handler);

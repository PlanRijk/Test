import {constantEqual,env,reply,requestBody,rpc} from '../_shared/platform.js';
import {possibleSession} from '../_shared/engine.js';
import {BY_SYMBOL} from '../_shared/catalogue.js';
import {trainCandidate,forwardVerdict,verifyArtifact} from '../_shared/learner.js';
import {pairedDays} from '../_shared/learning-runtime.js';

export async function handler(request){
 const secret=env('PAPERLAB_CRON_TOKEN');if(!secret||!constantEqual(request.headers.get('X-PaperLab-Cron')||'',secret))return reply({error:'Niet toegestaan.'},401);
 if(request.method!=='POST')return reply({error:'POST vereist.'},405);
 let input;
 try{
  const body=await requestBody(request);if(body.manual!==true&&possibleSession(BY_SYMBOL.AAPL,Date.now()))return reply({status:'deferred_market_open'});
  input=await rpc('paper_learning_train_input');if(!input)return reply({status:'paused_budget_busy_or_ended'});
  for(const m of input.models||[]){
   if(!await verifyArtifact(m.artifact))continue;
   const days=pairedDays(input.days_data||[],m.artifact.id),verdict=forwardVerdict(m.artifact,days,input.closes?.[m.artifact.id]||0);
   await rpc('paper_learning_review',{p_model:m.artifact.id,p_verdict:verdict});
  }
  const result=input.model_limit_reached?{status:'trial_budget',blocked:['Maximaal drie nieuwe modellen per negentig dagen; geen onbeperkte parameterzoektocht.'],samples:input.sample_count,days:input.days}:
   await trainCandidate(input.samples||[],{fingerprint:input.fingerprint,previousCutoff:input.previous_cutoff});
  if(result.status==='waiting_data'){result.samples=input.sample_count;result.days=input.days;}
  const stored=await rpc('paper_learning_store',{p_token:input.token,p_result:result});
  return reply({status:stored?result.status:'superseded',samples:result.samples,days:result.days,model_created:stored&&result.status==='trained',real_trading:false});
 }catch{
  if(input?.token)try{await rpc('paper_learning_store',{p_token:input.token,p_result:{status:'error',blocked:['Training of toetsing mislukt; geen nieuw model geactiveerd.']}});}catch{}
  return reply({error:'Leercontrole niet voltooid; geen nieuw model geactiveerd.'},503);
 }
}
if(globalThis.Deno?.serve)Deno.serve(handler);

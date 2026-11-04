import {constantEqual,env,reply,requestBody,rpc} from '../_shared/platform.js';
import {tick} from '../_shared/engine.js';
import {fetchMarket} from '../_shared/market.js';
import {livePolicy,stepLearning} from '../_shared/learning-runtime.js';
import {stepOpportunities} from '../_shared/opportunities.js';

export async function handler(request){
  const expected=env('PAPERLAB_CRON_TOKEN');if(!expected||!constantEqual(request.headers.get('X-PaperLab-Cron')||'',expected))return reply({error:'Niet toegestaan.'},401);
  if(request.method!=='POST')return reply({error:'POST vereist.'},405);
  let lease;
  try{
    const body=await requestBody(request);lease=await rpc('paper_claim_tick',{p_manual:body.manual===true});
    if(!lease)return reply({status:'paused_busy_or_ended'});
    const batch=await fetchMarket(lease.state),time=Date.now(),policy=await livePolicy(lease.learning,time,lease.state),out=tick(lease.state,batch,time,policy.options);
    try{out.learning=await stepLearning(lease.learning,lease.state,batch,time,policy);}
    catch{if(lease.learning?.enabled)out.learning={revision:lease.learning.revision,state:{...lease.learning.state,latest_status:'error',message:'Leerverwerking mislukt; hoofdproef blijft bij veilige baseline.'},events:[],trades:[],samples:[],days:[]};}
    try{out.opportunities=await stepOpportunities(lease.opportunities,out.state,batch,time);}
    catch{if(lease.opportunities?.enabled)out.opportunities={revision:lease.opportunities.revision,error:true};}
    out.state.running=Boolean(lease.persist_running)&&out.state.running;
    const committed=await rpc('paper_commit_tick',{p_token:lease.token,p_revision:lease.revision,p_output:out});
    return reply({status:committed?'committed':'superseded',fresh_quotes:Object.keys(batch.quotes).length,trades:committed?out.trades.length:0});
  }catch{
    if(lease)try{await rpc('paper_fail_tick',{p_token:lease.token,p_message:'Koersronde mislukt; geen nieuwe uitvoering bevestigd. Volgende ronde probeert opnieuw.'});}catch{}
    return reply({error:'Koersronde niet voltooid.'},503);
  }
}
if(globalThis.Deno?.serve)Deno.serve(handler);

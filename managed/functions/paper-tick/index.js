import {constantEqual,env,reply,requestBody,rpc} from '../_shared/platform.js';
import {tick} from '../_shared/engine.js';
import {fetchMarket} from '../_shared/market.js';

export async function handler(request){
  const expected=env('PAPERLAB_CRON_TOKEN');if(!expected||!constantEqual(request.headers.get('X-PaperLab-Cron')||'',expected))return reply({error:'Niet toegestaan.'},401);
  if(request.method!=='POST')return reply({error:'POST vereist.'},405);
  let lease;
  try{
    const body=await requestBody(request);lease=await rpc('paper_claim_tick',{p_manual:body.manual===true});
    if(!lease)return reply({status:'paused_busy_or_ended'});
    const batch=await fetchMarket(lease.state),out=tick(lease.state,batch,Date.now());
    out.state.running=Boolean(lease.persist_running)&&out.state.running;
    const committed=await rpc('paper_commit_tick',{p_token:lease.token,p_revision:lease.revision,p_output:out});
    return reply({status:committed?'committed':'superseded',fresh_quotes:Object.keys(batch.quotes).length,trades:committed?out.trades.length:0});
  }catch{
    if(lease)try{await rpc('paper_fail_tick',{p_token:lease.token,p_message:'Koersronde mislukt; geen nieuwe uitvoering bevestigd. Volgende ronde probeert opnieuw.'});}catch{}
    return reply({error:'Koersronde niet voltooid.'},503);
  }
}
if(globalThis.Deno?.serve)Deno.serve(handler);

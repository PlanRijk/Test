import{constantEqual,env,reply,rpc,requestBody}from'../_shared/platform.js';
import{collectReference}from'../_shared/project-followup.js';
import{snapshotBackup}from'../_shared/private-archive.js';
import{publicationBatch}from'../_shared/publication-watch.js';
export async function handler(request){
 const secret=env('PAPERLAB_CRON_TOKEN');if(!secret||!constantEqual(request.headers.get('X-PaperLab-Cron')||'',secret))return reply({error:'Niet toegestaan.'},401);
 if(request.method!=='POST')return reply({error:'POST vereist.'},405);
 let input;
 try{const body=await requestBody(request);input=await rpc('paper_project_claim');if(!input)return reply({status:'paused_budget_busy_or_daily_limit'});let result;
  try{result=await collectReference(input);}catch{result={symbol:'VWCE.DE',currency:'EUR',status:'source_unavailable'};}
  const saved=await rpc('paper_project_commit',{p_token:input.token,p_result:result});let backup={status:'weekly_not_due'};
  let publications={status:'not_due'};if(saved)try{const scan=await rpc('paper_project_watch_claim');if(scan){const rows=await publicationBatch(scan.targets);const done=await rpc('paper_project_watch_commit',{p_token:scan.token,p_rows:rows});publications={status:done?'checked':'superseded',companies:rows.length,confirmed:rows.filter(x=>x.status==='observed').length};}}catch{publications={status:'check_failed'};}
  if(saved&&(new Date().getUTCDay()===0||body.backup===true))try{backup=await snapshotBackup();}catch(error){const reason=['archive_key_missing','archive_plaintext_limit','archive_size','archive_upload','archive_verify_read','archive_integrity','archive_chunk_missing','archive_source_hash'].includes(error?.message)?error.message:'processing_or_database_error';backup={status:'backup_failed',reason};}
  return reply({status:saved?result.status:'superseded',backup,publications,research_queue_refreshed:true,trade_changes:false});
 }catch{return reply({error:'Opvolging niet bevestigd; geen handelswijziging.'},503);}
}
if(globalThis.Deno?.serve)Deno.serve(handler);

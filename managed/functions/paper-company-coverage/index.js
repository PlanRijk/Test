import{constantEqual,env,reply,requestBody,rpc}from'../_shared/platform.js';
import{collectCompanyCoverage}from'../_shared/company-coverage.js';
export async function handler(request){
 const secret=env('PAPERLAB_CRON_TOKEN');if(!secret||!constantEqual(request.headers.get('X-PaperLab-Cron')||'',secret))return reply({error:'Niet toegestaan.'},401);if(request.method!=='POST')return reply({error:'POST vereist.'},405);
 let input;try{const body=await requestBody(request);input=await rpc('paper_company_coverage_claim',{p_manual:body.manual===true});if(!input)return reply({status:'paused_budget_busy_or_fresh'});const rows=[];let i=0;async function worker(){while(i<input.targets.length){const c=input.targets[i++];try{rows.push(await collectCompanyCoverage(c));}catch(e){rows.push({symbol:c.symbol,source_bytes:100000,status:'source_unavailable',source_status:/^Financial source HTTP \d{3}$/.test(e.message)?e.message:'source_or_validation_failure'});}}}await Promise.all([worker(),worker()]);const saved=await rpc('paper_company_coverage_commit',{p_token:input.token,p_rows:rows});return reply({status:saved?'observed':'superseded',observed:rows.filter(x=>x.observation).length,unknown:rows.filter(x=>!x.observation).length,trade_approval:false});}
 catch{if(input?.token)try{await rpc('paper_company_coverage_fail',{p_token:input.token});}catch{}return reply({error:'Brede bedrijfsbronronde niet bevestigd; geen koopgoedkeuring.'},503);}
}
if(globalThis.Deno?.serve)Deno.serve(handler);

import{constantEqual,env,reply,requestBody,rpc}from'../_shared/platform.js';
import{collectCompany}from'../_shared/company-data.js';
export async function handler(request){
 const secret=env('PAPERLAB_CRON_TOKEN');if(!secret||!constantEqual(request.headers.get('X-PaperLab-Cron')||'',secret))return reply({error:'Niet toegestaan.'},401);if(request.method!=='POST')return reply({error:'POST vereist.'},405);
 let input;try{await requestBody(request);input=await rpc('paper_company_collect_claim');if(!input)return reply({status:'paused_budget_busy_or_daily_limit'});const record=await collectCompany(input.item),saved=await rpc('paper_company_collect_commit',{p_token:input.token,p_record:record,p_source_bytes:record.source_bytes});return reply({status:saved?'evidence_collected':'superseded',symbol:input.item.symbol,automatic_qualitative_approval:false});}
 catch{if(input?.token)try{await rpc('paper_company_collect_fail',{p_token:input.token});}catch{}return reply({error:'Bedrijfsbron niet bevestigd; geen fundamentele goedkeuring.'},503);}
}
if(globalThis.Deno?.serve)Deno.serve(handler);

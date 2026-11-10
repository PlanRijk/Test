// Private operator diagnosis; consumes the same two-per-day source budget.
import{constantEqual,env,reply,rpc}from'../_shared/platform.js';
import{collectCompany}from'../_shared/company-data.js';
export async function handler(request){
 const s=env('PAPERLAB_CRON_TOKEN');if(!s||!constantEqual(request.headers.get('X-PaperLab-Cron')||'',s))return reply({error:'Niet toegestaan.'},401);if(request.method!=='POST')return reply({error:'POST vereist.'},405);
 let input;const sources=[];try{input=await rpc('paper_company_collect_claim');if(!input)return reply({status:'budget_busy_or_daily_limit'});const record=await collectCompany(input.item,{fetcher:async(url,opts)=>{const r=await fetch(url,opts);sources.push({kind:url.includes('companyfacts')?'SEC facts':url.includes('submissions')?'SEC filings':'daily prices',http_status:r.status});return r;}});const saved=await rpc('paper_company_collect_commit',{p_token:input.token,p_record:record,p_source_bytes:record.source_bytes});return reply({status:saved?'collected':'superseded',symbol:input.item.symbol,sources});}
 catch(e){if(input?.token)try{await rpc('paper_company_collect_fail',{p_token:input.token});}catch{}const reason=['Official source unavailable','Source size','Issuer identity not confirmed','Dated financial reports missing','Comparable annual revenue missing'].includes(e.message)?e.message:'source_or_processing_failure';return reply({status:'not_confirmed',symbol:input?.item?.symbol||null,reason,sources},503);}
}
if(globalThis.Deno?.serve)Deno.serve(handler);

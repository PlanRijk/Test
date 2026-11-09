// Manual, read-only server diagnostic. No order endpoint, ledger RPC or cron job.
import {constantEqual,env,reply} from '../_shared/platform.js';
const URL='https://data.alpaca.markets/v2/stocks/quotes/latest?symbols=AAPL%2CMSFT%2CNVDA&feed=iex';
const SYMBOLS=['AAPL','MSFT','NVDA'];
export async function handler(request){
 const token=env('PAPERLAB_CRON_TOKEN');
 if(!token||!constantEqual(request.headers.get('X-PaperLab-Cron')||'',token))return reply({error:'Niet toegestaan.'},401);
 if(request.method!=='POST')return reply({error:'POST vereist.'},405);
 const key=env('ALPACA_API_KEY_ID').trim(),secret=env('ALPACA_API_SECRET_KEY').trim();
 if(!key||!secret)return reply({status:'missing_credentials',key_present:!!key,secret_present:!!secret},503);
 try{
  const response=await fetch(URL,{method:'GET',headers:{'APCA-API-KEY-ID':key,'APCA-API-SECRET-KEY':secret,'Accept':'application/json'},redirect:'error',signal:AbortSignal.timeout(12000)});
  // Never echo provider errors: they could contain submitted credentials.
  if(!response.ok)return reply({status:response.status===401?'credentials_rejected':response.status===403?'feed_access_denied':response.status===429?'rate_limited':'provider_error',provider_http_status:response.status,feed:'iex'},502);
  const text=await response.text();if(text.length>64000)throw Error('oversize');
  const payload=JSON.parse(text),checked=Date.now(),quotes=[],diagnostics=[];
  for(const symbol of SYMBOLS){
   const q=payload.quotes?.[symbol];if(!q){diagnostics.push({symbol,record_present:false});continue;}
   const stamp=Date.parse(q.t),bid=Number(q.bp),ask=Number(q.ap),age=(checked-stamp)/1000;
   const issue=!Number.isFinite(stamp)?'invalid_timestamp':!Number.isFinite(bid)||!Number.isFinite(ask)||bid<=0||ask<=0?'missing_bid_or_ask':ask<bid?'crossed_quote':null;
   diagnostics.push({symbol,record_present:true,bid:Number.isFinite(bid)?bid:null,ask:Number.isFinite(ask)?ask:null,quote_time:Number.isFinite(stamp)?new Date(stamp).toISOString():null,issue});
   if(issue)continue;
   quotes.push({symbol,bid,ask,currency:'USD',quote_time:new Date(stamp).toISOString(),age_seconds:Math.round(age*100)/100,fresh_within_60_seconds:age>=0&&age<=60});
  }
  return reply({status:quotes.length?'connected':'connected_without_valid_quotes',provider_http_status:response.status,feed:'iex',checked_at:new Date(checked).toISOString(),quote_count:quotes.length,quotes,quote_diagnostics:diagnostics,orders_submitted:0,trading_feed_changed:false});
 }catch{return reply({status:'connection_or_payload_error',feed:'iex'},502);}
}
if(globalThis.Deno?.serve)Deno.serve(handler);

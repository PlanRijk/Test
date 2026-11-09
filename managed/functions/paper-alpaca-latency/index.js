// Bounded read-only measurement over the executable US catalogue. No orders/RPCs.
import {COMPANIES} from '../_shared/catalogue.js';
import {constantEqual,env,reply} from '../_shared/platform.js';
export const US_SYMBOLS=COMPANIES.filter(c=>['XNAS','XNYS'].includes(c.exchange)).map(c=>c.symbol);
export const PROVIDER_SYMBOL=Object.fromEntries(US_SYMBOLS.map(s=>[s,s==='BRK-B'?'BRK.B':s]));
const percentile=(xs,p)=>xs.length?[...xs].sort((a,b)=>a-b)[Math.ceil(xs.length*p)-1]:null;
const round=n=>Number.isFinite(n)?Math.round(n*1000)/1000:null;
export function measurePayload(quotes,trades,now){
 const rows=US_SYMBOLS.map(symbol=>{
  const q=quotes?.[PROVIDER_SYMBOL[symbol]],t=trades?.[PROVIDER_SYMBOL[symbol]],qt=Date.parse(q?.t),tt=Date.parse(t?.t);
  const bid=Number(q?.bp),ask=Number(q?.ap),price=Number(t?.p);
  const quoteValid=Number.isFinite(qt)&&Number.isFinite(bid)&&Number.isFinite(ask)&&bid>0&&ask>=bid;
  const tradeValid=Number.isFinite(tt)&&Number.isFinite(price)&&price>0;
  const qa=(now-qt)/1000,ta=(now-tt)/1000;
  return {symbol,bid_size:Number.isFinite(q?.bs)?q.bs:null,ask_size:Number.isFinite(q?.as)?q.as:null,bid_exchange:typeof q?.bx==='string'&&/^[A-Z ]$/.test(q.bx)?q.bx:null,ask_exchange:typeof q?.ax==='string'&&/^[A-Z ]$/.test(q.ax)?q.ax:null,quote_conditions:Array.isArray(q?.c)?q.c.filter(x=>typeof x==='string'&&/^[A-Za-z0-9 ]{1,4}$/.test(x)).slice(0,8):[],provider_symbol:PROVIDER_SYMBOL[symbol],quote_present:!!q,quote_time:Number.isFinite(qt)?new Date(qt).toISOString():null,quote_age_seconds:round(qa),bid:Number.isFinite(bid)?bid:null,ask:Number.isFinite(ask)?ask:null,valid_quote_sides:quoteValid,quote_within_60s:quoteValid&&qa>=0&&qa<=60,quote_within_120s:quoteValid&&qa>=0&&qa<=120,trade_present:!!t,trade_time:Number.isFinite(tt)?new Date(tt).toISOString():null,trade_age_seconds:round(ta),trade_price:tradeValid?price:null,trade_within_60s:tradeValid&&ta>=0&&ta<=60};
 });
 const qa=rows.filter(x=>x.valid_quote_sides&&x.quote_age_seconds>=0).map(x=>x.quote_age_seconds),ta=rows.filter(x=>x.trade_price&&x.trade_age_seconds>=0).map(x=>x.trade_age_seconds);
 return {expected:rows.length,quote_records:rows.filter(r=>r.quote_present).length,valid_two_sided_quotes:rows.filter(r=>r.valid_quote_sides).length,quotes_within_60s:rows.filter(r=>r.quote_within_60s).length,quotes_within_120s:rows.filter(r=>r.quote_within_120s).length,trade_records:rows.filter(r=>r.trade_present).length,trades_within_60s:rows.filter(r=>r.trade_within_60s).length,quote_age_seconds:{median:percentile(qa,.5),p95:percentile(qa,.95),max:qa.length?Math.max(...qa):null},trade_age_seconds:{median:percentile(ta,.5),p95:percentile(ta,.95),max:ta.length?Math.max(...ta):null},rows};
}
export async function handler(request){
 const token=env('PAPERLAB_CRON_TOKEN');if(!token||!constantEqual(request.headers.get('X-PaperLab-Cron')||'',token))return reply({error:'Niet toegestaan.'},401);
 if(request.method!=='POST')return reply({error:'POST vereist.'},405);
 const key=env('ALPACA_API_KEY_ID').trim(),secret=env('ALPACA_API_SECRET_KEY').trim();
 if(!key||!secret)return reply({status:'missing_credentials'},503);
 const started=Date.now();
 async function read(kind){
  const begin=Date.now();
  try{
   const response=await fetch('https://data.alpaca.markets/v2/stocks/'+kind+'/latest?symbols='+encodeURIComponent(US_SYMBOLS.map(s=>PROVIDER_SYMBOL[s]).join(','))+'&feed=iex',{method:'GET',headers:{'APCA-API-KEY-ID':key,'APCA-API-SECRET-KEY':secret,'Accept':'application/json'},redirect:'error',signal:AbortSignal.timeout(12000)});
   if(!response.ok)return {kind,http_status:response.status,elapsed_ms:Date.now()-begin,error:'provider_rejected'};
   const text=await response.text();if(text.length>200000)throw Error('size');
   const data=JSON.parse(text);if(!data[kind]||typeof data[kind]!=='object'||Array.isArray(data[kind]))throw Error('shape');
   return {kind,http_status:response.status,elapsed_ms:Date.now()-begin,payload_bytes:new TextEncoder().encode(text).length,data:data[kind]};
  }catch{return {kind,error:'connection_or_payload_error',elapsed_ms:Date.now()-begin};}
 }
 const [q,t]=await Promise.all([read('quotes'),read('trades')]),finished=Date.now();
 const provider=[q,t].map(({data,...safe})=>safe);
 return reply({status:q.data&&t.data?'measured':'partial_or_failed',feed:'iex',requested_at:new Date(started).toISOString(),checked_at:new Date(finished).toISOString(),collection_ms:finished-started,provider,...measurePayload(q.data,t.data,finished),orders_submitted:0,trading_feed_changed:false});
}
if(globalThis.Deno?.serve)Deno.serve(handler);

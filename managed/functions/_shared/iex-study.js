import {COMPANIES} from './catalogue.js';
export const IEX_SYMBOLS=COMPANIES.filter(x=>['XNAS','XNYS'].includes(x.exchange)).map(x=>x.symbol);
export const IEX_POLICY={version:'iex-minute-research-v1',feed:'iex',symbols:IEX_SYMBOLS,cadence_seconds:60,study_days:14,raw_retention_hours:48,max_raw_batches:800,aggregate_retention_days:60,max_storage_bytes:12000000,max_database_bytes:105000000,max_monthly_bytes:200000000,shared_monthly_ceiling_bytes:1050000000,reserved_bytes_per_attempt:50000,max_attempts_per_day:400,source_response_bytes:16000,source_calls_per_round:2,quote_age_seconds:60,coarse_minutes:5,move_thresholds_bps:[50,150],orders:false,automatic_training:false};
const price=x=>typeof x==='number'&&Number.isFinite(x)&&x>=0&&x<1e9?x:null;
const stamp=x=>{const t=Date.parse(x);return Number.isFinite(t)&&t>=946684800000&&t<4102444800000?t:null;};
export function compactIex(quotes,trades){
 return IEX_SYMBOLS.map(symbol=>{const key=symbol==='BRK-B'?'BRK.B':symbol,q=quotes?.[key],t=trades?.[key];return [stamp(q?.t),price(q?.bp),price(q?.ap),stamp(t?.t),price(t?.p)];});
}
async function readBounded(response,limit){
 const reader=response.body?.getReader();if(!reader)throw Error('body');let size=0;const chunks=[];
 try{while(true){const{value,done}=await reader.read();if(done)break;size+=value.byteLength;if(size>limit)throw Error('size');chunks.push(value);}}finally{await reader.cancel().catch(()=>{});}
 const bytes=new Uint8Array(size);let at=0;for(const c of chunks){bytes.set(c,at);at+=c.length;}return {text:new TextDecoder().decode(bytes),bytes:size};
}
export async function collectIex(key,secret,{fetcher=fetch}={}){
 if(!key||!secret)throw Error('missing_credentials');
 const symbols=encodeURIComponent(IEX_SYMBOLS.map(s=>s==='BRK-B'?'BRK.B':s).join(','));
 async function get(kind){
  const response=await fetcher('https://data.alpaca.markets/v2/stocks/'+kind+'/latest?symbols='+symbols+'&feed=iex',{method:'GET',headers:{'APCA-API-KEY-ID':key,'APCA-API-SECRET-KEY':secret,'Accept':'application/json'},redirect:'error',signal:AbortSignal.timeout(5000)});
  if(!response.ok)throw Error('provider_rejected');
  const b=await readBounded(response,IEX_POLICY.source_response_bytes),data=JSON.parse(b.text)[kind];
  if(!data||typeof data!=='object'||Array.isArray(data))throw Error('payload');return {data,bytes:b.bytes};
 }
 const [q,t]=await Promise.allSettled([get('quotes'),get('trades')]);
 if(q.status!=='fulfilled'||t.status!=='fulfilled')throw Error('source_unavailable');
 return {points:compactIex(q.value.data,t.value.data),source_bytes:q.value.bytes+t.value.bytes,source_calls:2};
}

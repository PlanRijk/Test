import{digest}from'./platform.js';
import{COMPANY_POLICY as P}from'./company-policy.js';
import{parseCompanyFacts}from'./company-analysis.js';
async function read(url,max,budget,fetcher){
 const r=await fetcher(url,{headers:{'User-Agent':'PaperLab personal paper research paperlab@users.noreply.github.com','Accept':'application/json'},signal:AbortSignal.timeout(12000)});if(!r.ok)throw Error('Official source unavailable');
 let n=0;const chunks=[],reader=r.body.getReader();try{for(;;){const{done,value}=await reader.read();if(done)break;n+=value.byteLength;budget.bytes+=value.byteLength;if(n>max||budget.bytes>P.source_response_bytes)throw Error('Source size');chunks.push(value);}}finally{await reader.cancel().catch(()=>{});}
 const b=new Uint8Array(n);let at=0;for(const v of chunks){b.set(v,at);at+=v.length;}const text=new TextDecoder().decode(b);budget.hashes||={};budget.hashes[url]=await digest(text);return JSON.parse(text);
}
export function parseCompanyCloses(data,item,time=Date.now()){
 const c=data.chart?.result?.[0],m=c?.meta;if(m?.symbol!==item.symbol||m.currency!==item.currency||m.instrumentType!=='EQUITY')throw Error('Price instrument mismatch');
 const action=Object.values(c.events?.splits||{}).length+Object.values(c.events?.dividends||{}).length;if(action)return{market_closes:[],price_window_status:'corporate_action_requires_review'};
 const out=[];for(let i=0;i<(c.timestamp||[]).length;i++){const at=c.timestamp[i]*1000,day=new Intl.DateTimeFormat('en-CA',{timeZone:item.timezone,year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(at)),today=new Intl.DateTimeFormat('en-CA',{timeZone:item.timezone,year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(time)),close=c.indicators?.quote?.[0]?.close?.[i];if(day>=today||!Number.isFinite(close)||close<=0||at>time)continue;if(out.length&&day<=out.at(-1).day)throw Error('Price ordering');out.push({day,close,observed_at:new Date(time).toISOString()});}
 return{market_closes:out.slice(-20),price_window_status:out.length>=20?'twenty_source_closes':'insufficient_source_closes'};
}
export async function collectCompany(item,{fetcher=fetch,time=Date.now()}={}){
 const budget={bytes:0},facts=await read('https://data.sec.gov/api/xbrl/companyfacts/CIK'+item.cik+'.json',7500000,budget,fetcher),sub=await read('https://data.sec.gov/submissions/CIK'+item.cik+'.json',700000,budget,fetcher);
 const d=parseCompanyFacts(facts,sub,item,{time,source_bytes:budget.bytes});d.sector=item.sector;
 try{const q=await read('https://query1.finance.yahoo.com/v8/finance/chart/'+encodeURIComponent(item.symbol)+'?interval=1d&range=1mo&events=div%2Csplits',150000,budget,fetcher);Object.assign(d,parseCompanyCloses(q,item,time));}catch{d.market_closes=[];d.price_window_status='unavailable';}
 d.source_bytes=budget.bytes;d.source_hashes=budget.hashes;return d;
}

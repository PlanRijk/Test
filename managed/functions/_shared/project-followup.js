import{digest}from'./platform.js';
const day=t=>new Intl.DateTimeFormat('en-CA',{timeZone:'Europe/Berlin',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date(t));
export function referenceResult(data,input,time=Date.now()){
 const r=data?.chart?.result?.[0],m=r?.meta;
 if(data?.chart?.error||m?.symbol!=='VWCE.DE'||m.currency!=='EUR'||m.instrumentType!=='ETF'||m.exchangeTimezoneName!=='Europe/Berlin')throw Error('reference_identity');
 if(!Array.isArray(r.timestamp)||r.timestamp.length>35||!Array.isArray(r.indicators?.quote?.[0]?.close))throw Error('reference_bars');
 const known=new Date(time).toISOString(),today=day(time),start=day(Date.parse(input.started_at)),candidates=[];
 for(let i=0;i<r.timestamp.length;i++){const stamp=r.timestamp[i]*1000,d=day(stamp),close=r.indicators.quote[0].close[i];if(!Number.isFinite(stamp))throw Error('reference_time');if(d>=today)continue;if(stamp>time)throw Error('reference_time');if(!Number.isFinite(close)||close<=0)continue;if(candidates.length&&d<=candidates.at(-1).day)throw Error('reference_order');candidates.push({day:d,close});}
 const last=candidates.at(-1);if(!last||Date.parse(today)-Date.parse(last.day)>4*86400000)throw Error('reference_stale');
 const base={symbol:'VWCE.DE',currency:'EUR',known_at:known,source:'Yahoo Finance indicative Xetra ETF closes',status:'waiting_future_session'};
 if(last.day<=start)return base;
 if(input.benchmark?.entry_day)for(const event of Object.values(r.events?.splits||{}))if(day(event.date*1000)>=input.benchmark.entry_day)return{...base,status:'corporate_action_review'};
 return{...base,...last,status:'observed'};
}
export async function collectReference(input,{fetcher=fetch,time=Date.now()}={}){
 const url='https://query1.finance.yahoo.com/v8/finance/chart/VWCE.DE?interval=1d&range=1mo&events=div%2Csplits';
 const r=await fetcher(url,{headers:{'User-Agent':'PaperLab/1.0 bounded prospective reference'},signal:AbortSignal.timeout(10000)});if(!r.ok)throw Error('reference_http_'+r.status);
 const reader=r.body.getReader(),parts=[];let n=0;try{for(;;){const{done,value}=await reader.read();if(done)break;n+=value.byteLength;if(n>120000)throw Error('reference_size');parts.push(value);}}finally{await reader.cancel().catch(()=>{});}
 const bytes=new Uint8Array(n);let at=0;for(const p of parts){bytes.set(p,at);at+=p.length;}const text=new TextDecoder().decode(bytes);
 return{...referenceResult(JSON.parse(text),input,time),source_url:url,source_sha256:await digest(text),download_bytes:n};
}

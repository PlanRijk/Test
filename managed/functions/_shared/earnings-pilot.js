import {COMPANY_SOURCES} from './company-source-catalogue.js';
import {digest} from './platform.js';
const MAX=400000;
export async function boundedPage(url,fetcher=fetch){
 const r=await fetcher(url,{headers:{'User-Agent':'PaperLab/1.0 bounded free earnings research'},redirect:'error',signal:AbortSignal.timeout(8000)});
 if(!r.ok)throw Error('source_http_'+r.status);
 const reader=r.body.getReader(),parts=[];let n=0;
 try{for(;;){const{done,value}=await reader.read();if(done)break;n+=value.byteLength;if(n>MAX)throw Error('source_too_large');parts.push(value);}}finally{await reader.cancel().catch(()=>{});}
 const bytes=new Uint8Array(n);let at=0;for(const p of parts){bytes.set(p,at);at+=p.length;}return{text:new TextDecoder().decode(bytes),bytes:n};
}
export function priceSeries(data,symbol,time=Date.now()){
 const r=data?.chart?.result?.[0],m=r?.meta,today=new Intl.DateTimeFormat('en-CA',{timeZone:'America/New_York'}).format(new Date(time));
 if(data?.chart?.error||m?.symbol!==symbol||m.currency!=='USD'||m.instrumentType!=='EQUITY'||m.exchangeTimezoneName!=='America/New_York'||!Array.isArray(r.timestamp)||r.timestamp.length>95)throw Error('price_identity');
 const rows=[];for(let i=0;i<r.timestamp.length;i++){const t=r.timestamp[i]*1000,day=new Intl.DateTimeFormat('en-CA',{timeZone:'America/New_York'}).format(new Date(t)),close=r.indicators?.quote?.[0]?.close?.[i];if(t>time)throw Error('price_future');if(day>=today||!Number.isFinite(close)||close<=0)continue;if(rows.length&&day<=rows.at(-1).day)throw Error('price_order');rows.push({day,close});}
 return{status:Object.keys(r.events?.splits||{}).length?'corporate_action_review':'observed',currency:'USD',rows,known_at:new Date(time).toISOString(),dividends_excluded:true};
}
export async function earningsTarget(target,{fetcher=fetch,time=Date.now()}={}){
 const company=COMPANY_SOURCES.find(c=>c.symbol===target.symbol);if(!company||!company.sec_cik)throw Error('unknown_pilot_company');
 const urls=[target.calendar_url,company.primary_url],sources=[];
 for(const url of urls){
  // Calendar URL is operator-installed, never provided by anonymous input.
  try{const p=await boundedPage(url,fetcher),source={url,status:'observed',sha256:await digest(p.text),bytes:p.bytes,refs:[]};
   if(url===company.primary_url){const data=JSON.parse(p.text);if(Number(data.cik)!==Number(company.sec_cik))throw Error('issuer_identity');const f=data.filings?.recent;if(!f?.form)throw Error('issuer_filings');for(let i=0;i<f.form.length&&source.refs.length<6;i++)if(['10-Q','10-K','8-K'].includes(f.form[i])&&/^\d{10}-\d{2}-\d{6}$/.test(f.accessionNumber[i])&&Date.parse(f.filingDate[i])<=time){const doc=f.primaryDocument[i];if(typeof doc==='string'&&!doc.includes('..'))source.refs.push({form:f.form[i],day:f.filingDate[i],accession:f.accessionNumber[i],url:'https://www.sec.gov/Archives/edgar/data/'+Number(company.sec_cik)+'/'+f.accessionNumber[i].replaceAll('-','')+'/'+encodeURIComponent(doc)});}}
   else{for(const a of p.text.matchAll(/<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)){const label=a[2].replace(/<[^>]*>/g,' ').replace(/\s+/g,' ').trim();if(!/earnings|quarter|financial results/i.test(label))continue;const link=new URL(a[1].replaceAll('&amp;','&'),url);if(link.protocol==='https:'&&link.href.length<1200)source.refs.push({url:link.href,label:label.slice(0,150),date_confirmed:false});if(source.refs.length===6)break;}}
   sources.push(source);
  }catch{sources.push({url,status:'unavailable'});}
 }
 let prices=null;if(target.release_at&&Date.parse(target.release_at)<time){try{const url='https://query1.finance.yahoo.com/v8/finance/chart/'+encodeURIComponent(target.symbol)+'?interval=1d&range=3mo&events=div%2Csplits',p=await boundedPage(url,fetcher);prices={...priceSeries(JSON.parse(p.text),target.symbol,time),source_url:url,sha256:await digest(p.text)};}catch{prices={status:'unavailable'};}}
 return{symbol:target.symbol,status:sources.every(x=>x.status==='observed')?'observed':sources.some(x=>x.status==='observed')?'partial':'unavailable',checked_at:new Date(time).toISOString(),sources,prices,qualitative_review_completed:false,calendar_date_confirmed:false};
}
export async function earningsBatch(targets,options={}){let at=0;const out=[];async function worker(){while(at<targets.length)out.push(await earningsTarget(targets[at++],options));}await Promise.all([worker(),worker(),worker(),worker()]);return out;}

import{COMPANY_SOURCES}from'./company-source-catalogue.js';
import{digest}from'./platform.js';
export async function publicationWatch(target,{fetcher=fetch,time=Date.now(),blocked=new Set()}={}){
 const item=COMPANY_SOURCES.find(x=>x.symbol===target.symbol);if(!item)throw Error('unknown_company');
 const url=item.primary_url,host=new URL(url).hostname,kind=url.includes('data.sec.gov/submissions/')?'SEC_index':'issuer_page',base={symbol:item.symbol,url,kind,known_at:new Date(time).toISOString()};
 if(blocked.has(host))return{...base,status:'rate_limited'};
 let response;
 try{response=await fetcher(url,{headers:{'User-Agent':'PaperLab/1.0 bounded issuer publication monitor'},signal:AbortSignal.timeout(8000)});}catch{return{...base,status:'not_available'};}
 if(response.status===429){blocked.add(host);return{...base,status:'rate_limited'};}if(!response.ok)return{...base,status:'not_available',http_status:response.status};
 const reader=response.body.getReader(),parts=[];let n=0;try{for(;;){const{done,value}=await reader.read();if(done)break;n+=value.byteLength;if(n>200000)return{...base,status:'too_large'};parts.push(value);}}finally{await reader.cancel().catch(()=>{});}
 const bytes=new Uint8Array(n);let at=0;for(const p of parts){bytes.set(p,at);at+=p.length;}const text=new TextDecoder().decode(bytes);let refs=[];
 if(kind==='SEC_index'){
  try{const data=JSON.parse(text),recent=data.filings?.recent,cik=String(data.cik).padStart(10,'0'),expected=url.match(/CIK([0-9]+)\.json$/)?.[1];if(cik!==expected||!recent?.form)throw Error();
   for(let i=0;i<recent.form.length&&refs.length<12;i++){if(!['10-K','10-Q','8-K','20-F','6-K'].includes(recent.form[i]))continue;const d=recent.filingDate[i],accession=recent.accessionNumber[i],doc=recent.primaryDocument[i];if(!/^\d{4}-\d{2}-\d{2}$/.test(d)||Date.parse(d)>time||!/^\d{10}-\d{2}-\d{6}$/.test(accession)||typeof doc!=='string'||doc.includes('..'))continue;refs.push({form:recent.form[i],day:d,accession,url:'https://www.sec.gov/Archives/edgar/data/'+Number(cik)+'/'+accession.replaceAll('-','')+'/'+doc});}
  }catch{return{...base,status:'not_available',validation:'issuer_index_not_confirmed'};}
 }else{
  const seen=new Set();for(const match of text.matchAll(/<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)){
   const label=match[2].replace(/<[^>]*>/g,' ').replace(/\s+/g,' ').trim();if(!/report|result|earnings|quarter|interim|jaarverslag|jaarresult|half.year|financial/i.test(label+' '+match[1]))continue;
   try{const link=new URL(match[1].replaceAll('&amp;','&'),url);if(link.protocol!=='https:'||seen.has(link.href)||link.href.length>1200)continue;seen.add(link.href);refs.push({url:link.href,label:label.slice(0,160),publication_date_verified:false});if(refs.length===12)break;}catch{}
  }
 }
 return{...base,status:'observed',refs,sha256:await digest(JSON.stringify(refs)),download_bytes:n,scope:kind==='SEC_index'?'Filing index and dates, not report contents':'Candidate financial links; publication dates/materiality unverified'};
}
export async function publicationBatch(targets,options={}){
 const rows=[],blocked=new Set();let i=0;async function worker(){while(i<targets.length)rows.push(await publicationWatch(targets[i++],{...options,blocked}));}
 await Promise.all([worker(),worker(),worker(),worker()]);return rows;
}

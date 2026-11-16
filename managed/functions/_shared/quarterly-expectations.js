// Free deterministic research baseline. No model API, broker or trade approval.
import {digest} from './platform.js';
export const QUARTERLY_POLICY={version:'quarterly-baseline-v1',max_input_age_days:14,max_period_age_days:160,range_fraction:.20,high_change_range_fraction:.35,price_age_days:7,max_source_bytes:100000,automatic_trade_approval:false,analyst_consensus:false,qualitative_approval:false};
const DAY=86400000,types={revenue:'quarterlyTotalRevenue',net_income:'quarterlyNetIncome',diluted_eps:'quarterlyDilutedEPS'};
export function normalizeQuarterly(data,symbol,time=Date.now()){
 const series=data?.timeseries?.result;if(data?.timeseries?.error||!Array.isArray(series))throw Error('quarterly_source_missing');const values={};
 for(const s of series){const type=s.meta?.type?.[0];if(!Object.values(types).includes(type))continue;if(!(s.meta?.symbol||[]).includes(symbol))throw Error('quarterly_identity');const rows=[],seen=new Set();for(const p of s[type]||[]){const v=p.reportedValue?.raw;if(p.periodType!=='3M'||!/^\d{4}-\d{2}-\d{2}$/.test(p.asOfDate||'')||Date.parse(p.asOfDate)>time||!Number.isFinite(v)||!p.currencyCode)continue;if(seen.has(p.asOfDate))throw Error('duplicate_quarter');seen.add(p.asOfDate);rows.push({end:p.asOfDate,value:v,currency:p.currencyCode});}values[type]=rows.sort((a,b)=>a.end.localeCompare(b.end)).slice(-5);}
 return values;
}
function estimate(rows,time){
 const no=reason=>({status:'unavailable',reason});if(!Array.isArray(rows)||rows.length!==5)return no('Vijf vergelijkbare kwartalen ontbreken.');
 const r=[...rows].sort((a,b)=>a.end.localeCompare(b.end));for(let i=0;i<r.length;i++){const x=r[i];if(!Number.isFinite(x.value)||!/^\d{4}-\d{2}-\d{2}$/.test(x.end||'')||!x.currency||x.currency!==r[0].currency||Date.parse(x.end)>time)return no('Ongeldige periode, waarde of gewijzigde rapporteringsmunt.');if(i){const gap=(Date.parse(x.end)-Date.parse(r[i-1].end))/DAY;if(gap<65||gap>115)return no('Geen aaneengesloten kwartaalreeks; halfjaarcijfers worden niet als kwartaal behandeld.');}}
 if(time-Date.parse(r[4].end)>160*DAY)return no('Laatste kwartaal is te oud.');
 const yearGap=(Date.parse(r[4].end)-Date.parse(r[0].end))/DAY;if(yearGap<330||yearGap>400||r.some(x=>x.value<=0))return no('Geen stabiele positieve vergelijkingsbasis; verlies- en omslagsituatie vraagt inhoudelijke beoordeling.');
 const ratio=r[4].value/r[0].value;if(ratio<.2||ratio>3)return no('Grote structurele verandering; eenvoudige extrapolatie ingetrokken.');
 const base=r[1].value*ratio,width=ratio<.5||ratio>1.5?.35:.20;
 // Reference period from prior-year target; fiscal/calendar normalization stays explicit.
 const targetDate=new Date(r[1].end+'T00:00:00Z'),month=targetDate.getUTCMonth();targetDate.setUTCFullYear(targetDate.getUTCFullYear()+1);if(targetDate.getUTCMonth()!==month)targetDate.setUTCDate(0);const target_period_reference=targetDate.toISOString().slice(0,10);
 return{status:'baseline',currency:r[0].currency,low:base*(1-width),base,high:base*(1+width),yoy_growth_fraction:ratio-1,range_fraction:width,target_period_reference,last_observed_period:r[4].end,inputs:r,range_is_confidence_interval:false,confidence:'unvalidated',official_fiscal_period_verified:false};
}
export function quarterlyBaseline(input,time=Date.now()){
 const p=QUARTERLY_POLICY,known=Date.parse(input.known_at),gaps=[],metrics={};
 for(const[k,type]of Object.entries(types)){const m=estimate(input.values?.[type],time);metrics[k]=m;if(m.status!=='baseline')gaps.push(k+': '+m.reason);}
 const age=(time-known)/DAY;if(!Number.isFinite(age)||age<0||age>p.max_input_age_days){for(const k of Object.keys(metrics))metrics[k]={status:'unavailable',reason:'Financiële bronwaarneming ouder dan veertien dagen of ongeldig.'};gaps.push('Bronwaarneming moet vernieuwd worden.');}
 const revenue=metrics.revenue,priceAge=time-Date.parse(input.quote_at),quote_ok=Number.isFinite(priceAge)&&priceAge>=0&&priceAge<=7*DAY,source_ok=input.official_source_available===true;
 const eligible=quote_ok&&source_ok;let status=!quote_ok?'waiting_quote':!source_ok?'waiting_official_source':revenue.status==='baseline'?'baseline_available':'insufficient_data';
 if(!eligible)for(const k of Object.keys(metrics))metrics[k]={status:'unavailable',reason:!quote_ok?'Geen ontvangen koers binnen zeven dagen.':'Geen recent bevestigde officiële onderzoeksbron.'};
 return{version:p.version,symbol:input.symbol,checked_at:new Date(time).toISOString(),input_known_at:input.known_at||null,input_fingerprint:input.input_fingerprint||null,financial_source_url:input.source_url||null,financial_source_hash:input.source_hash||null,quote_at:input.quote_at||null,official_source_url:input.official_source_url||null,official_source_available:source_ok,eligible,status,metrics,company_guidance:{status:'not_verified'},analyst_consensus:{status:'not_connected'},qualitative_review:{status:'not_automated'},stock_direction:'not_predicted',trade_approval:false,gaps,method:'Voorgaand jaar hetzelfde kwartaal × laatst waargenomen jaar-op-jaarfactor. Illustratieve band ±20%, bij sterke verandering ±35%; geen gekalibreerde waarschijnlijkheid. EPS alleen indien apart gerapporteerd; niet uit jaarcijfers afgeleid.',limitations:['Secundaire financiële aggregator; periode-eindes zijn geen publicatiedatums.','Rekenraming is geen bedrijfsprognose, analistenconsensus of kwalitatieve beoordeling.','Geen automatische koersvoorspelling of koopgoedkeuring.']};
}
export async function fetchQuarterly(target,options={}){
 const fetcher=options.fetcher||fetch,time=options.time??Date.now();
 const url='https://query1.finance.yahoo.com/ws/fundamentals-timeseries/v1/finance/timeseries/'+encodeURIComponent(target.symbol)+'?type='+Object.values(types).join(',')+'&period1='+Math.floor((time-800*DAY)/1000)+'&period2='+Math.floor(time/1000);
 const r=await fetcher(url,{headers:{'User-Agent':'PaperLab bounded free quarterly baseline'},redirect:'error',signal:AbortSignal.timeout(8000)});if(!r.ok)throw Error('quarterly_http_'+r.status);const reader=r.body.getReader(),parts=[];let n=0;try{for(;;){const{done,value}=await reader.read();if(done)break;n+=value.byteLength;if(n>100000)throw Error('quarterly_size');parts.push(value);}}finally{await reader.cancel().catch(()=>{});}
 const b=new Uint8Array(n);let at=0;for(const p of parts){b.set(p,at);at+=p.length;}const text=new TextDecoder().decode(b),observed=options.time??Date.now(),values=normalizeQuarterly(JSON.parse(text),target.symbol,observed),source_hash=await digest(text);
 return quarterlyBaseline({...target,values,known_at:new Date(observed).toISOString(),source_url:url,source_hash,input_fingerprint:await digest(JSON.stringify(values))},observed);
}

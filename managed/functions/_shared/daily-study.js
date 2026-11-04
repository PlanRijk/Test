import {day} from './engine.js';
import {digest} from './platform.js';
import {DAILY_COMPANIES,DAILY_INDICES,DAILY_PROTOCOL as P} from './daily-catalogue.js';
const iso=t=>new Date(t).toISOString(),dateMs=d=>Date.parse(d+'T00:00:00Z');
export const DAILY_FX='https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist-90d.xml';
export function parseDailyFx(xml){
 const result=[];
 for(const m of xml.matchAll(/<Cube\s+time=['"]([0-9-]+)['"]>([\s\S]*?)<\/Cube>/g)){
  const rates={EUR:1};for(const v of m[2].matchAll(/currency=['"]([A-Z]{3})['"]\s+rate=['"]([0-9.]+)['"]/g))if(Number(v[2])>0)rates[v[1]]=Number(v[2]);
  if(rates.USD&&Number.isFinite(dateMs(m[1])))result.push({date:m[1],rates});
 }if(!result.length)throw Error('Geen gedateerde ECB-referenties.');return result.sort((a,b)=>b.date.localeCompare(a.date));
}
export function parseDailyChart(data,item,fx,time){
 const r=data.chart?.result?.[0],m=r?.meta,kind=item.kind||'EQUITY';
 if(data.chart?.error||!m||m.symbol!==item.symbol||m.instrumentType!==kind)throw Error('Instrument niet bevestigd.');
 const pence=['GBp','GBX'].includes(m.currency),currency=pence?'GBP':kind==='INDEX'&&!m.currency?item.currency:m.currency;
 if(currency!==item.currency)throw Error('Valuta wijkt af.');
 const today=day(time,item.timezone),unit=pence?100:1,prices=r.indicators?.quote?.[0]?.close;
 if(!Array.isArray(r.timestamp)||!Array.isArray(prices)||r.timestamp.length>100)throw Error('Dagbars ongeldig.');
 const bars=[];
 for(let i=0;i<r.timestamp.length;i++){
  const stamp=Number(r.timestamp[i])*1000,d=day(stamp,item.timezone),close=prices[i]/unit;
  if(d>=today||!Number.isFinite(close)||close<=0||stamp>time||[0,6].includes(new Date(d+'T00:00:00Z').getUTCDay()))continue;
  if(bars.length&&d<=bars.at(-1).day)throw Error('Ongeordende dagbars.');
  const rate=fx.find(x=>x.date<=d&&x.rates[currency]);
  const volume=r.indicators?.quote?.[0]?.volume?.[i];if(kind==='EQUITY'&&volume===0)continue;
  bars.push({day:d,open_time:iso(stamp),close,volume:Number.isFinite(volume)&&volume>=0?volume:null,fx:rate&&dateMs(d)-dateMs(rate.date)<=4*86400000?rate.rates[currency]:null,fx_date:rate?.date||null});
 }
 if(bars.length<21||dateMs(today)-dateMs(bars.at(-1).day)>4*86400000)throw Error('Te weinig of verouderde slotkoersen.');
 const actions=[];
 for(const type of ['splits','dividends'])for(const x of Object.values(r.events?.[type]||{})){
  const t=Number(x.date)*1000;if(Number.isFinite(t)&&t<=time)actions.push({day:day(t,item.timezone),type});
 }
 return {symbol:item.symbol,bars,actions,observed_at:iso(time),latest:bars.at(-1),source:'Yahoo Finance dagelijkse indicatieve slotkoersen',
  price_unit:kind==='INDEX'?'index_points':currency,earnings:{status:'unknown',note:'Geen geverifieerde winstkalender beschikbaar; niet gebruikt als modelkenmerk.'}};
}
async function boundedRead(url,max,fetcher,budget){
 if(budget.requests>=P.max_requests||budget.bytes>=P.max_download_bytes)throw Error('Bronbudget bereikt.');budget.requests++;
 const r=await fetcher(url,{headers:{'User-Agent':'PaperLab/1.0 (bounded daily paper research)'},signal:AbortSignal.timeout(4000)});
 if(!r.ok)throw Error('Bron HTTP '+r.status);
 const reader=r.body.getReader(),chunks=[];let size=0;
 try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;budget.bytes+=value.byteLength;
  if(size>max||budget.bytes>P.max_download_bytes)throw Error('Bronantwoord overschrijdt budget.');chunks.push(value);}}
 finally{await reader.cancel().catch(()=>{});}
 const out=new Uint8Array(size);let at=0;for(const chunk of chunks){out.set(chunk,at);at+=chunk.length;}return new TextDecoder().decode(out);
}
export async function collectDaily({fetcher=fetch,now=Date.now,companies=DAILY_COMPANIES}={}){
 const started=now(),budget={requests:0,bytes:0},charts={},errors={};
 const fx=parseDailyFx(await boundedRead(DAILY_FX,300000,fetcher,budget));
 // All three context indices first; then alternate Europe / US to avoid a timeout
 // systematically dropping the last venue in an alphabetical catalogue.
 const eu=companies.filter(x=>!['XNYS','XNAS'].includes(x.exchange)),us=companies.filter(x=>['XNYS','XNAS'].includes(x.exchange));
 const items=[...DAILY_INDICES];for(let n=0;n<Math.max(eu.length,us.length);n++){if(eu[n])items.push(eu[n]);if(us[n])items.push(us[n]);}
 let cursor=0;
 async function worker(){while(cursor<items.length){const item=items[cursor++];
  if(now()-started>P.max_seconds*1000){errors[item.symbol]='Tijdbudget bereikt; geen verzonnen koers.';continue;}
  try{const raw=await boundedRead('https://query1.finance.yahoo.com/v8/finance/chart/'+encodeURIComponent(item.symbol)+'?interval=1d&range=3mo&events=div%2Csplits',P.max_response_bytes,fetcher,budget);
   charts[item.symbol]=parseDailyChart(JSON.parse(raw),item,fx,now());
  }catch(e){const text=String(e.message||'');errors[item.symbol]=/^(Bron HTTP [0-9]{3}|Instrument niet bevestigd\.|Valuta wijkt af\.|Te weinig of verouderde slotkoersen\.|Bronbudget bereikt\.|Bronantwoord overschrijdt budget\.)$/.test(text)?text:'Geen gevalideerde daggegevens.';}
 }}await Promise.all(Array.from({length:6},worker));return {charts,errors,...budget,checked_at:iso(now())};
}
export function dailyFeatures(chart){
 const b=chart.bars,p=b.at(-1).close,returns=b.slice(-21).slice(1).map((v,i)=>v.close/b.at(-21+i).close-1),mean=returns.reduce((a,b)=>a+b,0)/returns.length;
 return {return_1d:p/b.at(-2).close-1,return_5d:p/b.at(-6).close-1,return_20d:p/b.at(-21).close-1,
  volatility_20d:Math.sqrt(returns.reduce((s,x)=>s+(x-mean)**2,0)/returns.length)};
}
export function companyWeek(d){const t=new Date(d+'T00:00:00Z');t.setUTCDate(t.getUTCDate()-(t.getUTCDay()+6)%7);return t.toISOString().slice(0,10);}
function fee(config,item,gross,fx){const c=config.costs;return Math.max(gross*c.commission_rate,item.currency==='USD'?c.us_minimum_commission_usd/fx:c.other_minimum_commission_eur);}
function tob(c,g){return c.tax_enabled?Math.min(g*c.tax.transaction_tax_rate,c.tax.transaction_tax_cap_eur):0;}
export function dailyEntry(config,item,b){
 const price=b.close*1.001/b.fx,foreign=!['US','BE'].includes(item.country)?config.costs.foreign_buy_reserve_rate:0;
 const cost=g=>g+fee(config,item,g,b.fx)+tob(config,g)+g*foreign+(['TSM','TM'].includes(item.symbol)?g/price*config.costs.adr_buy_reserve_usd_per_share/b.fx:0);
 let lo=0,hi=100;for(let n=0;n<60;n++){const mid=(lo+hi)/2;if(cost(mid)>100)hi=mid;else lo=mid;}
 return {...b,price_eur:price,qty:lo/price,gross_eur:lo,commission_eur:fee(config,item,lo,b.fx),buy_costs_eur:100-lo,budget_eur:100};
}
export function dailyOutcome(config,item,entry,b){
 const price=b.close*.999/b.fx,gross=entry.qty*price,gain=Math.max(0,gross-entry.gross_eur),commission=fee(config,item,gross,b.fx),tax=tob(config,gross)+(config.tax_enabled?gain*config.tax.capital_gains_reserve_rate:0);
 return {status:'observed',day:b.day,known_at:null,close:b.close,fx:b.fx,fx_date:b.fx_date,net_eur:gross-commission-tax-100,
  stressed_net_eur:gross-2*commission-tax-100-entry.commission_eur-(entry.gross_eur+gross)*.001,
  gross_move_percent:100*(price/entry.price_eur-1),exit_costs_eur:commission+tax};
}
export async function stepDaily(input,batch,time=Date.now()){
 const records=[],updates=[],bars=[],quality=[],items=Object.fromEntries(DAILY_COMPANIES.map(x=>[x.symbol,x])),revised=new Set(),old=new Map((input.bars||[]).map(b=>[b.symbol+'|'+b.day,b.close]));
 for(const [symbol,c]of Object.entries(batch.charts)){
  for(const b of c.bars){const prior=old.get(symbol+'|'+b.day);if(prior!=null&&Math.abs(b.close/prior-1)>.00001)revised.add(symbol);}
  bars.push({symbol,...c.latest,session_starts:c.bars.filter(b=>symbol.startsWith('^')||b.volume>0).map(b=>Date.parse(b.open_time)/1000),observed_at:c.observed_at,actions:c.actions.filter(a=>a.day>=c.latest.day)});
 }
 for(const item of DAILY_COMPANIES){const c=batch.charts[item.symbol];quality.push({symbol:item.symbol,venue:item.exchange,status:!c?'missing':revised.has(item.symbol)?'revised':!c.latest.fx?'missing_fx':'usable',day:c?.latest.day||null,error:batch.errors[item.symbol]||null});}
 const active=input.active||[];
 for(const r of active){
  const c=batch.charts[r.symbol],item=items[r.symbol],patch={id:r.id},outcomes={...r.outcomes};let entry=r.entry,status=r.status,reason=r.reason;
  const aged=time-Date.parse(r.decision_at)>55*86400000;
  if(revised.has(r.symbol)){status='censored';reason='Bron heeft reeds vastgelegde slotkoersen herzien.';}
  else if(c){
   if(!entry&&c.latest.day>r.known_price_day&&Date.parse(c.latest.open_time)>Date.parse(r.decision_at)){
    // Never backfill an entry after an outage: it must be the first session in
    // the provider calendar after the actual recorded decision.
    const next=c.bars.find(b=>Date.parse(b.open_time)>Date.parse(r.decision_at));
    if(next?.day!==c.latest.day){status='censored';reason='Eerste toekomstige instapsessie gemist.';}
    else if(!c.latest.fx){status='censored';reason='Geen destijds geldige ECB-valutaomrekening.';}
    else {entry=dailyEntry(input.config,item,c.latest);entry.known_at=c.observed_at;status='following';}
   }
   if(entry&&status!=='censored'){
    const at=c.bars.findIndex(b=>b.day===entry.day),span=c.bars.filter(b=>b.day>=entry.day);
    const corporate=c.actions.some(a=>a.day>r.known_price_day&&a.day<=c.latest.day);
    if(corporate||at<0||span.some((b,i)=>i&&Math.abs(b.close/span[i-1].close-1)>.3)){
     status='censored';reason='Dividend, splitsing, ontbrekende instapbar of grote koerssprong vereist herbeoordeling.';
    }else for(const h of P.horizons){
     if(outcomes[h])continue;const target=c.bars[at+h];if(!target)continue;
     if(target.day!==c.latest.day||!target.fx)outcomes[h]={status:'missing',reason:'Doelsessie niet op tijd geobserveerd of FX ontbreekt.'};
     else outcomes[h]={...dailyOutcome(input.config,item,entry,target),known_at:c.observed_at,sessions:h};
    }
   }
  }
  if(aged&&status!=='complete'){status='censored';reason='Bewaar- en meettermijn verlopen; geen achteraf gekozen uitvoer.';}
  if(status==='censored')for(const h of P.horizons)if(!outcomes[h])outcomes[h]={status:'missing',reason};
  if(P.horizons.every(h=>outcomes[h]))status=status==='censored'?'censored':'complete';
  if(JSON.stringify({entry,status,reason,outcomes})!==JSON.stringify({entry:r.entry,status:r.status,reason:r.reason,outcomes:r.outcomes}))updates.push({...patch,entry,status,reason:reason||null,outcomes});
 }
 const room=Math.max(0,Math.min(input.max_new_records??0,P.max_active-active.length));
 for(const item of DAILY_COMPANIES){
  const c=batch.charts[item.symbol];if(!c||!c.latest.fx||revised.has(item.symbol)||records.length>=room)continue;
  const local=day(time,item.timezone),week=companyWeek(local),key=item.symbol+'|'+week;
  if((input.seen||[]).includes(key)||c.actions.some(a=>a.day>=c.bars.at(-21).day))continue;
  const context={};for(const idx of DAILY_INDICES){const source=batch.charts[idx.symbol];context[idx.symbol]=source&&source.latest.day<=c.latest.day&&dateMs(c.latest.day)-dateMs(source.latest.day)<=4*86400000?
   {day:source.latest.day,known_at:source.observed_at,return_5d:dailyFeatures(source).return_5d,price_index:true}:{status:'missing'};}
  const features=dailyFeatures(c),id='dy-'+(await digest(input.profile+'|'+key)).slice(0,24);
  records.push({id,profile:input.profile,symbol:item.symbol,venue:item.exchange,sector:item.sector,week,decision_day:local,decision_at:iso(time),known_price_day:c.latest.day,
   features,context,earnings:c.earnings,cohort:features.return_5d>.002?'positive_momentum':'other_control',status:'pending',entry:null,reason:null,outcomes:{},
   statement:'Eerste bruikbare bedrijf-weekwaarneming, zonder selectie op latere winst. Een toekomstige dagslotkoers vormt de hypothetische instap; uitkomsten na 1, 5 en 20 volgende bronsessies.'});
 }
 return {protocol:P.version,records,updates,bars,quality,checked_at:batch.checked_at,requests:batch.requests,download_bytes:batch.bytes,revised_symbols:[...revised]};
}

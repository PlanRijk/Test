import {day} from './engine.js';
import {sha} from './learner.js';
import {env} from './platform.js';
import {DAILY_COMPANIES,DAILY_INDICES} from './daily-catalogue.js';
import {HISTORY_IMPLEMENTATION_SHA} from './history-implementation.js';
export const HISTORY_PROTOCOL={version:'historical-day-v1',start:'2007-01-01',horizon:20,features:['return_1d','return_5d','return_20d','volatility_20d','log_relative_volume','sp500_5d','eurostoxx50_5d','bel20_5d'],
 implementation_sha256:HISTORY_IMPLEMENTATION_SHA,max_samples:8000,max_company_samples:48,threshold:.6,epochs:100,step:.08,l2:.01,max_models:1,max_snapshot_bytes:64000000,
 forward_per_day:20,max_forward_active:500,max_forward_records:10000,forward_days:60,forward_closes:300,
 limitations:['Historische simulaties zijn geen gesloten referentietrades.','De huidige bedrijfslijst bevat overlevings- en selectiebias.','Bronhistorie kan achteraf herzien of voor splitsingen aangepast zijn; geen volledig point-in-time archief.',
  'Huidige kosten en Belgische belastingreserves worden als vast scenario op oude prijzen toegepast.','Prijsrendement; dividendontvangsten krijgen conservatief nul netto krediet. Geen totaalrendement.','Geen automatische activatie in de hoofdportefeuille.']};
export const HISTORY_ITEMS=[...DAILY_INDICES,...DAILY_COMPANIES];
export function connections(){return [
 {id:'yahoo',role:'Historische en nieuwe indicatieve aandelenprijzen',status:'public_source'},
 {id:'ecb',role:'Gedateerde EUR-wisselkoersen',status:'public_source'},
 {id:'indices',role:'S&P 500, EURO STOXX 50 en BEL 20',status:'via_yahoo'},
 {id:'sec',role:'Publicatiedata van bedrijfs-, bestuurders- en fondsmeldingen; context, geen koopadvies',status:'public_source'},
 {id:'alpaca',role:'Optionele controle Amerikaanse historie; gratis IEX-feed heeft beperkte dekking',status:env('ALPACA_API_KEY')&&env('ALPACA_API_SECRET')?'configured':'credentials_required'},
 {id:'alphavantage',role:'Optionele prijscontrole; maximaal twee aanvragen per dag in deze toepassing',status:env('ALPHAVANTAGE_API_KEY')?'configured':'credentials_required'}
];}
export async function historyRead(url,{fetcher=fetch,max=1000000,headers={},timeout=12000}={}){
 const r=await fetcher(url,{headers:{'User-Agent':'PaperLab personal investment research paperlab@users.noreply.github.com',...headers},signal:AbortSignal.timeout(timeout)});
 if(!r.ok)throw Error('Bron HTTP '+r.status);
 const reader=r.body.getReader(),chunks=[];let n=0;
 try{while(true){const {done,value}=await reader.read();if(done)break;n+=value.byteLength;if(n>max)throw Error('Bronantwoord te groot.');chunks.push(value);}}finally{await reader.cancel().catch(()=>{});}
 const out=new Uint8Array(n);let offset=0;for(const c of chunks){out.set(c,offset);offset+=c.length;}return {text:new TextDecoder().decode(out),bytes:n};
}
export function parseHistoryFx(xml,cutoff){
 const columns=['USD','GBP','CHF','SEK','DKK','NOK'],rows=[];
 for(const m of xml.matchAll(/<Cube\s+time=['"]([0-9-]+)['"]>([\s\S]*?)<\/Cube>/g)){
  if(m[1]<'2006-12-20'||m[1]>=cutoff)continue;const rates={};
  for(const v of m[2].matchAll(/currency=['"]([A-Z]{3})['"]\s+rate=['"]([0-9.]+)['"]/g))if(columns.includes(v[1])&&Number(v[2])>0)rates[v[1]]=Number(v[2]);
  rows.push([m[1],...columns.map(k=>rates[k]||null)]);
 }if(rows.length<1000)throw Error('Onvoldoende historische FX.');return {columns,rows:rows.sort((a,b)=>a[0].localeCompare(b[0]))};
}
export function parseHistoryChart(data,item,cutoff){
 const r=data.chart?.result?.[0],m=r?.meta,kind=item.kind||'EQUITY';
 if(data.chart?.error||m?.symbol!==item.symbol||m.instrumentType!==kind)throw Error('Instrument niet bevestigd.');
 const pence=['GBp','GBX'].includes(m.currency),currency=pence?'GBP':kind==='INDEX'&&!m.currency?item.currency:m.currency;
 if(currency!==item.currency||!Array.isArray(r.timestamp)||r.timestamp.length>6500)throw Error('Ongeldige historie.');
 const timestamps=[],closes=[],volumes=[];
 for(let i=0;i<r.timestamp.length;i++){
  const stamp=r.timestamp[i]*1000,d=day(stamp,item.timezone),c=r.indicators?.quote?.[0]?.close?.[i]/(pence?100:1),v=r.indicators?.quote?.[0]?.volume?.[i];
  if(d<HISTORY_PROTOCOL.start||d>=cutoff||!(c>0&&Number.isFinite(c)))continue;
  if(timestamps.length&&stamp<=timestamps.at(-1)*1000)throw Error('Historie niet chronologisch.');
  timestamps.push(stamp/1000);closes.push(c);volumes.push(Number.isFinite(v)&&v>=0?v:null);
 }if(closes.length<100)throw Error('Onvoldoende geschiedenis.');
 const actions=[];for(const type of ['splits','dividends'])for(const e of Object.values(r.events?.[type]||{})){
  const d=day(e.date*1000,item.timezone);if(d>=HISTORY_PROTOCOL.start&&d<cutoff)actions.push({day:d,type});
 }
 return {symbol:item.symbol,currency,timezone:item.timezone,timestamps,closes,volumes,actions,price_unit:kind==='INDEX'?'index_points':currency};
}
export async function historyBase(cutoff,{fetcher=fetch}={}){
 const raw=await historyRead('https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist.xml',{fetcher,max:10000000});
 const fx=parseHistoryFx(raw.text,cutoff);let mapping={},mapStatus='unavailable',bytes=raw.bytes;
 try{const map=await historyRead('https://www.sec.gov/files/company_tickers.json',{fetcher,max:1500000});bytes+=map.bytes;
  for(const x of Object.values(JSON.parse(map.text)))mapping[x.ticker]=String(x.cik_str).padStart(10,'0');mapStatus='available';}catch{}
 const data={fx,mapping,map_status:mapStatus,cutoff,source_checked_at:new Date().toISOString(),fx_raw_hash:await sha(raw.text)};
 return {symbol:'__base__',status:'available',data,hash:await sha(data),source_bytes:bytes};
}
export async function historyBatch(symbols,cutoff,{fetcher=fetch}={}){
 const rows=[];let cursor=0;const items=Object.fromEntries(HISTORY_ITEMS.map(x=>[x.symbol,x]));
 async function worker(){while(cursor<symbols.length){const symbol=symbols[cursor++],item=items[symbol];try{
  if(!item)throw Error('Onbekend instrument.');const url='https://query1.finance.yahoo.com/v8/finance/chart/'+encodeURIComponent(symbol)+'?interval=1d&period1='+Date.parse(HISTORY_PROTOCOL.start+'T00:00:00Z')/1000+'&period2='+Date.parse(cutoff+'T00:00:00Z')/1000+'&events=div%2Csplits';
  const raw=await historyRead(url,{fetcher,max:1000000}),data=parseHistoryChart(JSON.parse(raw.text),item,cutoff);
  const tail={...data,timestamps:data.timestamps.slice(-25),closes:data.closes.slice(-25),volumes:data.volumes.slice(-25),actions:data.actions.filter(a=>a.day>=day(Date.now()-50*86400000,item.timezone))};
  rows.push({symbol,status:'available',data,tail,hash:await sha(data),raw_hash:await sha(raw.text),source_bytes:raw.bytes});
 }catch(e){const message=String(e.message);rows.push({symbol,status:'unavailable',data:{reason:/^Bron HTTP \d{3}$/.test(message)?message:'Geen gevalideerde historie.'},hash:null,source_bytes:0});}}}
 await Promise.all(Array.from({length:4},worker));return rows;
}
export async function publicContext(base,symbols,{fetcher=fetch,time=Date.now()}={}){
 const reports=[],targets=[{symbol:'BERKSHIRE_13F',cik:'0001067983'},...symbols.map(symbol=>({symbol,cik:base.mapping?.[symbol]})).filter(x=>x.cik).slice(0,2)];
 for(const target of targets)try{
  const raw=await historyRead('https://data.sec.gov/submissions/CIK'+target.cik+'.json',{fetcher,max:1000000}),data=JSON.parse(raw.text),r=data.filings?.recent||{},filings=[];
  for(let i=0;i<(r.form||[]).length&&filings.length<6;i++){
   if(!(target.symbol==='BERKSHIRE_13F'?['13F-HR','13F-HR/A']:['4','4/A','8-K','10-Q','10-K']).includes(r.form[i]))continue;
   const accepted=r.acceptanceDateTime?.[i],stamp=Date.parse(accepted);if(!Number.isFinite(stamp)||stamp>time)continue;
   filings.push({form:r.form[i],filed:r.filingDate[i],accepted_at:new Date(stamp).toISOString(),accession:r.accessionNumber[i],
    url:'https://www.sec.gov/Archives/edgar/data/'+Number(target.cik)+'/'+r.accessionNumber[i].replaceAll('-','')+'/'+encodeURIComponent(r.primaryDocument[i])});
  }
  reports.push({source:'SEC',symbol:target.symbol,status:'available',known_at:new Date(time).toISOString(),issuer:data.name,filings,
   note:'Meldingen, geen gereconstrueerde koop-verkoopreeks. Form 4 kan ook beloning of schenking melden; 13F toont vertraagde kwartaalposities.'});
 }catch(e){reports.push({source:'SEC',symbol:target.symbol,status:'unavailable',known_at:new Date(time).toISOString(),note:/^Bron HTTP \d{3}$/.test(e.message)?e.message:'Bron niet beschikbaar.'});}
 return reports;
}
export async function optionalChecks({fetcher=fetch,time=Date.now()}={}){
 const rows=[];
 if(env('ALPACA_API_KEY')&&env('ALPACA_API_SECRET'))try{
  const raw=await historyRead('https://data.alpaca.markets/v2/stocks/AAPL/bars?timeframe=1Day&limit=5&feed=iex&sort=desc',{fetcher,headers:{'APCA-API-KEY-ID':env('ALPACA_API_KEY'),'APCA-API-SECRET-KEY':env('ALPACA_API_SECRET')}});
  const bars=JSON.parse(raw.text).bars;if(!Array.isArray(bars))throw Error('Geen brondata.');rows.push({source:'Alpaca',status:'available',known_at:new Date(time).toISOString(),feed:'IEX',bars:bars.slice(0,5).map(b=>({time:b.t,close:b.c})),note:'Andere venue; afwijking is geen bewijs dat een bron fout is.'});
 }catch{rows.push({source:'Alpaca',status:'unavailable'});}
 if(env('ALPHAVANTAGE_API_KEY'))try{
  const raw=await historyRead('https://www.alphavantage.co/query?function=TIME_SERIES_DAILY&symbol=AAPL&outputsize=compact&apikey='+encodeURIComponent(env('ALPHAVANTAGE_API_KEY')),{fetcher});
  const data=JSON.parse(raw.text)['Time Series (Daily)'];if(!data)throw Error('Geen brondata.');rows.push({source:'Alpha Vantage',status:'available',known_at:new Date(time).toISOString(),bars:Object.entries(data).slice(0,5).map(([date,b])=>({date,close:Number(b['4. close'])})),note:'Afzonderlijke broncontrole; niet als extra onafhankelijk trainingsvoorbeeld geteld.'});
 }catch{rows.push({source:'Alpha Vantage',status:'unavailable'});}
 return rows;
}

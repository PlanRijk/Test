import {currency,purchase,sale,fx} from './engine.js';

const MACRO={vix:['VIX','indexpunten',5],creditspread:['High-yield kredietopslag','procentpunten',5],yieldcurve:['10 jaar min 3 maanden','procentpunten',5],conditions:['Chicago Fed financiële condities','indexeenheden',14]};
const clean=s=>String(s||'').replace(/<[^>]*>/g,' ').replace(/\s+/g,' ').trim();
function xmlText(value){return clean(value).replace(/&(?:amp|lt|gt|quot|apos);/g,m=>({'&amp;':'&','&lt;':'<','&gt;':'>','&quot;':'"','&apos;':"'"}[m])).slice(0,240);}

export function parseIndicator(text,id,time){
 const descriptor=MACRO[id];if(!descriptor)throw Error('Unknown indicator');
 let latest;
 for(const line of text.trim().split(/\r?\n/).slice(1)){
  const [date,value]=line.trim().split(',');if(!/^\d{4}-\d{2}-\d{2}$/.test(date)||!value||value==='.')continue;
  const stamp=Date.parse(date+'T00:00:00Z'),n=Number(value);
  if(!Number.isFinite(stamp)||new Date(stamp).toISOString().slice(0,10)!==date||!Number.isFinite(n)||stamp>time)continue;
  if(!latest||date>latest.date)latest={date,value:n};
 }
 if(!latest)throw Error('No dated observation');
 const age=Math.floor((time-Date.parse(latest.date+'T00:00:00Z'))/86400000);
 return {...latest,label:descriptor[0],unit:descriptor[1],age_days:age,stale:age>descriptor[2],
  publication_time_verified:false,note:'Vertraagde context; observatiedatum is geen bewezen eerste publicatiemoment of crashkans.'};
}

export function parseHeadlines(text){
 return [...text.matchAll(/<item\b[^>]*>([\s\S]*?)<\/item>/gi)].slice(0,3).map(m=>({
  title:xmlText((m[1].match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1]||'').replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g,'$1')),
  published:xmlText(m[1].match(/<pubDate[^>]*>([\s\S]*?)<\/pubDate>/i)?.[1]||''),
 })).filter(x=>x.title);
}

async function limitedText(response,limit=131072){
 const reader=response.body?.getReader();if(!reader)return '';
 let size=0;const chunks=[];
 try{while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>limit)throw Error('Response too large');chunks.push(value);}}
 finally{await reader.cancel();}
 const all=new Uint8Array(size);let offset=0;for(const c of chunks){all.set(c,offset);offset+=c.length;}
 return new TextDecoder().decode(all);
}

export async function inspectSources(sources,{previous=[],time=Date.now(),fetcher=fetch}={}){
 const rows=[],old=new Map(previous.map(x=>[x.id,x]));let index=0;
 async function worker(){while(index<sources.length){
  const source=sources[index++],cached=old.get(source.id),dynamic=['rss','fred_csv'].includes(source.kind);
  if(!dynamic&&cached?.status==='reachable'&&time-Date.parse(cached.checked_at)>=0&&time-Date.parse(cached.checked_at)<604800000){rows.push({...cached,cached:true});continue;}
  const row={id:source.id,url:source.url,checked_at:new Date(time).toISOString(),status:'unavailable',read_mode:dynamic?'bounded_content':'metadata_only'};
  try{
   const url=new URL(source.url);
   if(source.kind==='fred_csv')url.searchParams.set('cosd',new Date(time-120*86400000).toISOString().slice(0,10));
   const response=await fetcher(url.href,{headers:{'User-Agent':'PaperLab/1.0 (personal source review)'},signal:AbortSignal.timeout(5000),redirect:'manual'});
   row.http=response.status;row.content_type=response.headers.get('Content-Type');
   if(response.ok){
    row.status='reachable';row.last_modified=response.headers.get('Last-Modified');
    if(dynamic){
     const text=await limitedText(response);
     if(source.kind==='fred_csv')row.indicator=parseIndicator(text,source.id,time);
     else row.headlines=parseHeadlines(text);
    }else if(response.body)await response.body.cancel();
   }else if(response.body)await response.body.cancel();
  }catch{row.status='unavailable';row.failure='Bron niet bereikbaar of inhoud niet geldig binnen het begrensde formaat.';}
  rows.push(row);
 }}
 await Promise.all(Array.from({length:4},worker));return rows.sort((a,b)=>a.id.localeCompare(b.id));
}

export function costScenario(s,symbol,budget=100){
 const c=currency(symbol),rate=c==='EUR'?1:s.data_info?.fx?.rates?.[c]||(c==='USD'?s.usd_per_eur:0);
 if(!Number.isFinite(rate)||rate<=0)return null;
 const mid=100/rate,entry=mid*1.0005*1.0005,buy=purchase(s,symbol,entry,budget);
 const p={qty:buy.qty,cost:budget,entry,entry_gross_eur:buy.qty*entry};
 const sellPrice=value=>value*.9995*.9995;
 const flat=-sale(s,symbol,p,sellPrice(mid)).net_pnl_eur,minimum=s.belgian_tax.config.minimum_net_profit_eur;
 let lo=mid,hi=mid*1.1;for(let i=0;i<20&&sale(s,symbol,p,sellPrice(hi)).net_pnl_eur<minimum;i++)hi*=1.2;
 for(let i=0;i<60;i++){const value=(lo+hi)/2;if(sale(s,symbol,p,sellPrice(value)).net_pnl_eur<minimum)lo=value;else hi=value;}
 return {symbol,currency:c,budget_eur:budget,hypothetical_price_local:100,flat_round_trip_loss_eur:flat,
  required_move_percent:(hi/mid-1)*100,minimum_net_profit_eur:minimum,assumed_total_spread_bps:10,slippage_bps_each_side:5,
  note:'Hypothetische koers van 100 lokale valuta-eenheden; proefcommissie, spread/slippage en belastingreserves, geen geverifieerd brokertarief.'};
}

export function diagnose(portfolio,input){
 const s=portfolio.state,trades=input.trades||[],quality=input.quality||[],versions={};
 for(const t of trades){
  const key=(t.strategy_version||'momentum-v1')+' / '+(t.transport_version||'legacy')+' / '+(t.model_id||'baseline');
  const v=versions[key]||={actions:0,closed_positions:0,realized_eur:0};v.actions++;
  if(t.side==='verkoop'){v.closed_positions++;v.realized_eur+=t.pnl;}
 }
 const managed=trades.filter(t=>t.transport_version==='supabase-v1'),closed=managed.filter(t=>t.side==='verkoop');
 let costs=0;for(const t of managed){const tax=t.tax_detail||{};costs+=t.fee+['transaction_tax_eur','capital_gains_reserve_eur','foreign_tax_reserve_eur','adr_reserve_eur'].reduce((n,k)=>n+(tax[k]||0),0);}
 const venues={};let attempts=0,expected=0,fresh=0,failures=0;
 for(const d of quality){attempts+=d.rounds;expected+=d.expected;fresh+=d.fresh;failures+=d.failures;
  for(const [k,v] of Object.entries(d.venues||{})){venues[k]||={expected:0,fresh:0};venues[k].expected+=v.expected;venues[k].fresh+=v.fresh;}}
 for(const v of Object.values(venues))v.fresh_percent=v.expected?100*v.fresh/v.expected:null;
 let exitCosts=0,liquidationAvailable=true;
 for(const [k,p] of Object.entries(s.positions))try{const price=s.prices[k]/fx(s,k);if(!Number.isFinite(price)||price<=0)throw Error();const result=sale(s,k,p,price);exitCosts+=['commission_eur','transaction_tax_eur','capital_gains_reserve_eur','foreign_tax_reserve_eur','adr_reserve_eur'].reduce((n,x)=>n+(result[x]||0),0);}catch{liquidationAvailable=false;}
 const latencies=managed.map(t=>(Date.parse(t.time)-Date.parse(t.decision_time))/1000).filter(x=>Number.isFinite(x)&&x>=0).sort((a,b)=>a-b);
 const quoteAges=managed.map(t=>(Date.parse(t.time)-Date.parse(t.quote_time))/1000).filter(x=>Number.isFinite(x)&&x>=0);
 const proposals=['Bewaar de huidige regels als baseline; wijzig geen parameters op basis van deze kleine proef.','Vergelijk toekomstige varianten op dezelfde gegevens, in EUR en na alle kosten; registreer ook mislukte varianten.'];
 if(expected&&fresh/expected<.9)proposals.push('Verbeter datadekking voordat je verschillen tussen beurzen aan de strategie toeschrijft.');
 if(managed.length)proposals.push('Controleer nettoresultaat en handelskosten per gesloten positie; frequent handelen moet aantoonbaar zijn kosten terugverdienen.');
 return {versions,managed_actions:managed.length,managed_closes:closed.length,managed_realized_eur:closed.reduce((n,t)=>n+t.pnl,0),
  profitable_managed_closes:closed.filter(t=>t.pnl>0).length,managed_costs_and_reserves_eur:costs,
  equity_eur:portfolio.equity,cost_adjusted_liquidation_estimate_eur:liquidationAvailable?portfolio.equity-exitCosts:null,
  liquidation_note:'Waardering op laatst bekende prijzen met geschatte verkoopkosten; geen actuele uitvoeringsgarantie.',
  median_decision_to_fill_seconds:latencies.length?(latencies[Math.floor((latencies.length-1)/2)]+latencies[Math.floor(latencies.length/2)])/2:null,
  max_execution_quote_age_seconds:quoteAges.length?Math.max(...quoteAges):null,stale_execution_count:quoteAges.filter(x=>x>120).length,
  coverage:{recorded_days:quality.length,rounds:attempts,expected,fresh,failed_rounds:failures,fresh_percent:expected?100*fresh/expected:null,venues,
   note:'Aggregatie start bij installatie; gesloten markten tellen niet als ontbrekende koersen. Geen teruggerekende dekking.'},
  cost_scenarios:['AAPL','KBC.BR','SAP.DE','TSM'].map(k=>costScenario(s,k)).filter(Boolean),
  cash_baseline_return_percent:0,profitability_proven:false,annualized_sharpe:null,
  sample_note:'Een maand of enkele transacties bewijst geen blijvend handelsvoordeel; er is geen gecorrigeerde significantietoets uitgevoerd.',proposals};
}

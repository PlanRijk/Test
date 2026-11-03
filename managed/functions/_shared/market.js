import {COMPANIES} from './catalogue.js';
import {possibleSession,day,validQuote} from './engine.js';
export const ECB='https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml';
const YAHOO='https://query1.finance.yahoo.com/v8/finance/chart/';
export function parseEcb(xml,time) {
  const date=xml.match(/time=['"]([0-9-]+)['"]/)?.[1];
  const age=(Date.parse(day(time)+'T00:00Z')-Date.parse(date+'T00:00Z'))/86400000;
  if(!date||!Number.isFinite(age)||age<0||age>4)throw Error('ECB-datum ontbreekt of is verlopen.');
  const rates={EUR:1};for(const m of xml.matchAll(/currency=['"]([A-Z]{3})['"]\s+rate=['"]([0-9.]+)['"]/g)){const rate=Number(m[2]);if(!Number.isFinite(rate)||rate<=0)throw Error('Ongeldige FX.');rates[m[1]]=rate;}
  if(!rates.USD)throw Error('ECB USD-referentie ontbreekt.');return {date,rates,usd_per_eur:rates.USD,source:'ECB dagelijkse referentie; geen uitvoerbare FX'};
}
export function parseYahoo(data,item,fx,time) {
  if(data.chart?.error)throw Error('Bronfout.');const m=data.chart?.result?.[0]?.meta;
  if(!m||m.symbol!==item.symbol||(m.instrumentType&&m.instrumentType!=='EQUITY'))throw Error('Onjuist instrument.');
  const c=['GBp','GBX'].includes(m.currency)?'GBP':m.currency,price=Number(m.regularMarketPrice)/(['GBp','GBX'].includes(m.currency)?100:1);
  if(c!==item.currency||!Number.isFinite(price)||price<=0)throw Error('Onjuiste koers of valuta.');
  const regular=m.currentTradingPeriod?.regular;if(!regular)throw Error('Beurssessie ontbreekt.');
  const start=regular.start*1000,end=regular.end*1000,stamp=m.regularMarketTime*1000;
  if(time<start||time>=end)return null;
  if(m.exchangeDataDelayedBy!==undefined&&m.exchangeDataDelayedBy!==null&&m.exchangeDataDelayedBy!==0)throw Error('Bron meldt vertraging.');
  if(!Number.isFinite(stamp)||stamp<start||time-stamp<0||time-stamp>120000)throw Error('Koers ouder dan 120 seconden of ongeldig.');
  const q={bid:price*.9995,ask:price*1.0005,time:new Date(stamp).toISOString(),currency:c,fx_per_eur:fx.rates[c],fx_date:fx.date,original_unit:m.currency,
    session_start:new Date(start).toISOString(),session_end:new Date(end).toISOString(),source:'Yahoo Finance',indicative:true,assumed_spread_bps:10,provider_delay_minutes:m.exchangeDataDelayedBy??null,delay_seconds:(time-stamp)/1000,exchange:item.exchange};
  if(!validQuote(item.symbol,q,time))throw Error('Geen uitvoerbare actuele paperquote.');return q;
}
async function read(url,type,fetcher,timeout=5000) {
  const response=await fetcher(url,{headers:{'User-Agent':'PaperLab/1.0 (personal paper-trading experiment)'},signal:AbortSignal.timeout(timeout)});
  if(!response.ok)throw Error(`Bron HTTP ${response.status}`);const text=await response.text();if(text.length>1000000)throw Error('Bronantwoord te groot.');return type==='json'?JSON.parse(text):text;
}
export async function fetchMarket(state,{now=Date.now,fetcher=fetch}={}) {
  const started=now(),active=COMPANIES.filter(x=>state.universe.includes(x.symbol)&&possibleSession(x,started));
  const batch={quotes:{},errors:{},expected_open:active.map(x=>x.symbol),closed_symbols:state.universe.filter(k=>!active.some(x=>x.symbol===k)),fx:null};
  if(!active.length){batch.error='Buiten mogelijke reguliere beursuren.';return batch;}
  batch.fx=parseEcb(await read(ECB,'text',fetcher),now());let index=0;
  async function worker(){while(index<active.length){const item=active[index++];
    if(now()-started>55000){batch.errors[item.symbol]='Tijdbudget van de batch bereikt.';continue;}
    try{const data=await read(YAHOO+encodeURIComponent(item.symbol)+'?interval=5m&range=1d','json',fetcher);const q=parseYahoo(data,item,batch.fx,now());
      if(q)batch.quotes[item.symbol]=q;else{batch.closed_symbols.push(item.symbol);batch.expected_open=batch.expected_open.filter(k=>k!==item.symbol);}}
    catch{batch.errors[item.symbol]='Geen verse gevalideerde koers beschikbaar.';}
  }}
  await Promise.all(Array.from({length:6},worker));const completed=now();
  for(const[k,q]of Object.entries(batch.quotes))if(!validQuote(k,q,completed)){delete batch.quotes[k];batch.errors[k]='Koers tijdens batch verlopen.';}
  return batch;
}

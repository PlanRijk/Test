// Transport optimization only. The frozen parser, timestamps, freshness gate,
// currency checks, sessions and paper execution rules remain authoritative.
import {fetchMarket} from './market.js';
export const COMPACT_TRANSPORT='yahoo-current-meta-compact-v1';
export async function fetchCompactMarket(state,{now=Date.now,fetcher=fetch}={}){
 let requests=0;
 const compactFetcher=async(url,options)=>{
  const target=new URL(url);
  if(target.protocol==='https:'&&target.hostname==='query1.finance.yahoo.com'&&target.pathname.startsWith('/v8/finance/chart/')){
   // Only meta.regularMarketPrice/Time are consumed by parseYahoo. Candle
   // resolution is unrelated to the age of these current quote fields.
   target.searchParams.set('interval','1d');requests++;
  }
  return fetcher(target.href,options);
 };
 const batch=await fetchMarket(state,{now,fetcher:compactFetcher});
 batch.transport={version:COMPACT_TRANSPORT,price_fields:'meta.regularMarketPrice and meta.regularMarketTime',candle_interval:'1d',candles_used_for_orders:false,requests,refresh_cadence_seconds:300};
 for(const q of Object.values(batch.quotes))q.transport_variant=COMPACT_TRANSPORT;
 return batch;
}

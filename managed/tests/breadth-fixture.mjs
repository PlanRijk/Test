// Synthetic local-test inputs only. Never import into the production project.
import {DAILY_COMPANIES,DAILY_INDICES} from '../functions/_shared/daily-catalogue.js';
import {HISTORY_PROTOCOL} from '../functions/_shared/history-data.js';
import {sha} from '../functions/_shared/learner.js';
export const TEST_CONFIG={costs:{commission_rate:.0005,us_minimum_commission_usd:1,other_minimum_commission_eur:1,foreign_buy_reserve_rate:.005,adr_buy_reserve_usd_per_share:.03},tax_enabled:true,tax:{transaction_tax_rate:.0035,transaction_tax_cap_eur:1600,capital_gains_reserve_rate:.1}};
export async function breadthFixture(time=Date.parse('2026-11-04T06:25:00Z')){
 const date=new Date(time).toISOString().slice(0,10),times=[];let t=Date.parse(date+'T14:30:00Z')-86400000;
 while(times.length<45){if(![0,6].includes(new Date(t).getUTCDay()))times.unshift(t);t-=86400000;}
 const symbols=DAILY_COMPANIES.filter(x=>!['COFB.BR','TSM','TM'].includes(x.symbol)).map(x=>x.symbol),rates={EUR:1,USD:1.1,GBP:.85,CHF:.95,DKK:7.46,SEK:11,NOK:11.6};
 const artifact={id:'hm-'+'1'.repeat(24),protocol:HISTORY_PROTOCOL.version,feature_names:HISTORY_PROTOCOL.features,algorithm:'fixed-day-logit-v1',mean:Array(8).fill(0),scale:Array(8).fill(1),weights:Array(8).fill(0),bias:0,
  prior:.3,threshold:.6,symbols,created_at:new Date(time-365*86400000).toISOString(),fingerprint:'f'.repeat(64),dataset_hash:'a'.repeat(64),automatic_trading_approval:false,offline_pass:false};
 artifact.integrity_hash=await sha(artifact);
 const bars=[...DAILY_INDICES,...DAILY_COMPANIES].flatMap(item=>times.map((stamp,i)=>[item.symbol,new Date(stamp).toISOString().slice(0,10),stamp,100+i*.01,100000,rates[item.currency],new Date(stamp).toISOString().slice(0,10),time-60000,i===times.length-1?times.map(t=>t/1000):null,false]));
 return {artifact,config:TEST_CONFIG,reference_implementation:HISTORY_PROTOCOL.implementation_sha256,bars,tails:[],active:[],reference_symbols:symbols.slice(0,20),seen:[],revised_symbols:[],max_new:150,max_details:40};
}

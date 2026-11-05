// Synthetic market and empty ledgers for local tests only.
import fs from 'node:fs';
import {BY_SYMBOL} from '../functions/_shared/catalogue.js';
import {CAPITAL_POLICY,initialCapital,stepCapital} from '../functions/_shared/capital-study.js';
import {CAPITAL_IMPLEMENTATION_SHA} from '../functions/_shared/capital-implementation.js';
import {learningFingerprint} from '../functions/_shared/learning-runtime.js';
export const CAPITAL_TEST_TIME=Date.parse('2026-11-03T15:00:00Z');
export async function capitalFixture(symbols=['AAPL'],time=CAPITAL_TEST_TIME){
 const market=JSON.parse(fs.readFileSync(new URL('./python-fixtures.json',import.meta.url))).state;market.positions={};market.pending=[];market.cash=500;market.fees=0;market.realized=0;market.peak=500;market.max_drawdown=0;market.operation_mode='continuous';market.running=true;
 market.risk={...market.risk,day:'2026-11-03',day_start_equity:500,daily_halted:false,global_halted:false,buys_today:0,previous_quotes:{},cooldowns:{}};
 const rates={USD:1.1,EUR:1,GBP:.85,CHF:.95,DKK:7.46,SEK:11,NOK:11.6},batch={quotes:{},expected_open:symbols,closed_symbols:[],errors:{},fx:{usd_per_eur:1.1,date:'2026-11-03',rates}};
 for(const k of symbols){const item=BY_SYMBOL[k],mid=100,rate=rates[item.currency];market.prices[k]=mid;market.price_fx[k]=rate;market.history[k]=Array.from({length:5},(_,i)=>({time:new Date(time-(5-i)*300000).toISOString(),price:mid*(.994+i*.0006),quote_time:new Date(time-(5-i)*300000-1000).toISOString()}));
 batch.quotes[k]={bid:mid*.9995,ask:mid*1.0005,time:new Date(time-1000).toISOString(),currency:item.currency,fx_per_eur:rate,session_start:'2026-11-03T07:00:00Z',session_end:'2026-11-03T21:00:00Z',indicative:true};}
 const policy={...CAPITAL_POLICY,implementation_sha256:CAPITAL_IMPLEMENTATION_SHA,reference_fingerprint:await learningFingerprint(market)},state=initialCapital(market,time);
 return {market,batch,policy,state,revision:1,allow_entries:true,time};
}

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {fill,tick,equity,profitTarget,sale,possibleSession,validQuote,HISTORY_LIMIT} from '../functions/_shared/engine.js';
import {parseEcb,parseYahoo,fetchMarket} from '../functions/_shared/market.js';
import {BY_SYMBOL,COMPANIES} from '../functions/_shared/catalogue.js';
const fixture=JSON.parse(fs.readFileSync(new URL('./python-fixtures.json',import.meta.url))),NOW=Date.parse('2026-11-03T15:00:00Z');
const clone=x=>structuredClone(x),close=(a,b)=>assert.ok(Math.abs(a-b)<1e-7,`${a} != ${b}`);
function state(k){const s=clone(fixture.state);s.multi_market.entry_symbols=[k];s.multi_market.expected_open=[k];s.run_until='2026-11-06T21:00:00Z';return s;}
function order(k,side,time=NOW-300000,risk_exit=false){return {symbol:k,side,time:new Date(time).toISOString(),reason:'synthetic fixture',risk_exit};}
const sink=()=>({trades:[],events:[]});
for(const row of fixture.cases)test('Python parity: '+row.symbol,()=>{
  const s=state(row.symbol),out=sink();assert.equal(fill(s,order(row.symbol,'koop'),row.buy_quote,NOW,out),true);
  const p=s.positions[row.symbol];assert.ok(p);for(const key of ['qty','cost','entry','entry_gross_eur','stop','target'])close(p[key],row.expected.position[key]);
  close(s.cash,row.expected.buycash);close(s.fees,row.expected.buyfees);
  assert.equal(fill(s,order(row.symbol,'verkoop',NOW),row.sell_quote,NOW+300000,out),true);
  assert.equal(Object.keys(s.positions).length,0);for(const key of ['cash','fees','realized'])close(s[key],row.expected[key]);
  for(const key of ['transaction_tax_eur','capital_gains_reserve_eur'])close(s.belgian_tax[key],row.expected.belgian_tax[key]);
  for(const key of ['foreign_tax_reserve_eur','adr_reserve_eur'])close(s.multi_market[key],row.expected.multi_market[key]);
  assert.equal(out.trades.length,2);assert.equal(out.trades[1].snapshot.currency,BY_SYMBOL[row.symbol].currency);
});
const eur=fixture.cases.find(x=>x.symbol==='KBC.BR');
test('same quote, stale quote, bad FX and crossed prices cannot fill',()=>{
 for(const q of [{...eur.buy_quote,time:new Date(NOW-300000).toISOString()},{...eur.buy_quote,time:new Date(NOW-121000).toISOString()},{...eur.buy_quote,fx_per_eur:1.1},{...eur.buy_quote,bid:120}]){
  const s=state('KBC.BR');assert.equal(fill(s,order('KBC.BR','koop'),q,NOW,sink()),false);assert.equal(s.cash,500);
 }
});
test('pending buy can fill without counting its own sector twice',()=>{
 const s=state('KBC.BR'),o=order('KBC.BR','koop');s.pending=[o];
 assert.equal(fill(s,o,eur.buy_quote,NOW,sink()),true);assert.ok(s.positions['KBC.BR']);
});
test('ordinary low-net sale blocked, protective exit allowed',()=>{
 const s=state('KBC.BR'),out=sink();fill(s,order('KBC.BR','koop'),eur.buy_quote,NOW,out);
 const q={...eur.sell_quote,bid:102,ask:102.1};fill(s,order('KBC.BR','verkoop',NOW),q,NOW+300000,out);assert.ok(s.positions['KBC.BR']);
 fill(s,order('KBC.BR','verkoop',NOW,true),q,NOW+300000,out);assert.equal(Object.keys(s.positions).length,0);assert.ok(s.realized<0);
});
test('EUR position valuation independent of USD and profit floor unchanged',()=>{
 const s=state('KBC.BR');fill(s,order('KBC.BR','koop'),eur.buy_quote,NOW,sink());const value=equity(s);s.usd_per_eur=2;close(equity(s),value);
 const p=s.positions['KBC.BR'];assert.ok(sale(s,'KBC.BR',p,profitTarget(s,'KBC.BR',p)).net_pnl_eur>=.01-1e-7);
});
test('European sessions open before US; DST and weekends',()=>{
 const morning=Date.parse('2026-11-03T09:00:00Z');assert.equal(possibleSession(BY_SYMBOL['KBC.BR'],morning),true);assert.equal(possibleSession(BY_SYMBOL.AAPL,morning),false);
 assert.equal(possibleSession(BY_SYMBOL.AAPL,Date.parse('2026-07-06T13:30:00Z')),true);
 assert.equal(possibleSession(BY_SYMBOL['KBC.BR'],Date.parse('2026-11-07T10:00:00Z')),false);
});
test('every instrument has an explicit timezone and US session boundaries follow DST',()=>{
 for(const item of COMPANIES)assert.ok(item.timezone, item.symbol+' timezone missing');
 for(const [stamp,open] of [['2026-11-03T14:29:59Z',false],['2026-11-03T14:30:00Z',true],['2026-11-03T19:45:00Z',true],['2026-11-03T21:00:00Z',false],['2026-07-06T13:29:59Z',false],['2026-07-06T13:30:00Z',true],['2026-07-06T20:00:00Z',false]])assert.equal(possibleSession(BY_SYMBOL.AAPL,Date.parse(stamp)),open,stamp);
 for(const [stamp,open] of [['2026-11-03T07:59:59Z',false],['2026-11-03T08:00:00Z',true],['2026-11-03T16:29:59Z',true],['2026-11-03T16:30:00Z',false]])assert.equal(possibleSession(BY_SYMBOL['KBC.BR'],Date.parse(stamp)),open,stamp);
 assert.throws(()=>possibleSession({...BY_SYMBOL.AAPL,timezone:undefined},NOW));
});
test('late US session fetch covers all 53 US listings and reports provider refusal without stale coverage',async()=>{
 const time=Date.parse('2026-11-03T19:45:00Z'),s=state('AAPL');s.universe=COMPANIES.map(x=>x.symbol);
 const batch=await fetchMarket(s,{now:()=>time,fetcher:async url=>url.includes('ecb.europa.eu')?new Response('<Cube time="2026-11-03"><Cube currency="USD" rate="1.1"/></Cube>'):new Response('',{status:429})});
 assert.equal(batch.expected_open.length,53);assert.ok(batch.expected_open.includes('AAPL'));assert.equal(Object.keys(batch.errors).length,53);assert.equal(batch.errors.AAPL,'Bron HTTP 429');
 const out=tick(s,batch,time);assert.equal(out.state.data_info.fresh_symbols,0);assert.equal(out.state.data_info.checked_at,new Date(time).toISOString());assert.equal(out.trades.length,0);assert.equal(out.observations.length,0);
});
test('missing held fresh quote blocks additional buys; immutable input',()=>{
 const s=state('KBC.BR');fill(s,order('KBC.BR','koop'),eur.buy_quote,NOW,sink());s.multi_market.expected_open=['KBC.BR','AAPL'];
 const apple=fixture.cases.find(x=>x.symbol==='AAPL').sell_quote,original=JSON.stringify(s);
 const out=tick(s,{quotes:{AAPL:apple},expected_open:['KBC.BR','AAPL'],closed_symbols:[],fx:{usd_per_eur:1.1,date:'2026-11-03'}},NOW+300000);
 assert.equal(out.state.risk.data_complete,false);assert.equal(out.trades.length,0);assert.equal(JSON.stringify(s),original);
 assert.deepEqual(out.quality.venues.XBRU,{expected:1,fresh:0});assert.deepEqual(out.quality.venues.XNAS,{expected:1,fresh:1});
});
test('pause and hard trial deadline prevent fresh orders',()=>{
 const s=state('KBC.BR');s.running=false;assert.equal(tick(s,{},NOW).state.tick,s.tick);
 s.running=true;s.run_until=new Date(NOW-1).toISOString();const out=tick(s,{},NOW);assert.equal(out.state.running,false);assert.equal(out.trades.length,0);
});
test('rolling history remains bounded without losing the six signal samples',()=>{
 const s=state('AAPL');
 const samples=Array.from({length:40},(_,i)=>({time:new Date(NOW-(40-i)*300000).toISOString(),price:100,quote_time:new Date(NOW-(40-i)*300000).toISOString()}));
 s.history.AAPL=clone(samples);s.history.MSFT=clone(samples);
 const original=JSON.stringify(s),q=fixture.cases.find(x=>x.symbol==='AAPL').buy_quote;
 const out=tick(s,{quotes:{AAPL:q},expected_open:['AAPL'],closed_symbols:['MSFT'],fx:{usd_per_eur:1.1,date:'2026-11-03'}},NOW);
 assert.equal(HISTORY_LIMIT,12);assert.equal(out.state.history.AAPL.length,12);assert.deepEqual(out.state.history.AAPL.slice(-6,-1),samples.slice(-5));assert.equal(out.state.history.MSFT.length,12);assert.equal(JSON.stringify(s),original);
});
test('day loss / peak loss latch and block fresh buys',()=>{
 const s=state('KBC.BR');s.risk.day='2026-11-03';s.risk.day_start_equity=520;s.peak=530;
 const out=tick(s,{quotes:{'KBC.BR':eur.buy_quote},expected_open:['KBC.BR'],closed_symbols:[],fx:{usd_per_eur:1.1,date:'2026-11-03'}},NOW);
 assert.equal(out.state.risk.daily_halted,true);assert.equal(out.state.risk.global_halted,true);assert.equal(out.trades.length,0);
});
test('ECB stale/invalid FX rejected',()=>{
 const xml='<Envelope><Cube time="2026-11-03"><Cube currency="USD" rate="1.1"/></Cube></Envelope>';
 close(parseEcb(xml,NOW).usd_per_eur,1.1);assert.throws(()=>parseEcb(xml.replace('2026-11-03','2026-10-20'),NOW));
});
test('Yahoo delayed observations cannot be executions; pence normalized',()=>{
 const item=BY_SYMBOL['NG.L'];const data={chart:{result:[{meta:{symbol:'NG.L',currency:'GBp',regularMarketPrice:1252,regularMarketTime:NOW/1000,instrumentType:'EQUITY',currentTradingPeriod:{regular:{start:NOW/1000-3600,end:NOW/1000+3600}}}}]}};
 const q=parseYahoo(data,item,{date:'2026-11-03',rates:{GBP:.8}},NOW);close((q.bid+q.ask)/2,12.52);
 data.chart.result[0].meta.regularMarketTime-=900;assert.throws(()=>parseYahoo(data,item,{rates:{GBP:.8}},NOW));
});

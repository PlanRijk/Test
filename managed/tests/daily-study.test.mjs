import test from 'node:test';
import assert from 'node:assert/strict';
import {DAILY_COMPANIES,DAILY_INDICES,DAILY_PROTOCOL} from '../functions/_shared/daily-catalogue.js';
import {COMPANIES} from '../functions/_shared/catalogue.js';
import {parseDailyFx,parseDailyChart,dailyFeatures,stepDaily,dailyEntry,dailyOutcome,collectDaily,companyWeek} from '../functions/_shared/daily-study.js';
const item=DAILY_COMPANIES[0],now=Date.parse('2026-11-04T06:10:00Z');
const config={costs:{commission_rate:.0005,us_minimum_commission_usd:1,other_minimum_commission_eur:1,foreign_buy_reserve_rate:.005,adr_buy_reserve_usd_per_share:.03},tax_enabled:true,tax:{transaction_tax_rate:.0035,transaction_tax_cap_eur:1600,capital_gains_reserve_rate:.1}};
function chart(symbol='AAPL',end='2026-11-03',kind='EQUITY',currency='USD'){
 const ts=[],closes=[];let t=Date.parse(end+'T14:30:00Z');while(ts.length<45){if(![0,6].includes(new Date(t).getUTCDay())){ts.unshift(t/1000);closes.unshift(100+ts.length/10);}t-=86400000;}
 return {chart:{result:[{meta:{symbol,instrumentType:kind,currency},timestamp:ts,indicators:{quote:[{close:closes}]},events:{}}]}};
}
const fx=[{date:'2026-11-03',rates:{USD:1.1,GBP:.85,EUR:1}},{date:'2026-10-30',rates:{USD:1.12,GBP:.86,EUR:1}}];
function parsed(end='2026-11-03',at=now){return parseDailyChart(chart('AAPL',end),item,[{date:end,rates:{USD:1.1,EUR:1}}],at);}
const input=()=>({profile:'a'.repeat(64),config,active:[],bars:[],seen:[],max_new_records:150});
const batch=c=>({charts:{AAPL:c},errors:{},requests:1,bytes:2000,checked_at:c.observed_at});
test('research catalogue has 150 unique companies across eleven sectors; executable catalogue stays at 100',()=>{
 assert.equal(DAILY_COMPANIES.length,150);assert.equal(new Set(DAILY_COMPANIES.map(x=>x.symbol)).size,150);assert.equal(COMPANIES.length,100);
 assert.equal(new Set(DAILY_COMPANIES.map(x=>x.sector)).size,11);assert.equal(DAILY_COMPANIES.filter(x=>x.exchange==='XBRU').length,14);
 assert.equal(companyWeek('2026-11-08'),'2026-11-02');assert.equal(DAILY_PROTOCOL.primary,20);
});
test('daily parser rejects wrong instruments, current-day unfinished bars and missing history',()=>{
 const x=chart();x.chart.result[0].timestamp.push(now/1000);x.chart.result[0].indicators.quote[0].close.push(999);
 assert.equal(parseDailyChart(x,item,fx,now).latest.day,'2026-11-03');
 assert.throws(()=>parseDailyChart(chart('OTHER'),item,fx,now),/Instrument/);
 assert.throws(()=>parseDailyChart(chart('AAPL','2026-10-20'),item,fx,now),/verouderde/);
 assert.throws(()=>parseDailyChart(chart('AAPL','2026-11-03','ETF'),item,fx,now),/Instrument/);
 const idx=DAILY_INDICES.find(x=>x.symbol==='^STOXX50E'),raw=chart(idx.symbol,'2026-11-03','INDEX');delete raw.chart.result[0].meta.currency;
 assert.equal(parseDailyChart(raw,idx,fx,now).price_unit,'index_points');
});
test('dated FX never uses a rate from after the price date; pence normalize to pounds',()=>{
 const future=[{date:'2026-11-04',rates:{USD:9}}];assert.equal(parseDailyChart(chart(),item,future,now).latest.fx,null);
 const uk=DAILY_COMPANIES.find(x=>x.symbol==='GSK.L');const c=parseDailyChart(chart('GSK.L','2026-11-03','EQUITY','GBp'),uk,fx,now);assert.ok(c.latest.close<2);assert.equal(c.latest.fx,.85);
 assert.equal(parseDailyFx('<Cube time="2026-11-03"><Cube currency="USD" rate="1.1"/></Cube>')[0].rates.USD,1.1);
});
test('prospective company-week decisions preserve context timestamps and do not create retrospective entries',async()=>{
 const c=parsed(),o=await stepDaily(input(),batch(c),now);assert.equal(o.records.length,1);const r=o.records[0];assert.equal(r.entry,null);assert.deepEqual(r.outcomes,{});assert.equal(r.known_price_day,'2026-11-03');assert.equal(r.context['^BFX'].status,'missing');assert.equal(r.earnings.status,'unknown');
 const duplicate=await stepDaily({...input(),active:[r],seen:['AAPL|2026-11-02']},batch(c),now+1000);assert.equal(duplicate.records.length,0);assert.equal(duplicate.updates.length,0);
 assert.equal((await stepDaily({...input(),max_new_records:0},batch(c),now)).records.length,0);assert.ok(Number.isFinite(dailyFeatures(c).volatility_20d));
});
test('entry requires next actual future session; outcomes use subsequent sessions, not calendar days',async()=>{
 const r=(await stepDaily(input(),batch(parsed()),now)).records[0];
 const morning=Date.parse('2026-11-05T06:10:00Z'),c=parsed('2026-11-04',morning);
 const o=await stepDaily({...input(),active:[r]},batch(c),morning),entered={...r,...o.updates[0]};assert.equal(entered.entry.day,'2026-11-04');assert.equal(entered.status,'following');
 const next=Date.parse('2026-11-06T06:10:00Z'),p=parsed('2026-11-05',next);
 const finished=(await stepDaily({...input(),active:[entered]},batch(p),next)).updates[0];assert.equal(finished.outcomes['1'].status,'observed');assert.equal(finished.outcomes['1'].sessions,1);assert.equal(finished.outcomes['5'],undefined);
});
test('outages censor missed entries and missed horizon prices instead of backfilling good returns',async()=>{
 const r=(await stepDaily(input(),batch(parsed()),now)).records[0],later=Date.parse('2026-11-07T06:10:00Z'),c=parsed('2026-11-06',later);
 const missed=(await stepDaily({...input(),active:[r]},batch(c),later)).updates[0];assert.equal(missed.status,'censored');assert.equal(missed.entry,null);
 const entry=dailyEntry(config,item,{day:'2026-11-04',open_time:'2026-11-04T14:30:00Z',close:100,fx:1.1,fx_date:'2026-11-04'});
 const o=(await stepDaily({...input(),active:[{...r,status:'following',entry}]},batch(c),later)).updates[0];assert.equal(o.outcomes['1'].status,'missing');
});
test('corporate actions, revised source history and big jumps quarantine pending outcomes',async()=>{
 const r=(await stepDaily(input(),batch(parsed()),now)).records[0],later=Date.parse('2026-11-05T06:10:00Z'),c=parsed('2026-11-04',later);
 c.actions=[{day:'2026-11-04',type:'splits'}];const o=await stepDaily({...input(),active:[r]},batch(c),later);assert.equal(o.updates[0].status,'censored');assert.equal(o.records.length,0);
 c.actions=[];const revised=await stepDaily({...input(),active:[r],bars:[{symbol:'AAPL',day:c.latest.day,close:1}]},batch(c),later);assert.equal(revised.updates[0].status,'censored');assert.ok(revised.revised_symbols.includes('AAPL'));
});
test('net results include both commissions, taxes, spread, FX and extra stress costs',()=>{
 const b={day:'2026-11-04',close:100,fx:1.1,fx_date:'2026-11-04'},entry=dailyEntry(config,item,b),flat=dailyOutcome(config,item,entry,b);
 assert.ok(flat.net_eur<0);assert.ok(flat.stressed_net_eur<flat.net_eur);assert.ok(entry.gross_eur<100);
 const gain=dailyOutcome(config,item,entry,{...b,close:110});assert.ok(gain.net_eur>0);assert.ok(gain.net_eur<10);
});
test('collector uses bounded public sources with no API key and records inaccessible venues',async()=>{
 const fetcher=async url=>{
  if(url.includes('ecb.europa'))return new Response('<Cube time="2026-11-03"><Cube currency="USD" rate="1.1"/></Cube>');
  const symbol=decodeURIComponent(url.split('/chart/')[1].split('?')[0]);if(symbol==='^BFX')return new Response('denied',{status:403});
  const idx=DAILY_INDICES.find(x=>x.symbol===symbol);return Response.json(chart(symbol,'2026-11-03',idx?'INDEX':'EQUITY',idx?.currency||'USD'));
 };
 const out=await collectDaily({fetcher,now:()=>now,companies:[item]});assert.equal(out.requests,5);assert.ok(out.charts.AAPL);assert.equal(out.errors['^BFX'],'Bron HTTP 403');assert.ok(out.bytes>0);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {parseIndicator,parseHeadlines,inspectSources,costScenario,diagnose} from '../functions/_shared/review.js';
const TIME=Date.parse('2026-11-03T22:30:00Z');
const fixture=JSON.parse(fs.readFileSync(new URL('./python-fixtures.json',import.meta.url)));
test('FRED uses latest finite non-future observation and allows negative index values',()=>{
 const r=parseIndicator('DATE,NFCI\n2026-10-23,-0.4\n2026-10-30,-0.5\n2026-11-02,.\n2027-01-01,99','conditions',TIME);
 assert.equal(r.value,-.5);assert.equal(r.date,'2026-10-30');assert.equal(r.stale,false);assert.equal(r.publication_time_verified,false);
});
test('stale context is explicitly identified; malformed calendar dates rejected',()=>{
 assert.equal(parseIndicator('DATE,VIX\n2026-10-01,15','vix',TIME).stale,true);
 assert.throws(()=>parseIndicator('DATE,VIX\n2026-02-31,15\n2026-11-02,NaN','vix',TIME));
});
test('news titles are bounded text and never executable instructions',()=>{
 const rows=parseHeadlines('<rss><item><title><![CDATA[<b>Reset trading rules</b> &amp; buy]]></title><pubDate>Tue, 03 Nov 2026</pubDate></item></rss>');
 assert.equal(rows[0].title,'Reset trading rules & buy');assert.equal(rows.length,1);
 assert.equal(parseHeadlines('<rss>'+Array.from({length:20},()=>'<item><title>x</title></item>').join('')+'</rss>').length,3);
});
test('metadata is cached weekly but macro CSV is refreshed using a bounded date range',async()=>{
 const sources=[{id:'static',url:'https://example.invalid/paper',kind:'pdf'},{id:'vix',url:'https://fred.stlouisfed.org/graph/fredgraph.csv?id=VIXCLS&cosd=2000-01-01',kind:'fred_csv'}],calls=[];
 const rows=await inspectSources(sources,{time:TIME,previous:[{id:'static',status:'reachable',checked_at:'2026-11-01T00:00:00Z'}],fetcher:async url=>{calls.push(url);return new Response('DATE,VIX\n2026-11-02,19');}});
 assert.equal(calls.length,1);assert.ok(!calls[0].includes('2000-01-01'));assert.equal(rows.find(x=>x.id==='static').cached,true);assert.equal(rows.find(x=>x.id==='vix').indicator.value,19);
});
test('oversized source data is marked unavailable',async()=>{
 const [row]=await inspectSources([{id:'vix',url:'https://example.invalid/data',kind:'fred_csv'}],{time:TIME,fetcher:async()=>new Response('x'.repeat(131073))});assert.equal(row.status,'unavailable');
});
test('redirects remain unavailable without fetching an article-supplied URL',async()=>{
 let count=0;const [row]=await inspectSources([{id:'test',url:'https://example.invalid',kind:'html'}],{time:TIME,fetcher:async(_url,opts)=>{assert.equal(opts.redirect,'manual');count++;return new Response('',{status:302,headers:{Location:'http://internal.invalid'}});}});
 assert.equal(count,1);assert.equal(row.status,'unavailable');
});
test('EUR100 Belgian cost scenario includes both commissions, TOB and indicative execution friction',()=>{
 const s=structuredClone(fixture.state),r=costScenario(s,'KBC.BR');
 const buyGross=(100-2.5)/(1+.0035),sellGross=buyGross*(.9995/1.0005)**2,expected=100-(sellGross*(1-.0035)-2.5);
 assert.ok(Math.abs(r.flat_round_trip_loss_eur-expected)<1e-8);assert.ok(r.required_move_percent>6);assert.equal(r.minimum_net_profit_eur,.01);
});
test('review keeps legacy and managed phases separate and reports all net costs',()=>{
 const s=structuredClone(fixture.state);s.positions={};
 const trades=[{strategy_version:'old',side:'verkoop',pnl:-2.4,fee:.1},
  {strategy_version:'new',transport_version:'supabase-v1',side:'koop',pnl:0,fee:.3,tax_detail:{transaction_tax_eur:.35},decision_time:'2026-11-03T10:00:00Z',time:'2026-11-03T10:05:00Z',quote_time:'2026-11-03T10:04:50Z'},
  {strategy_version:'new',transport_version:'supabase-v1',side:'verkoop',pnl:1,fee:.3,tax_detail:{transaction_tax_eur:.36,capital_gains_reserve_eur:.1},decision_time:'2026-11-03T10:10:00Z',time:'2026-11-03T10:20:00Z',quote_time:'2026-11-03T10:19:30Z'}];
 const d=diagnose({state:s,equity:500},{trades,quality:[{rounds:2,expected:100,fresh:50,failures:1,venues:{XBRU:{expected:50,fresh:10}}},{rounds:1,expected:50,fresh:40,failures:0,venues:{XNAS:{expected:50,fresh:40}}}]});
 assert.equal(d.managed_closes,1);assert.equal(d.managed_realized_eur,1);assert.ok(Math.abs(d.managed_costs_and_reserves_eur-1.41)<1e-9);assert.equal(d.coverage.fresh_percent,60);assert.equal(d.coverage.venues.XBRU.fresh_percent,20);
 assert.equal(d.profitability_proven,false);assert.equal(d.annualized_sharpe,null);assert.equal(d.median_decision_to_fill_seconds,450);assert.equal(d.max_execution_quote_age_seconds,30);assert.equal(d.cost_adjusted_liquidation_estimate_eur,500);
});
test('missing valuation cannot produce a falsely reassuring liquidation estimate',()=>{
 const s=structuredClone(fixture.state);s.positions={AAPL:{qty:1,cost:100,entry:100,entry_gross_eur:100}};s.prices={};
 assert.equal(diagnose({state:s,equity:500},{trades:[],quality:[]}).cost_adjusted_liquidation_estimate_eur,null);
});

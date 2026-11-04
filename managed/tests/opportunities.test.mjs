import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {stepOpportunities,STUDY} from '../functions/_shared/opportunities.js';
import {BY_SYMBOL} from '../functions/_shared/catalogue.js';
import {opportunityMarkup,opportunityDetailMarkup} from '../web/opportunities.js';
const fixture=JSON.parse(fs.readFileSync(new URL('./python-fixtures.json',import.meta.url))),T=Date.parse('2026-11-03T15:15:00Z');
const clone=structuredClone,iso=t=>new Date(t).toISOString();
function market(time=T,symbols=['AAPL']){
 const s=clone(fixture.state);s.positions={};s.pending=[];s.operation_mode='continuous';s.data_info={checked_at:iso(time)};s.risk.data_complete=true;
 s.multi_market.entry_symbols=symbols;
 for(const k of symbols){s.history[k]=[100,100.1,100.2,100.3,100.4,100.7].map((price,i)=>({price,time:iso(time-(5-i)*300000),quote_time:iso(time-(5-i)*300000)}));}
 return s;
}
function batch(time=T,symbols=['AAPL'],price=100.7){
 const quotes={};for(const k of symbols){const c=BY_SYMBOL[k].currency,rate=c==='EUR'?1:1.1;quotes[k]={bid:price*.9995,ask:price*1.0005,time:iso(time),currency:c,fx_per_eur:rate,session_start:'2026-11-03T14:30:00Z',session_end:'2026-11-03T21:00:00Z'};}
 return {quotes,expected_open:symbols,fx:{usd_per_eur:1.1,date:'2026-11-03'}};
}
const payload=out=>({enabled:true,revision:2,state:out.state});
test('all eligible opportunities are observed even when main buys are risk/capacity blocked; accounts untouched',async()=>{
 const s=market();s.risk.global_halted=true;s.risk.buys_today=8;s.cash=100;const before=clone(s);
 const out=await stepOpportunities({enabled:true,revision:1,state:{}},s,batch(),T);
 assert.equal(out.records.length,2);assert.deepEqual(s,before);assert.ok(out.records[0].main_reasons.includes('risk_pause'));assert.ok(out.records[0].main_reasons.includes('daily_limit'));
 assert.equal(out.records[0].observations.length,6);assert.equal(out.records[0].outcomes['30'],undefined);assert.equal(out.records[0].entry,undefined);
});
test('entry needs a genuinely later fresh quote and each cohort is sampled once per company/session day',async()=>{
 const first=await stepOpportunities({enabled:true,revision:1,state:{}},market(),batch(),T),again=await stepOpportunities(payload(first),market(),batch(),T);
 assert.equal(again.records.length,0);assert.equal(again.updates.length,0);
 const later=await stepOpportunities(payload(first),market(T+300000),batch(T+300000),T+300000);
 assert.equal(later.updates.filter(x=>x.entry).length,2);assert.equal(later.updates.filter(x=>x.outcomes).length,0);
 assert.equal(Object.values(later.state.active)[0].entry.taxes,undefined);
});
test('net outcomes use the prespecified future horizon, include both-side costs and cannot be reported early',async()=>{
 const first=await stepOpportunities({enabled:true,revision:1,state:{}},market(),batch(),T);
 const entered=await stepOpportunities(payload(first),market(T+300000),batch(T+300000),T+300000);
 const early=await stepOpportunities(payload(entered),market(T+1800000),batch(T+1800000),T+1800000);assert.ok(!early.updates.some(x=>x.outcomes));
 const h30=await stepOpportunities(payload(early),market(T+2100000),batch(T+2100000),T+2100000);
 const result=h30.updates.find(x=>x.outcomes)?.outcomes['30'];assert.equal(result.status,'observed');assert.ok(result.net_eur<0);assert.equal(result.actual_minutes,30);
 const h120=await stepOpportunities(payload(h30),market(T+7500000),batch(T+7500000),T+7500000);
 assert.equal(h120.updates.filter(x=>x.status==='complete').length,2);assert.equal(Object.keys(h120.state.active).length,0);
});
test('missing/late quotes censor observations instead of creating zero or invented returns',async()=>{
 const first=await stepOpportunities({enabled:true,revision:1,state:{}},market(),batch(),T);
 const expired=await stepOpportunities(payload(first),market(T+660000),{quotes:{},expected_open:['AAPL']},T+660000);
 assert.equal(expired.updates.filter(x=>x.status==='expired').length,2);assert.equal(Object.keys(expired.state.active).length,0);
 const entered=await stepOpportunities(payload(first),market(T+300000),batch(T+300000),T+300000);
 const late=await stepOpportunities(payload(entered),market(T+3000000),{quotes:{},expected_open:['AAPL']},T+3000000);
 assert.equal(late.updates[0].outcomes['30'].status,'missing');assert.equal(late.updates[0].outcomes['30'].net_eur,undefined);
});
test('future measurements and stale quotes cannot form a dossier',async()=>{
 const s=market();s.history.AAPL.at(-1).time=iso(T+1);
 assert.equal((await stepOpportunities({enabled:true,revision:1,state:{}},s,batch(),T)).records.length,0);
 const b=batch();b.quotes.AAPL.time=iso(T-121000);
 assert.equal((await stepOpportunities({enabled:true,revision:1,state:{}},market(),b,T)).records.length,0);
});
test('profile changes pause observation comparison and disabled payloads do no work',async()=>{
 const first=await stepOpportunities({enabled:true,revision:1,state:{}},market(),batch(),T),changed=market();changed.belgian_tax.config.transaction_tax_rate=.02;
 assert.equal((await stepOpportunities(payload(first),changed,batch(),T)).state.status,'profile_changed');
 assert.equal(await stepOpportunities({enabled:false},market(),batch(),T),null);
});
test('sector basket requires all eleven names and later quotes, stays distinct from main cash, and blocks large jumps',async()=>{
 const s=market(T,STUDY.basket),b=batch(T,STUDY.basket),before=clone(s);
 const first=await stepOpportunities({enabled:true,revision:1,state:{}},s,b,T);assert.equal(first.state.basket.stage,'pending');assert.deepEqual(s,before);
 const later=await stepOpportunities(payload(first),market(T+300000,STUDY.basket),batch(T+300000,STUDY.basket),T+300000);
 assert.equal(later.state.basket.stage,'holding');assert.equal(later.state.basket.cash,100);assert.ok(later.state.basket.liquidation_estimate_eur<500);assert.equal(later.state.basket.fresh_symbols,11);
 const missing=batch(T+600000,STUDY.basket);delete missing.quotes.AAPL;
 assert.equal((await stepOpportunities(payload(later),market(T+600000,STUDY.basket),missing,T+600000)).state.basket.current,false);
 const jump=batch(T+600000,STUDY.basket,160);
 assert.equal((await stepOpportunities(payload(later),market(T+600000,STUDY.basket),jump,T+600000)).state.basket.stage,'review_required');
 const staleMain=market(T+600000,STUDY.basket);staleMain.cash=400;staleMain.positions={'KBC.BR':{qty:1,cost:100,entry:100,entry_gross_eur:100}};staleMain.prices['KBC.BR']=100;staleMain.price_fx['KBC.BR']=1;
 assert.equal((await stepOpportunities(payload(later),staleMain,batch(T+600000,STUDY.basket),T+600000)).state.basket.main_current,false);
});
test('maximum scope of two cohorts for 100 companies fits bounded runtime payload after entry',async()=>{
 const symbols=Object.keys(BY_SYMBOL);
 const first=await stepOpportunities({enabled:true,revision:1,state:{}},market(T,symbols),batch(T,symbols),T);
 const later=await stepOpportunities(payload(first),market(T+300000,symbols),batch(T+300000,symbols),T+300000);
 assert.equal(Object.keys(later.state.active).length,symbols.length*2);assert.ok(JSON.stringify(later.state).length<131072);assert.ok(JSON.stringify(later).length<800000);
});
test('basket cannot anchor against stale main holdings',async()=>{
 const s=market(T,STUDY.basket);s.positions={'KBC.BR':{qty:1,cost:100,entry:100,entry_gross_eur:100}};s.prices['KBC.BR']=100;s.price_fx['KBC.BR']=1;
 const first=await stepOpportunities({enabled:true,revision:1,state:{}},s,batch(T,STUDY.basket),T);assert.equal(first.state.basket.stage,'waiting');
});
test('study views escape explanations and never present hypothetical sums as portfolio profit',()=>{
 const markup=opportunityMarkup({state:{message:'<img src=x onerror=bad()>'},recent:[],counts:{records:2,clusters:1}});
 assert.ok(!markup.includes('<img'));assert.match(markup,/geen optelbare portefeuillewinst/);assert.match(markup,/geen trainingslabels|niet mee als trainingslabels/);
 assert.ok(!opportunityDetailMarkup({symbol:'<script>',statement:'<img>',observations:[]}).includes('<script>'));
});

import test from 'node:test';
import assert from 'node:assert/strict';
import {HISTORY_PROTOCOL,parseHistoryChart,parseHistoryFx,publicContext,optionalChecks,connections} from '../functions/_shared/history-data.js';
import {DAILY_COMPANIES,DAILY_INDICES} from '../functions/_shared/daily-catalogue.js';
import {datedRate,historyFeatures,historySplit,trainHistory,verifyHistory,buildHistorical,historySeries} from '../functions/_shared/history-model.js';
import {forwardHistory,forwardReport} from '../functions/_shared/history-forward.js';
import {sha} from '../functions/_shared/learner.js';
import {historyMarkup} from '../web/history-learning.js';
const config={costs:{commission_rate:.0005,us_minimum_commission_usd:1,other_minimum_commission_eur:1,foreign_buy_reserve_rate:.005,adr_buy_reserve_usd_per_share:.03},tax_enabled:true,tax:{transaction_tax_rate:.0035,transaction_tax_cap_eur:1600,capital_gains_reserve_rate:.1}};
const cutoff='2026-11-04',now=Date.parse(cutoff+'T06:20:00Z'),profile='a'.repeat(64);
function rows(){const rows=[];let t=Date.parse('2016-01-04T06:20:00Z'),n=0;
 while(n<600){if(![0,6].includes(new Date(t).getUTCDay())){for(let j=0;j<6;j++){const item=DAILY_COMPANIES[(n*6+j)%DAILY_COMPANIES.length],y=(n+j)%2;
  rows.push({id:n+'-'+j,symbol:item.symbol,venue:item.exchange,sector:item.sector,date:new Date(t).toISOString().slice(0,10),decision:t,entry:t+86400000,available:t+30*86400000,
   features:[y?.02:-.02,y?.04:-.04,.01,.01,.1,-.01,.01,.02],net:y?4:-3,stress:y?3:-4,y,origin:'historically_simulated'});}n++;}t+=86400000;}return rows;}
function prepared(r=rows()){return {rows:r,sampled_candidates:r.length,source_candidates:r.length,excluded:{},source_count:153};}
let result;
test('fixed historical model trains with purged dates and signs reproducible inputs; no main-model schema reuse',async()=>{
 result=await trainHistory({profile,cutoff,config,prepared:prepared(),snapshots:[]},{time:now});assert.equal(result.status,'historical_model_frozen');assert.equal(await verifyHistory(result.artifact),true);
 assert.equal(result.artifact.automatic_trading_approval,false);assert.equal(result.artifact.feature_names.length,8);assert.equal(result.artifact.counts.samples,3600);
 const split=historySplit(rows());assert.ok(split.train.every(r=>r.available<Date.parse(split.windows.validation_start)));assert.ok(split.validation.every(r=>r.available<Date.parse(split.windows.test_start)));
});
test('changing test labels cannot change fitted means, scales or weights',async()=>{
 const r=rows(),boundary=historySplit(r).windows.test_start,changed=r.map(x=>x.date>=boundary?{...x,y:1-x.y,net:x.y?-3:4,stress:x.y?-4:3}:x);
 const a=await trainHistory({profile,cutoff,prepared:prepared(changed),snapshots:[]},{time:now});
 for(const k of ['weights','bias','mean','scale'])assert.deepEqual(a.artifact[k],result.artifact[k]);assert.notEqual(a.artifact.dataset_hash,result.artifact.dataset_hash);
 const broken={...result.artifact,bias:9};assert.equal(await verifyHistory(broken),false);
});
test('duplicates, future labels, foreign symbols, actual-trade labels and noncausal entries are rejected',async()=>{
 const original=rows();for(const bad of [{...original[0],available:now+86400000},{...original[0],entry:original[0].decision},{...original[0],origin:'real_trade'},{...original[0],symbol:'UNKNOWN'}]){
  await assert.rejects(trainHistory({profile,cutoff,prepared:prepared([bad,...original.slice(1)]),snapshots:[]}),/noncausal/);
 }await assert.rejects(trainHistory({profile,cutoff,prepared:prepared([...original,original[0]]),snapshots:[]}),/noncausal/);
 const small=await trainHistory({profile,cutoff,prepared:prepared(original.slice(0,20)),snapshots:[]});assert.equal(small.status,'waiting_history');
});
test('FX uses the historical date or at most four earlier days; no present-day FX backfill',()=>{
 const map=new Map([['2026-11-02',{USD:1.1}],['2026-11-04',{USD:9}]]);
 assert.equal(datedRate(map,'2026-11-03','USD').fx,1.1);assert.equal(datedRate(map,'2026-10-30','USD').fx,null);assert.equal(datedRate(map,'2026-11-03','EUR').fx,1);
});
function series(end='2026-11-03',count=80){const out=[];let t=Date.parse(end+'T14:30:00Z');while(out.length<count){if(![0,6].includes(new Date(t).getUTCDay()))out.unshift({day:new Date(t).toISOString().slice(0,10),open_time:new Date(t).toISOString(),close:100+out.length*.01,volume:100000,fx:1.1,fx_date:new Date(t).toISOString().slice(0,10),observed_at:new Date(t+86400000).toISOString(),actions:[]});t-=86400000;}return out;}
function withCalendar(b){const sessions=b.map(x=>Date.parse(x.open_time)/1000);b.at(-1).session_starts=sessions;return b;}
function source(symbol,b=series()){return {symbol,status:'available',data:{symbol,timestamps:b.map(x=>Date.parse(x.open_time)/1000),closes:b.map(x=>x.close),volumes:b.map(x=>x.volume),actions:[]}};}
test('historical reconstruction keeps future entry and twenty-session exit; unsupported cases remain in counts',()=>{
 const s=series('2026-11-03',400),fx={columns:['USD'],rows:s.map(b=>[b.day,1.1])},snapshots=[{symbol:'__base__',status:'available',data:{fx}},...DAILY_INDICES.map(x=>source(x.symbol,s)),source('AAPL',s),source('TSM',s)];
 const built=buildHistorical({profile,config,cutoff,snapshots});assert.ok(built.rows.length>0);assert.ok(built.excluded.adr_basis_unverified>0);
 assert.ok(built.rows.every(r=>r.origin==='historically_simulated'&&r.decision<r.entry&&r.entry<r.available));assert.ok(built.rows.every(r=>r.dividend_cash_credit===0));
});
test('new frozen forecasts do not use old entries or count weekends as new decision days',async()=>{
 const a={...result.artifact,created_at:new Date(now-1000).toISOString(),symbols:['AAPL'],mean:Array(8).fill(0),scale:Array(8).fill(1),weights:Array(8).fill(0),bias:0};delete a.integrity_hash;a.integrity_hash=await sha(a);
 const b=withCalendar(series()),bars=[...DAILY_INDICES.map(x=>x.symbol),'AAPL'].flatMap(symbol=>b.map(x=>({symbol,day:x.day,close:x.close,record:x})));
 const input={artifact:a,config,bars,tails:[],active:[],max_new_records:20,context:[]};
 const out=await forwardHistory(input,{time:now});assert.equal(out.records.length,1);assert.equal(out.records[0].entry,null);assert.equal(out.records[0].origin,'prospective_hypothetical');
 const weekend=await forwardHistory(input,{time:Date.parse('2026-11-07T06:20:00Z')});assert.equal(weekend.records.length,0);
 const row=out.records[0],later=Date.parse('2026-11-05T06:20:00Z'),next=withCalendar(series('2026-11-04'));const updated=await forwardHistory({...input,active:[row],bars:[...DAILY_INDICES.map(x=>x.symbol),'AAPL'].flatMap(symbol=>next.map(x=>({symbol,day:x.day,close:x.close,record:x})))},{time:later});
 assert.equal(updated.updates[0].entry.day,'2026-11-04');assert.equal(updated.updates[0].status,'following');
});
test('forward reports cannot replace an early unfinished day with a later winning day',()=>{
 const artifact=result.artifact,records=[];for(let i=0;i<61;i++)records.push({id:'f'+i,model_id:artifact.id,decision_at:new Date(now+(i+1)*86400000).toISOString(),decision_day:new Date(now+(i+1)*86400000).toISOString().slice(0,10),status:i===0?'following':'complete',symbol:'AAPL',sector:'IT',features:Array(8).fill(0),outcome:{status:'observed',net_eur:4,stressed_net_eur:3}});
 const report=forwardReport(artifact,records,now+100*86400000);assert.equal(report.status,'collecting_forward');assert.equal(report.days,59);assert.equal(report.automatic_trading_approval,false);
});
test('a broad positive forward fixture can complete the fixed research test without granting trading approval',()=>{
 const artifact={...result.artifact,offline_pass:true},records=[],templates=rows().slice(0,6);let t=now+86400000,days=0;
 while(days<60){if(![0,6].includes(new Date(t).getUTCDay())){for(let j=0;j<10;j++){const y=j%2,item=DAILY_COMPANIES[(days*10+j)%150];records.push({id:days+'-'+j,model_id:artifact.id,decision_at:new Date(t).toISOString(),decision_day:new Date(t).toISOString().slice(0,10),status:'complete',symbol:item.symbol,sector:item.sector,features:templates[j%6].features,outcome:{status:'observed',net_eur:y?4:-3,stressed_net_eur:y?3:-4}});}days++;}t+=86400000;}
 const report=forwardReport(artifact,records,now+200*86400000);assert.equal(report.status,'final');assert.equal(report.days,60);assert.equal(report.research_supported,true);assert.equal(report.metrics.block_unit,'day');assert.equal(report.automatic_trading_approval,false);
});
test('SEC data uses actual accepted timestamps; Form 4 is never inferred to be a buy',async()=>{
 const fetcher=async()=>Response.json({name:'TEST',filings:{recent:{form:['4','13F-HR'],acceptanceDateTime:['2026-11-03T20:00:00Z','2026-11-05T12:00:00Z'],filingDate:['2026-11-03','2026-11-05'],accessionNumber:['123-456','987-654'],primaryDocument:['form.xml','13f.xml']}}});
 const reports=await publicContext({mapping:{AAPL:'0000320193'}},['AAPL'],{fetcher,time:now});const issuer=reports.find(x=>x.symbol==='AAPL');assert.equal(issuer.filings.length,1);assert.equal(issuer.filings[0].form,'4');assert.equal(issuer.filings[0].side,undefined);
 const original=globalThis.Deno;globalThis.Deno={env:{get:()=>''}};assert.deepEqual(await optionalChecks({fetcher:()=>{throw Error('No key must not fetch')}}),[]);assert.equal(connections().find(x=>x.id==='alpaca').status,'credentials_required');globalThis.Deno=original;
});
test('owner UI labels simulated samples and missing credentials explicitly and escapes external context',()=>{
 const html=historyMarkup({runtime:{connections:[{id:'alpaca',status:'credentials_required',role:'<script>x</script>'}],context:[]},counts:{}});
 assert.ok(html.includes('gesimuleerde'));assert.ok(html.includes('waiting_data'));assert.ok(html.includes('persoonlijke API-sleutels'));assert.ok(!html.includes('<script>'));
});

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {FEATURE_SCHEMA,decisionContext,tick} from '../functions/_shared/engine.js';
import {trainCandidate,verifyArtifact,predict,prepareSamples,chronologicalSplit,forwardVerdict} from '../functions/_shared/learner.js';
import {compactAccount,hydrateAccount,learningFingerprint,stepLearning,livePolicy,modelGate} from '../functions/_shared/learning-runtime.js';
const fixture=JSON.parse(fs.readFileSync(new URL('./python-fixtures.json',import.meta.url))),NOW=Date.parse('2026-11-03T15:00:00Z'),FP='a'.repeat(64);
const clone=structuredClone;
function rows(days=40){
 const result=[];let date=Date.parse('2026-08-03T15:00:00Z'),day=0;
 while(day<days){if(![0,6].includes(new Date(date).getUTCDay())){
  for(let j=0;j<8;j++){const pos=j%2===0,stamp=date+j*1000;result.push({id:day+'-'+j,schema:FEATURE_SCHEMA,fingerprint:FP,
   features:[pos?.01:-.01,pos?.04:-.03,.002,pos?.01:.003,.015,.2,.7],symbol:'AAPL',venue:'XNAS',
   decision_time:new Date(stamp).toISOString(),entry_time:new Date(stamp+300000).toISOString(),available_at:new Date(stamp+3600000).toISOString(),net_eur:pos?3:-1});}
  day++;}date+=86400000;}
 return result;
}
const trained=await trainCandidate(rows(),{time:NOW,fingerprint:FP});
test('real fixed optimiser fits a bounded logistic artifact and signs it',async()=>{
 assert.equal(trained.status,'trained');assert.equal(trained.artifact.algorithm,'net-logit-v1');assert.equal(await verifyArtifact(trained.artifact),true);
 const a=predict(trained.artifact,rows()[0].features),b=predict(trained.artifact,rows()[1].features);assert.ok(a.probability>b.probability);assert.ok(a.probability>.6);
});
test('future outcomes, bad schema and foreign cost profiles cannot enter training',()=>{
 const good=rows(1),future={...good[0],id:'future',available_at:'2027-01-01T00:00:00Z'},bad={...good[1],id:'bad',fingerprint:'different'};
 assert.equal(prepareSamples([...good,future,bad],NOW,FP).length,good.length);
 assert.throws(()=>prepareSamples([good[0],good[0]],NOW,FP),/Duplicate/);
});
test('training split uses disjoint whole dates and an embargo at both boundaries',()=>{
 const s=chronologicalSplit(prepareSamples(rows(),NOW,FP)),a=new Set(s.train.map(r=>r.date)),b=new Set(s.validation.map(r=>r.date)),c=new Set(s.test.map(r=>r.date));
 assert.ok([...a].every(d=>!b.has(d)&&!c.has(d)));assert.ok([...b].every(d=>!c.has(d)));assert.equal(s.windows.embargo.length,2);
 assert.ok(s.windows.embargo.every(d=>!a.has(d)&&!b.has(d)&&!c.has(d)));
});
test('test-set changes cannot influence training means or coefficients',async()=>{
 const input=rows(),split=chronologicalSplit(prepareSamples(input,NOW,FP)),testDates=new Set(split.windows.test);
 for(const r of input)if(testDates.has(r.available_at.slice(0,10)))r.features=r.features.map(x=>x+10);
 const changed=await trainCandidate(input,{time:NOW,fingerprint:FP});assert.deepEqual(changed.artifact.mean,trained.artifact.mean);assert.deepEqual(changed.artifact.weights,trained.artifact.weights);
});
test('small and one-class data produces a waiting state rather than an invented model',async()=>{
 assert.equal((await trainCandidate(rows(2),{time:NOW,fingerprint:FP})).status,'waiting_data');
 const same=rows().map(r=>({...r,net_eur:1}));assert.equal((await trainCandidate(same,{time:NOW,fingerprint:FP})).status,'waiting_data');
});
test('training waits for fresh dates instead of repeatedly testing the same holdout',async()=>{
 const r=await trainCandidate(rows(),{time:NOW,fingerprint:FP,previousCutoff:trained.artifact.training_cutoff});assert.equal(r.status,'waiting_data');assert.ok(r.blocked.some(x=>x.includes('twintig nieuwe')));
});
test('model modification fails verification and JSONB key ordering does not',async()=>{
 const bad=clone(trained.artifact);bad.weights[0]+=.1;assert.equal(await verifyArtifact(bad),false);
 const reordered=Object.fromEntries(Object.entries(trained.artifact).reverse());assert.equal(await verifyArtifact(reordered),true);
});
test('forward gate rejects warmup, repeated dates and weak or negative evidence',()=>{
 const a={...trained.artifact,offline_pass:true},days=[];let t=Date.parse('2026-11-04T12:00:00Z');while(days.length<20){if(![0,6].includes(new Date(t).getUTCDay()))days.push({date:new Date(t).toISOString().slice(0,10),model_id:a.id,complete:true,excess_eur:2,matched_excess_eur:1,model_drawdown_eur:1,reference_drawdown_eur:1});t+=86400000;}
 assert.equal(forwardVerdict(a,days,30).eligible,true);assert.equal(forwardVerdict(a,days.slice(0,3),30).eligible,false);
 assert.equal(forwardVerdict(a,[...days,days[0]],30).eligible,false);assert.equal(forwardVerdict(a,days.map(d=>({...d,matched_excess_eur:-1})),30).eligible,false);
 assert.equal(forwardVerdict(a,days.map(d=>({...d,model_drawdown_eur:20})),30).eligible,false);
 assert.equal(forwardVerdict(a,days.map(d=>({...d,date:'2026-01-01'})),30).eligible,false);
});
test('shared prices/history are not duplicated into each shadow account',()=>{
 const s=clone(fixture.state),a=compactAccount(s);assert.equal(a.history,undefined);assert.equal(a.prices,undefined);assert.equal(a.risk.previous_quotes,undefined);
 const fresh=clone(s);fresh.prices.AAPL=123;const rebuilt=hydrateAccount(a,fresh);assert.equal(rebuilt.prices.AAPL,123);assert.equal(rebuilt.cash,s.cash);rebuilt.prices.AAPL=999;assert.equal(fresh.prices.AAPL,123);
});
test('stale, tampered and shifted live models block buys and request baseline rollback',async()=>{
 const a=clone(trained.artifact),payload={active_model_id:a.id,active_artifact:a,state:{fingerprint:FP,live_drift:{total:50,shifted:30},latest_status:'ok'}};
 assert.ok((await livePolicy(payload,Date.parse(a.created_at)+1000)).rollback);
 payload.state.live_drift={total:0,shifted:0};payload.active_artifact.weights[0]+=.1;assert.ok((await livePolicy(payload,NOW)).rollback);
});
test('model confidence is recorded as an estimate, never an instruction to relax risk',()=>{
 const a=trained.artifact,context={schema:FEATURE_SCHEMA,features:rows()[0].features,venue:'XNAS'};
 assert.equal(modelGate(a,NOW)({context}),true);assert.equal(context.model_evaluation.id,a.id);assert.equal(context.model_evaluation.threshold,.6);
});
function seed(){
 const s=clone(fixture.state);s.running=true;s.last_decision=null;s.run_until='2026-12-06T21:00:00Z';s.positions={};s.pending=[];s.history=Object.fromEntries(s.universe.map(k=>[k,[]]));
 s.history.AAPL=[100,100.1,100.2,100.3,100.4,100.7].map((price,i)=>({time:new Date(NOW-(5-i)*300000).toISOString(),quote_time:new Date(NOW-(5-i)*300000).toISOString(),price}));
 return s;
}
function batch(price,time){const q=clone(fixture.cases.find(r=>r.symbol==='AAPL').buy_quote);Object.assign(q,{bid:price*.9995,ask:price*1.0005,time:new Date(time).toISOString(),session_start:'2026-11-03T14:30:00Z',session_end:'2026-11-03T21:00:00Z'});
 return {quotes:{AAPL:q},expected_open:['AAPL'],closed_symbols:[],fx:{usd_per_eur:1.1,date:'2026-11-03'}};}
test('causal features reject future measurements',()=>{
 const s=seed(),q=batch(100.7,NOW).quotes.AAPL;assert.ok(decisionContext(s,'AAPL',q,NOW));s.history.AAPL.at(-1).time=new Date(NOW+1000).toISOString();assert.equal(decisionContext(s,'AAPL',q,NOW),null);
});
test('every new buy retains decision reasoning, execution checks and an entry/exit link',()=>{
 const s=seed(),first=tick(s,batch(100.7,NOW),NOW),order=first.state.pending.find(o=>o.symbol==='AAPL'&&o.side==='koop');assert.ok(order.purchase_rationale);assert.equal(order.purchase_rationale.decision.observations.length,6);
 const frozen=clone(order.purchase_rationale),second=tick(first.state,batch(100.8,NOW+300000),NOW+300000),buy=second.trades.find(t=>t.side==='koop');assert.ok(buy);
 assert.deepEqual(buy.snapshot.purchase_rationale.decision,frozen.decision);assert.ok(buy.snapshot.purchase_rationale.execution.quote_age_seconds<=120);
 const third=tick(second.state,batch(110,NOW+600000),NOW+600000),fourth=tick(third.state,batch(110,NOW+900000),NOW+900000),sell=fourth.trades.find(t=>t.side==='verkoop');
 assert.ok(sell);assert.equal(sell.snapshot.purchase_rationale.id,buy.snapshot.purchase_rationale.id);
});
test('shadow pipeline produces labels only from closed reference trades and preserves the main input',async()=>{
 let market=seed(),payload={enabled:true,revision:1,state:{},active_model_id:null,candidate_artifact:null},samples=[];const original=JSON.stringify(market);
 for(const [i,price]of [100.7,100.8,110,110].entries()){
  const time=NOW+i*300000,b=batch(price,time),out=await stepLearning(payload,market,b,time);samples.push(...out.samples);
  payload={...payload,revision:payload.revision+1,state:out.state};market=tick(market,b,time).state;
 }
 assert.equal(samples.length,1);assert.equal(samples[0].schema,FEATURE_SCHEMA);assert.ok(Date.parse(samples[0].decision_time)<Date.parse(samples[0].entry_time));assert.ok(Date.parse(samples[0].entry_time)<Date.parse(samples[0].available_at));
 assert.equal(payload.state.accounts.learned,null);assert.equal(original,JSON.stringify(seed()));assert.equal(payload.state.day_accumulators[Object.keys(payload.state.day_accumulators)[0]].complete,false);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import {reliableTrain,modelAudit,epochAudit,blockBounds} from '../functions/_shared/reliability.js';
import {verifyArtifact} from '../functions/_shared/learner.js';
import {BY_SYMBOL} from '../functions/_shared/catalogue.js';
const NOW=Date.parse('2026-11-04T23:00:00Z'),FP='a'.repeat(64);
const symbols=['AAPL','CAT','JNJ','JPM','NEE','LIN','XOM','KO','AMZN','GOOGL','PLD','MSFT'];
function samples(n=80){const rows=[];let t=Date.parse('2025-05-05T15:00:00Z'),d=0;
 while(d<n){if(![0,6].includes(new Date(t).getUTCDay())){for(let j=0;j<8;j++){const pos=j%2===0,k=symbols[(d*8+j)%symbols.length],s=t+j*1000;
 rows.push({id:d+'-'+j,symbol:k,venue:BY_SYMBOL[k].exchange,schema:'decision-net-v1',fingerprint:FP,features:[pos?.01:-.01,pos?.04:-.03,.002,pos?.01:.003,.01,.2,.7],decision_time:new Date(s).toISOString(),entry_time:new Date(s+300000).toISOString(),available_at:new Date(s+3600000).toISOString(),net_eur:pos?3:-1.5});}d++;}t+=86400000;}return rows;}
let trained;
test('reliable training waits for broad, dated data and produces a verifiable frozen artifact',async()=>{
 assert.equal((await reliableTrain(samples(20),{time:NOW,fingerprint:FP})).status,'waiting_data');
 assert.equal((await reliableTrain(samples().map(r=>({...r,symbol:'AAPL'})),{time:NOW,fingerprint:FP})).status,'waiting_data');
 trained=await reliableTrain(samples(),{time:NOW,fingerprint:FP});assert.equal(trained.status,'trained');assert.equal(trained.artifact.protocol,'paper-learning-v2');assert.equal(await verifyArtifact(trained.artifact),true);assert.equal(trained.artifact.reliability.version,'reliability-v1');
});
function forward(artifact,n=60){const days=[];let t=NOW+86400000;while(days.length<n){const date=new Date(t).toISOString().slice(0,10);if(![0,6].includes(new Date(t).getUTCDay()))days.push({date,model_id:artifact.id,complete:true,excess_eur:2,matched_excess_eur:2.2,stress_cost_eur:.2,model_net_eur:3,model_exposure:80,reference_exposure:100,exposure_ratio:.8,model_drawdown_eur:1,reference_drawdown_eur:1});t+=86400000;}return days;}
const meta={closes:120,symbols:12,sectors:11,quality_days:60,min_source_coverage:1,calendar_coverage:1,flagged_trades:0};
test('a fixed audit requires sixty actual future days and cannot use still-future observations',async()=>{
 const artifact={...trained.artifact,offline_pass:true},days=forward(artifact),asof=Date.parse(days.at(-1).date+'T23:00:00Z')+86400000;
 assert.equal((await modelAudit(artifact,days,meta,asof)).eligible,true);
 assert.equal((await modelAudit(artifact,days.slice(0,59),meta,asof)).status,'waiting');
 assert.equal((await modelAudit(artifact,days,meta,Date.parse(days.at(-1).date+'T12:00:00Z'))).status,'waiting');
 assert.equal((await modelAudit(artifact,days,{},asof)).eligible,false);
});
test('duplicates, unmatched risk, missing costs, poor coverage and concentrated results block approval',async()=>{
 const a={...trained.artifact,offline_pass:true},days=forward(a),time=Date.parse(days.at(-1).date+'T23:00:00Z')+86400000;
 assert.equal((await modelAudit(a,[...days,days[0]],meta,time)).eligible,false);
 assert.equal((await modelAudit(a,days.map(d=>({...d,exposure_ratio:2})),meta,time)).eligible,false);
 assert.equal((await modelAudit(a,days.map(d=>({...d,stress_cost_eur:null})),meta,time)).eligible,false);
 assert.equal((await modelAudit(a,days,{...meta,min_source_coverage:.5},time)).eligible,false);
 const oneWeek=days.map((d,i)=>({...d,matched_excess_eur:i<5?100:-1}));assert.equal((await modelAudit(a,oneWeek,meta,time)).eligible,false);
});
test('block uncertainty retains serial dependence and does not turn negative means into proof',()=>{
 assert.ok(blockBounds(Array(60).fill(2),5).lower>0);assert.ok(blockBounds(Array(60).fill(-1),10).lower<0);assert.equal(blockBounds([1,2,3]),null);
});
test('an unopened holdout is sealed and missing pairs can prevent a favorable conclusion',async()=>{
 const e={id:1,test_end:'2027-03-04',sectors:6,venues:2,flagged:0,days:Array.from({length:40},(_,i)=>({date:'fixture-'+i,expected:10,observed:10,mean_difference_eur:2,mean_stressed_difference_eur:1,adverse_mean_eur:2,control_gross_mean:i%2?1:-1}))};
 assert.equal((await epochAudit(e,NOW)).status,'sealed');
 const time=Date.parse('2027-03-06T00:00:00Z');assert.equal((await epochAudit(e,time)).automatic_trading_approval,false);
 assert.equal((await epochAudit({...e,days:e.days.map(d=>({...d,observed:5,adverse_mean_eur:-50}))},time)).conclusion,'not_supported');
});

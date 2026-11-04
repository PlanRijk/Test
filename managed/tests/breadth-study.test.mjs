import test from 'node:test';
import assert from 'node:assert/strict';
import {breadthFixture,TEST_CONFIG} from './breadth-fixture.mjs';
import {stepBreadth,encodeEntry,decodeEntry,encodeOutcome,decodeOutcome,decodeCase} from '../functions/_shared/breadth-study.js';
import {dailyEntry,dailyOutcome} from '../functions/_shared/daily-study.js';
import {DAILY_COMPANIES} from '../functions/_shared/daily-catalogue.js';
import {sha} from '../functions/_shared/learner.js';
import {breadthMarkup} from '../web/breadth-study.js';
const NOW=Date.parse('2026-11-04T06:25:00Z');
test('all eligible extra companies get compact forecasts; forty get detailed evidence without changing reference data',async()=>{
 const input=await breadthFixture(NOW),copy=structuredClone(input),out=await stepBreadth(input,{time:NOW});
 assert.equal(out.summary.eligible,147);assert.equal(out.records.length,127);assert.equal(out.traces.length,40);assert.equal(out.summary.reference,20);
 assert.ok(out.records.every(r=>!input.reference_symbols.includes(r[0])));assert.equal(new Set(out.records.map(r=>r[0])).size,127);
 assert.ok(out.traces.every(t=>out.records.some(r=>r[0]===t.symbol)));assert.equal(new Set(out.traces.map(t=>out.records.find(r=>r[0]===t.symbol)[6])).size,11);
 for(const t of out.traces){assert.equal(t.record.prices.length,21);assert.ok(t.record.prices.every(p=>p[3]<=NOW));assert.ok(Object.values(t.record.indices).every(a=>a.length===6&&a.every(p=>p[2]<=NOW)));}
 assert.deepEqual(input,copy);
});
test('evidence selection is deterministic and does not prefer optimistic model predictions',async()=>{
 const input=await breadthFixture(NOW),first=await stepBreadth(input,{time:NOW});
 const artifact={...input.artifact,bias:3};delete artifact.integrity_hash;artifact.integrity_hash=await sha(artifact);
 const second=await stepBreadth({...input,artifact},{time:NOW});assert.deepEqual(first.traces.map(t=>t.symbol),second.traces.map(t=>t.symbol));
 assert.ok(first.records.every(r=>r[4]===.5));assert.ok(second.records.every(r=>r[4]>.9));
});
test('budget reduction, full capacity and weekends do not invent new cases or stop existing follow-up',async()=>{
 const input=await breadthFixture(NOW),out=await stepBreadth(input,{time:NOW}),record=out.records[0];
 assert.equal((await stepBreadth({...input,max_new:75,max_details:0},{time:NOW})).records.length,75);
 assert.equal((await stepBreadth({...input,max_new:0,max_details:0},{time:NOW})).records.length,0);
 const nextTime=Date.parse('2026-11-05T06:25:00Z'),next=await breadthFixture(nextTime);
 const active=[record[0],record[1],record[2],record[3],record[4],record[5],0,null,null,null];
 const followed=await stepBreadth({...next,max_new:0,max_details:0,active:[active]},{time:nextTime});assert.equal(followed.updates.length,1);assert.equal(followed.updates[0][2],1);assert.equal(followed.records.length,0);
 const saturday=Date.parse('2026-11-07T06:25:00Z');assert.equal((await stepBreadth(await breadthFixture(saturday),{time:saturday})).records.length,0);
});
test('compact codecs preserve prices, dated FX, costs and outcomes for later analysis',()=>{
 const item=DAILY_COMPANIES[0],bar={day:'2026-11-03',open_time:'2026-11-03T14:30:00Z',close:100,fx:1.1,fx_date:'2026-11-03'},entry={...dailyEntry(TEST_CONFIG,item,bar),known_at:'2026-11-04T06:10:00Z'};
 const packed=encodeEntry(entry);assert.equal(packed.length,12);assert.deepEqual(encodeEntry(decodeEntry(packed)),packed);
 const outcome={...dailyOutcome(TEST_CONFIG,item,entry,{...bar,day:'2026-12-01',close:105}),known_at:'2026-12-02T06:10:00Z'};
 const result=encodeOutcome(outcome);assert.equal(result.length,10);assert.deepEqual(encodeOutcome(decodeOutcome(result)),result);
 assert.deepEqual(decodeOutcome([2],'missing'),{status:'missing',reason:'missing'});
 const decoded=decodeCase(['AAPL','2026-11-03',NOW,'2026-11-02',.5,Array(8).fill(0),2,packed,result,null],'hm-test');assert.equal(decoded.id,'AAPL|2026-11-03');assert.equal(decoded.outcome.net_eur,outcome.net_eur);
});
test('unavailable or future input times and altered reference implementations prevent false evidence',async()=>{
 const input=await breadthFixture(NOW);await assert.rejects(stepBreadth({...input,reference_implementation:'wrong'},{time:NOW}),/reference/);
 const changed=structuredClone(input);for(const b of changed.bars)if(b[0]==='^GSPC')b[7]=NOW+60000;
 const out=await stepBreadth(changed,{time:NOW});assert.equal(out.records.length,0);assert.ok(out.summary.excluded.unknown_or_future_source_time>0);
});
test('exploratory views explain dependence, exact reference separation and free budgets; untrusted text is escaped',()=>{
 const html=breadthMarkup({runtime:{status:'<script>bad</script>'},counts:{compact:127,traces:40},monthly_estimate_bytes:1100000000});
 assert.ok(html.includes('vaste toetsgroep'));assert.ok(html.includes('geen extra koersdownloads'));assert.ok(html.includes('waarschuwingsmarge'));assert.ok(!html.includes('<script>'));
});

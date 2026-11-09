import test from 'node:test';
import assert from 'node:assert/strict';
import {handler} from '../functions/paper-tick-compact/index.js';
import {MULTIDAY_POLICY} from '../functions/_shared/capital-multiday.js';
import {MULTIDAY_IMPLEMENTATION_SHA} from '../functions/_shared/multiday-implementation.js';
import {capitalFixture,CAPITAL_TEST_TIME as NOW} from './capital-fixture.mjs';
const nativeFetch=globalThis.fetch,nativeNow=Date.now;
globalThis.Deno={env:{get:name=>({SUPABASE_URL:'https://testproject.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'server-test-key',PAPERLAB_CRON_TOKEN:'test-cron-secret'})[name]}};
async function run({capital='ok',main=true,market=true}={}){const f=await capitalFixture(),calls=[];f.execution_policy={...MULTIDAY_POLICY,implementation_sha256:MULTIDAY_IMPLEMENTATION_SHA,base_implementation_sha256:f.policy.implementation_sha256};f.execution_profile='f'.repeat(64);f.execution_revision=1;Date.now=()=>NOW;
 globalThis.fetch=async(url,opts={})=>{const path=String(url);calls.push({path,body:opts.body?JSON.parse(opts.body):null});
  if(path.endsWith('/paper_claim_tick'))return Response.json({token:'main-lease',revision:1,state:f.market,persist_running:true});
  if(path.endsWith('/paper_capital_claim_multiday'))return capital==='unavailable'?Response.json({error:'unavailable'},{status:503}):Response.json(f);
  if(path.endsWith('/paper_commit_tick'))return Response.json(main);
  if(path.endsWith('/paper_capital_commit_multiday'))return capital==='commit-error'?Response.json({error:'unavailable'},{status:503}):Response.json(true);
  if(path.endsWith('/paper_capital_fail')||path.endsWith('/paper_fail_tick'))return Response.json(true);
  if(path.includes('ecb.europa.eu'))return market?new Response('<Cube time="2026-11-03"><Cube currency="USD" rate="1.1"/></Cube>'):new Response('',{status:503});
  if(path.includes('/chart/AAPL?'))return Response.json({chart:{result:[{meta:{symbol:'AAPL',instrumentType:'EQUITY',currency:'USD',regularMarketPrice:100,regularMarketTime:NOW/1000-1,exchangeDataDelayedBy:0,currentTradingPeriod:{regular:{start:Date.parse('2026-11-03T14:30:00Z')/1000,end:Date.parse('2026-11-03T21:00:00Z')/1000}}}}]}});
  if(path.includes('finance.yahoo.com'))return new Response('',{status:403});throw Error('Unexpected fetch');
 };
 try{const r=await handler(new Request('https://testproject.supabase.co/functions/v1/paper-tick',{method:'POST',headers:{'X-PaperLab-Cron':'test-cron-secret'},body:'{"manual":true}'}));return {status:r.status,result:await r.json(),calls};}
 finally{globalThis.fetch=nativeFetch;Date.now=nativeNow;}
}
test('shared single market download feeds separate ledgers only after the original commit',async()=>{const r=await run();assert.equal(r.status,200);assert.equal(r.result.capital,'committed');const main=r.calls.findIndex(c=>c.path.endsWith('/paper_commit_tick')),capital=r.calls.findIndex(c=>c.path.endsWith('/paper_capital_commit_multiday'));assert.ok(main<capital);assert.equal(r.calls.filter(c=>c.path.includes('/chart/AAPL?')).length,1);assert.equal(r.calls[main].body.p_output.state.cash,500);assert.equal(r.calls[capital].body.p_output.summary.cash_eur,10000);});
test('unavailable or failing capital route never cancels a successful original round',async()=>{for(const capital of ['unavailable','commit-error']){const r=await run({capital});assert.equal(r.status,200);assert.equal(r.result.status,'committed');assert.ok(!r.calls.some(c=>c.path.endsWith('/paper_fail_tick')));}});
test('superseded original round cannot save capital trades',async()=>{const r=await run({main:false});assert.equal(r.result.status,'superseded');assert.ok(!r.calls.some(c=>c.path.endsWith('/paper_capital_commit_multiday')));assert.ok(r.calls.some(c=>c.path.endsWith('/paper_capital_fail')));});
test('failed market fetch releases both leases without storing either output',async()=>{const r=await run({market:false});assert.equal(r.status,503);assert.ok(!r.calls.some(c=>c.path.endsWith('/paper_commit_tick')||c.path.endsWith('/paper_capital_commit_multiday')));assert.ok(r.calls.some(c=>c.path.endsWith('/paper_capital_fail')));assert.ok(r.calls.some(c=>c.path.endsWith('/paper_fail_tick')));});

import test from 'node:test';
import assert from 'node:assert/strict';
import {verifyOwner} from '../functions/_shared/platform.js';
import {handler as apiHandler} from '../functions/paper-api/index.js';
import {handler as tickHandler} from '../functions/paper-tick/index.js';
import {handler as researchHandler} from '../functions/paper-research/index.js';
import {handler as learnHandler} from '../functions/paper-learn/index.js';
import {handler as auditHandler} from '../functions/paper-audit/index.js';
import {handler as dailyHandler} from '../functions/paper-daily/index.js';
import {handler as historyHandler} from '../functions/paper-history/index.js';
import {handler as breadthHandler} from '../functions/paper-breadth/index.js';
const uid='11111111-1111-4111-8111-111111111111',sid='22222222-2222-4222-8222-222222222222',origin='https://paperlab-test.onrender.com';
const settings={owner_id:uid,origin},nativeFetch=globalThis.fetch;
globalThis.Deno={env:{get:name=>({SUPABASE_URL:'https://testproject.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'server-test-key',PAPERLAB_CRON_TOKEN:'test-cron-secret'})[name]}};
const jwt=(sub=uid,aal='aal2')=>'header.'+Buffer.from(JSON.stringify({sub,aal,session_id:sid})).toString('base64url')+'.signature';
function req({token=jwt(),method='GET',body,site=origin,query=''}={}){return new Request('https://testproject.supabase.co/functions/v1/paper-api'+query,{method,headers:{...(token?{Authorization:'Bearer '+token}:{}),Origin:site,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});}
function mock({user={id:uid},session=true}={}){
 globalThis.fetch=async(url,opts={})=>{
  if(String(url).endsWith('/paper_context'))return Response.json(settings);
  if(String(url).endsWith('/auth/v1/user'))return Response.json(user);
  if(String(url).endsWith('/paper_session'))return Response.json(session);
  if(String(url).endsWith('/paper_read'))return Response.json({private_data:'owner only'});
  if(String(url).endsWith('/paper_learning_read'))return Response.json({samples:0,enabled:true});
  if(String(url).endsWith('/paper_purchase_analysis'))return Response.json([]);
  if(String(url).endsWith('/paper_opportunity_read'))return Response.json({counts:{records:0},is_portfolio:false});
  if(String(url).endsWith('/paper_opportunity_records'))return Response.json([]);
  if(String(url).endsWith('/paper_reliability_read'))return Response.json({policy:'reliability-v1'});
  if(String(url).endsWith('/paper_archive_export'))return Response.json([]);
  if(String(url).endsWith('/paper_tax_input'))return Response.json([]);
  if(String(url).endsWith('/paper_daily_read'))return Response.json({counts:{records:0}});
  if(String(url).endsWith('/paper_daily_export'))return Response.json([]);
  if(String(url).endsWith('/paper_history_read'))return Response.json({counts:{predictions:0}});
  if(String(url).endsWith('/paper_history_export'))return Response.json([]);
  if(String(url).endsWith('/paper_capital_read'))return Response.json({runtime:{status:'collecting'}});
  if(String(url).endsWith('/paper_capital_action'))return Response.json(true);
  if(String(url).endsWith('/paper_capital_receipt'))return Response.json({account:'capital10k'});
  if(String(url).endsWith('/paper_candidates_read'))return Response.json({runtime:{status:'observing'}});
  if(String(url).endsWith('/paper_candidates_action'))return Response.json(true);
  if(String(url).endsWith('/paper_optimization_read'))return Response.json({status:'reviewed'});
  if(String(url).endsWith('/paper_breadth_read'))return Response.json({counts:{compact:0}});
  if(String(url).endsWith('/paper_breadth_export'))return Response.json([]);
  if(String(url).endsWith('/paper_breadth_action'))return Response.json(true);
  throw Error('Unexpected call: '+url);
 };
}
test('anonymous request denied without returning portfolio',async()=>{mock();const r=await apiHandler(req({token:null}));assert.equal(r.status,401);assert.ok(!(await r.text()).includes('private_data'));});
test('forged token denied when Supabase Auth rejects it',async()=>{
 globalThis.fetch=async()=>Response.json({error:'bad signature'},{status:401});await assert.rejects(verifyOwner(req(),settings),/AUTH_REQUIRED/);
});
test('valid password session without second factor denied',async()=>{mock();const r=await apiHandler(req({token:jwt(uid,'aal1')}));assert.equal(r.status,403);assert.ok((await r.json()).error.includes('Tweefactor'));});
test('another authenticated user denied even with MFA',async()=>{mock({user:{id:'33333333-3333-4333-8333-333333333333'}});const r=await apiHandler(req({token:jwt('33333333-3333-4333-8333-333333333333')}));assert.equal(r.status,403);});
test('authenticated owner with MFA can read; no wildcard CORS',async()=>{mock();const r=await apiHandler(req());assert.equal(r.status,200);assert.equal(r.headers.get('Access-Control-Allow-Origin'),origin);assert.equal((await r.json()).private_data,'owner only');});
test('foreign site rejected before authentication or state read',async()=>{mock();const r=await apiHandler(req({site:'https://foreign.example'}));assert.equal(r.status,403);assert.equal(r.headers.get('Access-Control-Allow-Origin'),null);});
test('expired/revoked application session denied',async()=>{mock({session:false});const r=await apiHandler(req());assert.equal(r.status,401);});
test('browser cannot choose arbitrary database commands',async()=>{mock();const r=await apiHandler(req({method:'POST',body:{action:'reset',query:'drop database'}}));assert.equal(r.status,400);});
test('cron is not executable without the independent cron secret',async()=>{globalThis.fetch=()=>{throw Error('Must not reach database');};const r=await tickHandler(new Request('https://test/functions/v1/paper-tick',{method:'POST',body:'{}'}));assert.equal(r.status,401);});
test('manual research cannot bypass its cron-secret gate using an owner JWT',async()=>{globalThis.fetch=()=>{throw Error('Must not reach database');};const r=await researchHandler(new Request('https://test/functions/v1/paper-research',{method:'POST',headers:{Authorization:'Bearer '+jwt()},body:'{"manual":true}'}));assert.equal(r.status,401);});
test('malformed operator research request rejected before source or database access',async()=>{globalThis.fetch=()=>{throw Error('Must not reach database');};const r=await researchHandler(new Request('https://test/functions/v1/paper-research',{method:'POST',headers:{'X-PaperLab-Cron':'test-cron-secret'},body:'bad json'}));assert.equal(r.status,400);});
test('learning and purchase explanations require the owner second factor',async()=>{mock();for(const query of ['?learning=1','?purchase-analysis=1','?learning-export=1']){const r=await apiHandler(req({token:jwt(uid,'aal1'),query}));assert.equal(r.status,403);}});
test('authenticated owner can read the learner without access to arbitrary model parameters',async()=>{mock();const r=await apiHandler(req({query:'?learning=1'}));assert.equal(r.status,200);assert.equal((await r.json()).samples,0);
 const forbidden=await apiHandler(req({method:'POST',body:{action:'learning',command:'upload-model',weights:[999]}}));assert.equal(forbidden.status,400);});
test('training endpoint rejects both anonymous requests and owner-JWT requests without cron secret',async()=>{globalThis.fetch=()=>{throw Error('Must not reach database');};for(const headers of [{},{Authorization:'Bearer '+jwt()}]){const r=await learnHandler(new Request('https://test/functions/v1/paper-learn',{method:'POST',headers,body:'{"manual":true}'}));assert.equal(r.status,401);}});
test('purchase analysis identifiers are validated before database access',async()=>{mock();const r=await apiHandler(req({query:'?shadow-receipt=drop-table'}));assert.equal(r.status,400);});
test('opportunity summaries, exports and dossiers require owner MFA',async()=>{mock();for(const query of ['?opportunities=1','?opportunity-export=1','?opportunity=op-'+24*'a'])assert.equal((await apiHandler(req({query,token:jwt(uid,'aal1')}))).status,403);});
test('owner can read observations but cannot inject results or arbitrary study commands',async()=>{mock();const r=await apiHandler(req({query:'?opportunities=1'}));assert.equal(r.status,200);assert.equal((await r.json()).is_portfolio,false);
 assert.equal((await apiHandler(req({method:'POST',body:{action:'opportunities',command:'inject-results',net_eur:999}}))).status,400);
 assert.equal((await apiHandler(req({query:'?opportunity=invalid-id'}))).status,400);
});
test('archive, independent assessments and tax reports require verified owner MFA',async()=>{mock();for(const query of ['?reliability=1','?archive-export=1','?tax-report=1'])assert.equal((await apiHandler(req({query,token:jwt(uid,'aal1')}))).status,403);});
test('owner reads bounded archive and tax report; malformed cursor and tax years are rejected',async()=>{mock();assert.equal((await apiHandler(req({query:'?archive-export=1'}))).status,200);assert.equal((await apiHandler(req({query:'?tax-report=1&year=2026'}))).status,200);assert.equal((await apiHandler(req({query:'?archive-export=1&before=invalid'}))).status,400);assert.equal((await apiHandler(req({query:'?tax-report=1&year=2020'}))).status,400);});
test('independent audit cannot be triggered by owner JWT or anonymous caller',async()=>{globalThis.fetch=()=>{throw Error('Must not reach database');};for(const headers of [{},{Authorization:'Bearer '+jwt()}])assert.equal((await auditHandler(new Request('https://test/functions/v1/paper-audit',{method:'POST',headers,body:'{}'}))).status,401);});
test('daily study and export require owner MFA; daily collection requires its separate cron secret',async()=>{
 mock();for(const query of ['?daily-study=1','?daily-export=1']){
  assert.equal((await apiHandler(req({query,token:jwt(uid,'aal1')}))).status,403);
  assert.equal((await apiHandler(req({query}))).status,200);
 }
 globalThis.fetch=()=>{throw Error('Must not reach database');};
 for(const headers of [{},{Authorization:'Bearer '+jwt()}])assert.equal((await dailyHandler(new Request('https://test/functions/v1/paper-daily',{method:'POST',headers,body:'{}'}))).status,401);
 assert.equal((await dailyHandler(new Request('https://test/functions/v1/paper-daily',{method:'POST',headers:{'X-PaperLab-Cron':'test-cron-secret'},body:'bad json'}))).status,503);
});
test('historical models and predictions require verified owner MFA; bootstrap accepts only cron authorization',async()=>{
 mock();for(const query of ['?history-learning=1','?history-export=1']){
  assert.equal((await apiHandler(req({query,token:jwt(uid,'aal1')}))).status,403);
  assert.equal((await apiHandler(req({query}))).status,200);
 }
 globalThis.fetch=()=>{throw Error('Must not access sources');};
 for(const headers of [{},{Authorization:'Bearer '+jwt()}])assert.equal((await historyHandler(new Request('https://test/functions/v1/paper-history',{method:'POST',headers,body:'{}'}))).status,401);
});
test('breadth records, original-input exports and pause control require verified owner MFA',async()=>{
 mock();for(const query of ['?breadth-study=1','?breadth-export=1','?breadth-traces=1']){
  assert.equal((await apiHandler(req({query,token:jwt(uid,'aal1')}))).status,403);
  assert.equal((await apiHandler(req({query}))).status,200);
 }
 assert.equal((await apiHandler(req({method:'POST',body:{action:'breadth',command:'pause'},token:jwt(uid,'aal1')}))).status,403);
 assert.equal((await apiHandler(req({method:'POST',body:{action:'breadth',command:'pause'}}))).status,200);
 assert.equal((await apiHandler(req({method:'POST',body:{action:'breadth',command:'replace-model'}}))).status,400);
 globalThis.fetch=()=>{throw Error('Must not reach database');};
 for(const headers of [{},{Authorization:'Bearer '+jwt()}])assert.equal((await breadthHandler(new Request('https://test/functions/v1/paper-breadth',{method:'POST',headers,body:'{}'}))).status,401);
});
test.after(()=>{globalThis.fetch=nativeFetch;delete globalThis.Deno;});

test('optimization review requires owner MFA and a live application session',async()=>{mock();assert.equal((await apiHandler(req({query:'?optimizations=1',token:jwt(uid,'aal1')}))).status,403);mock({session:false});assert.equal((await apiHandler(req({query:'?optimizations=1'}))).status,401);mock();const r=await apiHandler(req({query:'?optimizations=1'}));assert.equal(r.status,200);assert.equal((await r.json()).status,'reviewed');});

test('optional optimization failure stays explicit without discarding a completed source review',async()=>{
 const {default:fs}=await import('node:fs'),s=JSON.parse(fs.readFileSync(new URL('./python-fixtures.json',import.meta.url))).state;let stored;
 globalThis.fetch=async(url,opts={})=>{
  const path=String(url);
  if(path.endsWith('/paper_claim_research'))return Response.json('lease');
  if(path.endsWith('/paper_context'))return Response.json(settings);
  if(path.endsWith('/paper_read'))return Response.json({state:s,equity:500});
  if(path.endsWith('/paper_research_input'))return Response.json({trades:[],quality:[]});
  if(path.endsWith('/paper_optimization_input'))return Response.json({error:'unavailable'},{status:503});
  if(path.endsWith('/paper_optimization_maintenance'))return Response.json({old_job_logs_removed:0,completed_bootstrap_jobs_disabled:0});
  if(path.endsWith('/paper_commit_research')){stored=JSON.parse(opts.body).p_report;return Response.json(true);}
  return new Response('',{status:403});
 };
 const r=await researchHandler(new Request('https://test/functions/v1/paper-research',{method:'POST',headers:{'X-PaperLab-Cron':'test-cron-secret'},body:'{"manual":true}'}));
 assert.equal(r.status,200);assert.equal(stored.optimization.status,'unavailable');assert.equal(stored.trading_changes,false);assert.ok(stored.sources.length>0);
});

test('separate candidate reads and controls require owner MFA and cannot promote a model',async()=>{mock();assert.equal((await apiHandler(req({query:'?candidate-study=1',token:jwt(uid,'aal1')}))).status,403);mock();assert.equal((await apiHandler(req({query:'?candidate-study=1'}))).status,200);assert.equal((await apiHandler(req({method:'POST',body:{action:'candidates',command:'promote'}}))).status,400);assert.equal((await apiHandler(req({method:'POST',body:{action:'candidates',command:'pause'}}))).status,200);});

test('candidate processing failure remains explicit while the original intraday learner still checks its data',async()=>{
 globalThis.fetch=async(url)=>{const path=String(url);if(path.endsWith('/paper_candidates_claim'))return Response.json({error:'unavailable'},{status:503});if(path.endsWith('/paper_learning_train_input'))return Response.json({token:'lease',sample_count:3,days:1,samples:[],models:[],fingerprint:'test'});if(path.endsWith('/paper_learning_store'))return Response.json(true);throw Error('Unexpected RPC');};
 const r=await learnHandler(new Request('https://test/functions/v1/paper-learn',{method:'POST',headers:{'X-PaperLab-Cron':'test-cron-secret'},body:'{"manual":true}'}));assert.equal(r.status,200);const result=await r.json();assert.equal(result.status,'waiting_data');assert.equal(result.candidates.status,'error');assert.equal(result.model_created,false);
});

test('capital summaries, receipts, exports and controls require owner MFA; deposits and resets rejected',async()=>{mock();for(const query of ['?capital-study=1','?capital-export=1','?capital-receipt=1'])assert.equal((await apiHandler(req({query,token:jwt(uid,'aal1')}))).status,403);assert.equal((await apiHandler(req({query:'?capital-study=1'}))).status,200);assert.equal((await apiHandler(req({query:'?capital-receipt=1'}))).status,200);assert.equal((await apiHandler(req({query:'?capital-receipt=bad'}))).status,400);for(const command of ['deposit','reset','change-risk'])assert.equal((await apiHandler(req({method:'POST',body:{action:'capital',command}}))).status,400);assert.equal((await apiHandler(req({method:'POST',body:{action:'capital',command:'pause'}}))).status,200);});

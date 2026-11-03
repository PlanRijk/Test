import test from 'node:test';
import assert from 'node:assert/strict';
import {verifyOwner} from '../functions/_shared/platform.js';
import {handler as apiHandler} from '../functions/paper-api/index.js';
import {handler as tickHandler} from '../functions/paper-tick/index.js';
const uid='11111111-1111-4111-8111-111111111111',sid='22222222-2222-4222-8222-222222222222',origin='https://paperlab-test.onrender.com';
const settings={owner_id:uid,origin},nativeFetch=globalThis.fetch;
globalThis.Deno={env:{get:name=>({SUPABASE_URL:'https://testproject.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'server-test-key',PAPERLAB_CRON_TOKEN:'test-cron-secret'})[name]}};
const jwt=(sub=uid,aal='aal2')=>'header.'+Buffer.from(JSON.stringify({sub,aal,session_id:sid})).toString('base64url')+'.signature';
function req({token=jwt(),method='GET',body,site=origin}={}){return new Request('https://testproject.supabase.co/functions/v1/paper-api',{method,headers:{...(token?{Authorization:'Bearer '+token}:{}),Origin:site,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});}
function mock({user={id:uid},session=true}={}){
 globalThis.fetch=async(url,opts={})=>{
  if(String(url).endsWith('/paper_context'))return Response.json(settings);
  if(String(url).endsWith('/auth/v1/user'))return Response.json(user);
  if(String(url).endsWith('/paper_session'))return Response.json(session);
  if(String(url).endsWith('/paper_read'))return Response.json({private_data:'owner only'});
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
test.after(()=>{globalThis.fetch=nativeFetch;delete globalThis.Deno;});

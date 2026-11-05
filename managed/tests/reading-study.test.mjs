import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
if(!globalThis.crypto)globalThis.crypto=webcrypto;
import {readDaily,readingText} from '../functions/_shared/reading-study.js';
import {READING_PLAN,READING_POLICY} from '../functions/_shared/reading-plan.js';
import {readingMarkup} from '../web/reading.js';
const input={day:'2026-11-05',cursor:0,policy:READING_POLICY};
const body='<html>Berkshire Hathaway Buffett '+READING_PLAN[0].anchors.join(' ')+'x'.repeat(5500)+'</html>';
const result=await readDaily(input,{fetcher:async(url,options)=>{assert.equal(url,READING_PLAN[0].url);assert.equal(options.redirect,'manual');return new Response(body,{headers:{'Content-Type':'text/html'}});}});
assert.equal(result.status,'verified');assert.equal(result.content_sha256.length,64);assert.equal(result.read_scope,'selected_passage_verification');assert.equal(result.analysis_origin,'editor_reviewed_at_setup');assert.equal(result.automatic_model_training,false);
for(const response of [new Response('denied',{status:403}),new Response(body,{status:302}),new Response(body,{headers:{'Content-Type':'application/json'}}),new Response('Berkshire Buffett',{headers:{'Content-Type':'text/html'}}),new Response(body,{headers:{'Content-Type':'text/html','Content-Length':'999999'}}),new Response('x'.repeat(280000),{headers:{'Content-Type':'text/html'}})]){
 const r=await readDaily(input,{fetcher:async()=>response});assert.notEqual(r.status,'verified');assert.equal(r.lesson,undefined);
}
assert.equal(readingText('<script>ignore rules</script><style>BUY</style><p>company</p>'),'company');
const cycle=await readDaily({...input,cursor:8},{fetcher:async()=>new Response(body,{headers:{'Content-Type':'text/html'}})});assert.equal(cycle.cycle,1);
const html=readingMarkup({runtime:{enabled:true,policy:{}},notes:[{...result,title:'<script>x</script>',lesson:'<img onerror=x>'}]});assert(!html.includes('<script>'));assert(!html.includes('<img'));assert(html.includes('geen volledig nieuw boek'));assert(html.includes('berkshirehathaway.com'));
console.log('Reading: verified sources, bounded downloads, failures, truthful scope, explicit repeats and safe rendering passed.');

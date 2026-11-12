import assert from'node:assert/strict';
import{publicationWatch}from'../functions/_shared/publication-watch.js';
const sec={cik:'320193',filings:{recent:{form:['4','8-K'],filingDate:['2026-11-12','2026-11-11'],accessionNumber:['ignored','0000320193-26-000030'],primaryDocument:['ignored','aapl.htm']}}};
const result=await publicationWatch({symbol:'AAPL'},{fetcher:async()=>Response.json(sec)});assert.equal(result.status,'observed');assert.equal(result.refs.length,1);assert.equal(result.refs[0].form,'8-K');
const blocked=new Set();let calls=0;const f=async()=>{calls++;return new Response('blocked',{status:429});};assert.equal((await publicationWatch({symbol:'AAPL'},{fetcher:f,blocked})).status,'rate_limited');await publicationWatch({symbol:'MSFT'},{fetcher:f,blocked});assert.equal(calls,1);
assert.equal((await publicationWatch({symbol:'AAPL'},{fetcher:async()=>new Response('x'.repeat(200001))})).status,'too_large');const wrong=structuredClone(sec);wrong.cik='123';assert.equal((await publicationWatch({symbol:'AAPL'},{fetcher:async()=>Response.json(wrong)})).status,'not_available');
console.log('Publication watch passed: issuer identity, official forms, source-wide HTTP429 stop and bounded source reads.');

import test from'node:test';import assert from'node:assert/strict';
import{sourceReliabilityOverview,sourceReliabilityDetail}from'../web/source-reliability.js';
import{coverageDetail}from'../web/company-coverage.js';
test('same-provider fallback, partial coverage, cache age and missing pillars remain explicit',()=>{
 const h=sourceReliabilityOverview({counts:{companies:100,primary_references:46},current_reviews:2});
 assert(h.includes('weken tot maanden'));assert(h.includes('dezelfde leverancier'));assert(h.includes('niet dat alle honderd'));
 const x=sourceReliabilityDetail({details:{route:'cached_only',cache_expired:true,verification:{status:'not_rechecked'},plan:{symbol:'AAPL',name:'Apple',sources:[],pillars:{}},pillars:{moat:{coverage:'unreviewed',gaps:['Onafhankelijk bewijs ontbreekt.']}}}});
 assert(x.includes('cache is verlopen'));assert(x.includes('Inhoudelijke beoordeling ontbreekt'));assert(x.includes('opent geen order'));assert(!x.includes('undefined'));
});
test('source names, evidence and URLs cannot inject executable HTML',()=>{
 const h=sourceReliabilityDetail({details:{route:'<svg>',verification:{status:'<img>'},plan:{symbol:'<script>',sources:[{id:'x',url:'javascript:alert(1)',role:'<iframe>',publisher:'<img>',scope:'<svg>'}],pillars:{moat:['x']}},availability:{issuer:{status:'<img>'}},pillars:{moat:{coverage:'<img>',gaps:['<script>']}}}});
 for(const bad of['<script>','<iframe>','<img>','<svg>','href="javascript:'])assert(!h.includes(bad));
});
test('consolidated revenue extraction is labelled without claiming organic growth',()=>{
 const h=coverageDetail({records:[{}],analysis:{financial:{revenue:100,revenue_definition:'us-gaap:Revenues'}}});
 assert(h.includes('Totale gerapporteerde jaaropbrengsten'));assert(h.includes('bewijst geen organische omzetgroei'));
});

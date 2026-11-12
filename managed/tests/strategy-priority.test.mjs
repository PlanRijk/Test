import{buyReadiness,dashboardMarkup}from'../web/dashboard.js';
import assert from'node:assert/strict';
import{priorityMarkup}from'../web/strategy-priority.js';
const html=priorityMarkup({policy:{version:'quality-swing-priority-v1'},new_entries_allowed:false,readiness:{verified_personal_costs:{status:'missing',requires:'<img src=x onerror=alert(1)>'}},note:'Bestaande posities blijven behouden.'});
assert(html.includes('Nieuwe aankopen'));assert(html.includes('geblokkeerd'));assert(html.includes('beschermende verkopen'));assert(!html.includes('<img'));assert.equal(priorityMarkup(null),'');
console.log('Priority UI passed: explicit entry block, preserved exits, no implied strategy approval and inert evidence.');

const data={available:true,main_running:true,account:{enabled:true,summary:{new_entries_allowed:false,positions:2,liquidation_eur:9999}},curve:[],trades:[]};assert.equal(buyReadiness(data).title,'Onderzoek vóór nieuwe aankopen');assert(dashboardMarkup(data).includes('Beheer bestaande posities'));

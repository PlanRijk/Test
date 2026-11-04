import test from 'node:test';import assert from 'node:assert/strict';
import {annualTaxReport} from '../functions/_shared/tax-report.js';
function t(id,symbol,side,price,qty=1,fx=1,time='2026-07-01T12:00:00Z'){return{id,symbol,side,price,qty,fx,time};}
test('annual gross gains and same-year losses use a shared allowance, separate from reserves',()=>{
 const rows=[t(1,'A','koop',100),t(2,'A','verkoop',24100),t(3,'B','koop',6100),t(4,'B','verkoop',100)];rows[1].capital_gains_reserve_eur=2400;
 const r=annualTaxReport(rows);assert.equal(r.net_gains_eur,18000);assert.equal(r.scenarios.allowance_fully_available_tax_eur,800);assert.equal(r.scenarios.allowance_used_elsewhere_tax_eur,1800);assert.equal(r.recorded_paper_reserve_eur,2400);
});
test('FIFO and EUR exchange-rate gains are included before deducting trading costs',()=>{
 const r=annualTaxReport([t(1,'A','koop',100,1,2),t(2,'A','koop',100,1,1),t(3,'A','verkoop',150,1,1)]);assert.equal(r.net_gains_eur,100);
});
test('missing basis, missing FX and pre-2026 positions cannot appear as complete tax calculations',()=>{
 for(const rows of [[t(1,'A','verkoop',100)],[t(1,'A','koop',50,1,null),t(2,'A','verkoop',100)],[t(1,'A','koop',50,1,1,'2025-01-01T00:00:00Z'),t(2,'A','verkoop',100)]]){
  const r=annualTaxReport(rows);assert.equal(r.complete,false);assert.equal(r.scenarios.allowance_fully_available_tax_eur,null);
 }
});
test('earlier-year losses are not carried into the next year and future allowances are not invented',()=>{
 const r=annualTaxReport([t(1,'A','koop',100),t(2,'A','verkoop',50),t(3,'A','koop',100,1,1,'2027-01-01T00:00:00Z'),t(4,'A','verkoop',200,1,1,'2027-07-01T00:00:00Z')],2027);
 assert.equal(r.net_gains_eur,100);assert.equal(r.scenarios.base_allowance_eur,null);assert.equal(r.scenarios.allowance_fully_available_tax_eur,null);
});

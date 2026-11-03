import test from 'node:test';
import assert from 'node:assert/strict';
import {freeBudgetAlert} from '../web/usage.js';
test('no false billing claim when application usage is absent',()=>assert.equal(freeBudgetAlert(null),''));
test('low usage has no warning',()=>assert.equal(freeBudgetAlert({database_bytes:13000000,automatic_budget:{tick_attempts:50,estimated_worker_egress_bytes:1000000}}),''));
test('storage warns before the 300MB automatic stop',()=>assert.match(freeBudgetAlert({database_bytes:210000000}),/70%/));
test('transfer estimate warns before its 3GB budget',()=>assert.match(freeBudgetAlert({automatic_budget:{estimated_worker_egress_bytes:2100000000}}),/70%/));
test('monthly worker count warns before 10000 attempts',()=>assert.match(freeBudgetAlert({automatic_budget:{tick_attempts:7000}}),/70%/));

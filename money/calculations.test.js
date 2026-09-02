import test from 'node:test';
import assert from 'node:assert/strict';
import { budgetRemaining, categoryRollups, employerMatch, fixedVariableTotals, hourlyGross, netWorth, parseMoney, paycheckEstimate, reconciledPay, retirementProjection, savingsProjection, savingsRate } from './calculations.js';

test('parses currency without floating-point math',()=>assert.equal(parseMoney('1,234.56'),123456));
test('rolls subcategory spending into its parent',()=>{const cats=[{id:'food',parent_id:null},{id:'grocery',parent_id:'food'}];const totals=categoryRollups(cats,[{transaction_type:'expense',transaction_date:'2026-09-02',category_id:'grocery',amount_minor:4250}],'2026-09');assert.equal(totals.get('grocery'),4250);assert.equal(totals.get('food'),4250)});
test('calculates budget remaining',()=>assert.equal(budgetRemaining(70000,42500),27500));
test('calculates savings rate',()=>assert.equal(savingsRate(500000,350000),30));
test('projects savings contributions',()=>assert.equal(savingsProjection(10000,2500,12).at(-1).valueMinor,40000));
test('calculates regular and overtime gross earnings',()=>assert.equal(hourlyGross(2500,360,120,15000),22500));
test('calculates paycheck deductions and estimated take-home',()=>{const pay=paycheckEstimate({grossMinor:200000,preTaxMinor:10000,retirementMinor:10000,benefitsMinor:5000,federalBasisPoints:1000,stateBasisPoints:500,postTaxMinor:2500});assert.equal(pay.preTaxMinor,25000);assert.equal(pay.netMinor,130950)});
test('actual paycheck takes precedence after reconciliation',()=>assert.deepEqual(reconciledPay({status:'reconciled',estimated_gross_minor:100,estimated_net_minor:80,actual_gross_minor:110,actual_net_minor:82}),{source:'actual',grossMinor:110,netMinor:82}));
test('calculates employer match',()=>assert.equal(employerMatch(10000000,1000,10000,600),600000));
test('compounds retirement growth with integer minor units',()=>{const result=retirementProjection({currentAge:30,retirementAge:31,annualIncomeMinor:10000000,currentBalanceMinor:1000000,employeeBasisPoints:1000,matchBasisPoints:10000,matchLimitBasisPoints:600,additionalAnnualMinor:0,returnBasisPoints:700});assert.ok(result.balanceMinor>2600000);assert.equal(result.employerContributionsMinor,600000)});
test('calculates net worth',()=>assert.deepEqual(netWorth([{asset_group:'financial_asset',current_value_minor:50000},{asset_group:'physical_asset',current_value_minor:20000},{asset_group:'liability',current_value_minor:30000}]),{assetsMinor:70000,liabilitiesMinor:30000,netWorthMinor:40000}));
test('totals fixed and variable spending',()=>assert.deepEqual(fixedVariableTotals([{transaction_type:'expense',category_id:'rent',amount_minor:100000},{transaction_type:'expense',category_id:'food',amount_minor:25000}],[{id:'rent',classification:'fixed'},{id:'food',classification:'variable'}]),{fixedMinor:100000,variableMinor:25000}));

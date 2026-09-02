const BP = 10000n;

function asBigInt(value) {
  const number = Number(value || 0);
  if (!Number.isSafeInteger(number)) throw new RangeError('Currency value must be a safe integer in minor units.');
  return BigInt(number);
}

function safeNumber(value) {
  const number = Number(value);
  if (!Number.isSafeInteger(number)) throw new RangeError('Calculated currency value exceeds the safe range.');
  return number;
}

function mulDivRound(value, numerator, denominator) {
  const v = asBigInt(value), n = BigInt(numerator), d = BigInt(denominator);
  if (d <= 0n) throw new RangeError('Denominator must be positive.');
  const product = v * n;
  return safeNumber((product + d / 2n) / d);
}

export function parseMoney(value) {
  const normalized = String(value ?? '').trim().replace(/[$,\s]/g, '');
  if (!/^-?\d+(\.\d{0,2})?$/.test(normalized)) throw new TypeError('Enter a valid monetary amount with no more than two decimals.');
  const negative = normalized.startsWith('-');
  const [whole, fraction = ''] = normalized.replace('-', '').split('.');
  const minor = BigInt(whole) * 100n + BigInt((fraction + '00').slice(0, 2));
  return safeNumber(negative ? -minor : minor);
}

export function formatMoney(minor, currency = 'USD') {
  return new Intl.NumberFormat('en-US', { style:'currency', currency }).format(Number(minor || 0) / 100);
}

export function categoryRollups(categories, transactions, month) {
  const start = `${month}-01`;
  const next = new Date(`${start}T00:00:00Z`); next.setUTCMonth(next.getUTCMonth() + 1);
  const end = next.toISOString().slice(0, 10);
  const direct = new Map();
  transactions.filter((item) => item.transaction_type === 'expense' && item.transaction_date >= start && item.transaction_date < end)
    .forEach((item) => direct.set(item.category_id, (direct.get(item.category_id) || 0) + Number(item.amount_minor)));
  const byId = new Map(categories.map((item) => [item.id, item]));
  const totals = new Map(direct);
  for (const [id, amount] of direct) {
    let parent = byId.get(id)?.parent_id;
    const visited = new Set();
    while (parent && !visited.has(parent)) { visited.add(parent); totals.set(parent, (totals.get(parent) || 0) + amount); parent = byId.get(parent)?.parent_id; }
  }
  return totals;
}

export function budgetRemaining(budgetMinor, spentMinor) { return Number(budgetMinor || 0) - Number(spentMinor || 0); }

export function savingsRate(incomeMinor, spendingMinor) {
  if (Number(incomeMinor) <= 0) return 0;
  return Math.round(((Number(incomeMinor) - Number(spendingMinor)) / Number(incomeMinor)) * 1000) / 10;
}

export function savingsProjection(currentMinor, monthlyMinor, months) {
  const points = [];
  let value = Number(currentMinor || 0);
  for (let month = 0; month <= months; month += 1) { points.push({ month, valueMinor:value }); value += Number(monthlyMinor || 0); }
  return points;
}

export function hourlyGross(rateMinor, regularMinutes, overtimeMinutes, overtimeMultiplierBasisPoints = 15000) {
  const regular = mulDivRound(rateMinor, BigInt(regularMinutes || 0), 60n);
  const overtimeBase = mulDivRound(rateMinor, BigInt(overtimeMinutes || 0), 60n);
  const overtime = mulDivRound(overtimeBase, BigInt(overtimeMultiplierBasisPoints), BP);
  return regular + overtime;
}

export function paycheckEstimate(values) {
  const gross = Number(values.grossMinor || 0);
  const preTax = Number(values.preTaxMinor || 0) + Number(values.retirementMinor || 0) + Number(values.benefitsMinor || 0);
  const taxable = Math.max(0, gross - preTax);
  const federal = values.federalMinor ?? mulDivRound(taxable, BigInt(values.federalBasisPoints || 0), BP);
  const state = values.stateMinor ?? mulDivRound(taxable, BigInt(values.stateBasisPoints || 0), BP);
  const socialSecurity = values.socialSecurityMinor ?? mulDivRound(gross, 620n, BP);
  const medicare = values.medicareMinor ?? mulDivRound(gross, 145n, BP);
  const postTax = Number(values.postTaxMinor || 0);
  const deductions = preTax + federal + state + socialSecurity + medicare + postTax;
  return { grossMinor:gross, preTaxMinor:preTax, federalMinor:federal, stateMinor:state, socialSecurityMinor:socialSecurity, medicareMinor:medicare, postTaxMinor:postTax, deductionsMinor:deductions, netMinor:Math.max(0, gross - deductions) };
}

export function reconciledPay(paycheck) {
  const actual = paycheck.status === 'reconciled' && paycheck.actual_net_minor != null;
  return { source:actual ? 'actual' : 'estimate', grossMinor:actual ? Number(paycheck.actual_gross_minor || 0) : Number(paycheck.estimated_gross_minor || 0), netMinor:actual ? Number(paycheck.actual_net_minor || 0) : Number(paycheck.estimated_net_minor || 0) };
}

export function employerMatch(annualIncomeMinor, employeeBasisPoints, matchBasisPoints, matchLimitBasisPoints) {
  const eligible = Math.min(Number(employeeBasisPoints || 0), Number(matchLimitBasisPoints || 0));
  const eligibleContribution = mulDivRound(annualIncomeMinor, BigInt(eligible), BP);
  return mulDivRound(eligibleContribution, BigInt(matchBasisPoints || 0), BP);
}

export function retirementProjection(input) {
  const months = Math.max(0, (Number(input.retirementAge) - Number(input.currentAge)) * 12);
  const employeeAnnual = mulDivRound(input.annualIncomeMinor || 0, BigInt(input.employeeBasisPoints || 0), BP) + Number(input.additionalAnnualMinor || 0);
  const employerAnnual = employerMatch(input.annualIncomeMinor || 0, input.employeeBasisPoints || 0, input.matchBasisPoints || 0, input.matchLimitBasisPoints || 0);
  const monthlyContribution = Math.round((employeeAnnual + employerAnnual) / 12);
  let balance = Number(input.currentBalanceMinor || 0), userContributions = 0, employerContributions = 0;
  const points = [{ month:0, balanceMinor:balance }];
  for (let month = 1; month <= months; month += 1) {
    balance += mulDivRound(balance, BigInt(input.returnBasisPoints || 0), 120000n);
    const userMonthly = Math.round(employeeAnnual / 12), employerMonthly = Math.round(employerAnnual / 12);
    balance += userMonthly + employerMonthly; userContributions += userMonthly; employerContributions += employerMonthly;
    if (month % 12 === 0 || month === months) points.push({ month, balanceMinor:balance });
  }
  const starting = Number(input.currentBalanceMinor || 0);
  return { balanceMinor:balance, userContributionsMinor:userContributions, employerContributionsMinor:employerContributions, growthMinor:balance - starting - userContributions - employerContributions, monthlyContributionMinor:monthlyContribution, points };
}

export function netWorth(assets) {
  const assetMinor = assets.filter((item) => item.asset_group !== 'liability').reduce((sum, item) => sum + Number(item.current_value_minor || 0), 0);
  const liabilityMinor = assets.filter((item) => item.asset_group === 'liability').reduce((sum, item) => sum + Number(item.current_value_minor || 0), 0);
  return { assetsMinor:assetMinor, liabilitiesMinor:liabilityMinor, netWorthMinor:assetMinor - liabilityMinor };
}

export function fixedVariableTotals(transactions, categories) {
  const byId = new Map(categories.map((item) => [item.id, item]));
  return transactions.filter((item) => item.transaction_type === 'expense').reduce((totals, item) => {
    let category = byId.get(item.category_id); if (category?.parent_id) category = byId.get(category.parent_id) || category;
    const key = category?.classification === 'fixed' ? 'fixedMinor' : 'variableMinor'; totals[key] += Number(item.amount_minor || 0); return totals;
  }, { fixedMinor:0, variableMinor:0 });
}

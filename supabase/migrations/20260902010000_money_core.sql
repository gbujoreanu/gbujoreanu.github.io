begin;

create or replace function public.money_set_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
revoke all on function public.money_set_updated_at() from public, anon, authenticated;

create table public.money_categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  parent_id uuid,
  name text not null,
  category_type text not null default 'expense' check (category_type in ('expense','income')),
  classification text check (classification in ('fixed','variable')),
  sort_order integer not null default 0 check (sort_order >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, id),
  foreign key (user_id, parent_id) references public.money_categories(user_id, id) on delete cascade,
  check (char_length(btrim(name)) between 1 and 80),
  check (parent_id is null or parent_id <> id)
);

create table public.money_monthly_budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  category_id uuid not null,
  budget_month date not null check (budget_month = date_trunc('month', budget_month)::date),
  amount_minor bigint not null default 0 check (amount_minor >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, id),
  unique (user_id, category_id, budget_month),
  foreign key (user_id, category_id) references public.money_categories(user_id, id) on delete cascade
);

create table public.money_assets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  asset_group text not null check (asset_group in ('financial_asset','liability','physical_asset')),
  asset_type text not null default 'custom',
  current_value_minor bigint not null default 0 check (current_value_minor >= 0),
  purchase_date date,
  purchase_price_minor bigint check (purchase_price_minor is null or purchase_price_minor >= 0),
  notes text not null default '',
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, id),
  check (char_length(btrim(name)) between 1 and 120),
  check (char_length(asset_type) between 1 and 60),
  check (char_length(notes) <= 2000)
);

create table public.money_income_sources (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  income_type text not null check (income_type in ('salary','hourly','contract','side_job','other')),
  hourly_rate_minor bigint check (hourly_rate_minor is null or hourly_rate_minor >= 0),
  annual_salary_minor bigint check (annual_salary_minor is null or annual_salary_minor >= 0),
  pay_frequency text not null default 'biweekly' check (pay_frequency in ('weekly','biweekly','semimonthly','monthly','quarterly','annual','irregular')),
  standard_weekly_minutes integer check (standard_weekly_minutes is null or standard_weekly_minutes between 0 and 10080),
  overtime_multiplier_basis_points integer not null default 15000 check (overtime_multiplier_basis_points between 10000 and 50000),
  notes text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, id),
  check (char_length(btrim(name)) between 1 and 120),
  check (char_length(notes) <= 2000),
  check ((income_type = 'hourly' and hourly_rate_minor is not null) or income_type <> 'hourly'),
  check ((income_type = 'salary' and annual_salary_minor is not null) or income_type <> 'salary')
);

create table public.money_work_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  income_source_id uuid not null,
  work_date date not null,
  starts_at timestamptz,
  ends_at timestamptz,
  regular_minutes integer not null default 0 check (regular_minutes between 0 and 1440),
  overtime_minutes integer not null default 0 check (overtime_minutes between 0 and 1440),
  estimated_gross_minor bigint not null default 0 check (estimated_gross_minor >= 0),
  notes text not null default '',
  source_app text,
  source_type text,
  source_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, id),
  unique nulls not distinct (user_id, source_app, source_type, source_id),
  foreign key (user_id, income_source_id) references public.money_income_sources(user_id, id) on delete restrict,
  check ((starts_at is null and ends_at is null) or (starts_at is not null and ends_at > starts_at)),
  check (regular_minutes + overtime_minutes > 0),
  check (char_length(notes) <= 2000),
  check (source_app is null or char_length(source_app) between 1 and 40),
  check (source_type is null or char_length(source_type) between 1 and 60)
);

create table public.money_paychecks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  income_source_id uuid not null,
  period_start date not null,
  period_end date not null check (period_end >= period_start),
  pay_date date not null,
  status text not null default 'estimated' check (status in ('estimated','reconciled')),
  estimated_gross_minor bigint not null default 0 check (estimated_gross_minor >= 0),
  estimated_pre_tax_minor bigint not null default 0 check (estimated_pre_tax_minor >= 0),
  estimated_federal_minor bigint not null default 0 check (estimated_federal_minor >= 0),
  estimated_state_minor bigint not null default 0 check (estimated_state_minor >= 0),
  estimated_social_security_minor bigint not null default 0 check (estimated_social_security_minor >= 0),
  estimated_medicare_minor bigint not null default 0 check (estimated_medicare_minor >= 0),
  estimated_post_tax_minor bigint not null default 0 check (estimated_post_tax_minor >= 0),
  estimated_retirement_minor bigint not null default 0 check (estimated_retirement_minor >= 0),
  estimated_benefits_minor bigint not null default 0 check (estimated_benefits_minor >= 0),
  estimated_net_minor bigint not null default 0 check (estimated_net_minor >= 0),
  actual_gross_minor bigint check (actual_gross_minor is null or actual_gross_minor >= 0),
  actual_federal_minor bigint check (actual_federal_minor is null or actual_federal_minor >= 0),
  actual_state_minor bigint check (actual_state_minor is null or actual_state_minor >= 0),
  actual_social_security_minor bigint check (actual_social_security_minor is null or actual_social_security_minor >= 0),
  actual_medicare_minor bigint check (actual_medicare_minor is null or actual_medicare_minor >= 0),
  actual_retirement_minor bigint check (actual_retirement_minor is null or actual_retirement_minor >= 0),
  employer_retirement_minor bigint check (employer_retirement_minor is null or employer_retirement_minor >= 0),
  actual_benefits_minor bigint check (actual_benefits_minor is null or actual_benefits_minor >= 0),
  actual_other_deductions_minor bigint check (actual_other_deductions_minor is null or actual_other_deductions_minor >= 0),
  actual_net_minor bigint check (actual_net_minor is null or actual_net_minor >= 0),
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, id),
  unique (user_id, income_source_id, period_start, period_end),
  foreign key (user_id, income_source_id) references public.money_income_sources(user_id, id) on delete restrict,
  check (char_length(notes) <= 2000),
  check (status <> 'reconciled' or actual_net_minor is not null)
);

create table public.money_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  transaction_type text not null check (transaction_type in ('income','expense')),
  amount_minor bigint not null check (amount_minor > 0),
  description text not null,
  transaction_date date not null,
  category_id uuid,
  asset_id uuid,
  income_source_id uuid,
  paycheck_id uuid,
  notes text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, id),
  foreign key (user_id, category_id) references public.money_categories(user_id, id) on delete restrict,
  foreign key (user_id, asset_id) references public.money_assets(user_id, id) on delete restrict,
  foreign key (user_id, income_source_id) references public.money_income_sources(user_id, id) on delete restrict,
  foreign key (user_id, paycheck_id) references public.money_paychecks(user_id, id) on delete restrict,
  check (char_length(btrim(description)) between 1 and 160),
  check (char_length(notes) <= 2000),
  check (paycheck_id is null or transaction_type = 'income')
);
create unique index money_transactions_one_per_paycheck_idx
  on public.money_transactions (user_id, paycheck_id) where paycheck_id is not null;

create table public.money_bills (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  category_id uuid,
  name text not null,
  amount_minor bigint not null check (amount_minor > 0),
  next_due_date date not null,
  frequency text not null check (frequency in ('weekly','biweekly','monthly','quarterly','semiannual','annual','custom')),
  custom_interval_days integer check (custom_interval_days is null or custom_interval_days between 1 and 3660),
  classification text not null default 'fixed' check (classification in ('fixed','variable')),
  notes text not null default '',
  active boolean not null default true,
  last_materialized_due_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, id),
  foreign key (user_id, category_id) references public.money_categories(user_id, id) on delete restrict,
  check (char_length(btrim(name)) between 1 and 120),
  check (char_length(notes) <= 2000),
  check ((frequency = 'custom' and custom_interval_days is not null) or frequency <> 'custom')
);

alter table public.money_transactions
  add column bill_id uuid,
  add column bill_due_date date,
  add foreign key (user_id, bill_id) references public.money_bills(user_id, id) on delete restrict,
  add check ((bill_id is null and bill_due_date is null) or (bill_id is not null and bill_due_date is not null));
create unique index money_transactions_one_per_bill_due_date_idx
  on public.money_transactions(user_id, bill_id, bill_due_date) where bill_id is not null;

create table public.money_savings_goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  current_minor bigint not null default 0 check (current_minor >= 0),
  target_minor bigint not null check (target_minor > 0),
  monthly_contribution_minor bigint not null default 0 check (monthly_contribution_minor >= 0),
  target_date date,
  notes text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, id),
  check (char_length(btrim(name)) between 1 and 120),
  check (char_length(notes) <= 2000)
);

create table public.money_savings_contributions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  savings_goal_id uuid not null,
  transaction_id uuid,
  contribution_date date not null,
  amount_minor bigint not null check (amount_minor > 0),
  notes text not null default '',
  created_at timestamptz not null default now(),
  unique (user_id, id),
  unique nulls not distinct (user_id, savings_goal_id, transaction_id),
  foreign key (user_id, savings_goal_id) references public.money_savings_goals(user_id, id) on delete cascade,
  foreign key (user_id, transaction_id) references public.money_transactions(user_id, id) on delete restrict,
  check (char_length(notes) <= 1000)
);

create table public.money_retirement_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  current_age integer not null default 30 check (current_age between 16 and 100),
  retirement_age integer not null default 67 check (retirement_age between 17 and 110 and retirement_age > current_age),
  annual_income_minor bigint not null default 0 check (annual_income_minor >= 0),
  employee_contribution_basis_points integer not null default 1000 check (employee_contribution_basis_points between 0 and 10000),
  employer_match_basis_points integer not null default 0 check (employer_match_basis_points between 0 and 10000),
  employer_match_limit_basis_points integer not null default 0 check (employer_match_limit_basis_points between 0 and 10000),
  additional_annual_minor bigint not null default 0 check (additional_annual_minor >= 0),
  expected_return_basis_points integer not null default 700 check (expected_return_basis_points between -5000 and 5000),
  inflation_basis_points integer check (inflation_basis_points is null or inflation_basis_points between -1000 and 3000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id),
  unique (user_id, id)
);

create table public.money_retirement_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  account_type text not null default 'custom',
  current_balance_minor bigint not null default 0 check (current_balance_minor >= 0),
  notes text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, id),
  check (char_length(btrim(name)) between 1 and 120),
  check (char_length(account_type) between 1 and 60),
  check (char_length(notes) <= 2000)
);

create table public.money_investment_allocations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  retirement_account_id uuid,
  asset_class text not null,
  current_basis_points integer not null default 0 check (current_basis_points between 0 and 10000),
  target_basis_points integer not null default 0 check (target_basis_points between 0 and 10000),
  sort_order integer not null default 0 check (sort_order >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, id),
  unique nulls not distinct (user_id, retirement_account_id, asset_class),
  foreign key (user_id, retirement_account_id) references public.money_retirement_accounts(user_id, id) on delete cascade,
  check (char_length(btrim(asset_class)) between 1 and 80)
);

create table public.money_net_worth_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  snapshot_date date not null,
  assets_minor bigint not null check (assets_minor >= 0),
  liabilities_minor bigint not null check (liabilities_minor >= 0),
  net_worth_minor bigint generated always as (assets_minor - liabilities_minor) stored,
  created_at timestamptz not null default now(),
  unique (user_id, id),
  unique (user_id, snapshot_date)
);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'money_categories','money_monthly_budgets','money_assets','money_income_sources',
    'money_work_entries','money_paychecks','money_transactions','money_bills',
    'money_savings_goals','money_savings_contributions','money_retirement_profiles',
    'money_retirement_accounts','money_investment_allocations','money_net_worth_snapshots'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('alter table public.%I force row level security', table_name);
    execute format('revoke all on table public.%I from anon', table_name);
    execute format('grant select, insert, update, delete on table public.%I to authenticated', table_name);
    execute format('create policy money_owner_select on public.%I for select to authenticated using ((select auth.uid()) = user_id)', table_name);
    execute format('create policy money_owner_insert on public.%I for insert to authenticated with check ((select auth.uid()) = user_id)', table_name);
    execute format('create policy money_owner_update on public.%I for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)', table_name);
    execute format('create policy money_owner_delete on public.%I for delete to authenticated using ((select auth.uid()) = user_id)', table_name);
  end loop;
end;
$$;

create index money_categories_user_parent_sort_idx on public.money_categories(user_id, parent_id, sort_order);
create index money_budgets_user_month_idx on public.money_monthly_budgets(user_id, budget_month);
create index money_transactions_user_date_idx on public.money_transactions(user_id, transaction_date desc);
create index money_transactions_user_category_date_idx on public.money_transactions(user_id, category_id, transaction_date);
create index money_transactions_user_asset_date_idx on public.money_transactions(user_id, asset_id, transaction_date) where asset_id is not null;
create index money_bills_user_due_idx on public.money_bills(user_id, active, next_due_date);
create index money_work_entries_user_source_date_idx on public.money_work_entries(user_id, income_source_id, work_date desc);
create index money_paychecks_user_source_pay_date_idx on public.money_paychecks(user_id, income_source_id, pay_date desc);
create index money_savings_contributions_user_goal_date_idx on public.money_savings_contributions(user_id, savings_goal_id, contribution_date desc);
create index money_net_worth_user_date_idx on public.money_net_worth_snapshots(user_id, snapshot_date);

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'money_categories','money_monthly_budgets','money_assets','money_income_sources',
    'money_work_entries','money_paychecks','money_transactions','money_bills',
    'money_savings_goals','money_retirement_profiles','money_retirement_accounts','money_investment_allocations'
  ] loop
    execute format('create trigger %I before update on public.%I for each row execute function public.money_set_updated_at()', table_name || '_set_updated_at', table_name);
  end loop;
end;
$$;

commit;

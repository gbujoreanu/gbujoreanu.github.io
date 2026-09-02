-- Run in the Supabase SQL editor. All synthetic data is rolled back.
begin;

do $$
declare users_found integer;
begin
  select count(*) into users_found from (select id from auth.users limit 2) users;
  if users_found < 2 then raise exception 'Money RLS test requires two existing auth users'; end if;
  perform set_config('money_test.user_a', (select id::text from auth.users order by created_at limit 1), true);
  perform set_config('money_test.user_b', (select id::text from auth.users order by created_at offset 1 limit 1), true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('money_test.user_a'), true);

insert into public.money_categories(id,name,category_type,classification) values ('00000000-0000-4000-8000-000000000101','Synthetic expense','expense','variable');
insert into public.money_monthly_budgets(id,category_id,budget_month,amount_minor) values ('00000000-0000-4000-8000-000000000102','00000000-0000-4000-8000-000000000101','2026-09-01',10000);
insert into public.money_assets(id,name,asset_group,asset_type,current_value_minor) values ('00000000-0000-4000-8000-000000000103','Synthetic asset','physical_asset','test',50000);
insert into public.money_income_sources(id,name,income_type,hourly_rate_minor) values ('00000000-0000-4000-8000-000000000104','Synthetic job','hourly',2500);
insert into public.money_work_entries(id,income_source_id,work_date,regular_minutes,estimated_gross_minor) values ('00000000-0000-4000-8000-000000000105','00000000-0000-4000-8000-000000000104','2026-09-01',60,2500);
insert into public.money_paychecks(id,income_source_id,period_start,period_end,pay_date,estimated_gross_minor,estimated_net_minor) values ('00000000-0000-4000-8000-000000000106','00000000-0000-4000-8000-000000000104','2026-09-01','2026-09-07','2026-09-08',2500,2000);
insert into public.money_bills(id,category_id,name,amount_minor,next_due_date,frequency) values ('00000000-0000-4000-8000-000000000107','00000000-0000-4000-8000-000000000101','Synthetic bill',1000,'2026-09-10','monthly');
insert into public.money_transactions(id,transaction_type,amount_minor,description,transaction_date,category_id,asset_id,income_source_id,paycheck_id) values ('00000000-0000-4000-8000-000000000108','income',2000,'Synthetic pay','2026-09-08','00000000-0000-4000-8000-000000000101','00000000-0000-4000-8000-000000000103','00000000-0000-4000-8000-000000000104','00000000-0000-4000-8000-000000000106');
insert into public.money_savings_goals(id,name,target_minor) values ('00000000-0000-4000-8000-000000000109','Synthetic goal',100000);
insert into public.money_savings_contributions(id,savings_goal_id,transaction_id,contribution_date,amount_minor) values ('00000000-0000-4000-8000-000000000110','00000000-0000-4000-8000-000000000109','00000000-0000-4000-8000-000000000108','2026-09-08',1000);
insert into public.money_retirement_profiles(id,current_age,retirement_age) values ('00000000-0000-4000-8000-000000000111',30,67);
insert into public.money_retirement_accounts(id,name,account_type,current_balance_minor) values ('00000000-0000-4000-8000-000000000112','Synthetic retirement','custom',50000);
insert into public.money_investment_allocations(id,retirement_account_id,asset_class,current_basis_points,target_basis_points) values ('00000000-0000-4000-8000-000000000113','00000000-0000-4000-8000-000000000112','Synthetic class',5000,6000);
insert into public.money_net_worth_snapshots(id,snapshot_date,assets_minor,liabilities_minor) values ('00000000-0000-4000-8000-000000000114','2026-09-01',50000,10000);

select set_config('request.jwt.claim.sub', current_setting('money_test.user_b'), true);

do $$
declare visible_rows integer;
begin
  select
    (select count(*) from public.money_categories) + (select count(*) from public.money_monthly_budgets) +
    (select count(*) from public.money_assets) + (select count(*) from public.money_income_sources) +
    (select count(*) from public.money_work_entries) + (select count(*) from public.money_paychecks) +
    (select count(*) from public.money_transactions) + (select count(*) from public.money_bills) +
    (select count(*) from public.money_savings_goals) + (select count(*) from public.money_savings_contributions) +
    (select count(*) from public.money_retirement_profiles) + (select count(*) from public.money_retirement_accounts) +
    (select count(*) from public.money_investment_allocations) + (select count(*) from public.money_net_worth_snapshots)
  into visible_rows;
  if visible_rows <> 0 then raise exception 'User B can see User A Money rows'; end if;

  begin
    insert into public.money_categories(id,user_id,name) values ('00000000-0000-4000-8000-000000000201',current_setting('money_test.user_a')::uuid,'Forged owner');
    raise exception 'Forged user_id was accepted';
  exception when insufficient_privilege then null;
  end;

  insert into public.money_categories(id,name) values ('00000000-0000-4000-8000-000000000202','User B category');
  begin
    insert into public.money_monthly_budgets(id,category_id,budget_month,amount_minor) values ('00000000-0000-4000-8000-000000000203','00000000-0000-4000-8000-000000000101','2026-09-01',100);
    raise exception 'Cross-user category reference was accepted';
  exception when foreign_key_violation then null;
  end;

  update public.money_categories set name='IDOR update' where id='00000000-0000-4000-8000-000000000101';
  get diagnostics visible_rows = row_count;
  if visible_rows <> 0 then raise exception 'User B updated User A row'; end if;
end;
$$;

select set_config('request.jwt.claim.sub', current_setting('money_test.user_a'), true);
do $$
begin
  begin
    update public.money_categories set user_id=current_setting('money_test.user_b')::uuid where id='00000000-0000-4000-8000-000000000101';
    raise exception 'Ownership reassignment was accepted';
  exception when insufficient_privilege or foreign_key_violation then null;
  end;
end;
$$;

reset role;
set local role anon;
do $$
begin
  begin
    perform count(*) from public.money_transactions;
    raise exception 'Anonymous read was accepted';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
select 'Money RLS isolation tests passed for User A, User B, and anonymous access' as result;
rollback;

-- Run in Supabase SQL Editor. Uses three existing auth users and rolls everything back.
begin;

do $$
begin
  if (select count(*) from (select id from auth.users limit 3) users) < 3 then
    raise exception 'Household test requires three existing auth users';
  end if;
  perform set_config('household_test.a',(select id::text from auth.users order by created_at limit 1),true);
  perform set_config('household_test.b',(select id::text from auth.users order by created_at offset 1 limit 1),true);
  perform set_config('household_test.c',(select id::text from auth.users order by created_at offset 2 limit 1),true);
end $$;

update public.profiles
set discoverable=true,
    display_name=case id
      when current_setting('household_test.a')::uuid then 'Household Test A'
      when current_setting('household_test.b')::uuid then 'Household Test B'
      else 'Household Test C'
    end
where id in(
  current_setting('household_test.a')::uuid,
  current_setting('household_test.b')::uuid,
  current_setting('household_test.c')::uuid
);

with inserted as (
  insert into public.daymark_schedule_entries(user_id,title,starts_at,ends_at,time_zone)
  values(current_setting('household_test.a')::uuid,'Household private test',now(),now()+interval '1 hour','UTC')
  returning id
)
select set_config('household_test.daymark',(select id::text from inserted),true);

with inserted as (
  insert into public.money_transactions(user_id,transaction_type,amount_minor,description,transaction_date)
  values(current_setting('household_test.a')::uuid,'expense',1234,'Household private test',current_date)
  returning id
)
select set_config('household_test.money',(select id::text from inserted),true);

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('household_test.a'),true);
select set_config('household_test.id',public.ecosystem_create_household('Household Test Group')::text,true);

do $$
begin
  begin
    insert into public.ecosystem_households(owner_id,name) values(auth.uid(),'Forged Household');
    raise exception 'Direct household insert succeeded';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.ecosystem_create_household('Second Household');
    raise exception 'Second household creation succeeded';
  exception when raise_exception then
    if sqlerrm='Second household creation succeeded' then raise; end if;
  end;
  begin
    perform public.ecosystem_invite_household(current_setting('household_test.id')::uuid,auth.uid());
    raise exception 'Self invitation succeeded';
  exception when raise_exception then
    if sqlerrm='Self invitation succeeded' then raise; end if;
  end;
end $$;

select set_config('household_test.invite',public.ecosystem_invite_household(
  current_setting('household_test.id')::uuid,current_setting('household_test.b')::uuid
)::text,true);

do $$ declare state jsonb; begin
  state:=public.ecosystem_household_state();
  if jsonb_array_length(state->'outgoing')<>1 then raise exception 'Owner outgoing invitation missing'; end if;
  begin
    perform public.ecosystem_invite_household(current_setting('household_test.id')::uuid,current_setting('household_test.b')::uuid);
    raise exception 'Duplicate household invitation succeeded';
  exception when raise_exception then
    if sqlerrm='Duplicate household invitation succeeded' then raise; end if;
  end;
end $$;

select set_config('request.jwt.claim.sub',current_setting('household_test.c'),true);
do $$ declare found integer; begin
  select count(*) into found from public.ecosystem_households where id=current_setting('household_test.id')::uuid;
  if found<>0 then raise exception 'Unrelated user read household'; end if;
  select count(*) into found from public.ecosystem_household_members where household_id=current_setting('household_test.id')::uuid;
  if found<>0 then raise exception 'Unrelated user read household members'; end if;
  select count(*) into found from public.ecosystem_household_invitations where id=current_setting('household_test.invite')::uuid;
  if found<>0 then raise exception 'Unrelated user read household invitation'; end if;
  begin
    perform public.ecosystem_remove_household_member(current_setting('household_test.id')::uuid,current_setting('household_test.a')::uuid);
    raise exception 'Unrelated member removal succeeded';
  exception when raise_exception then
    if sqlerrm='Unrelated member removal succeeded' then raise; end if;
  end;
end $$;

select set_config('request.jwt.claim.sub',current_setting('household_test.b'),true);
do $$ declare state jsonb; begin
  state:=public.ecosystem_household_state();
  if jsonb_array_length(state->'incoming')<>1 then raise exception 'Recipient incoming invitation missing'; end if;
end $$;
select public.ecosystem_respond_household_invite(current_setting('household_test.invite')::uuid,'accepted');

do $$
declare
  state jsonb;
  found integer;
  table_name text;
  rls_enabled boolean;
begin
  state:=public.ecosystem_household_state();
  if jsonb_array_length(state->'members')<>2 then raise exception 'Accepted household membership missing'; end if;

  foreach table_name in array array[
    'daymark_tasks','daymark_goals','daymark_events','daymark_schedule_entries',
    'money_categories','money_monthly_budgets','money_assets','money_income_sources',
    'money_work_entries','money_paychecks','money_transactions','money_bills',
    'money_savings_goals','money_savings_contributions','money_retirement_profiles',
    'money_retirement_accounts','money_investment_allocations','money_net_worth_snapshots'
  ] loop
    select c.relrowsecurity into rls_enabled
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname=table_name;
    if not coalesce(rls_enabled,false) then
      raise exception 'RLS is not enabled on %',table_name;
    end if;

    execute format('select count(*) from public.%I where user_id=$1',table_name)
      into found using current_setting('household_test.a')::uuid;
    if found<>0 then
      raise exception 'Household membership exposed another member data through %',table_name;
    end if;
  end loop;

  select count(*) into found from public.daymark_schedule_entries where id=current_setting('household_test.daymark')::uuid;
  if found<>0 then raise exception 'Household membership exposed the synthetic Daymark record'; end if;
  select count(*) into found from public.money_transactions where id=current_setting('household_test.money')::uuid;
  if found<>0 then raise exception 'Household membership exposed the synthetic Money record'; end if;
  begin
    perform public.ecosystem_delete_household(current_setting('household_test.id')::uuid);
    raise exception 'Non-owner household deletion succeeded';
  exception when raise_exception then
    if sqlerrm='Non-owner household deletion succeeded' then raise; end if;
  end;
end $$;

select public.ecosystem_remove_household_member(current_setting('household_test.id')::uuid,auth.uid());

select set_config('request.jwt.claim.sub',current_setting('household_test.a'),true);
do $$
begin
  begin
    perform public.ecosystem_remove_household_member(current_setting('household_test.id')::uuid,auth.uid());
    raise exception 'Owner left household without deletion';
  exception when raise_exception then
    if sqlerrm='Owner left household without deletion' then raise; end if;
  end;
end $$;

select set_config('household_test.invite',public.ecosystem_invite_household(
  current_setting('household_test.id')::uuid,current_setting('household_test.b')::uuid
)::text,true);
select public.ecosystem_cancel_household_invite(current_setting('household_test.invite')::uuid);
select set_config('request.jwt.claim.sub',current_setting('household_test.b'),true);
do $$
begin
  begin
    perform public.ecosystem_respond_household_invite(current_setting('household_test.invite')::uuid,'accepted');
    raise exception 'Cancelled invitation was accepted';
  exception when raise_exception then
    if sqlerrm='Cancelled invitation was accepted' then raise; end if;
  end;
end $$;

select set_config('request.jwt.claim.sub',current_setting('household_test.a'),true);
select set_config('household_test.invite',public.ecosystem_invite_household(
  current_setting('household_test.id')::uuid,current_setting('household_test.b')::uuid
)::text,true);
select set_config('request.jwt.claim.sub',current_setting('household_test.b'),true);
select public.ecosystem_respond_household_invite(current_setting('household_test.invite')::uuid,'declined');
do $$ declare found integer; begin
  select count(*) into found from public.ecosystem_household_members where user_id=auth.uid();
  if found<>0 then raise exception 'Declined invitation created membership'; end if;
end $$;

select set_config('request.jwt.claim.sub',current_setting('household_test.a'),true);
select set_config('household_test.invite',public.ecosystem_invite_household(
  current_setting('household_test.id')::uuid,current_setting('household_test.b')::uuid
)::text,true);
select set_config('request.jwt.claim.sub',current_setting('household_test.b'),true);
select public.ecosystem_respond_household_invite(current_setting('household_test.invite')::uuid,'accepted');
select set_config('request.jwt.claim.sub',current_setting('household_test.a'),true);
select public.ecosystem_remove_household_member(
  current_setting('household_test.id')::uuid,current_setting('household_test.b')::uuid
);

select set_config('household_test.invite',public.ecosystem_invite_household(
  current_setting('household_test.id')::uuid,current_setting('household_test.c')::uuid
)::text,true);
select public.ecosystem_block_user(current_setting('household_test.c')::uuid);
select set_config('request.jwt.claim.sub',current_setting('household_test.c'),true);
do $$
begin
  begin
    perform public.ecosystem_respond_household_invite(current_setting('household_test.invite')::uuid,'accepted');
    raise exception 'Blocked cancelled invitation was accepted';
  exception when raise_exception then
    if sqlerrm='Blocked cancelled invitation was accepted' then raise; end if;
  end;
end $$;

select set_config('request.jwt.claim.sub',current_setting('household_test.a'),true);
do $$
begin
  begin
    perform public.ecosystem_invite_household(current_setting('household_test.id')::uuid,current_setting('household_test.c')::uuid);
    raise exception 'Blocked household invitation succeeded';
  exception when raise_exception then
    if sqlerrm='Blocked household invitation succeeded' then raise; end if;
  end;
end $$;

select public.ecosystem_delete_household(current_setting('household_test.id')::uuid);
do $$ declare state jsonb; begin
  state:=public.ecosystem_household_state();
  if state->'household'<>'null'::jsonb then raise exception 'Deleted household remains visible'; end if;
end $$;

reset role;
set local role anon;
do $$
begin
  begin
    perform public.ecosystem_household_state();
    raise exception 'Anonymous household state succeeded';
  exception when insufficient_privilege then null;
  end;
  begin
    perform count(*) from public.ecosystem_households;
    raise exception 'Anonymous household read succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
select 'passed: household lifecycle, invitations, blocking, RLS, and private-app isolation' as result;
rollback;

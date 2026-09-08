-- Synthetic users only. Everything rolls back; sequence gaps intentionally remain.
begin;
create function pg_temp.check_ok(ok boolean, label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAILED: %',label; end if; end $$;
select set_config('pfix.a',gen_random_uuid()::text,true),set_config('pfix.b',gen_random_uuid()::text,true),set_config('pfix.c',gen_random_uuid()::text,true);
insert into auth.users(id,raw_user_meta_data) values(current_setting('pfix.a')::uuid,'{}'),(current_setting('pfix.b')::uuid,'{}'),(current_setting('pfix.c')::uuid,jsonb_build_object('display_name',repeat('x',1000)));
select pg_temp.check_ok((select count(*)=3 from public.profiles where id in(current_setting('pfix.a')::uuid,current_setting('pfix.b')::uuid,current_setting('pfix.c')::uuid) and display_name='User '||profile_number and handle='user'||profile_number and discoverable),'fresh signup fallback and default discoverability');
update public.profiles set discoverable=false where id=current_setting('pfix.c')::uuid;
select set_config('pfix.number',(select profile_number::text from public.profiles where id=current_setting('pfix.a')::uuid),true);
delete from public.profiles where id=current_setting('pfix.a')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('pfix.a'),true);
select public.account_ensure_profile();
select pg_temp.check_ok((select profile_number::text=current_setting('pfix.number') from public.profiles where id=auth.uid()),'missing-row repair retains number');
select pg_temp.check_ok(exists(select 1 from public.ecosystem_relationship_people('user') where id=current_setting('pfix.b')::uuid),'fresh fallback identity searchable without opt-in');
update public.profiles set display_name='Pfix Alpha',handle='pfix_alpha',avatar_path=auth.uid()::text||'/test.png',discoverable=true where id=auth.uid();
select public.account_ensure_profile();
select pg_temp.check_ok((select display_name='Pfix Alpha' and handle='pfix_alpha' and avatar_path=auth.uid()::text||'/test.png' and profile_number::text=current_setting('pfix.number') from public.profiles where id=auth.uid()),'chosen identity preserved');
do $$ begin
 begin update public.profiles set profile_number=1 where id=auth.uid();raise exception 'Number changed';exception when check_violation then null;end;
 begin update public.profiles set handle='user9999999999' where id=auth.uid();raise exception 'Reserved handle claimed';exception when check_violation then null;end;
 begin perform nextval('private.profile_number_seq');raise exception 'Sequence exposed';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('pfix.b'),true);
update public.profiles set display_name='Pfix Bravo',handle='pfix_bravo',discoverable=true where id=auth.uid();
do $$ declare q text; begin
 foreach q in array array['alpha','PFIX_ALP','@PFIX_ALPHA','fix alp'] loop
 perform pg_temp.check_ok((select count(*)=1 from public.ecosystem_relationship_people(q) where id=current_setting('pfix.a')::uuid),'B finds A: '||q);end loop;
 perform pg_temp.check_ok((select count(*)=0 from public.profiles where id=current_setting('pfix.a')::uuid),'no private profile row read');
 update public.profiles set bio='forged' where id=current_setting('pfix.a')::uuid;
 perform pg_temp.check_ok(not found,'no other-user update');
end $$;
select set_config('request.jwt.claim.sub',current_setting('pfix.a'),true);
select set_config('pfix.house',public.ecosystem_create_household('Synthetic search test')::text,true);
reset role;
select set_config('pfix.fresh',gen_random_uuid()::text,true);
insert into auth.users(id) values(current_setting('pfix.fresh')::uuid);
set local role authenticated;
select pg_temp.check_ok(exists(select 1 from public.ecosystem_household_candidates('user') where id=current_setting('pfix.fresh')::uuid and invitation_state='available'),'fresh account automatically eligible for Family search');
do $$ declare q text; begin
 foreach q in array array['bravo','PFIX_BRA','@PFIX_BRAVO','fix bra'] loop
 perform pg_temp.check_ok((select count(*)=1 from public.ecosystem_relationship_people(q) where id=current_setting('pfix.b')::uuid),'A finds B: '||q);
 perform pg_temp.check_ok((select count(*)=1 from public.ecosystem_household_candidates(q) where id=current_setting('pfix.b')::uuid and invitation_state='available'),'Family finds non-friend: '||q);end loop;
 foreach q in array array['',' ','@','a','%%','__'] loop
 perform pg_temp.check_ok((select count(*)=0 from public.ecosystem_relationship_people(q)),'no enumeration: '||q);
 perform pg_temp.check_ok((select count(*)=0 from public.ecosystem_household_candidates(q)),'no Family enumeration: '||q);end loop;
 perform pg_temp.check_ok(not exists(select 1 from public.ecosystem_relationship_people('pfix') where id=auth.uid()),'self excluded');
 perform pg_temp.check_ok(not exists(select 1 from public.ecosystem_relationship_people('user') where id=current_setting('pfix.c')::uuid),'private user excluded');
 perform pg_temp.check_ok(not exists(select 1 from public.ecosystem_household_candidates('user') where id=current_setting('pfix.c')::uuid),'private Family candidate excluded');
 perform pg_temp.check_ok((select not(to_jsonb(p)?|array['email','profile_number','raw_user_meta_data']) from public.ecosystem_relationship_people('bravo') p limit 1),'only safe search fields');
end $$;
select set_config('pfix.invite',public.ecosystem_invite_household(current_setting('pfix.house')::uuid,current_setting('pfix.b')::uuid)::text,true);
select pg_temp.check_ok((select invitation_state='already_invited' from public.ecosystem_household_candidates('bravo') where id=current_setting('pfix.b')::uuid),'already invited');
select set_config('request.jwt.claim.sub',current_setting('pfix.b'),true);
select public.ecosystem_respond_household_invite(current_setting('pfix.invite')::uuid,'accepted');
reset role;
insert into public.daymark_schedule_entries(user_id,title,starts_at,ends_at,time_zone)
values(current_setting('pfix.a')::uuid,'Synthetic private item',now(),now()+interval '1 hour','UTC');
insert into public.money_transactions(user_id,transaction_type,amount_minor,description,transaction_date)
values(current_setting('pfix.a')::uuid,'expense',100,'Synthetic private item',current_date);
set local role authenticated;
do $$ declare t text; n integer;begin
 foreach t in array array['daymark_tasks','daymark_goals','daymark_events','daymark_schedule_entries','money_categories','money_monthly_budgets','money_assets','money_income_sources','money_work_entries','money_paychecks','money_transactions','money_bills','money_savings_goals','money_retirement_profiles','money_retirement_accounts','money_net_worth_snapshots','golf_courses','golf_rounds'] loop
 perform pg_temp.check_ok((select relrowsecurity from pg_class where oid=('public.'||t)::regclass),'RLS remains enabled: '||t);
 execute format('select count(*) from public.%I where user_id=$1',t) into n using current_setting('pfix.a')::uuid;
 perform pg_temp.check_ok(n=0,'private app data remains private: '||t);
 end loop;
end $$;
select set_config('request.jwt.claim.sub',current_setting('pfix.a'),true);
select pg_temp.check_ok((select invitation_state='already_member' from public.ecosystem_household_candidates('bravo') where id=current_setting('pfix.b')::uuid),'already member');
select public.ecosystem_delete_household(current_setting('pfix.house')::uuid);
select set_config('request.jwt.claim.sub',current_setting('pfix.b'),true);
select set_config('pfix.house',public.ecosystem_create_household('Synthetic reverse search')::text,true);
do $$ declare q text;begin foreach q in array array['alpha','PFIX_ALP','@PFIX_ALPHA','fix alp'] loop
 perform pg_temp.check_ok((select count(*)=1 from public.ecosystem_household_candidates(q) where id=current_setting('pfix.a')::uuid and invitation_state='available'),'reverse Family search: '||q);end loop;end $$;
select set_config('request.jwt.claim.sub',current_setting('pfix.a'),true);
select public.ecosystem_create_household('Synthetic other household');
select set_config('request.jwt.claim.sub',current_setting('pfix.b'),true);
select pg_temp.check_ok((select invitation_state='unavailable' from public.ecosystem_household_candidates('alpha') where id=current_setting('pfix.a')::uuid),'other-household unavailable');
select public.ecosystem_set_follow(current_setting('pfix.a')::uuid,true);
select set_config('request.jwt.claim.sub',current_setting('pfix.a'),true);
select pg_temp.check_ok(exists(select 1 from public.ecosystem_relationship_people('','followers') where id=current_setting('pfix.b')::uuid and is_follower),'follower list');
select public.ecosystem_set_follow(current_setting('pfix.b')::uuid,true);
select pg_temp.check_ok(exists(select 1 from public.ecosystem_relationship_people('','following') where id=current_setting('pfix.b')::uuid and is_following and is_follower and not is_friend),'follow back remains independent');
select public.ecosystem_set_follow(current_setting('pfix.b')::uuid,false);
select pg_temp.check_ok(not exists(select 1 from public.ecosystem_relationship_people('','following') where id=current_setting('pfix.b')::uuid),'unfollow');
select set_config('request.jwt.claim.sub',current_setting('pfix.b'),true);
select public.ecosystem_block_user(current_setting('pfix.a')::uuid);
select pg_temp.check_ok(not exists(select 1 from public.ecosystem_relationship_people('alpha')) and not exists(select 1 from public.ecosystem_household_candidates('alpha')),'blocking excludes both contexts');
select set_config('request.jwt.claim.sub',current_setting('pfix.a'),true);
select pg_temp.check_ok(not exists(select 1 from public.ecosystem_relationship_people('bravo')) and not exists(select 1 from public.ecosystem_household_candidates('bravo')),'reverse blocking');
reset role;
-- Deleted identities and rolled-back allocations never return to the sequence.
do $$ declare old_number bigint; burned bigint; fresh uuid:=gen_random_uuid();begin
 select profile_number into old_number from public.profiles where id=current_setting('pfix.c')::uuid;
 delete from auth.users where id=current_setting('pfix.c')::uuid;
 perform pg_temp.check_ok(exists(select 1 from private.profile_numbers where user_id=current_setting('pfix.c')::uuid and profile_number=old_number),'deleted identity number retained');
 begin burned:=nextval('private.profile_number_seq');raise exception 'rollback allocation';exception when raise_exception then null;end;
 insert into auth.users(id) values(fresh);
 perform pg_temp.check_ok((select profile_number>greatest(old_number,burned) from public.profiles where id=fresh),'numbers increase after deletion and rollback');
end $$;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 begin perform public.account_ensure_profile();raise exception 'Anonymous ensure';exception when insufficient_privilege then null;end;
 begin perform public.ecosystem_relationship_people('pfix');raise exception 'Anonymous search';exception when insufficient_privilege then null;end;
 begin perform public.ecosystem_household_candidates('pfix');raise exception 'Anonymous family search';exception when insufficient_privilege then null;end;
 begin perform 1 from public.profiles;raise exception 'Anonymous profiles';exception when insufficient_privilege then null;end;
end $$;
reset role;
select 'PASS: provisioning, permanence, both searches, eligibility, blocking, privacy and anonymous denial' as result;
rollback;

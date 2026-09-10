-- Run as postgres in SQL Editor; all fixtures/relationship changes roll back.
begin;
do $$ begin
  if (select count(*) from auth.users)<3 then raise exception 'Requires three existing auth users'; end if;
  perform set_config('calendar_test.a',(select id::text from auth.users order by id limit 1),true);
  perform set_config('calendar_test.b',(select id::text from auth.users order by id offset 1 limit 1),true);
  perform set_config('calendar_test.c',(select id::text from auth.users order by id offset 2 limit 1),true);
end $$;
delete from public.ecosystem_blocks where
  (blocker_id=current_setting('calendar_test.a')::uuid and blocked_id=current_setting('calendar_test.b')::uuid)
  or (blocker_id=current_setting('calendar_test.b')::uuid and blocked_id=current_setting('calendar_test.a')::uuid);
insert into public.ecosystem_friendships(user_low_id,user_high_id)
values(least(current_setting('calendar_test.a')::uuid,current_setting('calendar_test.b')::uuid),greatest(current_setting('calendar_test.a')::uuid,current_setting('calendar_test.b')::uuid)) on conflict do nothing;
insert into public.golf_courses(id,user_id,course,tee,par,rating,slope)
values('calendar-integration-fixture',current_setting('calendar_test.a')::uuid,'Test Links','Blue',72,71,120);

create function pg_temp.expect_calendar(expected integer) returns void language plpgsql as $$
declare actual integer;
begin
  select count(*) into actual from public.daymark_fairway_events() where source_id=current_setting('calendar_test.round')::uuid;
  if actual<>expected then raise exception 'Calendar access expected %, got %',expected,actual; end if;
  select count(*) into actual from public.platform_events where source_app='fairway' and source_id=current_setting('calendar_test.round');
  if actual<>expected then raise exception 'Direct event RLS expected %, got %',expected,actual; end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('calendar_test.a'),true);
select set_config('calendar_test.round',public.fairway_create_round_session('calendar-integration-fixture','2031-09-12T14:30:00Z','America/New_York','PRIVATE NOTES MUST NOT APPEAR')::text,true);
select pg_temp.expect_calendar(1);
select public.fairway_invite_player(current_setting('calendar_test.round')::uuid,current_setting('calendar_test.b')::uuid);
select set_config('request.jwt.claim.sub',current_setting('calendar_test.b'),true);
select pg_temp.expect_calendar(0);
select public.fairway_respond_round(current_setting('calendar_test.round')::uuid,'accepted',false);
select pg_temp.expect_calendar(1);
do $$ begin
  if exists(select 1 from public.daymark_fairway_events() e where source_id=current_setting('calendar_test.round')::uuid and row_to_json(e)::text like '%PRIVATE NOTES%') then raise exception 'Private notes leaked'; end if;
end $$;

select set_config('request.jwt.claim.sub',current_setting('calendar_test.a'),true);
select public.fairway_update_planned_round(current_setting('calendar_test.round')::uuid,'calendar-integration-fixture','2031-09-13T18:00:00Z','America/New_York','');
select set_config('request.jwt.claim.sub',current_setting('calendar_test.b'),true);
do $$ begin
  if not exists(select 1 from public.daymark_fairway_events() where source_id=current_setting('calendar_test.round')::uuid and starts_at='2031-09-13T18:00:00Z') then raise exception 'Tee time update missing'; end if;
end $$;
select public.fairway_leave_planned_round(current_setting('calendar_test.round')::uuid);
select pg_temp.expect_calendar(0);
select set_config('request.jwt.claim.sub',current_setting('calendar_test.a'),true);
select public.fairway_invite_player(current_setting('calendar_test.round')::uuid,current_setting('calendar_test.b')::uuid);
select set_config('request.jwt.claim.sub',current_setting('calendar_test.b'),true);
select public.fairway_respond_round(current_setting('calendar_test.round')::uuid,'declined',false);
select pg_temp.expect_calendar(0);
select set_config('request.jwt.claim.sub',current_setting('calendar_test.a'),true);
select public.fairway_invite_player(current_setting('calendar_test.round')::uuid,current_setting('calendar_test.b')::uuid);
select set_config('request.jwt.claim.sub',current_setting('calendar_test.b'),true);
select public.fairway_respond_round(current_setting('calendar_test.round')::uuid,'accepted',false);
select set_config('request.jwt.claim.sub',current_setting('calendar_test.a'),true);
select public.fairway_remove_round_participant(current_setting('calendar_test.round')::uuid,current_setting('calendar_test.b')::uuid);
select set_config('request.jwt.claim.sub',current_setting('calendar_test.b'),true);
select pg_temp.expect_calendar(0);
select set_config('request.jwt.claim.sub',current_setting('calendar_test.c'),true);
select pg_temp.expect_calendar(0);
do $$ declare t text; n bigint; begin
  foreach t in array array['daymark_tasks','daymark_goals','daymark_events','daymark_schedule_entries'] loop
    execute format('select count(*) from public.%I where user_id<>auth.uid()',t) into n;
    if n<>0 then raise exception 'Private Daymark data exposed: %',t; end if;
  end loop;
end $$;
select set_config('request.jwt.claim.sub',current_setting('calendar_test.a'),true);
select public.fairway_cancel_planned_round(current_setting('calendar_test.round')::uuid);
select pg_temp.expect_calendar(0);
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
  begin perform public.daymark_fairway_events(); raise exception 'Anonymous RPC access allowed'; exception when insufficient_privilege then null; end;
  begin perform * from public.platform_events; raise exception 'Anonymous table access allowed'; exception when insufficient_privilege then null; end;
end $$;
rollback;

-- Stale grants must not override live participation/blocking; no persistent fixtures.
begin;
select set_config('calendar_test.a',(select id::text from auth.users order by id limit 1),true);
select set_config('calendar_test.b',(select id::text from auth.users order by id offset 1 limit 1),true);
delete from public.ecosystem_blocks where blocker_id in(current_setting('calendar_test.a')::uuid,current_setting('calendar_test.b')::uuid) and blocked_id in(current_setting('calendar_test.a')::uuid,current_setting('calendar_test.b')::uuid);
insert into public.fairway_round_sessions(id,host_id,course_name,tee_name,par,course_rating,slope,scheduled_at)
values('aaaaaaaa-0909-4090-8090-aaaaaaaaaaaa',current_setting('calendar_test.a')::uuid,'Synthetic Links','Blue',72,71,120,'2031-10-10T10:00:00Z');
insert into public.fairway_round_participants(session_id,user_id,invitation_status)
values('aaaaaaaa-0909-4090-8090-aaaaaaaaaaaa',current_setting('calendar_test.b')::uuid,'accepted');
insert into public.platform_event_access(event_id,user_id)
select id,current_setting('calendar_test.b')::uuid from public.platform_events where source_id='aaaaaaaa-0909-4090-8090-aaaaaaaaaaaa';
insert into public.platform_event_subscriptions(event_id,user_id)
select id,current_setting('calendar_test.b')::uuid from public.platform_events where source_id='aaaaaaaa-0909-4090-8090-aaaaaaaaaaaa';
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('calendar_test.b'),true);
do $$ begin
  if not exists(select 1 from public.daymark_fairway_events() where source_id='aaaaaaaa-0909-4090-8090-aaaaaaaaaaaa') then raise exception 'Accepted participant missing'; end if;
  if has_table_privilege('authenticated','public.platform_events','INSERT') or has_table_privilege('authenticated','public.platform_events','UPDATE') then raise exception 'Forged source writes allowed'; end if;
  if has_function_privilege('authenticated','public.fairway_publish_calendar_reference()','EXECUTE') then raise exception 'Trigger exposed to callers'; end if;
end $$;
select public.ecosystem_block_user(current_setting('calendar_test.a')::uuid);
do $$ begin
  if exists(select 1 from public.daymark_fairway_events() where source_id='aaaaaaaa-0909-4090-8090-aaaaaaaaaaaa') then raise exception 'Blocking did not revoke calendar'; end if;
  if exists(select 1 from public.platform_daymark_events() where source_id='aaaaaaaa-0909-4090-8090-aaaaaaaaaaaa') then raise exception 'Legacy subscription bypassed blocking'; end if;
end $$;
reset role;
delete from public.ecosystem_blocks where blocker_id=current_setting('calendar_test.b')::uuid and blocked_id=current_setting('calendar_test.a')::uuid;
update public.fairway_round_participants set invitation_status='removed' where session_id='aaaaaaaa-0909-4090-8090-aaaaaaaaaaaa';
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('calendar_test.b'),true);
do $$ begin
  if exists(select 1 from public.platform_daymark_events() where source_id='aaaaaaaa-0909-4090-8090-aaaaaaaaaaaa') then raise exception 'Stale subscription bypassed removal'; end if;
  if exists(select 1 from public.platform_events where source_id='aaaaaaaa-0909-4090-8090-aaaaaaaaaaaa') then raise exception 'Stale access row bypassed removal'; end if;
end $$;
reset role;
update public.fairway_round_participants set invitation_status='accepted' where session_id='aaaaaaaa-0909-4090-8090-aaaaaaaaaaaa';
update public.fairway_round_sessions set status='cancelled' where id='aaaaaaaa-0909-4090-8090-aaaaaaaaaaaa';
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('calendar_test.b'),true);
do $$ begin
  if exists(select 1 from public.daymark_fairway_events() where source_id='aaaaaaaa-0909-4090-8090-aaaaaaaaaaaa') then raise exception 'Cancellation retained accepted participant access'; end if;
end $$;
rollback;
select 'Fairway / Daymark security lifecycle passed; fixtures rolled back' as result;

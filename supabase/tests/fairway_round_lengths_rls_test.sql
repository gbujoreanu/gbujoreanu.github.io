-- Transactional 9/18-hole scoring, duration, and authorization test. Requires three auth users.
begin;

do $$ begin
  if (select count(*) from (select id from auth.users limit 3) u)<3 then raise exception 'Round-length test requires three auth users'; end if;
  perform set_config('length_test.a',(select id::text from auth.users order by created_at limit 1),true);
  perform set_config('length_test.b',(select id::text from auth.users order by created_at offset 1 limit 1),true);
  perform set_config('length_test.c',(select id::text from auth.users order by created_at offset 2 limit 1),true);
end $$;

delete from public.ecosystem_blocks where blocker_id in(current_setting('length_test.a')::uuid,current_setting('length_test.b')::uuid,current_setting('length_test.c')::uuid)
  or blocked_id in(current_setting('length_test.a')::uuid,current_setting('length_test.b')::uuid,current_setting('length_test.c')::uuid);
insert into public.ecosystem_friendships(user_low_id,user_high_id)
values(least(current_setting('length_test.a')::uuid,current_setting('length_test.b')::uuid),greatest(current_setting('length_test.a')::uuid,current_setting('length_test.b')::uuid)) on conflict do nothing;
insert into public.golf_courses(id,user_id,course,tee,par,rating,slope)
values('round-length-test-course',current_setting('length_test.a')::uuid,'Synthetic Links','Blue',72,71.4,128);

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('length_test.a'),true);
select set_config('length_test.nine',public.fairway_create_round_session('round-length-test-course','2031-10-12T14:30:00Z','America/New_York','',9::smallint)::text,true);
select set_config('length_test.eighteen',public.fairway_create_round_session('round-length-test-course','2031-10-13T14:30:00Z','America/New_York','',18::smallint)::text,true);
select public.fairway_invite_player(current_setting('length_test.nine')::uuid,current_setting('length_test.b')::uuid);
select public.fairway_invite_player(current_setting('length_test.eighteen')::uuid,current_setting('length_test.b')::uuid);

do $$ begin
  if (select extract(epoch from (ends_at-starts_at))/3600 from public.platform_events where source_app='fairway' and source_id=current_setting('length_test.nine'))<>2 then raise exception '9-hole duration is not two hours'; end if;
  if (select extract(epoch from (ends_at-starts_at))/3600 from public.platform_events where source_app='fairway' and source_id=current_setting('length_test.eighteen'))<>4 then raise exception '18-hole duration is not four hours'; end if;
end $$;

-- Length and time edits update the source-linked end time before scoring begins.
select public.fairway_update_planned_round(current_setting('length_test.nine')::uuid,'round-length-test-course','2031-10-12T16:00:00Z','America/New_York','',18::smallint);
do $$ begin
  if (select hole_count from public.fairway_round_sessions where id=current_setting('length_test.nine')::uuid)<>18 then raise exception 'round length edit failed'; end if;
  if (select extract(epoch from (ends_at-starts_at))/3600 from public.platform_events where source_app='fairway' and source_id=current_setting('length_test.nine'))<>4 then raise exception 'duration did not follow length edit'; end if;
end $$;
select public.fairway_update_planned_round(current_setting('length_test.nine')::uuid,'round-length-test-course','2031-10-12T14:30:00Z','America/New_York','',9::smallint);

select set_config('request.jwt.claim.sub',current_setting('length_test.b'),true);
select public.fairway_respond_round(current_setting('length_test.nine')::uuid,'accepted',false);
select public.fairway_respond_round(current_setting('length_test.eighteen')::uuid,'accepted',false);
do $$ begin
  if not exists(select 1 from public.daymark_fairway_events() where source_id=current_setting('length_test.nine')::uuid and hole_count=9 and ends_at-starts_at=interval '2 hours') then raise exception 'accepted player cannot see 9-hole Daymark item'; end if;
end $$;

select public.fairway_upsert_scorecard(current_setting('length_test.nine')::uuid,current_setting('length_test.b')::uuid,array_fill(5::smallint,array[9]),'final');
select set_config('request.jwt.claim.sub',current_setting('length_test.a'),true);
select public.fairway_upsert_scorecard(current_setting('length_test.nine')::uuid,current_setting('length_test.a')::uuid,array_fill(4::smallint,array[9]),'final');
select public.fairway_update_round_status(current_setting('length_test.nine')::uuid,'completed');

select set_config('request.jwt.claim.sub',current_setting('length_test.b'),true);
select public.fairway_upsert_scorecard(current_setting('length_test.eighteen')::uuid,current_setting('length_test.b')::uuid,array_fill(5::smallint,array[18]),'final');
select set_config('request.jwt.claim.sub',current_setting('length_test.a'),true);
select public.fairway_upsert_scorecard(current_setting('length_test.eighteen')::uuid,current_setting('length_test.a')::uuid,array_fill(4::smallint,array[18]),'final');
select public.fairway_update_round_status(current_setting('length_test.eighteen')::uuid,'completed');

-- Personal 9-hole history accepts exactly nine scores, a null back nine, and remains owner-only.
insert into public.golf_rounds(id,user_id,player,played_on,course,tee,hole_count,par,course_rating,slope,pcc,holes,front,back,total,differential)
values('round-length-personal-nine',current_setting('length_test.a')::uuid,'Golfer','2031-10-11','Synthetic Links','Blue',9,36,35.7,128,0,array_fill(4::smallint,array[9]),36,null,36,0.3);
select set_config('request.jwt.claim.sub',current_setting('length_test.c'),true);
do $$ begin
  if exists(select 1 from public.golf_rounds where id='round-length-personal-nine') then raise exception 'unrelated user read personal 9-hole round'; end if;
  if exists(select 1 from public.daymark_fairway_events() where source_id in(current_setting('length_test.nine')::uuid,current_setting('length_test.eighteen')::uuid)) then raise exception 'unrelated user read Fairway Daymark item'; end if;
end $$;

reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
  begin perform public.daymark_fairway_events(); raise exception 'anonymous called Daymark Fairway RPC'; exception when insufficient_privilege then null; end;
end $$;

rollback;
select 'fairway_round_lengths_rls_test_passed' as result;

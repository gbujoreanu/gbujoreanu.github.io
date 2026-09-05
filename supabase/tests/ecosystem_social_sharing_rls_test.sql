-- Run in Supabase SQL Editor. Uses three existing auth users and rolls everything back.
begin;

do $$
declare users_found integer;
begin
  select count(*) into users_found from (select id from auth.users limit 3) users;
  if users_found < 3 then raise exception 'Social RLS test requires three existing auth users'; end if;
  perform set_config('social_test.a',(select id::text from auth.users order by created_at limit 1),true);
  perform set_config('social_test.b',(select id::text from auth.users order by created_at offset 1 limit 1),true);
  perform set_config('social_test.c',(select id::text from auth.users order by created_at offset 2 limit 1),true);
end $$;

update public.profiles set discoverable=true where id in(current_setting('social_test.a')::uuid,current_setting('social_test.b')::uuid,current_setting('social_test.c')::uuid);

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('social_test.a'),true);

do $$ declare visible integer; begin
  select count(*) into visible from public.profiles where id=current_setting('social_test.b')::uuid;
  if visible<>0 then raise exception 'User A directly read User B private profile'; end if;
  select count(*) into visible from public.ecosystem_safe_people('',30) where id=current_setting('social_test.b')::uuid;
  if visible<>1 then raise exception 'Safe discovery did not return discoverable User B'; end if;
end $$;

select public.ecosystem_send_friend_request(current_setting('social_test.b')::uuid);

select set_config('request.jwt.claim.sub',current_setting('social_test.c'),true);
do $$ declare visible integer; begin
  select count(*) into visible from public.ecosystem_friend_requests;
  if visible<>0 then raise exception 'Uninvolved User C read friend request'; end if;
end $$;

select set_config('request.jwt.claim.sub',current_setting('social_test.b'),true);
select public.ecosystem_respond_friend_request((select id from public.ecosystem_friend_requests where recipient_id=auth.uid() and status='pending' limit 1),'accepted');

select set_config('request.jwt.claim.sub',current_setting('social_test.a'),true);
insert into public.daymark_tasks(id,user_id,title,notes,due_date,priority,status,on_calendar)
values('social-test-task',auth.uid(),'Synthetic private task','Never persist','2026-09-04','medium','open',true);
insert into public.daymark_item_shares(owner_id,recipient_id,item_type,item_id,access_level)
values(auth.uid(),current_setting('social_test.b')::uuid,'task','social-test-task','details');

do $$ begin
  begin
    insert into public.daymark_item_shares(owner_id,recipient_id,item_type,item_id)
    values(auth.uid(),current_setting('social_test.c')::uuid,'task','social-test-task');
    raise exception 'Non-eligible Daymark share was accepted';
  exception when raise_exception then
    if sqlerrm='Non-eligible Daymark share was accepted' then raise; end if;
  end;
end $$;

insert into public.golf_courses(id,user_id,course,tee,par,rating,slope)
values('social-test-course',auth.uid(),'Synthetic Links','Test',72,71.2,125);
select set_config('social_test.round',public.fairway_create_round_session('social-test-course','2026-09-10T14:00:00Z','America/New_York','Synthetic round')::text,true);
select public.fairway_invite_player(current_setting('social_test.round')::uuid,current_setting('social_test.b')::uuid);

select set_config('request.jwt.claim.sub',current_setting('social_test.c'),true);
do $$ declare visible integer; begin
  select count(*) into visible from public.fairway_round_sessions where id=current_setting('social_test.round')::uuid;
  if visible<>0 then raise exception 'User C read a private Fairway session'; end if;
  begin
    perform public.fairway_upsert_scorecard(current_setting('social_test.round')::uuid,current_setting('social_test.b')::uuid,array[4,4,4]::smallint[],'draft');
    raise exception 'User C scored for User B';
  exception when raise_exception then
    if sqlerrm='User C scored for User B' then raise; end if;
  end;
end $$;

select set_config('request.jwt.claim.sub',current_setting('social_test.b'),true);
select public.daymark_respond_share((select share_id from public.daymark_shared_items() where item_id='social-test-task'),'accepted');
select public.fairway_respond_round(current_setting('social_test.round')::uuid,'accepted',true);
select public.fairway_upsert_scorecard(current_setting('social_test.round')::uuid,auth.uid(),array[4,5,4]::smallint[],'draft');

do $$ declare visible integer; begin
  select count(*) into visible from public.daymark_shared_items() where item_id='social-test-task' and title='Synthetic private task';
  if visible<>1 then raise exception 'Accepted Daymark share was unavailable to User B'; end if;
  select count(*) into visible from public.platform_daymark_events() where source_id=current_setting('social_test.round');
  if visible<>1 then raise exception 'Accepted Fairway round was not published to User B Daymark'; end if;
end $$;

select set_config('request.jwt.claim.sub',current_setting('social_test.a'),true);
insert into public.money_bills(id,user_id,name,amount_minor,next_due_date,frequency,classification,show_in_daymark)
values('00000000-0000-4000-8000-000000009901',auth.uid(),'Synthetic bill',999999,'2026-09-20','monthly','fixed',true);
do $$ declare payload jsonb; visible integer; begin
  select details into payload from public.platform_events where source_app='money' and source_id='00000000-0000-4000-8000-000000009901';
  if payload ? 'amount' or payload ? 'notes' then raise exception 'Money event leaked financial detail'; end if;
  select count(*) into visible from public.platform_daymark_events() where source_app='money';
  if visible<1 then raise exception 'Opt-in Money bill was not published to owner Daymark'; end if;
end $$;

select public.ecosystem_block_user(current_setting('social_test.b')::uuid);
do $$ declare visible integer; begin
  select count(*) into visible from public.ecosystem_friendships where auth.uid() in(user_low_id,user_high_id);
  if visible<>0 then raise exception 'Blocking failed to revoke friendship'; end if;
  select count(*) into visible from public.daymark_item_shares where item_id='social-test-task' and status in('pending','accepted');
  if visible<>0 then raise exception 'Blocking failed to revoke Daymark share'; end if;
end $$;

reset role;
set local role anon;
do $$ begin
  begin
    perform count(*) from public.fairway_round_sessions;
    raise exception 'Anonymous social-table read succeeded';
  exception when insufficient_privilege then null;
  end;
  begin
    perform * from public.ecosystem_safe_people('',10);
    raise exception 'Anonymous discovery RPC succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
select 'passed: User A/User B/User C/anonymous relationship, sharing, Fairway, Money-event, and block isolation' as result;
rollback;

-- Run in Supabase SQL Editor. Uses four existing auth users and rolls everything back.
begin;

do $$
begin
  if (select count(*) from (select id from auth.users limit 4) users)<4 then
    raise exception 'Planned round test requires four existing auth users';
  end if;
  perform set_config('round_test.a',(select id::text from auth.users order by created_at limit 1),true);
  perform set_config('round_test.b',(select id::text from auth.users order by created_at offset 1 limit 1),true);
  perform set_config('round_test.c',(select id::text from auth.users order by created_at offset 2 limit 1),true);
  perform set_config('round_test.d',(select id::text from auth.users order by created_at offset 3 limit 1),true);
end $$;

update public.profiles set discoverable=true
where id in(current_setting('round_test.a')::uuid,current_setting('round_test.b')::uuid,
  current_setting('round_test.c')::uuid,current_setting('round_test.d')::uuid);

delete from public.ecosystem_friendships
where user_low_id in(current_setting('round_test.a')::uuid,current_setting('round_test.b')::uuid,current_setting('round_test.c')::uuid,current_setting('round_test.d')::uuid)
  and user_high_id in(current_setting('round_test.a')::uuid,current_setting('round_test.b')::uuid,current_setting('round_test.c')::uuid,current_setting('round_test.d')::uuid);
delete from public.ecosystem_blocks
where blocker_id in(current_setting('round_test.a')::uuid,current_setting('round_test.b')::uuid,current_setting('round_test.c')::uuid,current_setting('round_test.d')::uuid)
  and blocked_id in(current_setting('round_test.a')::uuid,current_setting('round_test.b')::uuid,current_setting('round_test.c')::uuid,current_setting('round_test.d')::uuid);

insert into public.ecosystem_friendships(user_low_id,user_high_id)
values
  (least(current_setting('round_test.a')::uuid,current_setting('round_test.b')::uuid),greatest(current_setting('round_test.a')::uuid,current_setting('round_test.b')::uuid)),
  (least(current_setting('round_test.a')::uuid,current_setting('round_test.c')::uuid),greatest(current_setting('round_test.a')::uuid,current_setting('round_test.c')::uuid));

insert into public.golf_courses(id,user_id,course,tee,par,rating,slope)
values('planned-round-test-course',current_setting('round_test.a')::uuid,'Test Links','Blue',72,71.4,128);

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('round_test.a'),true);
select set_config('round_test.id',public.fairway_create_round_session(
  'planned-round-test-course','2030-09-12T14:30:00Z','America/New_York','Meet by the putting green.'
)::text,true);

select public.fairway_invite_player(current_setting('round_test.id')::uuid,current_setting('round_test.b')::uuid);
select public.fairway_invite_player(current_setting('round_test.id')::uuid,current_setting('round_test.c')::uuid);

do $$
begin
  begin
    perform public.fairway_invite_player(current_setting('round_test.id')::uuid,current_setting('round_test.b')::uuid);
    raise exception 'Duplicate invitation succeeded';
  exception when raise_exception then if sqlerrm='Duplicate invitation succeeded' then raise; end if; end;
  begin
    perform public.fairway_invite_player(current_setting('round_test.id')::uuid,auth.uid());
    raise exception 'Self invitation succeeded';
  exception when raise_exception then if sqlerrm='Self invitation succeeded' then raise; end if; end;
  begin
    perform public.fairway_invite_player(current_setting('round_test.id')::uuid,current_setting('round_test.d')::uuid);
    raise exception 'Unrelated invitation succeeded';
  exception when raise_exception then if sqlerrm='Unrelated invitation succeeded' then raise; end if; end;
end $$;

select set_config('request.jwt.claim.sub',current_setting('round_test.d'),true);
do $$ declare found integer; begin
  select count(*) into found from public.fairway_round_sessions where id=current_setting('round_test.id')::uuid;
  if found<>0 then raise exception 'Unrelated user read planned round'; end if;
  select jsonb_array_length(public.fairway_planned_rounds()) into found;
  if found<>0 then raise exception 'Unrelated user enumerated planned rounds'; end if;
end $$;

select set_config('request.jwt.claim.sub',current_setting('round_test.b'),true);
do $$ declare pending_round jsonb; begin
  select item into pending_round
  from jsonb_array_elements(public.fairway_planned_rounds()) item
  where item->>'id'=current_setting('round_test.id');
  if pending_round is null or pending_round->>'viewer_status'<>'invited' then raise exception 'Pending invitation unavailable'; end if;
  begin
    perform public.fairway_update_planned_round(current_setting('round_test.id')::uuid,'planned-round-test-course','2030-09-12T15:00:00Z','America/New_York','Forged edit');
    raise exception 'Non-host updated round';
  exception when raise_exception then if sqlerrm='Non-host updated round' then raise; end if; end;
end $$;
select public.fairway_respond_round(current_setting('round_test.id')::uuid,'accepted',false);

select set_config('request.jwt.claim.sub',current_setting('round_test.a'),true);
select public.fairway_update_planned_round(current_setting('round_test.id')::uuid,'planned-round-test-course','2030-09-12T15:00:00Z','America/New_York','Updated tee time.');

select set_config('request.jwt.claim.sub',current_setting('round_test.b'),true);
do $$ declare rounds jsonb; begin
  rounds:=public.fairway_planned_rounds();
  if rounds->0->>'scheduled_at'<>'2030-09-12T15:00:00+00:00' then raise exception 'Participant did not receive edited tee time'; end if;
  begin
    update public.fairway_round_sessions set notes='Direct edit' where id=current_setting('round_test.id')::uuid;
    raise exception 'Participant direct update succeeded';
  exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub',current_setting('round_test.c'),true);
select public.fairway_respond_round(current_setting('round_test.id')::uuid,'declined',false);
do $$ declare found integer; begin
  select count(*) into found from public.fairway_round_sessions where id=current_setting('round_test.id')::uuid;
  if found<>0 then raise exception 'Declined participant retained round access'; end if;
  select count(*) into found from public.fairway_social_rounds() where session_id=current_setting('round_test.id')::uuid;
  if found<>0 then raise exception 'Declined participant retained compatibility RPC access'; end if;
  select count(*) into found from public.fairway_scorecards where session_id=current_setting('round_test.id')::uuid;
  if found<>0 then raise exception 'Declined participant retained scorecard access'; end if;
end $$;

select set_config('request.jwt.claim.sub',current_setting('round_test.a'),true);
select public.fairway_remove_round_participant(current_setting('round_test.id')::uuid,current_setting('round_test.b')::uuid);
select set_config('request.jwt.claim.sub',current_setting('round_test.b'),true);
do $$ declare found integer; begin
  select count(*) into found from public.fairway_round_sessions where id=current_setting('round_test.id')::uuid;
  if found<>0 then raise exception 'Removed participant retained round access'; end if;
end $$;

select set_config('request.jwt.claim.sub',current_setting('round_test.a'),true);
select public.fairway_invite_player(current_setting('round_test.id')::uuid,current_setting('round_test.b')::uuid);
select set_config('request.jwt.claim.sub',current_setting('round_test.b'),true);
select public.fairway_respond_round(current_setting('round_test.id')::uuid,'accepted',false);
select public.fairway_leave_planned_round(current_setting('round_test.id')::uuid);
do $$ declare found integer; begin
  select count(*) into found from public.fairway_round_sessions where id=current_setting('round_test.id')::uuid;
  if found<>0 then raise exception 'Withdrawn participant retained round access'; end if;
end $$;

select set_config('request.jwt.claim.sub',current_setting('round_test.a'),true);
select public.ecosystem_block_user(current_setting('round_test.c')::uuid);
do $$ begin
  begin
    perform public.fairway_invite_player(current_setting('round_test.id')::uuid,current_setting('round_test.c')::uuid);
    raise exception 'Blocked invitation succeeded';
  exception when raise_exception then if sqlerrm='Blocked invitation succeeded' then raise; end if; end;
end $$;

select public.fairway_cancel_planned_round(current_setting('round_test.id')::uuid);
do $$ declare found integer; begin
  select count(*) into found
  from jsonb_array_elements(public.fairway_planned_rounds()) item
  where item->>'id'=current_setting('round_test.id');
  if found<>0 then raise exception 'Cancelled round remained upcoming'; end if;
end $$;

reset role;
do $$ declare found integer; begin
  select count(*) into found from public.fairway_round_sessions
  where id=current_setting('round_test.id')::uuid and status='cancelled';
  if found<>1 then raise exception 'Host cancellation failed'; end if;
end $$;
set local role anon;
do $$
begin
  begin perform public.fairway_planned_rounds(); raise exception 'Anonymous RPC access succeeded';
  exception when insufficient_privilege then null; end;
  begin perform count(*) from public.fairway_round_sessions; raise exception 'Anonymous round read succeeded';
  exception when insufficient_privilege then null; end;
end $$;

reset role;
select 'passed: Fairway planned rounds, invitations, host controls, participant withdrawal, blocking, and RLS' as result;
rollback;

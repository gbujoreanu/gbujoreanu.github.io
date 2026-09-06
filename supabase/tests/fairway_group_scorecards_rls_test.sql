-- Transactional group-scorecard authorization test. Requires five auth users.
begin;

do $$ begin
  if (select count(*) from (select id from auth.users limit 5) u)<5 then raise exception 'Group scorecard test requires five auth users'; end if;
  perform set_config('group_test.a',(select id::text from auth.users order by created_at limit 1),true);
  perform set_config('group_test.b',(select id::text from auth.users order by created_at offset 1 limit 1),true);
  perform set_config('group_test.c',(select id::text from auth.users order by created_at offset 2 limit 1),true);
  perform set_config('group_test.d',(select id::text from auth.users order by created_at offset 3 limit 1),true);
  perform set_config('group_test.e',(select id::text from auth.users order by created_at offset 4 limit 1),true);
end $$;

delete from public.ecosystem_blocks where blocker_id in(current_setting('group_test.a')::uuid,current_setting('group_test.b')::uuid,current_setting('group_test.c')::uuid,current_setting('group_test.d')::uuid,current_setting('group_test.e')::uuid)
  or blocked_id in(current_setting('group_test.a')::uuid,current_setting('group_test.b')::uuid,current_setting('group_test.c')::uuid,current_setting('group_test.d')::uuid,current_setting('group_test.e')::uuid);
insert into public.ecosystem_friendships(user_low_id,user_high_id) values
  (least(current_setting('group_test.a')::uuid,current_setting('group_test.b')::uuid),greatest(current_setting('group_test.a')::uuid,current_setting('group_test.b')::uuid)),
  (least(current_setting('group_test.a')::uuid,current_setting('group_test.c')::uuid),greatest(current_setting('group_test.a')::uuid,current_setting('group_test.c')::uuid)),
  (least(current_setting('group_test.a')::uuid,current_setting('group_test.d')::uuid),greatest(current_setting('group_test.a')::uuid,current_setting('group_test.d')::uuid))
on conflict do nothing;
insert into public.golf_courses(id,user_id,course,tee,par,rating,slope)
values('group-scorecard-test-course',current_setting('group_test.a')::uuid,'Synthetic Links','Blue',72,71.4,128)
;

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('group_test.a'),true);
select set_config('group_test.round',public.fairway_create_round_session('group-scorecard-test-course','2030-10-12T14:30:00Z','America/New_York','Synthetic test round')::text,true);
select public.fairway_invite_player(current_setting('group_test.round')::uuid,current_setting('group_test.b')::uuid);
select public.fairway_invite_player(current_setting('group_test.round')::uuid,current_setting('group_test.c')::uuid);
select public.fairway_invite_player(current_setting('group_test.round')::uuid,current_setting('group_test.d')::uuid);

select set_config('request.jwt.claim.sub',current_setting('group_test.b'),true);
select public.fairway_respond_round(current_setting('group_test.round')::uuid,'accepted',false);
select set_config('request.jwt.claim.sub',current_setting('group_test.c'),true);
select public.fairway_respond_round(current_setting('group_test.round')::uuid,'accepted',false);

-- B can save and repeatedly upsert only B's own row.
select set_config('request.jwt.claim.sub',current_setting('group_test.b'),true);
select public.fairway_upsert_scorecard(current_setting('group_test.round')::uuid,current_setting('group_test.b')::uuid,array_fill(5::smallint,array[18]),'draft');
select public.fairway_upsert_scorecard(current_setting('group_test.round')::uuid,current_setting('group_test.b')::uuid,array_fill(5::smallint,array[18]),'final');
do $$ begin
  if (select count(*) from public.fairway_scorecards where session_id=current_setting('group_test.round')::uuid and player_id=auth.uid())<>1 then raise exception 'Repeated save duplicated scorecard'; end if;
  begin
    perform public.fairway_upsert_scorecard(current_setting('group_test.round')::uuid,current_setting('group_test.a')::uuid,array_fill(4::smallint,array[18]),'draft');
    raise exception 'Participant changed host score';
  exception when raise_exception then if sqlerrm='Participant changed host score' then raise; end if; end;
end $$;

-- C has read access but cannot change B's card.
select set_config('request.jwt.claim.sub',current_setting('group_test.c'),true);
do $$ begin
  if public.fairway_group_scorecard(current_setting('group_test.round')::uuid) is null then raise exception 'Accepted participant cannot read group card'; end if;
  begin
    perform public.fairway_upsert_scorecard(current_setting('group_test.round')::uuid,current_setting('group_test.b')::uuid,array_fill(3::smallint,array[18]),'draft');
    raise exception 'Participant changed another participant score';
  exception when raise_exception then if sqlerrm='Participant changed another participant score' then raise; end if; end;
end $$;

-- Pending D and unrelated E cannot read or write.
select set_config('request.jwt.claim.sub',current_setting('group_test.d'),true);
do $$ begin
  if public.fairway_group_scorecard(current_setting('group_test.round')::uuid) is not null then raise exception 'Pending invitee read scorecard'; end if;
  begin perform public.fairway_upsert_scorecard(current_setting('group_test.round')::uuid,auth.uid(),array_fill(4::smallint,array[18]),'draft'); raise exception 'Pending invitee wrote scorecard';
  exception when raise_exception then if sqlerrm='Pending invitee wrote scorecard' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('group_test.e'),true);
do $$ begin if public.fairway_group_scorecard(current_setting('group_test.round')::uuid) is not null then raise exception 'Unrelated user read scorecard'; end if; end $$;

-- The designated scorer (host A) may score accepted players and complete only
-- after all three cards are final.
select set_config('request.jwt.claim.sub',current_setting('group_test.a'),true);
select public.fairway_upsert_scorecard(current_setting('group_test.round')::uuid,current_setting('group_test.a')::uuid,array_fill(4::smallint,array[18]),'final');
select public.fairway_upsert_scorecard(current_setting('group_test.round')::uuid,current_setting('group_test.c')::uuid,array_fill(6::smallint,array[18]),'final');
select public.fairway_update_round_status(current_setting('group_test.round')::uuid,'completed');
do $$ begin
  if (select status from public.fairway_round_sessions where id=current_setting('group_test.round')::uuid)<>'completed' then raise exception 'Round did not complete'; end if;
  if public.fairway_group_scorecard(current_setting('group_test.round')::uuid) is null then raise exception 'Completed scorecard disappeared'; end if;
  begin perform public.fairway_upsert_scorecard(current_setting('group_test.round')::uuid,auth.uid(),array_fill(3::smallint,array[18]),'draft'); raise exception 'Completed scorecard remained editable';
  exception when raise_exception then if sqlerrm='Completed scorecard remained editable' then raise; end if; end;
end $$;

-- Anonymous access is denied by EXECUTE grants and RLS.
reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
  begin perform public.fairway_group_scorecard(current_setting('group_test.round')::uuid); raise exception 'Anonymous called group scorecard RPC';
  exception when insufficient_privilege then null; end;
  begin
    perform count(*) from public.fairway_scorecards where session_id=current_setting('group_test.round')::uuid;
    raise exception 'Anonymous read scorecard rows';
  exception when insufficient_privilege then null; end;
end $$;

rollback;

select 'fairway_group_scorecards_rls_test_passed' as result;

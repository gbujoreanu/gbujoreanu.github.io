-- Transactional shared-round history materialization and authorization test.
-- Requires three auth users and the Fairway social/group-round migrations.
begin;

do $$
begin
  if (select count(*) from (select id from auth.users limit 3) users)<3 then
    raise exception 'Shared-round history test requires three auth users';
  end if;
  perform set_config('shared_history.a',(select id::text from auth.users order by created_at limit 1),true);
  perform set_config('shared_history.b',(select id::text from auth.users order by created_at offset 1 limit 1),true);
  perform set_config('shared_history.c',(select id::text from auth.users order by created_at offset 2 limit 1),true);
end $$;

delete from public.ecosystem_blocks
where blocker_id in(current_setting('shared_history.a')::uuid,current_setting('shared_history.b')::uuid,current_setting('shared_history.c')::uuid)
   or blocked_id in(current_setting('shared_history.a')::uuid,current_setting('shared_history.b')::uuid,current_setting('shared_history.c')::uuid);

insert into public.ecosystem_friendships(user_low_id,user_high_id)
values(
  least(current_setting('shared_history.a')::uuid,current_setting('shared_history.b')::uuid),
  greatest(current_setting('shared_history.a')::uuid,current_setting('shared_history.b')::uuid)
) on conflict do nothing;

insert into public.golf_courses(id,user_id,course,tee,par,rating,slope)
values('shared-history-test-course',current_setting('shared_history.a')::uuid,'Synthetic Links','Blue',72,71.4,128);

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('shared_history.a'),true);
select set_config('shared_history.nine',public.fairway_create_round_session(
  'shared-history-test-course','2032-06-10T13:00:00Z','America/New_York','Synthetic 9-hole test',9::smallint
)::text,true);
select set_config('shared_history.eighteen',public.fairway_create_round_session(
  'shared-history-test-course','2032-06-11T14:00:00Z','America/New_York','Synthetic 18-hole test',18::smallint
)::text,true);
select public.fairway_invite_player(current_setting('shared_history.nine')::uuid,current_setting('shared_history.b')::uuid);
select public.fairway_invite_player(current_setting('shared_history.eighteen')::uuid,current_setting('shared_history.b')::uuid);

select set_config('request.jwt.claim.sub',current_setting('shared_history.b'),true);
select public.fairway_respond_round(current_setting('shared_history.nine')::uuid,'accepted',false);
select public.fairway_respond_round(current_setting('shared_history.eighteen')::uuid,'accepted',false);
select public.fairway_upsert_scorecard(current_setting('shared_history.nine')::uuid,current_setting('shared_history.b')::uuid,array_fill(5::smallint,array[9]),'final');
select public.fairway_upsert_scorecard(current_setting('shared_history.eighteen')::uuid,current_setting('shared_history.b')::uuid,array_fill(5::smallint,array[18]),'final');

select set_config('request.jwt.claim.sub',current_setting('shared_history.a'),true);
select public.fairway_upsert_scorecard(current_setting('shared_history.nine')::uuid,current_setting('shared_history.a')::uuid,array_fill(4::smallint,array[9]),'final');
select public.fairway_update_round_status(current_setting('shared_history.nine')::uuid,'completed');
select public.fairway_upsert_scorecard(current_setting('shared_history.eighteen')::uuid,current_setting('shared_history.a')::uuid,array_fill(4::smallint,array[18]),'final');
select public.fairway_update_round_status(current_setting('shared_history.eighteen')::uuid,'completed');

-- Completion retry is safe and cannot duplicate either golfer's result.
select public.fairway_update_round_status(current_setting('shared_history.nine')::uuid,'completed');
select public.fairway_update_round_status(current_setting('shared_history.eighteen')::uuid,'completed');

do $$
begin
  if (select count(*) from public.golf_rounds where source_session_id in(
    current_setting('shared_history.nine')::uuid,current_setting('shared_history.eighteen')::uuid
  ))<>2 then raise exception 'Host did not receive exactly one result per shared round'; end if;

  if not exists(select 1 from public.golf_rounds
    where user_id=auth.uid() and source_session_id=current_setting('shared_history.nine')::uuid
      and hole_count=9 and cardinality(holes)=9 and total=36 and front=36 and back is null
      and par=36 and course='Synthetic Links' and tee='Blue' and played_on='2032-06-10'
      and differential is not null)
  then raise exception 'Host 9-hole result was not materialized correctly'; end if;

  if not exists(select 1 from public.golf_rounds
    where user_id=auth.uid() and source_session_id=current_setting('shared_history.eighteen')::uuid
      and hole_count=18 and cardinality(holes)=18 and total=72 and front=36 and back=36
      and par=72 and course='Synthetic Links' and tee='Blue' and played_on='2032-06-11'
      and differential is not null)
  then raise exception 'Host 18-hole result was not materialized correctly'; end if;
end $$;

-- A normal individual result remains writable and is not source-linked.
insert into public.golf_rounds(
  id,user_id,player,played_on,course,tee,hole_count,par,course_rating,slope,pcc,holes,front,back,total,differential
) values(
  'shared-history-existing-individual',auth.uid(),'Golfer','2032-06-09','Synthetic Links','Blue',9,36,35.7,128,0,array_fill(4::smallint,array[9]),36,null,36,0.3
);
update public.golf_rounds set player='Updated Golfer' where id='shared-history-existing-individual';

do $$
declare changed_rows integer;
begin
  update public.golf_rounds set total=37 where source_session_id=current_setting('shared_history.nine')::uuid;
  get diagnostics changed_rows=row_count;
  if changed_rows<>0 then raise exception 'Linked history result remained editable'; end if;

  begin
    insert into public.golf_rounds(
      id,user_id,player,played_on,course,tee,hole_count,par,course_rating,slope,pcc,holes,front,back,total,differential,source_session_id,source_scorecard_id
    ) select
      'forged-shared-result',auth.uid(),'Golfer','2032-06-10','Synthetic Links','Blue',9,36,35.7,128,0,array_fill(4::smallint,array[9]),36,null,36,0.3,
      source_session_id,source_scorecard_id
    from public.golf_rounds where source_session_id=current_setting('shared_history.nine')::uuid;
    raise exception 'Client forged a linked history result';
  exception when insufficient_privilege then null; end;
end $$;

-- B sees only B's own two results, each derived only from B's own scorecard.
select set_config('request.jwt.claim.sub',current_setting('shared_history.b'),true);
do $$
begin
  if (select count(*) from public.golf_rounds where source_session_id in(
    current_setting('shared_history.nine')::uuid,current_setting('shared_history.eighteen')::uuid
  ))<>2 then raise exception 'Participant did not receive exactly one result per shared round'; end if;

  if not exists(select 1 from public.golf_rounds
    where user_id=auth.uid() and source_session_id=current_setting('shared_history.nine')::uuid
      and hole_count=9 and total=45 and front=45 and back is null)
  then raise exception 'Participant 9-hole result used the wrong scorecard'; end if;

  if not exists(select 1 from public.golf_rounds
    where user_id=auth.uid() and source_session_id=current_setting('shared_history.eighteen')::uuid
      and hole_count=18 and total=90 and front=45 and back=45)
  then raise exception 'Participant 18-hole result used the wrong scorecard'; end if;

  if exists(select 1 from public.golf_rounds where user_id=current_setting('shared_history.a')::uuid)
  then raise exception 'Participant read the host personal history'; end if;
end $$;

-- An unrelated authenticated user cannot enumerate any materialized result.
select set_config('request.jwt.claim.sub',current_setting('shared_history.c'),true);
do $$
begin
  if exists(select 1 from public.golf_rounds where source_session_id in(
    current_setting('shared_history.nine')::uuid,current_setting('shared_history.eighteen')::uuid
  )) then raise exception 'Unrelated user read shared-round history'; end if;
end $$;

reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$
begin
  begin
    perform count(*) from public.golf_rounds;
    raise exception 'Anonymous user read golf history';
  exception when insufficient_privilege then null; end;
end $$;

rollback;
select 'fairway_shared_round_history_rls_test_passed' as result;

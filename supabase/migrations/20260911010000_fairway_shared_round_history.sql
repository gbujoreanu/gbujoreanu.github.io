begin;

alter table public.golf_rounds
  add column if not exists source_session_id uuid,
  add column if not exists source_scorecard_id uuid;

alter table public.golf_rounds
  drop constraint if exists golf_rounds_shared_source_pair_check;
alter table public.golf_rounds
  add constraint golf_rounds_shared_source_pair_check
  check ((source_session_id is null) = (source_scorecard_id is null));

alter table public.fairway_scorecards
  drop constraint if exists fairway_scorecards_source_key;
alter table public.fairway_scorecards
  add constraint fairway_scorecards_source_key unique (id,session_id,player_id);

alter table public.golf_rounds
  drop constraint if exists golf_rounds_shared_scorecard_fkey;
alter table public.golf_rounds
  add constraint golf_rounds_shared_scorecard_fkey
  foreign key (source_scorecard_id,source_session_id,user_id)
  references public.fairway_scorecards(id,session_id,player_id)
  on delete restrict;

create unique index if not exists golf_rounds_one_shared_result_per_player
  on public.golf_rounds(user_id,source_session_id)
  where source_session_id is not null;

create unique index if not exists golf_rounds_one_result_per_scorecard
  on public.golf_rounds(source_scorecard_id)
  where source_scorecard_id is not null;

create index if not exists golf_rounds_source_session_idx
  on public.golf_rounds(source_session_id)
  where source_session_id is not null;

create or replace function public.fairway_protect_shared_history_result()
returns trigger language plpgsql set search_path=pg_catalog,public
as $$
begin
  if old.source_session_id is not null then
    raise exception 'shared round results cannot be edited';
  end if;
  return new;
end $$;

drop trigger if exists fairway_protect_shared_history_result on public.golf_rounds;
create trigger fairway_protect_shared_history_result
before update on public.golf_rounds
for each row execute function public.fairway_protect_shared_history_result();

create or replace function public.fairway_materialize_completed_round(round_session_id uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public
as $$
declare
  shared_round public.fairway_round_sessions;
begin
  select * into shared_round
  from public.fairway_round_sessions
  where id=round_session_id and status='completed';

  if not found then
    raise exception 'completed round unavailable';
  end if;

  insert into public.golf_rounds(
    id,user_id,player,played_on,course,tee,par,course_rating,slope,pcc,
    holes,front,back,total,differential,visibility,hole_count,
    source_session_id,source_scorecard_id,created_at,updated_at
  )
  select
    'shared-'||shared_round.id::text,
    scorecard.player_id,
    left(coalesce(nullif(btrim(profile.display_name),''),nullif(btrim(profile.handle),''),'Golfer'),100),
    timezone(shared_round.time_zone,shared_round.scheduled_at)::date,
    shared_round.course_name,
    shared_round.tee_name,
    case when shared_round.hole_count=9 then round(shared_round.par/2.0)::smallint else shared_round.par end,
    case when shared_round.hole_count=9 then round(shared_round.course_rating/2,1) else shared_round.course_rating end,
    shared_round.slope,
    0,
    scorecard.holes,
    scorecard.front,
    scorecard.back,
    scorecard.total,
    scorecard.differential,
    'private',
    shared_round.hole_count,
    shared_round.id,
    scorecard.id,
    scorecard.updated_at,
    scorecard.updated_at
  from public.fairway_round_participants participant
  join public.fairway_scorecards scorecard
    on scorecard.session_id=participant.session_id
   and scorecard.player_id=participant.user_id
   and scorecard.status='final'
   and cardinality(scorecard.holes)=shared_round.hole_count
  left join public.profiles profile on profile.id=scorecard.player_id
  where participant.session_id=shared_round.id
    and participant.invitation_status='accepted'
  on conflict do nothing;
end $$;

create or replace function public.fairway_update_round_status(round_session_id uuid,next_status text)
returns void language plpgsql security definer set search_path=pg_catalog,public
as $$
declare
  current_status text;
  expected_holes smallint;
  incomplete integer;
begin
  if next_status not in('in_progress','completed','cancelled') then
    raise exception 'invalid status';
  end if;

  select status,hole_count into current_status,expected_holes
  from public.fairway_round_sessions
  where id=round_session_id and host_id=auth.uid()
  for update;

  if not found then raise exception 'round unavailable'; end if;

  if current_status='completed' and next_status='completed' then
    perform public.fairway_materialize_completed_round(round_session_id);
    return;
  end if;

  if current_status in('completed','cancelled') or (current_status='planned' and next_status='completed') then
    raise exception 'invalid transition';
  end if;

  if next_status='completed' then
    select count(*) into incomplete
    from public.fairway_round_participants participant
    left join public.fairway_scorecards scorecard
      on scorecard.session_id=participant.session_id
     and scorecard.player_id=participant.user_id
     and scorecard.status='final'
     and cardinality(scorecard.holes)=expected_holes
    where participant.session_id=round_session_id
      and participant.invitation_status='accepted'
      and scorecard.id is null;

    if incomplete>0 then
      raise exception 'all accepted players need a final scorecard';
    end if;
  end if;

  update public.fairway_round_sessions set status=next_status where id=round_session_id;

  if next_status='completed' then
    perform public.fairway_materialize_completed_round(round_session_id);
  end if;
end $$;

do $$
declare completed_round record;
begin
  for completed_round in select id from public.fairway_round_sessions where status='completed'
  loop
    perform public.fairway_materialize_completed_round(completed_round.id);
  end loop;
end $$;

revoke all on function public.fairway_materialize_completed_round(uuid) from public,anon,authenticated;
revoke all on function public.fairway_protect_shared_history_result() from public,anon,authenticated;
revoke all on function public.fairway_update_round_status(uuid,text) from public,anon;
grant execute on function public.fairway_update_round_status(uuid,text) to authenticated;

revoke truncate,references,trigger on table public.golf_rounds from authenticated;
grant insert,update on table public.golf_rounds to authenticated;

drop policy if exists golf_rounds_insert_own on public.golf_rounds;
create policy golf_rounds_insert_own on public.golf_rounds
for insert to authenticated
with check (
  (select auth.uid())=user_id
  and source_session_id is null
  and source_scorecard_id is null
);

drop policy if exists golf_rounds_update_own on public.golf_rounds;
create policy golf_rounds_update_own on public.golf_rounds
for update to authenticated
using (
  (select auth.uid())=user_id
  and source_session_id is null
  and source_scorecard_id is null
)
with check (
  (select auth.uid())=user_id
  and source_session_id is null
  and source_scorecard_id is null
);

commit;

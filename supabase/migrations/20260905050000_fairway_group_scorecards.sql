begin;

-- Return safe discoverable matches even when they are ineligible so the Family
-- UI can explain the state instead of incorrectly reporting no matching person.
create or replace function public.ecosystem_household_candidates(search_text text,result_limit integer default 30)
returns table(id uuid,display_name text,handle text,bio text,avatar_path text,invitation_state text)
language sql stable security definer set search_path=pg_catalog,public
as $$
  with owned as (
    select h.id from public.ecosystem_households h where h.owner_id=auth.uid() limit 1
  ), query as (
    select regexp_replace(btrim(coalesce(search_text,'')),'^@','') value
  )
  select p.id,p.display_name,p.handle,p.bio,p.avatar_path,
    case
      when exists(select 1 from public.ecosystem_household_members m where m.user_id=p.id and m.household_id=owned.id) then 'already_member'
      when exists(select 1 from public.ecosystem_household_invitations i where i.household_id=owned.id and i.recipient_id=p.id and i.status='pending') then 'already_invited'
      when exists(select 1 from public.ecosystem_household_members m where m.user_id=p.id) then 'unavailable'
      else 'available'
    end
  from public.profiles p cross join owned cross join query q
  where auth.uid() is not null and char_length(q.value)>=2 and p.id<>auth.uid() and p.discoverable
    and not public.ecosystem_is_blocked(auth.uid(),p.id)
    and (p.handle ilike '%'||q.value||'%' or p.display_name ilike '%'||q.value||'%')
  order by lower(coalesce(p.display_name,p.handle)),p.id
  limit least(greatest(result_limit,1),50)
$$;

create or replace function public.ecosystem_current_user_can_view_avatar(target_user uuid)
returns boolean language sql stable security definer set search_path=pg_catalog,public
as $$
  select auth.uid() is not null and target_user is not null
    and not public.ecosystem_is_blocked(auth.uid(),target_user) and (
      target_user=auth.uid()
      or exists(select 1 from public.profiles p where p.id=target_user and p.discoverable)
      or exists(select 1 from public.ecosystem_follows f where (f.follower_id=auth.uid() and f.followed_id=target_user) or (f.follower_id=target_user and f.followed_id=auth.uid()))
      or public.ecosystem_are_friends(auth.uid(),target_user)
      or exists(select 1 from public.ecosystem_friend_requests r where r.status='pending' and ((r.sender_id=auth.uid() and r.recipient_id=target_user) or (r.sender_id=target_user and r.recipient_id=auth.uid())))
      or exists(select 1 from public.ecosystem_household_members mine join public.ecosystem_household_members theirs using(household_id) where mine.user_id=auth.uid() and theirs.user_id=target_user)
      or exists(select 1 from public.ecosystem_household_invitations i where i.status='pending' and ((i.sender_id=auth.uid() and i.recipient_id=target_user) or (i.sender_id=target_user and i.recipient_id=auth.uid())))
      or exists(select 1 from public.fairway_round_participants mine
        join public.fairway_round_participants theirs using(session_id)
        join public.fairway_round_sessions s on s.id=mine.session_id
        where mine.user_id=auth.uid() and theirs.user_id=target_user
          and mine.invitation_status='accepted' and theirs.invitation_status='accepted'
          and s.status in('planned','in_progress','completed'))
    )
$$;

-- Group scoring is stored one row per session/player. All writes go through the
-- guarded RPC below; authenticated clients retain read-only table access.
create index if not exists fairway_scorecards_session_status
  on public.fairway_scorecards(session_id,status,player_id);

create or replace function public.fairway_current_user_can_read_session(target_session uuid)
returns boolean language sql stable security definer set search_path=pg_catalog,public
as $$
  select auth.uid() is not null and exists(
    select 1 from public.fairway_round_sessions s
    where s.id=target_session and s.status in('planned','in_progress','completed')
      and not public.ecosystem_is_blocked(s.host_id,auth.uid())
      and (s.host_id=auth.uid() or exists(
        select 1 from public.fairway_round_participants p
        where p.session_id=s.id and p.user_id=auth.uid() and p.invitation_status='accepted'
      ))
  )
$$;

create or replace function public.fairway_upsert_scorecard(
  round_session_id uuid,scorecard_player uuid,scores smallint[],card_status text default 'draft'
)
returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare
  s public.fairway_round_sessions;
  scorecard_id uuid;
  front_total integer;
  back_total integer;
  total_score integer;
  diff numeric;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if card_status not in('draft','final') then raise exception 'invalid scorecard status'; end if;
  if scores is null or cardinality(scores)<>18
    or exists(select 1 from unnest(scores) n where n is not null and (n<1 or n>20))
    or (card_status='final' and exists(select 1 from unnest(scores) n where n is null))
  then raise exception 'invalid scores'; end if;

  select * into s from public.fairway_round_sessions
  where id=round_session_id and status in('planned','in_progress') for update;
  if not found or public.ecosystem_is_blocked(s.host_id,auth.uid()) then raise exception 'round unavailable'; end if;

  if not exists(select 1 from public.fairway_round_participants p
    where p.session_id=round_session_id and p.user_id=scorecard_player and p.invitation_status='accepted')
  then raise exception 'player unavailable'; end if;

  if auth.uid()<>scorecard_player and auth.uid()<>s.designated_scorer_id
  then raise exception 'not allowed to score for this player'; end if;

  select sum(n)::integer into front_total from unnest(scores[1:9]) n;
  select sum(n)::integer into back_total from unnest(scores[10:18]) n;
  total_score=coalesce(front_total,0)+coalesce(back_total,0);
  if not exists(select 1 from unnest(scores) n where n is null) then
    diff=round((total_score-s.course_rating)*113/s.slope,1);
  end if;

  insert into public.fairway_scorecards(session_id,player_id,recorded_by,holes,front,back,total,differential,status)
  values(round_session_id,scorecard_player,auth.uid(),scores,front_total,back_total,
    case when exists(select 1 from unnest(scores) n where n is not null) then total_score end,diff,card_status)
  on conflict(session_id,player_id) do update set
    recorded_by=auth.uid(),holes=excluded.holes,front=excluded.front,back=excluded.back,
    total=excluded.total,differential=excluded.differential,status=excluded.status,updated_at=now()
  returning id into scorecard_id;

  update public.fairway_round_sessions set status='in_progress'
  where id=round_session_id and status='planned';
  return scorecard_id;
end
$$;

create or replace function public.fairway_group_scorecard(round_session_id uuid)
returns jsonb language sql stable security definer set search_path=pg_catalog,public
as $$
  select case when public.fairway_current_user_can_read_session(s.id) then jsonb_build_object(
    'id',s.id,'host_id',s.host_id,'designated_scorer_id',s.designated_scorer_id,
    'course_name',s.course_name,'tee_name',s.tee_name,'par',s.par,
    'course_rating',s.course_rating,'slope',s.slope,'scheduled_at',s.scheduled_at,
    'status',s.status,'viewer_id',auth.uid(),
    'participants',coalesce((select jsonb_agg(jsonb_build_object(
      'id',p.user_id,'display_name',coalesce(pr.display_name,'Golfer'),'handle',pr.handle,
      'avatar_path',pr.avatar_path,'role',p.role,
      'holes',coalesce(c.holes,array_fill(null::smallint,array[18])),
      'front',c.front,'back',c.back,'total',c.total,'differential',c.differential,
      'scorecard_status',coalesce(c.status,'draft')
    ) order by (p.role='host') desc,lower(coalesce(pr.display_name,pr.handle,'')))
      from public.fairway_round_participants p
      left join public.profiles pr on pr.id=p.user_id
      left join public.fairway_scorecards c on c.session_id=p.session_id and c.player_id=p.user_id
      where p.session_id=s.id and p.invitation_status='accepted'),'[]'::jsonb)
  ) else null end
  from public.fairway_round_sessions s where s.id=round_session_id
$$;

-- Keep the tee sheet useful after scoring begins and retain completed shared cards.
create or replace function public.fairway_planned_rounds()
returns jsonb language sql stable security definer set search_path=pg_catalog,public
as $$
  with visible as (
    select s.*,(s.host_id=auth.uid()) is_host,
      coalesce((select p.invitation_status from public.fairway_round_participants p
        where p.session_id=s.id and p.user_id=auth.uid()),'accepted') viewer_status
    from public.fairway_round_sessions s
    where auth.uid() is not null and s.status in('planned','in_progress','completed')
      and not public.ecosystem_is_blocked(s.host_id,auth.uid())
      and (s.host_id=auth.uid() or exists(select 1 from public.fairway_round_participants p
        where p.session_id=s.id and p.user_id=auth.uid()
          and (p.invitation_status='accepted' or (p.invitation_status='invited' and s.status='planned'))))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,'host_id',s.host_id,'host_name',coalesce(hp.display_name,'Golfer'),
    'host_handle',hp.handle,'host_avatar_path',hp.avatar_path,'course_id',s.course_id,
    'course_name',s.course_name,'tee_name',s.tee_name,'par',s.par,'course_rating',s.course_rating,
    'slope',s.slope,'scheduled_at',s.scheduled_at,'time_zone',s.time_zone,'notes',s.notes,
    'status',s.status,'is_host',s.is_host,'viewer_status',s.viewer_status,
    'participants',coalesce((select jsonb_agg(jsonb_build_object(
      'id',p.user_id,'display_name',coalesce(pp.display_name,'Golfer'),'handle',pp.handle,
      'avatar_path',pp.avatar_path,'role',p.role,'invitation_status',p.invitation_status
    ) order by (p.role='host') desc,lower(coalesce(pp.display_name,pp.handle,'')))
      from public.fairway_round_participants p left join public.profiles pp on pp.id=p.user_id
      where p.session_id=s.id and p.invitation_status<>'removed'),'[]'::jsonb)
  ) order by s.scheduled_at desc),'[]'::jsonb)
  from visible s left join public.profiles hp on hp.id=s.host_id
$$;

revoke all on function public.ecosystem_household_candidates(text,integer),public.ecosystem_current_user_can_view_avatar(uuid),
  public.fairway_upsert_scorecard(uuid,uuid,smallint[],text),
  public.fairway_group_scorecard(uuid),public.fairway_current_user_can_read_session(uuid) from public,anon;
revoke all on function public.fairway_current_user_can_read_session(uuid) from authenticated;
grant execute on function public.fairway_upsert_scorecard(uuid,uuid,smallint[],text),
  public.fairway_group_scorecard(uuid),public.ecosystem_household_candidates(text,integer),
  public.fairway_current_user_can_read_session(uuid),public.ecosystem_current_user_can_view_avatar(uuid) to authenticated;

commit;

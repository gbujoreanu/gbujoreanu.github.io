begin;

create index if not exists fairway_round_sessions_upcoming
  on public.fairway_round_sessions(host_id,scheduled_at)
  where status='planned';

create index if not exists fairway_round_participants_session_status
  on public.fairway_round_participants(session_id,invitation_status,user_id);

create or replace function public.fairway_current_user_can_read_session(target_session uuid)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,public
as $$
  select auth.uid() is not null and (
    exists(select 1 from public.fairway_round_sessions s where s.id=target_session and s.host_id=auth.uid())
    or exists(
      select 1 from public.fairway_round_participants p
      where p.session_id=target_session and p.user_id=auth.uid()
        and p.invitation_status in('invited','accepted')
    )
  )
$$;

create or replace function public.fairway_create_round_session(
  course_row_id text,play_at timestamptz,zone text,note_text text default ''
)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  c public.golf_courses;
  session_id uuid;
  clean_zone text:=coalesce(nullif(btrim(zone),''),'UTC');
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if play_at is null or play_at<=now() then raise exception 'tee time must be in the future'; end if;
  if not exists(select 1 from pg_catalog.pg_timezone_names where name=clean_zone) then raise exception 'invalid time zone'; end if;
  if char_length(coalesce(note_text,''))>1000 then raise exception 'notes are too long'; end if;
  select * into c from public.golf_courses where id=course_row_id and user_id=auth.uid();
  if not found then raise exception 'course unavailable'; end if;

  insert into public.fairway_round_sessions(
    host_id,course_id,course_name,tee_name,par,course_rating,slope,
    scheduled_at,time_zone,notes,status,visibility,designated_scorer_id
  ) values(
    auth.uid(),c.id,c.course,c.tee,c.par,c.rating,c.slope,
    play_at,clean_zone,coalesce(note_text,''),'planned','private',auth.uid()
  ) returning id into session_id;

  insert into public.fairway_round_participants(session_id,user_id,role,invitation_status,responded_at)
  values(session_id,auth.uid(),'host','accepted',now());
  return session_id;
end
$$;

create or replace function public.fairway_invite_player(round_session_id uuid,target_id uuid)
returns void
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  existing_status text;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if target_id is null or target_id=auth.uid() then raise exception 'cannot invite yourself'; end if;
  if not exists(
    select 1 from public.fairway_round_sessions
    where id=round_session_id and host_id=auth.uid() and status='planned'
  ) then raise exception 'round unavailable'; end if;
  if not public.ecosystem_are_friends(auth.uid(),target_id)
    or public.ecosystem_is_blocked(auth.uid(),target_id) then raise exception 'friend unavailable'; end if;

  select invitation_status into existing_status
  from public.fairway_round_participants
  where session_id=round_session_id and user_id=target_id
  for update;
  if existing_status in('invited','accepted') then raise exception 'already invited'; end if;

  insert into public.fairway_round_participants(session_id,user_id,role,invitation_status,responded_at,add_to_daymark)
  values(round_session_id,target_id,'player','invited',null,false)
  on conflict(session_id,user_id) do update
    set role='player',invitation_status='invited',responded_at=null,add_to_daymark=false;

  delete from public.ecosystem_notifications
  where recipient_id=target_id and source_app='fairway' and source_type='planned_round'
    and source_id=round_session_id::text and read_at is null;
  insert into public.ecosystem_notifications(
    recipient_id,actor_id,notification_type,source_app,source_type,source_id,message
  ) values(
    target_id,auth.uid(),'round_invite','fairway','planned_round',round_session_id::text,
    'invited you to a golf round'
  );
end
$$;

create or replace function public.fairway_respond_round(
  round_session_id uuid,response text,add_calendar boolean default false
)
returns void
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if response not in('accepted','declined') then raise exception 'invalid response'; end if;
  if not exists(
    select 1 from public.fairway_round_sessions
    where id=round_session_id and status='planned'
  ) then raise exception 'invitation unavailable'; end if;

  update public.fairway_round_participants
  set invitation_status=response,add_to_daymark=false,responded_at=now()
  where session_id=round_session_id and user_id=auth.uid() and role='player'
    and invitation_status='invited';
  if not found then raise exception 'invitation unavailable'; end if;

  update public.ecosystem_notifications
  set read_at=coalesce(read_at,now())
  where recipient_id=auth.uid() and source_app='fairway' and source_type='planned_round'
    and source_id=round_session_id::text;
  delete from public.platform_event_subscriptions
  where user_id=auth.uid() and event_id in(
    select id from public.platform_events
    where source_app='fairway' and source_type='planned_round' and source_id=round_session_id::text
  );
end
$$;

create or replace function public.fairway_update_planned_round(
  round_session_id uuid,course_row_id text,play_at timestamptz,zone text,note_text text default ''
)
returns void
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
  c public.golf_courses;
  clean_zone text:=coalesce(nullif(btrim(zone),''),'UTC');
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if play_at is null or play_at<=now() then raise exception 'tee time must be in the future'; end if;
  if not exists(select 1 from pg_catalog.pg_timezone_names where name=clean_zone) then raise exception 'invalid time zone'; end if;
  if char_length(coalesce(note_text,''))>1000 then raise exception 'notes are too long'; end if;
  select * into c from public.golf_courses where id=course_row_id and user_id=auth.uid();
  if not found then raise exception 'course unavailable'; end if;

  update public.fairway_round_sessions
  set course_id=c.id,course_name=c.course,tee_name=c.tee,par=c.par,
      course_rating=c.rating,slope=c.slope,scheduled_at=play_at,
      time_zone=clean_zone,notes=coalesce(note_text,'')
  where id=round_session_id and host_id=auth.uid() and status='planned';
  if not found then raise exception 'round unavailable'; end if;
end
$$;

create or replace function public.fairway_remove_round_participant(round_session_id uuid,target_id uuid)
returns void
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not exists(
    select 1 from public.fairway_round_sessions
    where id=round_session_id and host_id=auth.uid() and status='planned'
  ) then raise exception 'round unavailable'; end if;
  update public.fairway_round_participants
  set invitation_status='removed',add_to_daymark=false,responded_at=now()
  where session_id=round_session_id and user_id=target_id and role='player'
    and invitation_status in('invited','accepted');
  if not found then raise exception 'participant unavailable'; end if;
  delete from public.ecosystem_notifications
  where recipient_id=target_id and source_app='fairway' and source_type='planned_round'
    and source_id=round_session_id::text;
  delete from public.platform_event_access
  where user_id=target_id and event_id in(
    select id from public.platform_events
    where source_app='fairway' and source_type='planned_round' and source_id=round_session_id::text
  );
end
$$;

create or replace function public.fairway_leave_planned_round(round_session_id uuid)
returns void
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  update public.fairway_round_participants
  set invitation_status='removed',add_to_daymark=false,responded_at=now()
  where session_id=round_session_id and user_id=auth.uid() and role='player'
    and invitation_status='accepted'
    and exists(
      select 1 from public.fairway_round_sessions
      where id=round_session_id and status='planned'
    );
  if not found then raise exception 'round unavailable'; end if;
  delete from public.platform_event_access
  where user_id=auth.uid() and event_id in(
    select id from public.platform_events
    where source_app='fairway' and source_type='planned_round' and source_id=round_session_id::text
  );
end
$$;

create or replace function public.fairway_cancel_planned_round(round_session_id uuid)
returns void
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  update public.fairway_round_sessions
  set status='cancelled'
  where id=round_session_id and host_id=auth.uid() and status='planned';
  if not found then raise exception 'round unavailable'; end if;
  update public.platform_events set status='cancelled'
  where owner_id=auth.uid() and source_app='fairway' and source_type='planned_round'
    and source_id=round_session_id::text;
  update public.ecosystem_notifications set read_at=coalesce(read_at,now())
  where source_app='fairway' and source_type='planned_round' and source_id=round_session_id::text;
end
$$;

create or replace function public.fairway_planned_rounds()
returns jsonb
language sql
stable
security definer
set search_path=pg_catalog,public
as $$
  with visible as (
    select s.*,
      (s.host_id=auth.uid()) as is_host,
      coalesce((select p.invitation_status from public.fairway_round_participants p
        where p.session_id=s.id and p.user_id=auth.uid()),'accepted') as viewer_status
    from public.fairway_round_sessions s
    where auth.uid() is not null and s.status='planned' and (
      s.host_id=auth.uid() or exists(
        select 1 from public.fairway_round_participants p
        where p.session_id=s.id and p.user_id=auth.uid()
          and p.invitation_status in('invited','accepted')
      )
    )
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,'host_id',s.host_id,'host_name',coalesce(hp.display_name,'Golfer'),
    'host_handle',hp.handle,'host_avatar_path',hp.avatar_path,
    'course_id',s.course_id,'course_name',s.course_name,'tee_name',s.tee_name,
    'par',s.par,'course_rating',s.course_rating,'slope',s.slope,
    'scheduled_at',s.scheduled_at,'time_zone',s.time_zone,'notes',s.notes,
    'status',s.status,'is_host',s.is_host,'viewer_status',s.viewer_status,
    'participants',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.user_id,'display_name',coalesce(pp.display_name,'Golfer'),'handle',pp.handle,
        'avatar_path',pp.avatar_path,'role',p.role,'invitation_status',p.invitation_status
      ) order by (p.role='host') desc,lower(coalesce(pp.display_name,pp.handle,'')))
      from public.fairway_round_participants p
      left join public.profiles pp on pp.id=p.user_id
      where p.session_id=s.id and p.invitation_status<>'removed'
    ),'[]'::jsonb)
  ) order by s.scheduled_at),'[]'::jsonb)
  from visible s
  left join public.profiles hp on hp.id=s.host_id
$$;

-- Keep the older compatibility reader aligned with the stricter participant lifecycle.
create or replace function public.fairway_social_rounds()
returns table(session_id uuid,host_id uuid,host_name text,host_handle text,course_name text,
  tee_name text,par smallint,course_rating numeric,slope smallint,scheduled_at timestamptz,
  time_zone text,notes text,status text,visibility text,participant_status text,add_to_daymark boolean)
language sql stable security definer set search_path=pg_catalog,public
as $$
  select s.id,s.host_id,coalesce(p.display_name,'Golfer'),p.handle,s.course_name,s.tee_name,
    s.par,s.course_rating,s.slope,s.scheduled_at,s.time_zone,
    case when rp.invitation_status='accepted' then s.notes else '' end,
    s.status,s.visibility,rp.invitation_status,false
  from public.fairway_round_sessions s
  join public.fairway_round_participants rp on rp.session_id=s.id and rp.user_id=auth.uid()
  join public.profiles p on p.id=s.host_id
  where auth.uid() is not null and rp.invitation_status in('invited','accepted')
    and s.status in('planned','in_progress')
    and not public.ecosystem_is_blocked(s.host_id,auth.uid())
  order by s.scheduled_at desc
$$;

revoke update on public.fairway_round_sessions from authenticated;
drop policy if exists fairway_sessions_host_update on public.fairway_round_sessions;
drop policy if exists fairway_scorecards_participant_select on public.fairway_scorecards;
create policy fairway_scorecards_participant_select on public.fairway_scorecards
  for select to authenticated using(public.fairway_current_user_can_read_session(session_id));

revoke all on function public.fairway_update_planned_round(uuid,text,timestamptz,text,text),
  public.fairway_remove_round_participant(uuid,uuid),public.fairway_leave_planned_round(uuid),
  public.fairway_cancel_planned_round(uuid),public.fairway_planned_rounds() from public,anon;
grant execute on function public.fairway_update_planned_round(uuid,text,timestamptz,text,text),
  public.fairway_remove_round_participant(uuid,uuid),public.fairway_leave_planned_round(uuid),
  public.fairway_cancel_planned_round(uuid),public.fairway_planned_rounds() to authenticated;

commit;

begin;

revoke insert,update,delete,truncate,references,trigger on public.platform_events,public.platform_event_access,public.platform_event_subscriptions from authenticated;

-- A platform event is a source reference, never a second scorecard or Daymark record.
create or replace function public.fairway_publish_calendar_reference()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $$
begin
  if TG_OP='DELETE' then
    delete from public.platform_events where source_app='fairway' and source_type='planned_round' and source_id=old.id::text;
    return old;
  end if;
  insert into public.platform_events(owner_id,source_app,source_type,source_id,title,starts_at,ends_at,all_day,status,deep_link,details)
  values(new.host_id,'fairway','planned_round',new.id::text,left('Fairway · '||new.course_name,160),new.scheduled_at,null,false,
    case when new.status='cancelled' then 'cancelled' else 'active' end,'/golf/#upcoming/'||new.id::text,'{}'::jsonb)
  on conflict(owner_id,source_app,source_type,source_id) do update set
    title=excluded.title,starts_at=excluded.starts_at,ends_at=null,all_day=false,status=excluded.status,deep_link=excluded.deep_link,details='{}'::jsonb;
  return new;
end $$;
revoke all on function public.fairway_publish_calendar_reference() from public,anon,authenticated;
create trigger fairway_calendar_reference after insert or update of scheduled_at,course_name,tee_name,status or delete
  on public.fairway_round_sessions for each row execute function public.fairway_publish_calendar_reference();

-- Backfill references only; preserve source rounds and all personal Daymark records.
insert into public.platform_events(owner_id,source_app,source_type,source_id,title,starts_at,status,deep_link)
select host_id,'fairway','planned_round',id::text,left('Fairway · '||course_name,160),scheduled_at,
  case when status='cancelled' then 'cancelled' else 'active' end,'/golf/#upcoming/'||id::text
from public.fairway_round_sessions
on conflict(owner_id,source_app,source_type,source_id) do update set
  title=excluded.title,starts_at=excluded.starts_at,ends_at=null,all_day=false,status=excluded.status,deep_link=excluded.deep_link,details='{}'::jsonb;

-- Do not trust old access/subscription rows after decline/removal/cancellation.
create or replace function public.platform_current_user_can_read_event(target_event uuid)
returns boolean language sql stable security definer set search_path=pg_catalog,public
as $$
  select auth.uid() is not null and exists(
    select 1 from public.platform_events e where e.id=target_event and
    case when e.source_app='fairway' and e.source_type='planned_round' then exists(
      select 1 from public.fairway_round_sessions r where r.id::text=e.source_id and r.host_id=e.owner_id
        and r.status<>'cancelled' and not public.ecosystem_is_blocked(r.host_id,auth.uid())
        and (r.host_id=auth.uid() or exists(select 1 from public.fairway_round_participants p
          where p.session_id=r.id and p.user_id=auth.uid() and p.invitation_status='accepted'))
    ) else e.owner_id=auth.uid() or exists(select 1 from public.platform_event_access a where a.event_id=e.id and a.user_id=auth.uid()) end
  )
$$;
revoke all on function public.platform_current_user_can_read_event(uuid) from public,anon;
grant execute on function public.platform_current_user_can_read_event(uuid) to authenticated;

-- Calendar-specific, allowlisted projection. No notes, scores, email, or auth metadata.
-- Read source rows each time so participant/tee/profile changes cannot leave stale copies.
create function public.daymark_fairway_events()
returns table(id uuid,source_id uuid,title text,starts_at timestamptz,time_zone text,course text,tee text,
  host_name text,participant_count bigint,round_status text,deep_link text)
language sql stable security definer set search_path=pg_catalog,public
as $$
  select e.id,r.id,'Fairway · '||r.course_name,r.scheduled_at,r.time_zone,r.course_name,r.tee_name,
    coalesce(nullif(h.display_name,''),nullif(h.handle,''),'Golfer'),
    (select count(*) from public.fairway_round_participants p where p.session_id=r.id and p.invitation_status='accepted'),
    r.status,'/golf/#upcoming/'||r.id::text
  from public.platform_events e
  join public.fairway_round_sessions r on r.id::text=e.source_id and r.host_id=e.owner_id
  left join public.profiles h on h.id=r.host_id
  where e.source_app='fairway' and e.source_type='planned_round'
    and public.platform_current_user_can_read_event(e.id)
  order by r.scheduled_at
$$;
revoke all on function public.daymark_fairway_events() from public,anon;
grant execute on function public.daymark_fairway_events() to authenticated;

-- The older subscription reader must enforce current source authorization too.
create or replace function public.platform_daymark_events()
returns table(id uuid,title text,starts_at timestamptz,ends_at timestamptz,all_day boolean,status text,source_app text,source_type text,source_id text,deep_link text,access_level text)
language sql stable security definer set search_path=pg_catalog,public
as $$
  select e.id,case when a.access_level='busy' then 'Busy' else e.title end,e.starts_at,e.ends_at,e.all_day,e.status,e.source_app,e.source_type,e.source_id,e.deep_link,a.access_level
  from public.platform_event_subscriptions s join public.platform_events e on e.id=s.event_id
    join public.platform_event_access a on a.event_id=e.id and a.user_id=s.user_id
  where s.user_id=auth.uid() and s.consumer_app='daymark' and e.status='active'
    and not public.ecosystem_is_blocked(e.owner_id,s.user_id) and public.platform_current_user_can_read_event(e.id)
$$;
commit;

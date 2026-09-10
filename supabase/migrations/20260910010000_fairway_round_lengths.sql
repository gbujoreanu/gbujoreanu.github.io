begin;

alter table public.golf_rounds
  add column if not exists hole_count smallint not null default 18;
alter table public.fairway_round_sessions
  add column if not exists hole_count smallint not null default 18;

alter table public.golf_rounds drop constraint if exists golf_rounds_hole_count_check;
alter table public.golf_rounds add constraint golf_rounds_hole_count_check check (hole_count in (9,18));
alter table public.fairway_round_sessions drop constraint if exists fairway_round_sessions_hole_count_check;
alter table public.fairway_round_sessions add constraint fairway_round_sessions_hole_count_check check (hole_count in (9,18));

alter table public.golf_rounds drop constraint if exists golf_rounds_holes_check;
alter table public.golf_rounds add constraint golf_rounds_holes_check
  check (cardinality(holes)=hole_count and not (0=any(holes)));
alter table public.golf_rounds alter column back drop not null;
alter table public.golf_rounds drop constraint if exists golf_rounds_back_check;
alter table public.golf_rounds add constraint golf_rounds_back_check
  check ((hole_count=9 and back is null) or (hole_count=18 and back>0));

drop function if exists public.fairway_create_round_session(text,timestamptz,text,text);
create function public.fairway_create_round_session(
  course_row_id text,play_at timestamptz,zone text,note_text text default '',round_holes smallint default 18
)
returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare c public.golf_courses; session_id uuid; clean_zone text:=coalesce(nullif(btrim(zone),''),'UTC');
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if round_holes is null or round_holes not in(9,18) then raise exception 'round must be 9 or 18 holes'; end if;
  if play_at is null or play_at<=now() then raise exception 'tee time must be in the future'; end if;
  if not exists(select 1 from pg_catalog.pg_timezone_names where name=clean_zone) then raise exception 'invalid time zone'; end if;
  if char_length(coalesce(note_text,''))>1000 then raise exception 'notes are too long'; end if;
  select * into c from public.golf_courses where id=course_row_id and user_id=auth.uid();
  if not found then raise exception 'course unavailable'; end if;
  insert into public.fairway_round_sessions(host_id,course_id,course_name,tee_name,par,course_rating,slope,scheduled_at,time_zone,notes,status,visibility,designated_scorer_id,hole_count)
  values(auth.uid(),c.id,c.course,c.tee,c.par,c.rating,c.slope,play_at,clean_zone,coalesce(note_text,''),'planned','private',auth.uid(),round_holes)
  returning id into session_id;
  insert into public.fairway_round_participants(session_id,user_id,role,invitation_status,responded_at)
  values(session_id,auth.uid(),'host','accepted',now());
  return session_id;
end $$;

drop function if exists public.fairway_update_planned_round(uuid,text,timestamptz,text,text);
create function public.fairway_update_planned_round(
  round_session_id uuid,course_row_id text,play_at timestamptz,zone text,note_text text default '',round_holes smallint default 18
)
returns void language plpgsql security definer set search_path=pg_catalog,public
as $$
declare c public.golf_courses; clean_zone text:=coalesce(nullif(btrim(zone),''),'UTC');
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if round_holes is null or round_holes not in(9,18) then raise exception 'round must be 9 or 18 holes'; end if;
  if play_at is null or play_at<=now() then raise exception 'tee time must be in the future'; end if;
  if not exists(select 1 from pg_catalog.pg_timezone_names where name=clean_zone) then raise exception 'invalid time zone'; end if;
  if char_length(coalesce(note_text,''))>1000 then raise exception 'notes are too long'; end if;
  select * into c from public.golf_courses where id=course_row_id and user_id=auth.uid();
  if not found then raise exception 'course unavailable'; end if;
  update public.fairway_round_sessions set course_id=c.id,course_name=c.course,tee_name=c.tee,par=c.par,
    course_rating=c.rating,slope=c.slope,scheduled_at=play_at,time_zone=clean_zone,
    notes=coalesce(note_text,''),hole_count=round_holes
  where id=round_session_id and host_id=auth.uid() and status='planned';
  if not found then raise exception 'round unavailable'; end if;
end $$;

create or replace function public.fairway_upsert_scorecard(round_session_id uuid,scorecard_player uuid,scores smallint[],card_status text default 'draft')
returns uuid language plpgsql security definer set search_path=pg_catalog,public
as $$
declare s public.fairway_round_sessions; scorecard_id uuid; front_total integer; back_total integer; total_score integer; diff numeric; effective_rating numeric;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if card_status not in('draft','final') then raise exception 'invalid scorecard status'; end if;
  select * into s from public.fairway_round_sessions where id=round_session_id and status in('planned','in_progress') for update;
  if not found or public.ecosystem_is_blocked(s.host_id,auth.uid()) then raise exception 'round unavailable'; end if;
  if scores is null or cardinality(scores)<>s.hole_count
    or exists(select 1 from unnest(scores) n where n is not null and (n<1 or n>20))
    or (card_status='final' and exists(select 1 from unnest(scores) n where n is null)) then raise exception 'invalid scores'; end if;
  if not exists(select 1 from public.fairway_round_participants p where p.session_id=round_session_id and p.user_id=scorecard_player and p.invitation_status='accepted') then raise exception 'player unavailable'; end if;
  if auth.uid()<>scorecard_player and auth.uid()<>s.designated_scorer_id then raise exception 'not allowed to score for this player'; end if;
  select sum(n)::integer into front_total from unnest(scores[1:9]) n;
  if s.hole_count=18 then select sum(n)::integer into back_total from unnest(scores[10:18]) n; else back_total=null; end if;
  total_score=coalesce(front_total,0)+coalesce(back_total,0);
  effective_rating=case when s.hole_count=9 then round(s.course_rating/2,1) else s.course_rating end;
  if not exists(select 1 from unnest(scores) n where n is null) then diff=round((total_score-effective_rating)*113/s.slope,1); end if;
  insert into public.fairway_scorecards(session_id,player_id,recorded_by,holes,front,back,total,differential,status)
  values(round_session_id,scorecard_player,auth.uid(),scores,front_total,back_total,case when exists(select 1 from unnest(scores) n where n is not null) then total_score end,diff,card_status)
  on conflict(session_id,player_id) do update set recorded_by=auth.uid(),holes=excluded.holes,front=excluded.front,back=excluded.back,total=excluded.total,differential=excluded.differential,status=excluded.status,updated_at=now()
  returning id into scorecard_id;
  update public.fairway_round_sessions set status='in_progress' where id=round_session_id and status='planned';
  return scorecard_id;
end $$;

create or replace function public.fairway_group_scorecard(round_session_id uuid)
returns jsonb language sql stable security definer set search_path=pg_catalog,public
as $$
  select case when public.fairway_current_user_can_read_session(s.id) then jsonb_build_object(
    'id',s.id,'host_id',s.host_id,'designated_scorer_id',s.designated_scorer_id,'hole_count',s.hole_count,
    'course_name',s.course_name,'tee_name',s.tee_name,'par',case when s.hole_count=9 then round(s.par/2.0) else s.par end,
    'course_rating',case when s.hole_count=9 then round(s.course_rating/2,1) else s.course_rating end,
    'slope',s.slope,'scheduled_at',s.scheduled_at,'status',s.status,'viewer_id',auth.uid(),
    'participants',coalesce((select jsonb_agg(jsonb_build_object(
      'id',p.user_id,'display_name',coalesce(pr.display_name,'Golfer'),'handle',pr.handle,'avatar_path',pr.avatar_path,'role',p.role,
      'holes',coalesce(c.holes,array_fill(null::smallint,array[s.hole_count])),'front',c.front,'back',c.back,'total',c.total,'differential',c.differential,
      'scorecard_status',coalesce(c.status,'draft')) order by (p.role='host') desc,lower(coalesce(pr.display_name,pr.handle,'')))
      from public.fairway_round_participants p left join public.profiles pr on pr.id=p.user_id left join public.fairway_scorecards c on c.session_id=p.session_id and c.player_id=p.user_id
      where p.session_id=s.id and p.invitation_status='accepted'),'[]'::jsonb)
  ) else null end from public.fairway_round_sessions s where s.id=round_session_id
$$;

create or replace function public.fairway_update_round_status(round_session_id uuid,next_status text)
returns void language plpgsql security definer set search_path=pg_catalog,public
as $$ declare current_status text; expected_holes smallint; incomplete integer; begin
  if next_status not in('in_progress','completed','cancelled') then raise exception 'invalid status'; end if;
  select status,hole_count into current_status,expected_holes from public.fairway_round_sessions where id=round_session_id and host_id=auth.uid() for update;
  if not found then raise exception 'round unavailable'; end if;
  if current_status in('completed','cancelled') or (current_status='planned' and next_status='completed') then raise exception 'invalid transition'; end if;
  if next_status='completed' then
    select count(*) into incomplete from public.fairway_round_participants p left join public.fairway_scorecards c on c.session_id=p.session_id and c.player_id=p.user_id and c.status='final' and cardinality(c.holes)=expected_holes where p.session_id=round_session_id and p.invitation_status='accepted' and c.id is null;
    if incomplete>0 then raise exception 'all accepted players need a final scorecard'; end if;
  end if;
  update public.fairway_round_sessions set status=next_status where id=round_session_id;
end $$;

create or replace function public.fairway_planned_rounds()
returns jsonb language sql stable security definer set search_path=pg_catalog,public
as $$
  with visible as (
    select s.*,(s.host_id=auth.uid()) is_host,coalesce((select p.invitation_status from public.fairway_round_participants p where p.session_id=s.id and p.user_id=auth.uid()),'accepted') viewer_status
    from public.fairway_round_sessions s where auth.uid() is not null and s.status in('planned','in_progress','completed') and not public.ecosystem_is_blocked(s.host_id,auth.uid())
      and (s.host_id=auth.uid() or exists(select 1 from public.fairway_round_participants p where p.session_id=s.id and p.user_id=auth.uid() and (p.invitation_status='accepted' or (p.invitation_status='invited' and s.status='planned'))))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,'host_id',s.host_id,'host_name',coalesce(hp.display_name,'Golfer'),'host_handle',hp.handle,'host_avatar_path',hp.avatar_path,
    'course_id',s.course_id,'course_name',s.course_name,'tee_name',s.tee_name,'par',s.par,'course_rating',s.course_rating,'slope',s.slope,
    'scheduled_at',s.scheduled_at,'time_zone',s.time_zone,'notes',s.notes,'hole_count',s.hole_count,
    'status',s.status,'is_host',s.is_host,'viewer_status',s.viewer_status,
    'participants',coalesce((select jsonb_agg(jsonb_build_object('id',p.user_id,'display_name',coalesce(pp.display_name,'Golfer'),'handle',pp.handle,'avatar_path',pp.avatar_path,'role',p.role,'invitation_status',p.invitation_status) order by (p.role='host') desc,lower(coalesce(pp.display_name,pp.handle,''))) from public.fairway_round_participants p left join public.profiles pp on pp.id=p.user_id where p.session_id=s.id and p.invitation_status<>'removed'),'[]'::jsonb)
  ) order by s.scheduled_at desc),'[]'::jsonb) from visible s left join public.profiles hp on hp.id=s.host_id
$$;

create or replace function public.fairway_publish_calendar_reference()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $$
begin
  if TG_OP='DELETE' then delete from public.platform_events where source_app='fairway' and source_type='planned_round' and source_id=old.id::text; return old; end if;
  insert into public.platform_events(owner_id,source_app,source_type,source_id,title,starts_at,ends_at,all_day,status,deep_link,details)
  values(new.host_id,'fairway','planned_round',new.id::text,left('Fairway · '||new.course_name,160),new.scheduled_at,new.scheduled_at+case when new.hole_count=9 then interval '2 hours' else interval '4 hours' end,false,case when new.status='cancelled' then 'cancelled' else 'active' end,'/golf/#upcoming/'||new.id::text,'{}'::jsonb)
  on conflict(owner_id,source_app,source_type,source_id) do update set title=excluded.title,starts_at=excluded.starts_at,ends_at=excluded.ends_at,all_day=false,status=excluded.status,deep_link=excluded.deep_link,details='{}'::jsonb;
  return new;
end $$;
drop trigger if exists fairway_calendar_reference on public.fairway_round_sessions;
create trigger fairway_calendar_reference after insert or update of scheduled_at,course_name,tee_name,status,hole_count or delete on public.fairway_round_sessions for each row execute function public.fairway_publish_calendar_reference();

update public.platform_events e set ends_at=r.scheduled_at+case when r.hole_count=9 then interval '2 hours' else interval '4 hours' end
from public.fairway_round_sessions r where e.owner_id=r.host_id and e.source_app='fairway' and e.source_type='planned_round' and e.source_id=r.id::text;

drop function if exists public.daymark_fairway_events();
create function public.daymark_fairway_events()
returns table(id uuid,source_id uuid,title text,starts_at timestamptz,ends_at timestamptz,time_zone text,course text,tee text,hole_count smallint,host_name text,participant_count bigint,round_status text,deep_link text)
language sql stable security definer set search_path=pg_catalog,public
as $$
  select e.id,r.id,'Fairway · '||r.course_name,r.scheduled_at,r.scheduled_at+case when r.hole_count=9 then interval '2 hours' else interval '4 hours' end,r.time_zone,r.course_name,r.tee_name,r.hole_count,
    coalesce(nullif(h.display_name,''),nullif(h.handle,''),'Golfer'),(select count(*) from public.fairway_round_participants p where p.session_id=r.id and p.invitation_status='accepted'),r.status,'/golf/#upcoming/'||r.id::text
  from public.platform_events e join public.fairway_round_sessions r on r.id::text=e.source_id and r.host_id=e.owner_id left join public.profiles h on h.id=r.host_id
  where e.source_app='fairway' and e.source_type='planned_round' and public.platform_current_user_can_read_event(e.id) order by r.scheduled_at
$$;

revoke all on function public.fairway_create_round_session(text,timestamptz,text,text,smallint),public.fairway_update_planned_round(uuid,text,timestamptz,text,text,smallint),
  public.fairway_upsert_scorecard(uuid,uuid,smallint[],text),public.fairway_group_scorecard(uuid),public.fairway_update_round_status(uuid,text),public.fairway_planned_rounds(),public.daymark_fairway_events() from public,anon;
grant execute on function public.fairway_create_round_session(text,timestamptz,text,text,smallint),public.fairway_update_planned_round(uuid,text,timestamptz,text,text,smallint),
  public.fairway_upsert_scorecard(uuid,uuid,smallint[],text),public.fairway_group_scorecard(uuid),public.fairway_update_round_status(uuid,text),public.fairway_planned_rounds(),public.daymark_fairway_events() to authenticated;
revoke all on function public.fairway_publish_calendar_reference() from public,anon,authenticated;

commit;

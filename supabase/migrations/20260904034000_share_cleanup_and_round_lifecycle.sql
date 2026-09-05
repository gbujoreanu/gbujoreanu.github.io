begin;

create or replace function public.daymark_cleanup_item_shares()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $$ begin
  delete from public.daymark_item_shares where owner_id=old.user_id and item_type=tg_argv[0] and item_id=old.id::text;
  return old;
end $$;

drop trigger if exists daymark_task_share_cleanup on public.daymark_tasks;
create trigger daymark_task_share_cleanup after delete on public.daymark_tasks for each row execute function public.daymark_cleanup_item_shares('task');
drop trigger if exists daymark_goal_share_cleanup on public.daymark_goals;
create trigger daymark_goal_share_cleanup after delete on public.daymark_goals for each row execute function public.daymark_cleanup_item_shares('goal');
drop trigger if exists daymark_event_share_cleanup on public.daymark_events;
create trigger daymark_event_share_cleanup after delete on public.daymark_events for each row execute function public.daymark_cleanup_item_shares('event');
drop trigger if exists daymark_schedule_share_cleanup on public.daymark_schedule_entries;
create trigger daymark_schedule_share_cleanup after delete on public.daymark_schedule_entries for each row execute function public.daymark_cleanup_item_shares('schedule');

create or replace function public.fairway_update_round_status(round_session_id uuid,next_status text)
returns void language plpgsql security definer set search_path=pg_catalog,public
as $$ declare current_status text; incomplete integer; begin
  if next_status not in('in_progress','completed','cancelled') then raise exception 'invalid status'; end if;
  select status into current_status from public.fairway_round_sessions where id=round_session_id and host_id=auth.uid() for update;
  if not found then raise exception 'round unavailable'; end if;
  if current_status in('completed','cancelled') or (current_status='planned' and next_status='completed') then raise exception 'invalid transition'; end if;
  if next_status='completed' then
    select count(*) into incomplete from public.fairway_round_participants p left join public.fairway_scorecards c on c.session_id=p.session_id and c.player_id=p.user_id and c.status='final' and cardinality(c.holes)=18 where p.session_id=round_session_id and p.invitation_status='accepted' and c.id is null;
    if incomplete>0 then raise exception 'all accepted players need a final scorecard'; end if;
  end if;
  update public.fairway_round_sessions set status=next_status where id=round_session_id;
  update public.platform_events set status=case when next_status='cancelled' then 'cancelled' else 'active' end where source_app='fairway' and source_type='planned_round' and source_id=round_session_id::text;
end $$;

revoke all on function public.daymark_cleanup_item_shares(),public.fairway_update_round_status(uuid,text) from public,anon;
revoke all on function public.daymark_cleanup_item_shares() from authenticated;
grant execute on function public.fairway_update_round_status(uuid,text) to authenticated;

commit;

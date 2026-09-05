begin;

alter table public.golf_rounds add column if not exists visibility text not null default 'private'
  check (visibility in ('private','friends','followers','public'));

create or replace function public.ecosystem_household_has_user(target_household uuid, target_user uuid)
returns boolean language sql stable security definer set search_path=pg_catalog,public
as $$ select exists(select 1 from public.ecosystem_household_members where household_id=target_household and user_id=target_user) $$;

create or replace function public.platform_event_can_read(target_event uuid, target_user uuid)
returns boolean language sql stable security definer set search_path=pg_catalog,public
as $$ select exists(select 1 from public.platform_events where id=target_event and owner_id=target_user) or exists(select 1 from public.platform_event_access where event_id=target_event and user_id=target_user) $$;

create or replace function public.fairway_session_can_read(target_session uuid, target_user uuid)
returns boolean language sql stable security definer set search_path=pg_catalog,public
as $$ select exists(select 1 from public.fairway_round_sessions where id=target_session and host_id=target_user) or exists(select 1 from public.fairway_round_participants where session_id=target_session and user_id=target_user) $$;

revoke all on function public.ecosystem_household_has_user(uuid,uuid),public.platform_event_can_read(uuid,uuid),public.fairway_session_can_read(uuid,uuid) from public,anon,authenticated;

drop policy if exists households_member_select on public.ecosystem_households;
create policy households_member_select on public.ecosystem_households for select to authenticated using (public.ecosystem_household_has_user(id,(select auth.uid())));
drop policy if exists household_members_member_select on public.ecosystem_household_members;
create policy household_members_member_select on public.ecosystem_household_members for select to authenticated using (public.ecosystem_household_has_user(household_id,(select auth.uid())));
drop policy if exists platform_events_access_select on public.platform_events;
create policy platform_events_access_select on public.platform_events for select to authenticated using (public.platform_event_can_read(id,(select auth.uid())));
drop policy if exists platform_event_access_involved_select on public.platform_event_access;
create policy platform_event_access_involved_select on public.platform_event_access for select to authenticated using (user_id=(select auth.uid()) or public.platform_event_can_read(event_id,(select auth.uid())));
drop policy if exists fairway_sessions_participant_select on public.fairway_round_sessions;
create policy fairway_sessions_participant_select on public.fairway_round_sessions for select to authenticated using (public.fairway_session_can_read(id,(select auth.uid())));
drop policy if exists fairway_participants_involved_select on public.fairway_round_participants;
create policy fairway_participants_involved_select on public.fairway_round_participants for select to authenticated using (public.fairway_session_can_read(session_id,(select auth.uid())));

drop trigger if exists daymark_validate_share_trigger on public.daymark_item_shares;
create trigger daymark_validate_share_trigger before insert or update of owner_id,recipient_id,item_type,item_id on public.daymark_item_shares for each row execute function public.daymark_validate_share();

create or replace function public.ecosystem_mark_notification_read(notification_id uuid)
returns void language sql security definer set search_path=pg_catalog,public
as $$ update public.ecosystem_notifications set read_at=now() where id=notification_id and recipient_id=auth.uid() $$;

create or replace function public.ecosystem_remove_household_member(target_household uuid,target_user uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public
as $$ declare h public.ecosystem_households; begin
  select * into h from public.ecosystem_households where id=target_household; if not found then raise exception 'household unavailable'; end if;
  if auth.uid()=target_user then
    if h.owner_id=auth.uid() then raise exception 'owner must delete or transfer household'; end if;
  elsif h.owner_id<>auth.uid() then raise exception 'not allowed'; end if;
  delete from public.ecosystem_household_members where household_id=target_household and user_id=target_user and role<>'owner';
  update public.daymark_item_shares s set status='revoked',updated_at=now() where status in('pending','accepted') and ((s.owner_id=target_user and s.recipient_id in(select user_id from public.ecosystem_household_members where household_id=target_household)) or (s.recipient_id=target_user and s.owner_id in(select user_id from public.ecosystem_household_members where household_id=target_household))) and not public.ecosystem_are_friends(s.owner_id,s.recipient_id);
end $$;

create or replace function public.daymark_share_notify()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $$ begin
  insert into public.ecosystem_notifications(recipient_id,actor_id,notification_type,source_app,source_type,source_id,message)
    values(new.recipient_id,new.owner_id,'daymark_share','daymark',new.item_type,new.id::text,'shared a Daymark item with you');
  return new;
end $$;
drop trigger if exists daymark_share_notify_trigger on public.daymark_item_shares;
create trigger daymark_share_notify_trigger after insert on public.daymark_item_shares for each row execute function public.daymark_share_notify();

create or replace function public.fairway_set_round_daymark(round_session_id uuid, enabled boolean)
returns void language plpgsql security definer set search_path=pg_catalog,public
as $$ declare event_id uuid; begin
  if not exists(select 1 from public.fairway_round_participants where session_id=round_session_id and user_id=auth.uid() and invitation_status='accepted') then raise exception 'round unavailable'; end if;
  update public.fairway_round_participants set add_to_daymark=enabled where session_id=round_session_id and user_id=auth.uid();
  select id into event_id from public.platform_events where source_app='fairway' and source_type='planned_round' and source_id=round_session_id::text;
  if enabled then insert into public.platform_event_subscriptions(event_id,user_id) values(event_id,auth.uid()) on conflict do nothing;
  else delete from public.platform_event_subscriptions where platform_event_subscriptions.event_id=event_id and user_id=auth.uid(); end if;
end $$;

create or replace function public.fairway_public_profile(target_id uuid)
returns table(id uuid,display_name text,handle text,bio text,avatar_path text,rounds_played bigint,scoring_average numeric,best_score smallint,recent_rounds jsonb)
language sql stable security definer set search_path=pg_catalog,public
as $$
  with allowed as (
    select p.* from public.profiles p where p.id=target_id and p.discoverable and auth.uid() is not null and not public.ecosystem_is_blocked(auth.uid(),target_id)
  ), visible_rounds as (
    select r.* from public.golf_rounds r where r.user_id=target_id and (
      r.visibility='public' or (r.visibility='followers' and exists(select 1 from public.ecosystem_follows f where f.follower_id=auth.uid() and f.followed_id=target_id)) or (r.visibility='friends' and public.ecosystem_are_friends(auth.uid(),target_id))
    )
  )
  select p.id,p.display_name,p.handle,p.bio,p.avatar_path,count(v.id),round(avg(v.total),1),min(v.total),
    coalesce((select jsonb_agg(x) from (select jsonb_build_object('date',played_on,'course',course,'tee',tee,'score',total,'differential',differential) x from visible_rounds order by played_on desc limit 5) q),'[]'::jsonb)
  from allowed p left join visible_rounds v on true group by p.id,p.display_name,p.handle,p.bio,p.avatar_path
$$;

create or replace function public.money_sync_bill_event()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $$ declare event_id uuid; begin
  if tg_op='DELETE' then
    delete from public.platform_events where owner_id=old.user_id and source_app='money' and source_type='bill' and source_id=old.id::text;
    return old;
  end if;
  if not new.show_in_daymark or not new.active then
    delete from public.platform_events where owner_id=new.user_id and source_app='money' and source_type='bill' and source_id=new.id::text;
    return new;
  end if;
  insert into public.platform_events(owner_id,source_app,source_type,source_id,title,starts_at,all_day,deep_link,details)
    values(new.user_id,'money','bill',new.id::text,new.name,(new.next_due_date::timestamp at time zone 'UTC'),true,'/money/#bills',jsonb_build_object('kind','bill'))
    on conflict(owner_id,source_app,source_type,source_id) do update set title=excluded.title,starts_at=excluded.starts_at,status='active',updated_at=now()
    returning id into event_id;
  insert into public.platform_event_access(event_id,user_id) values(event_id,new.user_id) on conflict do nothing;
  insert into public.platform_event_subscriptions(event_id,user_id) values(event_id,new.user_id) on conflict do nothing;
  return new;
end $$;

revoke insert,delete on public.ecosystem_blocks,public.ecosystem_follows from authenticated;
revoke update on public.ecosystem_notifications,public.fairway_round_participants from authenticated;
drop policy if exists notifications_recipient_update on public.ecosystem_notifications;
drop policy if exists fairway_participant_self_update on public.fairway_round_participants;

revoke all on function public.ecosystem_mark_notification_read(uuid),public.ecosystem_remove_household_member(uuid,uuid),public.fairway_set_round_daymark(uuid,boolean),public.fairway_public_profile(uuid) from public,anon;
grant execute on function public.ecosystem_mark_notification_read(uuid),public.ecosystem_remove_household_member(uuid,uuid),public.fairway_set_round_daymark(uuid,boolean),public.fairway_public_profile(uuid) to authenticated;

commit;

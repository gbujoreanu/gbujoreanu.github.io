begin;

create or replace function public.ecosystem_current_user_household_member(target_household uuid)
returns boolean language sql stable security definer set search_path=pg_catalog,public
as $$ select auth.uid() is not null and exists(select 1 from public.ecosystem_household_members where household_id=target_household and user_id=auth.uid()) $$;

create or replace function public.platform_current_user_can_read_event(target_event uuid)
returns boolean language sql stable security definer set search_path=pg_catalog,public
as $$ select auth.uid() is not null and (exists(select 1 from public.platform_events where id=target_event and owner_id=auth.uid()) or exists(select 1 from public.platform_event_access where event_id=target_event and user_id=auth.uid())) $$;

create or replace function public.fairway_current_user_can_read_session(target_session uuid)
returns boolean language sql stable security definer set search_path=pg_catalog,public
as $$ select auth.uid() is not null and (exists(select 1 from public.fairway_round_sessions where id=target_session and host_id=auth.uid()) or exists(select 1 from public.fairway_round_participants where session_id=target_session and user_id=auth.uid())) $$;

create or replace function public.ecosystem_current_user_not_blocked(target_user uuid)
returns boolean language sql stable security definer set search_path=pg_catalog,public
as $$ select auth.uid() is not null and not public.ecosystem_is_blocked(auth.uid(),target_user) $$;

revoke all on function public.ecosystem_current_user_household_member(uuid),public.platform_current_user_can_read_event(uuid),public.fairway_current_user_can_read_session(uuid),public.ecosystem_current_user_not_blocked(uuid) from public,anon;
grant execute on function public.ecosystem_current_user_household_member(uuid),public.platform_current_user_can_read_event(uuid),public.fairway_current_user_can_read_session(uuid),public.ecosystem_current_user_not_blocked(uuid) to authenticated;

drop policy if exists households_member_select on public.ecosystem_households;
create policy households_member_select on public.ecosystem_households for select to authenticated using (public.ecosystem_current_user_household_member(id));
drop policy if exists household_members_member_select on public.ecosystem_household_members;
create policy household_members_member_select on public.ecosystem_household_members for select to authenticated using (public.ecosystem_current_user_household_member(household_id));
drop policy if exists platform_events_access_select on public.platform_events;
create policy platform_events_access_select on public.platform_events for select to authenticated using (public.platform_current_user_can_read_event(id));
drop policy if exists platform_event_access_involved_select on public.platform_event_access;
create policy platform_event_access_involved_select on public.platform_event_access for select to authenticated using (user_id=(select auth.uid()) or public.platform_current_user_can_read_event(event_id));
drop policy if exists fairway_sessions_participant_select on public.fairway_round_sessions;
create policy fairway_sessions_participant_select on public.fairway_round_sessions for select to authenticated using (public.fairway_current_user_can_read_session(id));
drop policy if exists fairway_participants_involved_select on public.fairway_round_participants;
create policy fairway_participants_involved_select on public.fairway_round_participants for select to authenticated using (public.fairway_current_user_can_read_session(session_id));

drop policy if exists avatar_authenticated_safe_select on storage.objects;
create policy avatar_authenticated_safe_select on storage.objects for select to authenticated using (
  bucket_id='avatars' and ((storage.foldername(name))[1]=(select auth.uid())::text or exists(
    select 1 from public.profiles p where p.id::text=(storage.foldername(name))[1] and p.discoverable and public.ecosystem_current_user_not_blocked(p.id)
  ))
);

commit;

begin;

create or replace function public.ecosystem_set_follow(target_id uuid,should_follow boolean)
returns void
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
begin
  if auth.uid() is null or target_id is null or target_id=auth.uid()
    or public.ecosystem_is_blocked(auth.uid(),target_id) then raise exception 'not allowed'; end if;
  if should_follow then
    if not exists(
      select 1 from public.profiles p
      where p.id=target_id and (
        p.discoverable or exists(
          select 1 from public.ecosystem_follows f
          where f.follower_id=target_id and f.followed_id=auth.uid()
        )
      )
    ) then raise exception 'profile not discoverable'; end if;
    insert into public.ecosystem_follows(follower_id,followed_id)
      values(auth.uid(),target_id) on conflict do nothing;
  else
    delete from public.ecosystem_follows where follower_id=auth.uid() and followed_id=target_id;
  end if;
end
$$;

create or replace function public.ecosystem_relationship_people(
  search_text text default '',list_mode text default 'search',result_limit integer default 50
)
returns table(
  id uuid,display_name text,handle text,bio text,avatar_path text,
  is_following boolean,is_follower boolean,is_friend boolean,
  request_direction text,request_id uuid
)
language sql stable security definer set search_path=pg_catalog,public
as $$
  with viewer as (select auth.uid() uid), query as (
    select regexp_replace(btrim(coalesce(search_text,'')),'^@','') value
  ), candidates as (
    select p.*
    from public.profiles p cross join viewer v cross join query q
    where v.uid is not null and p.id<>v.uid and not public.ecosystem_is_blocked(v.uid,p.id)
      and (
        (list_mode='search' and p.discoverable and q.value<>''
          and (p.handle ilike '%'||q.value||'%' or p.display_name ilike '%'||q.value||'%'))
        or (list_mode='friends' and public.ecosystem_are_friends(v.uid,p.id))
        or (list_mode='requests' and exists(select 1 from public.ecosystem_friend_requests r
          where r.status='pending' and ((r.sender_id=v.uid and r.recipient_id=p.id) or (r.sender_id=p.id and r.recipient_id=v.uid))))
        or (list_mode='following' and exists(select 1 from public.ecosystem_follows f where f.follower_id=v.uid and f.followed_id=p.id))
        or (list_mode='followers' and exists(select 1 from public.ecosystem_follows f where f.followed_id=v.uid and f.follower_id=p.id))
      )
  )
  select p.id,p.display_name,p.handle,p.bio,p.avatar_path,
    exists(select 1 from public.ecosystem_follows f where f.follower_id=v.uid and f.followed_id=p.id),
    exists(select 1 from public.ecosystem_follows f where f.followed_id=v.uid and f.follower_id=p.id),
    public.ecosystem_are_friends(v.uid,p.id),
    case when r.sender_id=v.uid then 'outgoing' when r.recipient_id=v.uid then 'incoming' else null end,
    r.id
  from candidates p cross join viewer v
  left join lateral (
    select request.id,request.sender_id,request.recipient_id
    from public.ecosystem_friend_requests request
    where request.status='pending' and ((request.sender_id=v.uid and request.recipient_id=p.id) or (request.sender_id=p.id and request.recipient_id=v.uid))
    limit 1
  ) r on true
  order by lower(coalesce(p.display_name,p.handle)),p.id
  limit least(greatest(result_limit,1),100)
$$;

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
    case when exists(select 1 from public.ecosystem_household_invitations i
      where i.household_id=owned.id and i.recipient_id=p.id and i.status='pending')
      then 'already_invited' else 'available' end
  from public.profiles p cross join owned cross join query q
  where auth.uid() is not null and q.value<>'' and p.id<>auth.uid() and p.discoverable
    and not public.ecosystem_is_blocked(auth.uid(),p.id)
    and (p.handle ilike '%'||q.value||'%' or p.display_name ilike '%'||q.value||'%')
    and not exists(select 1 from public.ecosystem_household_members m where m.user_id=p.id)
  order by lower(coalesce(p.display_name,p.handle)),p.id
  limit least(greatest(result_limit,1),50)
$$;

create or replace function public.ecosystem_current_user_can_view_avatar(target_user uuid)
returns boolean
language sql stable security definer set search_path=pg_catalog,public
as $$
  select auth.uid() is not null and target_user is not null and not public.ecosystem_is_blocked(auth.uid(),target_user) and (
    target_user=auth.uid()
    or exists(select 1 from public.profiles p where p.id=target_user and p.discoverable)
    or exists(select 1 from public.ecosystem_follows f where (f.follower_id=auth.uid() and f.followed_id=target_user) or (f.follower_id=target_user and f.followed_id=auth.uid()))
    or public.ecosystem_are_friends(auth.uid(),target_user)
    or exists(select 1 from public.ecosystem_friend_requests r where r.status='pending' and ((r.sender_id=auth.uid() and r.recipient_id=target_user) or (r.sender_id=target_user and r.recipient_id=auth.uid())))
    or exists(select 1 from public.ecosystem_household_members mine join public.ecosystem_household_members theirs using(household_id) where mine.user_id=auth.uid() and theirs.user_id=target_user)
    or exists(select 1 from public.ecosystem_household_invitations i where i.status='pending' and ((i.sender_id=auth.uid() and i.recipient_id=target_user) or (i.sender_id=target_user and i.recipient_id=auth.uid())))
    or exists(select 1 from public.fairway_round_participants mine join public.fairway_round_participants theirs using(session_id) join public.fairway_round_sessions s on s.id=mine.session_id where mine.user_id=auth.uid() and theirs.user_id=target_user and mine.invitation_status in('invited','accepted') and theirs.invitation_status in('invited','accepted') and s.status='planned')
  )
$$;

drop policy if exists avatar_authenticated_safe_select on storage.objects;
create policy avatar_authenticated_safe_select on storage.objects for select to authenticated using (
  bucket_id='avatars' and case
    when (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then public.ecosystem_current_user_can_view_avatar(((storage.foldername(name))[1])::uuid)
    else false end
);

revoke all on function public.ecosystem_household_candidates(text,integer),public.ecosystem_current_user_can_view_avatar(uuid) from public,anon;
grant execute on function public.ecosystem_household_candidates(text,integer),public.ecosystem_current_user_can_view_avatar(uuid) to authenticated;

commit;

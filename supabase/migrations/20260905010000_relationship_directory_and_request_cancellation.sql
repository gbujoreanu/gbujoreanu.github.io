begin;

create or replace function public.ecosystem_relationship_people(
  search_text text default '',
  list_mode text default 'search',
  result_limit integer default 50
)
returns table(
  id uuid,
  display_name text,
  handle text,
  bio text,
  avatar_path text,
  is_following boolean,
  is_follower boolean,
  is_friend boolean,
  request_direction text,
  request_id uuid
)
language sql stable security definer set search_path=pg_catalog,public
as $$
  with viewer as (select auth.uid() uid), candidates as (
    select p.*
    from public.profiles p cross join viewer v
    where v.uid is not null
      and p.id<>v.uid
      and not public.ecosystem_is_blocked(v.uid,p.id)
      and (
        (list_mode='search' and p.discoverable and btrim(coalesce(search_text,''))<>''
          and (p.handle ilike '%'||btrim(search_text)||'%' or p.display_name ilike '%'||btrim(search_text)||'%'))
        or (list_mode='friends' and public.ecosystem_are_friends(v.uid,p.id))
        or (list_mode='requests' and exists(
          select 1 from public.ecosystem_friend_requests r
          where r.status='pending' and ((r.sender_id=v.uid and r.recipient_id=p.id) or (r.sender_id=p.id and r.recipient_id=v.uid))
        ))
        or (list_mode='following' and exists(select 1 from public.ecosystem_follows f where f.follower_id=v.uid and f.followed_id=p.id))
        or (list_mode='followers' and exists(select 1 from public.ecosystem_follows f where f.followed_id=v.uid and f.follower_id=p.id))
      )
  )
  select p.id,p.display_name,p.handle,p.bio,p.avatar_path,
    exists(select 1 from public.ecosystem_follows f where f.follower_id=v.uid and f.followed_id=p.id),
    exists(select 1 from public.ecosystem_follows f where f.followed_id=v.uid and f.follower_id=p.id),
    public.ecosystem_are_friends(v.uid,p.id),
    case
      when r.sender_id=v.uid then 'outgoing'
      when r.recipient_id=v.uid then 'incoming'
      else null
    end,
    r.id
  from candidates p cross join viewer v
  left join lateral (
    select request.id,request.sender_id,request.recipient_id
    from public.ecosystem_friend_requests request
    where request.status='pending'
      and ((request.sender_id=v.uid and request.recipient_id=p.id) or (request.sender_id=p.id and request.recipient_id=v.uid))
    limit 1
  ) r on true
  order by lower(coalesce(p.display_name,p.handle)),p.id
  limit least(greatest(result_limit,1),100)
$$;

create or replace function public.ecosystem_cancel_friend_request(request_id uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public
as $$ begin
  update public.ecosystem_friend_requests
  set status='cancelled',responded_at=now()
  where id=request_id and sender_id=auth.uid() and status='pending';
  if not found then raise exception 'request unavailable'; end if;
  delete from public.ecosystem_notifications
  where notification_type='friend_request' and source_id=request_id::text and read_at is null;
end $$;

revoke all on function public.ecosystem_relationship_people(text,text,integer),public.ecosystem_cancel_friend_request(uuid) from public,anon;
grant execute on function public.ecosystem_relationship_people(text,text,integer),public.ecosystem_cancel_friend_request(uuid) to authenticated;

commit;

begin;

-- This private ledger intentionally survives profile/auth deletion. Numbers are
-- never recycled; sequence gaps (including rolled-back signups) are expected.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create sequence private.profile_number_seq as bigint start with 100 increment by 1 no cycle cache 1;
create table private.profile_numbers (
  user_id uuid primary key,
  profile_number bigint not null unique check (profile_number > 0)
);
revoke all on table private.profile_numbers from public, anon, authenticated;
revoke all on sequence private.profile_number_seq from public, anon, authenticated;
alter table private.profile_numbers enable row level security;

alter table public.profiles add column profile_number bigint;
-- New accounts are searchable by default. Do not update existing privacy choices.
alter table public.profiles alter column discoverable set default true;

create function public.account_provision_identity()
returns trigger language plpgsql security definer set search_path=pg_catalog
as $$
declare assigned bigint;
begin
  if tg_op='UPDATE' and new.id is distinct from old.id then
    raise exception 'Profile ownership cannot change' using errcode='23514';
  end if;
  select n.profile_number into assigned from private.profile_numbers n where n.user_id=new.id;
  if assigned is null then
    -- Serialize allocation with reserved-handle validation, including concurrent signups.
    perform pg_advisory_xact_lock(721604,1);
    select n.profile_number into assigned from private.profile_numbers n where n.user_id=new.id;
    if assigned is null then
      loop
        assigned := nextval('private.profile_number_seq'::regclass);
        exit when not exists(select 1 from public.profiles p where lower(p.handle)='user'||assigned::text);
      end loop;
      insert into private.profile_numbers(user_id,profile_number) values(new.id,assigned);
    end if;
  end if;
  if new.profile_number is not null and new.profile_number<>assigned then
    raise exception 'Profile number cannot change' using errcode='23514';
  end if;
  new.profile_number := assigned;
  if nullif(btrim(new.display_name),'') is null then new.display_name := 'User '||assigned::text; end if;
  if nullif(btrim(new.handle),'') is null then new.handle := 'user'||assigned::text; end if;
  if tg_op='INSERT' or new.handle is distinct from old.handle then
    if new.handle ~ '^user[0-9]+$' and new.handle<>'user'||assigned::text
      and not exists(select 1 from public.profiles p where p.id=new.id and p.handle=new.handle) then
      raise exception 'Numbered fallback handles are reserved' using errcode='23514';
    end if;
  end if;
  return new;
end $$;
revoke all on function public.account_provision_identity() from public,anon,authenticated;
create trigger profiles_provision_identity before insert or update on public.profiles
for each row execute function public.account_provision_identity();

-- Keep all chosen fields and privacy preferences; only absent identities are filled.
update public.profiles set profile_number=profile_number;
insert into public.profiles(id)
select u.id from auth.users u where not exists(select 1 from public.profiles p where p.id=u.id)
on conflict (id) do nothing;
alter table public.profiles alter column profile_number set not null;
alter table public.profiles add constraint profiles_number_key unique(profile_number);
alter table public.profiles add constraint profiles_identity_present
check (nullif(btrim(display_name),'') is not null and nullif(btrim(handle),'') is not null);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=pg_catalog
as $$ begin
  insert into public.profiles(id,display_name)
  values(new.id,case when char_length(btrim(new.raw_user_meta_data->>'display_name')) between 1 and 60
    then btrim(new.raw_user_meta_data->>'display_name') else null end)
  on conflict(id) do nothing;
  return new;
end $$;
revoke all on function public.handle_new_user() from public,anon,authenticated;
-- Reuse the established auth trigger name instead of creating duplicate provisioning.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();

create function public.account_ensure_profile()
returns void language plpgsql security definer set search_path=pg_catalog
as $$ begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode='42501'; end if;
  insert into public.profiles(id) values(auth.uid()) on conflict(id) do nothing;
end $$;
revoke all on function public.account_ensure_profile() from public,anon;
grant execute on function public.account_ensure_profile() to authenticated;

-- Both directory contexts use literal substring matching: % and _ are not
-- wildcard enumeration shortcuts. Only safe profile columns are returned.
create or replace function public.ecosystem_relationship_people(
  search_text text default '',list_mode text default 'search',result_limit integer default 50
)
returns table(id uuid,display_name text,handle text,bio text,avatar_path text,
  is_following boolean,is_follower boolean,is_friend boolean,request_direction text,request_id uuid)
language sql stable security definer set search_path=pg_catalog,public
as $$
  with viewer as (select auth.uid() uid), query as (
    select lower(btrim(regexp_replace(btrim(coalesce(search_text,'')),'^@',''))) value
  ), candidates as (
    select p.* from public.profiles p cross join viewer v cross join query q
    where v.uid is not null and p.id<>v.uid and not public.ecosystem_is_blocked(v.uid,p.id)
    and (
      (list_mode='search' and p.discoverable and char_length(q.value)>=2
        and (strpos(lower(p.handle),q.value)>0 or strpos(lower(p.display_name),q.value)>0))
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
    case when r.sender_id=v.uid then 'outgoing' when r.recipient_id=v.uid then 'incoming' else null end,r.id
  from candidates p cross join viewer v
  left join lateral (select request.id,request.sender_id,request.recipient_id
    from public.ecosystem_friend_requests request where request.status='pending'
    and ((request.sender_id=v.uid and request.recipient_id=p.id) or (request.sender_id=p.id and request.recipient_id=v.uid)) limit 1) r on true
  order by lower(coalesce(p.display_name,p.handle)),p.id limit least(greatest(result_limit,1),100)
$$;

create or replace function public.ecosystem_household_candidates(search_text text,result_limit integer default 30)
returns table(id uuid,display_name text,handle text,bio text,avatar_path text,invitation_state text)
language sql stable security definer set search_path=pg_catalog,public
as $$
  with owned as (select h.id from public.ecosystem_households h where h.owner_id=auth.uid() limit 1),
  query as (select lower(btrim(regexp_replace(btrim(coalesce(search_text,'')),'^@',''))) value)
  select p.id,p.display_name,p.handle,p.bio,p.avatar_path,
    case
      when exists(select 1 from public.ecosystem_household_members m where m.user_id=p.id and m.household_id=owned.id) then 'already_member'
      when exists(select 1 from public.ecosystem_household_invitations i where i.household_id=owned.id and i.recipient_id=p.id and i.status='pending') then 'already_invited'
      when exists(select 1 from public.ecosystem_household_members m where m.user_id=p.id) then 'unavailable'
      else 'available' end
  from public.profiles p cross join owned cross join query q
  where auth.uid() is not null and char_length(q.value)>=2 and p.id<>auth.uid() and p.discoverable
    and not public.ecosystem_is_blocked(auth.uid(),p.id)
    and (strpos(lower(p.handle),q.value)>0 or strpos(lower(p.display_name),q.value)>0)
  order by lower(coalesce(p.display_name,p.handle)),p.id limit least(greatest(result_limit,1),50)
$$;
revoke all on function public.ecosystem_relationship_people(text,text,integer),public.ecosystem_household_candidates(text,integer) from public,anon;
grant execute on function public.ecosystem_relationship_people(text,text,integer),public.ecosystem_household_candidates(text,integer) to authenticated;
commit;

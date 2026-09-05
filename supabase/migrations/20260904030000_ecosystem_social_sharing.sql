begin;

create extension if not exists pgcrypto;

create table if not exists public.ecosystem_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint ecosystem_blocks_no_self check (blocker_id <> blocked_id)
);

create table if not exists public.ecosystem_follows (
  follower_id uuid not null references auth.users(id) on delete cascade,
  followed_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followed_id),
  constraint ecosystem_follows_no_self check (follower_id <> followed_id)
);

create table if not exists public.ecosystem_friend_requests (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint ecosystem_friend_requests_no_self check (sender_id <> recipient_id)
);

create unique index if not exists ecosystem_friend_requests_one_pending_pair
  on public.ecosystem_friend_requests (least(sender_id, recipient_id), greatest(sender_id, recipient_id))
  where status = 'pending';

create table if not exists public.ecosystem_friendships (
  user_low_id uuid not null references auth.users(id) on delete cascade,
  user_high_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_low_id, user_high_id),
  constraint ecosystem_friendships_ordered check (user_low_id < user_high_id)
);

create table if not exists public.ecosystem_households (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.ecosystem_household_members (
  household_id uuid not null references public.ecosystem_households(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','member')),
  joined_at timestamptz not null default now(),
  primary key (household_id, user_id)
);

create table if not exists public.ecosystem_household_invitations (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.ecosystem_households(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint ecosystem_household_invitations_no_self check (sender_id <> recipient_id)
);

create unique index if not exists ecosystem_household_invitations_one_pending
  on public.ecosystem_household_invitations(household_id, recipient_id) where status = 'pending';

create table if not exists public.ecosystem_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  notification_type text not null check (notification_type in ('friend_request','friend_accepted','household_invite','round_invite','daymark_share')),
  source_app text not null check (source_app in ('account','daymark','fairway','money')),
  source_type text not null check (char_length(source_type) between 1 and 50),
  source_id text not null check (char_length(source_id) between 1 and 100),
  message text not null check (char_length(message) between 1 and 180),
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists ecosystem_notifications_recipient_created
  on public.ecosystem_notifications(recipient_id, created_at desc);

create table if not exists public.platform_events (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  source_app text not null check (source_app in ('daymark','fairway','money')),
  source_type text not null check (char_length(source_type) between 1 and 50),
  source_id text not null check (char_length(source_id) between 1 and 100),
  title text not null check (char_length(btrim(title)) between 1 and 160),
  starts_at timestamptz not null,
  ends_at timestamptz,
  all_day boolean not null default false,
  status text not null default 'active' check (status in ('active','cancelled')),
  deep_link text not null check (deep_link ~ '^/(tracker|golf|money)/'),
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(owner_id, source_app, source_type, source_id),
  constraint platform_events_end_after_start check (ends_at is null or ends_at > starts_at)
);

create index if not exists platform_events_owner_start on public.platform_events(owner_id, starts_at);
create index if not exists platform_events_source on public.platform_events(source_app, source_type, source_id);

create table if not exists public.platform_event_access (
  event_id uuid not null references public.platform_events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  access_level text not null default 'details' check (access_level in ('busy','details')),
  created_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

create table if not exists public.platform_event_subscriptions (
  event_id uuid not null references public.platform_events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  consumer_app text not null default 'daymark' check (consumer_app = 'daymark'),
  created_at timestamptz not null default now(),
  primary key (event_id, user_id, consumer_app)
);

create table if not exists public.daymark_item_shares (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  item_type text not null check (item_type in ('task','goal','event','schedule')),
  item_id text not null check (char_length(item_id) between 1 and 100),
  access_level text not null default 'details' check (access_level in ('busy','details')),
  status text not null default 'pending' check (status in ('pending','accepted','declined','revoked')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint daymark_item_shares_no_self check (owner_id <> recipient_id)
);

create unique index if not exists daymark_item_shares_one_active
  on public.daymark_item_shares(owner_id, recipient_id, item_type, item_id)
  where status in ('pending','accepted');

create index if not exists daymark_item_shares_recipient on public.daymark_item_shares(recipient_id, status, updated_at desc);

create table if not exists public.fairway_round_sessions (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references auth.users(id) on delete cascade,
  course_id text,
  course_name text not null check (char_length(btrim(course_name)) between 1 and 160),
  tee_name text not null check (char_length(btrim(tee_name)) between 1 and 80),
  par smallint not null check (par between 27 and 90),
  course_rating numeric(4,1) not null check (course_rating between 40 and 100),
  slope smallint not null check (slope between 55 and 155),
  scheduled_at timestamptz not null,
  time_zone text not null default 'UTC' check (char_length(time_zone) between 1 and 80),
  notes text not null default '' check (char_length(notes) <= 1000),
  status text not null default 'planned' check (status in ('planned','in_progress','completed','cancelled')),
  visibility text not null default 'private' check (visibility in ('private','friends','followers','public')),
  designated_scorer_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists fairway_round_sessions_host_date on public.fairway_round_sessions(host_id, scheduled_at desc);

create table if not exists public.fairway_round_participants (
  session_id uuid not null references public.fairway_round_sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'player' check (role in ('host','player')),
  invitation_status text not null default 'invited' check (invitation_status in ('invited','accepted','declined','removed')),
  add_to_daymark boolean not null default false,
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  primary key (session_id, user_id)
);

create index if not exists fairway_round_participants_user on public.fairway_round_participants(user_id, invitation_status);

create table if not exists public.fairway_scorecards (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null,
  player_id uuid not null,
  recorded_by uuid not null references auth.users(id) on delete restrict,
  holes smallint[] not null default '{}'::smallint[],
  front smallint,
  back smallint,
  total smallint,
  differential numeric(5,1),
  status text not null default 'draft' check (status in ('draft','final')),
  round_record_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(session_id, player_id),
  foreign key (session_id, player_id) references public.fairway_round_participants(session_id, user_id) on delete cascade,
  constraint fairway_scorecards_holes check (cardinality(holes) <= 18 and not (0 = any(holes)))
);

create index if not exists fairway_scorecards_player on public.fairway_scorecards(player_id, updated_at desc);

alter table public.money_bills add column if not exists show_in_daymark boolean not null default false;

create or replace function public.ecosystem_is_blocked(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = pg_catalog, public
as $$ select exists(select 1 from public.ecosystem_blocks where (blocker_id=a and blocked_id=b) or (blocker_id=b and blocked_id=a)) $$;

create or replace function public.ecosystem_are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = pg_catalog, public
as $$ select exists(select 1 from public.ecosystem_friendships where user_low_id=least(a,b) and user_high_id=greatest(a,b)) $$;

create or replace function public.ecosystem_share_eligible(owner uuid, recipient uuid)
returns boolean language sql stable security definer set search_path = pg_catalog, public
as $$
  select not public.ecosystem_is_blocked(owner,recipient) and (
    public.ecosystem_are_friends(owner,recipient) or exists(
      select 1 from public.ecosystem_household_members a
      join public.ecosystem_household_members b on b.household_id=a.household_id
      where a.user_id=owner and b.user_id=recipient
    )
  )
$$;

revoke all on function public.ecosystem_is_blocked(uuid,uuid) from public, anon, authenticated;
revoke all on function public.ecosystem_are_friends(uuid,uuid) from public, anon, authenticated;
revoke all on function public.ecosystem_share_eligible(uuid,uuid) from public, anon, authenticated;

create or replace function public.ecosystem_safe_people(search_text text default '', result_limit integer default 30)
returns table(id uuid, display_name text, handle text, bio text, avatar_path text, relation text, request_id uuid)
language sql stable security definer set search_path = pg_catalog, public
as $$
  with viewer as (select auth.uid() uid), visible as (
    select p.* from public.profiles p, viewer v
    where v.uid is not null and p.id<>v.uid and p.discoverable
      and not public.ecosystem_is_blocked(v.uid,p.id)
      and (coalesce(search_text,'')='' or p.handle ilike '%'||search_text||'%' or p.display_name ilike '%'||search_text||'%')
  )
  select p.id,p.display_name,p.handle,p.bio,p.avatar_path,
    case
      when public.ecosystem_are_friends(v.uid,p.id) then 'friend'
      when exists(select 1 from public.ecosystem_friend_requests r where r.sender_id=v.uid and r.recipient_id=p.id and r.status='pending') then 'request_sent'
      when exists(select 1 from public.ecosystem_friend_requests r where r.sender_id=p.id and r.recipient_id=v.uid and r.status='pending') then 'request_received'
      when exists(select 1 from public.ecosystem_follows f where f.follower_id=v.uid and f.followed_id=p.id) then 'following'
      else 'none' end,
    (select r.id from public.ecosystem_friend_requests r where r.status='pending' and ((r.sender_id=v.uid and r.recipient_id=p.id) or (r.sender_id=p.id and r.recipient_id=v.uid)) limit 1)
  from visible p cross join viewer v order by lower(coalesce(p.display_name,p.handle)),p.id limit least(greatest(result_limit,1),50)
$$;

create or replace function public.ecosystem_connection_people()
returns table(id uuid, display_name text, handle text, bio text, avatar_path text, relation text, request_id uuid)
language sql stable security definer set search_path = pg_catalog, public
as $$
  with viewer as (select auth.uid() uid), ids as (
    select followed_id id from public.ecosystem_follows,viewer where follower_id=viewer.uid
    union select follower_id from public.ecosystem_follows,viewer where followed_id=viewer.uid
    union select sender_id from public.ecosystem_friend_requests,viewer where recipient_id=viewer.uid and status='pending'
    union select recipient_id from public.ecosystem_friend_requests,viewer where sender_id=viewer.uid and status='pending'
    union select case when user_low_id=viewer.uid then user_high_id else user_low_id end from public.ecosystem_friendships,viewer where viewer.uid in(user_low_id,user_high_id)
  )
  select p.id,p.display_name,p.handle,p.bio,p.avatar_path,
    case
      when public.ecosystem_are_friends(v.uid,p.id) then 'friend'
      when exists(select 1 from public.ecosystem_friend_requests r where r.sender_id=v.uid and r.recipient_id=p.id and r.status='pending') then 'request_sent'
      when exists(select 1 from public.ecosystem_friend_requests r where r.sender_id=p.id and r.recipient_id=v.uid and r.status='pending') then 'request_received'
      when exists(select 1 from public.ecosystem_follows f where f.follower_id=v.uid and f.followed_id=p.id) then 'following'
      else 'follower' end,
    (select r.id from public.ecosystem_friend_requests r where r.status='pending' and ((r.sender_id=v.uid and r.recipient_id=p.id) or (r.sender_id=p.id and r.recipient_id=v.uid)) limit 1)
  from ids join public.profiles p using(id) cross join viewer v
  where not public.ecosystem_is_blocked(v.uid,p.id)
  order by lower(coalesce(p.display_name,p.handle)),p.id
$$;

create or replace function public.ecosystem_set_follow(target_id uuid, should_follow boolean)
returns void language plpgsql security definer set search_path = pg_catalog, public
as $$ begin
  if auth.uid() is null or target_id=auth.uid() or public.ecosystem_is_blocked(auth.uid(),target_id) then raise exception 'not allowed'; end if;
  if should_follow then
    if not exists(select 1 from public.profiles where id=target_id and discoverable) then raise exception 'profile not discoverable'; end if;
    insert into public.ecosystem_follows(follower_id,followed_id) values(auth.uid(),target_id) on conflict do nothing;
  else delete from public.ecosystem_follows where follower_id=auth.uid() and followed_id=target_id; end if;
end $$;

create or replace function public.ecosystem_send_friend_request(target_id uuid)
returns uuid language plpgsql security definer set search_path = pg_catalog, public
as $$ declare request_id uuid; begin
  if auth.uid() is null or target_id=auth.uid() or public.ecosystem_is_blocked(auth.uid(),target_id) then raise exception 'not allowed'; end if;
  if not exists(select 1 from public.profiles where id=target_id and discoverable) then raise exception 'profile not discoverable'; end if;
  if public.ecosystem_are_friends(auth.uid(),target_id) then raise exception 'already friends'; end if;
  insert into public.ecosystem_friend_requests(sender_id,recipient_id) values(auth.uid(),target_id) returning id into request_id;
  insert into public.ecosystem_notifications(recipient_id,actor_id,notification_type,source_app,source_type,source_id,message)
    values(target_id,auth.uid(),'friend_request','account','friend_request',request_id::text,'sent you a friend request');
  return request_id;
end $$;

create or replace function public.ecosystem_respond_friend_request(request_id uuid, response text)
returns void language plpgsql security definer set search_path = pg_catalog, public
as $$ declare req public.ecosystem_friend_requests; begin
  if response not in ('accepted','declined') then raise exception 'invalid response'; end if;
  select * into req from public.ecosystem_friend_requests where id=request_id and recipient_id=auth.uid() and status='pending' for update;
  if not found or public.ecosystem_is_blocked(req.sender_id,req.recipient_id) then raise exception 'request unavailable'; end if;
  update public.ecosystem_friend_requests set status=response,responded_at=now() where id=request_id;
  if response='accepted' then
    insert into public.ecosystem_friendships(user_low_id,user_high_id) values(least(req.sender_id,req.recipient_id),greatest(req.sender_id,req.recipient_id)) on conflict do nothing;
    insert into public.ecosystem_notifications(recipient_id,actor_id,notification_type,source_app,source_type,source_id,message)
      values(req.sender_id,auth.uid(),'friend_accepted','account','friend_request',request_id::text,'accepted your friend request');
  end if;
end $$;

create or replace function public.ecosystem_remove_friend(target_id uuid)
returns void language sql security definer set search_path = pg_catalog, public
as $$ delete from public.ecosystem_friendships where user_low_id=least(auth.uid(),target_id) and user_high_id=greatest(auth.uid(),target_id) $$;

create or replace function public.ecosystem_block_user(target_id uuid)
returns void language plpgsql security definer set search_path = pg_catalog, public
as $$ begin
  if auth.uid() is null or target_id=auth.uid() then raise exception 'not allowed'; end if;
  insert into public.ecosystem_blocks(blocker_id,blocked_id) values(auth.uid(),target_id) on conflict do nothing;
  delete from public.ecosystem_follows where (follower_id=auth.uid() and followed_id=target_id) or (follower_id=target_id and followed_id=auth.uid());
  delete from public.ecosystem_friend_requests where status='pending' and ((sender_id=auth.uid() and recipient_id=target_id) or (sender_id=target_id and recipient_id=auth.uid()));
  delete from public.ecosystem_friendships where user_low_id=least(auth.uid(),target_id) and user_high_id=greatest(auth.uid(),target_id);
  update public.daymark_item_shares set status='revoked',updated_at=now() where status in('pending','accepted') and ((owner_id=auth.uid() and recipient_id=target_id) or (owner_id=target_id and recipient_id=auth.uid()));
  update public.fairway_round_participants p set invitation_status='removed',responded_at=now() from public.fairway_round_sessions s where p.session_id=s.id and p.user_id in(auth.uid(),target_id) and s.host_id in(auth.uid(),target_id) and p.role<>'host';
end $$;

create or replace function public.ecosystem_unblock_user(target_id uuid)
returns void language sql security definer set search_path = pg_catalog, public
as $$ delete from public.ecosystem_blocks where blocker_id=auth.uid() and blocked_id=target_id $$;

create or replace function public.ecosystem_create_household(household_name text)
returns uuid language plpgsql security definer set search_path = pg_catalog, public
as $$ declare new_id uuid; begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  insert into public.ecosystem_households(owner_id,name) values(auth.uid(),btrim(household_name)) returning id into new_id;
  insert into public.ecosystem_household_members(household_id,user_id,role) values(new_id,auth.uid(),'owner'); return new_id;
end $$;

create or replace function public.ecosystem_invite_household(household uuid, target_id uuid)
returns uuid language plpgsql security definer set search_path = pg_catalog, public
as $$ declare invitation_id uuid; begin
  if not exists(select 1 from public.ecosystem_households where id=household and owner_id=auth.uid()) or public.ecosystem_is_blocked(auth.uid(),target_id) then raise exception 'not allowed'; end if;
  insert into public.ecosystem_household_invitations(household_id,sender_id,recipient_id) values(household,auth.uid(),target_id) returning id into invitation_id;
  insert into public.ecosystem_notifications(recipient_id,actor_id,notification_type,source_app,source_type,source_id,message)
    values(target_id,auth.uid(),'household_invite','account','household_invite',invitation_id::text,'invited you to a family household');
  return invitation_id;
end $$;

create or replace function public.ecosystem_respond_household_invite(invitation_id uuid, response text)
returns void language plpgsql security definer set search_path = pg_catalog, public
as $$ declare invite public.ecosystem_household_invitations; begin
  if response not in ('accepted','declined') then raise exception 'invalid response'; end if;
  select * into invite from public.ecosystem_household_invitations where id=invitation_id and recipient_id=auth.uid() and status='pending' for update;
  if not found or public.ecosystem_is_blocked(invite.sender_id,invite.recipient_id) then raise exception 'invitation unavailable'; end if;
  update public.ecosystem_household_invitations set status=response,responded_at=now() where id=invitation_id;
  if response='accepted' then insert into public.ecosystem_household_members(household_id,user_id) values(invite.household_id,auth.uid()) on conflict do nothing; end if;
end $$;

create or replace function public.ecosystem_household_summary()
returns table(household_id uuid, household_name text, owner_id uuid, member_id uuid, display_name text, handle text, avatar_path text, role text)
language sql stable security definer set search_path = pg_catalog, public
as $$
  select h.id,h.name,h.owner_id,m.user_id,p.display_name,p.handle,p.avatar_path,m.role
  from public.ecosystem_household_members mine
  join public.ecosystem_households h on h.id=mine.household_id
  join public.ecosystem_household_members m on m.household_id=h.id
  join public.profiles p on p.id=m.user_id
  where mine.user_id=auth.uid() order by h.created_at,m.role desc,lower(coalesce(p.display_name,p.handle))
$$;

create or replace function public.daymark_validate_share()
returns trigger language plpgsql security definer set search_path = pg_catalog, public
as $$ begin
  if new.owner_id<>auth.uid() or not public.ecosystem_share_eligible(new.owner_id,new.recipient_id) then raise exception 'sharing not allowed'; end if;
  if (new.item_type='task' and not exists(select 1 from public.daymark_tasks where id=new.item_id and user_id=new.owner_id))
    or (new.item_type='goal' and not exists(select 1 from public.daymark_goals where id=new.item_id and user_id=new.owner_id))
    or (new.item_type='event' and not exists(select 1 from public.daymark_events where id=new.item_id and user_id=new.owner_id))
    or (new.item_type='schedule' and not exists(select 1 from public.daymark_schedule_entries where id::text=new.item_id and user_id=new.owner_id)) then raise exception 'item unavailable'; end if;
  return new;
end $$;

drop trigger if exists daymark_validate_share_trigger on public.daymark_item_shares;
create trigger daymark_validate_share_trigger before insert on public.daymark_item_shares for each row execute function public.daymark_validate_share();

create or replace function public.daymark_respond_share(share_id uuid, response text)
returns void language plpgsql security definer set search_path = pg_catalog, public
as $$ begin
  if response not in ('accepted','declined') then raise exception 'invalid response'; end if;
  update public.daymark_item_shares set status=response,responded_at=now(),updated_at=now()
    where id=share_id and recipient_id=auth.uid() and status='pending';
  if not found then raise exception 'share unavailable'; end if;
end $$;

create or replace function public.daymark_shared_items()
returns table(share_id uuid, owner_id uuid, owner_name text, owner_handle text, item_type text, item_id text, access_level text, status text, title text, notes text, item_date date, item_time time, starts_at timestamptz, ends_at timestamptz, deep_link text)
language plpgsql stable security definer set search_path = pg_catalog, public
as $$ begin
  return query
  select s.id,s.owner_id,coalesce(p.display_name,'Someone'),p.handle,s.item_type,s.item_id,s.access_level,s.status,
    case when s.access_level='busy' then 'Busy' else coalesce(t.title,g.title,e.title,se.title) end,
    case when s.access_level='busy' then '' else coalesce(t.notes,g.notes,e.notes,se.notes,'') end,
    coalesce(t.due_date,g.target_date,e.event_date,(se.starts_at at time zone se.time_zone)::date),
    coalesce(t.due_time,e.event_time,(se.starts_at at time zone se.time_zone)::time),se.starts_at,se.ends_at,
    '/tracker/#'||case when s.item_type='schedule' then 'scheduler/'||coalesce((se.starts_at at time zone se.time_zone)::date::text,'') else 'calendar' end
  from public.daymark_item_shares s join public.profiles p on p.id=s.owner_id
  left join public.daymark_tasks t on s.item_type='task' and t.user_id=s.owner_id and t.id=s.item_id
  left join public.daymark_goals g on s.item_type='goal' and g.user_id=s.owner_id and g.id=s.item_id
  left join public.daymark_events e on s.item_type='event' and e.user_id=s.owner_id and e.id=s.item_id
  left join public.daymark_schedule_entries se on s.item_type='schedule' and se.user_id=s.owner_id and se.id::text=s.item_id
  where s.recipient_id=auth.uid() and s.status in('pending','accepted') and not public.ecosystem_is_blocked(s.owner_id,s.recipient_id);
end $$;

create or replace function public.fairway_create_round_session(course_row_id text, play_at timestamptz, zone text, note_text text default '')
returns uuid language plpgsql security definer set search_path = pg_catalog, public
as $$ declare c public.golf_courses; session_id uuid; event_id uuid; begin
  select * into c from public.golf_courses where id=course_row_id and user_id=auth.uid(); if not found then raise exception 'course unavailable'; end if;
  insert into public.fairway_round_sessions(host_id,course_id,course_name,tee_name,par,course_rating,slope,scheduled_at,time_zone,notes,designated_scorer_id)
    values(auth.uid(),c.id,c.course,c.tee,c.par,c.rating,c.slope,play_at,coalesce(nullif(zone,''),'UTC'),coalesce(note_text,''),auth.uid()) returning id into session_id;
  insert into public.fairway_round_participants(session_id,user_id,role,invitation_status,responded_at) values(session_id,auth.uid(),'host','accepted',now());
  insert into public.platform_events(owner_id,source_app,source_type,source_id,title,starts_at,ends_at,deep_link,details)
    values(auth.uid(),'fairway','planned_round',session_id::text,c.course,play_at,play_at+interval '4 hours','/golf/#friends',jsonb_build_object('tee',c.tee)) returning id into event_id;
  insert into public.platform_event_access(event_id,user_id) values(event_id,auth.uid());
  return session_id;
end $$;

create or replace function public.fairway_invite_player(round_session_id uuid, target_id uuid)
returns void language plpgsql security definer set search_path = pg_catalog, public
as $$ declare s public.fairway_round_sessions; begin
  select * into s from public.fairway_round_sessions where id=round_session_id and host_id=auth.uid() and status='planned'; if not found then raise exception 'round unavailable'; end if;
  if not public.ecosystem_are_friends(auth.uid(),target_id) or public.ecosystem_is_blocked(auth.uid(),target_id) then raise exception 'friend unavailable'; end if;
  insert into public.fairway_round_participants(session_id,user_id) values(round_session_id,target_id)
    on conflict(session_id,user_id) do update set invitation_status='invited',responded_at=null;
  insert into public.platform_event_access(event_id,user_id) select id,target_id from public.platform_events where owner_id=auth.uid() and source_app='fairway' and source_id=round_session_id::text on conflict do nothing;
  insert into public.ecosystem_notifications(recipient_id,actor_id,notification_type,source_app,source_type,source_id,message)
    values(target_id,auth.uid(),'round_invite','fairway','planned_round',round_session_id::text,'invited you to a golf round');
end $$;

create or replace function public.fairway_respond_round(round_session_id uuid, response text, add_calendar boolean default false)
returns void language plpgsql security definer set search_path = pg_catalog, public
as $$ declare event_id uuid; begin
  if response not in ('accepted','declined') then raise exception 'invalid response'; end if;
  update public.fairway_round_participants set invitation_status=response,add_to_daymark=(response='accepted' and add_calendar),responded_at=now()
    where session_id=round_session_id and user_id=auth.uid() and invitation_status='invited'; if not found then raise exception 'invitation unavailable'; end if;
  select id into event_id from public.platform_events where source_app='fairway' and source_type='planned_round' and source_id=round_session_id::text;
  if response='accepted' and add_calendar then insert into public.platform_event_subscriptions(event_id,user_id) values(event_id,auth.uid()) on conflict do nothing;
  else delete from public.platform_event_subscriptions where platform_event_subscriptions.event_id=event_id and user_id=auth.uid(); end if;
end $$;

create or replace function public.fairway_upsert_scorecard(round_session_id uuid, scorecard_player uuid, scores smallint[], card_status text default 'draft')
returns uuid language plpgsql security definer set search_path = pg_catalog, public
as $$ declare s public.fairway_round_sessions; allowed boolean; scorecard_id uuid; front_total int; back_total int; total_score int; diff numeric; begin
  select * into s from public.fairway_round_sessions where id=round_session_id and status in('planned','in_progress'); if not found then raise exception 'round unavailable'; end if;
  allowed := scorecard_player=auth.uid() or s.host_id=auth.uid() or s.designated_scorer_id=auth.uid();
  if not allowed or not exists(select 1 from public.fairway_round_participants where session_id=round_session_id and user_id=scorecard_player and invitation_status='accepted') then raise exception 'not allowed'; end if;
  if cardinality(scores)>18 or exists(select 1 from unnest(scores) n where n<1 or n>20) then raise exception 'invalid scores'; end if;
  select sum(n)::int into front_total from unnest(scores[1:least(cardinality(scores),9)]) n;
  if cardinality(scores)>9 then select sum(n)::int into back_total from unnest(scores[10:18]) n; end if;
  total_score=coalesce(front_total,0)+coalesce(back_total,0); if cardinality(scores)=18 then diff=round((total_score-s.course_rating)*113/s.slope,1); end if;
  insert into public.fairway_scorecards(session_id,player_id,recorded_by,holes,front,back,total,differential,status)
    values(round_session_id,scorecard_player,auth.uid(),scores,front_total,back_total,case when cardinality(scores)>0 then total_score end,diff,card_status)
    on conflict(session_id,player_id) do update set recorded_by=auth.uid(),holes=excluded.holes,front=excluded.front,back=excluded.back,total=excluded.total,differential=excluded.differential,status=excluded.status,updated_at=now()
    returning id into scorecard_id; return scorecard_id;
end $$;

create or replace function public.fairway_social_rounds()
returns table(session_id uuid,host_id uuid,host_name text,host_handle text,course_name text,tee_name text,par smallint,course_rating numeric,slope smallint,scheduled_at timestamptz,time_zone text,notes text,status text,visibility text,participant_status text,add_to_daymark boolean)
language sql stable security definer set search_path = pg_catalog, public
as $$
  select s.id,s.host_id,coalesce(p.display_name,'Golfer'),p.handle,s.course_name,s.tee_name,s.par,s.course_rating,s.slope,s.scheduled_at,s.time_zone,
    case when rp.invitation_status='accepted' then s.notes else '' end,s.status,s.visibility,rp.invitation_status,rp.add_to_daymark
  from public.fairway_round_sessions s join public.fairway_round_participants rp on rp.session_id=s.id and rp.user_id=auth.uid()
  join public.profiles p on p.id=s.host_id where not public.ecosystem_is_blocked(s.host_id,auth.uid())
  order by s.scheduled_at desc
$$;

create or replace function public.platform_daymark_events()
returns table(id uuid,title text,starts_at timestamptz,ends_at timestamptz,all_day boolean,status text,source_app text,source_type text,source_id text,deep_link text,access_level text)
language sql stable security definer set search_path = pg_catalog, public
as $$
  select e.id,case when a.access_level='busy' then 'Busy' else e.title end,e.starts_at,e.ends_at,e.all_day,e.status,e.source_app,e.source_type,e.source_id,e.deep_link,a.access_level
  from public.platform_event_subscriptions s join public.platform_events e on e.id=s.event_id join public.platform_event_access a on a.event_id=e.id and a.user_id=s.user_id
  where s.user_id=auth.uid() and s.consumer_app='daymark' and e.status='active' and not public.ecosystem_is_blocked(e.owner_id,s.user_id)
$$;

create or replace function public.money_sync_bill_event()
returns trigger language plpgsql security definer set search_path = pg_catalog, public
as $$ declare event_id uuid; begin
  if tg_op='DELETE' or not new.show_in_daymark or not new.active then
    delete from public.platform_events where owner_id=coalesce(new.user_id,old.user_id) and source_app='money' and source_type='bill' and source_id=coalesce(new.id,old.id)::text;
    return coalesce(new,old);
  end if;
  insert into public.platform_events(owner_id,source_app,source_type,source_id,title,starts_at,all_day,deep_link,details)
    values(new.user_id,'money','bill',new.id::text,new.name,(new.next_due_date::timestamp at time zone 'UTC'),true,'/money/#bills',jsonb_build_object('kind','bill'))
    on conflict(owner_id,source_app,source_type,source_id) do update set title=excluded.title,starts_at=excluded.starts_at,status='active',updated_at=now()
    returning id into event_id;
  insert into public.platform_event_access(event_id,user_id) values(event_id,new.user_id) on conflict do nothing;
  insert into public.platform_event_subscriptions(event_id,user_id) values(event_id,new.user_id) on conflict do nothing;
  return new;
end $$;

drop trigger if exists money_sync_bill_event_trigger on public.money_bills;
create trigger money_sync_bill_event_trigger after insert or update or delete on public.money_bills for each row execute function public.money_sync_bill_event();

create or replace function public.ecosystem_touch_updated_at()
returns trigger language plpgsql set search_path = pg_catalog, public as $$ begin new.updated_at=now(); return new; end $$;

drop trigger if exists ecosystem_households_touch on public.ecosystem_households;
create trigger ecosystem_households_touch before update on public.ecosystem_households for each row execute function public.ecosystem_touch_updated_at();
drop trigger if exists platform_events_touch on public.platform_events;
create trigger platform_events_touch before update on public.platform_events for each row execute function public.ecosystem_touch_updated_at();
drop trigger if exists daymark_item_shares_touch on public.daymark_item_shares;
create trigger daymark_item_shares_touch before update on public.daymark_item_shares for each row execute function public.ecosystem_touch_updated_at();
drop trigger if exists fairway_round_sessions_touch on public.fairway_round_sessions;
create trigger fairway_round_sessions_touch before update on public.fairway_round_sessions for each row execute function public.ecosystem_touch_updated_at();
drop trigger if exists fairway_scorecards_touch on public.fairway_scorecards;
create trigger fairway_scorecards_touch before update on public.fairway_scorecards for each row execute function public.ecosystem_touch_updated_at();

alter table public.ecosystem_blocks enable row level security;
alter table public.ecosystem_follows enable row level security;
alter table public.ecosystem_friend_requests enable row level security;
alter table public.ecosystem_friendships enable row level security;
alter table public.ecosystem_households enable row level security;
alter table public.ecosystem_household_members enable row level security;
alter table public.ecosystem_household_invitations enable row level security;
alter table public.ecosystem_notifications enable row level security;
alter table public.platform_events enable row level security;
alter table public.platform_event_access enable row level security;
alter table public.platform_event_subscriptions enable row level security;
alter table public.daymark_item_shares enable row level security;
alter table public.fairway_round_sessions enable row level security;
alter table public.fairway_round_participants enable row level security;
alter table public.fairway_scorecards enable row level security;

alter table public.ecosystem_blocks force row level security;
alter table public.ecosystem_follows force row level security;
alter table public.ecosystem_friend_requests force row level security;
alter table public.ecosystem_friendships force row level security;
alter table public.ecosystem_households force row level security;
alter table public.ecosystem_household_members force row level security;
alter table public.ecosystem_household_invitations force row level security;
alter table public.ecosystem_notifications force row level security;
alter table public.platform_events force row level security;
alter table public.platform_event_access force row level security;
alter table public.platform_event_subscriptions force row level security;
alter table public.daymark_item_shares force row level security;
alter table public.fairway_round_sessions force row level security;
alter table public.fairway_round_participants force row level security;
alter table public.fairway_scorecards force row level security;

revoke all on table public.ecosystem_blocks,public.ecosystem_follows,public.ecosystem_friend_requests,public.ecosystem_friendships,public.ecosystem_households,public.ecosystem_household_members,public.ecosystem_household_invitations,public.ecosystem_notifications,public.platform_events,public.platform_event_access,public.platform_event_subscriptions,public.daymark_item_shares,public.fairway_round_sessions,public.fairway_round_participants,public.fairway_scorecards from anon;
grant select on table public.ecosystem_blocks,public.ecosystem_follows,public.ecosystem_friend_requests,public.ecosystem_friendships,public.ecosystem_households,public.ecosystem_household_members,public.ecosystem_household_invitations,public.ecosystem_notifications,public.platform_events,public.platform_event_access,public.platform_event_subscriptions,public.daymark_item_shares,public.fairway_round_sessions,public.fairway_round_participants,public.fairway_scorecards to authenticated;
grant insert,delete on table public.ecosystem_blocks,public.ecosystem_follows to authenticated;
grant update on table public.ecosystem_notifications to authenticated;
grant insert,update,delete on table public.daymark_item_shares to authenticated;
grant update on table public.fairway_round_sessions,public.fairway_round_participants to authenticated;

create policy blocks_owner_all on public.ecosystem_blocks for all to authenticated using ((select auth.uid())=blocker_id) with check ((select auth.uid())=blocker_id);
create policy follows_involved_select on public.ecosystem_follows for select to authenticated using ((select auth.uid()) in(follower_id,followed_id));
create policy follows_owner_insert on public.ecosystem_follows for insert to authenticated with check ((select auth.uid())=follower_id and follower_id<>followed_id and not public.ecosystem_is_blocked(follower_id,followed_id));
create policy follows_owner_delete on public.ecosystem_follows for delete to authenticated using ((select auth.uid())=follower_id);
create policy friend_requests_involved_select on public.ecosystem_friend_requests for select to authenticated using ((select auth.uid()) in(sender_id,recipient_id));
create policy friendships_involved_select on public.ecosystem_friendships for select to authenticated using ((select auth.uid()) in(user_low_id,user_high_id));
create policy households_member_select on public.ecosystem_households for select to authenticated using (exists(select 1 from public.ecosystem_household_members m where m.household_id=id and m.user_id=(select auth.uid())));
create policy household_members_member_select on public.ecosystem_household_members for select to authenticated using (exists(select 1 from public.ecosystem_household_members mine where mine.household_id=household_id and mine.user_id=(select auth.uid())));
create policy household_invites_involved_select on public.ecosystem_household_invitations for select to authenticated using ((select auth.uid()) in(sender_id,recipient_id));
create policy notifications_recipient_select on public.ecosystem_notifications for select to authenticated using ((select auth.uid())=recipient_id);
create policy notifications_recipient_update on public.ecosystem_notifications for update to authenticated using ((select auth.uid())=recipient_id) with check ((select auth.uid())=recipient_id);
create policy platform_events_access_select on public.platform_events for select to authenticated using (owner_id=(select auth.uid()) or exists(select 1 from public.platform_event_access a where a.event_id=id and a.user_id=(select auth.uid())));
create policy platform_event_access_involved_select on public.platform_event_access for select to authenticated using (user_id=(select auth.uid()) or exists(select 1 from public.platform_events e where e.id=event_id and e.owner_id=(select auth.uid())));
create policy platform_subscriptions_owner_select on public.platform_event_subscriptions for select to authenticated using (user_id=(select auth.uid()));
create policy daymark_shares_involved_select on public.daymark_item_shares for select to authenticated using ((select auth.uid()) in(owner_id,recipient_id));
create policy daymark_shares_owner_insert on public.daymark_item_shares for insert to authenticated with check ((select auth.uid())=owner_id);
create policy daymark_shares_owner_update on public.daymark_item_shares for update to authenticated using ((select auth.uid())=owner_id) with check ((select auth.uid())=owner_id);
create policy daymark_shares_owner_delete on public.daymark_item_shares for delete to authenticated using ((select auth.uid())=owner_id);
create policy fairway_sessions_participant_select on public.fairway_round_sessions for select to authenticated using (host_id=(select auth.uid()) or exists(select 1 from public.fairway_round_participants p where p.session_id=id and p.user_id=(select auth.uid())));
create policy fairway_sessions_host_update on public.fairway_round_sessions for update to authenticated using (host_id=(select auth.uid())) with check (host_id=(select auth.uid()));
create policy fairway_participants_involved_select on public.fairway_round_participants for select to authenticated using (user_id=(select auth.uid()) or exists(select 1 from public.fairway_round_sessions s where s.id=session_id and s.host_id=(select auth.uid())));
create policy fairway_participant_self_update on public.fairway_round_participants for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy fairway_scorecards_participant_select on public.fairway_scorecards for select to authenticated using (exists(select 1 from public.fairway_round_participants p where p.session_id=fairway_scorecards.session_id and p.user_id=(select auth.uid())));

drop policy if exists avatar_owner_select on storage.objects;
create policy avatar_authenticated_safe_select on storage.objects for select to authenticated using (
  bucket_id='avatars' and (
    (storage.foldername(name))[1]=(select auth.uid())::text or exists(
      select 1 from public.profiles p where p.id::text=(storage.foldername(name))[1] and p.discoverable and not public.ecosystem_is_blocked((select auth.uid()),p.id)
    )
  )
);

revoke all on function public.ecosystem_safe_people(text,integer),public.ecosystem_connection_people(),public.ecosystem_set_follow(uuid,boolean),public.ecosystem_send_friend_request(uuid),public.ecosystem_respond_friend_request(uuid,text),public.ecosystem_remove_friend(uuid),public.ecosystem_block_user(uuid),public.ecosystem_unblock_user(uuid),public.ecosystem_create_household(text),public.ecosystem_invite_household(uuid,uuid),public.ecosystem_respond_household_invite(uuid,text),public.ecosystem_household_summary(),public.daymark_respond_share(uuid,text),public.daymark_shared_items(),public.fairway_create_round_session(text,timestamptz,text,text),public.fairway_invite_player(uuid,uuid),public.fairway_respond_round(uuid,text,boolean),public.fairway_upsert_scorecard(uuid,uuid,smallint[],text),public.fairway_social_rounds(),public.platform_daymark_events() from public,anon;
grant execute on function public.ecosystem_safe_people(text,integer),public.ecosystem_connection_people(),public.ecosystem_set_follow(uuid,boolean),public.ecosystem_send_friend_request(uuid),public.ecosystem_respond_friend_request(uuid,text),public.ecosystem_remove_friend(uuid),public.ecosystem_block_user(uuid),public.ecosystem_unblock_user(uuid),public.ecosystem_create_household(text),public.ecosystem_invite_household(uuid,uuid),public.ecosystem_respond_household_invite(uuid,text),public.ecosystem_household_summary(),public.daymark_respond_share(uuid,text),public.daymark_shared_items(),public.fairway_create_round_session(text,timestamptz,text,text),public.fairway_invite_player(uuid,uuid),public.fairway_respond_round(uuid,text,boolean),public.fairway_upsert_scorecard(uuid,uuid,smallint[],text),public.fairway_social_rounds(),public.platform_daymark_events() to authenticated;

commit;

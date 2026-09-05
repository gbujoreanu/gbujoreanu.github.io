begin;

-- A person belongs to at most one household in the first household model.
create unique index if not exists ecosystem_household_members_one_household
  on public.ecosystem_household_members(user_id);

create unique index if not exists ecosystem_household_members_one_owner
  on public.ecosystem_household_members(household_id)
  where role = 'owner';

create index if not exists ecosystem_household_invitations_recipient_status
  on public.ecosystem_household_invitations(recipient_id,status,created_at desc);

create index if not exists ecosystem_household_invitations_sender_status
  on public.ecosystem_household_invitations(sender_id,status,created_at desc);

create or replace function public.ecosystem_create_household(household_name text)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  new_id uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if char_length(btrim(coalesce(household_name,''))) not between 1 and 80 then
    raise exception 'household name must be between 1 and 80 characters';
  end if;
  if exists(select 1 from public.ecosystem_household_members where user_id=auth.uid()) then
    raise exception 'already belongs to a household';
  end if;

  insert into public.ecosystem_households(owner_id,name)
  values(auth.uid(),btrim(household_name))
  returning id into new_id;

  insert into public.ecosystem_household_members(household_id,user_id,role)
  values(new_id,auth.uid(),'owner');
  return new_id;
end
$$;

create or replace function public.ecosystem_invite_household(household uuid,target_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  invitation_id uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if target_id is null or target_id=auth.uid() then raise exception 'cannot invite yourself'; end if;
  if not exists(select 1 from public.ecosystem_households h where h.id=household and h.owner_id=auth.uid()) then
    raise exception 'household unavailable';
  end if;
  if not exists(select 1 from public.profiles p where p.id=target_id and p.discoverable) then
    raise exception 'profile unavailable';
  end if;
  if public.ecosystem_is_blocked(auth.uid(),target_id) then raise exception 'invitation blocked'; end if;
  if exists(select 1 from public.ecosystem_household_members m where m.user_id=target_id) then
    raise exception 'already belongs to a household';
  end if;
  if exists(
    select 1 from public.ecosystem_household_invitations i
    where i.household_id=household and i.recipient_id=target_id and i.status='pending'
  ) then raise exception 'invitation already pending'; end if;

  insert into public.ecosystem_household_invitations(household_id,sender_id,recipient_id)
  values(household,auth.uid(),target_id)
  returning id into invitation_id;

  insert into public.ecosystem_notifications(recipient_id,actor_id,notification_type,source_app,source_type,source_id,message)
  values(target_id,auth.uid(),'household_invite','account','household_invite',invitation_id::text,'invited you to a family group');
  return invitation_id;
end
$$;

create or replace function public.ecosystem_respond_household_invite(invitation_id uuid,response text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  invite public.ecosystem_household_invitations;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if response not in ('accepted','declined') then raise exception 'invalid response'; end if;

  select * into invite
  from public.ecosystem_household_invitations i
  where i.id=invitation_id and i.recipient_id=auth.uid() and i.status='pending'
  for update;
  if not found then raise exception 'invitation unavailable'; end if;

  if response='accepted' then
    if public.ecosystem_is_blocked(invite.sender_id,invite.recipient_id) then
      raise exception 'invitation unavailable';
    end if;
    if not exists(
      select 1 from public.ecosystem_households h
      where h.id=invite.household_id and h.owner_id=invite.sender_id
    ) then raise exception 'invitation unavailable'; end if;
    if exists(select 1 from public.ecosystem_household_members m where m.user_id=auth.uid()) then
      raise exception 'already belongs to a household';
    end if;

    update public.ecosystem_household_invitations
      set status='accepted',responded_at=now()
      where id=invite.id;
    insert into public.ecosystem_household_members(household_id,user_id,role)
      values(invite.household_id,auth.uid(),'member');
    update public.ecosystem_household_invitations
      set status='cancelled',responded_at=now()
      where recipient_id=auth.uid() and status='pending' and id<>invite.id;
  else
    update public.ecosystem_household_invitations
      set status='declined',responded_at=now()
      where id=invite.id;
  end if;

  update public.ecosystem_notifications
    set read_at=coalesce(read_at,now())
    where recipient_id=auth.uid() and source_app='account'
      and source_type='household_invite' and source_id=invite.id::text;
end
$$;

create or replace function public.ecosystem_cancel_household_invite(invitation_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  cancelled_id uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  update public.ecosystem_household_invitations i
    set status='cancelled',responded_at=now()
  from public.ecosystem_households h
  where i.id=invitation_id and i.household_id=h.id and i.status='pending'
    and i.sender_id=auth.uid() and h.owner_id=auth.uid()
  returning i.id into cancelled_id;
  if cancelled_id is null then raise exception 'invitation unavailable'; end if;

  delete from public.ecosystem_notifications
  where source_app='account' and source_type='household_invite'
    and source_id=cancelled_id::text;
end
$$;

create or replace function public.ecosystem_remove_household_member(target_household uuid,target_user uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  household_owner uuid;
  removed_id uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select owner_id into household_owner from public.ecosystem_households where id=target_household;
  if household_owner is null then raise exception 'household unavailable'; end if;

  if target_user=household_owner then raise exception 'owner must delete the household'; end if;
  if auth.uid()<>target_user and auth.uid()<>household_owner then raise exception 'not allowed'; end if;

  delete from public.ecosystem_household_members
  where household_id=target_household and user_id=target_user and role='member'
  returning user_id into removed_id;
  if removed_id is null then raise exception 'member unavailable'; end if;
end
$$;

create or replace function public.ecosystem_delete_household(target_household uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  deleted_id uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;

  delete from public.ecosystem_notifications n
  using public.ecosystem_household_invitations i
  where i.household_id=target_household and n.source_app='account'
    and n.source_type='household_invite' and n.source_id=i.id::text;

  delete from public.ecosystem_households
  where id=target_household and owner_id=auth.uid()
  returning id into deleted_id;
  if deleted_id is null then raise exception 'household unavailable'; end if;
end
$$;

create or replace function public.ecosystem_household_state()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with current_household as (
    select h.id,h.name,h.owner_id,m.role,h.created_at,h.updated_at
    from public.ecosystem_household_members m
    join public.ecosystem_households h on h.id=m.household_id
    where m.user_id=auth.uid()
    limit 1
  ), member_rows as (
    select m.user_id as id,p.display_name,p.handle,p.bio,p.avatar_path,m.role,m.joined_at
    from current_household h
    join public.ecosystem_household_members m on m.household_id=h.id
    left join public.profiles p on p.id=m.user_id
  ), incoming_rows as (
    select i.id,i.household_id,h.name as household_name,i.sender_id,
      p.display_name,p.handle,p.avatar_path,i.created_at
    from public.ecosystem_household_invitations i
    join public.ecosystem_households h on h.id=i.household_id
    left join public.profiles p on p.id=i.sender_id
    where i.recipient_id=auth.uid() and i.status='pending'
      and not public.ecosystem_is_blocked(i.sender_id,i.recipient_id)
  ), outgoing_rows as (
    select i.id,i.household_id,i.recipient_id,
      p.display_name,p.handle,p.avatar_path,i.created_at
    from public.ecosystem_household_invitations i
    join current_household h on h.id=i.household_id and h.owner_id=auth.uid()
    left join public.profiles p on p.id=i.recipient_id
    where i.sender_id=auth.uid() and i.status='pending'
  )
  select jsonb_build_object(
    'household',(
      select jsonb_build_object('id',id,'name',name,'owner_id',owner_id,'role',role,'created_at',created_at,'updated_at',updated_at)
      from current_household
    ),
    'members',coalesce((
      select jsonb_agg(to_jsonb(m) order by (m.role='owner') desc,lower(coalesce(m.display_name,m.handle,''))) from member_rows m
    ),'[]'::jsonb),
    'incoming',coalesce((
      select jsonb_agg(to_jsonb(i) order by i.created_at desc) from incoming_rows i
    ),'[]'::jsonb),
    'outgoing',coalesce((
      select jsonb_agg(to_jsonb(o) order by o.created_at desc) from outgoing_rows o
    ),'[]'::jsonb)
  )
  where auth.uid() is not null
$$;

create or replace function public.ecosystem_block_user(target_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if auth.uid() is null or target_id=auth.uid() then raise exception 'not allowed'; end if;
  insert into public.ecosystem_blocks(blocker_id,blocked_id) values(auth.uid(),target_id) on conflict do nothing;
  delete from public.ecosystem_follows where (follower_id=auth.uid() and followed_id=target_id) or (follower_id=target_id and followed_id=auth.uid());
  delete from public.ecosystem_friend_requests where status='pending' and ((sender_id=auth.uid() and recipient_id=target_id) or (sender_id=target_id and recipient_id=auth.uid()));
  delete from public.ecosystem_friendships where user_low_id=least(auth.uid(),target_id) and user_high_id=greatest(auth.uid(),target_id);
  delete from public.ecosystem_household_invitations where status='pending' and ((sender_id=auth.uid() and recipient_id=target_id) or (sender_id=target_id and recipient_id=auth.uid()));
  update public.daymark_item_shares set status='revoked',updated_at=now() where status in('pending','accepted') and ((owner_id=auth.uid() and recipient_id=target_id) or (owner_id=target_id and recipient_id=auth.uid()));
  update public.fairway_round_participants p set invitation_status='removed',responded_at=now() from public.fairway_round_sessions s where p.session_id=s.id and p.user_id in(auth.uid(),target_id) and s.host_id in(auth.uid(),target_id) and p.role<>'host';
end
$$;

revoke all on function public.ecosystem_create_household(text),public.ecosystem_invite_household(uuid,uuid),
  public.ecosystem_respond_household_invite(uuid,text),public.ecosystem_cancel_household_invite(uuid),
  public.ecosystem_remove_household_member(uuid,uuid),public.ecosystem_delete_household(uuid),
  public.ecosystem_household_state() from public,anon;
grant execute on function public.ecosystem_create_household(text),public.ecosystem_invite_household(uuid,uuid),
  public.ecosystem_respond_household_invite(uuid,text),public.ecosystem_cancel_household_invite(uuid),
  public.ecosystem_remove_household_member(uuid,uuid),public.ecosystem_delete_household(uuid),
  public.ecosystem_household_state() to authenticated;

commit;

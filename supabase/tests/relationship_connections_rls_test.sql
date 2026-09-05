-- Run in Supabase SQL Editor. Uses three existing auth users and rolls everything back.
begin;

do $$
begin
  if (select count(*) from (select id from auth.users limit 3) users) < 3 then
    raise exception 'Relationship test requires three existing auth users';
  end if;
  perform set_config('relationship_test.a',(select id::text from auth.users order by created_at limit 1),true);
  perform set_config('relationship_test.b',(select id::text from auth.users order by created_at offset 1 limit 1),true);
  perform set_config('relationship_test.c',(select id::text from auth.users order by created_at offset 2 limit 1),true);
end $$;

update public.profiles set discoverable=true,
  display_name=case id when current_setting('relationship_test.a')::uuid then 'Relationship Test A' else 'Relationship Test B' end
where id in(current_setting('relationship_test.a')::uuid,current_setting('relationship_test.b')::uuid,current_setting('relationship_test.c')::uuid);

-- Isolate the test lifecycle from legitimate relationships between the selected
-- accounts. The surrounding transaction restores every row on rollback.
delete from public.ecosystem_friendships
where user_low_id in(current_setting('relationship_test.a')::uuid,current_setting('relationship_test.b')::uuid,current_setting('relationship_test.c')::uuid)
  and user_high_id in(current_setting('relationship_test.a')::uuid,current_setting('relationship_test.b')::uuid,current_setting('relationship_test.c')::uuid);
delete from public.ecosystem_friend_requests
where sender_id in(current_setting('relationship_test.a')::uuid,current_setting('relationship_test.b')::uuid,current_setting('relationship_test.c')::uuid)
  and recipient_id in(current_setting('relationship_test.a')::uuid,current_setting('relationship_test.b')::uuid,current_setting('relationship_test.c')::uuid);
delete from public.ecosystem_follows
where follower_id in(current_setting('relationship_test.a')::uuid,current_setting('relationship_test.b')::uuid,current_setting('relationship_test.c')::uuid)
  and followed_id in(current_setting('relationship_test.a')::uuid,current_setting('relationship_test.b')::uuid,current_setting('relationship_test.c')::uuid);
delete from public.ecosystem_blocks
where blocker_id in(current_setting('relationship_test.a')::uuid,current_setting('relationship_test.b')::uuid,current_setting('relationship_test.c')::uuid)
  and blocked_id in(current_setting('relationship_test.a')::uuid,current_setting('relationship_test.b')::uuid,current_setting('relationship_test.c')::uuid);

set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('relationship_test.a'),true);

do $$ declare found integer; begin
  select count(*) into found from public.profiles where id=current_setting('relationship_test.b')::uuid;
  if found<>0 then raise exception 'User A directly read User B private profile'; end if;
  select count(*) into found from public.ecosystem_relationship_people('', 'search', 20);
  if found<>0 then raise exception 'Blank discovery unexpectedly enumerated profiles'; end if;
  select count(*) into found from public.ecosystem_relationship_people('Relationship Test B','search',20)
  where id=current_setting('relationship_test.b')::uuid;
  if found<>1 then raise exception 'Discoverable User B was not found safely'; end if;
  begin
    insert into public.ecosystem_follows(follower_id,followed_id) values(auth.uid(),current_setting('relationship_test.b')::uuid);
    raise exception 'Direct follow-table insert succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;

select public.ecosystem_set_follow(current_setting('relationship_test.b')::uuid,true);
select public.ecosystem_set_follow(current_setting('relationship_test.b')::uuid,true);
do $$ declare found integer; begin
  select count(*) into found from public.ecosystem_follows
  where follower_id=auth.uid() and followed_id=current_setting('relationship_test.b')::uuid;
  if found<>1 then raise exception 'Follow uniqueness failed'; end if;
  begin
    perform public.ecosystem_set_follow(auth.uid(),true);
    raise exception 'Self follow succeeded';
  exception when raise_exception then
    if sqlerrm='Self follow succeeded' then raise; end if;
  end;
end $$;

select set_config('request.jwt.claim.sub',current_setting('relationship_test.c'),true);
do $$ declare found integer; begin
  select count(*) into found from public.ecosystem_follows
  where follower_id=current_setting('relationship_test.a')::uuid and followed_id=current_setting('relationship_test.b')::uuid;
  if found<>0 then raise exception 'Uninvolved User C read A/B follow'; end if;
end $$;

select set_config('request.jwt.claim.sub',current_setting('relationship_test.a'),true);
select set_config('relationship_test.request',public.ecosystem_send_friend_request(current_setting('relationship_test.b')::uuid)::text,true);
do $$ declare affected integer; begin
  begin
    update public.ecosystem_friend_requests set status='accepted' where id=current_setting('relationship_test.request')::uuid;
    get diagnostics affected=row_count;
    if affected>0 then raise exception 'Direct friend-request mutation succeeded'; end if;
  exception when insufficient_privilege then null;
  end;
end $$;
select public.ecosystem_cancel_friend_request(current_setting('relationship_test.request')::uuid);
do $$ declare found integer; begin
  select count(*) into found from public.ecosystem_relationship_people('', 'requests', 20);
  if found<>0 then raise exception 'Cancelled outgoing request remained active'; end if;
end $$;

select set_config('relationship_test.request',public.ecosystem_send_friend_request(current_setting('relationship_test.b')::uuid)::text,true);
do $$ begin
  begin
    perform public.ecosystem_send_friend_request(current_setting('relationship_test.b')::uuid);
    raise exception 'Duplicate pending request succeeded';
  exception when unique_violation then null;
  end;
end $$;

select set_config('request.jwt.claim.sub',current_setting('relationship_test.b'),true);
do $$ declare found integer; begin
  select count(*) into found from public.ecosystem_relationship_people('', 'requests', 20)
  where id=current_setting('relationship_test.a')::uuid and request_direction='incoming';
  if found<>1 then raise exception 'Incoming request was not visible to recipient'; end if;
end $$;
select public.ecosystem_respond_friend_request(current_setting('relationship_test.request')::uuid,'accepted');

select set_config('request.jwt.claim.sub',current_setting('relationship_test.a'),true);
do $$ declare found integer; begin
  select count(*) into found from public.ecosystem_relationship_people('', 'friends', 20)
  where id=current_setting('relationship_test.b')::uuid and is_friend;
  if found<>1 then raise exception 'Accepted friendship missing for User A'; end if;
end $$;
select public.ecosystem_remove_friend(current_setting('relationship_test.b')::uuid);

select set_config('relationship_test.request',public.ecosystem_send_friend_request(current_setting('relationship_test.b')::uuid)::text,true);
select set_config('request.jwt.claim.sub',current_setting('relationship_test.b'),true);
select public.ecosystem_respond_friend_request(current_setting('relationship_test.request')::uuid,'declined');
do $$ declare found integer; begin
  select count(*) into found from public.ecosystem_relationship_people('', 'friends', 20)
  where id=current_setting('relationship_test.a')::uuid;
  if found<>0 then raise exception 'Declined request created friendship'; end if;
end $$;

do $$ declare found integer; begin
  select count(*) into found from public.daymark_tasks where user_id=current_setting('relationship_test.a')::uuid;
  if found<>0 then raise exception 'Friend/follow relationship exposed another user Daymark'; end if;
  select count(*) into found from public.money_transactions where user_id=current_setting('relationship_test.a')::uuid;
  if found<>0 then raise exception 'Friend/follow relationship exposed another user Money data'; end if;
end $$;

select set_config('request.jwt.claim.sub',current_setting('relationship_test.a'),true);
select public.ecosystem_block_user(current_setting('relationship_test.c')::uuid);
select set_config('request.jwt.claim.sub',current_setting('relationship_test.c'),true);
do $$ declare found integer; begin
  select count(*) into found from public.ecosystem_relationship_people('Relationship Test A','search',20)
  where id=current_setting('relationship_test.a')::uuid;
  if found<>0 then raise exception 'Blocked User C could discover User A'; end if;
  begin
    perform public.ecosystem_set_follow(current_setting('relationship_test.a')::uuid,true);
    raise exception 'Blocked follow succeeded';
  exception when raise_exception then
    if sqlerrm='Blocked follow succeeded' then raise; end if;
  end;
end $$;

reset role;
set local role anon;
do $$ begin
  begin
    perform * from public.ecosystem_relationship_people('test','search',10);
    raise exception 'Anonymous relationship discovery succeeded';
  exception when insufficient_privilege then null;
  end;
  begin
    perform count(*) from public.ecosystem_friend_requests;
    raise exception 'Anonymous friend-request read succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
select 'passed: discovery, follows, requests, friendships, blocking, private-app isolation, and anonymous denial' as result;
rollback;

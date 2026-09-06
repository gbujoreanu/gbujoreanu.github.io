-- Run in Supabase SQL Editor. Uses three existing auth users and rolls everything back.
begin;

do $$
begin
  if (select count(*) from (select id from auth.users limit 3) users) < 3 then
    raise exception 'Avatar test requires three existing auth users';
  end if;
  perform set_config('avatar_test.a',(select id::text from auth.users order by created_at limit 1),true);
  perform set_config('avatar_test.b',(select id::text from auth.users order by created_at offset 1 limit 1),true);
  perform set_config('avatar_test.c',(select id::text from auth.users order by created_at offset 2 limit 1),true);
  perform set_config('avatar_test.path',(select id::text from auth.users order by created_at limit 1)||'/avatar-rls-test-'||gen_random_uuid()::text||'.png',true);
end $$;

update public.profiles set discoverable=false
where id=current_setting('avatar_test.a')::uuid;

delete from public.ecosystem_blocks
where blocker_id in(current_setting('avatar_test.a')::uuid,current_setting('avatar_test.b')::uuid,current_setting('avatar_test.c')::uuid)
  and blocked_id in(current_setting('avatar_test.a')::uuid,current_setting('avatar_test.b')::uuid,current_setting('avatar_test.c')::uuid);
delete from public.ecosystem_follows
where follower_id in(current_setting('avatar_test.a')::uuid,current_setting('avatar_test.b')::uuid,current_setting('avatar_test.c')::uuid)
  and followed_id in(current_setting('avatar_test.a')::uuid,current_setting('avatar_test.b')::uuid,current_setting('avatar_test.c')::uuid);
insert into public.ecosystem_follows(follower_id,followed_id)
values(current_setting('avatar_test.a')::uuid,current_setting('avatar_test.b')::uuid);

insert into storage.objects(bucket_id,name,owner_id)
values('avatars',current_setting('avatar_test.path'),current_setting('avatar_test.a'));

-- The followed user may see a non-discoverable follower's avatar, but cannot mutate it.
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('avatar_test.b'),true);
do $$ declare touched integer; begin
  select count(*) into touched from storage.objects
  where bucket_id='avatars' and name=current_setting('avatar_test.path');
  if touched<>1 then raise exception 'Legitimate follower avatar was not readable'; end if;

  update storage.objects set metadata='{}'::jsonb
  where bucket_id='avatars' and name=current_setting('avatar_test.path');
  get diagnostics touched=row_count;
  if touched<>0 then raise exception 'User B updated User A avatar'; end if;

  begin
    insert into storage.objects(bucket_id,name,owner_id)
    values('avatars',current_setting('avatar_test.a')||'/forged.png',current_setting('avatar_test.b'));
    raise exception 'User B inserted into User A path';
  exception when insufficient_privilege then null;
  end;
end $$;

-- An unrelated authenticated user cannot read the same private object.
select set_config('request.jwt.claim.sub',current_setting('avatar_test.c'),true);
do $$ declare touched integer; begin
  select count(*) into touched from storage.objects
  where bucket_id='avatars' and name=current_setting('avatar_test.path');
  if touched<>0 then raise exception 'Unrelated User C read User A avatar'; end if;
end $$;

-- Anonymous users cannot enumerate or create avatar objects.
reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ declare touched integer; begin
  select count(*) into touched from storage.objects
  where bucket_id='avatars' and name=current_setting('avatar_test.path');
  if touched<>0 then raise exception 'Anonymous user read User A avatar'; end if;
  begin
    insert into storage.objects(bucket_id,name) values('avatars','anonymous/avatar.png');
    raise exception 'Anonymous avatar insert succeeded';
  exception when insufficient_privilege then null;
  end;
end $$;

reset role;
select 'passed: private avatars visible only in legitimate profile contexts' as result;
rollback;

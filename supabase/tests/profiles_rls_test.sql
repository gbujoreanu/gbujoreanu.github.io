-- Run in the Supabase SQL editor. All changes are rolled back.
begin;

do $$
declare users_found integer;
begin
  select count(*) into users_found from (select id from auth.users limit 2) users;
  if users_found < 2 then raise exception 'Profile RLS test requires two existing auth users'; end if;
  perform set_config('profile_test.user_a', (select id::text from auth.users order by created_at limit 1), true);
  perform set_config('profile_test.user_b', (select id::text from auth.users order by created_at offset 1 limit 1), true);
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('profile_test.user_a'), true);

do $$
declare affected integer;
begin
  update public.profiles
  set display_name = 'Synthetic User A', handle = 'synthetic_user_a', bio = 'Rolled back test profile.'
  where id = current_setting('profile_test.user_a')::uuid;
  get diagnostics affected = row_count;
  if affected <> 1 then raise exception 'User A could not update their profile'; end if;
end;
$$;

select set_config('request.jwt.claim.sub', current_setting('profile_test.user_b'), true);

do $$
declare visible integer;
begin
  select count(*) into visible from public.profiles
  where id = current_setting('profile_test.user_a')::uuid;
  if visible <> 0 then raise exception 'User B can read User A profile'; end if;

  update public.profiles set bio = 'IDOR update'
  where id = current_setting('profile_test.user_a')::uuid;
  get diagnostics visible = row_count;
  if visible <> 0 then raise exception 'User B updated User A profile'; end if;

  begin
    update public.profiles set handle = 'synthetic_user_a'
    where id = current_setting('profile_test.user_b')::uuid;
    raise exception 'Case-insensitive duplicate handle was accepted';
  exception when unique_violation then null;
  end;

  begin
    insert into public.profiles(id, display_name, handle)
    values (current_setting('profile_test.user_a')::uuid, 'Forged owner', 'forged_owner');
    raise exception 'User B inserted against User A identity';
  exception when insufficient_privilege or unique_violation then null;
  end;
end;
$$;

reset role;
set local role anon;
do $$
begin
  begin
    perform count(*) from public.profiles;
    raise exception 'Anonymous profile read was accepted';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.profiles set display_name = 'Anonymous update';
    raise exception 'Anonymous profile update was accepted';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
select 'Profile owner isolation tests passed for User A, User B, and anonymous access' as result;
rollback;

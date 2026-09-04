do $$
declare
  user_a uuid;
  user_b uuid;
  touched integer;
begin
  select id into user_a from auth.users order by created_at limit 1;
  select id into user_b from auth.users where id <> user_a order by created_at limit 1;
  if user_a is null or user_b is null then raise exception 'requires two auth users'; end if;

  begin
    execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', user_a::text, true);
    insert into storage.objects (bucket_id, name, owner_id)
    values ('avatars', user_a::text || '/avatar-rls-test.png', user_a::text);

    perform set_config('request.jwt.claim.sub', user_b::text, true);
    select count(*) into touched from storage.objects
    where bucket_id = 'avatars' and name = user_a::text || '/avatar-rls-test.png';
    if touched <> 0 then raise exception 'User B read User A avatar'; end if;

    update storage.objects set metadata = '{}'::jsonb
    where bucket_id = 'avatars' and name = user_a::text || '/avatar-rls-test.png';
    get diagnostics touched = row_count;
    if touched <> 0 then raise exception 'User B updated User A avatar'; end if;

    begin
      insert into storage.objects (bucket_id, name, owner_id)
      values ('avatars', user_a::text || '/forged.png', user_b::text);
      raise exception 'User B inserted into User A path';
    exception when insufficient_privilege then null;
    end;

    -- Roll back the synthetic owner row without directly deleting from Storage tables.
    raise exception using errcode = 'P0001', message = 'rollback synthetic owner object';
  exception when sqlstate 'P0001' then null;
  end;

  execute 'reset role';
  execute 'set local role anon';
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    insert into storage.objects (bucket_id, name) values ('avatars', 'anonymous/avatar.png');
    raise exception 'Anonymous avatar insert succeeded';
  exception when insufficient_privilege then null;
  end;
  execute 'reset role';
end $$;

select 'passed' as avatar_user_a_user_b_anonymous_rls;

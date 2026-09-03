begin;

alter table public.profiles
  add column if not exists handle text,
  add column if not exists avatar_url text,
  add column if not exists bio text,
  add column if not exists discoverable boolean not null default false;

alter table public.profiles
  drop constraint if exists profiles_display_name_length,
  drop constraint if exists profiles_handle_format,
  drop constraint if exists profiles_bio_length,
  add constraint profiles_display_name_length
    check (display_name is null or char_length(btrim(display_name)) between 1 and 60),
  add constraint profiles_handle_format
    check (handle is null or (
      handle = lower(btrim(handle))
      and handle ~ '^[a-z][a-z0-9_]{2,23}$'
    )),
  add constraint profiles_bio_length
    check (bio is null or char_length(bio) <= 180);

create unique index if not exists profiles_handle_lower_key
  on public.profiles (lower(handle))
  where handle is not null;

create or replace function public.account_touch_profile()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function public.account_touch_profile() from public;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.account_touch_profile();

alter table public.profiles enable row level security;
alter table public.profiles force row level security;

revoke all on table public.profiles from anon;
revoke all on table public.profiles from authenticated;
grant select, insert, update on table public.profiles to authenticated;

do $$
declare
  policy_name text;
begin
  for policy_name in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'profiles'
  loop
    execute format('drop policy %I on public.profiles', policy_name);
  end loop;
end;
$$;

create policy profiles_owner_select
  on public.profiles for select to authenticated
  using ((select auth.uid()) = id);

create policy profiles_owner_insert
  on public.profiles for insert to authenticated
  with check ((select auth.uid()) = id);

create policy profiles_owner_update
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

commit;

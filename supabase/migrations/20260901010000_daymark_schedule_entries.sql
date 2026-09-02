create table if not exists public.daymark_schedule_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null,
  notes text not null default '',
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  time_zone text not null default 'UTC',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint daymark_schedule_entries_title_length
    check (char_length(btrim(title)) between 1 and 120),
  constraint daymark_schedule_entries_notes_length
    check (char_length(notes) <= 1000),
  constraint daymark_schedule_entries_time_zone_length
    check (char_length(time_zone) between 1 and 100),
  constraint daymark_schedule_entries_valid_range
    check (ends_at > starts_at),
  constraint daymark_schedule_entries_max_duration
    check (ends_at <= starts_at + interval '24 hours'),
  constraint daymark_schedule_entries_user_id_id_key unique (user_id, id)
);

create index if not exists daymark_schedule_entries_user_starts_at_idx
  on public.daymark_schedule_entries (user_id, starts_at);

create index if not exists daymark_schedule_entries_user_ends_at_idx
  on public.daymark_schedule_entries (user_id, ends_at);

alter table public.daymark_schedule_entries enable row level security;

revoke all on table public.daymark_schedule_entries from anon;
grant select, insert, update, delete on table public.daymark_schedule_entries to authenticated;

drop policy if exists "Users can view their own schedule entries" on public.daymark_schedule_entries;
create policy "Users can view their own schedule entries"
  on public.daymark_schedule_entries
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can create their own schedule entries" on public.daymark_schedule_entries;
create policy "Users can create their own schedule entries"
  on public.daymark_schedule_entries
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update their own schedule entries" on public.daymark_schedule_entries;
create policy "Users can update their own schedule entries"
  on public.daymark_schedule_entries
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete their own schedule entries" on public.daymark_schedule_entries;
create policy "Users can delete their own schedule entries"
  on public.daymark_schedule_entries
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

create or replace function public.daymark_touch_schedule_entry()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function public.daymark_touch_schedule_entry() from public;

drop trigger if exists daymark_schedule_entries_set_updated_at on public.daymark_schedule_entries;
create trigger daymark_schedule_entries_set_updated_at
before update on public.daymark_schedule_entries
for each row execute function public.daymark_touch_schedule_entry();

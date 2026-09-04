begin;

alter table public.profiles
  add column if not exists avatar_path text;

alter table public.profiles
  drop constraint if exists profiles_avatar_path_owner,
  add constraint profiles_avatar_path_owner check (
    avatar_path is null or (
      split_part(avatar_path, '/', 1) = id::text
      and avatar_path !~ '/.*/'
      and lower(avatar_path) ~ '\.(jpg|jpeg|png|webp)$'
    )
  );

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists avatar_owner_select on storage.objects;
drop policy if exists avatar_owner_insert on storage.objects;
drop policy if exists avatar_owner_update on storage.objects;
drop policy if exists avatar_owner_delete on storage.objects;

create policy avatar_owner_select on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy avatar_owner_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy avatar_owner_update on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy avatar_owner_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

commit;

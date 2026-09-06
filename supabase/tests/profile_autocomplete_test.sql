-- Search normalization and safe result-state checks. Rolls back all changes.
begin;
do $$ begin
  if (select count(*) from (select id from auth.users limit 2) u)<2 then raise exception 'Autocomplete test requires two auth users'; end if;
  perform set_config('search_test.a',(select id::text from auth.users order by created_at limit 1),true);
  perform set_config('search_test.b',(select id::text from auth.users order by created_at offset 1 limit 1),true);
end $$;
update public.profiles set display_name='Synthetic Wavy Profile',handle='synthetic_wavy',discoverable=true where id=current_setting('search_test.b')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('search_test.a'),true);
do $$ declare hits integer; begin
  select count(*) into hits from public.ecosystem_relationship_people('wav','search',30) where id=current_setting('search_test.b')::uuid;if hits<>1 then raise exception 'Partial display/handle search failed';end if;
  select count(*) into hits from public.ecosystem_relationship_people('@SYNTHETIC_WAVY','search',30) where id=current_setting('search_test.b')::uuid;if hits<>1 then raise exception '@handle normalization failed';end if;
  select count(*) into hits from public.ecosystem_relationship_people('SyNtHeTiC_WaVy','search',30) where id=current_setting('search_test.b')::uuid;if hits<>1 then raise exception 'Case-insensitive handle search failed';end if;
  select count(*) into hits from public.ecosystem_relationship_people('','search',30);if hits<>0 then raise exception 'Blank search enumerated profiles';end if;
end $$;
rollback;

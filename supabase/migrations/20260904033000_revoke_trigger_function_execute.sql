begin;
revoke all on function public.daymark_validate_share(),public.daymark_share_notify(),public.money_sync_bill_event() from public,anon,authenticated;
commit;

begin;

create index if not exists ecosystem_follows_followed
  on public.ecosystem_follows(followed_id, follower_id);
create index if not exists ecosystem_friend_requests_recipient_status
  on public.ecosystem_friend_requests(recipient_id, status, created_at desc);
create index if not exists ecosystem_friend_requests_sender_status
  on public.ecosystem_friend_requests(sender_id, status, created_at desc);
create index if not exists ecosystem_friendships_high
  on public.ecosystem_friendships(user_high_id, user_low_id);
create index if not exists ecosystem_blocks_blocked
  on public.ecosystem_blocks(blocked_id, blocker_id);

commit;

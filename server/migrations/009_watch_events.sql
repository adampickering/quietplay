-- Per-playback telemetry. Client batches watch seconds up to the
-- server every minute so the admin dashboard can tell a parent what
-- their kid actually watched, when, and how much.
create table if not exists watch_events (
  id          bigserial primary key,
  profile_id  uuid not null references profiles(id) on delete cascade,
  video_id    uuid references videos(id) on delete set null,
  event_type  text not null default 'watch',
  seconds     int,
  occurred_at timestamptz not null default now()
);

create index if not exists watch_events_profile_time_idx
  on watch_events (profile_id, occurred_at desc);
create index if not exists watch_events_video_idx
  on watch_events (video_id);
create index if not exists watch_events_type_idx
  on watch_events (event_type);

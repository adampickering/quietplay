create extension if not exists "pgcrypto";

create table if not exists channels (
  id                  uuid primary key default gen_random_uuid(),
  youtube_channel_id  text unique not null,
  title               text not null,
  thumbnail_url       text,
  is_active           boolean not null default true,
  created_at          timestamptz not null default now()
);

create table if not exists videos (
  id                uuid primary key default gen_random_uuid(),
  channel_id        uuid not null references channels(id) on delete cascade,
  youtube_video_id  text unique not null,
  title             text not null,
  thumbnail_url     text,
  published_at      timestamptz not null,
  ingested_at       timestamptz not null default now()
);

create index if not exists videos_published_at_desc_idx on videos (published_at desc);
create index if not exists videos_channel_id_idx on videos (channel_id);

create table if not exists profiles (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  channel_ids  uuid[] not null,
  position     int not null check (position between 0 and 2),
  unique (position)
);

alter table videos add column if not exists is_short boolean not null default false;

create index if not exists videos_is_short_idx on videos(is_short) where is_short = false;

drop view if exists playable_videos;

create view playable_videos as
select
  v.youtube_video_id,
  v.title,
  v.thumbnail_url,
  v.published_at,
  c.id    as channel_id,
  c.title as channel_title
from videos v
join channels c on v.channel_id = c.id
where c.is_active = true
  and v.is_short = false
order by v.published_at desc
limit 150;

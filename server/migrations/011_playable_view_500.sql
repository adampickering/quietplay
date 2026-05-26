-- Bump the playable_videos per-channel cap from 200 to 500. Kept in
-- sync with MAX_ENTRIES in ingest-lib.ts and the rn <= N clause in
-- /library — all three want the same number.

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
limit 500;

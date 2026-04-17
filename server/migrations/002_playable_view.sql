create or replace view playable_videos as
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
order by v.published_at desc
limit 150;

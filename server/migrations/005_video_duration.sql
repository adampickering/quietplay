-- yt-dlp's flat-playlist mode returns each video's duration when the
-- YouTube extractor includes it in the channel listing response. We
-- store it so the tvOS client can render a `12:34` badge on every
-- thumbnail without an extra roundtrip.
alter table videos
  add column if not exists duration_seconds int;

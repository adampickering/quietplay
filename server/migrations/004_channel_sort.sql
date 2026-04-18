-- Per-channel default video sort order. 'newest' (default) shows the most
-- recently published first — right for vlog/episodic channels. 'oldest'
-- surfaces the oldest first — right for serial content the viewer wants
-- to start from episode 1.
alter table channels
  add column if not exists default_video_sort text not null default 'newest'
  check (default_video_sort in ('newest', 'oldest'));

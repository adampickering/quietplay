-- Per-channel category so the tvOS sidebar can offer "virtual
-- super-channels" that pool videos from every channel in a bucket
-- (Trains, LEGO, Cars, etc.). Free text so we can add categories
-- without another migration; client maps unknown values to "Other".
alter table channels
  add column if not exists category text;

create index if not exists channels_category_idx on channels (category) where is_active;

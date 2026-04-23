-- Dad-curated "Recommended" flag. Surfaces a dedicated virtual
-- channel in the tvOS sidebar pooling every channel Dad has flagged,
-- so Henry lands on handpicked stuff near the top of the library.
alter table channels
  add column if not exists is_recommended boolean not null default false;

create index if not exists channels_recommended_idx
  on channels (is_recommended) where is_recommended;

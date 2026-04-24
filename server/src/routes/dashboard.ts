import type { FastifyInstance } from 'fastify';
import { pool } from '../db.js';

/**
 * Returns an opinionated blob for a single profile that the admin UI
 * renders without additional logic. Everything is computed per
 * profile, over the "last 7 calendar days including today."
 *
 * Why a single fat endpoint: the dashboard is one page, the parent
 * wants everything at once, and round-tripping 6 queries from the
 * browser is slower than running 6 queries in parallel on the server.
 */
export async function dashboardRoutes(app: FastifyInstance) {
  app.get<{ Params: { id: string } }>('/api/dashboard/:id', async (req, reply) => {
    const profileId = req.params.id;

    const [
      profileRow,
      week,
      daily,
      hourly,
      topChannels,
      topCategories,
      streak,
      favoriteCount,
      newChannels,
      staleChannels,
      recommendedPlays,
    ] = await Promise.all([
      pool.query<{ id: string; name: string }>(
        'select id, name from profiles where id = $1',
        [profileId],
      ),

      // Totals for the trailing 7 days (today included).
      pool.query<{ total_seconds: number; video_count: number; channel_count: number }>(
        `select coalesce(sum(seconds), 0)::int as total_seconds,
                count(distinct video_id)::int as video_count,
                count(distinct v.channel_id)::int as channel_count
         from watch_events we
         left join videos v on v.id = we.video_id
         where we.profile_id = $1
           and we.event_type = 'watch'
           and we.occurred_at >= now() - interval '7 days'`,
        [profileId],
      ),

      // Per-day bars, Mon–Sun aligned to the current week. Oldest first.
      pool.query<{ day: string; seconds: number }>(
        `select to_char(day, 'YYYY-MM-DD') as day,
                coalesce(sum(seconds), 0)::int as seconds
         from (
           select generate_series(
             (current_date - interval '6 days')::date,
             current_date,
             '1 day'::interval
           )::date as day
         ) d
         left join watch_events we
           on we.profile_id = $1
          and we.event_type = 'watch'
          and we.occurred_at::date = d.day
         group by d.day
         order by d.day asc`,
        [profileId],
      ),

      // Hour-of-day totals over the last 7 days.
      pool.query<{ hour: number; seconds: number }>(
        `with hours as (select generate_series(0, 23) as hour)
         select h.hour::int as hour,
                coalesce(sum(we.seconds), 0)::int as seconds
         from hours h
         left join watch_events we
           on we.profile_id = $1
          and we.event_type = 'watch'
          and we.occurred_at >= now() - interval '7 days'
          and extract(hour from we.occurred_at at time zone 'UTC')::int = h.hour
         group by h.hour
         order by h.hour`,
        [profileId],
      ),

      // Top channels by watch seconds, last 7 days.
      pool.query<{ channel_id: string; title: string; seconds: number }>(
        `select c.id as channel_id, c.title,
                coalesce(sum(we.seconds), 0)::int as seconds
         from watch_events we
         join videos v on v.id = we.video_id
         join channels c on c.id = v.channel_id
         where we.profile_id = $1
           and we.event_type = 'watch'
           and we.occurred_at >= now() - interval '7 days'
         group by c.id, c.title
         order by seconds desc
         limit 8`,
        [profileId],
      ),

      pool.query<{ category: string; seconds: number }>(
        `select coalesce(c.category, 'Other') as category,
                coalesce(sum(we.seconds), 0)::int as seconds
         from watch_events we
         join videos v on v.id = we.video_id
         join channels c on c.id = v.channel_id
         where we.profile_id = $1
           and we.event_type = 'watch'
           and we.occurred_at >= now() - interval '7 days'
         group by coalesce(c.category, 'Other')
         order by seconds desc`,
        [profileId],
      ),

      // Streak: number of consecutive days ending today with any
      // watch activity. Uses a day-bitmap over the last 30 days.
      pool.query<{ streak: number }>(
        `with days as (
           select d::date as day
           from generate_series(current_date - interval '30 days', current_date, '1 day'::interval) as d
         ), active as (
           select distinct occurred_at::date as day
           from watch_events
           where profile_id = $1 and event_type = 'watch'
         )
         select coalesce(count(*) filter (
           where days.day in (select day from active)
             and not exists (
               select 1 from generate_series(days.day + 1, current_date, '1 day'::interval) gap
               where gap::date not in (select day from active)
             )
         ), 0)::int as streak
         from days
         where days.day <= current_date`,
        [profileId],
      ),

      // Favorites gained this week (best-effort via 'favorite' events).
      pool.query<{ count: number }>(
        `select count(*)::int as count
         from watch_events
         where profile_id = $1
           and event_type = 'favorite'
           and occurred_at >= now() - interval '7 days'`,
        [profileId],
      ),

      pool.query<{ count: number }>(
        `select count(distinct v.channel_id)::int as count
         from watch_events we
         join videos v on v.id = we.video_id
         where we.profile_id = $1
           and we.event_type = 'watch'
           and we.occurred_at >= now() - interval '7 days'
           and v.channel_id not in (
             select distinct v2.channel_id
             from watch_events we2
             join videos v2 on v2.id = we2.video_id
             where we2.profile_id = $1
               and we2.event_type = 'watch'
               and we2.occurred_at < now() - interval '7 days'
           )`,
        [profileId],
      ),

      // Channels with no new ingests in 30+ days AND that the profile
      // subscribes to. Archive candidates.
      pool.query<{ count: number; titles: string[] }>(
        `with profile_channels as (
           select unnest(channel_ids) as channel_id from profiles where id = $1
         ),
         stale as (
           select c.id, c.title
           from channels c
           join profile_channels pc on pc.channel_id = c.id
           where c.is_active = true
             and not exists (
               select 1 from videos v
               where v.channel_id = c.id
                 and v.published_at >= now() - interval '30 days'
             )
         )
         select count(*)::int as count,
                coalesce(array_agg(title order by title), '{}') as titles
         from stale`,
        [profileId],
      ),

      // How much of the kid's watching came from recommended channels.
      pool.query<{ seconds: number; plays: number }>(
        `select coalesce(sum(we.seconds), 0)::int as seconds,
                count(distinct we.video_id)::int as plays
         from watch_events we
         join videos v on v.id = we.video_id
         join channels c on c.id = v.channel_id
         where we.profile_id = $1
           and we.event_type = 'watch'
           and we.occurred_at >= now() - interval '7 days'
           and c.is_recommended = true`,
        [profileId],
      ),
    ]);

    if (profileRow.rows.length === 0) {
      return reply.code(404).send({ error: 'profile not found' });
    }

    const totals = week.rows[0];
    const staleRow = staleChannels.rows[0];
    const recRow = recommendedPlays.rows[0];

    // Human-readable insights — short, warm, not alarming. Derived
    // from the aggregates above.
    const insights: string[] = [];
    if (totals.total_seconds > 0) {
      const hrs = totals.total_seconds / 3600;
      insights.push(`${hrs.toFixed(1)} hours of watching across ${totals.channel_count} channels this week.`);
    }
    if (recRow.plays > 0) {
      insights.push(`Your Recommended picks earned ${recRow.plays} play${recRow.plays === 1 ? '' : 's'} — ${fmtMin(recRow.seconds)} of attention.`);
    }
    if (streak.rows[0].streak >= 3) {
      insights.push(`Current streak: ${streak.rows[0].streak} day${streak.rows[0].streak === 1 ? '' : 's'}.`);
    }
    if (newChannels.rows[0].count > 0) {
      insights.push(`${newChannels.rows[0].count} channel${newChannels.rows[0].count === 1 ? '' : 's'} got first-time attention this week.`);
    }
    if (staleRow.count > 0) {
      const sample = staleRow.titles.slice(0, 3).join(', ');
      insights.push(`${staleRow.count} subscribed channel${staleRow.count === 1 ? '' : 's'} haven't posted in 30+ days${staleRow.count > 3 ? ` (incl. ${sample})` : `: ${sample}`} — consider deactivating.`);
    }

    return {
      profile: profileRow.rows[0],
      week: {
        total_seconds: totals.total_seconds,
        video_count: totals.video_count,
        channel_count: totals.channel_count,
        streak_days: streak.rows[0].streak,
        favorite_count: favoriteCount.rows[0].count,
        new_channel_count: newChannels.rows[0].count,
      },
      daily: daily.rows,
      hourly: hourly.rows.map((r) => r.seconds),
      top_channels: topChannels.rows,
      top_categories: topCategories.rows,
      recommended: recRow,
      stale_channels: staleRow,
      insights,
    };
  });
}

function fmtMin(seconds: number): string {
  if (seconds < 60) return `${seconds}s`;
  const m = Math.round(seconds / 60);
  if (m < 60) return `${m}m`;
  const h = Math.floor(m / 60);
  const rem = m % 60;
  return rem === 0 ? `${h}h` : `${h}h ${rem}m`;
}

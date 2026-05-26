<div align="center">
  <img src="docs/logo.png" alt="QuietPlay" width="420" />

  <p><em>A calm, intentional YouTube player for Apple TV.</em></p>

  <p>
    <a href="#why"><img src="https://img.shields.io/badge/Why-It%20exists-1D4790" alt="Why"></a>
    <a href="#architecture"><img src="https://img.shields.io/badge/Platform-tvOS%2018%2B-black" alt="tvOS 18+"></a>
    <a href="#architecture"><img src="https://img.shields.io/badge/Server-Node%20%2B%20Postgres-brightgreen" alt="Node + Postgres"></a>
    <a href="#license"><img src="https://img.shields.io/badge/License-MIT-blue" alt="MIT"></a>
  </p>
</div>

---

## Why

YouTube Kids isn't it. The algorithm is loud, the recommendations drift, and the whole interface is engineered to keep a seven-year-old clicking. We wanted something quieter: a TV app where the channels in the library are the ones a parent actually chose, videos play without sidebars full of "up next," and the hardest decision a kid makes is *which show*, not *which of a thousand thumbnails*.

QuietPlay is that app. A self-hosted Node server pulls uploads from a curated list of YouTube channels via `yt-dlp`, stores metadata in Postgres, and resolves playable stream URLs on demand. A SwiftUI tvOS client renders the library — channels on the left, videos on the right — with no search, no algorithm, no comments, no ads, and no autoplay. When a video ends or the kid swipes right, a three-card picker offers the next videos in the same channel. That's it.

It was built for one specific seven-year-old (hi, Henry) but the architecture is generic. If you've got an Apple TV, a spare Mac or Linux box, and a list of channels you trust, you can run your own.

## Features

- **Library-first, no algorithm.** You curate the channels; QuietPlay never recommends anything you didn't pick.
- **Calm playback.** Fullscreen video, generous margins, a single play indicator. Swipe right for the next video, menu for back to library.
- **"Who's watching?"** Multi-profile picker on cold launch, with per-family profile photos.
- **Resume where you left off.** Playback position saved every 5 seconds, surfaced as a progress bar on each thumbnail plus a pinned "Continue watching" row.
- **Favorites.** Press Play/Pause on any video card to star it; starred videos appear in a gold "Favorites" row pinned above everything else.
- **Continue-browsing strip.** After the last video in a channel, a horizontal row of other channels so a kid can hop without going back to the sidebar.
- **No Shorts.** Ingest filters out Shorts automatically.
- **Warm loading screen.** Rotating deadpan quips ("Asking YouTube nicely…", "Buttering the popcorn…") while the stream resolves.
- **Admin web UI** (LAN-only) for adding channels, tweaking profiles, and flipping channels active/inactive — no SSH into Postgres required.
- **Self-contained.** No YouTube Data API key. No Google OAuth. Just `yt-dlp` under the hood.

## Architecture

```
┌────────────────────────┐           ┌──────────────────────────┐
│  tvOS SwiftUI client   │  HTTP     │  Fastify server          │
│  AVPlayer + Library    │ ────────▶ │  /library /resolve /admin│
└────────────────────────┘           │  Postgres · Redis (cache)│
                                     │  yt-dlp subprocess       │
                                     └───────────┬──────────────┘
                                                 │
                                                 ▼
                                         ┌────────────────┐
                                         │  YouTube (RSS  │
                                         │  & yt-dlp flat │
                                         │  playlist)     │
                                         └────────────────┘
```

- **Ingest** — hourly cron. For each active channel, `yt-dlp --flat-playlist --playlist-end 500` lists the 500 newest uploads. Rows upsert into Postgres with `is_short` flagged by duration (≤60s). Shorts are hidden from the client.
- **Resolve** — on each tap, the tvOS client POSTs the YouTube video ID to `/resolve`. The server shells to `yt-dlp` to get a fresh stream URL, caches it in Redis for ~5 hours, and returns it. AVPlayer plays the URL directly.
- **Admin** — Fastify serves a single-file HTML admin UI at `/admin` (no auth — LAN boundary is the security model). Channel URL → metadata lookup happens server-side by scraping the channel page for `og:title` and the `UC…` ID.
- **Storage** — Postgres is the source of truth. Redis is only used for short-lived resolver caching.

## Requirements

- macOS with Xcode 16+ (tvOS 18 SDK)
- Node.js 20+
- Docker (simplest path for Postgres + Redis) or native installs of both
- `yt-dlp` on the server host's PATH (Homebrew: `brew install yt-dlp`)
- An Apple TV for the full experience — the tvOS Simulator works for development

## Getting started

### 1. Clone and install

```bash
git clone https://github.com/adampickering/quietplay.git
cd quietplay
npm install
```

### 2. Start Postgres + Redis

```bash
docker compose up -d
```

### 3. Configure server

```bash
cp .env.example server/.env
# adjust DATABASE_URL / REDIS_URL if you're not using the docker-compose defaults
```

### 4. Run migrations and ingest

```bash
npm run -w @quietplay/server migrate
```

### 5. Start the server

```bash
npm run -w @quietplay/server dev
```

Server listens on `http://localhost:8787`. Admin UI at `http://localhost:8787/admin`. No auth — assume LAN-only access.

### 6. Add some channels + a profile

Open the admin UI, paste any YouTube channel URL (works with `@handle`, `channel/UC…`, and custom URLs), and save. Then create a profile and tick the channels you want to include.

### 7. Run the tvOS app

Open `ios/QuietPlay/QuietPlay.xcodeproj` in Xcode, pick the tvOS Simulator, and hit Run. You should land on the "Who's watching?" screen.

## Running on a real Apple TV

The tvOS Simulator talks to `localhost:8787` out of the box, but an Apple TV on your network needs your Mac's **LAN IP**. In `ios/QuietPlay/Info.plist`, change:

```xml
<key>QuietPlayAPIBaseURL</key>
<string>http://localhost:8787</string>
```

to your Mac's IP (e.g. `http://192.168.0.143:8787`). To avoid committing your personal LAN IP to your fork, after editing run:

```bash
git update-index --skip-worktree ios/QuietPlay/Info.plist
```

Then pair the Apple TV in Xcode via **Window → Devices and Simulators**, pick it as the run destination, and Cmd-R. First launch takes a few minutes while Xcode downloads symbols for the device's tvOS version.

> **Note on Xcode free signing.** Apps signed with a Personal Team expire after 7 days. For longer installs you'll need an Apple Developer account ($99/yr).

## Personalizing profile avatars

Profile photos are matched to profile names by asset lookup:

- Profile named **"Henry"** → looks for `ProfileHenry` in `Assets.xcassets`
- Profile named **"Dad"** → looks for `ProfileDad`

To add a photo:

```bash
mkdir -p ios/QuietPlay/QuietPlay/Assets.xcassets/ProfileYourName.imageset
cp ~/Downloads/myface.png ios/QuietPlay/QuietPlay/Assets.xcassets/ProfileYourName.imageset/yourname.png
```

Then add a `Contents.json` alongside the PNG:

```json
{
  "images": [
    { "filename": "yourname.png", "idiom": "universal", "scale": "1x" },
    { "idiom": "universal", "scale": "2x" },
    { "idiom": "universal", "scale": "3x" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

If no asset is found, QuietPlay falls back to rendering the profile's initials in a circle. The `Profile*.imageset` folders are gitignored so personal photos stay off your public fork.

## Operations

The `scripts/` folder has two pieces worth knowing:

- `scripts/install-cron.sh` — sets up three user crontab entries: hourly ingest, weekly `yt-dlp` upgrade (Sundays 03:00), and nightly Postgres dump (04:00). Idempotent.
- `scripts/backup-postgres.sh` — `pg_dump | gzip` to `~/backups/quietplay` with a 14-day retention.

Health check endpoint: `GET /healthz` returns `{status, db, redis, uptime_seconds}`. Returns 503 if any dependency is down.

## Remote controls

On a focused video card in the library:
- **Click the clickpad** → play
- **Play/Pause** → toggle favorite (pins a gold star to the thumbnail and adds it to the Favorites row)
- **Menu** → back to the sidebar

During playback:
- **Click** → show/hide overlay (title + progress)
- **Swipe right** → picker for next video
- **Swipe left** → previous video in the channel
- **Play/Pause** → pause/resume
- **Menu** → back to library

## Contributing

PRs welcome. The test suite:

```bash
# Swift (PickerBuilder logic)
cd ios && swift test

# Server
npm test -w @quietplay/server

# Typecheck
npm run -w @quietplay/server typecheck
```

## License

MIT. See [LICENSE](LICENSE).

The QuietPlay wordmark and logo in `docs/logo.png` and the app icon assets under `ios/QuietPlay/QuietPlay/Assets.xcassets/App Icon & Top Shelf Image.brandassets/` are not MIT-licensed — please swap them for your own branding on a fork.

## Credits

Built for Henry. The loading-screen quip "Reticulating splines…" is borrowed with gratitude from SimCity.

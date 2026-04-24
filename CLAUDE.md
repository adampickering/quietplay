# CLAUDE.md

Agent-facing operational reference for QuietPlay. For the human-facing
overview see `README.md`. For design intent see `docs/voice.md` and
`docs/easter-eggs.md`.

## Product in one paragraph

A calm, curated YouTube player for Apple TV. A Fastify+Postgres server
ingests uploads from an allowlisted channel list via `yt-dlp`, a SwiftUI
tvOS client plays them with no search, no recommendations, no autoplay
discovery, and no comments. Everything is built around **deterministic
sort by `published_at DESC`** and **parent-curated channels** — the kid
decides *which show*, never *which of a thousand thumbnails*.

## The 7 Golden Rules (from the PRD)

The ones load-bearing enough to reject a feature over:

- **GR2** — No algorithmic recommendations. Ever.
- **GR3** — Deterministic sort only. `published_at DESC` (or ASC per
  channel toggle).

Any feature that violates these is wrong by definition. See §14 of the
PRD for the full non-goals list (search, notifications, view counts,
trending, personalisation, history-based anything).

## Repo layout

```
~/dev/quietplay/
├── server/                  # Fastify + Postgres + Redis + yt-dlp
│   ├── src/
│   │   ├── routes/          # resolver, client, admin, dashboard, events, health
│   │   ├── admin/index.html # single-file admin UI
│   │   ├── ingest-lib.ts    # yt-dlp channel ingest
│   │   ├── categorize.ts    # keyword rules → channel category
│   │   ├── db.ts, redis.ts, ytdlp.ts, logger.ts
│   │   └── migrate.ts, ingest.ts
│   └── migrations/          # numbered .sql files
├── ios/QuietPlay/           # Xcode project + SwiftPM package
│   └── QuietPlay/QuietPlay/ # all the Swift sources
├── scripts/                 # ops: backup, cron, launchd, asset gen, date fixer
├── docs/
│   ├── voice.md             # copy tone reference — read before writing strings
│   ├── easter-eggs.md       # index of hidden moments and their odds
│   └── channel-import.md
└── docker-compose.yml       # Postgres + Redis for local dev
```

## Build / run — common commands

### Server
```bash
cd ~/dev/quietplay
npm run -w @quietplay/server dev         # tsx watch
npm run -w @quietplay/server migrate     # apply migrations/*.sql
npm run -w @quietplay/server typecheck   # tsc --noEmit
npm run -w @quietplay/server test
```

The server runs under a LaunchAgent (`com.quietplay.server`). Restart it
after server edits:
```bash
launchctl kickstart -k gui/$UID/com.quietplay.server
```

### iOS — tvOS Simulator
```bash
cd ~/dev/quietplay/ios/QuietPlay
xcodebuild -project QuietPlay.xcodeproj -scheme QuietPlay -configuration Debug \
  -destination 'platform=tvOS Simulator,id=067DDF4E-F57D-4E86-998C-90BE1258B2BE' \
  -derivedDataPath build build

xcrun simctl install 067DDF4E-F57D-4E86-998C-90BE1258B2BE \
  build/Build/Products/Debug-appletvsimulator/QuietPlay.app
xcrun simctl launch 067DDF4E-F57D-4E86-998C-90BE1258B2BE com.adampickering.quietplay
```

### iOS — physical Apple TV
Device: **Entertainment Room**, id `9D45582F-267C-54D8-B93A-A414BAC7BBF4`.
Signing is automatic, dev team `8HFHML5FGG`.

```bash
cd ~/dev/quietplay/ios/QuietPlay
xcodebuild -project QuietPlay.xcodeproj -scheme QuietPlay -configuration Debug \
  -destination 'platform=tvOS,id=9D45582F-267C-54D8-B93A-A414BAC7BBF4' \
  -derivedDataPath build-device -allowProvisioningUpdates build

xcrun devicectl device install app --device 9D45582F-267C-54D8-B93A-A414BAC7BBF4 \
  build-device/Build/Products/Debug-appletvos/QuietPlay.app
```

`devicectl` prints a noisy `"No provider was found"` warning before
success — harmless, ignore it. Check the `databaseSequenceNumber` bumps
to confirm LaunchServices actually re-registered the bundle.

## Key file map — "where do I go when…"

| When you want to change… | Go to |
|---|---|
| Playback state, overlays, seek, auto-advance | `ios/.../AppState.swift` |
| The video screen (pause card, up-next, progress, retry) | `ios/.../StreamView.swift` |
| The library grid, favorites, continue-watching | `ios/.../LibraryView.swift` |
| Loading screen quips, spinner | `ios/.../LoadingView.swift` |
| Bedtime lock, break modal, "5 min left", BritishEmpty, Blobby | `ios/.../EasterEggs.swift` |
| Profile picker, first-launch QR setup | `ios/.../BootstrapViews.swift`, `ProfileSwitcher.swift` |
| Design tokens (colors, radii, font sizes) | `ios/.../Theme.swift`, `Motion.swift` |
| YouTube ID → stream URL | `server/src/routes/resolver.ts` + `ytdlp.ts` |
| `/library`, `/playable`, `/profiles` | `server/src/routes/client.ts` |
| Admin channel/profile CRUD | `server/src/routes/admin.ts` |
| Dashboard aggregates + insights | `server/src/routes/dashboard.ts` |
| Watch telemetry sink | `server/src/routes/events.ts` |
| Admin UI (single file) | `server/src/admin/index.html` |
| Keyword rules for channel categorisation | `server/src/categorize.ts` |
| Schema changes | `server/migrations/NNN_*.sql` |

## Conventions — do / don't

**Do**
- Write user-facing strings against `docs/voice.md`. Calm, dry, mildly
  British, no emojis, no apologies, no status codes.
- Use SF Symbols for glyphs (see `BreakModal` for the pattern).
- Keep overlays gated on `!app.isLoading` when they render text on top
  of the video — learned the hard way with the PausedCard/LoadingView
  collision (fixed in commit `b365064`).
- Persist kid-facing state (`PlaybackProgressStore`, `WatchedVideoStore`,
  `FavoritesStore`, `ChannelSeenStore`) via the existing stores — don't
  add new UserDefaults call sites.
- Use `formatPlaybackTime(_:)` in `StreamView.swift` for `m:ss` — don't
  reimplement.

**Don't**
- Don't add a search box, trending row, notification, view count, or
  history-based sort anywhere. See GR2/GR3 above.
- Don't add HTTP Basic auth back to `/admin`. LAN is the boundary
  (removed in commit `7af28e8`).
- Don't hardcode colors, spacings, or radii in views — use `Theme.Palette`,
  `Theme.Spacing`, `Theme.Radius`, `Theme.FontSize`.
- Don't use `AVPlayerViewController` — the custom `PlayerLayerView` with
  `StreamView` overlays is intentional. Switching would lose PausedCard,
  UpNextChip, the seek HUD, and the five-minute-warning toast.
- Don't write multi-paragraph Swift/TS comments. One short line max.
  Comment the *why*, not the *what*.

## Voice / copy

Before writing any user-visible string (error JSON, label, empty state,
loading quip, dashboard prose), read `docs/voice.md`. The voice is
"calm train guard at Crewe explaining the delay." If it sounds like a
Slack notification, rewrite it.

## Easter eggs

See `docs/easter-eggs.md` for the index — Mr. Blobby sighting odds,
goodnight rotation, break modal, British-rail loading quips, empty-state
rotations. Tune odds and copy there.

## Gotchas

- **Bedtime lock is simulator-bypassed** — `BedtimeLock.isActive()`
  returns false under `#if targetEnvironment(simulator)` so the app
  is demo-able at any hour. If you want to test the lock, build to the
  physical device.
- **Info.plist points at LAN IP** (`192.168.0.143:8787` as of writing).
  If the network changes, edit `ios/QuietPlay/QuietPlay/Info.plist`
  `QuietPlayAPIBaseURL` before a device build. The simulator uses the
  same value (it shares the Mac's network stack).
- **`yt-dlp` must be on PATH** of the server process. The LaunchAgent
  inherits login-shell PATH; if you add it via Homebrew after install,
  reload the agent with `launchctl kickstart -k`.
- **YouTube stream URLs + timedtext URLs are signed and expire.**
  Resolver caches them in Redis (OK: 4h, FAIL: 15m). Client resolves on
  each tap, no long-lived links.
- **Captions are not implemented.** If asked to add them: the work is
  ~1-2 days, use yt-dlp `--write-auto-subs --sub-format vtt --skip-download`,
  inject via AVMutableComposition on the client. Expire captions like
  streams. Decided against for now (2026-04-24).
- **Ingest filters Shorts** server-side via a HEAD check against
  `/shorts/`. Don't re-add Shorts to the client filter; it'll double-skip.

## Recent context

- `36fd1f0` (2026-04-23) — copy pass + polish wins (voice, retry
  cooldown, Blobby tone-down, PausedCard dedup, Postgres startup ping,
  dashboard insight sentences). Live on sim + Apple TV.
- `7af28e8` (2026-04-23) — dropped HTTP Basic auth from `/admin/`.
- `b365064` (2026-04-23) — telemetry, break modal, auto-advance,
  categories, recommended flag, caching, goodnight rotation.

## Out-of-scope reference files (not in this repo)

- The v2 PRD (origin of the Golden Rules) lives outside the repo — if
  the user references "§14 non-goals" or "the 7 Golden Rules", they mean
  that document. Don't invent content for it.

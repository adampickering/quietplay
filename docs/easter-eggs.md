# Easter eggs

Hidden moments in QuietPlay. All live in `ios/QuietPlay/QuietPlay/EasterEggs.swift`.
Logged here so future-you remembers what's in there and future-Henry
doesn't accidentally spoil everything by grepping the source.

## Mr. Blobby sighting

- **Where:** `BlobbySighting` — mounted at the bottom of `LibraryView`.
- **Odds:** 1 in 2000 cold launches.
- **What:** A soft pink-and-yellow-spotted dot drifts across the
  bottom-left of the library over 1.8 seconds, then vanishes.
- **Why:** Rare-enough-to-be-memorable, calm-enough-to-be-deniable.
- **Tunable:** `Int.random(in: 1...2000)` — lower the denominator to
  raise the odds. Don't make it so common it reads as a glitch.

## Rotating goodnight lock

- **Where:** `BedtimeLock`, active from 20:15 → 06:00 local (Saturdays 21:00).
- **What:** 10 funny subtitles and 10 sleepy SF Symbols, cycled
  deterministically by day-of-year. Same date always shows the same
  combo (no flicker across reboots), but tomorrow's different.
- **Tunable:** `goodnightSubtitles` and `goodnightSymbols` arrays.

## "5 minutes left" toast

- **Where:** `FiveMinutesLeftToast` + `FiveMinuteWarningStore`.
- **When:** Fires anywhere in the 20:10–20:15 window (20:55–21:00 Saturdays), once per evening.
- **What:** Small capsule in the top-right of the player. Ignores the
  remote, doesn't pause playback, fades after 8 seconds.

## Take-a-break modal

- **Where:** `BreakModal`, triggered by `WatchTimeTracker` at 2h
  cumulative daily playback.
- **What:** A kettle, a punchline, a dismiss button. 12 sayings
  rotate randomly per mount (not deterministic — the break modal
  appearing twice in a day with the same joke would feel broken).
- **Dismiss:** "Alright then" — the only bit of copy allowed to
  sound mildly defeated.

## Rare British rail quips in LoadingView

- **Where:** `LoadingView.quips`. Most quips are generic-silly ("Waking
  the video gnomes…"). A handful are deep railway: "Consulting the
  Railway Series…", "Wagons rolllll…", "Don't panic."
- **Cadence:** every 2.4s while the loading view is on screen.
- **Note:** British ones should stay a minority. If the mix feels too
  on-the-nose, dilute with more absurd generics.

## British empty-state copy

- **Where:** `BritishEmpty` enum — picks one line per day from
  `noVideos` and `noChannels` arrays.
- **Why a file of its own:** so "the platform is empty" can drift into
  "signal failure at the next station" on Tuesday without any view
  code caring.

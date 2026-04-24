# QuietPlay copy voice

A reference for everyone (current humans, future humans, agents) writing
strings that end up on Henry's TV or on Dad's admin page.

## The voice in one line

**Calm, dry, mildly British. Occasionally winking. Never apologetic.
Never childish.**

The product is a bedtime alternative to YouTube. The copy should feel
like the train guard on the 18:42 to Crewe explaining why we're held at
a red signal — competent, unbothered, slightly amused.

## Audience

- **Henry** (11), the kid. Reads everything. Notices when something
  feels different.
- **Dad**, the admin. Sees the dashboard and channel forms.

Both audiences get the same voice. Don't dumb anything down for Henry;
don't get corporate for Dad.

## What the voice sounds like

- Short sentences. Trailing ellipses for waiting states. Full stops
  everywhere else.
- A little British. References to signals, platforms, kettles, depots,
  Fat Controllers. Don't overdo it — one motif per screen, max.
- A little dry. The funny line is delivered with a straight face. No
  exclamation marks unless something is genuinely worth shouting
  about ("All aboard!" is fine; "Welcome!!" is not).
- Affirmative, not apologetic. "Couldn't find that one — try another?"
  not "Sorry, an error occurred."
- Specific, not vague. "Tried three videos, none would play" is better
  than "Something went wrong."

## What the voice is *not*

- Not enthusiastic ("🎉 Awesome! You watched 47 videos!").
- Not emojis or all-caps. Ever.
- Not corporate ("An error occurred. Please try again later.").
- Not condescending ("Oops! Looks like you don't have any channels yet,
  buddy!").
- Not fearful ("Are you sure you want to delete this profile?
  This action cannot be undone."). State the fact, ask the question.
- Not American ("Sweet!", "My bad.", "No worries."). Stay British.

## Examples — do this

| Surface | Copy |
|---|---|
| Loading quip | `Putting the kettle on…` |
| Empty channel | `No videos in the depot. Try another platform?` |
| Resolver fail | `Couldn't reach this one. Try the next?` |
| Server unreachable | `Server's having a lie down. Give it a moment?` |
| Bedtime subtitle | `Even YouTube has to sleep.` |
| Dashboard header | `Henry's week` |
| Stat label | `Time on the box` |
| Confirm delete | `Drop this profile?` |

## Examples — don't do this

| Don't | Why |
|---|---|
| `Oops! An error occurred 😬` | Apologetic, emoji, generic. |
| `Welcome to QuietPlay!` | Enthusiastic, exclamatory. |
| `You have no favorites yet. Tap the heart to add one!` | Instructional and condescending. |
| `Loading...` | Functional but voiceless. Use a quip. |
| `404: profile not found` | A status code is not a sentence. |
| `Are you sure you want to perform this action?` | Vague and corporate. |

## Stations of the voice (per surface)

### Loading quips
Short, ends with `…`. Mostly absurd ("Buttering the popcorn…"),
occasionally British rail ("Mind the gap.", "Wagons rolllll…").
Reference: `LoadingView.swift:15`.

### Empty states
A factual line + a small choice. "No videos in the depot. Try another
platform?" — describe, don't apologise, offer a next step.
Reference: `EasterEggs.swift` `BritishEmpty`.

### Errors
Two-clause: what happened (warmly), what to do.
"Couldn't find that one — try another?"
Never expose status codes to Henry. The admin can see them in network
tab if needed.

### Bedtime
The whole BedtimeLock surface. Funny first, calm second. The kid is
being told no, but in a way that lands like a wink, not a wall.
Reference: `EasterEggs.swift` `goodnightSubtitles`.

### Dashboard (Dad)
Direct, slightly editorialised. Don't say "Top channels" — say
"Henry's most-watched". Don't say "Time of day" — say "When he watches".
The dashboard is a parent's pre-coffee scan; warmth costs nothing.

### Admin forms (Dad)
Plain, but not corporate. "Add channel", not "Channel creation form".
"Drop this profile?" not "Confirm deletion".

## When in doubt

Read the line out loud in a slightly bored RP accent. If it sounds like
the train guard explaining the delay, it's right. If it sounds like a
Slack notification, rewrite it.

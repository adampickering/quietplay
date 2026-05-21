#!/usr/bin/env bash
#
# Install (or refresh) the QuietPlay user crontab entries:
#   - hourly ingest of YouTube RSS feeds
#   - weekly yt-dlp upgrade (Sundays 03:00)
#   - nightly Postgres backup (04:00)
#
# Safe to re-run; existing QuietPlay-prefixed lines are replaced, other
# lines in the user's crontab are left alone.
#
# Usage:
#   ./scripts/install-cron.sh

set -euo pipefail

REPO="${REPO:-/Users/adam/dev/quietplay}"
NPM="$(which npm)"
BREW="/usr/local/bin/brew"

if [[ -z "$NPM" ]]; then
  echo "npm not found on PATH" >&2
  exit 1
fi

BLOCK_TAG="# QuietPlay cron — managed by scripts/install-cron.sh"
BLOCK_END="# /QuietPlay cron"

# cron's default PATH excludes nvm and Homebrew, so the `npm` script
# (a `#!/usr/bin/env node` shebang) can't find node. Pin PATH to the
# dirs that own the binaries this block invokes.
NODE_BIN_DIR="$(dirname "$NPM")"
CRON_PATH="$NODE_BIN_DIR:/usr/local/bin:/usr/bin:/bin"

read -r -d '' BLOCK <<EOF || true
$BLOCK_TAG
PATH=$CRON_PATH
0 * * * * cd $REPO && $NPM run -w @quietplay/server ingest >> /tmp/quietplay-ingest.log 2>&1
0 3 * * 0 $BREW upgrade yt-dlp >> /tmp/quietplay-ytdlp-upgrade.log 2>&1
0 4 * * * $REPO/scripts/backup-postgres.sh >> /tmp/quietplay-backup.log 2>&1
$BLOCK_END
EOF

existing="$(crontab -l 2>/dev/null || true)"

# Strip any previous managed block so re-running replaces instead of
# duplicating.
filtered="$(printf '%s\n' "$existing" | awk -v tag="$BLOCK_TAG" -v endtag="$BLOCK_END" '
  $0 == tag { skip=1; next }
  $0 == endtag { skip=0; next }
  !skip
')"

{
  if [[ -n "$filtered" ]]; then
    printf '%s\n' "$filtered"
  fi
  printf '%s\n' "$BLOCK"
} | crontab -

echo "Installed QuietPlay cron:"
crontab -l | awk -v tag="$BLOCK_TAG" -v endtag="$BLOCK_END" '
  $0 == tag { inside=1 }
  inside { print }
  $0 == endtag { exit }
'

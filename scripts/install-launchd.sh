#!/usr/bin/env bash
# Install (or refresh) a LaunchAgent so the QuietPlay server starts
# automatically on Mac login and restarts itself if it crashes. Runs
# as the current user, no sudo, and leaves logs at /tmp so you can
# tail them.
#
# Usage:
#   scripts/install-launchd.sh           # install + load
#   scripts/install-launchd.sh uninstall # tear down

set -euo pipefail

LABEL="com.quietplay.server"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
REPO="${REPO:-/Users/adam/dev/quietplay}"
NPM="$(command -v npm || true)"
NODE_BIN_DIR="$(dirname "$(command -v node || echo /usr/local/bin/node)")"
LOG="/tmp/quietplay-server.log"

if [[ "${1:-install}" == "uninstall" ]]; then
  launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Uninstalled $LABEL."
  exit 0
fi

if [[ -z "$NPM" ]]; then
  echo "npm not found on PATH" >&2
  exit 1
fi

mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>WorkingDirectory</key>
    <string>$REPO</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>$NPM run -w @quietplay/server dev</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
        <key>Crashed</key>
        <true/>
    </dict>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$NODE_BIN_DIR:/usr/local/bin:/usr/bin:/bin</string>
        <key>NODE_ENV</key>
        <string>production</string>
    </dict>
</dict>
</plist>
PLIST_EOF

# Reload if already loaded
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || \
  launchctl unload "$PLIST" 2>/dev/null || true

launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || \
  launchctl load "$PLIST"

echo "Installed $LABEL."
echo "  plist: $PLIST"
echo "  log:   $LOG"
echo "  check: launchctl print gui/\$(id -u)/$LABEL | head"

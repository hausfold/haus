#!/bin/bash
# last_closed_app.sh — recorder for "reopen last closed app" (the browser ⌘⇧T
# analog, bound to the caps→z leader).
#
# Runs off macOS's front_app_switched event — the same cheap signal
# empty_workspace.sh uses. Each event records the frontmost app's pid + bundle
# id; on the NEXT event, if that pid is now dead the app was QUIT, so its bundle
# id is pushed onto a stack. reopen-last-app.sh (deployed by windows, bound to
# caps→z) pops the stack and `open -b`s the app back — press z again to walk
# further back, exactly like ⌘⇧T reopening successively older closed tabs.
#
# Non-drawing item, subscribed to front_app_switched in sketchybarrc. Frontmost
# is read via lsappinfo (≈8ms), not osascript (≈110ms) — this runs every event.

export PATH="/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

STATE=/tmp/haus_last_app.state     # "<pid>|<bundleid>" of last frontmost app
STACK=/tmp/haus_closed_apps.stack  # quit apps' bundle ids, most recent LAST
MAX=20                                   # cap the stack depth

# Frontmost app's pid + bundle id, the cheap way (mirrors empty_workspace.sh).
asn=$(lsappinfo front 2>/dev/null)
cur_pid=$(lsappinfo info -only pid "$asn" 2>/dev/null);      cur_pid=${cur_pid#\"pid\"=}
cur_bid=$(lsappinfo info -only bundleid "$asn" 2>/dev/null); cur_bid=${cur_bid#\"CFBundleIdentifier\"=}; cur_bid=${cur_bid#\"}; cur_bid=${cur_bid%\"}

# Read the previous frontmost, then record the current one for the next event.
prev=$(cat "$STATE" 2>/dev/null)
prev_pid=${prev%%|*}
prev_bid=${prev#*|}
printf '%s|%s' "$cur_pid" "$cur_bid" > "$STATE"

# Only a QUIT is interesting: previous frontmost recorded, had a bundle id, and
# is now dead. A plain app-switch (prev still alive) records nothing.
[ -n "$prev_pid" ] && [ -n "$prev_bid" ] || exit 0
kill -0 "$prev_pid" 2>/dev/null && exit 0

# Never stack the palette itself — its window comes and goes constantly.
case "$prev_bid" in *pounce*) exit 0 ;; esac

# Push it (skip if it's already on top), keeping the newest MAX.
[ "$prev_bid" = "$(tail -1 "$STACK" 2>/dev/null)" ] && exit 0
echo "$prev_bid" >> "$STACK"
tail -"$MAX" "$STACK" > "$STACK.t" 2>/dev/null && mv "$STACK.t" "$STACK"

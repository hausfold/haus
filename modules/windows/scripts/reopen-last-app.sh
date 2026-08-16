#!/bin/bash
# reopen-last-app.sh — the browser ⌘⇧T analog: reopen the most recently QUIT
# app. Bound to the caps→z leader (see aerospace.toml [mode.launch.binding]).
#
# The stack is maintained by bar's last_closed_app.sh plugin, which pushes a
# bundle id every time the frontmost app is quit. Here we pop the newest and
# relaunch it; pressing z again walks further back through the stack — exactly
# like ⌘⇧T reopening successively older closed tabs. Empty stack → no-op.

export PATH="/run/current-system/sw/bin:/usr/bin:/bin:$PATH"
set -u

STACK=/tmp/haus_closed_apps.stack

bid=$(tail -1 "$STACK" 2>/dev/null)
[ -n "$bid" ] || exit 0

# Pop it before relaunching. (Reopening makes the app frontmost, which fires
# front_app_switched — but that's a launch, not a quit, so the recorder won't
# re-push it.)
sed '$d' "$STACK" > "$STACK.t" 2>/dev/null && mv "$STACK.t" "$STACK"

open -b "$bid" 2>/dev/null || true

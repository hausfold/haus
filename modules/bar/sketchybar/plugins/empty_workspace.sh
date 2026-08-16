#!/bin/bash
# empty_workspace.sh — when a ⌘Q empties the focused workspace, pull back to the
# most recent non-empty workspace ("gravity").
#
# Why this lives in a SketchyBar plugin and not a keybinding: it runs off macOS's
# front_app_switched event, which fires on a ⌘Q (and on every workspace switch,
# which is how we cheaply keep a focused-workspace history without touching
# aerospace.toml).
#
# Detecting a quit (vs. a plain app-switch or visiting an already-empty space):
#   each event records the frontmost app's PID; on the next event, if that PID
#   is now dead (kill -0 fails), the previous app was QUIT. Only then do we act.
#   Frontmost is read via lsappinfo (≈8ms) rather than osascript/System Events
#   (≈110ms) — this runs on every event, so the cheap path matters.
#
#   A dead PID alone is NOT enough. Gravity must fire only for a workspace you
#   EMPTIED, never for one you deliberately navigated to that happens to be
#   empty — and once you're standing on it those look identical. The tell is the
#   focused workspace itself: a ⌘Q never moves you, so a real quit always has
#   focused == the workspace focused at the previous event. The leader's launch
#   path changes it — windows/scripts/launch.sh switches to the app's workspace
#   BEFORE `open -a`, so you sit on an empty space for the second the app takes
#   to start, and gravity used to yank you off it mid-launch. You landed on a
#   workspace you never asked for while macOS made the launching app frontmost:
#   the bar showed the right app name beside the wrong workspace. That desync is
#   what the quit-in-place guard below closes.
#
# There is no back-and-forth re-pointing here any more. <mod>⇥
# (workspace-back-and-forth) is retired — pounce's ⌘⇥ switcher is
# cross-workspace, so nothing can be stranded behind a single previous-workspace
# pointer the way it could before. Gravity is a single hop again, with no
# flicker through an intermediate workspace to fix that pointer up.
#
# Wired as a non-drawing item subscribed to front_app_switched in sketchybarrc.

export PATH="/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

AEROSPACE=/opt/homebrew/bin/aerospace

STATE=/tmp/sketchybar_empty_ws.state    # "<pid>|<name>" of last frontmost app
HIST=/tmp/sketchybar_empty_ws.hist      # focused-workspace history, most recent LAST
TOKEN=/tmp/sketchybar_empty_ws.token    # latest-event nonce; guards the fork
LOG=/tmp/sketchybar_empty_ws.log
DEBUG=0

log() { [ "$DEBUG" = 1 ] && echo "$(date '+%H:%M:%S') $*" >> "$LOG"; }

# Frontmost app's pid + name, the cheap way.
asn=$(lsappinfo front 2>/dev/null)
cur_pid=$(lsappinfo info -only pid "$asn" 2>/dev/null);   cur_pid=${cur_pid#\"pid\"=}
cur_name=$(lsappinfo info -only name "$asn" 2>/dev/null); cur_name=${cur_name#\"LSDisplayName\"=}; cur_name=${cur_name#\"}; cur_name=${cur_name%\"}

# Read the previous frontmost, then record the current one for the next event.
prev=$(cat "$STATE" 2>/dev/null)
prev_pid=${prev%%|*}
prev_name=${prev#*|}
printf '%s|%s' "$cur_pid" "$cur_name" > "$STATE"

# Record focused-workspace history (dedup consecutive, keep last 12). This is
# how we later pick the gravity target D — and, read BEFORE the append, where
# the previous event left us, which is the quit-in-place guard further down.
focused=$($AEROSPACE list-workspaces --focused 2>/dev/null)
prev_focused=$(tail -1 "$HIST" 2>/dev/null)
if [ -n "$focused" ] && [ "$focused" != "$prev_focused" ]; then
    echo "$focused" >> "$HIST"
    tail -12 "$HIST" > "$HIST.t" 2>/dev/null && mv "$HIST.t" "$HIST"
fi

log "event: prev=$prev cur=$cur_pid|$cur_name focused=$focused prev_focused=$prev_focused"

# Only a QUIT is interesting: previous frontmost recorded and now dead.
[ -n "$prev_pid" ] || { log "  no prev → skip"; exit 0; }
if kill -0 "$prev_pid" 2>/dev/null; then log "  prev alive → switch, skip"; exit 0; fi
case "$prev_name" in Pounce|pounce*) log "  prev is palette → skip"; exit 0 ;; esac
case "$cur_name"  in Pounce|pounce*) log "  cur is palette → skip";  exit 0 ;; esac

# ...and only a quit IN PLACE. If the focused workspace moved since the last
# event, you navigated here (a leader launch, a ⌘⇥ landing, a manual hop) and
# whatever died elsewhere is none of gravity's business. An empty workspace you
# chose is not one you emptied.
[ "$focused" = "$prev_focused" ] || { log "  moved '$prev_focused' → '$focused', not a quit in place → skip"; exit 0; }

log "  QUIT detected (prev '$prev_name' dead) → fork"

nonce="$cur_pid.$prev_pid"
echo "$nonce" > "$TOKEN"
(
    # Act the instant the window is reaped — tight poll, not a fixed sleep, so
    # there's no noticeable sit on the empty workspace. The last fetched
    # non-empty set is reused below, so this costs no extra AeroSpace calls.
    reaped=0
    for _ in $(seq 1 20); do
        nonempty=$($AEROSPACE list-workspaces --monitor all --empty no 2>/dev/null)
        grep -qx "$focused" <<<"$nonempty" || { reaped=1; break; }
        sleep 0.01
    done
    [ "$reaped" = 1 ] || { log "  [fork] '$focused' still has windows → skip"; exit 0; }
    [ "$(cat "$TOKEN" 2>/dev/null)" = "$nonce" ] || { log "  [fork] superseded → skip"; exit 0; }
    now=$($AEROSPACE list-workspaces --focused 2>/dev/null)
    [ "$now" = "$focused" ] || { log "  [fork] moved off '$focused' → skip"; exit 0; }

    # Candidates = non-empty workspaces (excluding the one we're leaving),
    # ordered most-relevant first: recent history, then any other populated
    # workspace. The target is the most recent — where you came from.
    ordered=()
    add() {
        local w=$1 c
        [ -z "$w" ] && return
        [ "$w" = "$focused" ] && return
        grep -qx "$w" <<<"$nonempty" || return
        for c in "${ordered[@]}"; do [ "$c" = "$w" ] && return; done
        ordered+=("$w")
    }
    while IFS= read -r ws; do add "$ws"; done < <(tail -r "$HIST" 2>/dev/null)
    for ws in $nonempty; do add "$ws"; done
    D=${ordered[0]}

    # Nothing populated anywhere — every workspace is empty, so there's nowhere
    # better to be. Stay put rather than hop for the sake of hopping.
    [ -n "$D" ] || { log "  [fork] no non-empty target → stay"; exit 0; }

    log "  [fork] gravity → $D"
    exec "$AEROSPACE" workspace "$D"
) &

exit 0

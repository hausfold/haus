#!/bin/bash
# empty_workspace.sh — when the focused workspace loses its last window, pull
# back to the most recent non-empty one ("gravity").
#
# Why this lives in a SketchyBar plugin and not a keybinding: AeroSpace has no
# hook for either thing that empties a workspace. The bar's event stream has
# both — front_app_switched for a ⌘Q, space_windows_change for a window that
# closed on its own — and aerospace_workspace_change keeps the "where am I"
# half honest between them.
#
# ── TWO ways a workspace empties, and they need different tells ──────────────
#
#   a QUIT       ⌘Q takes every window of an app at once. front_app_switched
#                fires; the detection is below.
#   a CLOSE      the last WINDOW on a page goes (⌘W, a ⌃D that ends a shell,
#                `zmx kill` from the bar) while the app lives on in other
#                windows elsewhere. NOTHING about the front app changes, so the
#                quit path never saw it — and a lane page is deliberately not
#                persistent, so what you were left standing on was a workspace
#                that no longer exists in any list, with nothing on it and no
#                chord that means "off". That is what space_windows_change is
#                subscribed for.
#
# The CLOSE tell is a transition rather than a state, and it has to be: an empty
# workspace you NAVIGATED to must not be pulled out from under you, and once you
# are standing on one the two look identical. So every event records whether the
# workspace under you had windows, and gravity fires only when a
# space_windows_change finds that the SAME workspace has just gone from having
# them to having none. Walking onto an empty page records `empty` and never
# transitions; walking onto a full one and closing its last window does.
#
# That is also why aerospace_workspace_change is in the subscription list: it is
# the only event that fires on every page walk, so it is what keeps the recorded
# workspace equal to the one you are actually on. Without it a page you reached
# without changing apps would still carry the PREVIOUS workspace's record, and
# the same-workspace guard would throw the close away.
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
# WHERE the hop lands: the family before the world. A workspace and its pages
# (T, T/<repo>, …) are one place split across screens, so emptying one member
# pulls back to the most recent POPULATED member of the same family — even a
# page never visited, which recency alone would rank last — and only when the
# whole family is empty does it fall back to the most recently populated
# workspace anywhere. Without that rule, closing the last lane on T/<repo>
# yanked you clean out of the T family while a sibling repo's lanes were still
# running one page over.
#
# Wired as a non-drawing item in sketchybarrc, subscribed to front_app_switched,
# space_windows_change and aerospace_workspace_change.

export PATH="/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

AEROSPACE=/opt/homebrew/bin/aerospace

STATE=/tmp/sketchybar_empty_ws.state    # "<pid>|<name>" of last frontmost app
SEEN=/tmp/sketchybar_empty_ws.seen      # "<workspace>|<1 if it had windows>", last event
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

log "event: sender=${SENDER:-none} prev=$prev cur=$cur_pid|$cur_name focused=$focused prev_focused=$prev_focused"

# ── did the workspace under you just lose its last window? ───────────────────
# `--empty no` never lists an empty workspace, so "is $focused in this list" IS
# the emptiness question — the same call and the same rule as the fork below and
# as windows/scripts/workspace-mru.sh's page test. One extra AeroSpace round
# trip (~4 ms) per event, which is what buys the transition the CLOSE tell needs.
# The `-n` guard is not tidiness: with no answer from AeroSpace at all `nonempty`
# is empty, a herestring of it is still ONE empty line, and `grep -qx ""` matches
# it — so an unanswered workspace would record itself as populated and the next
# close would read as a transition that never happened.
nonempty=$($AEROSPACE list-workspaces --monitor all --empty no 2>/dev/null)
now_full=0
[ -n "$focused" ] && [ -n "$nonempty" ] && grep -qxF "$focused" <<<"$nonempty" && now_full=1
seen=$(cat "$SEEN" 2>/dev/null)
seen_ws=${seen%%|*}
seen_full=${seen#*|}
[ -n "$focused" ] && printf '%s|%s' "$focused" "$now_full" > "$SEEN"

# Deliberately NOT gated on `SENDER = space_windows_change`, even though that is
# the event this tell was added for. Every event rewrites the record above, so a
# front_app_switched landing between the window closing and the
# space_windows_change — with AeroSpace already done reaping — would record
# `<ws>|0` and the real tell would then see "was already empty" and throw the
# close away. That ordering is ordinary (closing the last window on a page often
# yields frontmost to another app), and the miss is unrecoverable: there is no
# second close to catch. Firing from any sender costs nothing, because the
# TRANSITION is what is being tested, not the event — and a ⌘Q that reaches this
# line first simply fires the same fork the quit tell would have.
emptied=0
if [ -n "$focused" ] && [ "$focused" = "$seen_ws" ] &&
   [ "$seen_full" = "1" ] && [ "$now_full" = "0" ]; then
    emptied=1
fi

# The QUIT tell, as a function so the two triggers read as the two triggers
# rather than as one long chain of exits with a branch through the middle.
# Returns 0 when this event is a quit in place.
quit_in_place() {
    # Previous frontmost recorded and now dead.
    [ -n "$prev_pid" ] || { log "  no prev → skip"; return 1; }
    if kill -0 "$prev_pid" 2>/dev/null; then log "  prev alive → switch, skip"; return 1; fi
    case "$prev_name" in Pounce|pounce*) log "  prev is palette → skip"; return 1 ;; esac
    case "$cur_name"  in Pounce|pounce*) log "  cur is palette → skip";  return 1 ;; esac

    # ...and only a quit IN PLACE. If the focused workspace moved since the last
    # event, you navigated here (a leader launch, a ⌘⇥ landing, a manual hop) and
    # whatever died elsewhere is none of gravity's business. An empty workspace you
    # chose is not one you emptied.
    [ "$focused" = "$prev_focused" ] ||
        { log "  moved '$prev_focused' → '$focused', not a quit in place → skip"; return 1; }

    log "  QUIT detected (prev '$prev_name' dead) → fork"
    return 0
}

if [ "$emptied" = 1 ]; then
    log "  EMPTIED in place ('$focused' lost its last window) → fork"
else
    quit_in_place || exit 0
fi

nonce="$cur_pid.$prev_pid.${SENDER:-}"
echo "$nonce" > "$TOKEN"
(
    # Act the instant the window is reaped — tight poll, not a fixed sleep, so
    # there's no noticeable sit on the empty workspace. The last fetched
    # non-empty set is reused below, so this costs no extra AeroSpace calls.
    reaped=0
    for _ in $(seq 1 20); do
        # The CLOSE path already knows it is empty — the outer `nonempty` above
        # said so — so this costs it one round trip and breaks on the first
        # pass. The QUIT path is the one that has to wait for the reap.
        nonempty=$($AEROSPACE list-workspaces --monitor all --empty no 2>/dev/null)
        grep -qxF "$focused" <<<"$nonempty" || { reaped=1; break; }
        sleep 0.01
    done
    [ "$reaped" = 1 ] || { log "  [fork] '$focused' still has windows → skip"; exit 0; }
    [ "$(cat "$TOKEN" 2>/dev/null)" = "$nonce" ] || { log "  [fork] superseded → skip"; exit 0; }
    now=$($AEROSPACE list-workspaces --focused 2>/dev/null)
    [ "$now" = "$focused" ] || { log "  [fork] moved off '$focused' → skip"; exit 0; }

    # Candidates = non-empty workspaces (excluding the one we're leaving),
    # ordered most-relevant first: recent history, then any other populated
    # workspace.
    ordered=()
    add() {
        local w=$1 c
        [ -z "$w" ] && return
        [ "$w" = "$focused" ] && return
        grep -qxF "$w" <<<"$nonempty" || return
        for c in "${ordered[@]}"; do [ "$c" = "$w" ] && return; done
        ordered+=("$w")
    }
    while IFS= read -r ws; do add "$ws"; done < <(tail -r "$HIST" 2>/dev/null)
    for ws in $nonempty; do add "$ws"; done

    # Gravity stays in the family first. Emptying T/<repo> while the T family
    # still has populated members must land on the most recent of THEM — a
    # sibling page from the history, or one you never visited from the
    # nonempty sweep — and only fall back to plain recency once the whole
    # family is empty. `ordered` already runs history-then-anything, so the
    # family pick is just its first member with the same base.
    D=
    base=${focused%%/*}
    for w in "${ordered[@]}"; do
        case "$w" in "$base" | "$base"/*) D=$w; break ;; esac
    done
    [ -n "$D" ] || D=${ordered[0]}

    # Nothing populated anywhere — every workspace is empty, so there's nowhere
    # better to be. Stay put rather than hop for the sake of hopping.
    [ -n "$D" ] || { log "  [fork] no non-empty target → stay"; exit 0; }

    log "  [fork] gravity → $D"
    exec "$AEROSPACE" workspace "$D"
) &

exit 0

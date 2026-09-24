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
#   an EVICTION the last window goes AND macOS takes you with it. A lane is its
#                own Ghostty process, so ⌃C out of the agent ends the shell,
#                Ghostty quits (quit-after-last-window-closed), macOS activates
#                the next app — the browser, say — and AeroSpace follows that
#                app to ITS workspace before this script sees an event. Both
#                tells above key on standing where the window died, so both
#                read the hop as navigation and let it stand: tabbing through
#                T/<repo> pages, you closed one and were dropped in the browser.
#                The tell is below; the fork then decides whether macOS's pick
#                stands.
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

# Both overridable for test/empty-workspace.bats, which stubs the tiler.
AEROSPACE=${EMPTY_WS_AEROSPACE:-/opt/homebrew/bin/aerospace}
DIR=${EMPTY_WS_DIR:-/tmp}

STATE=$DIR/sketchybar_empty_ws.state    # "<pid>|<name>" of last frontmost app
SEEN=$DIR/sketchybar_empty_ws.seen      # "<workspace>|<1 if it had windows>|<focused window id>", last event
HIST=$DIR/sketchybar_empty_ws.hist      # focused-workspace history, most recent LAST
TOKEN=$DIR/sketchybar_empty_ws.token    # latest-event nonce; guards the fork
LOG=$DIR/sketchybar_empty_ws.log
DEBUG=0

log() { [ "$DEBUG" = 1 ] && echo "$(date '+%H:%M:%S') $*" >> "$LOG"; }

# Frontmost app's pid + name, the cheap way.
asn=$(lsappinfo front 2>/dev/null)
cur_pid=$(lsappinfo info -only pid "$asn" 2>/dev/null | sed -n -e 's/^"pid"=\([0-9]*\).*/\1/p' -e 's/.*[[:space:]]pid = \([0-9]*\).*/\1/p')
cur_name=$(lsappinfo info -only name "$asn" 2>/dev/null | sed -n -e 's/.*"LSDisplayName"="\([^"]*\)".*/\1/p' -e '1s/^"\([^"]*\)" ASN:.*/\1/p')

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
# The focused window's id is what tells a window that CLOSED from one that was
# thrown elsewhere, for the eviction tell below. Empty on an empty workspace.
now_wid=$($AEROSPACE list-windows --focused --format '%{window-id}' 2>/dev/null)
IFS='|' read -r seen_ws seen_full seen_wid < "$SEEN" 2>/dev/null
[ -n "$focused" ] && printf '%s|%s|%s' "$focused" "$now_full" "$now_wid" > "$SEEN"

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
# `leaving` is the workspace that emptied — where gravity pulls AWAY from.
emptied=0
leaving=$focused
if [ -n "$focused" ] && [ "$focused" = "$seen_ws" ] &&
   [ "$seen_full" = "1" ] && [ "$now_full" = "0" ]; then
    emptied=1
fi

# The EVICTION tell: we are somewhere else now, the workspace we were on had
# windows and has none, and the window that was focused there no longer exists.
# That last clause is what separates it from a throw-and-follow (leader ⇧digit),
# which also leaves the old workspace empty — but the window survives, on the
# workspace you followed it to. Only this branch pays for list-windows --all.
evicted=0
if [ "$emptied" = 0 ] && [ -n "$focused" ] && [ -n "$seen_ws" ] &&
   [ "$focused" != "$seen_ws" ] && [ "$seen_full" = "1" ] && [ -n "$seen_wid" ] &&
   [ -n "$nonempty" ] && ! grep -qxF "$seen_ws" <<<"$nonempty" &&
   ! $AEROSPACE list-windows --all --format '%{window-id}' 2>/dev/null | grep -qxF "$seen_wid"; then
    evicted=1
    leaving=$seen_ws
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
elif [ "$evicted" = 1 ]; then
    log "  EVICTED ('$leaving' lost its last window, macOS moved us to '$focused') → fork"
else
    quit_in_place || exit 0
fi

nonce="$cur_pid.$prev_pid.$leaving.${SENDER:-}"
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
        grep -qxF "$leaving" <<<"$nonempty" || { reaped=1; break; }
        sleep 0.01
    done
    [ "$reaped" = 1 ] || { log "  [fork] '$leaving' still has windows → skip"; exit 0; }
    [ "$(cat "$TOKEN" 2>/dev/null)" = "$nonce" ] || { log "  [fork] superseded → skip"; exit 0; }
    now=$($AEROSPACE list-workspaces --focused 2>/dev/null)

    # Candidates = non-empty workspaces (excluding the one we're leaving),
    # ordered most-relevant first: recent history, then any other populated
    # workspace.
    ordered=()
    add() {
        local w=$1 c
        [ -z "$w" ] && return
        [ "$w" = "$leaving" ] && return
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
    base=${leaving%%/*}
    for w in "${ordered[@]}"; do
        case "$w" in "$base" | "$base"/*) D=$w; break ;; esac
    done

    # Moved off already — macOS handed focus to the next app and AeroSpace
    # followed it (the eviction, or the same race landing inside this fork's
    # poll). Where macOS put you is as good as plain recency, so it stands
    # unless the family still has somewhere to be and you are not in it:
    # one hop back into the family, never a hop between two outsiders.
    if [ "$now" != "$leaving" ]; then
        case "$now" in "$base" | "$base"/*) log "  [fork] moved within the family to '$now' → stay"; exit 0 ;; esac
        [ -n "$D" ] || { log "  [fork] moved to '$now', family empty → stay"; exit 0; }
    fi
    [ -n "$D" ] || D=${ordered[0]}

    # Nothing populated anywhere — every workspace is empty, so there's nowhere
    # better to be. Stay put rather than hop for the sake of hopping.
    [ -n "$D" ] || { log "  [fork] no non-empty target → stay"; exit 0; }

    log "  [fork] gravity → $D"
    exec "$AEROSPACE" workspace "$D"
) &

exit 0

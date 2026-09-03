#!/usr/bin/env bash
# fullscreen-toggle.sh — the ON take for an AeroSpace window, and the whole
# body of <mod>f behind it.
#
#   fullscreen-toggle.sh               the <mod>f binding: toggle the FOCUSED window
#   fullscreen-toggle.sh on <id>       take the ON side for one window, by id
#
# The second form is why this file has an argument at all: there is ONE
# fullscreen-ON rule on the machine and it is this one. terminal's
# scripts/raise-session.sh --fullscreen calls it when a lane's trill fin is
# clicked, so the agent that asked for you is the window in FRONT of you rather
# than one of five on a page found by its solid cursor. It calls this rather
# than spelling `aerospace fullscreen` for itself because the three rules below
# are the windows room's, and a second copy of them in another room is a second
# copy to drift.
#
# AeroSpace's `fullscreen` is a MODE with no other tell of its own: the window
# fills the workspace, its siblings vanish, and nothing says they still exist.
#
# The guard: toggling ON with a solo window is a visual no-op — the window
# already fills the workspace — but it still arms `window-is-fullscreen`,
# which is a trap deferred. The NEXT window to open on this workspace is
# hidden behind this one, and the bar spends the whole time in between
# painting the fullscreen glyph over a mode that meant nothing. The OFF take
# is always allowed: a window left flagged after its siblings closed must
# still have a way back.
#
# <mod>f is not the only way back out, and that is what makes arriving
# fullscreen cheap. AeroSpace's own commands page: "Switching to a different
# tiling window within the same workspace while the current focused window is
# in fullscreen mode results in the fullscreen window exiting fullscreen
# mode." So a page you land on fullscreen returns the moment you go to any
# window on it. It is also the sharpest reason for the guard: a page with no
# sibling to switch to has no way out but the chord.
#
# The bar notify rides along only when the state actually changed — the same
# shape the two-command binding had before the guard, answered by
# `--fail-if-noop` rather than a second query. aerospace-notify.sh wakes the
# bar's aerospace watcher (aerospace_lib.sh); the watcher polls too, so
# dropping it costs latency, not the indicator.

set -euo pipefail

# HAUS_AEROSPACE_BIN is the test seam, not a knob: test/fullscreen-take.bats
# hands this a recorder, because a PATH stub would lose to the absolute path a
# GUI-spawned script has to carry.
AP="${HAUS_AEROSPACE_BIN:-/opt/homebrew/bin/aerospace}"
NOTIFY="$HOME/.config/sketchybar/aerospace-notify.sh"

notify() {
    [ -x "$NOTIFY" ] && "$NOTIFY" fullscreen >/dev/null 2>&1 &
}

# The ON take, for one window by id — the guard, the mode and the poke.
take_on() {
    local id="$1" ws count
    # The window's OWN page, never the focused one. The caller may be acting on
    # a window it has just raised, and a raise that did not land would other-
    # wise be counted against whatever page WAS in front — an off-by-one page
    # with no symptom but a mode armed somewhere you are not. Ids are digits by
    # construction, so a sed is the whole parse.
    ws=$("$AP" list-windows --all --format '%{window-id}|%{workspace}' 2>/dev/null |
        sed -n "s/^$id|//p" | head -1) || ws=""
    [ -n "$ws" ] || return 0
    # Toggle-ON: only with company, per the guard above.
    count=$("$AP" list-windows --workspace "$ws" --count 2>/dev/null || echo 0)
    [ "${count:-0}" -gt 1 ] || return 0
    # `on`, never the bare toggle: a caller asking for fullscreen twice (two
    # clicks on the same lane's fin) must not get the OFF take on the second.
    "$AP" fullscreen on --window-id "$id" --fail-if-noop >/dev/null 2>&1 || return 0
    notify
    return 0
}

# ── `on <window-id>`: the ON take alone, for a window the caller names ───────
if [ "${1:-}" = on ]; then
    id="${2:-}"
    # A window id is digits. Anything else is a bug in the caller rather than
    # an input, so decline it instead of escaping it into the sed above.
    case "$id" in
        '' | *[!0-9]*) exit 0 ;;
    esac
    take_on "$id"
    exit 0
fi

# ── no arguments: the <mod>f binding ────────────────────────────────────────
# One listing for both halves of the question — which window is focused, and is
# it already in the mode.
foc=$("$AP" list-windows --focused --format '%{window-id}|%{window-is-fullscreen}' 2>/dev/null) || foc=""

# Already fullscreen → this press is the OFF take. Always allowed, siblings
# or no: the OFF take is how a window left flagged by a closed sibling
# escapes the mode.
if [ "${foc#*|}" = "true" ]; then
    "$AP" fullscreen
    notify
    exit 0
fi

id="${foc%%|*}"
[ -n "$id" ] || exit 0
take_on "$id"
exit 0

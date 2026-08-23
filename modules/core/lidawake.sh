#!/usr/bin/env bash
# lidawake — keep this Mac running with its lid shut, for exactly as long as an
# agent is actually mid-turn.
#
# WHY THIS EXISTS AND `awake` DOES NOT COVER IT. `awake` holds a `caffeinate`
# assertion, and caffeinate cannot cross a lid close — its own usage text says
# so. Lid-close sleep is a separate path in macOS, and the only supported lever
# over it is pmset's `disablesleep`, which is root-only. Hence a launchd DAEMON
# rather than another verb on `awake`, and hence no end-user CLI here: there is
# nothing to run by hand.
#
# THE SIGNAL. modules/bar/sketchybar/plugins/agents-hook.sh is already the one
# writer of agent state, for every client (Claude Code, Codex, OpenCode) and
# both shapes (a zmx lane, a desktop-app conversation). It now also drops one
# empty file per agent that is `working` into $LIDAWAKE_HOLD_DIR, and removes it
# on every other state. So this loop never discovers, polls or screen-scrapes
# anything: that directory being non-empty IS "work is happening right now".
#
# `waiting` deliberately does not hold. A permission prompt is blocked on a
# human, and the whole premise here is that the lid is shut and nobody is there.
#
# WHY THE HOOK WRITES AND ROOT ONLY READS. The hold directory lives in the
# user's home and is written by the user's own hook; this daemon is root and
# never writes into it. Privilege flows one way only, and the worst a stray hold
# file can cost you is one $LIDAWAKE_MAX_HOLD window (below).
#
# THREE FAILSAFES, because a daemon that died mid-hold would otherwise leave a
# Mac that never sleeps again and nothing on screen to say why:
#
#   1. It clears `disablesleep` on every start, before the loop. A crashed
#      predecessor, a rebuild, a reboot — all of them land here first.
#   2. $LIDAWAKE_MAX_HOLD caps ONE continuous hold. Past it the hold releases
#      and refuses to re-arm until the signal has actually cleared, so a hold
#      file that outlived its agent costs one window rather than forever.
#   3. It owns a marker at $LIDAWAKE_MARKER for as long as it is holding.
#      Activation reads that marker to undo a hold when the option is switched
#      off — see the lidAwake block in modules/core/default.nix. Without it,
#      `enable = false` would remove the only process that could put the key
#      back.
set -uo pipefail

HOLD_DIR="${LIDAWAKE_HOLD_DIR:?lidawake: LIDAWAKE_HOLD_DIR is required}"
MODE="${LIDAWAKE_MODE:-agents}"        # agents | always
REQUIRE_POWER="${LIDAWAKE_REQUIRE_POWER:-1}"
LINGER="${LIDAWAKE_LINGER:-300}"       # seconds
MAX_HOLD="${LIDAWAKE_MAX_HOLD:-28800}" # seconds; 0 = uncapped
INTERVAL="${LIDAWAKE_INTERVAL:-5}"     # seconds between polls
PMSET="${LIDAWAKE_PMSET_BIN:-/usr/bin/pmset}"
MARKER="${LIDAWAKE_MARKER:-/var/db/haus-lidawake.held}"

# ── test seams (test/lidawake.sh) ────────────────────────────────────────────
# A poll loop whose whole job is three time-dependent failsafes is exactly the
# kind of thing that rots untested, so the loop is drivable: a clock read from a
# file, a tick budget, and a hook the test uses to move its fake world forward
# between iterations. All three are unset in production, where now() is the real
# clock and the loop never ends.
NOW_FILE="${LIDAWAKE_NOW_FILE:-}"
TICKS="${LIDAWAKE_TICKS:-0}" # 0 = run forever
TICK_HOOK="${LIDAWAKE_TICK_HOOK:-}"

now() {
    if [ -n "$NOW_FILE" ]; then
        cat "$NOW_FILE"
    else
        /bin/date +%s
    fi
}

say() {
    printf '%s lidawake: %s\n' "$(/bin/date '+%Y-%m-%dT%H:%M:%S%z')" "$*"
}

# `pmset -g batt` says "Now drawing from 'AC Power'" or "'Battery Power'". A
# desktop Mac has no battery and reports AC, which is the right answer for it:
# no lid to close, and nothing to protect against.
on_ac() {
    "$PMSET" -g batt 2>/dev/null | grep -q "'AC Power'"
}

# The one privileged act in this file. Everything else is arithmetic.
apply() {
    if "$PMSET" -a disablesleep "$1" >/dev/null 2>&1; then
        if [ "$1" = 1 ]; then
            mkdir -p "$(dirname "$MARKER")" 2>/dev/null || true
            : >"$MARKER" 2>/dev/null || true
        else
            rm -f "$MARKER" 2>/dev/null || true
        fi
        return 0
    fi
    say "pmset -a disablesleep $1 was refused — the lid still sleeps this Mac."
    return 1
}

# Non-empty means at least one agent is mid-turn. `ls -A` rather than a glob, so
# a directory nothing has ever written to reads as empty instead of as a literal
# unexpanded pattern.
holds_present() {
    [ -n "$(ls -A "$HOLD_DIR" 2>/dev/null)" ]
}

held=0        # what we last successfully applied
held_since=0  # when this continuous hold began
last_hold=0   # last tick at which the raw signal said work is happening
capped=0      # MAX_HOLD tripped; refuse to re-arm until the signal clears
tick=0

trap 'apply 0; exit 0' TERM INT

# Failsafe 1. Never inherit a predecessor's hold — start from a known floor.
apply 0

say "watching $HOLD_DIR (mode=$MODE requirePower=$REQUIRE_POWER linger=${LINGER}s maxHold=${MAX_HOLD}s)"

while :; do
    [ -n "$TICK_HOOK" ] && "$TICK_HOOK" "$tick"
    t=$(now)

    # The raw signal, before any guard.
    raw=0
    case "$MODE" in
        always) raw=1 ;;
        *) holds_present && raw=1 ;;
    esac
    [ "$raw" = 1 ] && last_hold=$t

    want=$raw

    # Linger. The gap between two turns is seconds, and sleeping inside it would
    # end the run this exists to protect. It only ever EXTENDS a hold that is
    # already up; it can never start one.
    if [ "$want" = 0 ] && [ "$held" = 1 ] && [ "$LINGER" -gt 0 ] &&
        [ $((t - last_hold)) -lt "$LINGER" ]; then
        want=1
    fi

    # Failsafe 2. Cap one continuous hold, and LATCH until the signal clears —
    # without the latch a stuck hold file would re-arm on the very next tick and
    # the cap would mean nothing.
    if [ "$capped" = 1 ]; then
        if [ "$want" = 0 ]; then
            capped=0
        else
            want=0
        fi
    elif [ "$want" = 1 ] && [ "$held" = 1 ] && [ "$MAX_HOLD" -gt 0 ] &&
        [ $((t - held_since)) -ge "$MAX_HOLD" ]; then
        say "one hold has run ${MAX_HOLD}s — releasing it. Something is holding that should not be; the lid sleeps this Mac until the holds clear."
        capped=1
        want=0
    fi

    # On battery, a closed lid is a warm laptop in a bag with a draining battery
    # and no screen to say so. Refuse by default; the host can opt out.
    if [ "$want" = 1 ] && [ "$REQUIRE_POWER" = 1 ] && ! on_ac; then
        [ "$held" = 1 ] && say "unplugged — releasing (haus.power.lidAwake.requirePower)."
        want=0
    fi

    if [ "$want" = 1 ] && [ "$held" = 0 ]; then
        if apply 1; then
            held=1
            held_since=$t
            say "holding — a lid close no longer sleeps this Mac."
        fi
    elif [ "$want" = 0 ] && [ "$held" = 1 ]; then
        apply 0 && held=0
        say "released — a lid close sleeps this Mac again."
    fi

    tick=$((tick + 1))
    [ "$TICKS" -gt 0 ] && [ "$tick" -ge "$TICKS" ] && break
    [ "$INTERVAL" -gt 0 ] && sleep "$INTERVAL"
done

exit 0

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
#   1. It releases OUR hold on every start, before the loop — a crashed
#      predecessor, a rebuild, a reboot all land here first. Guarded on the
#      marker rather than run flat, because the activation block guards on it
#      too and for the same reason: this room's contract is that haus writes
#      only what the host asked for, and clearing a `disablesleep` somebody set
#      by hand would break it. (The window in which a crash could leave a hold
#      with no marker is the microseconds inside apply() between the pmset call
#      and the marker write. maxHold covers it.)
#   2. $LIDAWAKE_MAX_HOLD caps ONE continuous hold. Past it the hold releases
#      and refuses to re-arm until the signal has actually cleared, so a hold
#      file that outlived its agent costs one window rather than forever. It
#      does not apply to `while = "always"`, which HAS no signal that could get
#      stuck — capping there would just stop a closed-display Mac dead after
#      eight hours with nothing on screen to say why.
#   3. It owns a marker at $LIDAWAKE_MARKER for as long as it is holding.
#      Activation reads that marker to undo a hold when the option is switched
#      off — see the lidAwake block in modules/core/default.nix. Without it,
#      `enable = false` would remove the only process that could put the key
#      back.
#
# AND ONE THING THE HOLD FILES CANNOT DO FOR THEMSELVES. They are files, and a
# file outlives what it describes — the very reason agents-hook.sh's own header
# gives for deleting the /tmp state files it used to keep. A panic or a power
# cut with a lane mid-turn leaves one behind with nobody to remove it. So this
# daemon ignores any hold older than its own start: across a reboot every
# survivor is stale by construction. The cost is that a daemon restarted while
# agents really are working ignores them until their next turn re-touches the
# file, which fails toward sleeping rather than toward never sleeping, and is
# the right way round to be wrong.
set -uo pipefail

HOLD_DIR="${LIDAWAKE_HOLD_DIR:?lidawake: LIDAWAKE_HOLD_DIR is required}"
MODE="${LIDAWAKE_MODE:-agents}"        # agents | always
REQUIRE_POWER="${LIDAWAKE_REQUIRE_POWER:-1}"
LINGER="${LIDAWAKE_LINGER:-300}"       # seconds
MAX_HOLD="${LIDAWAKE_MAX_HOLD:-28800}" # seconds; 0 = uncapped
INTERVAL="${LIDAWAKE_INTERVAL:-5}"     # seconds between polls
PMSET="${LIDAWAKE_PMSET_BIN:-/usr/bin/pmset}"
MARKER="${LIDAWAKE_MARKER:-/var/db/haus-lidawake.held}"
# Root's own timestamp for "this run started", written beside the marker so the
# staleness test below has something to compare against that is not a clock.
STAMP="${LIDAWAKE_STAMP:-${MARKER}.started}"

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
#
# A refusal is retried on the next tick rather than being fatal — it is far more
# likely transient than permanent — but it is SAID only when it changes, because
# the alternative is a line every five seconds forever into a log with no
# rotation, which is how a disk fills up over a weekend.
last_refusal=""
apply() {
    if "$PMSET" -a disablesleep "$1" >/dev/null 2>&1; then
        if [ "$1" = 1 ]; then
            mkdir -p "$(dirname "$MARKER")" 2>/dev/null || true
            : >"$MARKER" 2>/dev/null || true
        else
            rm -f "$MARKER" 2>/dev/null || true
        fi
        last_refusal=""
        return 0
    fi
    if [ "$last_refusal" != "$1" ]; then
        say "pmset -a disablesleep $1 was refused — the lid still sleeps this Mac."
        last_refusal="$1"
    fi
    return 1
}

# At least one agent is mid-turn. Deliberately not "the directory is non-empty":
# a hold that predates this process survived something that should have cleared
# it (see the header), so it is evidence of a dead agent rather than a live one.
#
# `find -newer` against a file root stamped at startup, rather than reading each
# mtime and comparing numbers. Two reasons, and the second is why this is not the
# obvious `stat`: the comparison is against a real file rather than the test
# clock, so a fake clock cannot fake staleness away — and `stat`'s mtime flag is
# `-f %m` on BSD and `-c %Y` on GNU, which made the first version pass on this
# Mac and fail on CI's Linux with every hold silently unreadable. `find -newer`
# is the same word on both.
holds_present() {
    [ -n "$(find "$HOLD_DIR" -type f -newer "$STAMP" 2>/dev/null | head -n 1)" ]
}

held=0        # what we last successfully applied
held_since=0  # when this continuous hold began
last_hold=0   # last tick at which the raw signal said work is happening
capped=0      # MAX_HOLD tripped; refuse to re-arm until the signal clears
tick=0

trap 'apply 0; exit 0' TERM INT

# The floor for the staleness test above: a file, so `find -newer` can compare
# against it, and one this run owns rather than anything the hold directory or
# the fake clock could influence. Anything in $HOLD_DIR older than this survived
# something that should have removed it.
mkdir -p "$(dirname "$STAMP")" 2>/dev/null || true
: >"$STAMP"

# Failsafe 1. Never inherit a predecessor's hold. Only ours, though — the marker
# is what says so.
if [ -e "$MARKER" ]; then
    say "a previous run left a hold behind — releasing it before starting."
    apply 0
fi

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
    elif [ "$MODE" != always ] && [ "$want" = 1 ] && [ "$held" = 1 ] &&
        [ "$MAX_HOLD" -gt 0 ] && [ $((t - held_since)) -ge "$MAX_HOLD" ]; then
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

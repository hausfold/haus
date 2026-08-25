#!/usr/bin/env bash
# lidawake — keep this Mac awake for exactly as long as an agent is mid-turn.
#
# TWO LEVERS, one loop, chosen by $LIDAWAKE_DEPTH:
#
#   sleep   a `caffeinate -i` assertion. Stops IDLE sleep, which is what ends an
#           agent's run when the lid is OPEN and nobody has touched the keyboard
#           for ten minutes. Needs no privilege, so the AI room runs this one as
#           a per-user launchd AGENT (haus.ai.keepAwake).
#   lid     pmset's `disablesleep`. The deeper lever, and the only one that
#           crosses a lid close. Root-only, so core runs it as a launchd DAEMON
#           (haus.power.lidAwake).
#
# Both read the same signal and share every failsafe below, which is the whole
# reason they are one file rather than two: the interesting part here is not
# which key gets written but the three time-dependent guards around it, and a
# second copy of those would rot.
#
# WHY NEITHER IS A VERB ON `awake`. `awake` is a DURABLE, user-owned assertion —
# you asked for three hours, it survives a rebuild and a login. These are the
# opposite: nobody asked, they last exactly as long as the work does, and one of
# them is root. An agent-held keep-awake that stomped the coffee pill's state
# would be a worse bug than the sleep it prevented.
#
# The name is historical and stayed on purpose: `lidAwake` shipped first and the
# marker, the log and the daemon label are all spelled from it. It is the same
# loop at a shallower depth, not a second feature.
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
# never writes into it. Privilege flows one way only, and a stray hold file
# costs you one $LIDAWAKE_MAX_HOLD window (below) — one PER FILE, since the cap
# now lifts for a hold that appears after it. Whoever can write that directory
# can therefore hold the lid indefinitely by using a fresh name each window.
# That is the user themselves, holding their own machine awake, which is the
# whole feature; it is stated here so nobody reads failsafe 2 as a bound on the
# total rather than on a single hold.
#
# THREE FAILSAFES, because a daemon that died mid-hold would otherwise leave a
# Mac that never sleeps again and nothing on screen to say why. Failsafes 1 and
# 3 are `lid` business only: a `sleep` hold is a CHILD PROCESS started with
# `-w $$`, so it dies with this loop by construction and there is nothing for a
# successor or for activation to clean up. That asymmetry is the point of using
# a child rather than a written key for the shallow lever.
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
#      and latches off, so a hold file that outlived its agent costs one window
#      rather than forever. TWO things clear the latch, and the second is the
#      one that makes the promise true: the signal going away entirely, OR a
#      hold appearing that is NEWER than the moment we capped. Without the
#      second, a leaked file — which by definition nothing will ever remove —
#      would hold the latch down for good, and every real agent that started
#      work afterwards would find the feature silently dead. It does not apply
#      to `while = "always"`, which HAS no signal that could get stuck —
#      capping there would just stop a closed-display Mac dead after eight
#      hours with nothing on screen to say why.
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
DEPTH="${LIDAWAKE_DEPTH:-lid}"         # lid | sleep -- see the header
REQUIRE_POWER="${LIDAWAKE_REQUIRE_POWER:-1}"
LINGER="${LIDAWAKE_LINGER:-300}"       # seconds
MAX_HOLD="${LIDAWAKE_MAX_HOLD:-28800}" # seconds; 0 = uncapped
INTERVAL="${LIDAWAKE_INTERVAL:-5}"     # seconds between polls
PMSET="${LIDAWAKE_PMSET_BIN:-/usr/bin/pmset}"
CAFFEINATE="${LIDAWAKE_CAFFEINATE_BIN:-/usr/bin/caffeinate}"
MARKER="${LIDAWAKE_MARKER:-/var/db/haus-lidawake.held}"
# Root's own timestamp for "this run started", written beside the marker so the
# staleness test below has something to compare against that is not a clock.
STAMP="${LIDAWAKE_STAMP:-${MARKER}.started}"
# The same trick a second time, for the maxHold latch: stamped at the moment we
# cap, so "a hold newer than this" means an agent that started work AFTER the
# cap — the one thing that distinguishes real new work from the leaked file that
# tripped the cap in the first place.
#
# It is only ever trustworthy if it is THIS cap's stamp. A stale one — left by an
# earlier cap and not overwritten because the write failed — sits in the past, so
# every hold on disk is "newer" than it and the latch lifts on the very next
# tick: the cap would release and re-arm forever, which is the never-sleeps-again
# failure this whole file exists to prevent. So the latch consults `capstamp_ok`
# rather than the file's existence: it starts 0 every run and is set only by a
# write that actually succeeded, which is why no run can inherit a predecessor's
# stamp and why deleting one at startup would test nothing this does not already
# cover. A cap whose stamp did not land simply never lifts — the behaviour from
# before the latch had an escape hatch at all, and the safe direction to fail in.
CAPSTAMP="${LIDAWAKE_CAPSTAMP:-${MARKER}.capped}"

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
apply_lid() {
    if "$PMSET" -a disablesleep "$1" >/dev/null 2>&1; then
        if [ "$1" = 1 ]; then
            mkdir -p "$(dirname "$MARKER")" 2>/dev/null || true
            # `2>/dev/null` FIRST: redirections apply left to right, so with
            # it last the shell's "Permission denied" for $MARKER goes to the
            # still-live stderr — into the unrotated daemon log, every tick.
            : 2>/dev/null >"$MARKER" || true
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

# The shallow lever: one `caffeinate -i` child, alive for exactly as long as the
# hold is.
#
# `-w $$` is the whole reason this is a child process rather than a written key.
# caffeinate exits when the pid it is waiting on exits, so if this loop is
# SIGKILLed, crashes, or is torn down by a rebuild, the assertion goes with it —
# no marker to reconcile, no failsafe 1, no way to leave a Mac that will not idle
# sleep and nothing on screen to say why. The `lid` lever cannot work that way
# (`disablesleep` is a key macOS keeps until someone puts it back), which is
# exactly why that half needs the marker and this half does not.
#
# `-i` only: idle SYSTEM sleep. Not `-d` — an agent working is no reason to keep
# the screen lit, and a display that never sleeps is both a battery cost and the
# most visible way to get a feature like this switched off.
caff_pid=""
apply_sleep() {
    if [ "$1" = 1 ]; then
        caff_alive && return 0
        "$CAFFEINATE" -i -w $$ &
        caff_pid=$!
        return 0
    fi
    caff_alive && kill "$caff_pid" 2>/dev/null
    caff_pid=""
    return 0
}

# Is our assertion actually up? Checked once per tick rather than once at
# launch, and that is the whole design of this lever.
#
# `kill -0 $!` straight after `&` answers almost nothing: the fork exists before
# the exec has had a chance to fail, so a missing or non-executable caffeinate
# passes it and the loop then believes it is holding forever. Asking on every
# tick instead catches the same birth failure one tick later AND every later
# death — a caffeinate someone killed by hand, an OOM, a binary that exits on
# its own — with one predicate and no start-up special case. The cost is up to
# one $LIDAWAKE_INTERVAL of not holding, which is the same resolution the whole
# loop already runs at.
caff_alive() {
    [ -n "$caff_pid" ] && kill -0 "$caff_pid" 2>/dev/null
}

apply() {
    case "$DEPTH" in
        sleep) apply_sleep "$1" ;;
        *) apply_lid "$1" ;;
    esac
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
holds_newer_than() {
    [ -n "$(find "$HOLD_DIR" -type f -newer "$1" 2>/dev/null | head -n 1)" ]
}

holds_present() { holds_newer_than "$STAMP"; }

held=0        # what we last successfully applied
held_since=0  # when this continuous hold began
last_hold=0   # last tick at which the raw signal said work is happening
capped=0      # MAX_HOLD tripped; refuse to re-arm until the signal clears
capstamp_ok=0 # this cap's stamp landed, so "newer than the cap" is answerable
tick=0

trap 'apply 0; exit 0' TERM INT

# The floor for the staleness test above: a file, so `find -newer` can compare
# against it, and one this run owns rather than anything the hold directory or
# the fake clock could influence. Anything in $HOLD_DIR older than this survived
# something that should have removed it.
mkdir -p "$(dirname "$STAMP")" 2>/dev/null || true
: >"$STAMP"

# Failsafe 1. Never inherit a predecessor's hold. Only ours, though — the marker
# is what says so. `lid` only: a `sleep` hold was a child of the process that
# is already gone, so it went with it (see apply_sleep) and there is no marker
# to find.
if [ "$DEPTH" != sleep ] && [ -e "$MARKER" ]; then
    say "a previous run left a hold behind — releasing it before starting."
    apply 0
fi

say "watching $HOLD_DIR (depth=$DEPTH mode=$MODE requirePower=$REQUIRE_POWER linger=${LINGER}s maxHold=${MAX_HOLD}s)"

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
        elif [ "$capstamp_ok" = 1 ] && holds_newer_than "$CAPSTAMP"; then
            say "an agent started work after the cap — the latch is off and the lid can hold again."
            capped=0
        else
            want=0
        fi
    elif [ "$MODE" != always ] && [ "$want" = 1 ] && [ "$held" = 1 ] &&
        [ "$MAX_HOLD" -gt 0 ] && [ $((t - held_since)) -ge "$MAX_HOLD" ]; then
        say "one hold has run ${MAX_HOLD}s — releasing it. Something is holding that should not be; the lid sleeps this Mac until the holds clear or an agent starts a fresh turn."
        # See CAPSTAMP's own note: a cap whose stamp did not land must latch
        # HARDER, not softer, so the flag is what the clause above consults
        # rather than the file's existence.
        if : 2>/dev/null >"$CAPSTAMP"; then
            capstamp_ok=1
        else
            capstamp_ok=0
            say "could not write $CAPSTAMP — this cap holds until the holds clear."
        fi
        capped=1
        want=0
    fi

    # On battery, a closed lid is a warm laptop in a bag with a draining battery
    # and no screen to say so. Refuse by default; the host can opt out.
    #
    # `lid` only, and not for tidiness: the guard's whole argument is that
    # nothing can stop a closed laptop cooking in a bag, and at `sleep` depth
    # closing the lid still sleeps the Mac normally. Applying it there would
    # mean an unplugged laptop, lid open, on a desk in front of you, sleeping
    # mid-turn — refusing to protect the one case that is plainly safe.
    if [ "$DEPTH" != sleep ] && [ "$want" = 1 ] && [ "$REQUIRE_POWER" = 1 ] && ! on_ac; then
        [ "$held" = 1 ] && say "unplugged — releasing (haus.power.lidAwake.requirePower)."
        want=0
    fi

    # `sleep` depth only: believe the process table over our own bookkeeping. If
    # the child is gone while we think we are holding, we are not holding — say
    # so once and let the arm below start a fresh one on this very tick.
    if [ "$DEPTH" = sleep ] && [ "$held" = 1 ] && ! caff_alive; then
        say "the caffeinate assertion is gone — re-taking it."
        held=0
    fi

    if [ "$want" = 1 ] && [ "$held" = 0 ]; then
        if apply 1; then
            held=1
            held_since=$t
            if [ "$DEPTH" = sleep ]; then
                say "holding — idle sleep no longer ends a run (the lid still does)."
            else
                say "holding — a lid close no longer sleeps this Mac."
            fi
        fi
    elif [ "$want" = 0 ] && [ "$held" = 1 ]; then
        apply 0 && held=0
        if [ "$DEPTH" = sleep ]; then
            say "released — this Mac idle sleeps again."
        else
            say "released — a lid close sleeps this Mac again."
        fi
    fi

    tick=$((tick + 1))
    [ "$TICKS" -gt 0 ] && [ "$tick" -ge "$TICKS" ] && break
    # A string test, not `-gt 0`: the suite drives the shallow lever at a
    # fractional interval so a real child process has time to reach its first
    # line, and `[ 0.2 -gt 0 ]` is an error rather than a comparison.
    [ "$INTERVAL" != 0 ] && sleep "$INTERVAL"
done

exit 0

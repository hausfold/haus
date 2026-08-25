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
# Optional, and purely so something on screen can say a hold is up: a file that
# exists for exactly as long as this run is holding. Unset by default, because
# the LID depth already has one -- $MARKER is world-readable in /var/db and
# means precisely this -- and because root must never write into the user's
# home (see the privilege note above). It is the `sleep` depth, running as the
# USER, that has nothing to point a pill at.
#
# Deliberately not the same file as $MARKER even where both exist: the marker
# is a RECEIPT that activation acts on, and a reader that merely wants to draw
# a cup must not be able to make a rebuild think it has a key to put back.
HELD_FILE="${LIDAWAKE_HELD_FILE:-}"
# Run whenever a hold is taken or released, so a surface that draws $HELD_FILE
# can repaint at once instead of waiting out its own update interval — the bar's
# caffeinate pill ticks every 30s, and a cup that appears half a minute after
# the turn started reads as a broken pill rather than a slow one.
#
# Only the `sleep` depth is ever given one, and that is not a policy choice: the
# lid daemon is ROOT, and a user's SketchyBar mach service is not addressable
# from there. It is also why this is a command handed in rather than a
# `sketchybar` call written here — this file knows nothing about bars.
ON_CHANGE="${LIDAWAKE_ON_CHANGE:-}"

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
caff_started=-1 # the tick we last spawned on, for the birth-failure test below
apply_sleep() {
    if [ "$1" = 1 ]; then
        caff_alive && return 0
        # stderr to /dev/null for the reason the marker write has it: a
        # $CAFFEINATE that does not exist makes the shell print an exec error
        # here, every tick, into a log with no rotation.
        "$CAFFEINATE" -i -w $$ 2>/dev/null &
        caff_pid=$!
        caff_started=$tick
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
    local rc
    case "$DEPTH" in
        sleep)
            apply_sleep "$1"
            rc=$?
            ;;
        *)
            apply_lid "$1"
            rc=$?
            ;;
    esac
    # Only on a lever that actually moved. A receipt for a hold that was refused
    # would put a cup on the menu bar over a Mac that is going to sleep anyway,
    # which is worse than no cup at all.
    if [ "$rc" = 0 ] && [ -n "$HELD_FILE" ]; then
        if [ "$1" = 1 ]; then
            mkdir -p "$(dirname "$HELD_FILE")" 2>/dev/null || true
            : 2>/dev/null >"$HELD_FILE" || true
        else
            rm -f "$HELD_FILE" 2>/dev/null || true
        fi
        # After the file, never before: a reader woken by this must find the
        # world it is being told about. Backgrounded and muted because a bar
        # that is slow, wedged or absent is not this loop's problem to wait on.
        [ -n "$ON_CHANGE" ] && ("$ON_CHANGE" >/dev/null 2>&1 &)
    fi
    return $rc
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
hold_pending=0 # a `sleep` hold taken but not yet announced (see below)
tick=0

trap 'apply 0; exit 0' TERM INT

# The floor for the staleness test above: a file, so `find -newer` can compare
# against it, and one this run owns rather than anything the hold directory or
# the fake clock could influence. Anything in $HOLD_DIR older than this survived
# something that should have removed it.
mkdir -p "$(dirname "$STAMP")" 2>/dev/null || true
: >"$STAMP"

# A receipt outlives what it describes, exactly like a hold file does — a
# SIGKILL or a panic mid-hold leaves one behind, and the pill would then draw a
# cup forever over a Mac that sleeps perfectly well. Nothing this run has not
# taken itself is ours to claim, so start from nothing.
[ -n "$HELD_FILE" ] && rm -f "$HELD_FILE" 2>/dev/null

# Failsafe 1. Never inherit a predecessor's hold. Only ours, though — the marker
# is what says so. `lid` only: a `sleep` hold was a child of the process that
# is already gone, so it went with it (see apply_sleep) and there is no marker
# to find.
if [ "$DEPTH" != sleep ] && [ -e "$MARKER" ]; then
    say "a previous run left a hold behind — releasing it before starting."
    apply 0
fi

# requirePower is only reported where it is consulted — a banner naming a guard
# this depth ignores is how you spend an afternoon debugging the wrong thing.
if [ "$DEPTH" = sleep ]; then
    say "watching $HOLD_DIR (depth=$DEPTH mode=$MODE linger=${LINGER}s maxHold=${MAX_HOLD}s)"
else
    say "watching $HOLD_DIR (depth=$DEPTH mode=$MODE requirePower=$REQUIRE_POWER linger=${LINGER}s maxHold=${MAX_HOLD}s)"
fi

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
    # the child is gone while we think we are holding, we are not holding — let
    # the arm below start a fresh one on this very tick.
    #
    # WHICH of the two failures this is matters, because they want opposite
    # logging. A child that lived a while and then died is an event worth a line
    # each time. A child that never survives the tick it was born on is a
    # $CAFFEINATE that cannot run at all — and saying so every five seconds
    # forever is the same unrotated-log hazard apply_lid's `last_refusal` exists
    # to avoid, made worse by the arm below cheerfully announcing a hold it does
    # not have. So a birth failure is said once and the hold is never claimed.
    if [ "$DEPTH" = sleep ] && [ "$held" = 1 ] && ! caff_alive; then
        if [ $((tick - caff_started)) -le 1 ]; then
            if [ "$last_refusal" != birth ]; then
                say "$CAFFEINATE will not stay running — idle sleep still ends a run."
                last_refusal=birth
            fi
        else
            say "the caffeinate assertion is gone — re-taking it."
            last_refusal=""
        fi
        held=0
    fi

    # Announce a `sleep` hold only once its child has survived a tick.
    #
    # apply_sleep cannot answer "did it start" at the moment it spawns — the
    # fork exists before the exec has had a chance to fail — so saying "holding"
    # there would print a line that is false whenever $CAFFEINATE cannot run,
    # and print it on every one of the loop's re-arm attempts. Deferring by one
    # tick costs nothing (the assertion is up either way; only the log line
    # waits) and makes the log's word for it true.
    if [ "$DEPTH" = sleep ] && [ "$hold_pending" = 1 ] && [ "$held" = 1 ] && caff_alive; then
        say "holding — idle sleep no longer ends a run (the lid still does)."
        hold_pending=0
    fi

    if [ "$want" = 1 ] && [ "$held" = 0 ]; then
        if apply 1; then
            held=1
            held_since=$t
            # At `sleep` depth the announcement waits a tick — see hold_pending.
            if [ "$DEPTH" = sleep ]; then
                hold_pending=1
            else
                say "holding — a lid close no longer sleeps this Mac."
            fi
        fi
    elif [ "$want" = 0 ] && [ "$held" = 1 ]; then
        apply 0 && held=0
        hold_pending=0
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

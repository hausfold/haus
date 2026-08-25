#!/usr/bin/env bash
# lidawake — the daemon behind haus.power.lidAwake, driven tick by tick against
# a fake pmset and a fake clock.
#
# What is actually worth testing here is not "does it call pmset" but the three
# failsafes, every one of which is time-dependent and none of which you would
# ever notice failing: a Mac that quietly stopped sleeping looks exactly like a
# Mac you forgot to close. So each scenario asserts the WHOLE sequence of
# disablesleep writes, which is the only way to catch a hold that was taken
# twice, released twice, or never released at all.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIDAWAKE="$ROOT/modules/core/lidawake.sh"
TMP=$(/usr/bin/mktemp -d)
trap '/bin/rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/holds"

# `pmset -g batt` reads the fake power source; `pmset -a disablesleep N` records
# the write. Nothing else is called.
#
# A function rather than a one-off heredoc because scenario 7 swaps in a FAILING
# stub, and a suite where one scenario can quietly change the world every later
# scenario runs in is worse than no suite: `scenario` puts this one back.
good_pmset() {
    cat >"$TMP/bin/pmset" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    -g)
        if [ "${2:-}" = batt ]; then
            if [ "$(cat "$LIDAWAKE_TEST_POWER" 2>/dev/null)" = battery ]; then
                printf "Now drawing from 'Battery Power'\n"
            else
                printf "Now drawing from 'AC Power'\n"
            fi
        fi
        ;;
    -a)
        printf '%s\n' "${3:-}" >>"$LIDAWAKE_TEST_LOG"
        ;;
esac
EOF
    chmod +x "$TMP/bin/pmset"
}

# The `sleep` depth's lever: a stub that records its start, stays alive so the
# daemon's `kill -0` liveness check passes, and records its own death. Both
# halves matter — a caffeinate that exits immediately must NOT count as a hold.
good_caffeinate() {
    cat >"$TMP/bin/caffeinate" <<'EOF'
#!/usr/bin/env bash
# Detach the inherited stdio FIRST. This stub outlives the daemon whenever a
# scenario is testing a path that fails to release it, and a live child holding
# the suite's own stdout pipe open means whatever is reading that pipe never
# sees EOF — a broken assertion turns into a hang, which is the worst way for a
# test to fail. The real caffeinate has the same shape and does not care,
# because a daemon's stdout is a log file.
exec >/dev/null 2>&1
printf '1\n' >>"$LIDAWAKE_TEST_LOG"
trap 'printf "0\n" >>"$LIDAWAKE_TEST_LOG"; exit 0' TERM
# `& wait` rather than a bare sleep: bash runs a trap only between commands, so
# a foreground `sleep 3600` would swallow the TERM for an hour.
sleep 3600 &
wait
EOF
    chmod +x "$TMP/bin/caffeinate"
}

export LIDAWAKE_PMSET_BIN="$TMP/bin/pmset"
export LIDAWAKE_CAFFEINATE_BIN="$TMP/bin/caffeinate"
export LIDAWAKE_TEST_LOG="$TMP/log"
export LIDAWAKE_TEST_POWER="$TMP/power"
export LIDAWAKE_HOLD_DIR="$TMP/holds"
export LIDAWAKE_MARKER="$TMP/marker"
# The maxHold latch's own stamp. Exported as a seam like the rest rather than
# left to default off $LIDAWAKE_MARKER, so a scenario can put something
# UNWRITABLE at the path and drive the "this cap's stamp did not land" branch.
export LIDAWAKE_CAPSTAMP="$TMP/capstamp"
# The pill's receipt: exists for exactly as long as a hold does.
export LIDAWAKE_HELD_FILE="$TMP/held"
export LIDAWAKE_NOW_FILE="$TMP/clock"
export LIDAWAKE_TICK_HOOK="$TMP/hook"
export LIDAWAKE_INTERVAL=0

fail() {
    printf 'not ok - %s\n' "$*" >&2
    exit 1
}

# Every disablesleep write this run made, in order, space separated. A hold that
# was taken twice or never released shows up here and nowhere else.
writes() {
    tr '\n' ' ' <"$LIDAWAKE_TEST_LOG" | sed 's/ $//'
}

# The caffeinate stub records its release from its own TERM handler, which runs
# in a process the suite does not wait on — so unlike every pmset assertion,
# this one is not true the instant the daemon returns. Poll for it rather than
# sleeping a flat guess; it lands in milliseconds and the ceiling only exists so
# a genuine failure fails instead of hanging.
await_writes() {
    local i=0
    while [ "$i" -lt 100 ]; do
        [ "$(writes)" = "$1" ] && return 0
        sleep 0.05
        i=$((i + 1))
    done
    return 0
}

assert_writes() {
    local got
    got=$(writes)
    [ "$got" = "$1" ] || fail "$2: expected disablesleep writes '$1', got '$got'"
}

# Reset the fake world. The hook is the test's whole grip on the loop: lidawake
# runs it with the tick number before each iteration, so a scenario is written
# as a `case` over ticks rather than as several processes that would each forget
# the hold state the failsafes are made of.
scenario() {
    good_pmset
    good_caffeinate
    : >"$LIDAWAKE_TEST_LOG"
    /bin/rm -rf "$TMP/holds" "$LIDAWAKE_MARKER" "$LIDAWAKE_CAPSTAMP" "$LIDAWAKE_HELD_FILE"
    mkdir -p "$TMP/holds"
    printf 'ac\n' >"$LIDAWAKE_TEST_POWER"
    printf '1000\n' >"$LIDAWAKE_NOW_FILE"
}

hook() {
    printf '#!/usr/bin/env bash\n%s\n' "$1" >"$LIDAWAKE_TICK_HOOK"
    chmod +x "$LIDAWAKE_TICK_HOOK"
}

# ── 1. hold while an agent works, release when it stops ──────────────────────
# Two writes and no more: nothing is cleared on the way in, because no marker
# says a previous run left a hold behind (scenario 8 is the case where one does).
scenario
hook '
case "$1" in
  1) : >'"$TMP"'/holds/lane-a ;;
  3) rm -f '"$TMP"'/holds/lane-a ;;
esac'
LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=0 LIDAWAKE_REQUIRE_POWER=0 LIDAWAKE_TICKS=5 \
    bash "$LIDAWAKE" >/dev/null
assert_writes "1 0" "basic hold/release"
[ ! -e "$LIDAWAKE_MARKER" ] || fail "basic: marker survived the release"

# ── 2. two agents, and the hold outlives the first to finish ─────────────────
scenario
hook '
case "$1" in
  1) : >'"$TMP"'/holds/lane-a; : >'"$TMP"'/holds/lane-b ;;
  2) rm -f '"$TMP"'/holds/lane-a ;;
  4) rm -f '"$TMP"'/holds/lane-b ;;
esac'
LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=0 LIDAWAKE_REQUIRE_POWER=0 LIDAWAKE_TICKS=6 \
    bash "$LIDAWAKE" >/dev/null
assert_writes "1 0" "two agents"

# ── 3. linger carries the hold across the gap between turns ──────────────────
# The clock jumps rather than ticks: 100s after the agent stops is inside the
# 300s linger and must NOT release; 400s is outside it and must.
scenario
hook '
case "$1" in
  0) : >'"$TMP"'/holds/lane-a ;;
  1) rm -f '"$TMP"'/holds/lane-a; echo 1100 >'"$TMP"'/clock ;;
  2) echo 1400 >'"$TMP"'/clock ;;
esac'
LIDAWAKE_LINGER=300 LIDAWAKE_MAX_HOLD=0 LIDAWAKE_REQUIRE_POWER=0 LIDAWAKE_TICKS=3 \
    bash "$LIDAWAKE" >/dev/null
assert_writes "1 0" "linger"

# Same shape, but the next turn starts inside the linger: one unbroken hold, so
# exactly one write. This is the case linger exists for.
scenario
hook '
case "$1" in
  0) : >'"$TMP"'/holds/lane-a ;;
  1) rm -f '"$TMP"'/holds/lane-a; echo 1100 >'"$TMP"'/clock ;;
  2) : >'"$TMP"'/holds/lane-a; echo 1150 >'"$TMP"'/clock ;;
esac'
LIDAWAKE_LINGER=300 LIDAWAKE_MAX_HOLD=0 LIDAWAKE_REQUIRE_POWER=0 LIDAWAKE_TICKS=3 \
    bash "$LIDAWAKE" >/dev/null
assert_writes "1" "linger spans two turns"

# ── 4. requirePower ──────────────────────────────────────────────────────────
# On battery the hold is never taken, however hard the agents are working; plug
# in and it arms; unplug mid-hold and it releases. Unplugging is also how you
# say stop.
scenario
printf 'battery\n' >"$LIDAWAKE_TEST_POWER"
hook '
case "$1" in
  0) : >'"$TMP"'/holds/lane-a ;;
  2) echo ac >'"$TMP"'/power ;;
  4) echo battery >'"$TMP"'/power ;;
esac'
LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=0 LIDAWAKE_REQUIRE_POWER=1 LIDAWAKE_TICKS=6 \
    bash "$LIDAWAKE" >/dev/null
assert_writes "1 0" "requirePower"

# ── 5. maxHold caps one continuous hold, and latches ─────────────────────────
# The hold file never goes away — this is the stuck-client case. The cap must
# release, then REFUSE to re-arm while the same stale hold is still there, and
# only re-arm after the signal has genuinely cleared once.
scenario
hook '
case "$1" in
  0) : >'"$TMP"'/holds/stuck ;;
  1) echo 1700 >'"$TMP"'/clock ;;
  2) echo 1800 >'"$TMP"'/clock ;;
  3) rm -f '"$TMP"'/holds/stuck; echo 1900 >'"$TMP"'/clock ;;
  4) : >'"$TMP"'/holds/fresh; echo 2000 >'"$TMP"'/clock ;;
esac'
LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=600 LIDAWAKE_REQUIRE_POWER=0 LIDAWAKE_TICKS=5 \
    bash "$LIDAWAKE" >/dev/null
assert_writes "1 0 1" "maxHold caps, latches, then re-arms"

# ── 5b. the cap must not outlive the leak that tripped it ────────────────────
# The case scenario 5 cannot reach, and the one that actually happens: a lane
# force-killed mid-turn never gets its SessionEnd, so its hold file is never
# removed and the signal NEVER clears. Latching until it does would mean one
# leaked file kills the feature for good — the option's own promise is that a
# stuck hold "costs one window rather than forever". So a hold that appears
# AFTER the cap is a real agent starting real work, and it re-arms.
#
# Note the stuck file is still there at the end: the fix is not that it went
# away, it is that it stopped mattering.
scenario
hook '
case "$1" in
  0) : >'"$TMP"'/holds/stuck ;;
  1) echo 1700 >'"$TMP"'/clock ;;
  2) echo 1800 >'"$TMP"'/clock ;;
  3) : >'"$TMP"'/holds/a-real-agent; echo 1900 >'"$TMP"'/clock ;;
esac'
LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=600 LIDAWAKE_REQUIRE_POWER=0 LIDAWAKE_TICKS=5 \
    bash "$LIDAWAKE" >/dev/null
assert_writes "1 0 1" "a new agent re-arms a capped hold, leak or no leak"
[ -e "$TMP/holds/stuck" ] || fail "5b: the test's own premise went missing"

# ── 5c. a cap whose stamp did not land latches HARDER, not softer ────────────
# The failure mode 5b's escape hatch opens up, and the worst one in the file: if
# the cap stamp cannot be written, "a hold newer than the cap" has no floor to be
# newer THAN. Answer it wrong — by falling back to whatever stale stamp is on
# disk — and the cap lifts on the very next tick, releasing and re-arming
# forever, which is precisely the Mac-that-never-sleeps this daemon exists to
# prevent. So an unwritable stamp must mean the latch never lifts at all.
#
# A DIRECTORY at the stamp path, because it is the one way to make a write fail
# that reads the same on macOS and on CI's Linux — `chmod`/`chflags` differ, and
# the suite runs on both.
scenario
mkdir -p "$LIDAWAKE_CAPSTAMP"
hook '
case "$1" in
  0) : >'"$TMP"'/holds/stuck ;;
  1) echo 1700 >'"$TMP"'/clock ;;
  2) echo 1800 >'"$TMP"'/clock ;;
  3) : >'"$TMP"'/holds/a-real-agent; echo 1900 >'"$TMP"'/clock ;;
  4) echo 2600 >'"$TMP"'/clock ;;
esac'
LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=600 LIDAWAKE_REQUIRE_POWER=0 LIDAWAKE_TICKS=6 \
    bash "$LIDAWAKE" >/dev/null 2>&1
assert_writes "1 0" "an unwritable cap stamp keeps the latch down"


# ── 6. while = "always" ──────────────────────────────────────────────────────
# Plain closed-display mode: holds with an empty hold directory and never lets
# go, because there is no signal to wait for.
scenario
hook 'true'
LIDAWAKE_MODE=always LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=0 LIDAWAKE_REQUIRE_POWER=0 \
    LIDAWAKE_TICKS=3 bash "$LIDAWAKE" >/dev/null
assert_writes "1" "while=always"
[ -e "$LIDAWAKE_MARKER" ] || fail "while=always: no marker for activation to find"

# ── 7. a refused pmset is not recorded as a hold ─────────────────────────────
# If the write fails there is no hold, so nothing may claim one — otherwise the
# release would never fire and the marker would lie to activation.
scenario
cat >"$TMP/bin/pmset" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    -g) printf "Now drawing from 'AC Power'\n" ;;
    -a) printf '%s\n' "${3:-}" >>"$LIDAWAKE_TEST_LOG"; [ "${3:-}" != 1 ] ;;
esac
EOF
chmod +x "$TMP/bin/pmset"
hook '
case "$1" in
  0) : >'"$TMP"'/holds/lane-a ;;
esac'
LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=0 LIDAWAKE_REQUIRE_POWER=0 LIDAWAKE_TICKS=2 \
    bash "$LIDAWAKE" >/dev/null
assert_writes "1 1" "a refused write retries rather than pretending"
[ ! -e "$LIDAWAKE_MARKER" ] || fail "refused write left a marker behind"

# ── 8. failsafe 1 releases a previous run's hold, and only that ──────────────
# The marker is the whole question: with one, a crashed predecessor's hold is
# ours to clear; without one, a `disablesleep` somebody set by hand is not.
scenario
: >"$LIDAWAKE_MARKER"
hook 'true'
LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=0 LIDAWAKE_REQUIRE_POWER=0 LIDAWAKE_TICKS=1 \
    bash "$LIDAWAKE" >/dev/null
assert_writes "0" "a marked hold is released at startup"

scenario
hook 'true'
LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=0 LIDAWAKE_REQUIRE_POWER=0 LIDAWAKE_TICKS=1 \
    bash "$LIDAWAKE" >/dev/null
assert_writes "" "an unmarked disablesleep is left alone"

# ── 9. maxHold does not apply to while = "always" ────────────────────────────
# `always` has no signal that could get stuck, so there is nothing for the cap
# to protect against — and capping anyway would stop a docked, lid-shut Mac dead
# at hour eight with nothing on screen to say why. One write, and it stays.
scenario
hook '
case "$1" in
  1) echo 1700 >'"$TMP"'/clock ;;
  2) echo 9999 >'"$TMP"'/clock ;;
esac'
LIDAWAKE_MODE=always LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=600 LIDAWAKE_REQUIRE_POWER=0 \
    LIDAWAKE_TICKS=3 bash "$LIDAWAKE" >/dev/null
assert_writes "1" "while=always is never capped"

# ── 10. a hold that outlived a reboot is not a hold ──────────────────────────
# The failure this closes: a panic with a lane mid-turn leaves a file behind that
# nothing will ever remove, and the next boot would hold the lid open for a full
# maxHold window with no agent running at all. Real mtimes, so the fake clock
# cannot paper over it — an old file is ignored, a fresh one still counts.
# A stale hold ALONE must move nothing. This is the assertion that discriminates:
# with staleness off, the same run holds immediately, and the "stale + fresh"
# case below reads identically either way — so it cannot be the only one.
scenario
touch -t 202001010000 "$TMP/holds/from-before-the-reboot"
hook 'true'
LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=0 LIDAWAKE_REQUIRE_POWER=0 LIDAWAKE_TICKS=3 \
    bash "$LIDAWAKE" >/dev/null
assert_writes "" "a hold from before this daemon started is not a hold"
[ ! -e "$LIDAWAKE_MARKER" ] || fail "a stale hold took the lid"

# And a live agent arriving beside the stale one still works.
scenario
touch -t 202001010000 "$TMP/holds/from-before-the-reboot"
hook '
case "$1" in
  2) : >'"$TMP"'/holds/live-agent ;;
esac'
LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=0 LIDAWAKE_REQUIRE_POWER=0 LIDAWAKE_TICKS=4 \
    bash "$LIDAWAKE" >/dev/null
assert_writes "1" "a live hold beside a stale one still counts"


# ── 11. depth = sleep holds a caffeinate child instead of the lid ────────────
# The AI room's shallower lever (haus.ai.keepAwake = "idle"): it must take and
# release on exactly the same signal, touch pmset not at all, and leave NO
# marker — the marker exists so activation can undo a `disablesleep` the daemon
# is no longer around to put back, and a caffeinate child has already died with
# its parent by then. A marker here would make `enable = false` clear a key
# nobody set.
scenario
hook '
case "$1" in
  1) : >'"$TMP"'/holds/lane-a ;;
  3) rm -f '"$TMP"'/holds/lane-a ;;
esac'
LIDAWAKE_DEPTH=sleep LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=0 LIDAWAKE_REQUIRE_POWER=0 \
    LIDAWAKE_INTERVAL=0.2 LIDAWAKE_TICKS=5 bash "$LIDAWAKE" >/dev/null
await_writes "1 0"
assert_writes "1 0" "depth=sleep holds and releases a caffeinate child"
[ ! -e "$LIDAWAKE_MARKER" ] || fail "depth=sleep wrote a lid marker"

# ── 11b. the shallow lever must not touch the deep lever's marker ────────────
# Both depths can be running at once on a real machine — core's root daemon on
# the lid, the AI room's user agent on idle sleep — and the marker means "WE set
# disablesleep and activation may have to put it back". Only the root half can
# have set it. So failsafe 1 is gated on depth: a `sleep` run that found one and
# "released" it would clear root's receipt while the key stayed set, which is
# the one state that leaves a Mac not sleeping with nothing left to say why.
#
# Asserted on the log line rather than on the writes, because at this depth
# `apply 0` writes nothing either way — which is exactly how this could have
# been wrong and still looked right.
scenario
: >"$LIDAWAKE_MARKER"
hook 'true'
out=$(LIDAWAKE_DEPTH=sleep LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=0 LIDAWAKE_REQUIRE_POWER=0 \
    LIDAWAKE_TICKS=1 bash "$LIDAWAKE" 2>&1)
case "$out" in
    *"previous run left a hold"*)
        fail "depth=sleep claimed the lid daemon's marker as its own" ;;
esac
[ -e "$LIDAWAKE_MARKER" ] || fail "depth=sleep deleted the lid daemon's marker"

# ── 12. requirePower is a LID guard and must not reach the shallow lever ─────
# On battery at `lid` depth the hold is refused outright (scenario 4). At
# `sleep` depth the same refusal would mean an unplugged laptop, lid open, on
# the desk in front of you, sleeping mid-turn — the one case that is plainly
# safe. So requirePower stays ON here and the hold still happens.
scenario
printf 'battery\n' >"$LIDAWAKE_TEST_POWER"
hook '
case "$1" in
  1) : >'"$TMP"'/holds/lane-a ;;
  3) rm -f '"$TMP"'/holds/lane-a ;;
esac'
LIDAWAKE_DEPTH=sleep LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=0 LIDAWAKE_REQUIRE_POWER=1 \
    LIDAWAKE_INTERVAL=0.2 LIDAWAKE_TICKS=5 bash "$LIDAWAKE" >/dev/null
await_writes "1 0"
assert_writes "1 0" "depth=sleep holds on battery, where depth=lid would refuse"

# ── 13. a caffeinate that dies is noticed, every tick, not just at birth ─────
# The `sleep` twin of scenario 7, and the reason the liveness check is per-tick
# rather than once at launch: `kill -0 $!` straight after `&` sees the fork, not
# the failed exec, so a caffeinate that cannot run would otherwise be believed
# forever. Here the stub exits immediately and each tick re-takes it.
scenario
cat >"$TMP/bin/caffeinate" <<'EOF'
#!/usr/bin/env bash
printf '1\n' >>"$LIDAWAKE_TEST_LOG"
exit 1
EOF
chmod +x "$TMP/bin/caffeinate"
hook '
case "$1" in
  0) : >'"$TMP"'/holds/lane-a ;;
esac'
out=$(LIDAWAKE_DEPTH=sleep LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=0 LIDAWAKE_REQUIRE_POWER=0 \
    LIDAWAKE_INTERVAL=0.2 LIDAWAKE_TICKS=4 bash "$LIDAWAKE" 2>&1)
await_writes "1 1 1 1"
assert_writes "1 1 1 1" "a caffeinate that exits at once is re-taken, not believed"
# ...and says so ONCE, without ever claiming the hold it does not have. A loop
# that logged both lines per tick would put ~6 MB a day into a log with no
# rotation, and every line of it would be false.
[ "$(printf '%s\n' "$out" | grep -c "will not stay running")" = 1 ] ||
    fail "a lever that cannot start said so more than once"
case "$out" in
    *"holding — idle sleep"*)
        fail "claimed a hold while the lever was failing to start" ;;
esac

# ── 14. the receipt the bar draws from tracks the hold, at both depths ───────
# One file, present exactly while this run is holding. The bar's caffeinate pill
# stats it to draw its "agents are holding this" state, so the two failures that
# matter are a receipt left behind (a cup over a Mac that sleeps fine) and a
# receipt for a hold that was refused (the same, with no hold at all).
for depth in lid sleep; do
    scenario
    hook '
case "$1" in
  1) : >'"$TMP"'/holds/lane-a ;;
  3) rm -f '"$TMP"'/holds/lane-a ;;
esac'
    LIDAWAKE_DEPTH="$depth" LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=0 LIDAWAKE_REQUIRE_POWER=0 \
        LIDAWAKE_INTERVAL=0.2 LIDAWAKE_TICKS=3 bash "$LIDAWAKE" >/dev/null
    [ -e "$LIDAWAKE_HELD_FILE" ] || fail "$depth: no receipt while holding"

    scenario
    hook '
case "$1" in
  1) : >'"$TMP"'/holds/lane-a ;;
  3) rm -f '"$TMP"'/holds/lane-a ;;
esac'
    LIDAWAKE_DEPTH="$depth" LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=0 LIDAWAKE_REQUIRE_POWER=0 \
        LIDAWAKE_INTERVAL=0.2 LIDAWAKE_TICKS=5 bash "$LIDAWAKE" >/dev/null
    [ ! -e "$LIDAWAKE_HELD_FILE" ] || fail "$depth: receipt survived the release"
done

# A receipt from a run that was SIGKILLed mid-hold is not this run's to keep.
scenario
: >"$LIDAWAKE_HELD_FILE"
hook 'true'
LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=0 LIDAWAKE_REQUIRE_POWER=0 LIDAWAKE_TICKS=1 \
    bash "$LIDAWAKE" >/dev/null
[ ! -e "$LIDAWAKE_HELD_FILE" ] || fail "a previous run's receipt was inherited"

# A refused lever writes no receipt: scenario 7's failing pmset, asked again.
scenario
cat >"$TMP/bin/pmset" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    -g) printf "Now drawing from 'AC Power'\n" ;;
    -a) printf '%s\n' "${3:-}" >>"$LIDAWAKE_TEST_LOG"; [ "${3:-}" != 1 ] ;;
esac
EOF
chmod +x "$TMP/bin/pmset"
hook '
case "$1" in
  0) : >'"$TMP"'/holds/lane-a ;;
esac'
LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=0 LIDAWAKE_REQUIRE_POWER=0 LIDAWAKE_TICKS=2 \
    bash "$LIDAWAKE" >/dev/null
[ ! -e "$LIDAWAKE_HELD_FILE" ] || fail "a refused hold still wrote a receipt"

printf 'ok - lidawake hold lifecycle, linger, requirePower, the maxHold latch, and staleness\n'

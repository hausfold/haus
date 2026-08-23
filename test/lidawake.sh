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

export LIDAWAKE_PMSET_BIN="$TMP/bin/pmset"
export LIDAWAKE_TEST_LOG="$TMP/log"
export LIDAWAKE_TEST_POWER="$TMP/power"
export LIDAWAKE_HOLD_DIR="$TMP/holds"
export LIDAWAKE_MARKER="$TMP/marker"
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
    : >"$LIDAWAKE_TEST_LOG"
    /bin/rm -rf "$TMP/holds" "$LIDAWAKE_MARKER"
    mkdir -p "$TMP/holds"
    printf 'ac\n' >"$LIDAWAKE_TEST_POWER"
    printf '1000\n' >"$LIDAWAKE_NOW_FILE"
}

hook() {
    printf '#!/usr/bin/env bash\n%s\n' "$1" >"$LIDAWAKE_TICK_HOOK"
    chmod +x "$LIDAWAKE_TICK_HOOK"
}

# ── 1. hold while an agent works, release when it stops ──────────────────────
# The leading 0 is failsafe 1: the loop clears disablesleep before its first
# iteration, so it can never inherit a crashed predecessor's hold.
scenario
hook '
case "$1" in
  1) : >'"$TMP"'/holds/lane-a ;;
  3) rm -f '"$TMP"'/holds/lane-a ;;
esac'
LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=0 LIDAWAKE_REQUIRE_POWER=0 LIDAWAKE_TICKS=5 \
    bash "$LIDAWAKE" >/dev/null
assert_writes "0 1 0" "basic hold/release"
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
assert_writes "0 1 0" "two agents"

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
assert_writes "0 1 0" "linger"

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
assert_writes "0 1" "linger spans two turns"

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
assert_writes "0 1 0" "requirePower"

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
assert_writes "0 1 0 1" "maxHold caps, latches, then re-arms"

# ── 6. while = "always" ──────────────────────────────────────────────────────
# Plain closed-display mode: holds with an empty hold directory and never lets
# go, because there is no signal to wait for.
scenario
hook 'true'
LIDAWAKE_MODE=always LIDAWAKE_LINGER=0 LIDAWAKE_MAX_HOLD=0 LIDAWAKE_REQUIRE_POWER=0 \
    LIDAWAKE_TICKS=3 bash "$LIDAWAKE" >/dev/null
assert_writes "0 1" "while=always"
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
assert_writes "0 1 1" "a refused write retries rather than pretending"
[ ! -e "$LIDAWAKE_MARKER" ] || fail "refused write left a marker behind"

printf 'ok - lidawake hold lifecycle, linger, requirePower, and the maxHold latch\n'

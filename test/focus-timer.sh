#!/usr/bin/env bash
# focus 25 — the fuse, run rather than read.
#
# What this suite is about is the one rule the feature rests on: a timer ends
# ONLY the quiet it armed. Everything else about `focus 25` is a timestamp and
# a launchd job, and both of those are boring; the claim check is where a wrong
# answer costs you a Mac that un-quiets itself in the middle of something,
# which is the same failure the trigger daemon's suite exists to prevent one
# level up.
#
# What it can and cannot see. The DECISIONS are pure logic over a state dir and
# a clock, so they run anywhere — which is why the clock (FOCUS_NOW), launchd
# and the DND keypress are all stubbed below, and why nothing here ever sleeps.
# What it says nothing about is whether macOS actually goes quiet: that is the
# symbolic hotkey, felt by hand, and `focus doctor` on a real Mac.
#
# ⚠️ The engine is built by test/focus-engine.sh, which mirrors
# modules/focus/default.nix's substitutions and fails when the two drift.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/home"

# shellcheck source=test/focus-engine.sh
. "$ROOT/test/focus-engine.sh"

# A press that always SUCCEEDS, which is the opposite of what test/focus-auto.sh
# stubs and right for the opposite reason: that suite is about a tick surviving
# a press it cannot make, and this one is about what happens after a press that
# worked. `apply` writes the state file itself once the press returns, and
# `focus_state` falls back to that file with no pounce and no Assertions.json —
# so a stub that exits 0 is a whole working DND switch as far as the engine can
# tell.
cat >"$TMP/bin/osascript" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

# launchd, recorded rather than run. `focus 25` refuses outright when the
# kickstart fails, which is a real path (an unloaded job after a fresh install),
# so the stub can be told to fail.
cat >"$TMP/bin/launchctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${LAUNCHCTL_LOG:-/dev/null}"
[ -z "${FAKE_LAUNCHCTL_FAIL:-}" ] || exit 1
exit 0
EOF

# Only `-r <epoch>` is ours: it is the clock time in the confirmation line, and
# GNU date spells it as a file reference. The engine reads the clock through
# FOCUS_NOW here, never through this.
cat >"$TMP/bin/date" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    -r) printf '09:41\n' ;;
    *) exec /bin/date "$@" ;;
esac
EOF

chmod +x "$TMP/bin/"*

export HOME="$TMP/home"
export FOCUS_OSASCRIPT_BIN="$TMP/bin/osascript"
export FOCUS_LAUNCHCTL_BIN="$TMP/bin/launchctl"
export FOCUS_DATE_BIN="$TMP/bin/date"
export FOCUS_BAR_POKE_BIN="$TMP/bin/no-such-poke"
export LAUNCHCTL_LOG="$TMP/launchctl.log"

STATE="$HOME/.local/state/focus"
TIMER="$STATE/timer.json"

fail() {
    printf 'not ok - %s\n' "$*" >&2
    exit 1
}

ASSERTIONS=0
assert_eq() {
    ASSERTIONS=$((ASSERTIONS + 1))
    [ "$1" = "$2" ] || fail "${3:-expected} '$2', got '$1'"
}

assert_no_timer() {
    ASSERTIONS=$((ASSERTIONS + 1))
    [ ! -f "$TIMER" ] || fail "${1:-a fuse was left behind}"
}

# One scene, so the "a scene owns the Mac" arms have something to enter. `dnd`
# is false for the same reason test/focus-auto.sh's are: the DND leg is not
# what these arms are about, and a scene that takes quiet would move the very
# state the assertions read.
cat >"$TMP/scenes.json" <<'EOF'
{
  "recording": {
    "description": "camera on",
    "dnd": false, "preventSleep": false, "restorePreviousState": true,
    "apps": [], "closeApps": false, "audioInput": "", "hooks": [],
    "when": { "time": "", "days": [], "wifi": [], "power": "any", "displays": null }
  }
}
EOF
focus_build_engine "$ROOT/modules/focus/focus.sh" "$TMP/scenes.json" "$TMP/no-such-ui.sh" "$TMP/focus" \
    || exit 1

f() { "$TMP/focus" "$@" 2>/dev/null; }
quiet_now() { f status; }
entry_now() { /bin/cat "$STATE/quiet-entry" 2>/dev/null || echo 0; }
reset() { rm -rf "$STATE"; }

# ---------------------------------------------------------------------------
# 1. The whole feature in five lines: quiet now, quiet off at the end of it.
reset
FOCUS_NOW=1000 f 25
assert_eq "$(quiet_now)" on "focus 25 quiets the Mac:"
assert_eq "$(FOCUS_NOW=1000 f status --raw)" "$(printf 'on\t1500')" \
    "and the pill's face carries the countdown:"
assert_eq "$(FOCUS_NOW=1900 f status --raw)" "$(printf 'on\t600')" \
    "which shrinks with the clock:"
FOCUS_NOW=2500 f _timer
assert_eq "$(quiet_now)" off "and the fuse un-quiets at the end:"
assert_no_timer "the spent fuse is gone"

# 2. The launchd job is what sleeps it out, and it is kickstarted with -k so a
# second `focus 25` replaces the first rather than racing it.
grep -q 'kickstart -k gui/.*/com\.hausfold\.focus-timer' "$LAUNCHCTL_LOG" \
    || fail "the arm did not kickstart the timer job"
ASSERTIONS=$((ASSERTIONS + 1))

# 3. A fuse whose moment passed while the Mac was shut fires on the way back up.
# This is the agent's RunAtLoad, and it is why the timestamp is what gets
# written down rather than the sleeping process.
reset
FOCUS_NOW=1000 f 25
FOCUS_NOW=99999 f _timer
assert_eq "$(quiet_now)" off "an expiry slept through still ends the quiet:"

# ---------------------------------------------------------------------------
# 4. THE RULE. A quiet the fuse did not arm survives its expiry.
#
# Reached the way it is reached in life: something wrote the quiet state without
# going through a verb that drops the fuse — the trigger daemon leaving a scene,
# say — and then the Mac went quiet again from Control Center, which focus never
# sees at all. The second half of that sequence is an iPhone, so the counter is
# moved here rather than driven.
reset
FOCUS_NOW=1000 f 25
printf '%s\n' "$(($(entry_now) + 1))" >"$STATE/quiet-entry"
FOCUS_NOW=2500 f _timer
assert_eq "$(quiet_now)" on "a quiet the fuse did not arm is not ended by it:"
assert_no_timer "and the fuse forgets itself rather than waiting for another chance"

# 5. The same rule through the front door: turning quiet off and on again by
# hand leaves nothing for the fuse to burn.
reset
FOCUS_NOW=1000 f 25
FOCUS_NOW=1100 f off
assert_eq "$(quiet_now)" off "'focus off' ends the quiet:"
assert_no_timer "and takes the fuse with it"
FOCUS_NOW=1200 f on
FOCUS_NOW=2500 f _timer
assert_eq "$(quiet_now)" on "the quiet you switched back on is still on:"

# 6. A fuse over a quiet that is simply gone has nothing to end.
reset
FOCUS_NOW=1000 f 25
printf 'off\n' >"$STATE/state"
FOCUS_NOW=2500 f _timer
assert_no_timer "a fuse over a Mac that is no longer quiet drops itself"

# ---------------------------------------------------------------------------
# 7. A scene owns the whole state while it runs, so it ends the fuse — and the
# arm refuses rather than starting one underneath a scene.
reset
f scene recording
if FOCUS_NOW=1000 f 25; then fail "arming under a scene must refuse"; fi
ASSERTIONS=$((ASSERTIONS + 1))
assert_no_timer "and leave nothing behind"
f scene off

reset
FOCUS_NOW=1000 f 25
f scene recording
assert_no_timer "entering a scene ends the fuse"

# The claim's own scene check, for a scene entered by the trigger daemon rather
# than by a verb — that path never reaches the dispatcher's cancel.
reset
FOCUS_NOW=1000 f 25
printf 'recording\n' >"$STATE/scene"
assert_eq "$(FOCUS_NOW=1100 f status --raw)" "$(printf 'on\t0')" \
    "a fuse under a scene stops counting down:"
assert_no_timer "and is dropped on the read that noticed"

# ---------------------------------------------------------------------------
# 8. `focus timer off` is the one way to drop the countdown and STAY quiet.
reset
FOCUS_NOW=1000 f 25
FOCUS_NOW=1100 f timer off
assert_eq "$(quiet_now)" on "dropping the timer leaves the quiet alone:"
assert_no_timer "but the countdown is gone"
FOCUS_NOW=2500 f _timer
assert_eq "$(quiet_now)" on "and nothing comes back for it later:"

# 9. `focus timer` says what is left, rounded up so the last minute reads as one.
reset
FOCUS_NOW=1000 f 25
assert_eq "$(FOCUS_NOW=1000 f timer)" "quiet for 25m more" "the human face:"
assert_eq "$(FOCUS_NOW=2441 f timer)" "quiet for 1m more" "rounds up through the final minute:"
assert_eq "$(FOCUS_NOW=1000 f status --raw)" "$(printf 'on\t1500')" "and the machine face is seconds:"
f off
assert_eq "$(f timer)" "no timer" "with nothing armed:"
assert_eq "$(f status --raw)" "$(printf 'off\t0')" "and the machine face says so too:"

# ---------------------------------------------------------------------------
# 10. Durations. A bare number is MINUTES here, where `awake 3` is hours.
reset
FOCUS_NOW=0 f 25
assert_eq "$(FOCUS_NOW=0 f status --raw)" "$(printf 'on\t1500')" "25 is twenty-five minutes:"
FOCUS_NOW=0 f 25m
assert_eq "$(FOCUS_NOW=0 f status --raw)" "$(printf 'on\t1500')" "and so is 25m:"
FOCUS_NOW=0 f 90min
assert_eq "$(FOCUS_NOW=0 f status --raw)" "$(printf 'on\t5400')" "90min is ninety minutes:"
FOCUS_NOW=0 f 1h
assert_eq "$(FOCUS_NOW=0 f status --raw)" "$(printf 'on\t3600')" "1h is an hour:"
FOCUS_NOW=0 f 2hours
assert_eq "$(FOCUS_NOW=0 f status --raw)" "$(printf 'on\t7200')" "2hours is two:"
FOCUS_NOW=0 f 09m
assert_eq "$(FOCUS_NOW=0 f status --raw)" "$(printf 'on\t540')" "a leading zero is decimal, not octal:"

# A second arm replaces the first outright rather than adding to it.
FOCUS_NOW=0 f 25
FOCUS_NOW=0 f 60
assert_eq "$(FOCUS_NOW=0 f status --raw)" "$(printf 'on\t3600')" "the second arm replaces the first:"

# Everything that is not a duration falls through to the usage text, which is
# what keeps a typo'd verb readable instead of "unknown duration '--probe'".
reset
for bad in 0 abc 25x 1441 25h -5; do
    if f "$bad"; then fail "'$bad' was taken as a duration"; fi
    ASSERTIONS=$((ASSERTIONS + 1))
done
assert_eq "$(quiet_now)" off "and none of them quieted the Mac:"
# Captured rather than piped: the verb exits 64 and `pipefail` would hand that
# to the `||`, failing an assertion about text that is right there.
usage_out=$("$TMP/focus" nonsense 2>&1 || true)
printf '%s' "$usage_out" | grep -q 'focus <minutes>' \
    || fail "the usage text does not mention a duration"
ASSERTIONS=$((ASSERTIONS + 1))

# ---------------------------------------------------------------------------
# 11. No launchd job, no fuse. Refusing is the honest answer — the alternative
# is a countdown on the bar that nothing will ever act on — and the refusal
# says out loud that the Mac IS quiet, because by then it is.
reset
if FAKE_LAUNCHCTL_FAIL=1 FOCUS_NOW=1000 f 25; then
    fail "an unloadable timer job must refuse the arm"
fi
ASSERTIONS=$((ASSERTIONS + 1))
assert_no_timer "and leave no fuse nothing can burn"
assert_eq "$(quiet_now)" on "the quiet it had already turned on stays on:"
refusal=$(FAKE_LAUNCHCTL_FAIL=1 "$TMP/focus" 25 2>&1 || true)
printf '%s' "$refusal" | grep -q "'focus off' ends it" \
    || fail "the refusal does not say how to undo the quiet it left on"
ASSERTIONS=$((ASSERTIONS + 1))

printf 'ok - focus timer: %s assertions\n' "$ASSERTIONS"

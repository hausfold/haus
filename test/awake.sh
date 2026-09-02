#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
AWAKE="$ROOT/modules/core/awake.sh"

# The LIFECYCLE suite, and deliberately not the painter's — awake's prose paths
# draw through snug when one is reachable, and every exact-match assertion below
# is written against the plain sentence. Unset rather than left alone: this file
# is run straight off disk with whatever environment a caller has, and
# `.github/workflows/check.yml` exports HAUS_UI_SH for the render suites further
# down the same job. Today this step happens to run above that export; that is
# ordering, not a contract, and a reordered workflow would turn every assertion
# here red with a mark it never asked about. The painted shapes are
# test/awake-ui.bats's subject.
unset HAUS_UI_SH || true
TMP=$(/usr/bin/mktemp -d)
trap '/bin/rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/home"

cat >"$TMP/bin/launchctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$AWAKE_TEST_LOG"
[ "${AWAKE_LAUNCHCTL_FAIL:-0}" = 0 ]
EOF

cat >"$TMP/bin/caffeinate" <<'EOF'
#!/usr/bin/env bash
printf 'caffeinate %s\n' "$*" >>"$AWAKE_TEST_LOG"
while [ -n "${AWAKE_TEST_GATE:-}" ] && [ -e "$AWAKE_TEST_GATE" ]; do
    sleep 0.05
done
EOF

cat >"$TMP/bin/sketchybar" <<'EOF'
#!/usr/bin/env bash
printf 'sketchybar %s\n' "$*" >>"$AWAKE_TEST_LOG"
EOF

# bar's optional second bar (haus.bar.bottom.enable) is a second SketchyBar
# instance under a second name, and `awake` pokes BOTH — so it needs a stub too.
# Without one the default path is /run/current-system/sw/bin/bar-bottom, which
# on a dev Mac running that bar means this suite fires a real --trigger at the
# live bottom bar; CI (Linux, no such path) would never see it.
cat >"$TMP/bin/bar-bottom" <<'EOF'
#!/usr/bin/env bash
printf 'bar-bottom %s\n' "$*" >>"$AWAKE_TEST_LOG"
EOF

chmod +x "$TMP/bin/"*

export HOME="$TMP/home"
export AWAKE_STATE_DIR="$TMP/state"
export AWAKE_LAUNCHCTL_BIN="$TMP/bin/launchctl"
export AWAKE_CAFFEINATE_BIN="$TMP/bin/caffeinate"
export AWAKE_SKETCHYBAR_BIN="$TMP/bin/sketchybar"
export AWAKE_BAR_BOTTOM_BIN="$TMP/bin/bar-bottom"
export AWAKE_TEST_LOG="$TMP/log"
export AWAKE_NOW=1000000

fail() {
    printf 'not ok - %s\n' "$*" >&2
    exit 1
}

assert_eq() {
    [ "$1" = "$2" ] || fail "expected '$2', got '$1'"
}

assert_contains() {
    /usr/bin/grep -Fq "$2" "$1" || fail "$1 does not contain '$2'"
}

out=$("$AWAKE" 2h)
assert_eq "$out" "awake for 2h 00m"
assert_eq "$("$AWAKE" status --raw)" "$(printf 'timed\t7200\t1007200')"
assert_contains "$TMP/log" "kickstart -k gui/$(id -u)/com.hausfold.awake"
assert_contains "$TMP/log" "sketchybar --trigger caffeinate_change"
assert_contains "$TMP/log" "bar-bottom --trigger caffeinate_change"

out=$("$AWAKE" indefinitely)
assert_eq "$out" "awake indefinitely"
assert_eq "$("$AWAKE" status --raw)" "$(printf 'indefinite\t0\t0')"

out=$("$AWAKE" off)
assert_eq "$out" "idle sleep is allowed"
assert_eq "$("$AWAKE" status --raw)" "$(printf 'off\t0\t0')"
assert_contains "$TMP/log" "kill TERM gui/$(id -u)/com.hausfold.awake"

"$AWAKE" 90m >/dev/null
"$AWAKE" _run
assert_contains "$TMP/log" "caffeinate -i -t 5400"
assert_eq "$("$AWAKE" status --raw)" "$(printf 'off\t0\t0')"

"$AWAKE" forever >/dev/null
"$AWAKE" _run
assert_contains "$TMP/log" "caffeinate -i"
assert_eq "$("$AWAKE" status --raw)" "$(printf 'off\t0\t0')"

# A replaced assertion must survive cleanup from the controller it superseded.
"$AWAKE" 1h >/dev/null
export AWAKE_TEST_GATE="$TMP/gate"
touch "$AWAKE_TEST_GATE"
"$AWAKE" _run &
old_controller=$!
while ! tail -n 1 "$TMP/log" | grep -qF "caffeinate -i -t 3600"; do sleep 0.05; done
"$AWAKE" indefinitely >/dev/null
rm "$AWAKE_TEST_GATE"
wait "$old_controller"
assert_eq "$("$AWAKE" status --raw)" "$(printf 'indefinite\t0\t0')"
unset AWAKE_TEST_GATE
"$AWAKE" off >/dev/null

# Expired or malformed state self-heals to off.
"$AWAKE" 1m >/dev/null
AWAKE_NOW=1000061
assert_eq "$("$AWAKE" status --raw)" "$(printf 'off\t0\t0')"
AWAKE_NOW=1000000
mkdir -p "$AWAKE_STATE_DIR"
printf 'not valid state\n' >"$AWAKE_STATE_DIR/state"
assert_eq "$("$AWAKE" status --raw)" "$(printf 'off\t0\t0')"
[ ! -e "$AWAKE_STATE_DIR/state" ] || fail "malformed state was not removed"

# A missing/unloaded launchd job cannot leave a lying active state behind.
export AWAKE_LAUNCHCTL_FAIL=1
if "$AWAKE" 1h >/dev/null 2>&1; then fail "accepted a failed launchd start"; fi
[ ! -e "$AWAKE_STATE_DIR/state" ] || fail "failed start left active state"
unset AWAKE_LAUNCHCTL_FAIL

if "$AWAKE" 0h >/dev/null 2>&1; then fail "accepted zero duration"; fi
if "$AWAKE" nonsense >/dev/null 2>&1; then fail "accepted invalid duration"; fi

printf 'ok - awake lifecycle, duration parsing, and caffeinate arguments\n'

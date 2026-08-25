#!/usr/bin/env bash
# focus auto — the trigger daemon's decision logic, run rather than read.
#
# What this suite can and cannot see, because the split is the whole reason it
# is shaped like this: the DECISIONS (which scene rises, which one the daemon
# may enter, which one it is allowed to leave) are pure logic over a table and
# five facts, so they run anywhere. The FACTS themselves come from `pmset`,
# `networksetup`, `hausdisp`/`system_profiler` and the clock — four macOS reads
# this runner has none of. So every probe is stubbed here and every probe is
# also printed by `focus auto --probe`, which is the one command that checks
# them on a real Mac. A green run here means the daemon decides correctly about
# whatever it is told; it says nothing about what macOS tells it.
#
# Scenes here declare `dnd = false` on purpose. The DND leg presses a symbolic
# hotkey through pounce or System Events, neither of which exists on Linux, and
# `apply` exits 1 when the press fails — so a quiet scene would test the
# keystroke path (already felt by hand, 2026-08-16) instead of the trigger path
# this suite is about.
#
# ⚠️ The scene table below is a FIXTURE of what modules/focus/default.nix's
# `scenesJson` writes. That file is the source of truth for these key names —
# rename one there and this suite keeps passing while the engine reads nothing.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/home"

# The engine as the module builds it: the same script, with the substitutions
# default.nix makes. Anything else would test a copy.
build_engine() { # $1 = path to the scene table
    sed -e "s|@jq@|/usr/bin/jq|" \
        -e "s|@keyCode@|105|" \
        -e "s|@slackEnabled@|0|" \
        -e "s|@slackTokenCommand@|''|" \
        -e "s|@slackTokenHint@|'run: haus-secret --check'|" \
        -e "s|@slackStatusText@|'heads down'|" \
        -e "s|@slackStatusEmoji@|':no_bell:'|" \
        -e "s|@slackSnooze@|0|" \
        -e "s|@hooks@||" \
        -e "s|@scenes@|$1|" \
        -e "s|@switchAudio@||" \
        -e "s|@sketchybar@|$TMP/bin/sketchybar|" \
        "$ROOT/modules/focus/focus.sh" >"$TMP/focus"
    chmod +x "$TMP/focus"
    # The sed table above MIRRORS default.nix's --subst-var-by names, and a
    # hand-copied mirror is the thing this family keeps getting caught by. A new
    # placeholder there would otherwise reach the engine unsubstituted and this
    # suite would keep passing, testing a script the module never builds. So the
    # mirror is checked rather than trusted: anything left in @placeholder@ form
    # fails here, naming itself.
    # Comment lines are stripped first: the script's own header explains the
    # @var@ convention in prose, and every real substitution is on the
    # right-hand side of an assignment.
    if /usr/bin/grep -v '^[[:space:]]*#' "$TMP/focus" \
        | /usr/bin/grep -oE '@[a-zA-Z][a-zA-Z0-9]*@' | sort -u | grep .; then
        fail "a placeholder above survived — the sed table has drifted from modules/focus/default.nix"
    fi
}

cat >"$TMP/bin/date" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    +%H%M) printf '%s\n' "${FAKE_HHMM:-1200}" ;;
    +%a) printf '%s\n' "${FAKE_DAY:-Wed}" ;;
    *) exec /bin/date "$@" ;;
esac
EOF

cat >"$TMP/bin/pmset" <<'EOF'
#!/usr/bin/env bash
case "${FAKE_POWER:-ac}" in
    ac) echo "Now drawing from 'AC Power'" ;;
    battery) echo "Now drawing from 'Battery Power'" ;;
    *) echo "Now drawing from 'Wat'" ;;
esac
EOF

# The real thing prints a block per port; the reader wants the Device line that
# follows "Hardware Port: Wi-Fi", not the first one in the file — so the stub
# puts Ethernet ahead of it, which is where a Mac puts it too.
cat >"$TMP/bin/networksetup" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    -listallhardwareports)
        printf 'Hardware Port: Ethernet\nDevice: en3\n\nHardware Port: Wi-Fi\nDevice: en0\n' ;;
    -getairportnetwork)
        [ "${2:-}" = en0 ] || { echo "not a Wi-Fi device"; exit 1; }
        if [ -n "${FAKE_SSID:-}" ]; then
            printf 'Current Wi-Fi Network: %s\n' "$FAKE_SSID"
        else
            printf 'You are not associated with an AirPort network.\n'
        fi ;;
esac
EOF

cat >"$TMP/bin/hausdisp" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = list ] || exit 64
printf 'active displays: %s\n' "${FAKE_DISPLAYS:-1}"
printf '  [0] built-in\n'
EOF

cat >"$TMP/bin/system_profiler" <<'EOF'
#!/usr/bin/env bash
n=${FAKE_DISPLAYS:-1}
printf '{"SPDisplaysDataType":[{"spdisplays_ndrvs":['
for i in $(seq 1 "$n"); do
    [ "$i" = 1 ] || printf ','
    printf '{"_name":"screen%s"}' "$i"
done
printf ']}]}\n'
EOF

chmod +x "$TMP/bin/"*

export HOME="$TMP/home"
export FOCUS_DATE_BIN="$TMP/bin/date"
export FOCUS_PMSET_BIN="$TMP/bin/pmset"
export FOCUS_NETWORKSETUP_BIN="$TMP/bin/networksetup"
export FOCUS_SYSTEM_PROFILER_BIN="$TMP/bin/system_profiler"
export FOCUS_HAUSDISP_BIN="$TMP/bin/hausdisp"

STATE="$HOME/.local/state/focus"

fail() {
    printf 'not ok - %s\n' "$*" >&2
    exit 1
}

assert_eq() {
    [ "$1" = "$2" ] || fail "${3:-expected} '$2', got '$1'"
}

# What is on right now: a scene name, `quiet`, or `off`.
on_now() { "$TMP/focus" scene status; }
owner_now() { /usr/bin/jq -r '.owner' "$STATE/auto.json" 2>/dev/null || echo MISSING; }
tick() { "$TMP/focus" auto 2>/dev/null; }

reset() { rm -rf "$STATE"; }

# ---------------------------------------------------------------------------
# One scene, one window. The whole edge story lives in this fixture.
cat >"$TMP/scenes-time.json" <<'EOF'
{
  "work": {
    "description": "office hours",
    "dnd": false, "preventSleep": false, "restorePreviousState": true,
    "apps": [], "closeApps": false, "audioInput": "", "hooks": [],
    "when": { "time": "09:00-17:00", "days": [], "wifi": [], "power": "any", "displays": null }
  }
}
EOF
build_engine "$TMP/scenes-time.json"

# 1. Outside the window: nothing happens, and the state file records the miss.
reset
FAKE_HHMM=0830 tick
assert_eq "$(on_now)" off "outside the window nothing is entered:"
assert_eq "$(owner_now)" "" "no owner outside the window:"

# 2. The edge where it opens enters the scene, and records who entered it.
FAKE_HHMM=0905 tick
assert_eq "$(on_now)" work "the rising edge enters the scene:"
assert_eq "$(owner_now)" work "the daemon records itself as the owner:"

# 3. A condition that is merely STILL true changes nothing.
FAKE_HHMM=0930 tick
assert_eq "$(on_now)" work "a level that was already true is not an edge:"

# 4. Walk out by hand mid-window: the daemon must not put you back.
"$TMP/focus" scene off 2>/dev/null
assert_eq "$(on_now)" off "leaving by hand leaves:"
FAKE_HHMM=1000 tick
assert_eq "$(on_now)" off "the daemon does not re-enter a scene you left:"
assert_eq "$(owner_now)" "" "and it stops claiming ownership:"
FAKE_HHMM=1600 tick
assert_eq "$(on_now)" off "still left, hours later, while the window holds:"

# 5. The window closes and opens again tomorrow: that IS a new edge.
FAKE_HHMM=1730 tick
assert_eq "$(on_now)" off "closed window, nothing on:"
FAKE_HHMM=0901 tick
assert_eq "$(on_now)" work "the next day's edge enters again:"

# 6. The falling edge leaves what the daemon entered.
FAKE_HHMM=1701 tick
assert_eq "$(on_now)" off "the falling edge leaves the scene:"
assert_eq "$(owner_now)" "" "and releases ownership:"

# 7. A scene entered BY HAND is never taken away, however its condition moves.
reset
FAKE_HHMM=0830 tick
"$TMP/focus" scene work 2>/dev/null
assert_eq "$(on_now)" work "entered by hand:"
FAKE_HHMM=0905 tick
assert_eq "$(on_now)" work "still on when its own window opens:"
assert_eq "$(owner_now)" "" "the daemon never claims a scene it did not enter:"
FAKE_HHMM=1800 tick
assert_eq "$(on_now)" work "and the daemon does not leave it when the window closes:"

# 7b. Built-in quiet is a state you chose too, so the daemon leaves it alone.
# Written straight into the state file because turning quiet ON means pressing
# the DND hotkey, which is the one thing this runner cannot do — and what the
# guard reads is exactly this file when no pounce and no Assertions.json answer.
reset
mkdir -p "$STATE"
echo on >"$STATE/state"
FAKE_HHMM=0830 tick
FAKE_HHMM=0905 tick
assert_eq "$(on_now)" quiet "a rising edge does not take a quiet Mac off you:"
assert_eq "$(owner_now)" "" "and nothing is owned:"
# The edge is spent rather than remembered: going neutral later must not make
# the daemon pounce on a window that opened while you were busy.
echo off >"$STATE/state"
FAKE_HHMM=1000 tick
assert_eq "$(on_now)" off "and it does not fire late once you go neutral:"

# ---------------------------------------------------------------------------
# 8. Two conditions rising in the same tick: the first name wins, every time.
cat >"$TMP/scenes-two.json" <<'EOF'
{
  "beta": {
    "description": "second alphabetically",
    "dnd": false, "preventSleep": false, "restorePreviousState": true,
    "apps": [], "closeApps": false, "audioInput": "", "hooks": [],
    "when": { "time": "09:00-17:00", "days": [], "wifi": [], "power": "any", "displays": null }
  },
  "alpha": {
    "description": "first alphabetically",
    "dnd": false, "preventSleep": false, "restorePreviousState": true,
    "apps": [], "closeApps": false, "audioInput": "", "hooks": [],
    "when": { "time": "09:00-17:00", "days": [], "wifi": [], "power": "any", "displays": null }
  }
}
EOF
build_engine "$TMP/scenes-two.json"
reset
FAKE_HHMM=0830 tick
FAKE_HHMM=0905 tick
assert_eq "$(on_now)" alpha "two rising edges resolve to the first name:"

# ---------------------------------------------------------------------------
# 9. Handover in ONE tick: one window closes as the next opens.
cat >"$TMP/scenes-handover.json" <<'EOF'
{
  "day": {
    "description": "office hours",
    "dnd": false, "preventSleep": false, "restorePreviousState": true,
    "apps": [], "closeApps": false, "audioInput": "", "hooks": [],
    "when": { "time": "09:00-17:00", "days": [], "wifi": [], "power": "any", "displays": null }
  },
  "evening": {
    "description": "after work",
    "dnd": false, "preventSleep": false, "restorePreviousState": true,
    "apps": [], "closeApps": false, "audioInput": "", "hooks": [],
    "when": { "time": "17:00-23:00", "days": [], "wifi": [], "power": "any", "displays": null }
  }
}
EOF
build_engine "$TMP/scenes-handover.json"
reset
# Also the first-tick case: no state file at all, and a condition that already
# holds counts as an edge — which is what makes logging in at 10:00 land in the
# scene rather than waiting for tomorrow's 09:00.
FAKE_HHMM=1000 tick
assert_eq "$(on_now)" day "a condition true on the very first tick is entered:"
FAKE_HHMM=1700 tick
assert_eq "$(on_now)" evening "one tick leaves the closing scene and enters the opening one:"
assert_eq "$(owner_now)" evening "and owns the new one:"

# ---------------------------------------------------------------------------
# 10. A window that wraps midnight is one night, not an empty set.
cat >"$TMP/scenes-night.json" <<'EOF'
{
  "night": {
    "description": "wraps midnight",
    "dnd": false, "preventSleep": false, "restorePreviousState": true,
    "apps": [], "closeApps": false, "audioInput": "", "hooks": [],
    "when": { "time": "22:00-06:00", "days": [], "wifi": [], "power": "any", "displays": null }
  }
}
EOF
build_engine "$TMP/scenes-night.json"
reset
FAKE_HHMM=2100 tick
assert_eq "$(on_now)" off "before the night window:"
FAKE_HHMM=2300 tick
assert_eq "$(on_now)" night "inside it, before midnight:"
FAKE_HHMM=0300 tick
assert_eq "$(on_now)" night "still inside it, after midnight:"
FAKE_HHMM=0600 tick
assert_eq "$(on_now)" off "and out at the closing minute, which is exclusive:"

# ---------------------------------------------------------------------------
# 11. Days narrow a window rather than standing alone.
cat >"$TMP/scenes-days.json" <<'EOF'
{
  "weekday": {
    "description": "mon-fri mornings",
    "dnd": false, "preventSleep": false, "restorePreviousState": true,
    "apps": [], "closeApps": false, "audioInput": "", "hooks": [],
    "when": { "time": "09:00-12:00", "days": ["mon","tue","wed","thu","fri"],
              "wifi": [], "power": "any", "displays": null }
  }
}
EOF
build_engine "$TMP/scenes-days.json"
reset
FAKE_HHMM=1000 FAKE_DAY=Sat tick
assert_eq "$(on_now)" off "a Saturday inside the window is not a match:"
FAKE_HHMM=1000 FAKE_DAY=Wed tick
assert_eq "$(on_now)" weekday "a Wednesday is:"

# ---------------------------------------------------------------------------
# 12. Power, Wi-Fi and the screen count — the three probed facts.
cat >"$TMP/scenes-facts.json" <<'EOF'
{
  "battery": {
    "description": "off the wall",
    "dnd": false, "preventSleep": false, "restorePreviousState": true,
    "apps": [], "closeApps": false, "audioInput": "", "hooks": [],
    "when": { "time": "", "days": [], "wifi": [], "power": "battery", "displays": null }
  },
  "docked": {
    "description": "two screens on the desk",
    "dnd": false, "preventSleep": false, "restorePreviousState": true,
    "apps": [], "closeApps": false, "audioInput": "", "hooks": [],
    "when": { "time": "", "days": [], "wifi": [], "power": "any", "displays": 2 }
  },
  "home": {
    "description": "on the home network",
    "dnd": false, "preventSleep": false, "restorePreviousState": true,
    "apps": [], "closeApps": false, "audioInput": "", "hooks": [],
    "when": { "time": "", "days": [], "wifi": ["Home","Home 5G"], "power": "any", "displays": null }
  }
}
EOF
build_engine "$TMP/scenes-facts.json"

reset
FAKE_POWER=ac FAKE_DISPLAYS=1 tick
assert_eq "$(on_now)" off "on wall power with one screen and no SSID, nothing holds:"
FAKE_POWER=battery FAKE_DISPLAYS=1 tick
assert_eq "$(on_now)" battery "unplugging is an edge:"
FAKE_POWER=ac FAKE_DISPLAYS=1 tick
assert_eq "$(on_now)" off "plugging back in leaves it:"

reset
FAKE_POWER=ac FAKE_DISPLAYS=2 tick
assert_eq "$(on_now)" docked "a second screen enters the docked scene:"
FAKE_POWER=ac FAKE_DISPLAYS=3 tick
assert_eq "$(on_now)" docked "a third screen keeps it (the count is a floor):"
FAKE_POWER=ac FAKE_DISPLAYS=1 tick
assert_eq "$(on_now)" off "undocking leaves it:"

reset
FAKE_POWER=ac FAKE_DISPLAYS=1 FAKE_SSID="Home 5G" tick
assert_eq "$(on_now)" home "the second SSID in the list matches too:"
FAKE_POWER=ac FAKE_DISPLAYS=1 FAKE_SSID="Cafe" tick
assert_eq "$(on_now)" off "another network leaves it:"

# The refusal case, and the reason `--probe` exists: an SSID macOS won't report
# is indistinguishable from a network you are not on, so it must match NOTHING
# rather than anything.
reset
FAKE_POWER=ac FAKE_DISPLAYS=1 tick
assert_eq "$(on_now)" off "an unreadable SSID matches no wifi condition:"

# The system_profiler fallback answers the same question as hausdisp. Same
# assertion, one probe removed — this is the branch a machine without the
# displays room takes, and nothing else covers it.
reset
FOCUS_HAUSDISP_BIN="$TMP/bin/does-not-exist" FAKE_DISPLAYS=2 tick
assert_eq "$(on_now)" docked "the system_profiler fallback counts screens too:"

# ---------------------------------------------------------------------------
# 13. A scene the host deleted while it was on is still left — the daemon reads
# its owner from state, and the engine reverses off scene-prev.json, so neither
# needs the table to still contain it.
build_engine "$TMP/scenes-time.json"
reset
FAKE_HHMM=0830 tick
FAKE_HHMM=0905 tick
assert_eq "$(on_now)" work "on, before the rebuild:"
# A table `work` is not in at all, and whose own scene cannot match at 09:30 —
# otherwise this would prove the handover in step 9 a second time instead of
# the thing it is here for.
build_engine "$TMP/scenes-night.json"
FAKE_HHMM=0930 tick
assert_eq "$(on_now)" off "a scene that left the table is left rather than stranded:"

# ---------------------------------------------------------------------------
# 14. `auto --probe` reads and never acts — the feel-test command.
build_engine "$TMP/scenes-facts.json"
reset
out=$(FAKE_POWER=battery FAKE_DISPLAYS=2 FAKE_SSID=Home "$TMP/focus" auto --probe 2>/dev/null)
printf '%s' "$out" | grep -q "power      battery" || fail "--probe does not print the power source"
printf '%s' "$out" | grep -q "wifi       Home" || fail "--probe does not print the SSID"
printf '%s' "$out" | grep -q "displays   2" || fail "--probe does not print the screen count"
printf '%s' "$out" | grep -q "docked" || fail "--probe does not list the scenes"
assert_eq "$(on_now)" off "--probe entered a scene, which it must never do:"
[ ! -f "$STATE/auto.json" ] || fail "--probe wrote the daemon's state file"

# An unreadable SSID has to SAY so here, because that is the whole reason this
# subcommand exists — "no match" and "no answer" look identical from outside.
out=$(FAKE_POWER=ac FAKE_DISPLAYS=1 "$TMP/focus" auto --probe 2>/dev/null)
printf '%s' "$out" | grep -q "unreadable" || fail "--probe does not flag an unreadable SSID"

# ---------------------------------------------------------------------------
# 15. An entry that FAILS spends its edge anyway, and this is the one test whose
# subject is a failure mode rather than a feature. A quiet scene presses the DND
# hotkey, `apply` exits 1 when that press has no Accessibility grant, and the
# exit takes the whole tick with it — so if the daemon recorded the edge after
# acting, every tick from then on would see the same rising edge, try again, and
# post the same notification, thirty seconds apart, forever. This runner cannot
# press a hotkey at all, which makes it a perfect stand-in for a Mac that has
# not been granted Accessibility yet.
cat >"$TMP/scenes-quiet.json" <<'EOF'
{
  "hush": {
    "description": "a scene that actually takes DND",
    "dnd": true, "preventSleep": false, "restorePreviousState": true,
    "apps": [], "closeApps": false, "audioInput": "", "hooks": [],
    "when": { "time": "09:00-17:00", "days": [], "wifi": [], "power": "any", "displays": null }
  }
}
EOF
build_engine "$TMP/scenes-quiet.json"
reset
FAKE_HHMM=0830 tick
FAKE_HHMM=0905 "$TMP/focus" auto >/dev/null 2>&1 && fail "the keypress cannot succeed here, so the tick must not report success"
assert_eq "$(on_now)" off "a scene whose DND leg failed is not recorded as entered:"
assert_eq "$(/usr/bin/jq -r '.matched.hush' "$STATE/auto.json")" true     "the edge is spent even though acting on it failed:"
FAKE_HHMM=0906 "$TMP/focus" auto >/dev/null 2>&1     || fail "the next tick tried the same failed entry again — the edge was not spent"

# ---------------------------------------------------------------------------
# 16. A PROBE THAT BLINKS MUST NOT FLAP THE SCENE. macOS reports no Wi-Fi
# network during sleep/wake, AP roaming and VPN reconnects, and launchd fires
# StartInterval right at wake — so "the SSID read came back empty" is a routine
# event, not a corner case. Treating it as a falling edge would leave the scene
# and re-enter it a tick later, which means hooks off/on, the caffeinate hold
# dropped and retaken, and with apps.closeOnExit the scene's apps quit and
# relaunched. The entry counter is the honest witness: it must not move.
build_engine "$TMP/scenes-facts.json"
reset
FAKE_SSID=Home tick
assert_eq "$(on_now)" home "on the home network:"
entry_before=$(/bin/cat "$STATE/scene-entry")
tick # the same tick with no FAKE_SSID: macOS declined to answer
assert_eq "$(on_now)" home "an unreadable SSID holds the scene rather than leaving it:"
assert_eq "$(owner_now)" home "and ownership survives the blink:"
FAKE_SSID=Home tick
assert_eq "$(on_now)" home "and it is still the same scene when the SSID comes back:"
assert_eq "$(/bin/cat "$STATE/scene-entry")" "$entry_before" \
    "the scene was never re-entered — no hooks, no relaunched apps:"
# The other half of the rule: a probe that ANSWERS, with an answer that fails,
# still leaves. "Cannot say" is not "no", but "no" is still "no".
FAKE_SSID=Cafe tick
assert_eq "$(on_now)" off "a different network is a definite miss, and leaves:"

# ---------------------------------------------------------------------------
# 17. A LEAVE THAT FAILS IS NOT RETRIED FOREVER — the mirror of case 15, on the
# other door. `scene_off` can reach `apply off`, which exits 1 without an
# Accessibility grant and takes the tick with it; ownership recorded after that
# would re-run the scene's exit every thirty seconds. Reached here through the
# engine's own no-prev-file branch (an entry whose write failed, or a
# hand-edited state dir), which is the one path to `apply off` this runner can
# take: the keypress it needs cannot succeed on Linux.
build_engine "$TMP/scenes-time.json"
reset
FAKE_HHMM=0830 tick
FAKE_HHMM=0905 tick
assert_eq "$(on_now)" work "entered, before the state dir is disturbed:"
rm -f "$STATE/scene-prev.json"
echo on >"$STATE/state"
FAKE_HHMM=1730 "$TMP/focus" auto >/dev/null 2>&1 \
    && fail "the un-quiet keypress cannot succeed here, so the tick must not report success"
assert_eq "$(owner_now)" "" "a leave that threw still gave up ownership:"
FAKE_HHMM=1731 "$TMP/focus" auto >/dev/null 2>&1 \
    || fail "the next tick tried the same failed leave again"

# ---------------------------------------------------------------------------
# 18. Leaving and re-entering the same scene BY HAND between two ticks is
# visible to the daemon. Ownership is a name plus the entry it was entered
# under; on the name alone this is invisible, and the daemon would evict a
# scene you had just chosen — breaking the one promise the whole feature makes.
reset
FAKE_HHMM=0830 tick
FAKE_HHMM=0905 tick
assert_eq "$(owner_now)" work "the daemon owns what it entered:"
"$TMP/focus" scene off 2>/dev/null
"$TMP/focus" scene work 2>/dev/null # same scene, same interval, by hand
FAKE_HHMM=0930 tick
assert_eq "$(owner_now)" "" "a hand re-entry inside one interval takes ownership back:"
FAKE_HHMM=1730 tick
assert_eq "$(on_now)" work "so the closing window does not evict the scene you entered:"

printf 'ok - focus auto: %s assertions\n' "$(grep -cE '^assert_eq |\|\| fail ' "$0")"

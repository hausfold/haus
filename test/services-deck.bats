#!/usr/bin/env bats
#
# The background-jobs deck's READERS: the US record encoding, the
# `launchctl print` parse, and the four-verdict truth table behind
# `haus services` and doctor's Background jobs section.
#
# `nix flake check`'s `services-deck` already pins the deck's COMPLETENESS —
# every launchd job in the repo has an entry and every entry names a job. That
# check knows nothing about what the CLI then does with the file, which is where
# the cost of a wrong answer actually lands: a false red line also fires the BTM
# card in the permissions deck, and a false green hides a job that has stopped
# working.
#
# The case this file exists for is `last exit code = (never exited)`. launchd
# prints exactly that for a job with `runs = 0` — the field is present and
# simply is not a number, so a reader testing "non-empty and not 0" calls a job
# that has NEVER RUN failed. That is a false red on two real machine states:
# `nix-gc` for the whole first week after an install, and github's tunnel —
# dormant by design until its credentials file appears, so `runs = 0` forever on
# a machine that never bootstrapped it — permanently.
#
# ⚠️ `launchctl` is faked as a FUNCTION, never as a script on PATH. modules/core/
# haus.sh:41 PREPENDS a fixed PATH (`/run/current-system/sw/bin` first) at load,
# so a stub dropped in front of `$PATH` by `setup()` is shadowed by the real
# binary and every case quietly measures whichever jobs this Mac happens to be
# running. Four cases in the first draft of this file "passed" that way. A shell
# function is resolved before PATH is consulted at all, so it cannot lose.
#
# ⚠️ Every runner below spawns `"$BASH"`, never a bare `bash`. On macOS a bare
# `bash` is /bin/bash 3.2, which has no `coproc` — so it cannot even parse
# haus.sh's `snug_open`, and every case here dies at `source` with an unbound
# `SNUG[1]` rather than testing anything. `$BASH` is the interpreter bats itself
# is running under, which is by construction one that can.

setup() {
  # The REAL file, sourced through its own library seam — `HAUS_LIB=1` returns
  # before the dispatch, which is what test/phase-painter.bats and
  # test/haus-plan.sh both use. Never a `sed` that strips the dispatch into a
  # copy: that reaches the verbs without passing the load-time guards, so the
  # suite stops testing the conditions the script actually starts under.
  HAUS_SRC="$BATS_TEST_DIRNAME/../modules/core/haus.sh"
  export HAUS_LIB=1

  # haus.sh refuses to load without a config flake, and `HAUS_LIB` stops it
  # before the dispatch but NOT before that guard. Give it an empty one — a
  # developer's Mac has ~/.config/nix and a CI runner has nothing, so without
  # this the whole suite passes locally and every case fails in CI, which is the
  # worst way round.
  export HAUS_CONSUMER="$BATS_TEST_TMPDIR/consumer"
  mkdir -p "$HAUS_CONSUMER"
  : > "$HAUS_CONSUMER/flake.nix"
}

# The body of the fake, shared by both runners. Reproduces the real shape: the
# job's own fields at ONE tab and a nested endpoint carrying `state = active` at
# two, which is the thing the reader's anchors have to step over. A label ending
# `absent.job` fails the way launchd answers for a job it does not have.
_fake='
  launchctl() {
    [ "$1" = print ] || return 0
    case "$2" in *absent.job) return 113 ;; esac
    printf "%s = {\n" "$2"
    printf "\tactive count = 1\n"
    printf "\tstate = %s\n" "$FAKE_STATE"
    [ -z "${FAKE_CODE:-}" ] || printf "\tlast exit code = %s\n" "$FAKE_CODE"
    printf "\tendpoints = {\n"
    printf "\t\tstate = active\n"
    printf "\t}\n}\n"
  }
'

# probe <state> <code|""> <domain> <label> — the raw "<verdict>US<code>" record.
probe() {
  FAKE_STATE="$1" FAKE_CODE="$2" "$BASH" -c "
    set -euo pipefail
    source \"\$1\"
    $_fake
    _svc_probe \"\$2\" \"\$3\"
  " _ "$HAUS_SRC" "$3" "$4"
}

# verdict <state> <code|""> <liveness> <domain> <label> — the reported status.
verdict() {
  FAKE_STATE="$1" FAKE_CODE="$2" "$BASH" -c "
    set -euo pipefail
    source \"\$1\"
    $_fake
    p=\"\$(_svc_probe \"\$3\" \"\$4\")\"
    _svc_status \"\$2\" \"\${p%%\$'\037'*}\" \"\${p#*\$'\037'}\"
  " _ "$HAUS_SRC" "$3" "$4" "$5"
}

# ---- the case this file was written for ------------------------------------

@test "a job that has never run is idle, not failed" {
  run verdict "not running" "(never exited)" periodic system org.nixos.nix-gc
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "(never exited) never reaches a caller as a code" {
  run probe "not running" "(never exited)" system org.nixos.nix-gc
  [ "$status" -eq 0 ]
  # A verdict and an EMPTY code, never the literal launchd printed.
  [ "$output" = "stopped$(printf '\037')" ]
}

@test "a dormant job that has never run stays quiet forever" {
  # github's tunnel on a machine that skipped the one-time bootstrap.
  run verdict "not running" "(never exited)" dormant user org.nixos.haus-github-tunnel
  [ "$output" = "ok" ]
}

# ---- the truth table -------------------------------------------------------

@test "an idle job whose last run failed is a finding" {
  run verdict "not running" "1" periodic system org.nixos.nix-gc
  [ "$output" = "failed" ]
}

@test "an idle job whose last run succeeded is not" {
  run verdict "not running" "0" periodic system org.nixos.nix-gc
  [ "$output" = "ok" ]
}

@test "a job meant to be running and isn't is wedged" {
  run verdict "not running" "0" running user org.nixos.sketchybar
  [ "$output" = "wedged" ]
}

@test "a live job is ok whatever it last exited" {
  # A KeepAlive job's last exit is a crash launchd has already recovered from;
  # reporting it would nag forever about something that needs nothing.
  run verdict "running" "78" running user org.nixos.sketchybar
  [ "$output" = "ok" ]
}

@test "a job launchd has never heard of is absent, not wedged" {
  run verdict "not running" "0" running user com.hausfold.absent.job
  [ "$output" = "absent" ]
}

@test "spawn scheduled is not a wedge" {
  # launchd's third state: the window in which it is starting the job. Only
  # `not running` earns a red line, because a red line here also puts a BTM
  # card in front of somebody.
  run verdict "spawn scheduled" "" running user org.nixos.sketchybar
  [ "$output" = "ok" ]
}

# ---- the parse -------------------------------------------------------------

@test "a nested endpoint's state is not read as the job's own" {
  # An unanchored match takes the endpoint's `state = active` at two tabs and
  # calls a dead job healthy.
  run probe "not running" "0" user org.nixos.sketchybar
  [ "${output%%$(printf '\037')*}" = "stopped" ]
}

@test "a job with no exit line at all is idle, not failed" {
  run verdict "not running" "" watch user org.nixos.focus-watcher
  [ "$output" = "ok" ]
}

# ---- the record encoding ---------------------------------------------------

@test "every field survives, including the empty ones" {
  # `cost` and `log` are routinely empty (focus's watcher logs nowhere), and an
  # encoding that collapsed them would shift every field after them one column
  # left — silently. That is why the separator is US and not TAB.
  cat > "$BATS_TEST_TMPDIR/deck.json" <<'JSON'
[{"key":"k","domain":"user","label":"com.example.k","liveness":"watch",
  "title":"T","why":"W","cost":"","order":10,"log":""}]
JSON
  run "$BASH" -c '
    set -euo pipefail
    source "$1"
    HAUS_SERVICES="$2"
    while IFS=$'"'"'\037'"'"' read -r key domain label liveness title why cost log; do
      printf "%s|%s|%s|%s|%s|%s|[%s]|[%s]\n" \
        "$key" "$domain" "$label" "$liveness" "$title" "$why" "$cost" "$log"
    done < <(_svc_deck)
  ' _ "$HAUS_SRC" "$BATS_TEST_TMPDIR/deck.json"
  [ "$status" -eq 0 ]
  [ "$output" = "k|user|com.example.k|watch|T|W|[]|[]" ]
}

@test "a multi-line why is folded to one record" {
  # Every `why` in the deck is a Nix indented string, so it arrives with real
  # newlines in it — one of which would end the record halfway through the card.
  cat > "$BATS_TEST_TMPDIR/deck.json" <<'JSON'
[{"key":"k","domain":"user","label":"com.example.k","liveness":"running",
  "title":"T","why":"one\n  two\n","cost":"c","order":10,"log":"/tmp/l"}]
JSON
  run "$BASH" -c '
    set -euo pipefail
    source "$1"
    HAUS_SERVICES="$2"
    _svc_deck | wc -l | tr -d " "
  ' _ "$HAUS_SRC" "$BATS_TEST_TMPDIR/deck.json"
  [ "$output" = "1" ]
}

@test "a missing deck file is silence, not an error" {
  run "$BASH" -c '
    set -euo pipefail
    source "$1"
    HAUS_SERVICES="$2"
    _svc_deck
  ' _ "$HAUS_SRC" "$BATS_TEST_TMPDIR/nothing-here.json"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

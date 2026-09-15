#!/usr/bin/env bats
# The palette's Accessibility card — the two snippets in
# modules/launcher/default.nix that decide whether `haus doctor` and `haus
# permissions` draw it, and green or red.
#
# Why a suite for two lines of shell. The card's failure mode is a FALSE GREEN,
# which is the one verdict nobody looks behind. It used to read the grant with
# `pounce --check-accessibility`, which prints AXIsProcessTrusted() from the
# short-lived CLI, and macOS answers that for whatever process is RESPONSIBLE
# for the shell — the terminal. So on every machine whose terminal held
# Accessibility the flag said `true` for a daemon that held nothing: a tick in
# doctor, a card the wizard skipped, and a palette whose chords all did nothing,
# against a TCC row reading `kTCCServiceAccessibility|com.hausfold.pounce|0`.
# Found on a fresh VM install, which is the one machine that has the state.
#
# Nothing else in the repo can catch it. `nix flake check` type-checks the card
# and says nothing about what the snippet MEANS, and a feel-test needs a Mac
# where the grant is missing — the machine you have on install day and never
# again. So the headline case here is exactly that split: a CLI answering
# `true` while the daemon answers false. The old card passes it and the new one
# must not.
#
# The subject is the snippet as WRITTEN, lifted out of the module by awk and run
# the way haus.sh runs it — `set -euo pipefail`, in a subshell, stdin closed
# (modules/core/haus.sh, `_perm_run`). `pounce` is a stub on PATH that answers
# the two verbs separately, so the CLI's own trust flag and the daemon's report
# can disagree the way they do on a real Mac, and every other state — silent
# daemon, unhealthy report, a CLI too old for `--json`, no pounce — is a case
# that needs no Mac at all.

bats_require_minimum_version 1.5.0

setup() {
  # The override is how this suite is proved to fail on the OLD card: point it
  # at a fixture carrying the previous snippets and the cases below go red.
  NIX_FILE="${LAUNCHER_NIX_UNDER_TEST:-$BATS_TEST_DIRNAME/../modules/launcher/default.nix}"
  STUB="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB"
  PATH="$STUB:$PATH"

  APPLIES="$(card_field applies)"
  CHECK="$(card_field check)"
  # A field the extractor cannot see would make every `run !` case below pass
  # on an empty script, so the whole suite stops here instead.
  [ -n "$APPLIES" ] && [ -n "$CHECK" ]
}

# One field of the card, dedented — the snippet exactly as the deck will carry
# it. Reading the module rather than a copy is the point: a card that goes back
# to asking the CLI fails these cases instead of quietly passing them. Both
# spellings, because a one-line `check = ''…'';` is as legal as the block form
# and an extractor that saw only one of them would return empty and prove
# nothing.
card_field() {
  awk -v field="$1" '
    BEGIN { q = "\047\047" }
    /haus\._contrib\.permissions\.launcher-accessibility = \{/ { in_card = 1; next }
    !in_card { next }
    $0 == "  };" { exit }
    !grab && $0 == "    " field " = " q { grab = 1; next }
    grab && $0 == "    " q ";" { exit }
    grab { sub(/^      /, ""); print; next }
    !grab && index($0, "    " field " = ") == 1 {
      line = substr($0, length("    " field " = ") + 1)
      sub(/;$/, "", line)
      if (index(line, q) == 1) { line = substr(line, 3, length(line) - 4) }
      else if (index(line, "\"") == 1) { line = substr(line, 2, length(line) - 2) }
      print line
      exit
    }
  ' "$NIX_FILE"
}

# A pounce whose two verbs answer independently, because on the machine this
# card was wrong on they disagreed: $1/$2 are the daemon's report and `pounce
# doctor`'s exit code, $3 is what the CLI's own trust flag prints — `true` by
# default, since a granted terminal is what makes it lie.
fake_pounce() {
  cat >"$STUB/pounce" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  doctor)
    cat <<'JSON'
$1
JSON
    exit ${2:-0} ;;
  --check-accessibility) printf '%s\n' "${3:-true}" ;;
  *) : ;;
esac
EOF
  chmod +x "$STUB/pounce"
}

# haus.sh's `_perm_run`, to the letter: a subshell so an `exit` in the snippet
# ends the snippet rather than the caller, both streams silenced, and stdin
# closed — the deck is read by a `while read` loop, so a snippet that reads
# stdin would eat the rest of it.
perm_run() {
  ( bash -c "set -euo pipefail
$1" ) >/dev/null 2>&1 </dev/null
}

# THE case. The terminal holds Accessibility and the daemon does not, which is
# every fresh machine where the grant was never given: the CLI flag says `true`,
# the daemon says false, and only one of those is the card's subject.
@test "a granted terminal cannot vouch for an ungranted daemon" {
  fake_pounce '{"daemon":{"running":true,"accessibility":false}}' 1 true
  run -0 perm_run "$APPLIES"
  run ! perm_run "$CHECK"
}

@test "granted: the daemon says yes and the card goes green" {
  fake_pounce '{"daemon":{"running":true,"accessibility":true}}' 0 true
  run -0 perm_run "$APPLIES"
  run -0 perm_run "$CHECK"
}

# `daemon.accessibility` is null when no daemon answered, and null is not a
# denial — so the card is not DRAWN rather than drawn red at somebody whose real
# fault is a stopped job, which the services deck reports. What it must never
# be is green.
@test "no daemon: null is neither a grant nor a denial" {
  fake_pounce '{"daemon":{"running":false,"accessibility":null}}' 1 true
  run ! perm_run "$APPLIES"
  run ! perm_run "$CHECK"
}

# `pounce doctor` exits 1 for ANY unhappy line in its report — another tool
# shadowing ⌘Space is enough — and haus.sh runs under `pipefail`, which hands
# that status to the whole pipeline. Unwrapped, this case reads a properly
# granted Mac as unmet: a red card that granting something cannot clear.
@test "granted, while the rest of pounce's report is unhealthy" {
  fake_pounce '{"daemon":{"running":true,"accessibility":true}}' 1 true
  run -0 perm_run "$APPLIES"
  run -0 perm_run "$CHECK"
}

# A pounce too old for `doctor --json` prints nothing on stdout. Same rule as a
# silent daemon: no answer is not a grant, and an undrawable card is not drawn.
@test "a pounce that cannot answer: no card, no tick" {
  fake_pounce '' 2 true
  run ! perm_run "$APPLIES"
  run ! perm_run "$CHECK"
}

@test "no pounce at all: the card does not apply" {
  rm -f "$STUB/pounce"
  PATH="/usr/bin:/bin"
  run ! perm_run "$APPLIES"
}

# The regression guard proper: both snippets ask the DAEMON over `pounce doctor
# --json`, and neither goes back to the flag that answers for the terminal.
@test "both snippets read the daemon, not the calling process" {
  [[ "$CHECK" == *"pounce doctor --json"* ]]
  [[ "$CHECK" == *".daemon.accessibility"* ]]
  [[ "$APPLIES" == *".daemon.running"* ]]
  [[ "$APPLIES$CHECK" != *"--check-accessibility"* ]]
}

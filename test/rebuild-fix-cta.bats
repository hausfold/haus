#!/usr/bin/env bats
# The "Fix it with AI" recovery CTA on a failed `haus rebuild` — the haus.sh
# half (modules/core/haus.sh's `rebuild_failed` and the four `fault_*` helpers)
# and the refusals of the binary it hands off to (modules/ai/fix.sh).
#
# What this suite is FOR. Every part of this feature fails SILENTLY when it
# breaks, and in the direction nobody notices:
#
#   * the breadcrumb is the only thing that crosses from the rebuild to
#     `haus fix`, which runs minutes later in another process. A key renamed on
#     either side is a "Fix it" that answers "nothing to fix" for a rebuild that
#     failed in front of you. (`modules/lib/state-files.nix` pins the PATH; this
#     pins the CONTENTS.)
#   * the four gates — a fixer on PATH, a git repo to undo in, a surface, and
#     HAUS_NO_FIX — each fail OPEN if they are inverted: an offer nobody can
#     honour, or an agent editing a checkout with no undo.
#   * the holder is detached on purpose, and the whole reason is invisible: it
#     has to outlive the window the rebuild ran in, because trill retracts an
#     ask whose caller died. A holder that merely backgrounds looks identical
#     until someone closes the terminal.
#
# ⚠️ Two stubs are FUNCTIONS, not scripts on PATH, and that is not a shortcut:
# haus.sh prepends the system profile to PATH at load (so a sudo or login-item
# shell can find nix at all), which puts a real `haus-fix` and a real `gum`
# ahead of any directory a test could add — and on a machine that has shipped
# this feature, both exist. `command -v` finds a function first, so that is the
# one seam that actually shadows them. trill needs no such trick: `HAUS_TRILL`
# is authoritative in `trill_bin`, including pointed at nothing.
#
# What is NOT here, and was verified by hand instead: the three OUTCOME banners
# of a completed fix (fixed / nothing changed / still broken) and the in-pane
# `gum` rows. The first needs a real flake and a nix evaluation, the second a
# pty; neither is worth a CI dependency for a courtesy surface.

bats_require_minimum_version 1.5.0

setup() {
  SUBJECT="$BATS_TEST_DIRNAME/../modules/core/haus.sh"
  FIXER="$BATS_TEST_DIRNAME/../modules/ai/fix.sh"

  # haus.sh refuses to load without a config flake; HAUS_LIB stops it before the
  # dispatch but not before that guard, so give it one — and a git repo, since
  # the CTA's undo gate is `git -C $CONSUMER`.
  export HAUS_CONSUMER="$BATS_TEST_TMPDIR/consumer"
  mkdir -p "$HAUS_CONSUMER"
  : >"$HAUS_CONSUMER/flake.nix"
  git -C "$HAUS_CONSUMER" init -q .

  export STATE="$BATS_TEST_TMPDIR/state"
  export CRUMB="$STATE/last-failure"
  export ASKED="$BATS_TEST_TMPDIR/asked"
  export FIXED="$BATS_TEST_TMPDIR/fixed"
  mkdir -p "$STATE" "$BATS_TEST_TMPDIR/bin"

  # A trill that records the ask and answers with $ASK_RC. Reached through
  # HAUS_TRILL, the seam trill_bin documents.
  cat >"$BATS_TEST_TMPDIR/bin/trill" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ASKED"
exit "${ASK_RC:-0}"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/trill"
  export HAUS_TRILL="$BATS_TEST_TMPDIR/bin/trill"
  unset HAUS_NO_FIX HAUS_NO_BANNER
}

# Load haus.sh as a library in a FRESH shell, with the CTA's own state wired to
# the tmpdir, and run a snippet. The two shadowing functions are defined before
# it so `command -v` sees them; `fault_hold`'s detached subshell inherits both.
haus_sh() { # haus_sh <VAR=val…> <snippet>
  local snippet="${!#}"
  run env "${@:1:$#-1}" HAUS_CONSUMER="$HAUS_CONSUMER" HAUS_LIB=1 "$BASH" -c "
    set -uo pipefail
    haus-fix() { date >>\"\$FIXED\"; }
    source '$SUBJECT'
    HAUS_LOG_DIR='$STATE'
    HAUS_LOG='$STATE/rebuild.log'
    FAULT_HOST=mbp
    FAULT_DRV=/nix/store/deadbeef.drv
    CARD_GEN=418
    HAUS_PHASE_OFF=99
    $snippet"
}

crumb() { sed -n "s/^$1=//p" "$CRUMB"; }

# The holder is detached, so nothing about it is synchronous. Poll rather than
# sleep a fixed amount: a fixed sleep is either flaky or slow, and on a loaded
# runner it is both.
wait_for() { # wait_for <path> [tries]
  local i
  for ((i = 0; i < ${2:-40}; i++)); do
    [ -e "$1" ] && return 0
    sleep 0.1
  done
  return 1
}

# ---- the breadcrumb ---------------------------------------------------------

@test "fault_crumb writes every field haus fix reads" {
  haus_sh 'fault_crumb resolve'
  [ "$status" -eq 0 ]
  [ "$(crumb class)" = resolve ]
  [ "$(crumb host)" = mbp ]
  [ "$(crumb consumer)" = "$HAUS_CONSUMER" ]
  [ "$(crumb log)" = "$STATE/rebuild.log" ]
  [ "$(crumb offset)" = 99 ]
  [ "$(crumb drv)" = /nix/store/deadbeef.drv ]
  [ "$(crumb gen)" = 418 ]
  [ -n "$(crumb when)" ]
}

@test "fault_crumb values never contain a newline" {
  # Read back by name, one KEY=value per line. A value with a newline in it
  # would silently become a key `haus fix` then reads as empty.
  haus_sh 'fault_crumb build'
  run bash -c "grep -c '=' '$CRUMB'"
  [ "$output" = "$(wc -l <"$CRUMB" | tr -d ' ')" ]
}

# ---- rebuild_failed ---------------------------------------------------------

@test "rebuild_failed exits 1 and says what happened, per class" {
  haus_sh 'rebuild_failed resolve'
  [ "$status" -eq 1 ]
  [[ "$output" == *"evaluation failed"* ]]

  haus_sh 'rebuild_failed build'
  [ "$status" -eq 1 ]
  [[ "$output" == *"build failed"* ]]

  haus_sh 'rebuild_failed activate'
  [ "$status" -eq 1 ]
  # The generation still on disk is the one thing this message must carry: it
  # is what `haus rollback` goes back to.
  [[ "$output" == *"418"* ]]
  [[ "$output" == *"haus rollback"* ]]
  [ "$(crumb class)" = activate ]
}

# ---- which surface ----------------------------------------------------------

@test "fault_surface: banner when trill answers and no terminal is watching" {
  haus_sh 'fault_surface'
  [ "$output" = banner ]
}

@test "fault_surface: none when there is no trill" {
  haus_sh HAUS_TRILL=/nowhere/at/all 'fault_surface'
  [ "$output" = none ]
}

@test "fault_surface: none under HAUS_NO_BANNER, the same gate the card keeps" {
  haus_sh HAUS_NO_BANNER=1 'fault_surface'
  [ "$output" = none ]
}

# ---- the four gates ---------------------------------------------------------

@test "no fixer on PATH, no offer — and core never asks whether the AI room is on" {
  # The function stub is dropped for this one, so `command -v haus-fix` fails
  # exactly as it does on a machine with haus.ai.enable = false.
  run env HAUS_CONSUMER="$HAUS_CONSUMER" HAUS_LIB=1 HAUS_TRILL="$HAUS_TRILL" \
    ASKED="$ASKED" "$BASH" -c "
      set -uo pipefail; source '$SUBJECT'
      HAUS_LOG_DIR='$STATE'; FAULT_HOST=mbp; fault_cta resolve"
  [ "$status" -eq 0 ]
  [ ! -e "$ASKED" ]
  # And that gate is a `command -v`, which is the whole of core's coupling to
  # the AI room. AGENTS.md forbids the other kind, and the difference is not
  # observable from the outside — both spellings would pass the case above on a
  # machine that has the room switched on.
  haus_sh 'declare -f fault_cta'
  [[ "$output" == *"command -v haus-fix"* ]]
}

@test "a consumer with no git repo gets no offer — there would be no undo" {
  mkdir -p "$BATS_TEST_TMPDIR/nogit"
  : >"$BATS_TEST_TMPDIR/nogit/flake.nix"
  haus_sh HAUS_CONSUMER="$BATS_TEST_TMPDIR/nogit" 'fault_cta resolve'
  [ "$status" -eq 0 ]
  [ ! -e "$ASKED" ]
}

@test "HAUS_NO_FIX=1 turns the whole thing off" {
  haus_sh HAUS_NO_FIX=1 'fault_cta resolve'
  [ "$status" -eq 0 ]
  [ ! -e "$ASKED" ]
}

# ---- the holder -------------------------------------------------------------

@test "the pill runs the fix, and the ask carries what a person needs to answer it" {
  haus_sh 'fault_cta resolve'
  [ "$status" -eq 0 ]
  wait_for "$FIXED" || fail "haus-fix never ran"
  run cat "$ASKED"
  [[ "$output" == *"ask "* ]]
  [[ "$output" == *"--pill Fix it"* ]]
  [[ "$output" == *"--source haus.rebuild.fault"* ]]
  # Keyed, so a second failure REPLACES this fin rather than growing a second.
  [[ "$output" == *"--key haus-rebuild-fault"* ]]
}

@test "a dismissed ask runs nothing" {
  haus_sh ASK_RC=1 'fault_cta resolve'
  [ "$status" -eq 0 ]
  wait_for "$ASKED" || fail "no ask was put up"
  sleep 0.5
  [ ! -e "$FIXED" ]
}

@test "haus rebuild does not wait for the answer" {
  # The offer parks for as long as it takes; the rebuild is over. A holder that
  # blocked here would hold the shell prompt until someone clicked a banner.
  cat >"$BATS_TEST_TMPDIR/bin/trill" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ASKED"
sleep 30
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/trill"
  local t0 t1
  t0=$SECONDS
  haus_sh 'fault_cta resolve'
  t1=$SECONDS
  [ "$status" -eq 0 ]
  [ "$((t1 - t0))" -lt 5 ]
}

@test "a second failure reaps the holder waiting on the first" {
  cat >"$BATS_TEST_TMPDIR/bin/trill" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ASKED"
sleep 30
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/trill"
  haus_sh 'fault_cta resolve'
  wait_for "$STATE/fault-holder.pid" || fail "no holder recorded"
  local first
  first="$(cat "$STATE/fault-holder.pid")"
  haus_sh 'fault_cta build'
  # Reaped BEFORE the second ask goes up: the old holder retracts on its way
  # out, and a retraction landing after the new ask would take the new fin.
  run kill -0 "$first"
  [ "$status" -ne 0 ]
  local second
  second="$(cat "$STATE/fault-holder.pid")"
  [ "$second" != "$first" ]
}

@test "closing the window does not take the offer with it" {
  # The whole reason the holder is detached. A SIGHUP to the process group is
  # what Ghostty sends when its window closes, and trill retracts an ask whose
  # caller died — so a holder that merely backgrounded would lose the fin.
  command -v perl >/dev/null 2>&1 || skip "needs perl for setsid"
  cat >"$BATS_TEST_TMPDIR/bin/trill" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ASKED"
sleep 2
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/trill"
  cat >"$BATS_TEST_TMPDIR/drive.sh" <<DRIVE
#!/usr/bin/env bash
set -uo pipefail
haus-fix() { date >>"\$FIXED"; }
source '$SUBJECT'
HAUS_LOG_DIR='$STATE'
FAULT_HOST=mbp
fault_cta resolve
DRIVE
  # BASH is a shell variable, not an exported one — perl needs it handed over.
  run env HAUS_CONSUMER="$HAUS_CONSUMER" HAUS_LIB=1 HAUS_TRILL="$HAUS_TRILL" \
    ASKED="$ASKED" FIXED="$FIXED" BASH="$BASH" perl -e '
      use POSIX; setsid(); print "PGID=", getpgrp(), "\n";
      system($ENV{BASH} || "bash", $ARGV[0]);' "$BATS_TEST_TMPDIR/drive.sh"
  local pgid
  pgid="$(printf '%s\n' "$output" | sed -n 's/^PGID=//p')"
  [ -n "$pgid" ]
  kill -HUP "-$pgid" 2>/dev/null || true
  wait_for "$FIXED" 60 || fail "the holder died with the window"
}

# ---- what haus-fix refuses --------------------------------------------------
# Only the refusals: every one of them returns before any agent is spawned and
# before nix is called, so they need nothing but bash and git.

fixer() { # fixer <VAR=val…> — the substituted script, run against $STATE
  local sub="$BATS_TEST_TMPDIR/haus-fix"
  sed -e 's/@client@/stubagent/' -e 's/@oneshot@/stubagent --oneshot --/' \
    "$FIXER" >"$sub"
  chmod +x "$sub"
  run env "$@" XDG_STATE_HOME="$BATS_TEST_TMPDIR/xdg" HAUS_NOTIFY=off "$sub"
}

write_crumb() { # write_crumb <consumer>
  mkdir -p "$BATS_TEST_TMPDIR/xdg/haus"
  cat >"$BATS_TEST_TMPDIR/xdg/haus/last-failure" <<EOF
class=resolve
host=mbp
consumer=$1
log=$STATE/rebuild.log
offset=0
drv=
gen=418
when=2026-08-31 14:02:11
EOF
}

@test "haus-fix: nothing to fix without a breadcrumb" {
  rm -rf "$BATS_TEST_TMPDIR/xdg"
  fixer
  [ "$status" -eq 2 ]
  [[ "$output" == *"no failed rebuild recorded"* ]]
}

@test "haus-fix: refuses a consumer with no git repo, naming the undo it wants" {
  mkdir -p "$BATS_TEST_TMPDIR/nogit2"
  write_crumb "$BATS_TEST_TMPDIR/nogit2"
  fixer
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a git repo"* ]]
  [[ "$output" == *"revert HEAD"* ]]
}

@test "haus-fix: refuses when the client haus.ai.default names is not installed" {
  write_crumb "$HAUS_CONSUMER"
  fixer
  [ "$status" -eq 2 ]
  [[ "$output" == *"stubagent is not on PATH"* ]]
}

@test "haus-fix: one at a time" {
  write_crumb "$HAUS_CONSUMER"
  mkdir -p "$BATS_TEST_TMPDIR/bin2"
  cat >"$BATS_TEST_TMPDIR/bin2/stubagent" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin2/stubagent"
  mkdir -p "$BATS_TEST_TMPDIR/xdg/haus/fix.lock"
  fixer PATH="$BATS_TEST_TMPDIR/bin2:$PATH"
  [ "$status" -eq 2 ]
  [[ "$output" == *"already running"* ]]
}

@test "haus-fix --dry-run prints the prompt and spawns nothing" {
  write_crumb "$HAUS_CONSUMER"
  mkdir -p "$BATS_TEST_TMPDIR/bin2"
  cat >"$BATS_TEST_TMPDIR/bin2/stubagent" <<'STUB'
#!/usr/bin/env bash
touch "$BATS_TEST_TMPDIR/agent-ran"
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin2/stubagent"
  local sub="$BATS_TEST_TMPDIR/haus-fix"
  sed -e 's/@client@/stubagent/' -e 's/@oneshot@/stubagent --oneshot --/' \
    "$FIXER" >"$sub"
  chmod +x "$sub"
  run env PATH="$BATS_TEST_TMPDIR/bin2:$PATH" XDG_STATE_HOME="$BATS_TEST_TMPDIR/xdg" \
    HAUS_NOTIFY=off "$sub" --dry-run
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/agent-ran" ]
  # The four things the prompt must carry, and the one it must forbid.
  [[ "$output" == *"mbp"* ]]
  [[ "$output" == *"resolve"* ]]
  [[ "$output" == *"nix eval"* ]]
  [[ "$output" == *"Do NOT run \`haus rebuild\`"* ]]
  # Deliberately silent about where it may commit: the instructions this
  # machine already writes for every client answer that, and a second copy
  # here would drift away from them.
  [[ "$output" != *"commit to main"* ]]
}

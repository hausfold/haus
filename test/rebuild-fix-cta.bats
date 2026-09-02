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
# of a completed fix (fixed / nothing changed / still broken). Those need a real
# flake and a nix evaluation, which is not worth a CI dependency.
#
# The in-pane `gum` rows used to be on that list too, on the grounds that they
# need a pty. They needed no such thing: what broke them was a redirect that
# threw away the stream gum draws on, and a stub that draws where gum draws
# catches it without a terminal at all. "Only testable by hand" was the reason
# it shipped invisible — see the rows section below.

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

fail() { printf '%s\n' "$*" >&2; return 1; }   # not a bats builtin

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

wait_gone() { # wait_gone <pid> [tries] — polled, because the holder exits only
  local i    # once the ask it INTed has actually gone, which is a round trip
  for ((i = 0; i < ${2:-40}; i++)); do
    kill -0 "$1" 2>/dev/null || return 0
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

# ---- the in-pane rows -------------------------------------------------------

# gum draws the picker on STDERR, so that `$( )` can take the selection off
# stdout. Redirecting stderr away therefore does not quiet gum — it deletes the
# only thing the person is meant to see, while gum still blocks for its whole
# timeout. That shipped once (hausfold/haus#592): a failed rebuild, thirty
# seconds of nothing, prompt back, indistinguishable from the feature being
# off. No pty is needed to hold the line, only a stub that draws where gum
# draws — and a function, for the PATH reason at the top of this file.
@test "fault_rows: gum's UI reaches the terminal rather than /dev/null" {
  haus_sh "gum() { printf 'ROWS-DREW\n' >&2; printf 'Fix it with AI\n'; }
    fault_rows"
  [ "$status" -eq 0 ]
  [[ "$output" == *ROWS-DREW* ]] || fail "gum's picker was swallowed — the rows never render"
  [ -s "$FIXED" ]
}

@test "fault_rows: 'Not now' and an expired timeout both leave haus-fix alone" {
  haus_sh "gum() { printf 'Not now\n'; }
    fault_rows"
  [ "$status" -eq 0 ]
  [ ! -s "$FIXED" ]

  # gum 0.17 returns 124 with no selection when --timeout expires, rather than
  # committing the row under the cursor. A walked-away prompt must not fix.
  haus_sh "gum() { return 124; }
    fault_rows"
  [ "$status" -eq 0 ]
  [ ! -s "$FIXED" ]
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

@test "a second failure supersedes the first, before its ask goes up" {
  # 75 is trill's "nobody answered", so the stub retracts quickly and no fix
  # runs on either holder — what is under test is the ordering, not the pill.
  cat >"$BATS_TEST_TMPDIR/bin/trill" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ASKED"
sleep 0.3
exit 75
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/trill"
  haus_sh 'fault_cta resolve'
  wait_for "$STATE/fault-holder.pid" || fail "no holder recorded"
  local first
  first="$(cat "$STATE/fault-holder.pid")"
  haus_sh 'fault_cta build'
  local second
  second="$(cat "$STATE/fault-holder.pid")"
  [ "$second" != "$first" ]
  # Gone before the second ask went up. The old holder retracts on its way out
  # and both asks carry ONE key, so a retraction landing late would take the
  # NEW fin down — which is silent, and leaves the second failure with no offer.
  wait_gone "$first" 10 || fail "the superseded holder is still up"
  run grep -c -- '--key haus-rebuild-fault' "$ASKED"
  [ "$output" = 2 ]
  sleep 0.5
  [ ! -e "$FIXED" ]
}

@test "a reaped holder waits for its own ask to go, rather than exiting on the signal" {
  # The regression this pins is a one-character one. `wait "$child"; rc=$?`
  # under `set -e` exits the subshell the instant the relayed TERM lands —
  # measured — which skips the reap and leaves the retraction in flight while
  # the next ask, under the same key, is already going up. So: TERM the holder
  # and it must still be there, waiting on the child it just interrupted.
  cat >"$BATS_TEST_TMPDIR/bin/trill" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ASKED"
sleep 5
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/trill"
  haus_sh 'fault_cta resolve'
  wait_for "$STATE/fault-holder.pid" || fail "no holder recorded"
  local pid
  pid="$(cat "$STATE/fault-holder.pid")"
  wait_for "$ASKED" || fail "no ask was put up"
  kill -TERM "$pid"
  sleep 0.5
  run kill -0 "$pid"
  [ "$status" -eq 0 ]
  # And it never treats a signalled wait as a pressed pill.
  [ ! -e "$FIXED" ]
  kill -KILL "$pid" 2>/dev/null || true
}

@test "a rebuild that succeeds ends the last failure's offer" {
  # The crumb names a log `log_open` rotates every run, and the ask carries no
  # timeout — so without this a fin can sit for days and then spawn an agent,
  # unattended and with its gate open, at a config that is fine, holding a
  # slice of a SUCCESSFUL rebuild's log as "what the failure said".
  cat >"$BATS_TEST_TMPDIR/bin/trill" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$ASKED"
[ "${1:-}" = resolve ] && exit 0
sleep 0.3
exit 75
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/trill"
  haus_sh 'fault_crumb resolve; fault_cta resolve'
  wait_for "$STATE/fault-holder.pid" || fail "no holder recorded"
  local pid
  pid="$(cat "$STATE/fault-holder.pid")"
  [ -e "$CRUMB" ] || fail "no crumb to clear"

  haus_sh 'fault_clear'
  [ "$status" -eq 0 ]
  [ ! -e "$CRUMB" ]
  wait_gone "$pid" || fail "the holder is still waiting on a fin for a rebuild that succeeded"
  # The fin is taken down by KEY as well, for the holder that was already gone
  # — killed -9, or a reboot — and only trill still remembers.
  run grep -c 'resolve haus-rebuild-fault' "$ASKED"
  [ "$output" = 1 ]
}

@test "no surface still says the offer exists" {
  # A pipe, CI, a machine with banners off: there is still a fixer and still an
  # undo, and silence here would make the feature undiscoverable on exactly the
  # machines whose owner reads the transcript afterwards.
  haus_sh HAUS_TRILL=/nowhere/at/all 'fault_cta resolve'
  [ "$status" -eq 0 ]
  [[ "$output" == *"haus fix"* ]]
  [ ! -e "$ASKED" ]
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

# snug's bash painter, wherever this machine keeps it — the same probe
# awake-ui.bats, haus-secret.bats and phase-painter.bats use. Above
# `build_fixer` because that bakes the answer into the subject's @uiSh@ hole.
real_ui_sh() {
  local q
  for q in "${HAUS_UI_SH:-}" \
           "$BATS_TEST_DIRNAME/../../snug/share/ui.sh" \
           "$HOME/code/workshop/snug/share/ui.sh"; do
    [ -n "$q" ] && [ -r "$q" ] && { printf '%s' "$q"; return 0; }
  done
  return 1
}

# ---- what haus-fix refuses --------------------------------------------------
# Only the refusals: every one of them returns before any agent is spawned and
# before nix is called, so they need nothing but bash and git.

# The substituted script, with its PATH preamble stripped. That preamble
# PREPENDS the system profile so a launchd-ish caller can find nix at all, which
# also puts the real `nix` and the real `haus-notify` ahead of anything a test
# can add — and two cases below turn on what `nix eval` answers. Same seam
# phase-painter.bats documents for `snug`, cut one line higher up.
build_fixer() {
  local sub="$BATS_TEST_TMPDIR/haus-fix" ui
  # @uiSh@ baked in rather than left literal, so the painted cases below drive
  # the SUBSTITUTED default — which is the path every real machine takes, since
  # nothing sets HAUS_UI_SH for a binary a trill pill exec'd. An unresolvable
  # path is a fine value: `[ -r ]` is false and the fallback line is what the
  # unpainted cases want anyway.
  ui="$(real_ui_sh || printf '%s' "$BATS_TEST_TMPDIR/no-such-ui.sh")"
  sed -e 's/@client@/stubagent/' -e 's/@oneshot@/stubagent --oneshot --/' \
    -e "s|@uiSh@|$ui|" \
    -e '/^PATH="\/run\/current-system\/sw\/bin/d' -e '/^export PATH$/d' \
    "$FIXER" >"$sub"
  chmod +x "$sub"
  printf '%s' "$sub"
}

fixer() { # fixer <VAR=val…> — the substituted script, run against $STATE
  local sub
  sub="$(build_fixer)"
  run env "$@" XDG_STATE_HOME="$BATS_TEST_TMPDIR/xdg" HAUS_NOTIFY=off "$sub"
}

fixer_args() { # fixer_args <arg…> <VAR=val…> — args first, env after
  local sub a args=() envs=()
  sub="$(build_fixer)"
  for a in "$@"; do
    case "$a" in *=*) envs+=("$a") ;; *) args+=("$a") ;; esac
  done
  run env "${envs[@]}" XDG_STATE_HOME="$BATS_TEST_TMPDIR/xdg" HAUS_NOTIFY=off \
    "$sub" ${args[@]+"${args[@]}"}
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

@test "haus-fix refuses a stale resolve crumb rather than spawning at a healthy config" {
  # A fin answered days later, or `haus fix` typed from memory. The agent would
  # run unattended, gate open, holding some other rebuild's log as the error.
  write_crumb "$HAUS_CONSUMER"
  mkdir -p "$BATS_TEST_TMPDIR/bin2"
  cat >"$BATS_TEST_TMPDIR/bin2/stubagent" <<STUB
#!/usr/bin/env bash
touch "$BATS_TEST_TMPDIR/agent-ran"
STUB
  # a nix whose eval SUCCEEDS — i.e. the config is fine now
  cat >"$BATS_TEST_TMPDIR/bin2/nix" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin2/stubagent" "$BATS_TEST_TMPDIR/bin2/nix"
  fixer_args PATH="$BATS_TEST_TMPDIR/bin2:$PATH"
  [ "$status" -eq 2 ]
  [[ "$output" == *"that failure is over"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/agent-ran" ]
}

@test "haus-fix does NOT ask that of a build failure, which evaluates by definition" {
  mkdir -p "$BATS_TEST_TMPDIR/xdg/haus"
  cat >"$BATS_TEST_TMPDIR/xdg/haus/last-failure" <<EOF
class=build
host=mbp
consumer=$HAUS_CONSUMER
log=$STATE/rebuild.log
offset=0
drv=/nix/store/deadbeef.drv
gen=418
when=2026-08-31 14:02:11
EOF
  mkdir -p "$BATS_TEST_TMPDIR/bin2"
  cat >"$BATS_TEST_TMPDIR/bin2/stubagent" <<STUB
#!/usr/bin/env bash
touch "$BATS_TEST_TMPDIR/agent-ran"
STUB
  cat >"$BATS_TEST_TMPDIR/bin2/nix" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin2/stubagent" "$BATS_TEST_TMPDIR/bin2/nix"
  fixer_args PATH="$BATS_TEST_TMPDIR/bin2:$PATH"
  [ -e "$BATS_TEST_TMPDIR/agent-ran" ]
}

@test "haus-fix refuses a flag it does not know" {
  write_crumb "$HAUS_CONSUMER"
  fixer_args --yolo
  [ "$status" -eq 64 ]
  [[ "$output" == *"usage: haus fix"* ]]
}

@test "haus-fix --dry-run runs no build either, on the class that would need one" {
  # The build phase keeps the terminal, so its error is re-derived with a real
  # `nix build` — minutes of it. "Print the prompt, run nothing" has to mean
  # that one too, and the prompt names the command instead.
  mkdir -p "$BATS_TEST_TMPDIR/xdg/haus"
  cat >"$BATS_TEST_TMPDIR/xdg/haus/last-failure" <<EOF
class=build
host=mbp
consumer=$HAUS_CONSUMER
log=$STATE/rebuild.log
offset=0
drv=/nix/store/deadbeef.drv
gen=418
when=2026-08-31 14:02:11
EOF
  mkdir -p "$BATS_TEST_TMPDIR/bin2"
  for stub in stubagent nix; do
    cat >"$BATS_TEST_TMPDIR/bin2/$stub" <<STUB
#!/usr/bin/env bash
touch "$BATS_TEST_TMPDIR/ran-$stub"
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin2/$stub"
  done
  fixer_args --dry-run PATH="$BATS_TEST_TMPDIR/bin2:$PATH"
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/ran-stubagent" ]
  [[ "$output" == *"nix build -L /nix/store/deadbeef.drv"* ]]
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

# ---- the wait, said in the pane ---------------------------------------------
# The gum redirect's lesson, applied one layer down. Pressing "Fix it with AI"
# in a pane drew the rows and then went SILENT for the whole length of a
# headless turn — not a slow client, but print mode doing exactly what print
# mode does: buffer the answer to the end. So the pane got a rebuild that
# failed, two rows, and then a minute of nothing with the only sign of life a
# trill card on the other side of the screen. Reported from feel-testing #592
# on a live machine, the run after the rows themselves started drawing.
#
# A pty is fifteen lines of python (awake-ui.bats carries the same helper), so
# "you have to be sitting at it" is again not a reason to leave it untested.

# A client that takes long enough to spin and says something recognisable, plus
# a `nix` that answers yes. `sleep` is what makes the case real: an agent that
# returns instantly never enters the paint loop at all.
slow_stubs() {
  mkdir -p "$BATS_TEST_TMPDIR/bin2"
  cat >"$BATS_TEST_TMPDIR/bin2/stubagent" <<'STUB'
#!/usr/bin/env bash
sleep 0.4
printf 'STUB-ANSWER: fixed the typo\n'
exit 0
STUB
  # Two answers from one stub, because `haus-fix` asks `nix eval` twice and the
  # two questions are opposites: FIRST the staleness probe (a resolve crumb
  # whose config already evaluates is refused before anything is spawned —
  # see the case above), THEN the check on the client's work. So: broken, then
  # fixed, which is the whole story this suite is telling.
  cat >"$BATS_TEST_TMPDIR/bin2/nix" <<STUB
#!/usr/bin/env bash
sleep 0.2
printf 'x' >>"$BATS_TEST_TMPDIR/nixcalls"
[ "\$(wc -c <"$BATS_TEST_TMPDIR/nixcalls" | tr -d ' ')" -gt 1 ]
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin2/stubagent" "$BATS_TEST_TMPDIR/bin2/nix"
}

# Run an argv on a pty and hand back its raw bytes, both streams merged the way
# a terminal merges them.
pty_run() { # pty_run <arg…>
  # PYTHONIOENCODING is not optional, and it is python3's rather than the
  # subject's: python writes the bytes it read back out through ITS stdout,
  # whose encoding follows the locale, and everything here is non-ASCII — the
  # braille spinner, the ✓, the em dash in `note`. A runner without
  # en_US.UTF-8 generated raises UnicodeEncodeError on the first frame rather
  # than failing an assertion. awake-ui.bats pins it in `setup()` for this.
  PYTHONIOENCODING=utf-8 python3 - "$@" <<'PYEOF'
import os, pty, sys, fcntl, termios, struct, select
cmd = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
out = b""
while True:
    r, _, _ = select.select([fd], [], [], 20)
    if not r: break
    try: chunk = os.read(fd, 65536)
    except OSError: break
    if not chunk: break
    out += chunk
os.waitpid(pid, 0)
sys.stdout.write(out.decode("utf-8", "replace"))
PYEOF
}

@test "the pane spins a row while the client thinks, and prints its answer under it" {
  local ui; ui="$(real_ui_sh || true)"
  [ -n "$ui" ] || skip "no snug share/ui.sh on this machine"
  write_crumb "$HAUS_CONSUMER"
  slow_stubs
  local sub seen; sub="$(build_fixer)"
  # TERM and LANG pinned for the reason awake-ui.bats pins them: a GitHub runner
  # sets TERM=dumb for every step, which ui.sh honours absolutely, and an
  # unpinned locale picks the ASCII marks over the UTF-8 ones.
  seen="$(pty_run env PATH="$BATS_TEST_TMPDIR/bin2:$PATH" \
    XDG_STATE_HOME="$BATS_TEST_TMPDIR/xdg" HAUS_NOTIFY=off \
    TERM=xterm-256color LANG=en_US.UTF-8 "$sub")"
  # The row, named for the client and for what it is doing — this is the whole
  # complaint. Red against the pre-spinner script, which drew nothing at all
  # between the rows and the outcome.
  [[ "$seen" == *"stubagent"* ]] || { printf 'no client row: %q\n' "$seen"; false; }
  [[ "$seen" == *"fixing the resolve failure"* ]] \
    || { printf 'the row does not say what it is waiting on: %q\n' "$seen"; false; }
  # It really painted a region rather than printing a line: the cursor hide is
  # ui_live_open's first byte, and only the live path emits one.
  [[ "$seen" == *$'\033[?25l'* ]] || { printf 'nothing painted: %q\n' "$seen"; false; }
  # …and gave the cursor back. A terminal left without one is the worst thing a
  # spinner can do to you, and every path here ends in `ui_live_close`.
  [[ "$seen" == *$'\033[?25h'* ]] || { printf 'cursor never restored: %q\n' "$seen"; false; }
  # The second silence gets its own row.
  [[ "$seen" == *"checking the config evaluates"* ]] \
    || { printf 'the eval wait is unsaid: %q\n' "$seen"; false; }
  # The answer still reaches the pane. It is read back out of $FIXLOG from the
  # offset the turn started at, because the run itself is redirected there — a
  # spinner and a live `tee` of one terminal fight over the cursor.
  [[ "$seen" == *"STUB-ANSWER: fixed the typo"* ]] \
    || { printf 'the client answer never landed: %q\n' "$seen"; false; }
}

@test "no terminal, no escapes: the banner path keeps the plain line it always had" {
  # The other half, and the one that must not regress: `haus fix` from the trill
  # pill runs in a detached holder with both streams on /dev/null, and a CI or a
  # pipe gets the same. One `note` line per wait, no cursor escape anywhere.
  local ui; ui="$(real_ui_sh || true)"
  [ -n "$ui" ] || skip "no snug share/ui.sh on this machine"
  write_crumb "$HAUS_CONSUMER"
  slow_stubs
  fixer PATH="$BATS_TEST_TMPDIR/bin2:$PATH"
  [[ "$output" != *$'\033['* ]] \
    || { printf 'escapes reached a pipe: %s\n' "$(printf '%s' "$output" | sed -n l)"; false; }
  [[ "$output" == *"fixing the resolve failure"* ]] \
    || { printf 'the wait is unsaid on a pipe too: %s\n' "$output"; false; }
}

@test "a client that fails still reaches the still-broken verdict" {
  # `spin_wait` hands back the job's own status, which is the only thing the
  # outcome lines below it read. A spinner that swallowed it would report a
  # crashed client as a quiet success.
  local ui; ui="$(real_ui_sh || true)"
  [ -n "$ui" ] || skip "no snug share/ui.sh on this machine"
  write_crumb "$HAUS_CONSUMER"
  mkdir -p "$BATS_TEST_TMPDIR/bin2"
  cat >"$BATS_TEST_TMPDIR/bin2/stubagent" <<'STUB'
#!/usr/bin/env bash
exit 7
STUB
  # a nix whose eval FAILS — the config is still broken after the client ran
  cat >"$BATS_TEST_TMPDIR/bin2/nix" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin2/stubagent" "$BATS_TEST_TMPDIR/bin2/nix"
  local sub seen; sub="$(build_fixer)"
  seen="$(pty_run env PATH="$BATS_TEST_TMPDIR/bin2:$PATH" \
    XDG_STATE_HOME="$BATS_TEST_TMPDIR/xdg" HAUS_NOTIFY=off \
    TERM=xterm-256color LANG=en_US.UTF-8 "$sub")"
  # The row wears the client's own status. A spinner that swallowed it would
  # leave a crashed client looking like a quiet success on the way past.
  [[ "$seen" == *"exit 7"* ]] || { printf 'the client status was swallowed: %q\n' "$seen"; false; }
  [[ "$seen" == *"still broken"* ]] || { printf 'no verdict: %q\n' "$seen"; false; }
}

@test "cancelling the wait stops the agent, and only then drops the lock" {
  # The hazard the backgrounded turn introduced, and it is not obvious: bash's
  # `wait` RETURNS on a trapped signal, where a foreground command defers the
  # trap until it finishes. So a ^C that used to reach the client now reaches
  # the handler first — and a handler that merely dropped the lock and exited
  # would leave an agent that caught the signal itself still editing the config
  # flake with its permission gate open, while the one-at-a-time lock it was
  # holding is released for the next `haus fix` to walk into.
  write_crumb "$HAUS_CONSUMER"
  mkdir -p "$BATS_TEST_TMPDIR/bin2"
  # A client that catches the signal for a graceful shutdown — claude and codex
  # both do — so a TERM the handler sends must not be taken for "it stopped".
  cat >"$BATS_TEST_TMPDIR/bin2/stubagent" <<STUB
#!/usr/bin/env bash
trap '' TERM INT HUP
printf '%s' \$\$ >"$BATS_TEST_TMPDIR/agentpid"
while :; do sleep 0.2; done
STUB
  cat >"$BATS_TEST_TMPDIR/bin2/nix" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin2/stubagent" "$BATS_TEST_TMPDIR/bin2/nix"

  local sub fixpid agent i
  sub="$(build_fixer)"
  env PATH="$BATS_TEST_TMPDIR/bin2:$PATH" XDG_STATE_HOME="$BATS_TEST_TMPDIR/xdg" \
    HAUS_NOTIFY=off "$sub" >"$BATS_TEST_TMPDIR/cancel-out" 2>&1 &
  fixpid=$!
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 \
           21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40; do
    [ -s "$BATS_TEST_TMPDIR/agentpid" ] && break
    sleep 0.1
  done
  [ -s "$BATS_TEST_TMPDIR/agentpid" ] || fail "the stub client never started"
  agent="$(cat "$BATS_TEST_TMPDIR/agentpid")"
  [ -d "$BATS_TEST_TMPDIR/xdg/haus/fix.lock" ] || fail "no lock while a fix runs"

  kill -TERM "$fixpid"
  wait "$fixpid" || true

  # The agent is gone. It ignored TERM, so only the escalation can have done it
  # — this case is red against a handler that just released the lock and left.
  for i in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$agent" 2>/dev/null || break
    sleep 0.1
  done
  if kill -0 "$agent" 2>/dev/null; then
    kill -KILL "$agent" 2>/dev/null || true
    fail "the agent outlived the cancel — it is still editing the config flake"
  fi
  # …and the lock went with it, so the button is not dead afterwards.
  [ ! -d "$BATS_TEST_TMPDIR/xdg/haus/fix.lock" ] \
    || fail "the lock survived the cancel — every later haus fix says 'already running'"
}

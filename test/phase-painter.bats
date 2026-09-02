#!/usr/bin/env bats
# How the two end-user CLIs put a line on screen: the `haus rebuild` phase
# painter, the colour gate, and the `snug run` coprocess both of them draw
# through. The standard is docs/cli-presentation.md in the workshop.
#
# What this suite is FOR. Neither half fails loudly on the machine that writes
# it: a maximised terminal never sees a fold, a developer watching colour never
# sees an ungated escape, and a record `snug run` cannot parse produces a line
# that simply never appears. All three are pinned here.
#
# Where the boundary is. Folding, the tiers, the budget, the resize and the
# cursor are SNUG's now, and snug's own suite tests them — this one tests what
# haus does: which verb, on which stream, in which record, and what happens on
# each rung of the degrade ladder when the painter is not there.
#
#   snug on PATH + a terminal on fd 2   the coprocess
#   ui.sh only                          its live region and its lines
#   neither                             plain text on fd 2, and nothing dies
#
# ui.sh is the REAL file, fetched in CI at the rev flake.lock pins (see the
# workflow step beside the one that runs this). A fixture would have made the
# integration green while checking nothing, which is the failure this repo has
# already been bitten by once.
#
# haus.sh is sourced as a library (HAUS_LIB=1, the same seam test/haus-plan.sh
# uses) so the verbs can be called directly, on streams no window has to have.

setup() {
  SUBJECT="$BATS_TEST_DIRNAME/../modules/core/haus.sh"
  SHOW="$BATS_TEST_DIRNAME/../modules/core/haus-show.sh"
  # haus.sh refuses to load without a config flake; HAUS_LIB stops it before the
  # dispatch but not before that guard, so give it an empty one.
  export HAUS_CONSUMER="$BATS_TEST_TMPDIR/consumer"
  mkdir -p "$HAUS_CONSUMER"
  : >"$HAUS_CONSUMER/flake.nix"
  # Pinned, because the colour gate reads it and the two machines that run this
  # disagree: a developer's terminal says xterm-256color, and a GitHub runner
  # sets TERM=dumb for every `run:` step. ui.sh honours `dumb` even under
  # CLICOLOR_FORCE — there is no escape a dumb terminal will not print at you
  # literally — so without this the forced-colour cases pass locally and fail in
  # CI, which is the worst way round. `dumb` gets its own case below.
  export TERM=xterm-256color
  unset NO_COLOR CLICOLOR_FORCE COLORTERM SNUG_VARIANT
  UI_SH_REAL="$(real_ui_sh || true)"
}

# snug's `share/ui.sh`, wherever this machine keeps it: the path CI exports, a
# snug checkout beside this one, or the store path a haus machine's own wrapper
# points at. Empty when there is none — the rungs below it still have to pass.
real_ui_sh() {
  local p
  for p in "${HAUS_UI_SH:-}" \
           "$BATS_TEST_DIRNAME/../../snug/share/ui.sh" \
           "$HOME/code/workshop/snug/share/ui.sh"; do
    [ -n "$p" ] && [ -r "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
}
need_ui() { [ -n "$UI_SH_REAL" ] || skip "no snug share/ui.sh on this machine"; }

# Load haus.sh as a library in a FRESH shell and run a snippet. A fresh one, not
# setup()'s in-process source, because half of what is under test happens at
# load: the guarded `source`, the gate, and `set -euo pipefail` over both.
haus_sh() { # haus_sh <VAR=val…> <snippet>
  local snippet="${!#}"
  run env "${@:1:$#-1}" HAUS_CONSUMER="$HAUS_CONSUMER" HAUS_LIB=1 "$BASH" -c \
    "set -euo pipefail; source '$SUBJECT'; $snippet"
}

# A stand-in for the binary that records what it was fed. It is the only way to
# read the wire: a real `snug run` renders the records and throws them away.
#
# A FUNCTION rather than a script on PATH, and that is not a shortcut — haus.sh
# PREPENDS the system profile to PATH at load (line ~36, so a sudo or login-item
# shell can find nix at all), which puts the real `snug` ahead of any directory a
# test could add. `command -v` finds a function first, so this is the one seam
# that actually shadows it.
#
# `UI_TTY=1` is the other seam: it is ui.sh's own measurement of fd 2, and
# forcing it opens the coprocess with no terminal in sight, which is what lets
# bats watch the path a window would take. `snug_close` at the end of a snippet
# is not tidiness — it closes the write end and REAPS the coprocess, so the
# records are on disk before the assertion reads them.
SNUG_STUB='snug() { printf "INVOCATION\n" >>"$FORKS"; case "${1:-}" in run) cat >>"$RECORDS";; esac; }'

stub_env() { # stub_env — the two paths the stub writes, as env assignments
  : >"$BATS_TEST_TMPDIR/records"
  : >"$BATS_TEST_TMPDIR/forks"
  printf 'RECORDS=%s FORKS=%s' "$BATS_TEST_TMPDIR/records" "$BATS_TEST_TMPDIR/forks"
}
# The snippet's records. A trailing `end` is dropped: that one is the harness's
# own `snug_close`, which every snippet needs in order to reap the coprocess
# before the assertion reads the file, and it is not something haus sent.
records() { sed '$ { /^end$/d; }' "$BATS_TEST_TMPDIR/records"; }
forks()   { grep -c . "$BATS_TEST_TMPDIR/forks" 2>/dev/null || true; }
# Records are TAB-separated and the tabs are the assertion, so show them.
show_records() { sed -n 'l' "$BATS_TEST_TMPDIR/records"; }

# haus_snug <snippet> — load haus.sh with the stub shadowing the binary.
haus_snug() {
  local e; e="$(stub_env)"
  # shellcheck disable=SC2086
  haus_sh $e "$SNUG_STUB; UI_TTY=1; $1; snug_close"
}

# ── the record grammar ───────────────────────────────────────────────────────
# `snug run` splits on tabs, verb first, and answers `unknown record` to
# anything else — including a verb followed by a space, which is exactly what a
# careless `printf '%s %s\n'` would send. None of that is visible from the
# calling side: a bad record renders as a line that never appears.
#
# Each snippet below opens the region itself, because a message verb no longer
# does — see "a message verb never opens the coprocess", further down. What is
# under test here is what goes on the wire once one is open.

@test "each message verb sends one tab-separated record, verb first" {
  haus_snug "snug_open; say hello; warn careful; hint 'try this'"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(records)" = "$(printf 'say\thello\nwarn\tcareful\nhint\ttry this')" ] \
    || { echo "got:"; show_records; false; }
}

@test "die sends a fail record and still exits 1" {
  # No `snug_close` here: `die` exits, which is the path a real one takes, and
  # the coprocess's write end closes with the shell.
  local e; e="$(stub_env)"
  # shellcheck disable=SC2086
  haus_sh $e "$SNUG_STUB; UI_TTY=1; snug_open; die 'the end'; echo UNREACHED"
  [ "$status" -eq 1 ] || { echo "die exited $status: $output"; false; }
  [[ "$output" != *UNREACHED* ]]
  [ "$(records)" = "$(printf 'fail\tthe end')" ] || { echo "got:"; show_records; false; }
}

@test "multi-line text is one record per line, not one record with newlines" {
  # A newline inside a record breaks the framing for everything after it, so the
  # emitter folds — and the fold has to keep the verb, or the second line comes
  # out as an unknown record instead of a second line.
  haus_snug "snug_open; say \$'one\ntwo'"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(records)" = "$(printf 'say\tone\nsay\ttwo')" ] || { echo "got:"; show_records; false; }
}

@test "one coprocess for the whole command, not one fork per line" {
  # The entire economy of `run` over `snug say`: a fork is ~4.4 ms and a rebuild
  # draws sixty lines, so per-line would be a third of a second of pure overhead.
  haus_snug "snug_open; for i in 1 2 3 4 5 6 7 8 9 10; do say \"line \$i\"; done"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(forks)" -eq 1 ] || { echo "forked $(forks) times for ten lines"; false; }
  [ "$(records | grep -c '^say')" -eq 10 ] || { echo "got:"; show_records; false; }
}

@test "a message verb never opens the coprocess — only the phase painter does" {
  # A record crosses a pipe and is drawn by ANOTHER process on its stderr, while
  # the lines haus.sh prints itself — the blank that separates the header, a
  # failed phase's log tail — go straight to the terminal. Two writers on two
  # schedules put them in the wrong order. Inside a region there is no race,
  # because nothing here writes directly while one is up, which is what makes
  # "the region opens it" the whole rule. Five narrating lines, a terminal on
  # fd 2, snug on PATH: still zero forks.
  #
  # And the lines have to LAND. "Zero forks" is equally true of verbs that
  # became silent, which is the whole risk of moving them off the coprocess — so
  # the real painter is loaded and the words are counted on fd 2.
  need_ui
  local e; e="$(stub_env)"
  # shellcheck disable=SC2086
  haus_sh $e HAUS_UI_SH="$UI_SH_REAL" \
    "$SNUG_STUB; UI_TTY=1; { for i in 1 2 3; do say \"line \$i\"; done; warn w; hint h; } 1>/dev/null"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(forks)" -eq 0 ] || { echo "a message verb forked snug"; show_records; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'line 1\|line 2\|line 3\|w\|h')" -eq 5 ] \
    || { echo "lines went missing on the ui.sh path: $output"; false; }
}

@test "a background job that draws nothing drops the write end" {
  # snug_close closes the PARENT's copy and then waits for `snug run` to see
  # EOF. The duplicate is an ordinary fd — that is what lets the spinner
  # subshell write frames — so every `&` inherits one, and a job that merely
  # inherited it holds snug's stdin open. Measured before snug_detach existed:
  # snug_close blocked for exactly the lifetime of the background subshell. With
  # card_hold's ticker, whose loop exits only when the PARENT does, that is not
  # a delay but a deadlock — on `activate`, the phase whose failure the user
  # most needs to read.
  #
  # A real coprocess, not the stub: the stub is a shell function and the whole
  # question is what a forked process does with an inherited descriptor.
  command -v snug >/dev/null 2>&1 || skip "snug not on PATH"
  haus_sh "UI_TTY=1
    snug_open || { echo NO-COPROC; exit 0; }
    ( snug_detach; n=0; while [ \$n -lt 6 ]; do sleep 1; n=\$((n+1)); done ) &
    bg=\$!
    t0=\$(date +%s); snug_close; t1=\$(date +%s)
    echo \"waited \$(( t1 - t0 ))\"
    kill \$bg 2>/dev/null || true"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *NO-COPROC* ]] && skip "no terminal to open a coprocess on"
  local waited; waited="$(printf '%s\n' "$output" | sed -n 's/^waited //p')"
  [ -n "$waited" ] || { echo "no timing line: $output"; false; }
  [ "$waited" -le 2 ] || { echo "snug_close waited ${waited}s on a background job"; false; }
}

@test "a verb that prints nothing forks nothing" {
  # `haus get some.path` prints one line of data and no prose, and pays nothing
  # for a painter it never uses. It is the phase painter that opens one now, so
  # this holds for every phase-less command too — the case above is the one that
  # pins that; this one keeps the floor.
  haus_snug "true"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(forks)" -eq 0 ] || { echo "forked with nothing to draw"; false; }
}

@test "a snug that died once is never re-opened for the rest of the command" {
  # SNUG_TRIED. Re-opening per line would be a fork a line, and re-opening per
  # FRAME would be a fork a frame — the exact regression the coprocess exists to
  # prevent, and the one that would arrive during a rebuild's spinner. Asserted
  # as the invariant rather than by killing a coprocess and watching, because
  # that race is the thing that would make this test lie either way.
  haus_sh "SNUG_TRIED=1; snug_open && echo OPENED || echo STAYED-DEAD"
  [ "$output" = STAYED-DEAD ] || { echo "re-opened after a death: $output"; false; }

  local e; e="$(stub_env)"
  # shellcheck disable=SC2086
  haus_sh $e "$SNUG_STUB; UI_TTY=1; snug_open; snug_close; snug_open && echo OPENED || echo STAYED-DEAD"
  [ "$output" = STAYED-DEAD ] || { echo "close re-armed the open: $output"; false; }
  [ "$(forks)" -eq 1 ] || { echo "forked $(forks) times"; false; }
}

@test "with no painter and no snug the verbs still say their words" {
  # The failover has to be a failover, not a silence: a machine where `snug`
  # cannot run must still be told what happened.
  need_ui
  haus_sh HAUS_UI_SH="$UI_SH_REAL" \
    "snug_open() { return 1; }; { say one; say two; say three; } 2>&1 1>/dev/null"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'one\|two\|three')" -eq 3 ] \
    || { echo "lines went missing: $output"; false; }
}

# ── the phase region ─────────────────────────────────────────────────────────

@test "a phase opens a spinning row and closes the region on the finished one" {
  haus_snug "VERBOSE=; phase_start resolve; phase_ok resolve 3.4s"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # `run` spins, `ok` is the finished mark, `end` puts the last frame in
  # scrollback and gives the cursor back.
  [[ "$(records)" == "$(printf 'row\trun\tresolve\t0.0s\npaint')"* ]] \
    || { echo "got:"; show_records; false; }
  [ "$(records | tail -3)" = "$(printf 'row\tok\tresolve\t3.4s\npaint\nend')" ] \
    || { echo "got:"; show_records; false; }
}

@test "a failed phase closes the region too" {
  haus_snug "VERBOSE=; phase_start activate; phase_bad activate 9.9s"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(records | tail -3)" = "$(printf 'row\tfail\tactivate\t9.9s\npaint\nend')" ] \
    || { echo "got:"; show_records; false; }
}

@test "the elapsed and the detail share one column, and neither field is ever empty" {
  # `read` collapses consecutive delimiters, so a row must never carry an empty
  # field between two non-empty ones: `row<TAB>ok<TAB>name<TAB><TAB>detail` would
  # arrive as a three-field row and the detail would land in the wrong column.
  # Hence the join here rather than a second field.
  haus_snug "VERBOSE=;
    phase_ok activate 12.3s '12 services · homebrew changed'
    phase_ok build 4.0s
    phase_ok generation '' '3 → 4'"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(records)" == *"$(printf 'row\tok\tactivate\t12.3s · 12 services · homebrew changed')"* ]] \
    || { echo "joined wrong:"; show_records; false; }
  [[ "$(records)" == *"$(printf 'row\tok\tbuild\t4.0s')"* ]] || { show_records; false; }
  [[ "$(records)" == *"$(printf 'row\tok\tgeneration\t3 → 4')"* ]] || { show_records; false; }
  # No record anywhere carries two tabs in a row.
  [ "$(records | grep -c $'\t\t' || true)" -eq 0 ] || { echo "empty middle field:"; show_records; false; }
}

@test "the build phase's row lands even though it left nothing to repaint" {
  # nix keeps the terminal for its own progress bar, so `build` never opens a
  # region — but its finished row still has to arrive, folded like the others.
  haus_snug "VERBOSE=; phase_ok build 41.2s"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(records)" = "$(printf 'row\tok\tbuild\t41.2s\npaint\nend')" ] \
    || { echo "got:"; show_records; false; }
}

@test "the spinner actually spins, and the clock actually ticks" {
  # The regression this exists for shipped once and was invisible: bash CLOSES a
  # coprocess's own descriptors in every subshell it forks, so the background
  # frame loop's write failed with EBADF, `|| break` swallowed it, and the row
  # sat on its first glyph at 0.0s for the whole phase. Every other assertion in
  # this file passed with zero frames.
  haus_snug "VERBOSE=; phase_start resolve; sleep 0.55; phase_ok resolve 0.6s"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local frames
  frames="$(records | grep -c "^row"$'\t'"run"$'\t' || true)"
  [ "$frames" -ge 3 ] || { echo "only $frames running frames in 0.55s:"; show_records; false; }
  # And they carry a MOVING clock, not the same stale 0.0s repainted.
  local clocks
  clocks="$(records | grep "^row"$'\t'"run"$'\t' | cut -f4 | sort -u | grep -c .)"
  [ "$clocks" -ge 2 ] || { echo "the clock never moved:"; show_records; false; }
}

@test "a still phase draws a bullet and sends no second frame" {
  # PHASE_STILL is what `activate` runs under whenever sudo might ask for a
  # password: the prompt lands on /dev/tty, the same terminal the region
  # repaints, and the region's line count knows nothing about a line sudo
  # printed — so ten frames a second would rewind over the prompt and over what
  # you are typing into it. `wait`, not `run`, because a spinner glyph that
  # never turns reads as a hung terminal where a bullet reads as "queued".
  haus_snug "VERBOSE=; PHASE_STILL=1; phase_start activate; phase_ok activate 9.9s"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(records | head -2)" = "$(printf 'row\twait\tactivate\t0.0s\npaint')" ] \
    || { echo "got:"; show_records; false; }
  # Exactly two frames — the opening one and the finished one. A third means the
  # spin loop started anyway.
  [ "$(records | grep -c '^paint')" -eq 2 ] || { echo "it span:"; show_records; false; }
}

@test "verbose and a redirected stream open no region at all" {
  # PHASE_LABEL is what licenses every frame, and a live region off a terminal
  # would put cursor escapes into a log. VERBOSE is the person who asked for the
  # raw stream; the second case is everyone who never had a window.
  haus_snug "VERBOSE=1; phase_start resolve; echo \"[\$PHASE_LABEL]\""
  [ "$output" = "[]" ] || { echo "verbose painted: $output"; false; }
  [ "$(records)" = "" ] || { echo "verbose sent records:"; show_records; false; }

  local e; e="$(stub_env)"
  # shellcheck disable=SC2086
  haus_sh $e "$SNUG_STUB; UI_TTY=; VERBOSE=; phase_start resolve; echo \"[\$PHASE_LABEL]\""
  [ "$output" = "[]" ] || { echo "painted with no terminal: $output"; false; }
  [ "$(records)" = "" ] || { echo "no terminal, but records:"; show_records; false; }
}

@test "no cursor escape reaches a pipe" {
  # The whole reason the gate reads fd 2 rather than a guess: a rebuild whose
  # output is a file must leave a file somebody can read, not a frame.
  need_ui
  haus_sh HAUS_UI_SH="$UI_SH_REAL" \
    "VERBOSE=; phase_start resolve; phase_ok resolve 3.4s; phase_ok build 1.0s"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *$'\033['* ]] || { echo "escapes in a pipe: $(printf '%s' "$output" | sed -n l)"; false; }
}

# ── the streams ──────────────────────────────────────────────────────────────
# stdout carries DATA only. The message verbs are prose and live on fd 2; the
# REPORT verbs are the body of `haus doctor`, which this repo's own issue form
# asks people to paste, so they stay on fd 1 where a pipe can still catch them.

@test "a narrating command draws entirely on fd 2" {
  need_ui
  # 2>/dev/null over the whole block: what survives is fd 1 alone.
  run env HAUS_UI_SH="$UI_SH_REAL" HAUS_CONSUMER="$HAUS_CONSUMER" HAUS_LIB=1 "$BASH" -c \
    "set -euo pipefail; source '$SUBJECT'; REPORT=; { say a; warn b; hint c; } 2>/dev/null"
  [ -z "$output" ] || { echo "narration on stdout: $output"; false; }

  run env HAUS_UI_SH="$UI_SH_REAL" HAUS_CONSUMER="$HAUS_CONSUMER" HAUS_LIB=1 "$BASH" -c \
    "set -euo pipefail; source '$SUBJECT'; REPORT=; { say a; warn b; hint c; } 1>/dev/null"
  [ "$(printf '%s\n' "$output" | grep -c '^')" -eq 3 ] \
    || { echo "not three lines on stderr: $output"; false; }
}

@test "a report command draws entirely on fd 1, headers and warnings included" {
  # The flow this protects is named in .github/ISSUE_TEMPLATE/bug.yml: "paste
  # the output of `haus doctor`". A section header on stderr makes that paste an
  # unlabelled list of ticks, and a warning on stderr drops the finding the
  # person is reporting. Both were true of the first cut of this change.
  need_ui
  run env HAUS_UI_SH="$UI_SH_REAL" HAUS_CONSUMER="$HAUS_CONSUMER" HAUS_LIB=1 "$BASH" -c \
    "set -euo pipefail; source '$SUBJECT'; REPORT=1;
     { say header; warn finding; hint detail; ok fine; bad broken; info note; } 2>/dev/null"
  local n; n="$(printf '%s\n' "$output" | grep -c 'header\|finding\|detail\|fine\|broken\|note')"
  [ "$n" -eq 6 ] || { echo "only $n of 6 report lines on stdout: $output"; false; }

  run env HAUS_UI_SH="$UI_SH_REAL" HAUS_CONSUMER="$HAUS_CONSUMER" HAUS_LIB=1 "$BASH" -c \
    "set -euo pipefail; source '$SUBJECT'; REPORT=1;
     { say header; warn finding; hint detail; ok fine; bad broken; info note; } 1>/dev/null"
  [ -z "$output" ] || { echo "report leaked to stderr: $output"; false; }
}

@test "a report never opens the coprocess" {
  # It cannot use one: `snug run` draws on ITS stderr, which is the terminal,
  # not this command's stdout. Opening one anyway would be a fork for nothing
  # and half a report on the wrong stream.
  haus_snug "REPORT=1; say header; warn finding; hint detail"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(forks)" -eq 0 ] || { echo "a report forked snug"; show_records; false; }
}

@test "die is on fd 2 even inside a report" {
  # An error is not part of the report. `haus doctor >out` must still say why it
  # stopped, on the terminal, rather than burying it in the file.
  need_ui
  run env HAUS_UI_SH="$UI_SH_REAL" HAUS_CONSUMER="$HAUS_CONSUMER" HAUS_LIB=1 "$BASH" -c \
    "set -euo pipefail; source '$SUBJECT'; REPORT=1; { die 'the end'; } 2>/dev/null"
  [ "$status" -eq 1 ]
  [ -z "$output" ] || { echo "die landed on stdout: $output"; false; }
}

@test "the dispatch and the verbs agree about which commands are reports" {
  # The list lives in one place on purpose. This is the check that it is the
  # place everything reads — a command added to the dispatch and forgotten here
  # is a report that prints on stderr, and nothing else would notice.
  local listed
  listed="$(sed -n 's/^  \(status | doctor.*\))$/\1/p' "$SUBJECT" | tr -d ' ')"
  [ -n "$listed" ] || { echo "the REPORT arm is gone or was reflowed"; false; }
  local c
  for c in status doctor plan diff permissions btm generations get capture report; do
    [[ "|$listed|" == *"|$c|"* ]] || { echo "$c is not in the REPORT arm: $listed"; false; }
  done
}

# ── the colour gate ──────────────────────────────────────────────────────────
# Every escape in both CLIs now comes from snug's generated palette, so the gate
# is asserted by ROLE rather than by a hex index nobody should be typing.

@test "haus.sh emits no escape into a pipe, and every one under CLICOLOR_FORCE" {
  need_ui
  haus_sh HAUS_UI_SH="$UI_SH_REAL" "say hi; ok fine; warn careful; info detail"
  [[ "$output" != *$'\033['* ]] || { echo "ungated: $(printf '%s' "$output" | sed -n l)"; false; }
  [[ "$output" == *hi* ]]

  haus_sh HAUS_UI_SH="$UI_SH_REAL" CLICOLOR_FORCE=1 \
    'printf "%s|%s|%s|%s\n" "$C_FOG" "$C_OK" "$C_ERR" "$C_OFF"; ok fine; info detail'
  [[ "$output" == *$'\033['* ]] || { echo "forced colour never arrived: $output"; false; }
  # The roles resolve to different colours — one empty C_* would pass a mere
  # "is there an escape" check while painting two roles the same.
  [[ "$output" != *'||'* ]] || { echo "an empty role: $(printf '%s' "$output" | sed -n l)"; false; }

  haus_sh HAUS_UI_SH="$UI_SH_REAL" NO_COLOR=1 "say hi; ok fine; info detail"
  [[ "$output" != *$'\033['* ]] || { echo "NO_COLOR lost: $output"; false; }

  # And the conflict, asserted rather than left to whichever half was written
  # last: CLICOLOR_FORCE beats NO_COLOR. no-color.org and bixense.com disagree
  # about this and both are cited in the wild — what matters here is that ONE
  # binary cannot answer it two ways, so haus takes snug's answer by asking
  # snug's own detector. If this flips, it flips in snug, for everybody.
  haus_sh HAUS_UI_SH="$UI_SH_REAL" NO_COLOR=1 CLICOLOR_FORCE=1 \
    'printf "%s|%s\n" "$C_OK" "$C_OFF"; say hi'
  [[ "$output" == *$'\033['* ]] || { echo "CLICOLOR_FORCE lost to NO_COLOR: $output"; false; }
  [[ "$output" != *'||'* ]] || { echo "the report roles went empty: $output"; false; }

  # And the one thing that beats even the force: there is no escape sequence a
  # dumb terminal will not print at you literally. ui.sh's rule, inherited here
  # rather than re-decided — and the reason TERM is pinned in setup(), since a
  # GitHub runner sets `dumb` for every step.
  haus_sh HAUS_UI_SH="$UI_SH_REAL" TERM=dumb CLICOLOR_FORCE=1 "say hi; ok fine; info detail"
  [[ "$output" != *$'\033['* ]] || { echo "TERM=dumb still painted: $output"; false; }
  [[ "$output" == *hi* ]] || { echo "and it lost the words too: $output"; false; }
}

@test "haus-show.sh emits no escape into a pipe, and every one under CLICOLOR_FORCE" {
  # `die` is the one painted line reachable with no nix and no fixture, and it
  # goes through the same gate as the whole report. HAUS_DESKTOP_CHECK points at
  # a directory that merely EXISTS so the "no such file" die is the one that
  # fires: without it, a machine with no /run/current-system (every CI runner)
  # trips the checker-missing die three steps earlier instead, and the test
  # would be asserting about a different message on each platform.
  need_ui
  local ck="$BATS_TEST_TMPDIR"
  run env HAUS_UI_SH="$UI_SH_REAL" HAUS_DESKTOP_CHECK="$ck" "$BASH" "$SHOW" /nope.nix
  [[ "$output" != *$'\033['* ]]
  [[ "$output" == *"no such file"* ]]

  run env CLICOLOR_FORCE=1 HAUS_UI_SH="$UI_SH_REAL" HAUS_DESKTOP_CHECK="$ck" "$BASH" "$SHOW" /nope.nix
  [[ "$output" == *$'\033['* ]] || { echo "forced colour never arrived: $output"; false; }

  run env TERM=dumb CLICOLOR_FORCE=1 HAUS_UI_SH="$UI_SH_REAL" HAUS_DESKTOP_CHECK="$ck" "$BASH" "$SHOW" /nope.nix
  [[ "$output" != *$'\033['* ]] || { echo "TERM=dumb still painted: $output"; false; }

  run env NO_COLOR=1 HAUS_UI_SH="$UI_SH_REAL" HAUS_DESKTOP_CHECK="$ck" "$BASH" "$SHOW" /nope.nix
  [[ "$output" != *$'\033['* ]] || { echo "NO_COLOR lost: $output"; false; }

  # The same conflict, answered the same way, by the same detector — which is
  # the point of both scripts asking snug rather than each carrying a rule.
  run env NO_COLOR=1 CLICOLOR_FORCE=1 HAUS_UI_SH="$UI_SH_REAL" HAUS_DESKTOP_CHECK="$ck" "$BASH" "$SHOW" /nope.nix
  [[ "$output" == *$'\033['* ]] || { echo "CLICOLOR_FORCE lost to NO_COLOR: $output"; false; }
}

@test "haus show's earliest errors say what they mean" {
  # Every helper scrubs its message, so a `die` that fired before `scrub` was
  # defined printed `scrub: command not found` and then an EMPTY message —
  # `✗ ` and nothing else. The two earliest dies are the two that most need
  # words: an unknown flag, and "this machine's haus predates 'haus show'".
  run env HAUS_DESKTOP_CHECK=/definitely/not/here "$BASH" "$SHOW" /nope.nix
  [[ "$output" == *"haus update"* ]] || { echo "blank checker error: $output"; false; }
  [[ "$output" != *"command not found"* ]]

  run "$BASH" "$SHOW" --nope
  [[ "$output" == *"unknown flag"* ]] || { echo "blank flag error: $output"; false; }
  [[ "$output" != *"command not found"* ]]
}

@test "the three non-CLI painters hold no colour of their own either" {
  # The three painters that are not CLIs: the statusline, the image preview and
  # the lane opener. Weaker than the ban above, and the difference is the whole
  # point — these three legitimately emit escapes that are NOT colour, and a
  # blanket `\033[` ban would have to be suppressed per line until it meant
  # nothing. So this bans the two SGR colour forms specifically:
  #
  #   \033[38;…  \033[48;…   foreground / background colour
  #   \033[3Nm   \033[9Nm    the ANSI-basic sets
  #
  # and leaves legal: OSC 8 hyperlinks and OSC 2 window titles (`\033]`), and
  # DECTCEM cursor visibility (`\e[?25l/h`). Structure, not style — a hyperlink
  # you can still click and a cursor that comes back are things a monochrome
  # terminal must keep.
  #
  # ONE exception, and it is named rather than pattern-matched so that adding a
  # second requires editing this list: statusline.sh's TINT_FABLE. It is a
  # 24-bit BACKGROUND, and snug's nine roles are all foreground, so there is no
  # role for it to become. If snug ever grows one, delete the line.
  local f hits
  for f in "$BATS_TEST_DIRNAME/../modules/ai/statusline.sh" \
           "$BATS_TEST_DIRNAME/../modules/terminal/scripts/image-preview.sh" \
           "$BATS_TEST_DIRNAME/../modules/terminal/lanes/lane-open.sh"; do
    [ -r "$f" ] || { echo "missing: $f"; false; }
    hits="$(grep -nE '\\(033|e|x1[bB])\[(38;|48;|[0-9;]*[0-9]m)' "$f" \
      | grep -v '^[0-9]*:[[:space:]]*#' \
      | grep -v 'TINT_FABLE=' || true)"
    [ -z "$hits" ] || { echo "$f still paints by hand:"; echo "$hits"; false; }
  done
}

@test "the three non-CLI painters cannot be broken by ui.sh's own sentinel" {
  # ui.sh guards against a double source with `[ -n "${UI_SH:-}" ] && return 0`
  # — it uses that exact name as its sentinel. A caller that holds the PATH to
  # ui.sh in a variable called UI_SH therefore makes the file return before it
  # defines anything: no error, no colour, and a suite that still passes because
  # every role is legitimately empty when the painter is absent. All three of
  # these were written that way first and shipped nothing.
  local f
  for f in "$BATS_TEST_DIRNAME/../modules/ai/statusline.sh" \
           "$BATS_TEST_DIRNAME/../modules/terminal/scripts/image-preview.sh" \
           "$BATS_TEST_DIRNAME/../modules/terminal/lanes/lane-open.sh"; do
    grep -qE '^[[:space:]]*UI_SH=' "$f" \
      && { echo "$f assigns UI_SH, which is ui.sh's own source-twice guard"; false; }
  done
  return 0
}

@test "a script that sources ui.sh asks for a bash that can run it" {
  # ui.sh is bash 4+ (`declare -gA`, `${v^^}`). Under macOS's /bin/bash 3.2 it
  # does not degrade — it prints three `bad substitution` / syntax errors and
  # half-loads, which for image-preview.sh means garbage across a full-screen
  # reader. Two things keep that off the screen and both are asserted here.
  #
  # image-preview.sh ONLY. lane-open.sh is deliberately not in this list and its
  # own case is below: it keeps `/bin/bash`, because it never sources ui.sh in
  # its own shell. Asserting the shebang for both would have passed for the
  # wrong reason on one of them, which is how a test stops meaning anything.
  local f="$BATS_TEST_DIRNAME/../modules/terminal/scripts/image-preview.sh"
  head -1 "$f" | grep -q 'env bash' \
    || { echo "$f has a /bin/bash shebang and sources a bash-4 painter"; false; }
  grep -q 'BASH_VERSINFO' "$f" \
    || { echo "$f sources ui.sh with no bash-version guard"; false; }
}

@test "lane-open's hold snippet carries the guard, because it is the shell that sources" {
  # lane-open.sh draws its one line from a single-quoted string handed to the
  # lane's own `bash -lc`, not from this process — so the version guard has to
  # live INSIDE that string, and a `grep BASH_VERSINFO "$f"` would be satisfied
  # by a guard anywhere in the file, including one protecting nothing.
  #
  # Extract the snippet the way the script builds it and check the guard is in
  # THAT text, next to the source it protects.
  local f="$BATS_TEST_DIRNAME/../modules/terminal/lanes/lane-open.sh" snippet
  snippet="$(sed -n "/^held=\"\$SCRUFF_COMMAND\"'/,/^exit \"\$rc\"'\$/p" "$f")"
  [ -n "$snippet" ] || { echo "could not find the held snippet in $f"; false; }
  grep -q 'HAUS_UI_SH' <<<"$snippet" \
    || { echo "the held snippet does not reach the painter at all"; false; }
  grep -q 'BASH_VERSINFO' <<<"$snippet" \
    || { echo "the held snippet sources ui.sh with no bash-version guard"; false; }
  # And the file itself keeps /bin/bash: it sources nothing, and scruff may exec
  # it from launchd, where an absolute interpreter beats an inherited PATH.
  head -1 "$f" | grep -qx '#!/bin/bash' \
    || { echo "$f changed shebang without gaining a source of its own"; false; }
}

@test "neither CLI hardcodes an escape or a glyph index of its own" {
  # The stronger form of the check these files grew: they used to be allowed a
  # palette block of literal `\033[38;5;NNNm`, and 35 ungated escapes had
  # accumulated around it. There is now no legal place for one — every colour is
  # an alias onto snug's generated roles, so ANY literal escape outside a
  # comment is drift by construction. haus-activate.sh is still not in this
  # list, and the reason narrowed: it cannot SOURCE a painter (sudo, root, a
  # reset environment, before the generation that installs share/ui.sh exists),
  # but it no longer paints by hand either — its colour is copied out of snug's
  # generated tables, and test/installer-palette.bats diffs it back. Same for
  # bootstrap.sh. Neither belongs here; both are covered there.
  local f hits
  for f in "$SUBJECT" "$SHOW"; do
    hits="$(grep -n '\\033\[' "$f" | grep -v '^[0-9]*:[[:space:]]*#' || true)"
    [ -z "$hits" ] || { echo "$f still paints by hand:"; echo "$hits"; false; }
  done
}

# ── the degrade ladder ───────────────────────────────────────────────────────
# haus.sh is `builtins.readFile`'d into a store binary, so `dirname $0` is
# /nix/store and there is no checkout beside it — the wrapper in
# modules/core/default.nix hands it snug's `share/ui.sh` as an absolute path
# instead. These cases are the whole contract of that hand-off: it takes when
# the path is real, and it costs the caller NOTHING when it is not.

@test "haus.sh sources the painter HAUS_UI_SH points at" {
  local ui="$BATS_TEST_TMPDIR/ui.sh"
  # Every function haus.sh probes for at load, because UI_READY means "the whole
  # painter is here" — a fixture that answered only `ui_say` would be exactly the
  # partial painter that probe exists to reject.
  cat > "$ui" <<'UI'
ui_say() { printf 'FIXTURE %s\n' "$*"; }
ui_warn() { :; }; ui_hint() { :; }; ui_fail() { :; }
ui_glyph_bare() { printf -v "$1" '%s' '+'; }
ui_row() { :; }; ui_clear() { :; }; ui_paint() { :; }; ui_live_close() { :; }
ui_col() { :; }; ui_trow() { :; }; ui_table_data() { :; }; ui_table_clear() { :; }
UI
  haus_sh HAUS_UI_SH="$ui" 'echo "[$UI_READY]"; ui_say hello'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "$(printf '[1]\nFIXTURE hello')" ] || { echo "got: $output"; false; }

  # And a PARTIAL painter is rejected: UI_READY is what licenses every `ui_*`
  # call below it, so one missing function must read as no painter rather than
  # as a `command not found` in the middle of a rebuild, under `set -e`, after
  # activation.
  local half="$BATS_TEST_TMPDIR/half.sh"
  grep -v 'ui_live_close' "$ui" > "$half"
  haus_sh HAUS_UI_SH="$half" 'echo "[$UI_READY]"'
  [ "$output" = "[]" ] || { echo "a half-loaded painter read as ready: $output"; false; }
}

@test "haus.sh loads with HAUS_UI_SH unset, and with it pointing at nothing" {
  # The measured failure shape this guard exists for, and haus.sh's `set -euo
  # pipefail` makes both halves of it fatal: an unset variable dies on `-u`, and
  # a `source` of a missing path exits 1 under `-e`. Either kills `haus` at LOAD
  # time — before any verb ran, with nothing on either stream and nothing
  # activated. That is the worst possible failure mode for a courtesy.
  #
  # An older generation, a rollback, or a developer who exported the variable at
  # a path they have since deleted all land here, so it is not hypothetical.
  haus_sh -u HAUS_UI_SH 'echo LOADED'
  [ "$status" -eq 0 ] || { echo "unset HAUS_UI_SH killed haus.sh: $output"; false; }
  [ "$output" = LOADED ]

  haus_sh HAUS_UI_SH="$BATS_TEST_TMPDIR/nope/ui.sh" 'echo LOADED'
  [ "$status" -eq 0 ] || { echo "a missing HAUS_UI_SH killed haus.sh: $output"; false; }
  [ "$output" = LOADED ]
}

@test "with no painter at all every verb still says its words, on the right stream" {
  # The bottom rung: an older generation whose wrapper predates HAUS_UI_SH, or
  # `bash haus.sh` run straight off a checkout. No colour, no gutter, no region
  # — and nothing missing and nothing fatal.
  haus_sh -u HAUS_UI_SH '{ say prose; warn prose; hint prose; } 2>&1 1>/dev/null'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c prose)" -eq 3 ] \
    || { echo "lines lost with no painter: $output"; false; }
  [[ "$output" != *$'\033['* ]]

  haus_sh -u HAUS_UI_SH 'VERBOSE=; { phase_ok resolve 3.4s; } 2>&1 1>/dev/null'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *resolve* && "$output" == *3.4s* ]] \
    || { echo "the phase row vanished with no painter: $output"; false; }
}

@test "a session with no terminal and no TERM does not kill its caller" {
  # The bug the deleted width probe carried, kept as a regression because the
  # shape is what matters, not the line:
  #
  #   sz="$(stty size 2>/dev/null </dev/tty)" && COLS=… || COLS="$(tput cols)"
  #
  # `tput` exits 2 with TERM unset, and under `set -e` the command after the
  # final `||` is the ONE case the shell does not exempt. Measured: `ssh mac
  # haus rebuild` (no pty, so no TERM and no controlling terminal) exited 2 with
  # NOTHING on either stream — after a successful evaluation and before anything
  # activated. Silent, and on a workflow this repo's own docs recommend.
  run python3 - "$SUBJECT" "$HAUS_CONSUMER" "${UI_SH_REAL:-}" "$BASH" <<'NOTTY'
import os, sys, subprocess
haus, consumer, ui, bash = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
env = {k: v for k, v in os.environ.items() if k != "TERM"}
env.update(HAUS_LIB="1", HAUS_CONSUMER=consumer)
if ui:
    env["HAUS_UI_SH"] = ui
else:
    env.pop("HAUS_UI_SH", None)
# start_new_session: no controlling terminal, so /dev/tty cannot be opened and
# the fallback is the path that runs.
# "$BASH", not a bare `bash`: /bin/bash on a Mac is 3.2 and cannot parse ui.sh,
# so a bare name would fail on `${v,,}` rather than on the thing under test — and
# it would fail only on a Mac, leaving CI green.
p = subprocess.run(
    [bash, "-c",
     f"set -euo pipefail; source {haus}; VERBOSE=; phase_start resolve; "
     f"phase_ok resolve 3.4s; echo REACHED-THE-END"],
    env=env, stdin=subprocess.DEVNULL, capture_output=True, start_new_session=True)
print("rc=%d" % p.returncode)
sys.stdout.write(p.stdout.decode())
sys.stdout.write(p.stderr.decode())
NOTTY
  [[ "$output" == *"rc=0"* ]] || { echo "got: $output"; false; }
  [[ "$output" == *"REACHED-THE-END"* ]] || { echo "died before the end: $output"; false; }
}

# ── a real window ────────────────────────────────────────────────────────────
# Everything above runs on pipes. The bug this room was built around only exists
# on a terminal — a repaint that assumes a width corrupts the screen at 52
# columns and below for the finished `activate` row, and at 13 and below for the
# stub, which used to strand `· activate` above `✓ activate` for the whole
# rebuild. snug owns the fold now, so this asserts the OUTCOME rather than the
# arithmetic: one phase, one row, whatever the window.

# Replay a pty's bytes onto a virtual screen and print the rows that have
# something on them. Only the escapes a live region uses are interpreted —
# anything else is skipped, which is the point: an escape this cannot model is
# an escape a live region has no business writing.
phase_screen() { # phase_screen <cols>
  python3 - "$SUBJECT" "$HAUS_CONSUMER" "$UI_SH_REAL" "$1" "$BASH" <<'PYEOF'
import os, pty, sys, fcntl, termios, struct, select, unicodedata, re
haus, consumer, ui, cols, bash = (
    sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5])
pid, fd = pty.fork()
if pid == 0:
    env = dict(os.environ, HAUS_LIB="1", HAUS_CONSUMER=consumer, HAUS_UI_SH=ui,
               TERM="xterm-256color", NO_COLOR="1")
    # This repo's bash, by absolute path: /bin/bash on a Mac is 3.2 and cannot
    # parse ui.sh at all. And `snug_open` is stubbed out rather than the binary
    # hidden, because haus.sh PREPENDS the system profile to PATH at load, so
    # nothing this end does to PATH can keep the real one out of reach. What is
    # under test here is ui.sh's own region — the rung a machine without the
    # binary lands on, and the one bash can drive alone.
    os.execve(bash, [bash, "-c",
        f"set -euo pipefail; source {haus}; snug_open() {{ return 1; }}; "
        f"VERBOSE=; read -r _; "
        f"phase_start activate; phase_ok activate 12.3s '12 services · homebrew changed'"],
        env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, cols, 0, 0))
# ECHO off before the gating byte goes in, or the pty writes "go" back onto the
# screen we are about to measure and every row count is one too many.
a = termios.tcgetattr(fd)
a[3] &= ~termios.ECHO
termios.tcsetattr(fd, termios.TCSANOW, a)
os.write(fd, b"go\n")
out = b""
while True:
    r, _, _ = select.select([fd], [], [], 10)
    if not r: break
    try: chunk = os.read(fd, 65536)
    except OSError: break
    if not chunk: break
    out += chunk
os.waitpid(pid, 0)

text = out.decode("utf-8", "replace")
screen, row, col = [], 0, 0
CSI = re.compile(r"\033\[([0-9;?]*)([A-Za-z])")
def ensure(r):
    while len(screen) <= r:
        screen.append([" "] * cols)
i = 0
while i < len(text):
    m = CSI.match(text, i)
    if m:
        p, f = m.group(1), m.group(2)
        if f == "K":
            ensure(row)
            start = 0 if p == "2" else col
            for c in range(start, cols):
                screen[row][c] = " "
        elif f == "J":
            ensure(row)
            for c in range(col, cols):
                screen[row][c] = " "
            del screen[row + 1:]
        elif f == "A":
            row = max(0, row - (int(p) if p else 1))
        i = m.end()
        continue
    ch, i = text[i], i + 1
    if ch == "\r":
        col = 0
    elif ch == "\n":
        row, col = row + 1, 0
        ensure(row)
    elif ch == "\033":
        continue
    else:
        w = 2 if unicodedata.east_asian_width(ch) in "WF" else 1
        if col + w > cols:
            row, col = row + 1, 0
            ensure(row)
        ensure(row)
        screen[row][col] = ch
        col += w
for r in screen:
    line = "".join(r).rstrip()
    if line:
        print(line)
PYEOF
}

@test "one phase leaves exactly one row on a real terminal, at any width" {
  # 52 is where the finished row used to wrap; 13 is where the stub did, and
  # where the screen kept `· activate` above `✓ activate` for the whole rebuild.
  need_ui
  local w out n
  for w in 120 53 52 40 20 14 13 10 6 3; do
    out="$(phase_screen "$w")"
    n="$(printf '%s\n' "$out" | grep -c . || true)"
    [ "$n" -eq 1 ] || { echo "cols=$w left $n rows on screen:"; printf '%s\n' "$out"; false; }
    # The spinner is the only mark that can still be on screen when the finished
    # row lands, and it stranded above it in every version of this bug.
    if printf '%s\n' "$out" | grep -qE '^[[:space:]]*[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏|/\\-]([[:space:]]|$)'; then
      echo "cols=$w orphaned the running row:"; printf '%s\n' "$out"; false
    fi
  done
}

@test "no row reaches the last column of the window" {
  # A line whose width EQUALS the terminal's leaves the cursor past the edge and
  # the terminal wraps it anyway — which is the same corruption by another route.
  need_ui
  local w out widest
  for w in 120 53 52 40 20 14 13 10 6 3; do
    out="$(phase_screen "$w")"
    widest="$(printf '%s\n' "$out" | python3 -c 'import sys,unicodedata
print(max([0]+[sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in l) for l in sys.stdin.read().split("\n")]))')"
    [ "$widest" -lt "$w" ] || { echo "cols=$w drew $widest cells:"; printf '%s\n' "$out"; false; }
  done
}

# ── the geometry gate ────────────────────────────────────────────────────────
# The colour gate above says no escape is hand-picked. This one says no COLUMN
# is: every row with more than one field in it goes through `ui_col` + `ui_trow`
# + `ui_table_data`, which budget against the real window, rather than through a
# `%-NNs` that reserves its width whatever is in the cell and wraps the row in
# anything narrower (docs/cli-presentation.md, defect 1).
#
# A count rather than a pattern, because what is left is not a shape a regex can
# tell from a new one: each remaining `%-NNs` is either the no-ui.sh fallback —
# a machine whose `HAUS_UI_SH` points at nothing has no window to budget against
# and no painter, and keeps the columns it always had — or one of two named
# exceptions. Adding a table means the count does not move; if this test reds,
# either a fixed-width row was added (draw it with `ui_col`) or a fallback was
# removed (update the number here and say which in the message).

@test "every column is budgeted: no new fixed-width row in the four painters" {
  local f n want
  # file → how many `%-NNs` printf lines it may still hold, and why.
  #
  # haus.sh 8:      settings_diff's two fallback rows · the `gum filter` INPUT,
  #                 whose padding is the parse contract that recovers the chosen
  #                 path · `haus get`'s listing fallback · `haus desktop`'s four
  #                 fallback rows.
  # haus-show.sh 8: `field`, a one-row label and not a table · the five
  #                 render_machine fallbacks · render_desktop's two.
  # focus.sh 3:     scene_list's two fallback rows · the auto listing's one.
  # signal.sh 2:    the hooks fallback and its fix row.
  for f in "modules/core/haus.sh 8" \
           "modules/core/haus-show.sh 8" \
           "modules/focus/focus.sh 3" \
           "modules/github/signal.sh 2"; do
    set -- $f
    want="$2"
    n="$(grep -c "printf.*%-[0-9]\+s" "$BATS_TEST_DIRNAME/../$1" || true)"
    [ "$n" = "$want" ] || {
      echo "$1 has $n fixed-width printf rows, expected $want:"
      grep -n "printf.*%-[0-9]\+s" "$BATS_TEST_DIRNAME/../$1"
      false
    }
  done
}

@test "each painter actually reaches snug's table" {
  # The other half of the count above: a file could pass it by drawing nothing
  # at all. Every one of the four declares columns and paints them.
  local f
  for f in modules/core/haus.sh modules/core/haus-show.sh \
           modules/focus/focus.sh modules/github/signal.sh; do
    grep -q 'ui_col ' "$BATS_TEST_DIRNAME/../$f" \
      || { echo "$f declares no column"; false; }
    grep -q 'ui_table_data' "$BATS_TEST_DIRNAME/../$f" \
      || { echo "$f never paints a table"; false; }
  done
}

@test "the binaries outside the wrapper source ui.sh safely" {
  # `focus`, `github-signal` and `haus-secret` are the callers outside the `haus`
  # wrapper that SOURCE ui.sh in their own shell — the others either only alias
  # roles or hand the snippet to somebody else's. Three properties, and each has
  # a way of going wrong silently:
  #
  #  - a bash-version guard, because ui.sh is bash 4+ and macOS's /bin/bash 3.2
  #    half-loads it: three `bad substitution` errors and a painter that answers
  #    `type` and then draws nothing.
  #  - `env bash` on the two that are SUBSTITUTED rather than wrapped — `focus`
  #    and `haus-secret` — because for those the first line is the interpreter
  #    that actually runs, and both are exec'd directly (the bar, pounce, a
  #    launchd agent, `haus doctor`, a person). `github-signal` is deliberately
  #    NOT asserted here: it is built by `writeShellScriptBin`, so its
  #    interpreter is nixpkgs' bash whatever its own first line says, and
  #    asserting it would pass for the wrong reason.
  #  - none may hold the path in `UI_SH`, which is ui.sh's own source-twice
  #    sentinel — that name makes the file return before defining anything.
  local f
  for f in "$BATS_TEST_DIRNAME/../modules/focus/focus.sh" \
           "$BATS_TEST_DIRNAME/../modules/github/signal.sh" \
           "$BATS_TEST_DIRNAME/../modules/secrets/haus-secret.sh"; do
    grep -q 'BASH_VERSINFO' "$f" \
      || { echo "$f sources ui.sh with no bash-version guard"; false; }
    if grep -qE '^[[:space:]]*UI_SH=' "$f"; then
      echo "$f assigns UI_SH, which is ui.sh's own source-twice guard"; false
    fi
  done
  for f in "$BATS_TEST_DIRNAME/../modules/focus/focus.sh" \
           "$BATS_TEST_DIRNAME/../modules/secrets/haus-secret.sh"; do
    head -1 "$f" | grep -q 'env bash' \
      || { echo "$f has a /bin/bash shebang and sources a bash-4 painter"; false; }
  done
}

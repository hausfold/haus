#!/usr/bin/env bats
# What `awake` puts on screen, and what it must go on NOT putting there.
#
# Why a suite for four sentences. `awake` was nearly written off as a
# machine-only binary, and it is not: `status` is its DEFAULT verb
# (`command=${1:-status}`), so a bare `awake` prints prose for a person. But the
# same script is also the bar's data source — `awake status --raw` runs on every
# caffeinate tick — and the launchd program behind the assertion itself. So
# every case below is one question in two halves: did the sentence get better
# for the person, WITHOUT the machine paths paying for it or changing shape.
#
# Nothing here starts a real assertion: launchctl and caffeinate are stubs and
# the clock is `AWAKE_NOW`, because the thing under test is the drawing.

bats_require_minimum_version 1.5.0

# snug's bash painter, wherever this machine keeps it — the same probe
# haus-secret.bats, statusline.bats and phase-painter.bats use, and for the same
# reason: the role escapes are read back out of the real file rather than
# spelled here, so a nebelung retune cannot leave this suite asserting a stale
# colour.
real_ui_sh() {
  local q
  for q in "${HAUS_UI_SH:-}" \
           "$BATS_TEST_DIRNAME/../../snug/share/ui.sh" \
           "$HOME/code/workshop/snug/share/ui.sh"; do
    [ -n "$q" ] && [ -r "$q" ] && { printf '%s' "$q"; return 0; }
  done
  return 1
}
need_ui() { [ -n "$UI_SH_REAL" ] || skip "no snug share/ui.sh on this machine"; }

setup() {
  SRC="$BATS_TEST_DIRNAME/../modules/core/awake.sh"
  TMP="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
  UI_SH_REAL="$(real_ui_sh || true)"
  unset HAUS_UI_SH || true

  export HOME="$TMP/home"
  # `awake` resolves its state as `${AWAKE_STATE_DIR:-$HOME/.local/state/…}` and
  # reads no XDG variable at all, so the pin that matters here is that one — set
  # below, and set rather than left to default, because the defaulted branch is
  # not the branch under test. XDG is pinned anyway for the same reason
  # haus-secret.bats pins it: a runner that exports either one (GitHub's does)
  # is exactly the difference between green locally and red in CI, and a suite
  # that only pins HOME has already been bitten by it once in this repo.
  export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state"
  export AWAKE_STATE_DIR="$TMP/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$AWAKE_STATE_DIR"

  # The colour environment, pinned for the reason statusline.bats pins it: a
  # developer's terminal says truecolor and a GitHub runner sets TERM=dumb for
  # every step, which ui.sh honours absolutely. Unpinned, every assertion about
  # an escape passes locally and fails in CI.
  # `LANG` is what ui.sh's `ui__detect_alphabet` reads to choose the UTF-8 marks
  # over the ASCII ones, so it is pinned rather than inherited. `PYTHONIOENCODING`
  # is the OTHER half and is not optional: `pty_run` writes the subject's bytes
  # back out through python, whose stdout encoding follows the locale, and a
  # runner without `en_US.UTF-8` generated would raise UnicodeEncodeError on the
  # first `✓` rather than fail an assertion.
  export TERM=xterm-256color COLORTERM=truecolor LANG=en_US.UTF-8
  export PYTHONIOENCODING=utf-8
  unset NO_COLOR CLICOLOR_FORCE || true
  # A fixed clock and a fixed zone, or the `(until …)` half of the timed
  # sentence is a different string every run and in every checkout.
  export TZ=UTC AWAKE_NOW=1000000

  # Stubs for everything that would touch the real machine. `poke_bar` is
  # pointed at nothing on purpose — both bar binaries are behind `[ -x ]`.
  mkdir -p "$TMP/bin"
  cat >"$TMP/bin/launchctl" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$TMP/launchctl.log"
[ "\${AWAKE_LAUNCHCTL_FAIL:-0}" = 0 ]
EOF
  chmod +x "$TMP/bin/launchctl"
  export AWAKE_LAUNCHCTL_BIN="$TMP/bin/launchctl"
  export AWAKE_CAFFEINATE_BIN="/usr/bin/true"
  # `date -r <seconds>` is BSD's "format this epoch time" and GNU's
  # `--reference=FILE`, which answers `No such file or directory` on a number.
  # This suite runs on a Linux CI runner as well as on the Mac awake ships to,
  # so the clock is stubbed rather than trusted: what these cases are about is
  # the SHAPE of the sentence, and a real `date` here would assert BSD's
  # formatting on one platform and a blank parenthetical on the other.
  cat >"$TMP/bin/date" <<'EOF'
#!/bin/sh
case "$*" in
  *"%l:%M %p"*) printf '%s\n' " 3:46 PM" ;;   # a leading space, as BSD emits
  *) printf '%s\n' 1000000 ;;
esac
EOF
  chmod +x "$TMP/bin/date"
  export AWAKE_DATE_BIN="$TMP/bin/date"
  export AWAKE_SKETCHYBAR_BIN="$TMP/no-such-bar"
  export AWAKE_BAR_BOTTOM_BIN="$TMP/no-such-bar-bottom"

  # `awake`'s shebang is `env bash` — the contract phase-painter.bats asserts —
  # and ui.sh is bash 4+. On a machine whose PATH finds macOS's /bin/bash 3.2
  # first, every painted case below would take the guard's plain branch and the
  # suite would assert the fallback while believing it tested the painter. So
  # PATH is given a bash 4+ to find, which is what a real haus machine has; the
  # 3.2 branch gets its own case, run through /bin/bash by name.
  BASH4="$(resolve_bash4 || true)"
  if [ -n "$BASH4" ]; then
    ln -sf "$BASH4" "$TMP/bin/bash"
    export PATH="$TMP/bin:$PATH"
  fi

  build_subject "${UI_SH_REAL:-/nonexistent/ui.sh}"
}

resolve_bash4() {
  local c
  for c in /run/current-system/sw/bin/bash "$(command -v bash || true)" /bin/bash; do
    [ -n "$c" ] && [ -x "$c" ] || continue
    [ "$("$c" -c 'echo ${BASH_VERSINFO[0]}' 2>/dev/null || echo 0)" -ge 4 ] \
      && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# The derivation's two build-time steps, by hand: modules/core/default.nix
# PREPENDS the `HAUS_UI_SH` line and substitutes `@sketchybar@`. Doing both here
# means the suite tests what nix will actually install rather than a shape only
# bats has ever run — and in particular it tests the `:-` in that prepended
# line, which is the whole reason a caller can still point the binary at a
# working copy.
build_subject() { # build_subject <uish>
  SUBJECT="$TMP/awake"
  {
    # `writeShellScriptBin` writes its OWN shebang above the prepended line, so
    # awake.sh's `#!/usr/bin/env bash` ends up in the middle of the installed
    # binary as a comment. Reproduce that rather than leaving the file
    # shebang-less: a script whose first byte is not `#!` is not a program at
    # all, and `execvp` refuses it with `Exec format error` where bash would
    # have quietly run it under /bin/sh.
    printf '#!/usr/bin/env bash\n'
    printf 'HAUS_UI_SH="${HAUS_UI_SH:-%s}"\n' "$1"
    sed -e "s|@sketchybar@|$TMP/no-such-bar|" "$SRC"
  } >"$SUBJECT"
  chmod +x "$SUBJECT"
}

# Run the subject on a pty of a stated width and hand back its raw bytes.
pty_run() { # pty_run <cols> <arg…>
  python3 - "$1" "$SUBJECT" "${@:2}" <<'PYEOF'
import os, pty, sys, fcntl, termios, struct, select
cols, cmd = int(sys.argv[1]), sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, cols, 0, 0))
out = b""
while True:
    r, _, _ = select.select([fd], [], [], 10)
    if not r: break
    try: chunk = os.read(fd, 65536)
    except OSError: break
    if not chunk: break
    out += chunk
os.waitpid(pid, 0)
sys.stdout.write(out.decode("utf-8", "replace"))
PYEOF
}

# The colour-setting escapes on a line, in the order they appear and with the
# resets dropped — read back out of the output rather than spelled here, so a
# nebelung retune cannot leave this suite asserting a stale hex.
sgrs() {
  python3 -c '
import sys, re
for m in re.findall(r"\033\[[0-9;]*m", sys.stdin.read()):
    if m != "\033[0m": print(m)
'
}

# ---- the machine path, which must not have moved ----------------------------

@test "--raw is exactly mode<TAB>remaining<TAB>until, on a terminal too" {
  need_ui
  # modules/bar/sketchybar/plugins/caffeinate.sh reads this with `IFS=$'\t'
  # read` and with `cut -f1`. One escape, one glyph or one fold in it and the
  # coffee pill goes wrong SILENTLY — a stale label, no error anywhere — so the
  # terminal case matters as much as the pipe: a person debugging the pill runs
  # `awake status --raw` by hand at a prompt.
  run -0 "$SUBJECT" 2h
  run -0 "$SUBJECT" status --raw
  [ "$output" = "$(printf 'timed\t7200\t1007200')" ]

  local seen; seen="$(pty_run 40 status --raw | tr -d '\r')"
  [ "$seen" = "$(printf 'timed\t7200\t1007200')" ] || {
    printf 'a terminal changed --raw: %q\n' "$seen"; false; }
}

@test "--raw never loads the painter — the bar runs it every tick" {
  # The hot path, and the reason ui_load is a function rather than a source at
  # the top. A ui.sh that records being sourced is the only way to see the
  # difference: a loaded painter that draws nothing looks identical on screen
  # and costs a thousand lines of bash on every caffeinate tick, forever.
  local spy="$TMP/spy-ui.sh"
  printf 'printf x >>"%s/sourced"\n' "$TMP" >"$spy"
  build_subject "$spy"
  run -0 "$SUBJECT" status --raw
  [ ! -e "$TMP/sourced" ] || { echo "--raw sourced ui.sh"; false; }

  # `_run`, the launchd controller, is the other path with no reader.
  run -0 "$SUBJECT" _run
  [ ! -e "$TMP/sourced" ] || { echo "_run sourced ui.sh"; false; }

  # And the control: a path that DOES draw reaches it.
  run -0 "$SUBJECT" status
  [ -e "$TMP/sourced" ] || { echo "the prose status never loaded the painter"; false; }
}

# ---- the sentence -----------------------------------------------------------

@test "held and allowed wear different glyphs, and both survive NO_COLOR" {
  need_ui
  # The glyph is load-bearing and the colour is not: `awake` under NO_COLOR
  # still has to answer "is anything holding this Mac awake" at a glance, and
  # every role resolves to the empty string there.
  run -0 "$SUBJECT" 3h
  local held="$output"
  run -0 "$SUBJECT" off
  local allowed="$output"
  [ "${held%% *}" != "${allowed%% *}" ] || {
    echo "held and allowed drew the same mark: ${held%% *}"; false; }

  # With colour off the mark is ALL that is left, so it has to still be there
  # and still differ. Read back rather than spelled: naming snug's `·` here
  # would red this suite on a glyph retune instead of degrading with it, which
  # is the same reason no role's hex appears anywhere in this file.
  NO_COLOR=1 run -0 pty_run 80 status
  [ "$(printf '%s' "$output" | grep -c $'\033')" -eq 0 ]
  [[ "$output" == *"idle sleep is allowed"* ]]
  local plain_allowed="${output%% *}"
  [ -n "$plain_allowed" ] || { echo "NO_COLOR lost the mark: $output"; false; }
  run -0 "$SUBJECT" 3h
  NO_COLOR=1 run -0 pty_run 80 status
  [ "${output%% *}" != "$plain_allowed" ] || {
    echo "NO_COLOR left held and allowed indistinguishable: $output"; false; }
}

@test "the mark, the duration and the parenthetical are three different roles" {
  need_ui
  # What a person came for is the NUMBER. `awake for` is scaffolding, so it
  # carries no role at all and stays the terminal's own colour; the mark says
  # held-or-not and the `(until …)` is context. Three roles, and the assertion
  # is that they DIFFER — the hexes themselves belong to nebelung.
  run -0 "$SUBJECT" 90m
  run -0 pty_run 80 status
  local painted; painted="$(printf '%s' "$output" | sgrs)"
  [ "$(printf '%s\n' "$painted" | wc -l | tr -d ' ')" -eq 3 ] || {
    echo "expected three painted segments, got:"; printf '%s\n' "$painted"; false; }
  [ "$(printf '%s\n' "$painted" | sort -u | wc -l | tr -d ' ')" -eq 3 ] || {
    echo "two of the three segments share a role:"; printf '%s\n' "$painted"; false; }
  # And the scaffolding really is unpainted: `awake for ` sits between the
  # mark's reset and the duration's set, with nothing of its own.
  [[ "$output" == *$'\033'"[0mawake for "$'\033'"["* ]] || {
    echo "awake for picked up a role of its own: $output"; false; }
}

@test "the state line is fd 1 for every verb, including the two that change the machine" {
  need_ui
  # `awake` has no narration to separate a report from, and the bar's popup rows
  # have run `awake 1h >/dev/null` since before there was a painter — so the
  # confirmation stays on fd 1 where those rows discard it. A move to fd 2 would
  # put a line in sketchybar's log on every click, silently.
  local v
  for v in 3h indefinitely off status; do
    run -0 --separate-stderr "$SUBJECT" "$v"
    [ -n "$output" ] || { echo "'awake $v' wrote nothing to fd 1"; false; }
    [ -z "$stderr" ] || { echo "'awake $v' wrote to fd 2: $stderr"; false; }
  done
}

# ---- the refusals -----------------------------------------------------------

@test "a refusal is fd 2, keeps the name, and still exits 64" {
  need_ui
  run -64 --separate-stderr "$SUBJECT" nonsense
  [ -z "$output" ] || { echo "a refusal reached fd 1: $output"; false; }
  # The name stays where `haus.sh`'s die drops it: this binary's stderr is a
  # sketchybar log as often as it is a terminal, and there nothing else says who
  # refused.
  [[ "$stderr" == *"awake: unknown duration 'nonsense'"* ]] || {
    echo "stderr was: $stderr"; false; }
}

@test "a launchd job that will not start says so on fd 2 and claims nothing on fd 1" {
  need_ui
  # The one failure a person meets on a machine that has never rebuilt since the
  # room landed. It must not print a state line: the assertion did not start,
  # and `awake` has just deleted the state it optimistically wrote.
  AWAKE_LAUNCHCTL_FAIL=1 run -1 --separate-stderr "$SUBJECT" 1h
  [ -z "$output" ] || { echo "a failed start still claimed a state: $output"; false; }
  [[ "$stderr" == *"could not start"* ]]
  [[ "$stderr" == *"rebuild once"* ]]
  [ ! -e "$AWAKE_STATE_DIR/state" ] || { echo "a failed start left state behind"; false; }
}

# ---- degradation ------------------------------------------------------------

@test "the probe names every verb the script calls, not a sample of them" {
  # A ui.sh that predates one of the verbs is the case the probe exists for, and
  # here it is worse than a wrong colour: `set -euo pipefail` turns one missing
  # function into an abort AFTER `launchctl kickstart` has already started the
  # assertion, leaving a Mac held awake with an error where its confirmation
  # should be.
  local half="$TMP/half-ui.sh"
  cat >"$half" <<'EOF'
ui_fail() { printf 'PAINTED %s\n' "$*" >&2; }
ui_hint() { printf 'PAINTED %s\n' "$*" >&2; }
ui_paint_role() { printf -v "$1" 'PAINTED%s' "$3"; }
EOF
  build_subject "$half"
  run -0 "$SUBJECT" 2h
  [[ "$output" != *PAINTED* ]] || {
    echo "a half-loaded painter was accepted: $output"; false; }
  [ "$output" = "awake for 2h 00m" ]
}

@test "an absent ui.sh prints the sentence exactly as it always did" {
  # The plain branch is byte-for-byte what this script printed before it drew
  # through anything, which is what makes the conversion safe to land: a machine
  # with no painter loses the mark and nothing else.
  build_subject "/nonexistent/share/ui.sh"
  run -0 "$SUBJECT" 2h
  [ "$output" = "awake for 2h 00m" ]
  run -0 "$SUBJECT" status
  # The clock is the stub's, so what this pins is the SENTENCE — the template,
  # the two substitutions, and the `sed 's/^ //'` that eats the leading space
  # BSD's `%l` pads with. Turning an epoch into a wall time is `date`'s job and
  # not awake's, and asserting it here would only ever test the platform.
  [ "$output" = "awake for 2h 00m more (until 3:46 PM)" ]
  run -0 "$SUBJECT" indefinitely
  [ "$output" = "awake indefinitely" ]
  run -0 "$SUBJECT" off
  [ "$output" = "idle sleep is allowed" ]
  run -64 --separate-stderr "$SUBJECT" nope
  [ "$stderr" = "awake: unknown duration 'nope' (try: awake 3h)" ]
}

@test "bash 3.2 keeps the plain sentence — the version is checked, not assumed" {
  need_ui
  [ -x /bin/bash ] || skip "no /bin/bash to test the old-bash path with"
  local v; v="$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}')"
  [ "$v" -lt 4 ] || skip "/bin/bash here is $v, not the 3.2 this guards against"
  # Sourcing ui.sh under 3.2 half-loads it: three `bad substitution` errors and
  # a painter that answers `type` and then draws nothing. `awake` is exec'd on a
  # launchd and a sketchybar PATH where `env bash` still finds 3.2, so this is
  # the machine the guard was written for.
  run -0 --separate-stderr /bin/bash "$SUBJECT" 2h
  [ "$output" = "awake for 2h 00m" ]
  [ -z "$stderr" ] || { echo "3.2 printed to fd 2: $stderr"; false; }
}

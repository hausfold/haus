#!/usr/bin/env bats
# What `haus-secret` puts on screen — the listing, the two streams, and the
# degradation underneath both.
#
# Why a suite for a 200-line script. This is the ONE haus binary a person meets
# before they have a working machine: `haus doctor` sends them here, and what
# they read is a wall of prose about values they have not entered yet. It is
# also exec'd directly by launchd agents at boot, which is what makes the
# painter here a hazard the other CLIs do not have — `haus show` inherits
# HAUS_UI_SH from a wrapper and always runs from a terminal, while this runs
# under `env bash` on a launchd PATH where `bash` is macOS's 3.2 and ui.sh
# cannot be parsed at all. So every case below is really one question: does the
# report get better on a terminal WITHOUT the value path getting worse anywhere
# else.
#
# Nothing here touches secretspec, a provider or the network: the manifest table
# is written by hand and `@secretspec@` is a stub, because the thing under test
# is the drawing, not the fetching.

bats_require_minimum_version 1.5.0

# snug's bash painter, wherever this machine keeps it — the same probe
# statusline.bats and phase-painter.bats use, and for the same reason: the role
# escapes are read back out of the real file rather than spelled here, so a
# nebelung retune cannot leave this suite asserting a stale colour.
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
  SRC="$BATS_TEST_DIRNAME/../modules/secrets/haus-secret.sh"
  TMP="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
  UI_SH_REAL="$(real_ui_sh || true)"
  # Captured, then taken OUT of the environment. The script under test reads
  # `${HAUS_UI_SH:-@uiSh@}`, so a variable CI exports for the other suites would
  # win over the path this one substitutes — and the degradation cases below,
  # which are the whole reason for a build-time substitution, would silently
  # test the working painter instead.
  unset HAUS_UI_SH || true

  export HOME="$TMP/home"
  mkdir -p "$HOME/.config/haus"

  # The colour environment, pinned for the same reason statusline.bats pins it:
  # a developer's terminal says truecolor and a GitHub runner sets TERM=dumb for
  # every step, which ui.sh honours absolutely. Unpinned, every assertion about
  # an escape passes locally and fails in CI.
  export TERM=xterm-256color COLORTERM=truecolor
  unset NO_COLOR CLICOLOR_FORCE || true

  # Two rows: one required with a `why` long enough to need folding at any real
  # window, one optional with a short one. The long sentence is the whole point
  # — an unfolded `why` came back at column 0 and read as the next entry.
  TABLE="$TMP/table.tsv"
  printf 'haus.github.webhook\tGITHUB_WEBHOOK_SECRET\t1\tthe shared secret GitHub signs each webhook delivery with, so the receiver can tell a real delivery from anybody who found the URL\thttps://github.com/settings/hooks\n' >"$TABLE"
  printf 'haus.bar.weather\tOPENWEATHER_API_KEY\t0\tthe weather pill goes quiet without one\t\n' >>"$TABLE"
  # A third shape, and the one that caught a bug on the real manifest: `obtain`
  # is not always a URL. Half of them are a sentence telling you how to make the
  # value, and a sentence has to fold like every other line in the block.
  printf 'haus.ai.usage\tANTHROPIC_ADMIN_KEY\t0\tthe cost pill reads your org spend with it\tmake one in the console under Settings, then paste it here — a workspace key will not do\n' >>"$TABLE"

  # The stub stands in for secretspec and records that it was reached, which is
  # how the value path proves it did not detour through the painter.
  STUB="$TMP/secretspec-stub"
  cat >"$STUB" <<EOF
#!/bin/sh
printf '%s\n' "stub:\$*" >"$TMP/stub-ran"
printf 'the-value\n'
EOF
  chmod +x "$STUB"

  build_subject "$TABLE" "${UI_SH_REAL:-/nonexistent/ui.sh}"
}

# The derivation's `substitute` call, by hand — the script under test is the
# repo's file with its four build-time holes filled, so the suite tests what
# nix will actually install rather than a shape only bats has ever run.
build_subject() { # build_subject <table> <uish>
  SUBJECT="$TMP/haus-secret"
  sed -e "s|@secretspec@|$STUB|" \
      -e "s|@table@|$1|" \
      -e "s|@uiSh@|$2|" \
      -e "s|@providerItemAcl@|1|" "$SRC" >"$SUBJECT"
  chmod +x "$SUBJECT"
}

# Run the subject on a pty of a stated width and hand back its raw bytes. No
# virtual screen: nothing here draws a live region, so what was written IS what
# was seen, and a fold that failed shows up as a line too long rather than as a
# row in the wrong place.
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

# Display cells, with the escapes taken out first — the only width that means
# anything about a window.
widest() { # widest <text>
  python3 -c '
import sys, re
t = re.sub(r"\033\[[0-9;]*m", "", sys.stdin.read())
print(max((len(l.rstrip("\r")) for l in t.splitlines()), default=0))
'
}

# ---- the listing ------------------------------------------------------------

@test "--list folds the why at the window instead of letting it wrap" {
  need_ui
  run -0 pty_run 60 --list
  # The long sentence arrives as several lines, every one of them hanging at the
  # two cells the block indents by.
  [ "$(printf '%s' "$output" | grep -c '^  the shared secret')" -eq 1 ]
  local w; w="$(printf '%s' "$output" | grep -v 'where:' | widest)"
  [ "$w" -le 60 ] || { echo "a line ran to $w cells in a 60-column window:"; echo "$output"; false; }
}

@test "the fold tracks the window, not a number in the script" {
  need_ui
  local wide narrow
  wide="$(pty_run 100 --list | grep -c '^  ')"
  narrow="$(pty_run 40 --list | grep -c '^  ')"
  [ "$narrow" -gt "$wide" ] || {
    echo "40 columns produced $narrow body lines and 100 produced $wide"; false; }
}

@test "a prose where: folds and hangs; a lone url is left whole" {
  need_ui
  run -0 pty_run 70 --list
  # The sentence broke, and the continuation hangs two cells deeper than the
  # `↳` so the mark still reads as introducing the line under it.
  [[ "$output" == *"↳ where: make one in the console"* ]]
  [ "$(printf '%s' "$output" | grep -c '^    ')" -ge 1 ]
  # ui_fold hard-breaks a word wider than the line — correct for prose and fatal
  # for a URL, which is why a lone token skips the fold. Nothing may cut it.
  [[ "$output" == *"where: https://github.com/settings/hooks"* ]]
  # And the mark plus the label are inside the budget, not added after it: the
  # first line of a folded `where:` fits the window like every other line.
  local w; w="$(printf '%s' "$output" | grep -v 'https://' | widest)"
  [ "$w" -le 70 ] || { echo "a line ran to $w cells in a 70-column window:"; echo "$output"; false; }
}

@test "the name is never truncated, and the url is never folded" {
  need_ui
  # Both are strings a person is about to type or click. `…` through either is
  # worse than the wrap, and this is the assertion that keeps a future width
  # budget off them.
  run -0 pty_run 40 --list
  [[ "$output" == *"GITHUB_WEBHOOK_SECRET"* ]]
  [[ "$output" == *"where: https://github.com/settings/hooks"* ]]
}

@test "a redirected listing is written whole — no window, no fold, no escape" {
  need_ui
  run -0 "$SUBJECT" --list
  [ "$(printf '%s' "$output" | grep -c $'\033')" -eq 0 ]
  # One line, not four: a stream with no window is not given one.
  [ "$(printf '%s' "$output" | grep -c 'anybody who found the URL')" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c '^  the shared secret.*anybody who found the URL$')" -eq 1 ]
}

@test "required and optional are different roles, and both survive NO_COLOR" {
  need_ui
  run -0 pty_run 80 --list
  local req opt
  req="$(printf '%s' "$output" | sed -n 's/.*(\(.*required.*\)).*/\1/p')"
  opt="$(printf '%s' "$output" | sed -n 's/.*(\(.*optional.*\)).*/\1/p')"
  [ -n "$req" ] && [ -n "$opt" ]
  [ "$req" != "$opt" ] || { echo "required and optional painted the same: $req"; false; }
  # With colour off the words are all that is left, and they still say it.
  NO_COLOR=1 run -0 pty_run 80 --list
  [ "$(printf '%s' "$output" | grep -c $'\033')" -eq 0 ]
  [[ "$output" == *"(required)"* ]] && [[ "$output" == *"(optional)"* ]]
}

# ---- the two streams --------------------------------------------------------

@test "the listing is fd 1 and every refusal is fd 2" {
  need_ui
  run -0 --separate-stderr "$SUBJECT" --list
  [ -n "$output" ] && [ -z "$stderr" ]

  run -1 --separate-stderr "$SUBJECT" --nope
  [ -z "$output" ] && [ -n "$stderr" ]
}

@test "a refusal still says who refused, because its stderr is a launchd log" {
  need_ui
  run -1 --separate-stderr "$SUBJECT" --nope
  [[ "$stderr" == *"haus-secret: unknown option: --nope"* ]] || {
    echo "stderr was: $stderr"; false; }
}

@test "no manifest is a refusal with a way forward, not a stack of prose" {
  need_ui
  local empty="$TMP/empty.tsv"; : >"$empty"
  build_subject "$empty" "$UI_SH_REAL"
  run -1 --separate-stderr "$SUBJECT" --list
  [ -z "$output" ]
  [[ "$stderr" == *"no room on this Mac declares a secret"* ]]
  [[ "$stderr" == *"haus._contrib.secrets"* ]]
}

@test "--check asks on fd 2 whether or not a painter drew the question" {
  need_ui
  # One contract, not two. The prompt is narration in both branches — a
  # `--check >log` that swallowed the question on a bash-3.2 machine and showed
  # it everywhere else is the same verb behaving differently by accident.
  touch "$HOME/.config/haus/secretspec.toml"
  run -0 --separate-stderr "$SUBJECT" --check
  [[ "$stderr" == *"is optional"* ]] || { echo "stderr was: $stderr"; false; }
  [[ "$output" != *"is optional"* ]] || { echo "the question landed on fd 1: $output"; false; }

  build_subject "$TABLE" "/nonexistent/share/ui.sh"
  run -0 --separate-stderr "$SUBJECT" --check
  [[ "$stderr" == *"is optional"* ]] || { echo "plain stderr was: $stderr"; false; }
  [[ "$output" != *"is optional"* ]] || { echo "the plain question landed on fd 1: $output"; false; }
}

# ---- degradation ------------------------------------------------------------

@test "the probe names every verb the script calls, not a sample of them" {
  # A ui.sh that predates one of the verbs is the case the probe exists for, and
  # a probe that checks five of seven passes it and then aborts under `set -e`
  # halfway through `--check` — after the listing, before the stamp, which
  # leaves `haus-secret --ok` reporting the machine as waiting on you forever.
  local half="$TMP/half-ui.sh"
  cat >"$half" <<'EOF'
UI_OUT_AVAIL=79
ui_fail() { printf 'PAINTED %s
' "$*" >&2; }
ui_hint() { printf 'PAINTED %s
' "$*" >&2; }
ui_fold() { UI_FOLD=("$2"); }
ui_paint_role() { printf -v "$1" 'PAINTED%s' "$3"; }
ui_glyph_bare() { printf -v "$1" '>'; }
EOF
  build_subject "$TABLE" "$half"
  run -0 "$SUBJECT" --list
  [[ "$output" != *PAINTED* ]] || {
    echo "a half-loaded painter was accepted:"; echo "$output"; false; }
  [[ "$output" == *"GITHUB_WEBHOOK_SECRET  (required)"* ]]
}


@test "an absent ui.sh prints the plain blocks rather than dying" {
  build_subject "$TABLE" "/nonexistent/share/ui.sh"
  run -0 pty_run 60 --list
  [ "$(printf '%s' "$output" | grep -c $'\033')" -eq 0 ]
  [[ "$output" == *"GITHUB_WEBHOOK_SECRET  (required)"* ]]
  [[ "$output" == *"wanted by haus.github.webhook"* ]]
  [[ "$output" == *"where: https://github.com/settings/hooks"* ]]
}

@test "bash 3.2 keeps the plain blocks — the version is checked, not assumed" {
  need_ui
  [ -x /bin/bash ] || skip "no /bin/bash to test the old-bash path with"
  local v; v="$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}')"
  [ "$v" -lt 4 ] || skip "/bin/bash here is $v, not the 3.2 this guards against"
  # Sourcing ui.sh under 3.2 half-loads it: `type` answers for functions that
  # then draw nothing. The guard is what stops that, and this is the machine it
  # was written for.
  run -0 /bin/bash "$SUBJECT" --list
  [ "$(printf '%s' "$output" | grep -c $'\033')" -eq 0 ]
  [[ "$output" == *"GITHUB_WEBHOOK_SECRET  (required)"* ]]
}

@test "reading one value never loads the painter" {
  need_ui
  # The hot path: a room exec's this at boot, prints nothing, and must not pay
  # to read a thousand lines of bash. `--list` is what loads ui.sh; a `get` has
  # to reach secretspec with the value alone on fd 1.
  touch "$HOME/.config/haus/secretspec.toml"
  run -0 --separate-stderr "$SUBJECT" GITHUB_WEBHOOK_SECRET
  [ "$output" = "the-value" ]
  [ -z "$stderr" ]
  [ -f "$TMP/stub-ran" ]
}

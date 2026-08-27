#!/usr/bin/env bats
# The `haus rebuild` phase painter, and the colour gate both end-user CLIs grew
# with it. The family standard is docs/cli-presentation.md in the workshop.
#
# What broke, measured in real ptys against the code this replaces:
#
#   * the finished `activate` row is 52 cells ("12 services · homebrew
#     changed"), so at 52 columns and below it SOFT-WRAPPED into two screen
#     rows — a line the painter believed was one.
#   * the stub `phase_start` leaves is 14 cells, so at 13 columns and below it
#     wrapped too, and `\r` then rewound only its LAST row. The screen kept
#     `  · activate` orphaned above `  ✓ activate` for the rest of the rebuild.
#     That is the whole bug: `\r` addresses the current PHYSICAL row, and a
#     painter that never measures cannot know which one that is.
#   * every escape in haus.sh and haus-show.sh was unconditional, so a `haus
#     status | less`, a CI log and an agent pane all got raw \033[38;5;103m.
#
# Both halves fail SILENTLY on the machine that writes them — a maximised
# terminal never sees the fold, and a developer watching colour never sees the
# escapes — which is why they are pinned here rather than eyeballed.
#
# haus.sh is sourced as a library (HAUS_LIB=1, the same seam test/haus-plan.sh
# uses) so the painter can be called directly at a width no window has to have.

setup() {
  SUBJECT="$BATS_TEST_DIRNAME/../modules/core/haus.sh"
  SHOW="$BATS_TEST_DIRNAME/../modules/core/haus-show.sh"
  # haus.sh refuses to load without a config flake; HAUS_LIB stops it before the
  # dispatch but not before that guard, so give it an empty one.
  export HAUS_CONSUMER="$BATS_TEST_TMPDIR/consumer"
  mkdir -p "$HAUS_CONSUMER"
  : >"$HAUS_CONSUMER/flake.nix"
  # shellcheck disable=SC1090
  HAUS_LIB=1 source "$SUBJECT"
  VERBOSE=          # bats is not a tty, so the source above turned it on

  # Pin the window for the in-process tests: bats has no terminal, so the real
  # phase_measure would answer 80 for every one of them. The pty tests at the
  # bottom of this file run the real one in a real window, which is where it
  # belongs — a stub here would only be testing itself.
  PHASE_PIN=80
  phase_measure() { PHASE_COLS="$PHASE_PIN"; }
}

pin() { PHASE_PIN="$1"; PHASE_COLS="$1"; }

# Display CELLS, not bytes and not runes: `…` is three bytes and one cell, and
# `·` is two bytes and one cell. Width is counted the way a terminal counts it.
# The CR goes too: a pty's ONLCR puts one at the end of every line on the wire,
# and a measurement that counts it reports one cell more than the painter drew.
strip_paint() { tr -d '\r' | sed $'s/\033\\[[0-9;?]*[A-Za-z]//g' | grep . || true; }
widest_cells() {
  python3 -c 'import sys,unicodedata
w=0
for l in sys.stdin.read().split("\n"):
    w=max(w,sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in l))
print(w)'
}

# The row a real `haus rebuild` ends on — the widest one it can draw, and the
# one that was corrupt.
activate_row() { # activate_row <cols>
  pin "$1"
  phase_row "$C_OK" '✓' activate 12.3s '12 services · homebrew changed' | strip_paint
}

# ── the row fits the window ──────────────────────────────────────────────────

@test "phase_row never reaches the last column, at any width" {
  local w widest
  for w in 120 100 60 54 53 52 51 40 30 24 20 15 14 13 10 6 4 3 2 1; do
    widest="$(activate_row "$w" | widest_cells)"
    [ "$widest" -le $((w - 1)) ] || { echo "cols=$w painted $widest cells"; false; }
  done
}

@test "phase_row prints exactly one line, at any width" {
  # One line per phase is the invariant the repaint rests on. `strip_paint`
  # drops blank lines, so count what was actually written.
  local w n
  for w in 120 52 40 20 14 13 6 2; do
    n="$(activate_row "$w" | wc -l | tr -d ' ')"
    [ "$n" -eq 1 ] || { echo "cols=$w printed $n lines"; false; }
  done
  # The floor is 2 cells — one glyph. At 1 there is nothing honest left to
  # draw, so the row is a bare newline rather than a glyph over the edge.
  pin 1
  run phase_row "$C_OK" '✓' activate 12.3s 'ok'
  [ "$output" = "" ]
}

@test "phase_row sheds the detail before the label, and the label last" {
  local wide narrow bare
  wide="$(activate_row 120)"
  narrow="$(activate_row 20)"
  bare="$(activate_row 6)"
  [[ "$wide"   == *"activate"* ]]
  [[ "$wide"   == *"12 services · homebrew changed"* ]]
  [[ "$narrow" == *"activate"* ]]
  [[ "$narrow" != *"homebrew"* ]]
  [[ "$bare"   == *"✓"* ]]
}

@test "a short phase keeps its detail on a wide window" {
  # The tier is chosen from the WINDOW and only then clamped to the content.
  # Testing the clamped value first asks "is the detail short?" when it means
  # "is there room?", and drops a column a 200-column terminal had space for.
  local out
  pin 200
  out="$(phase_row "$C_OK" '✓' build 1.2s 'nothing to do' | strip_paint)"
  [[ "$out" == *"nothing to do"* ]] || { echo "lost the detail at 200 cols: $out"; false; }
}

@test "an elapsed wider than the usual six cells still fits" {
  # `%6s` is a MINIMUM, not a budget: a phase past a thousand seconds renders
  # "1234.5s" — seven cells, which a hardcoded six writes past the edge with.
  # A nixpkgs bump that rebuilds the world is exactly that phase.
  local w widest
  for w in 120 60 40 30 24 20 15 14 10 6 4 2; do
    pin "$w"
    widest="$(phase_row "$C_OK" '✓' activate 1234.5s 'ok' | strip_paint | widest_cells)"
    [ "$widest" -le $((w - 1)) ] || { echo "cols=$w painted $widest cells"; false; }
  done
}

@test "the stub phase_start leaves fits the window too" {
  # The orphan came from HERE: a stub that wraps puts `\r` on the wrong screen
  # row for the rest of the phase, whatever the finished row then does. In a pty
  # rather than in-process, because phase_start declines to paint at all without
  # a terminal — which is the point, and would make an in-process version of
  # this test pass by drawing nothing.
  local w raw widest stub
  for w in 120 40 20 15 14 13 10 6 4 2 1; do
    raw="$(phase_raw "$w" 'phase_start activate; printf "\n%s\n" "STUB=$PHASE_STUB"')"
    widest="$(printf '%s' "$raw" | head -1 | strip_paint | widest_cells)"
    stub="$(printf '%s' "$raw" | sed -n 's/.*STUB=\([0-9]*\).*/\1/p' | head -1)"
    [ "$widest" -le $((w - 1)) ] || { echo "cols=$w stubbed $widest cells"; false; }
    [ "$stub" -le $((w - 1)) ] || { echo "cols=$w claims a $stub-cell stub"; false; }
    # …and what it claims is what it drew, because `\r` is licensed by the claim.
    [ "$stub" -eq "$widest" ] || { echo "cols=$w drew $widest, claims $stub"; false; }
  done
}

# ── what reaches a pipe ──────────────────────────────────────────────────────
#
# The cursor escapes are gated on stdout being a TERMINAL, so the tests that
# assert one was written need a real one. `phase_raw` gives them the bytes the
# painter put on the wire, unrendered — which is the level `\r` and `[2K` live
# at. `phase_screen`, at the bottom of this file, renders those same bytes.

phase_raw() { # phase_raw <cols> <shell> — raw pty bytes, escapes and all
  python3 - "$SUBJECT" "$HAUS_CONSUMER" "$1" "$2" <<'RAWPTY'
import os, pty, sys, fcntl, termios, struct, select
haus, consumer, cols, body = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
pid, fd = pty.fork()
if pid == 0:
    os.execvp("bash", ["bash", "-c",
        f"read -r _; HAUS_CONSUMER={consumer} HAUS_LIB=1 source {haus}; VERBOSE=; " + body])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, cols, 0, 0))
os.write(fd, b"\n")
buf = b""
while True:
    r, _, _ = select.select([fd], [], [], 5)
    if not r:
        break
    try:
        d = os.read(fd, 65536)
    except OSError:
        break
    if not d:
        break
    buf += d
os.waitpid(pid, 0)
# The pty echoes the newline that ungated the child; everything after it is ours.
sys.stdout.write(buf.decode("utf8", "replace").split("\n", 1)[-1])
RAWPTY
}


@test "the repaint returns to column 0 and wipes the line" {
  # `[2K` and not `\r` alone: a folded row can be NARROWER than the stub, and
  # `\r` would leave the stub's tail behind it. It leads with the same pair when
  # the phase left NO stub — `build` is that phase, because nix keeps the
  # terminal for its own progress bar — which is the recovery the old
  # unconditional `\r` gave every row.
  local raw
  raw="$(phase_raw 80 "phase_start activate; phase_ok activate 12.3s ''")"
  [[ "$raw" == *$'\r\033[2K'* ]]
  raw="$(phase_raw 80 "phase_ok build 41.2s")"
  [[ "$raw" == *$'\r\033[2K'* ]]
}

@test "no cursor escape reaches a pipe" {
  # Live-region rule 1: piped, in CI or under bats, no cursor escape is written
  # at all. There is no stub to cover, because phase_start never drew one.
  VERBOSE=1
  run phase_start activate
  [ -z "$output" ]
  [ "$PHASE_STUB" -eq 0 ]
  run phase_ok activate 12.3s '12 services · homebrew changed'
  [[ "$output" != *$'\r'* ]]
  [[ "$output" != *$'\033['* ]]
  [[ "$output" == *"activate"* ]]
}

@test "a window that narrowed past the stub lands a fresh line, not a corrupt one" {
  # A resize reflows what is already on screen in ways nothing can model. One
  # stale stub above the row is honest; `\r` into the middle of it is not.
  # Tested by the absence of `[2K` rather than of `\r`: a pty's ONLCR turns
  # every newline we write into CR LF on the wire, so a raw `\r` proves nothing.
  # `[2K` is written on the repaint path and nowhere else.
  local raw
  raw="$(phase_raw 10 "PHASE_STUB=14; phase_ok activate 12.3s ''")"
  [[ "$raw" != *$'\033[2K'* ]]
  [[ "$raw" == *"✓"* ]]   # …and the row itself still landed, truncated to fit
}

@test "off a terminal nothing is folded, however narrow the window was" {
  # A file has no columns. `haus rebuild >build.log` from an 80-column terminal
  # must not put an `…` in the log — the window it was launched from is not a
  # fact about the file, and a truncated summary is one someone has to re-run
  # the rebuild to recover. bats is not a tty, so this is the live case.
  # A fresh shell, because setup() pins the window for the tests above and this
  # is the one that has to ask the REAL phase_measure what a pipe is worth.
  local long="12 services · homebrew changed · and a great deal more besides, well past any window"
  run bash -c "HAUS_CONSUMER='$HAUS_CONSUMER' HAUS_LIB=1 source '$SUBJECT'; VERBOSE=; phase_ok activate 12.3s '$long'"
  [[ "$output" == *"$long"* ]] || { echo "folded into a pipe: $output"; false; }
  [[ "$output" != *"…"* ]]
}

@test "a session with no terminal and no TERM does not kill its caller" {
  # `tput` exits 2 with TERM unset, and under `set -e` the command after the
  # final `||` is the ONE case the shell does not exempt. Measured before the
  # `|| true`: `ssh mac haus rebuild` (no pty, so no TERM and no controlling
  # terminal) exited 2 with NOTHING on either stream — after a successful
  # evaluation and before anything activated. Silent, and on a workflow this
  # repo's own docs recommend.
  run python3 - "$SUBJECT" "$HAUS_CONSUMER" <<'NOTTY'
import os, sys, subprocess
haus, consumer = sys.argv[1], sys.argv[2]
env = {k: v for k, v in os.environ.items() if k != "TERM"}
env.update(HAUS_LIB="1", HAUS_CONSUMER=consumer)
# start_new_session: no controlling terminal, so /dev/tty cannot be opened and
# the fallback is the path that runs.
p = subprocess.run(
    ["bash", "-c", f"source {haus}; phase_measure; phase_ok resolve 3.4s; echo REACHED-THE-END"],
    env=env, stdin=subprocess.DEVNULL, capture_output=True, start_new_session=True)
print("rc=%d" % p.returncode)
sys.stdout.write(p.stdout.decode())
sys.stdout.write(p.stderr.decode())
NOTTY
  [[ "$output" == *"rc=0"* ]] || { echo "got: $output"; false; }
  [[ "$output" == *"REACHED-THE-END"* ]] || { echo "died before the end: $output"; false; }
}

# ── the colour gate ──────────────────────────────────────────────────────────

@test "haus.sh emits no escape into a pipe, and every one under CLICOLOR_FORCE" {
  run bash -c "HAUS_LIB=1 source '$SUBJECT'; say hi; ok fine; warn careful"
  [[ "$output" != *$'\033['* ]]
  [[ "$output" == *"hi"* ]]

  run bash -c "CLICOLOR_FORCE=1 HAUS_LIB=1 source '$SUBJECT'; say hi; ok fine; warn careful"
  [[ "$output" == *$'\033[38;5;103m'* ]]
  [[ "$output" == *$'\033[38;5;108m'* ]]
  [[ "$output" == *$'\033[38;5;179m'* ]]

  run bash -c "NO_COLOR=1 CLICOLOR_FORCE=1 HAUS_LIB=1 source '$SUBJECT'; say hi"
  [[ "$output" != *$'\033['* ]]
}

@test "haus-show.sh emits no escape into a pipe, and every one under CLICOLOR_FORCE" {
  # `die` is the one painted line reachable with no nix and no fixture, and it
  # goes through the same gate as the whole report. HAUS_DESKTOP_CHECK points at
  # a directory that merely EXISTS so the "no such file" die is the one that
  # fires: without it, a machine with no /run/current-system (every CI runner)
  # trips the checker-missing die three steps earlier instead, and the test
  # would be asserting about a different message on each platform.
  local ck="$BATS_TEST_TMPDIR"
  run bash -c "HAUS_DESKTOP_CHECK='$ck' bash '$SHOW' /nope.nix 2>&1"
  [[ "$output" != *$'\033['* ]]
  [[ "$output" == *"no such file"* ]]

  run bash -c "CLICOLOR_FORCE=1 HAUS_DESKTOP_CHECK='$ck' bash '$SHOW' /nope.nix 2>&1"
  [[ "$output" == *$'\033[38;5;167m'* ]]

  run bash -c "NO_COLOR=1 CLICOLOR_FORCE=1 HAUS_DESKTOP_CHECK='$ck' bash '$SHOW' /nope.nix 2>&1"
  [[ "$output" != *$'\033['* ]]
}

@test "haus show's earliest errors say what they mean" {
  # Every helper scrubs its message, so a `die` that fired before `scrub` was
  # defined printed `scrub: command not found` and then an EMPTY message —
  # `✗ ` and nothing else. The two earliest dies are the two that most need
  # words: an unknown flag, and "this machine's haus predates 'haus show'".
  # Pre-existing; found because the gate test above could not tell which `die`
  # it had reached on a runner with no /run/current-system.
  run bash -c "HAUS_DESKTOP_CHECK=/definitely/not/here bash '$SHOW' /nope.nix 2>&1"
  [[ "$output" == *"haus update"* ]] || { echo "blank checker error: $output"; false; }
  [[ "$output" != *"command not found"* ]]

  run bash -c "bash '$SHOW' --nope 2>&1"
  [[ "$output" == *"unknown flag"* ]] || { echo "blank flag error: $output"; false; }
  [[ "$output" != *"command not found"* ]]
}

@test "no CLI in this room hardcodes an escape outside its palette block" {
  # The gate is only worth having while every escape goes through it, and a new
  # printf with a literal \033[38;5;NNNm in it is exactly how 35 of them
  # accumulated. haus-activate.sh is in the list because `haus rebuild` runs it
  # INSIDE the activate phase, so its one `die` prints into the same stream the
  # other two just stopped painting into. Legal literals: the C_* assignments,
  # a comment at any indent, and `[2K`, which is cursor motion rather than
  # colour and is written only on a terminal.
  local f hits
  for f in "$SUBJECT" "$SHOW" "$BATS_TEST_DIRNAME/../modules/core/haus-activate.sh"; do
    hits="$(grep -n '\\033\[' "$f" \
      | grep -v "C_[A-Z]*=\$'" \
      | grep -v '033\[2K' \
      | grep -v '^[0-9]*:[[:space:]]*#' || true)"
    [ -z "$hits" ] || { echo "$f still paints by hand:"; echo "$hits"; false; }
  done
}

# ── the measurement itself ───────────────────────────────────────────────────

@test "phase_measure reads COLUMNS from the kernel, not rows and not terminfo" {
  # Two ways to get this wrong, and both survive a source grep:
  #   · `tput cols` reads terminfo's STATIC size — 80 for every xterm-* entry —
  #     and answers 80 in a 37-column window. Only TIOCGWINSZ tracks a resize.
  #   · `stty size` prints "<rows> <cols>", so a `${sz% *}` takes the ROWS.
  # 24×37: neither field is 80 and neither equals the other, so a pty is the
  # only thing that can tell the three answers apart.
  run python3 - "$SUBJECT" "$HAUS_CONSUMER" <<'PYEOF'
import os, pty, sys, fcntl, termios, struct, select
haus, consumer = sys.argv[1], sys.argv[2]
pid, fd = pty.fork()
if pid == 0:
    # Gate on a read so the parent's TIOCSWINSZ lands before we measure.
    os.execvp("bash", ["bash", "-c",
        f"read -r _; HAUS_CONSUMER={consumer} HAUS_LIB=1 source {haus};"
        " phase_measure; echo COLS=$PHASE_COLS"])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 37, 0, 0))
os.write(fd, b"\n")
out = b""
while True:
    r, _, _ = select.select([fd], [], [], 5)
    if not r:
        break
    try:
        d = os.read(fd, 65536)
    except OSError:
        break
    if not d:
        break
    out += d
    if b"COLS=" in out:
        break
sys.stdout.write(out.decode("utf8", "replace"))
PYEOF
  [[ "$output" == *"COLS=37"* ]] || { echo "got: $output"; false; }
}

# ── and the whole thing, on a real terminal ──────────────────────────────────
#
# The tests above call the painter with a width handed to it. This one gives it
# a WINDOW: a pty of a stated size, a stub, a repaint, and a tiny terminal that
# renders the bytes the way a terminal does — wrapping at the right margin, `\r`
# to column 0 of the current physical row, `[2K` clearing it. It is the only
# thing here that can see an orphan, because an orphan is a property of the
# screen and not of the stream.

phase_screen() { # phase_screen <cols> — the rendered screen after one phase
  python3 - "$SUBJECT" "$HAUS_CONSUMER" "$1" <<'PYEOF'
import os, pty, sys, fcntl, termios, struct, select, re, unicodedata
haus, consumer, cols = sys.argv[1], sys.argv[2], int(sys.argv[3])
pid, fd = pty.fork()
if pid == 0:
    os.execvp("bash", ["bash", "-c",
        f"read -r _; HAUS_CONSUMER={consumer} HAUS_LIB=1 source {haus}; VERBOSE=;"
        " phase_start activate;"
        " phase_ok activate 12.3s '12 services · homebrew changed'"])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, cols, 0, 0))
os.write(fd, b"\n")
buf = b""
while True:
    r, _, _ = select.select([fd], [], [], 5)
    if not r:
        break
    try:
        d = os.read(fd, 65536)
    except OSError:
        break
    if not d:
        break
    buf += d
os.waitpid(pid, 0)

text, screen, row, col, i = buf.decode("utf8", "replace"), [[" "] * cols], 0, 0, 0
CSI = re.compile(r"\033\[([0-9;?]*)([A-Za-z])")
def ensure(r):
    while len(screen) <= r:
        screen.append([" "] * cols)
while i < len(text):
    m = CSI.match(text, i)
    if m:
        if m.group(2) == "K":
            ensure(row)
            start = 0 if m.group(1) == "2" else col
            for c in range(start, cols):
                screen[row][c] = " "
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
  local w out n
  for w in 120 53 52 40 20 14 13 10 6 3; do
    out="$(phase_screen "$w")"
    n="$(printf '%s\n' "$out" | grep -c . || true)"
    [ "$n" -eq 1 ] || { echo "cols=$w left $n rows on screen:"; printf '%s\n' "$out"; false; }
    # The stub is the only row that opens with `·` — the finished row opens
    # with `✓`, and the `·` inside "12 services · homebrew changed" is mid-line.
    if printf '%s\n' "$out" | grep -q '^[[:space:]]*·'; then
      echo "cols=$w orphaned the stub:"; printf '%s\n' "$out"; false
    fi
  done
}

# ── snug's bash painter, reached through HAUS_UI_SH ──────────────────────────
# haus.sh is `builtins.readFile`'d into a store binary, so `dirname $0` is
# /nix/store and there is no checkout beside it — the wrapper in
# modules/core/default.nix hands it snug's `share/ui.sh` as an absolute path
# instead. These two cases are the whole contract of that hand-off: it takes
# when the path is real, and it costs the caller NOTHING when it is not.
#
# A fresh shell each time, not the sourced-in-process one from setup(): the
# thing under test is what happens at load, under `set -euo pipefail`.

haus_sh() { # haus_sh <env…> — load haus.sh as a library and run the snippet
  local snippet="${!#}"
  run env "${@:1:$#-1}" HAUS_CONSUMER="$HAUS_CONSUMER" HAUS_LIB=1 "$BASH" -c \
    "set -euo pipefail; source '$SUBJECT'; $snippet"
}

@test "haus.sh sources the painter HAUS_UI_SH points at" {
  local ui="$BATS_TEST_TMPDIR/ui.sh"
  cat > "$ui" <<'UI'
ui_say() { printf 'FIXTURE %s\n' "$*"; }
UI
  haus_sh HAUS_UI_SH="$ui" 'ui_say hello'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "FIXTURE hello" ]
}

@test "haus.sh loads with HAUS_UI_SH unset, and with it pointing at nothing" {
  # The measured failure shape this guard exists for, and haus.sh's `set -euo
  # pipefail` makes both halves of it fatal: an unset variable dies on `-u`, and
  # a `source` of a missing path exits 1 under `-e`. Either kills `haus` at LOAD
  # time — before any verb ran, with nothing on either stream and nothing
  # activated. That is the worst possible failure mode for a courtesy, and it is
  # the same shape as the `tput` bug the width probe carries a `|| true` for.
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

@test "the painter it loads is snug's, and still draws inside haus.sh" {
  # Not a fixture: the real file, so a rename or a moved marker in snug fails
  # here rather than on somebody's machine. Skipped when there is no snug
  # checkout beside this one — CI for THIS repo has no reason to clone it, and
  # snug's own bash job is where that file is actually tested.
  local ui="$BATS_TEST_DIRNAME/../../snug/share/ui.sh"
  [ -r "$ui" ] || skip "no snug checkout beside haus (looked in $ui)"
  haus_sh HAUS_UI_SH="$ui" SNUG_ASCII=1 'ui_say drawn; ui_ok also drawn'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # ui.sh puts every human line on fd 2 — which is exactly why haus.sh's own
  # verbs are NOT yet routed through it. `run` merges the streams, so seeing
  # them here is the assertion that it drew, not that it drew on stdout.
  [[ "$output" == *drawn* ]] || { echo "got: $output"; false; }
}

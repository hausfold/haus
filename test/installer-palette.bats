#!/usr/bin/env bats
# The two installers' inlined nebelung, diffed against snug's generated
# `share/ui.sh`. The standard is docs/cli-presentation.md in the workshop; this
# suite is the enforcement of its ONE permanent exemption.
#
# What it is FOR. `bootstrap.sh` and `modules/core/haus-activate.sh` both run
# before snug is reachable — the first is a standalone `curl … | bash` on a Mac
# with no nix at all, the second is handed a reset environment by sudo, as root,
# to activate the very generation that would install `share/ui.sh`. So they are
# the only two scripts in the family that spell a colour NUMBER rather than
# naming a role. That is a copy of a generated table, and a copy drifts: the
# palette moves in nebelung, snug regenerates, and these two keep painting last
# year's hue on the one screen a new user sees before anything else. Nothing
# else would notice — a wrong index is green at eval, green at `nix flake
# check`, green through a build, and only ever visible to someone holding the
# two files side by side.
#
# ui.sh is the REAL file, fetched in CI at the rev flake.lock pins (see the
# workflow step above the one that runs this). A fixture would make the whole
# suite green while checking nothing, which is the failure this repo has been
# bitten by once already.
#
# The role→token indirection is read from ui.sh too, so remapping `err` off
# `red` in snug fails here as loudly as moving `red`'s hex does.

setup() {
  BOOT="$BATS_TEST_DIRNAME/../bootstrap.sh"
  ACTIVATE="$BATS_TEST_DIRNAME/../modules/core/haus-activate.sh"
  UI_SH_REAL="$(real_ui_sh || true)"
}

# snug's `share/ui.sh`, wherever this machine keeps it. In PIN ORDER, because
# only the first two are the rev flake.lock names:
#
#   $HAUS_UI_SH                 what CI exports, fetched at the pinned rev
#   the store copy beside       a haus machine's own — `command -v snug` then
#     `bin/snug`                  `readlink -f`, the resolution AGENTS.md
#                                 documents for a caller outside the wrapper
#   a snug checkout             UNPINNED, and last for that reason: a developer
#                                 whose checkout has wandered gets an answer
#                                 that is not what CI will diff against
#
# Empty when there is none — the shape tests below still have to pass without it.
real_ui_sh() {
  local p snug
  snug="$(command -v snug 2>/dev/null || true)"
  [ -n "$snug" ] && snug="$(dirname "$(dirname "$(readlink -f "$snug")")")/share/ui.sh"
  for p in "${HAUS_UI_SH:-}" \
           "$snug" \
           "$BATS_TEST_DIRNAME/../../snug/share/ui.sh" \
           "$HOME/code/workshop/snug/share/ui.sh"; do
    [ -n "$p" ] && [ -r "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
}

# A skip is an `ok` in TAP, and three of the tests below are behind this one —
# so on a runner, "the fetch step moved" and "the palette is in step" look
# IDENTICAL. That is the vacuity this whole suite exists to prevent, aimed at
# itself. Off a runner a skip is honest (a stranger's checkout has no snug); in
# CI it is the failure, so say so out loud and go red.
need_ui() {
  [ -n "$UI_SH_REAL" ] && return 0
  [ -z "${CI:-}" ] || {
    echo "no share/ui.sh in CI — the 'snug's painter, at the pinned rev' step"
    echo "must run BEFORE this suite and export HAUS_UI_SH into \$GITHUB_ENV."
    false
  }
  skip "no snug share/ui.sh on this machine"
}

# Ask ui.sh itself for a role's three numbers, rather than parsing its generated
# block — a reformatted table must not read as a palette change. The variant is
# `nebelung` because that is what ui__detect_variant answers with nothing in
# ~/.config/snug/variant, which is exactly the machine both installers run on.
ui_role() { # ui_role <role> -> "<hex> <x256> <ansi16>"
  "$BASH" -c '
    set -euo pipefail
    unset SNUG_VARIANT
    source "$1"
    tok="${UI__TOKEN[$2]}"
    printf "%s %s %s" "${UI__HEX[nebelung:$tok]}" \
                      "${UI__X256[nebelung:$tok]}" \
                      "${UI__ANSI16[$2]}"
  ' _ "$UI_SH_REAL" "$1"
}

# What a file DECLARES for a role, read the way the script itself reads it.
file_role() { # file_role <path> <role> -> "<hex> <x256> <ansi16>"
  local up
  up="$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')"
  "$BASH" -c '
    set -euo pipefail
    eval "$(grep -E "^UI_(HEX|X256|ANSI)_$2=" "$1")"
    h="UI_HEX_$2"; x="UI_X256_$2"; a="UI_ANSI_$2"
    printf "%s %s %s" "${!h}" "${!x}" "${!a}"
  ' _ "$1" "$up"
}

@test "bootstrap.sh's four roles are snug's, hex and 256 and 16" {
  need_ui
  local role
  for role in accent warn err muted; do
    [ "$(file_role "$BOOT" "$role")" = "$(ui_role "$role")" ] || {
      echo "bootstrap.sh $role: $(file_role "$BOOT" "$role")"
      echo "snug ui.sh    $role: $(ui_role "$role")"
      false
    }
  done
}

@test "haus-activate.sh's err is snug's, hex and 256 and 16" {
  need_ui
  [ "$(file_role "$ACTIVATE" err)" = "$(ui_role err)" ] || {
    echo "haus-activate.sh err: $(file_role "$ACTIVATE" err)"
    echo "snug ui.sh       err: $(ui_role err)"
    false
  }
}

# The marks are a copy too, and until now nothing diffed them. Both installers
# spell their glyphs as literals for the same reason they spell colour NUMBERS:
# they cannot reach `ui_glyph_bare` on a Mac with no nix. That makes the marks
# the same kind of hand-maintained copy — and the same kind of silent drift, on
# the same first screen. snug swapping a mark leaves the installer painting the
# old one, green at every other gate this repo has.
#
# The ASCII half is deliberately NOT diffed: neither installer has a locale gate
# and neither ever draws it, so there is nothing on this side to drift.
#
# ⚠️ Everything here is bytes-vs-runes, so the whole comparison runs under an
# explicit UTF-8 locale. Under `LC_ALL=C` a `[^ ]` class matches ONE BYTE of a
# three-byte glyph and bash expands ui.sh's `$'\u224B'` to the literal six
# characters — so a C-locale runner would red with "draws '', snug's say is
# '\u224B'", which reads as drift and is not. This is the only test in the file
# that compares text rather than numbers, and the only one that needs this.
UI_LOCALE=C.UTF-8

ui_glyph() { # ui_glyph <mark> -> the UTF-8 glyph, from the real ui.sh
  LC_ALL="$UI_LOCALE" "$BASH" -c '
    set -euo pipefail
    source "$1"
    printf "%s" "${UI__GLYPH_UTF8[$2]}"
  ' _ "$UI_SH_REAL" "$1"
}

# The glyph as the script actually prints it: the rune between the colour
# variable and the two spaces of gutter, in `<fn>() { printf '<colour>G  …' }`.
file_glyph() { # file_glyph <path> <fn>
  LC_ALL="$UI_LOCALE" sed -n "s/^$2()  *{ printf '[^']*%s\\(.\\)  .*/\\1/p" "$1"
}

@test "the installers' marks are snug's" {
  need_ui
  local row f fn mark want got
  # <file> <verb> <role>. bootstrap.sh draws three; haus-activate.sh draws one,
  # and the suite already diffs that one's colour.
  for row in "$BOOT say say" "$BOOT warn warn" "$BOOT die err" \
             "$ACTIVATE die err"; do
    set -- $row; f=$1; fn=$2; mark=$3
    want="$(ui_glyph "$mark")"
    got="$(file_glyph "$f" "$fn")"
    [ "$got" = "$want" ] || {
      echo "$(basename "$f") $fn(): draws '$got', snug's $mark is '$want'"
      false
    }
  done
}

@test "the two installers agree with each other about err" {
  [ "$(file_role "$BOOT" err)" = "$(file_role "$ACTIVATE" err)" ]
}

# The defect the standard was written against: a hue picked by eye. Once every
# colour is a named role resolved from the constants above, there is no legal
# place left for a literal index — so any `38;5;<n>` or `38;2;<r;g;b>` in either
# file is a hand-pick, and any bare SGR attribute (`\033[2m` dim, `\033[3xm`) is
# the same mistake wearing a different escape. `\033[0m` is structure, not
# colour, and stays: it is what ui.sh's own UI_OFF is.
@test "neither installer hardcodes a colour" {
  local f
  for f in "$BOOT" "$ACTIVATE"; do
    ! grep -nE '38;[52];[0-9]' "$f" || { echo "hardcoded index in $f"; false; }
    ! grep -nE '\\033\[[0-9;]*[0-9]m' "$f" | grep -vE '\\033\[0m' \
      || { echo "raw SGR in $f (only \\033[0m is structure)"; false; }
  done
}

# The ported precedence, pinned against ui.sh's own — NO_COLOR beats everything
# except CLICOLOR_FORCE, a non-TTY is colourless unless forced, and `dumb` means
# it under CLICOLOR_FORCE too. It is copied prose in two files, so it drifts the
# same way the numbers do; this is the same diff for the gate.
@test "the inlined gate answers exactly what ui.sh's detector does" {
  need_ui
  local f env_case out want got
  for f in "$BOOT" "$ACTIVATE"; do
    for env_case in \
      "TERM=xterm-256color COLORTERM=truecolor" \
      "TERM=xterm-256color COLORTERM=" \
      "TERM=xterm COLORTERM=" \
      "TERM=dumb COLORTERM=" \
      "TERM= COLORTERM=" \
      "TERM=xterm-256color COLORTERM= NO_COLOR=1" \
      "TERM=xterm-256color COLORTERM= NO_COLOR=1 CLICOLOR_FORCE=1" \
      "TERM=xterm-256color COLORTERM= CLICOLOR_FORCE=0"
    do
      # ui.sh measures fd 2 at load; both sides are asked about the same
      # forced-TTY answer so only the RULE is under test, not the window.
      want="$("$BASH" -c '
        set -euo pipefail
        unset NO_COLOR CLICOLOR_FORCE
        eval "export $3"
        source "$1"
        UI_TTY="$2"; ui__detect_profile; printf "%s" "$UI_PROFILE"
      ' _ "$UI_SH_REAL" 1 "$env_case")"
      got="$("$BASH" -c '
        set -euo pipefail
        unset NO_COLOR CLICOLOR_FORCE
        eval "export $3"
        # Read only the gate out of the script — sourcing bootstrap.sh would
        # run the installer.
        eval "$(sed -n "/^ui_profile() {/,/^}/p" "$1")"
        ui_profile "$2"
      ' _ "$f" 1 "$env_case")"
      [ "$want" = "$got" ] || {
        echo "$f under [$env_case]: ui.sh says $want, the installer says $got"
        false
      }
    done
  done
}

# The other half of that gate: `bootstrap.sh` has TWO streams to be right about,
# and it is the only family CLI that does. The two-streams rule elsewhere keys on
# the COMMAND — a report draws on fd 1, a narrator on fd 2 — but bootstrap's
# whole preflight (the audit, the settings table, the undo note) is plain stdout
# prose, so its narration is gated with it on fd 1 and only `die` draws on fd 2.
#
# ⚠️ The negative alone does not test this. Under `run`, neither stream is a
# terminal, both gates answer `none`, and a COLLAPSED implementation — one gate
# asked about one stream and used for both — is indistinguishable from the right
# one. So each stream gets a real pty in turn, with the other on a pipe, and the
# assertion is that the paint follows the pty. That is the bug this catches:
# `bootstrap.sh | tee log` coming out either escape-littered or silently
# monochrome, depending which way the collapse went.
#
# The gate is read out of the script rather than sourced — sourcing bootstrap.sh
# would run the installer.
two_streams() { # two_streams <1|2 — which fd gets the pty> -> "1[set|] 2[set|]"
  python3 - "$BOOT" "$BASH" "$1" <<'PYEOF'
import os, pty, select, subprocess, sys
boot, bash, which = sys.argv[1], sys.argv[2], sys.argv[3]
snippet = (
    'eval "$(sed -n "/^# ── nebelung, inlined/,/^unset _tty1/p" "$1")"; '
    'printf "1[%s] 2[%s]\n" "${C_ACCENT:+set}" "${E_ERR:+set}"'
)
master, slave = pty.openpty()
r, w = os.pipe()
out, err = (slave, w) if which == "1" else (w, slave)
env = dict(os.environ, TERM="xterm-256color")
for k in ("NO_COLOR", "CLICOLOR_FORCE", "COLORTERM"):
    env.pop(k, None)
p = subprocess.Popen([bash, "-c", snippet, "_", boot], stdout=out, stderr=err,
                     stdin=subprocess.DEVNULL, env=env)
os.close(w)
p.wait()
# The parent keeps its own slave fd open on purpose. Closing the LAST slave
# hands the master an EIO and discards whatever is still in the tty buffer —
# measured: this test read an empty string every time until the close moved
# below the read. So the pty is drained with a timeout instead of an EOF.
data = b""
while True:
    ready, _, _ = select.select([master], [], [], 0.5)
    if not ready:
        break
    chunk = os.read(master, 4096)
    if not chunk:
        break
    data += chunk
    if b"\n" in data:
        break
os.close(slave)
while True:                  # the pipe's write end IS closed, so this sees EOF
    chunk = os.read(r, 4096)
    if not chunk:
        break
    data += chunk
sys.stdout.write(data.decode(errors="replace").replace("\r", "").strip())
PYEOF
}

@test "bootstrap.sh gates its two streams apart" {
  local out
  # Off a terminal entirely: nobody is watching either stream, so nothing paints.
  out="$("$BASH" -c '
    eval "$(sed -n "/^# ── nebelung, inlined/,/^unset _tty1/p" "$1")"
    printf "1[%s] 2[%s]" "${C_ACCENT:+set}" "${E_ERR:+set}"
  ' _ "$BOOT" 2>/dev/null </dev/null | cat)"
  [ "$out" = "1[] 2[]" ] || { echo "off a tty, got: $out"; false; }

  # A terminal on stdout only — the narration paints, `die` does not.
  out="$(two_streams 1)"
  [ "$out" = "1[set] 2[]" ] || {
    echo "pty on fd 1, pipe on fd 2: expected 1[set] 2[], got: $out"
    echo "one gate is answering for both streams"
    false
  }

  # And the mirror: a terminal on stderr only.
  out="$(two_streams 2)"
  [ "$out" = "1[] 2[set]" ] || {
    echo "pipe on fd 1, pty on fd 2: expected 1[] 2[set], got: $out"
    echo "one gate is answering for both streams"
    false
  }
}

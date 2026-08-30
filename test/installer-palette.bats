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

# snug's `share/ui.sh`, wherever this machine keeps it: the path CI exports, a
# snug checkout beside this one, or a haus machine's own store copy. Empty when
# there is none — the shape tests below still have to pass without it.
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

# The other half of that gate: a stream nobody is watching gets no escapes, and
# `bootstrap.sh` has TWO streams to be right about. Its whole preflight — the
# audit, the settings table, the undo note — is plain stdout prose, so its
# narration is gated on fd 1 alongside it and only `die` draws on fd 2. One gate
# asked about both is how `bootstrap.sh | tee log` ends up either
# escape-littered or silently monochrome.
@test "bootstrap.sh gates its two streams apart" {
  local out
  out="$("$BASH" -c '
    eval "$(sed -n "/^# ── nebelung, inlined/,/^unset _tty1/p" "$1")"
    printf "1[%s] 2[%s]" "${C_ACCENT:+set}" "${C_ERR:-${E_ERR:+set}}"
  ' _ "$BOOT" 2>/dev/null </dev/null | cat)"
  # Neither stream is a terminal under `run`, so neither may be painted.
  [ "$out" = "1[] 2[]" ] || { echo "unforced, off a tty, got: $out"; false; }
}

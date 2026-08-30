#!/usr/bin/env bash
# haus-activate — activate an ALREADY-BUILT darwin system, without evaluating
# the config a second time.
#
# Why this exists. `darwin-rebuild switch --flake .#host` BUILDS before it
# activates, and it runs as root — so a `haus rebuild` (or `bench try switch`),
# which has already built that exact system as YOU, pays for a whole second
# evaluation against root's separate caches under /var/root/.cache/nix.
# Measured on a small consumer config: ~3 s after a host-file edit, and ~15 s
# whenever a flake input moved, because root then re-unpacks nixpkgs into its
# own lazy-trees git cache (~84 MB) that your user-side eval just finished
# unpacking into yours. Pure duplicate work: same store, same result.
#
# So haus builds once, as you, and hands the store path here. This does only
# the two privileged steps `switch` performs AFTER its build:
#
#     nix-env -p /nix/var/nix/profiles/system --set <system>
#     <system>/sw/bin/darwin-rebuild activate
#
# Both lines are load-bearing. `activate` alone does NOT bump the system
# profile, so without the nix-env line `haus rollback` would have no generation
# to go back to; and the activation itself is deliberately delegated to the
# BUILT system's own darwin-rebuild rather than reimplemented here, so this
# wrapper can never drift from whatever nix-darwin decides activation means
# (today: the activate-user compatibility shim, the root check, then
# `$system/activate`).
#
# Why it's a separate binary at a stable path, rather than a branch inside
# `haus`: security's passwordless-sudo rule has to name a literal path (sudo
# ≥1.9.17 no longer dereferences the command symlink before matching sudoers),
# and the path it names is /run/current-system/sw/bin/haus-activate. That grant
# is no wider than the darwin-rebuild one beside it — `darwin-rebuild switch
# --flake <anything>` already activates any tree you can build, as root.
set -euo pipefail

# Invoked through sudo, where the environment is reset — resolve our own tools.
PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export PATH

# The whole of this script's output is that one `die`, and it goes to STDERR —
# so the gate reads fd 2, where haus.sh and haus-show.sh read fd 1. Gating on
# stdout here would answer about the wrong stream: `haus rebuild` runs this
# inside a phase whose stdout is the rebuild log, with the terminal still on
# stderr, which is exactly when the message is worth painting.
#
# ── nebelung, inlined ────────────────────────────────────────────────────────
# This script and the repo's `bootstrap.sh` are the only two places in the
# family that spell a colour NUMBER instead of naming a role, and this comment
# is the whole of the exemption: both run before snug is reachable. This one is
# handed a PATH by sudo with the environment reset, as root, to activate the
# very generation that would put `share/ui.sh` somewhere it could source — so
# there is nothing to source and nothing to drive. That was never a licence to
# pick a hue by eye, which is how this line sat on index 167 while every other
# family CLI had moved to nebelung's own `red`.
#
# So the number is COPIED, never chosen: it is snug's generated `share/ui.sh`
# for the `nebelung` variant — the variant ui.sh itself resolves to when nothing
# has written ~/.config/snug/variant — and `test/installer-palette.bats` diffs
# it against that file, so a nebelung that moves reds the suite instead of
# drifting quietly. Never hand-pick an index here.
#
#   role  token  hex      x256  ansi16   what it says
#   err   red    ed8fa9   211   91       failure
UI_HEX_ERR=ed8fa9; UI_X256_ERR=211; UI_ANSI_ERR=91

# ui.sh's own precedence, ported rather than re-derived: NO_COLOR beats
# everything except CLICOLOR_FORCE, a non-TTY is colourless unless forced, and
# `dumb` means it under CLICOLOR_FORCE too — there is no escape a dumb terminal
# will not print at you literally. An empty C_* is the fallback, so the same
# printf below stays clean text.
ui_profile() { # ui_profile <non-empty if that stream is a tty> -> none|16|256|truecolor
  local forced=
  case "${CLICOLOR_FORCE:-}" in '' | 0) ;; *) forced=1 ;; esac
  if [ -n "${NO_COLOR+set}" ] && [ -z "$forced" ]; then printf none; return 0; fi
  if [ -z "$1" ] && [ -z "$forced" ]; then printf none; return 0; fi
  if [ "${TERM:-}" = dumb ]; then printf none; return 0; fi
  case "${COLORTERM:-}" in
    truecolor | 24bit | TRUECOLOR | 24BIT) printf truecolor; return 0 ;;
  esac
  case "${TERM:-}" in
    *truecolor* | *direct*) printf truecolor ;;
    *256*)                  printf 256 ;;
    # Forced with nothing to go on — a CI log renderer, usually. 256 is the safe
    # middle: universally understood, and a small step from the hex.
    '')                     printf 256 ;;
    *)                      printf 16 ;;
  esac
  return 0
}

ui_sgr() { # ui_sgr <profile> <err>
  # Emptied, and with a default arm below: an unknown role must return NO
  # colour, never die. `${hex:0:2}` on an unset name is fatal under `set -u`,
  # and in bootstrap.sh that is an installer that aborts on a fresh Mac over a
  # caller's typo — the one failure mode a painter must never have.
  local hex= x256= ansi=
  case "$2" in
    err) hex=$UI_HEX_ERR; x256=$UI_X256_ERR; ansi=$UI_ANSI_ERR ;;
    *)   return 0 ;;
  esac
  case "$1" in
    truecolor) printf '\033[38;2;%s;%s;%sm' \
                 "$((16#${hex:0:2}))" "$((16#${hex:2:2}))" "$((16#${hex:4:2}))" ;;
    256)       printf '\033[38;5;%sm' "$x256" ;;
    16)        printf '\033[%sm' "$ansi" ;;
  esac
  return 0
}

_tty2=; [ -t 2 ] && _tty2=1
_prof2="$(ui_profile "$_tty2")"
C_OFF=; C_ERR=
[ "$_prof2" != none ] && { C_OFF=$'\033[0m'; C_ERR="$(ui_sgr "$_prof2" err)"; }
unset _tty2 _prof2

die() { printf '%s✗  %s%s\n' "$C_ERR" "$*" "$C_OFF" >&2; exit 1; }

[ -n "${1:-}" ] || die "usage: sudo haus-activate <system>   (./result, or a /nix/store/…-darwin-system-… path)"
[ "$(id -u)" -eq 0 ] || die "must run as root — try: sudo /run/current-system/sw/bin/haus-activate $1"

# Resolve ./result-style symlinks to the store path the profile must point at.
# `cd … && pwd -P` rather than `readlink -f`: this runs before any coreutils is
# guaranteed on PATH, and BSD readlink's -f is not something to rely on here.
sys="$(cd "$1" 2>/dev/null && pwd -P)" || die "no such system: $1"
case "$sys" in
  /nix/store/*) ;;
  *) die "not a store path: $sys" ;;
esac
[ -x "$sys/activate" ] && [ -x "$sys/sw/bin/darwin-rebuild" ] ||
  die "$sys doesn't look like a darwin system (no activate / sw/bin/darwin-rebuild)"

# The same two environment fixups darwin-rebuild makes for itself: sudo keeps
# the invoking user's $HOME, which makes nix warn about an unwritable store
# config; and the daemon owns the store even when we're root.
export HOME=~root
export NIX_REMOTE="${NIX_REMOTE:-daemon}"

nix-env -p /nix/var/nix/profiles/system --set "$sys"
# $SUDO_USER rides through from sudo — darwin-rebuild needs it for the legacy
# activate-user shim on systems old enough to still have one.
exec "$sys/sw/bin/darwin-rebuild" activate

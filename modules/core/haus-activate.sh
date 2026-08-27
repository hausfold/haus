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
# stderr, which is exactly when the message is worth painting. Otherwise the
# same rule as everywhere: NO_COLOR off, CLICOLOR_FORCE on through a pipe, and
# an empty C_* so the same printf falls back to clean text.
if { [ -t 2 ] || [ -n "${CLICOLOR_FORCE:-}" ]; } && [ -z "${NO_COLOR:-}" ]; then
  C_OFF=$'\033[0m'; C_ERR=$'\033[38;5;167m'   # rose — failure
else
  C_OFF=; C_ERR=
fi

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

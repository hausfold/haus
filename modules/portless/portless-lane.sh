#!/usr/bin/env bash
# portless-lane — run a dev server in a holt lane under `<lane>.<repo>.localhost`.
#
# portless already names a worktree well on its own: inside one it prefixes the
# git branch, so a lane lands on `<branch>.<project>.localhost` with no help from
# anybody. The gap this closes is cosmetic and is holt's fault, not portless':
# `branchToPrefix` splits a branch on "/" and takes the last segment, and holt's
# branches are `worktree-<lane>` with a DASH — so the prefix comes out as the
# whole `worktree-wiggly-crane` rather than the `wiggly-crane` you call the lane.
# There is no flag to override just the prefix (--name replaces the base name and
# the prefix is still prepended in front of it), so the short name is registered
# alongside as a static route. Both work; this one is the one you can say aloud.
#
# The port is chosen HERE and handed to portless with --app-port, rather than
# letting portless assign one and then reading it back. Two reasons, and the
# second is the load-bearing one:
#
#   1. `portless alias` needs a port to point at, and polling `portless list`
#      for the port portless just picked is a race against the app's own startup.
#   2. A port derived from the lane's NAME is stable across restarts, which is
#      what makes the URL stable for a browser tab that is already open — the
#      entire promise. An auto-assigned port is fresh every run.
#
# Derived, then probed upward: the hash is what makes it stable, the probe is
# what makes it correct, and a lane is what makes a collision unlikely enough
# that the probe almost never moves. $HOLT_PORT wins if holt handed us one.
set -euo pipefail

portless=@portless@
lane_fallback_base=4000
lane_fallback_span=1000

die() {
  printf 'portless-lane: %s\n' "$1" >&2
  exit 1
}

command -v git >/dev/null 2>&1 || die "git is not on PATH"

# ── who am I ─────────────────────────────────────────────────────────────────
# The lane is the checkout's own directory name, which is what holt named it and
# what you type at `holt <name>`. The repo is the MAIN checkout's basename, the
# same join lane-open.sh makes for its zmx session name — `git rev-parse
# --git-common-dir` points into the main checkout's .git from inside a worktree.
common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || die "not in a git repo"
toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || die "not in a git repo"

case $common_dir in
  /*) ;;
  *) common_dir=$toplevel/$common_dir ;;
esac
main_checkout=$(cd "$common_dir/.." && pwd)

if [ "$main_checkout" = "$toplevel" ]; then
  # Not a worktree at all — the main checkout. Nothing to disambiguate, so get
  # out of the way entirely and let portless do what it does with no prefix.
  exec "$portless" run "$@"
fi

lane=$(basename "$toplevel")
# $HOLT_MAIN first, for the same reason lane-open.sh prefers it over the cwd: it
# is the main checkout holt RECORDED, and it is right even from a `holt child`
# worktree of a sibling repo, where walking up from here would name the parent's.
repo=$(basename "${HOLT_MAIN:-$main_checkout}")
name="$lane.$repo"

# NOTE the second label is the REPO's directory name, which is what holt calls it
# and what you type at `holt <name>` — not portless' own inferred project name,
# which comes from package.json and can differ. When they differ you simply get
# two working names for one server (`wiggly-crane.haus` here, portless'
# `worktree-wiggly-crane.myapp` beside it), which is the cheap direction for
# this to be wrong in.

# ── the port ─────────────────────────────────────────────────────────────────
# cksum over the name, folded into portless' own 4000-4999 range so the two
# allocators cannot disagree about who owns what. cksum rather than a hash
# written out in awk: it is POSIX, it is one fork, and nothing here is
# cryptographic — "the same name lands on the same number" is the whole spec.
hash_port() { printf '%s' "$1" | cksum | cut -d' ' -f1; }

# /dev/tcp rather than `nc`: this is bash already, so the probe costs no process
# and cannot be defeated by a PATH that has no netcat on it.
port_free() { ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

if [ -n "${HOLT_PORT:-}" ]; then
  port=$HOLT_PORT
else
  port=$((lane_fallback_base + $(hash_port "$name") % lane_fallback_span))
  tries=0
  while ! port_free "$port"; do
    port=$((lane_fallback_base + (port - lane_fallback_base + 1) % lane_fallback_span))
    tries=$((tries + 1))
    [ "$tries" -lt "$lane_fallback_span" ] ||
      die "no free port in ${lane_fallback_base}-$((lane_fallback_base + lane_fallback_span - 1))"
  done
fi

# ── the short name ───────────────────────────────────────────────────────────
# --force, because the lane's own alias from a previous run is exactly what we
# expect to find and exactly what we mean to replace. Best-effort: a failure here
# costs the pretty name, and losing the pretty name must not cost you the server.
"$portless" alias "$name" "$port" --force >/dev/null 2>&1 ||
  printf 'portless-lane: could not register %s (the branch-prefixed name still works)\n' "$name.localhost" >&2

printf 'portless-lane: %s -> :%s\n' "$name.localhost" "$port" >&2

exec "$portless" run --app-port "$port" "$@"

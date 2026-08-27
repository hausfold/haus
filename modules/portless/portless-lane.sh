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
# That paragraph has an expiry date: vercel-labs/portless#398 adds `--prefix`
# and PORTLESS_PREFIX, which is this shim's whole job done one level down. When
# it lands and the pin moves past it, delete this file and have lane-open.sh
# export PORTLESS_PREFIX="$lane" instead.
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
# that the probe almost never moves.
#
# The range is deliberately OUTSIDE portless' own 4000-4999 auto-assign window.
# Sharing it looked tidy and was backwards: portless hands 4000-4999 to apps it
# assigns itself, so a lane's hashed port and some other app's assigned port
# could land on the same number, and `port_free` only catches that if the other
# server is already listening — a window this script cannot close, since nothing
# is bound until `portless run` gets there. Disjoint ranges close it by
# construction. HAUS_PORTLESS_PORT pins the number by hand if you need it.
set -euo pipefail

portless=@portless@
lane_base=5200
lane_span=600

die() {
  printf 'portless-lane: %s\n' "$1" >&2
  exit 1
}

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

# Hostname labels, so the names below cannot be rejected by the thing they are
# names for: `portless alias` refuses an underscore outright, and a capital in a
# hostname is a difference nobody means. Everything else a directory name can
# hold is already legal.
label() { printf '%s' "$1" | tr '[:upper:]_' '[:lower:]-'; }

lane=$(label "$(basename "$toplevel")")
# git, and deliberately NOT $HOLT_MAIN. That looked like the better source —
# lane-open.sh prefers it — and measuring it said otherwise: HOLT_MAIN is a HOOK
# variable that LEAKS into the pane it opens and every shell started from there,
# so a pane opened on repo A that cd's into a worktree of repo B still carries
# A's path. Trusting it named a `myapp` worktree `wiggly-crane.haus` in exactly
# that setup. Walking up from the cwd cannot be wrong about the cwd.
repo=$(label "$(basename "$main_checkout")")
name="$lane.$repo"

# NOTE the second label is the REPO's directory name, which is what holt calls it
# and what you type at `holt <name>` — not portless' own inferred project name,
# which comes from package.json and can differ. When they differ you simply get
# two working names for one server (`wiggly-crane.haus` here, portless'
# `worktree-wiggly-crane.myapp` beside it), which is the cheap direction for
# this to be wrong in.

# ── the port ─────────────────────────────────────────────────────────────────
# cksum over the name, folded into the private range above. cksum rather than a
# hash written out in awk: it is POSIX, it is one fork, and nothing here is
# cryptographic — "the same name lands on the same number" is the whole spec.
hash_port() { printf '%s' "$1" | cksum | cut -d' ' -f1; }

# /dev/tcp rather than `nc`: this is bash already, so the probe costs no process
# and cannot be defeated by a PATH that has no netcat on it.
port_free() { ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

if [ -n "${HAUS_PORTLESS_PORT:-}" ]; then
  port=$HAUS_PORTLESS_PORT
else
  port=$((lane_base + $(hash_port "$name") % lane_span))
  tries=0
  while ! port_free "$port"; do
    port=$((lane_base + (port - lane_base + 1) % lane_span))
    tries=$((tries + 1))
    [ "$tries" -lt "$lane_span" ] ||
      die "no free port in ${lane_base}-$((lane_base + lane_span - 1))"
  done
fi

# ── the short name ───────────────────────────────────────────────────────────
# --force, because the lane's own alias from a previous run is exactly what we
# expect to find and exactly what we mean to replace. Best-effort: a failure here
# costs the pretty name, and losing the pretty name must not cost you the server.
"$portless" alias "$name" "$port" --force >/dev/null 2>&1 ||
  printf 'portless-lane: could not register %s (the branch-prefixed name still works)\n' "$name.localhost" >&2

printf 'portless-lane: %s -> :%s\n' "$name.localhost" "$port" >&2

# NOT exec, which is the whole reason this script outlives the command it runs:
# an alias is a STATIC route and portless never reaps it, so exec'ing away would
# leave one dead entry in routes.json per lane name ever used, forever.
#
# Backgrounded and `wait`ed rather than run in the foreground, which is the part
# that took a measurement to get right: bash defers a trap until the CURRENT
# command finishes, so with the dev server in the foreground a TERM to this
# script does nothing until the server exits on its own — the alias outlived the
# lane exactly as if there were no trap at all. `wait` is interruptible, so the
# handler runs the moment the signal lands; it forwards the signal on and waits
# again, and the alias goes when the server does. The exit status stays the dev
# server's.
"$portless" run --app-port "$port" "$@" &
child=$!

# Inlined rather than a helper: a function reached only from a trap string looks
# uncalled to shellcheck (SC2329), and writeShellApplication runs shellcheck.
trap 'kill -TERM "$child" 2>/dev/null || true' TERM
trap 'kill -INT "$child" 2>/dev/null || true' INT

status=0
wait "$child" || status=$?
# A second wait: the first returns as soon as the signal is handled, while the
# child is still shutting down. Without it the alias can go before the server it
# points at, and a request in that window reaches the proxy with nowhere to go.
wait "$child" 2>/dev/null || true

"$portless" alias --remove "$name" >/dev/null 2>&1 || true
exit "$status"

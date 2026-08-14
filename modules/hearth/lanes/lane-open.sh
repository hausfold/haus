#!/bin/bash
# lane-open.sh — holt's `open`/`resume` seam, backed by zmx + a Ghostty window.
#
# This is the zmx half of `haus.hearth.lanes.backend`. With the zellij backend
# (the default) holt keeps its built-in behaviour: it execs the client in the
# pane you ran it from, and the pane IS the lane. Here the pane is gone and
# three things carry a lane instead, all named the same:
#
#   zmx session   holt.<repo>.<lane>   the PTY the client actually runs in
#   Ghostty       --title=<same>       a window looking at that PTY
#   AeroSpace     window-title-regex   a tile, placed by on-window-detected
#
# One name across all three is the whole point. Everything the rice does to a
# lane from outside — the bar's go-to, a peek, "which window is this branch" —
# used to be a join across a zellij session id, a pane id, a checkout path and
# an AeroSpace window title, with a /tmp file per pane to glue them (see
# modules/sill/sketchybar/plugins/agents.sh). With this backend it's a string
# equality.
#
# ── why the window is not the session ────────────────────────────────────────
# A zellij pane dies with its tab, so closing one had to mean parking the work.
# A zmx session outlives every client attached to it, so ⌘W closes the WINDOW
# and the agent keeps thinking. That falls out of the design rather than being
# implemented here: this script only ever runs `zmx attach`, which creates the
# session on first call and re-attaches on every call after. `holt <name>` on a
# lane whose session is still up therefore reopens a window onto a live
# conversation instead of resuming a transcript — no client-side --continue, no
# session picker, nothing to resolve.
#
# ── the seam contract ────────────────────────────────────────────────────────
# holt hands action seams their situation as HOLT_* in the environment ONLY —
# stdin is inherited from the caller, not JSON (internal/config/config.go's
# `run`, `action == true`). The two that matter:
#
#   HOLT_COMMAND  the exact client invocation holt was about to exec, already
#                 resolved to continue-the-newest or open-the-picker. Run it;
#                 don't rebuild it, or a `holt <name> --pick` lands on the
#                 picker holt just resolved away.
#   HOLT_CHAT     the cwd the CONVERSATION lives in, which for a `holt child`
#                 lane is the PARENT's checkout, not the lane's. Getting this
#                 wrong is how a resumed child opens an empty session.
#
# Exit 0 = handled. Exit 3 = no opinion, use the built-in — which is what a
# machine without zmx wants, so it stays exactly as good as it was before.
set -u

# A hook is exec'd by holt, which may itself have been started by launchd (the
# palette's Spawn Agent) with a bare PATH. Resolve our tools the way every
# other rice script run from outside a shell does.
export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

command -v zmx >/dev/null 2>&1 || exit 3
[ -n "${HOLT_COMMAND:-}" ] || exit 3
[ -n "${HOLT_NAME:-}" ] || exit 3

chat="${HOLT_CHAT:-${HOLT_PATH:-}}"
[ -d "$chat" ] || exit 3

# ── the name ─────────────────────────────────────────────────────────────────
# NOT bare $HOLT_NAME. `holt child` names a child lane after the parent pane's
# own lane, so one agent that spawned an out-of-repo worktree owns two lanes
# with the SAME name in different repos — the exact ambiguity that forced
# agents.sh to keep a `.cwd` sibling file per pane just to tell them apart.
# Qualifying by the main checkout's basename makes the session name unique by
# construction, so nothing downstream needs a tiebreaker.
#
# HOLT_MAIN, not HOLT_REPO: the latter is a remote slug and is empty for a repo
# that has never been pushed, which is a perfectly ordinary lane.
repo="$(basename "${HOLT_MAIN:-$chat}")"
sess="holt.${repo}.${HOLT_NAME}"

# ── the launcher ─────────────────────────────────────────────────────────────
# Ghostty's `initial-command` is split shell-style, so passing an already-quoted
# `zmx attach … bash -lc '…'` through `open --args` means three levels of
# quoting over a $HOLT_COMMAND we don't control. A throwaway script is one
# level, and deletes itself the moment it has run.
run_dir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/nebelhaus-lanes"
mkdir -p "$run_dir" 2>/dev/null || exit 3
launcher="$(mktemp "$run_dir/open.XXXXXX")" || exit 3

# printf %q, not bash 5's ${var@Q}: /bin/bash on macOS is still 3.2, and this
# script has no guarantee about which bash holt found first.
#
# The self-tile block is lifted from zellij/launch.sh, for the reason its own
# comment gives: prowl floats every ghostty window spawned at runtime, because
# an `on-window-detected` TITLE rule races window detection (the AX title lands
# after the window is mapped) and a popup tiled for a beat reflows the whole
# workspace. From inside the window that race is gone — it certainly exists, and
# it has focus, because it was just opened. So a lane tiles ITSELF onto T rather
# than adding a title rule to aerospace.toml that would lose the same race.
{
  printf '#!/bin/bash\n'
  printf 'rm -f %q\n' "$launcher"
  printf 'export PATH="/opt/homebrew/bin:$PATH"\n'
  printf '(\n'
  printf '  for _ in $(seq 1 20); do\n'
  printf '    WID=$(aerospace list-windows --focused --format "%%{window-id}" 2>/dev/null)\n'
  printf '    [ -n "$WID" ] && break\n'
  printf '    sleep 0.05\n'
  printf '  done\n'
  printf '  [ -n "${WID:-}" ] || exit 0\n'
  printf '  aerospace move-node-to-workspace --window-id "$WID" T\n'
  printf '  aerospace layout --window-id "$WID" tiling\n'
  printf ') >/dev/null 2>&1 &\n'
  printf 'cd %q || exit 1\n' "$chat"
  # `zmx attach` creates the session if it is not there and ignores the trailing
  # command if it is — so open and resume are the same call, and a resume can
  # never restart a client that is already running.
  printf 'exec zmx attach %q bash -lc %q\n' "$sess" "$HOLT_COMMAND"
} >"$launcher"
chmod +x "$launcher"

# ── the window ───────────────────────────────────────────────────────────────
# `--title` is a FORCED title in Ghostty, not a starting value: the client
# inside can't clobber it with OSC 2. Nothing in the rice depends on that yet —
# the window places itself, above — but it is what lets anything outside find
# this lane later (`aerospace list-windows | grep '^holt\.'`) without the
# per-pane state files the bar keeps today.
#
# `open -na` rather than `ghostty +new-window`, which refuses on macOS
# ("+new-window is not supported on this platform").
pgrep -x Ghostty >/dev/null 2>&1 || open -a Ghostty
open -na Ghostty.app --args \
  --title="$sess" \
  --initial-command="$launcher" || exit 3

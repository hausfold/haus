#!/bin/bash
# new-window.sh — the ONE way this room opens a TILED Ghostty window running
# something. The floating counterpart is float-term.sh's `spawn`; the split is
# by intent, not by mechanism: a peek panel or a rebuild log is summoned OVER
# your work and floats, an editor or an ssh session joins the tiling.
#
# Usage:
#   new-window.sh [--cwd DIR] [--env K=V]… [--] [COMMAND ARG…]
#
# With no COMMAND the window gets a login shell in DIR — which is what the
# window's own launcher would have given it anyway, minus the zmx session (a
# window opened to run one command has nothing worth reattaching to).
#
# ── why AppleScript and not `open -na` ───────────────────────────────────────
# 252 ms into the running instance vs 366 ms and a whole second Ghostty process
# per window (measured 2026-08-16, notes/zellij-exit.md). More importantly a
# `surface configuration` record carries `initial working directory`, `command`
# and `environment variables` natively, and `open --args` carries none of them
# without a temp launcher script and three levels of quoting.
#
# The one caller that must NOT use this is lanes/lane-open.sh: a lane is found
# by its window TITLE, and only `open -na --title` forces a title the client
# inside can't clobber with OSC 2. Nothing here carries a name anything joins
# on, so nothing here pays for that.
#
# ── why the tile poll ────────────────────────────────────────────────────────
# windows/aerospace.toml floats every runtime-spawned Ghostty window, because an
# `on-window-detected` title rule races window detection (the AX title lands
# after the window is mapped) and a popup tiled for a beat reflows the whole
# workspace. So a window that WANTS tiling asks for it by hand, once it has
# focus. Same poll as lane-open.sh's self-tile, run from outside the window:
# wait for focus to land on a different window id than the one we started from.
set -u

export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

cwd=""
envs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --cwd) cwd="$2"; shift 2 ;;
    --env) envs+=("$2"); shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done

[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$HOME"

# An explicit login shell, NOT the ghostty-config default command: that default
# is scripts/launch.sh, which would claim a `term.<n>` zmx session for a window
# whose whole life is one command.
shell="${SHELL:-/bin/zsh}"
if [ $# -gt 0 ]; then
  # `command` in a surface configuration is a shell-style STRING that Ghostty
  # splits, so each argument has to be quoted back into one.
  #
  # Single quotes, hand-rolled, rather than `printf %q`. %q escapes with
  # BACKSLASHES outside any quotes (`a\ b`, `\$1`, `\;`), which assumes
  # Ghostty's splitter implements backslash escaping — an assumption nothing
  # here can check, and one that fails silently and confusingly (the window
  # opens, running not-quite-your-command). Single quotes only assume it
  # implements quotes, which any splitter worth the name does. An embedded
  # single quote closes, adds a double-quoted one, and reopens — `'"'"'` — so
  # even that case needs no backslash.
  #
  # The pattern and the replacement come from VARIABLES rather than being
  # written inline, and that is not style: `${a//\'/…}` puts backslashes in the
  # replacement, and bash keeps them literally — the round trip produced
  # `'it\'"\'"\'s'`, which is a syntax error rather than a string. From
  # variables there are no backslashes to survive.
  sq="'"
  esc="'\"'\"'"
  cmd=""
  for a in "$@"; do
    cmd="$cmd$sq${a//$sq/$esc}$sq "
  done
else
  cmd="$shell --login"
fi

# AppleScript string literals escape backslash and double-quote and nothing
# else, and every value below is attacker-adjacent (a filename from a click, an
# ssh host from the palette). Build the record by hand rather than through
# `on run argv`, because the environment-variables list has no argv shape.
osa_str() {
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//\"/\\\"}"
  printf '"%s"' "$v"
}

env_list=""
if [ "${#envs[@]}" -gt 0 ]; then
  for e in "${envs[@]}"; do
    [ -n "$env_list" ] && env_list="$env_list, "
    env_list="$env_list$(osa_str "$e")"
  done
  env_list=", environment variables:{$env_list}"
fi

# The window AeroSpace sees before this one, so the poll below can tell the new
# window from the one we were called from (both are Ghostty).
before="$(aerospace list-windows --focused --format '%{window-id}' 2>/dev/null)"

# Cold start: `open -a` returns as soon as LaunchServices accepts, and asking a
# not-yet-running Ghostty for a window over Apple Events just fails.
if ! pgrep -x Ghostty >/dev/null 2>&1; then
  open -a Ghostty
  for _ in $(seq 1 40); do
    pgrep -x Ghostty >/dev/null 2>&1 && break
    sleep 0.05
  done
fi

if ! osascript -e "tell application \"Ghostty\" to new window with configuration {initial working directory:$(osa_str "$cwd"), command:$(osa_str "$cmd")$env_list}" >/dev/null 2>&1; then
  # Failing silently is the one sin a chord can't afford, and the classic cause
  # is the Automation (Apple Events) grant rather than anything in the command:
  # System Settings → Privacy & Security → Automation → <the caller> → Ghostty.
  osascript -e 'display notification "couldn'"'"'t ask Ghostty for a window — check Privacy & Security → Automation." with title "haus · new window"' >/dev/null 2>&1
  exit 1
fi

osascript -e 'tell application "Ghostty" to activate' >/dev/null 2>&1

for _ in $(seq 1 20); do
  wid="$(aerospace list-windows --focused --format '%{window-id}' 2>/dev/null)"
  [ -n "$wid" ] && [ "$wid" != "$before" ] && break
  sleep 0.05
done
[ -n "${wid:-}" ] && [ "$wid" != "$before" ] &&
  aerospace layout --window-id "$wid" tiling >/dev/null 2>&1

exit 0

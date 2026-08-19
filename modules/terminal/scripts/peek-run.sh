#!/bin/bash
# peek-run.sh — runs INSIDE the peek ghostty instance (spawned by peek.sh).
#
# Single-shot: run yazi once against the passed cwd, and when yazi quits
# (q/Esc) exit so Ghostty closes the window (wait-after-command defaults off).
# No persistence, no fifo — each ⌘Y spawns a fresh instance and this script is
# its whole life. If Enter picks a directory (peek-open.yazi), open it as a new
# tiled Ghostty window before exiting.

set -u
export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"

# macOS `open` forwards the caller's environment, so the summoning window's zmx
# session leaks in here. Scrub it: this window is its own process, and a stray
# $ZMX_SESSION would make an agent hook fired from inside peek report against
# the session that summoned it.
unset ZMX_SESSION

# PEEK=1 tells the peek-open yazi plugin (Enter) it's running inside peek, so a
# directory picks → new window instead of yazi's default open. Unset everywhere
# else, so a plain `yy` session keeps the default Enter.
export PEEK=1

# --stay: peek.sh forwards its own ⌘⇧Y flag here so the Enter-on-dir window
# inherits the same intent. Without it, a window spawned from a stayed peek
# would land in the worktree and then have terminal's zshrc hop it straight out
# to the main checkout at shell birth — undoing the one thing --stay is for.
STAY=0
[ "${1:-}" = "--stay" ] && STAY=1

CWDFILE="$HOME/.cache/peek.cwd"

dir="$PWD"
[ -d "$dir" ] || dir="$HOME"
# Clear any prior pick so only THIS session's Enter-on-dir counts.
rm -f "$CWDFILE"
yazi "$dir"
# Enter on a directory (peek-open.yazi) drops its path here and quits yazi.
picked=$(cat "$CWDFILE" 2>/dev/null); rm -f "$CWDFILE"
if [ -n "$picked" ] && [ -d "$picked" ]; then
  # No session to target and no layout to clone — the whole spawn_tab
  # apparatus this replaced (a KDL-escaped copy of custom.kdl with a
  # tab-level cwd injected, because `new-tab --cwd` was silently ignored
  # under a default_tab_template) collapses into one call.
  if [ "$STAY" = 1 ]; then
    "$HOME/.config/haus/term/new-window.sh" --cwd "$picked" --env HAUS_STAY=1
  else
    "$HOME/.config/haus/term/new-window.sh" --cwd "$picked"
  fi
fi
# Falling off the end exits the --command process; Ghostty closes the window.

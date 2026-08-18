#!/bin/bash
# lane-spawn.sh — "start an agent here", bound at the WINDOW layer.
#
# This is the other half of the lane chord ⌃⌘A. lane-open.sh
# answers holt's open/resume seam (what a lane looks like once it exists); this
# answers the chord (which repo a new lane is FOR).
#
# ── why this is not a zellij bind ────────────────────────────────────────────
# ⌘A used to be `bind "Super a" { Run … }` in config.kdl, and zellij's only way
# to run a command IS to open a pane for it. Under the zellij backend that pane
# was the lane, so it cost nothing. Under zmx the lane is a window, and `holt
# new` returns in well under a second — so the pane appeared, flashed, and
# close_on_exit tore it down again. That flash isn't a bug in the pane, it is
# the pane being the wrong mechanism.
#
# It also couldn't reach half the machine. ⌘A arrives at zellij only because
# ghostty/config unbinds cmd+a and lets it fall through to the terminal app; a
# zmx lane window has no zellij in it, so the chord did nothing there — you
# could start an agent from a zellij pane and from nowhere else. Ghostty can't
# take over either: `ghostty +list-actions` on 1.3.1 has 85 actions and not one
# of them runs a command.
#
# So the chord belongs to the only layer that sees every window: AeroSpace,
# which already owns the global chord table (modules/windows/wm-bindings.nix)
# and already tiles these windows. Same conclusion notes/zellij-exit.md reached
# for the whole keymap — "chords move to AeroSpace, not to Ghostty" — arrived at
# early, for the one chord that needed it first.
#
# ── the cost of that: no cwd ─────────────────────────────────────────────────
# A zellij bind inherited the focused pane's directory for free. A window-layer
# chord has to ask; lane-cwd.sh (extracted so ⌘P's shell-here shares it) reads
# the focused window's title and asks zmx or zellij, whichever is behind it.
# Anything else — a browser, Finder, a plain shell — has no repo to speak of and
# falls back, because "⌃⌘A from anywhere" is worth more than a refusal.
set -u

# Bound through AeroSpace's exec-and-forget, which runs with a bare environment.
# Same prelude as lane-open.sh, for the same reason.
export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

# ── saying no out loud ───────────────────────────────────────────────────────
# This runs under AeroSpace's exec-and-forget: no terminal, no stdout anyone
# will ever see. So `holt new` refusing ("not inside a git repo") is invisible,
# and a global chord that silently does nothing is worse than one that isn't
# bound — you press it again, harder, and conclude the rebuild didn't land.
# Everything below that gives up says so on screen first.
say() { osascript -e "display notification \"$1\" with title \"haus · agent lane\"" >/dev/null 2>&1; }

# Where a chord pressed over a browser puts you. It only helps if it happens to
# be a repo; when it isn't, `refuse` is what the user actually gets.
fallback="${HAUS_LANE_FALLBACK:-$HOME}"

command -v holt >/dev/null 2>&1 || {
  say "holt isn't on PATH — nothing to spawn a lane with."
  exit 0
}

cwd="$("$(dirname "$0")/lane-cwd.sh")"
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$fallback"

cd "$cwd" || {
  say "couldn't enter $cwd."
  exit 0
}

# `holt new` needs a repo, and refuses without one — to a terminal that isn't
# there. Ask the same question here, where the answer can still be shown. The
# check is git's own rather than a .git test, so a worktree, a submodule and a
# plain checkout all pass exactly as holt would judge them.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  say "$(basename "$cwd") isn't a git repo — focus a window in one, then press ⌃⌘A."
  exit 0
fi

exec holt new

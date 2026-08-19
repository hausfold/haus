#!/bin/bash
# peek.sh — ⌘Y / ⌘⇧Y: summon the floating yazi "peek" panel, rooted at the
# focused window's cwd.
#
#   peek.sh          ⌘Y  — hop out of an agent worktree to the repo's main
#                          checkout (the ⌘N convention)
#   peek.sh --stay   ⌘⇧Y — stay exactly where the window is, worktree or not
#                          (the ⌘⇧N convention)
#
# A separate, FLOATING Ghostty instance rather than a tiled one: peek is
# summoned over your work and dismissed, so it covers the window that called it
# and takes nothing away when it goes. (It was a separate instance under zellij
# too, for a reason that has since become the whole architecture: zellij's VTE
# parser strips kitty-graphics APC sequences, so yazi inside it could only draw
# chafa block art. Nothing strips them now.)
#
# Spawn model: this fires ONE fresh, centered Ghostty instance per summon via
# the shared float-term helper — the same "spawn → PID-diff → AppleScript
# settle → aerospace-float" dance the Rebuild System pounce command uses. yazi
# runs inside it; when yazi quits (q/Esc), peek-run.sh exits, and Ghostty
# closes the window (wait-after-command defaults off). No background window,
# no fifo, no offscreen parking — the panel exists only while it's on screen.
#
# Trade-off vs the old persistent-window design: each summon pays a cold spawn
# (a new Ghostty instance launch) instead of teleporting a parked one, so the
# panel appears a touch slower and may briefly flash at its saved frame before
# the AppleScript settle re-centers it — identical to how Rebuild System pops
# in. In exchange there's no lingering hidden instance to babysit.

set -u
export PATH="/opt/homebrew/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"

FLOAT_TERM="$HOME/.config/haus/term/float-term.sh"
WINDOW_TITLE="quick-terminal-peek"

# --stay (⌘⇧Y) is the no-hop sibling of the plain chord, exactly as ⌘⇧N is to
# ⌘N: sometimes you DO want to browse the agent's throwaway checkout rather than
# the repo it branched from. It rides through to peek-run.sh as well, so an
# Enter-on-a-directory WINDOW opened from a stayed peek doesn't hop back out of
# the worktree the moment its shell starts.
STAY=0
STAY_ARG=""
if [ "${1:-}" = "--stay" ]; then
    STAY=1
    STAY_ARG=" --stay"
fi

# WHERE peek starts. Under zellij this was `$PWD`, because the bind ran inside
# the pane and inherited its directory for free. The chord fires from the pounce
# daemon now, whose cwd is whatever launchd gave it — so ask, the same way every
# other window-layer chord does (⌘N's shell-here.sh, ⌘↵'s lane-spawn.sh, ⌘B).
# $PWD stays as the fallback: lane-cwd.sh is only installed when the agent
# clients are on, and a peek rooted at the daemon's cwd still beats no peek.
START=""
[ -x "$HOME/.config/haus/lanes/lane-cwd.sh" ] && START="$("$HOME/.config/haus/lanes/lane-cwd.sh")"
[ -n "$START" ] && [ -d "$START" ] || START="$PWD"

# Root peek at the REAL repo, not a throwaway worktree checkout: if the
# summoning window sits inside a linked git worktree (its per-worktree gitdir
# differs from the shared common dir), start yazi at the repo's MAIN worktree —
# the first entry of `git worktree list` — so peek always opens you in the
# canonical repo. A normal checkout (gitdir == common dir), a non-repo cwd, or
# --stay all fall through unchanged.
if [ "$STAY" = 0 ]; then
    _gd="$(git -C "$START" rev-parse --path-format=absolute --git-dir 2>/dev/null)"
    _gcd="$(git -C "$START" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
    if [ -n "$_gd" ] && [ "$_gd" != "$_gcd" ]; then
        _main="$(git -C "$START" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
        [ -n "$_main" ] && [ -d "$_main" ] && START="$_main"
    fi
fi

# Spawn a Ghostty running peek-run.sh, sized and placed to COVER THE SUMMONING
# WINDOW exactly: --match-frontmost hands float-term the frame of the window
# that's on top at this instant — the Ghostty window whose ⌘Y ran us — so
# peek reads as that terminal switching into a file browser rather than as a
# popup landing somewhere over it. (It used to take a centered 80% of the
# cursor's screen, which on a tiled half-width window sat crooked and spilled
# past the edges; float-term still falls back to that if the frame is
# unreadable.) --pin lands it on the current workspace and force-floats it.
# cwd rides in on --working-directory (an EXTRA ghostty flag after `--`).
"$FLOAT_TERM" spawn \
    --title "$WINDOW_TITLE" \
    --match-frontmost \
    --pin \
    --command "/bin/bash $HOME/.config/haus/term/peek-run.sh$STAY_ARG" \
    -- --working-directory="$START" >/dev/null

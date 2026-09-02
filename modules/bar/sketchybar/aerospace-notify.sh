#!/bin/bash
# aerospace-notify.sh [fullscreen|tiling]
#
# AeroSpace's hooks into the bar. No argument is the workspace-change hook
# (exec-on-workspace-change in aerospace.toml); `fullscreen` is the <mod>f
# binding's second command; `tiling` is what windows/scripts/tiling-mode.sh
# calls on its way out, so the tiling pill repaints on the leader→. press
# rather than up to 2 s later on aerospace_watcher.sh's own tick.
#
# Both live here rather than as `exec-and-forget sketchybar --trigger …` lines
# in aerospace.toml so that the path to the MENU bar's sketchybar — and
# specifically the top bar's mach service — is written in the bar's own tree and
# nowhere in the windows room.

# bar.sh is that path, GENERATED from haus.roster.sketchybar.binPath — so the
# top bar's binary is named once, where the roster's `scope` decided it, and
# never spelled here. It used to be written out three times in this file alone,
# and the count grew by one in haus#484 without anybody noticing (§5.4).
# Sourced up front because the two top-bar-only arms below need $BAR_TOP, and
# because the guard beneath this is what makes "no bar deployed" one exit
# rather than a test in every branch.
if [ -r "$HOME/.config/sketchybar/bar.sh" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.config/sketchybar/bar.sh"
fi
# No bar deployed (or a generation mid-switch): nothing to trigger, and the tour
# hook at the bottom is a bar item too. Exit quietly rather than run a path that
# is not there.
[ -x "${BAR_TOP:-}" ] || exit 0

if [ "$1" = fullscreen ]; then
    # Repaint on the keypress rather than up to 2s later on the watcher's next
    # poll. The watcher is what reads the new state and paints both pills; this
    # only wakes it. See plugins/aerospace_lib.sh.
    "$BAR_TOP" --trigger aerospace_fullscreen_change
    exit 0
fi

if [ "$1" = tiling ]; then
    # Wakes the watcher, which reads the mode file and paints the pill — the
    # same division of labour as `fullscreen` above.
    "$BAR_TOP" --trigger aerospace_tiling_change
    exit 0
fi

# BOTH instances, and the one arm of this file that is: the SECOND bar is a
# separate SketchyBar instance with its own mach service, so a `$BAR_TOP`
# trigger never reaches it — a pill placed there (the `page` one) would only
# ever repaint on its own tick, which for a hidden item is never.
#
# `haus-bar-poke` is where that pair lives, for every producer on the machine
# (modules/core/haus-bar-poke.sh). Absolute, because this script is spawned by
# AeroSpace and by the leader-mode scripts, on a PATH that names nothing of
# ours — the same reason barlib.sh addresses `barpop` that way. It resolves
# both bar binaries itself, which is why the `$BAR_BOTTOM` that used to be
# read here is gone; `$BAR_TOP` stays for the two arms above, which are NOT
# this shape.
/run/current-system/sw/bin/haus-bar-poke aerospace_workspace_change
# Haus-tour hook — one stat when no tour is mid-flight (plugins/tour.sh).
{ [ -f "$HOME/.local/state/haus/tour" ] && "$HOME/.config/sketchybar/plugins/tour.sh" event workspace; } >/dev/null 2>&1 &

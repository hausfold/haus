#!/bin/bash

# Batch-update every workspace indicator in one pass — the ONE painter of the
# workspace pills. What each pill says is plugins/workspace_lib.sh's; this is
# when it is said.
#
# It used to share the job with plugins/space.sh, run once PER PILL on every
# workspace change — eleven processes and twenty-two `aerospace` calls for one
# keypress, painting the same answer this batch paints two seconds later. And
# because a hidden pill never hears an event (the bar's `updates=when_shown`),
# a workspace that gained its first window without being switched to — a
# window thrown there with ⌥⇧ — only ever lit up on this loop's tick anyway.
# So the workspace-change event comes HERE now, and so does
# space_windows_change (a window opened or closed), which is what makes the
# window pips on a pill move when the window does rather than a tick later.
#
# The roster comes from the generated workspaces.sh — the SAME WORKSPACES array
# sketchybarrc adds the pills from, so this loop cannot cover a different set
# than the one on screen.
#
# It is also the sole writer of the FULLSCREEN state (plugins/aerospace_lib.sh)
# — the glyph on the front-app pill and the focused workspace pill's peach fill,
# both appended to the same batch this already sends. Sole writer on purpose:
# front_app.sh is subscribed to the same front_app_switched this is, but
# routing the fullscreen repaint through it would hang the state on an event
# that does not always fire for it (the poll note below), and split one
# sketchybar batch into two. Here it costs one more `aerospace` call per tick
# and no extra sketchybar call at all.
#
# The <mod>f binding fires aerospace_fullscreen_change (see
# ../aerospace-notify.sh) so the paint lands on the keypress rather than up to
# 2 s later. The poll stays because that event is not the only route into the
# state: focusing another window OF THE SAME APP changes which window's
# fullscreen flag we're reading and fires no front_app_switched at all.
#
# The TILING pill rides here on the same terms — one more `aerospace` call per
# tick, no extra sketchybar call — and for the same reason the fullscreen state
# does: its other input is how many tiled windows the focused workspace holds.
# leader→. fires aerospace_tiling_change (again through ../aerospace-notify.sh)
# so a mode change lands on the keypress; the count follows space_windows_change.
#
# And the BURIED pill (workspace_lib.sh's ws_buried_args) rides here for the
# same reason as both: a floating window sinks when you click something else,
# which is a front_app_switched, and surfaces when you focus it, which is one
# too. Clicking a second window of the SAME app fires nothing, and the tick is
# what covers that.

# $BAR_TOP — GENERATED from haus.roster.sketchybar.binPath. Everything this loop
# paints is a menu-bar item, so it is always the TOP bar's mach service (§5.4).
source "$HOME/.config/sketchybar/bar.sh"
source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/sizes.sh"
source "$HOME/.config/sketchybar/workspaces.sh"
source "$HOME/.config/sketchybar/plugins/aerospace_lib.sh"
source "$HOME/.config/sketchybar/plugins/workspace_lib.sh"
# $BAR_TILING / $BAR_BURIED — GENERATED from haus.windows.enable (and, for the
# second, haus.bar.workspaces.buried), the same switches that decide whether
# sketchybarrc adds the `tiling` and `buried` items at all. Read here for the
# reason launch_mode.sh reads $BAR_PAGES: this paints in ONE batch, and a
# `--set` naming an item that was never added takes the whole batch down with
# it.
source "$HOME/.config/sketchybar/windows_config.sh"

# The leader has the left side swapped out for its picker: the pills are frozen
# and hidden, and a paint now would put them back over it. launch_mode.sh
# freezes this item too, but a trigger (space_windows_change above all) can
# still reach it through the freeze; the snapshot file is launch_mode's own
# "I am armed", the same one plugins/logo.sh reads.
[ -f /tmp/sketchybar_launch_logo.json ] && exit 0

ws_snapshot
ACTIVE_COLOR=$(fullscreen_active_ws_color "$WS_FULLSCREEN")

WS_ARGS=()
ws_pills_args "$ACTIVE_COLOR"

# Unquoted on purpose — the helper echoes space-separated `key=value` words with
# no spaces inside any value, and each has to reach sketchybar as its own arg.
WS_ARGS+=(--set front_app $(fullscreen_front_app_args "$WS_FULLSCREEN"))
[ "${BAR_TILING:-0}" = 1 ] && WS_ARGS+=(--set tiling $(aerospace_tiling_args "$WS_FOCUSED"))
[ "${BAR_BURIED:-0}" = 1 ] && ws_buried_args

# Asked again at the last moment: the snapshot above is five `aerospace` calls,
# and a caps tap landing inside them would otherwise have this paint the pills
# back over the picker it just drew.
[ -f /tmp/sketchybar_launch_logo.json ] && exit 0
"$BAR_TOP" "${WS_ARGS[@]}"

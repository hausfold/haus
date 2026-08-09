#!/bin/bash

# Auto-position hook for haus.sill.position = "auto". Subscribed to
# display_change + system_woke in sketchybarrc (added only in auto mode), so it
# fires whenever a display attaches/detaches or the machine wakes. bar_position()
# lives in the GENERATED position.sh: it echoes `bottom` when an external display
# is attached, `top` on the built-in alone. Re-asserting the same position is
# harmless, so there's no need to diff the current one.
#
# topmost travels WITH the position — a bar that lands at the bottom has to
# outrank the tiled window above it or that window's shadow paints over the
# strip (bar_topmost() in position.sh has the full story). Leave it out here and
# an undock would move the bar back to the top while the level stayed floating.
# bar_position() is resolved once and handed on: in auto mode it costs ~1s.
source "$HOME/.config/sketchybar/position.sh"

pos="$(bar_position)"
sketchybar --bar position="$pos" topmost="$(bar_topmost "$pos")"

#!/bin/bash

# Auto-position hook for nebelhaus.sill.position = "auto". Subscribed to
# display_change + system_woke in sketchybarrc (added only in auto mode), so it
# fires whenever a display attaches/detaches or the machine wakes. bar_position()
# lives in the GENERATED position.sh: it echoes `bottom` when an external display
# is attached, `top` on the built-in alone. Re-asserting the same position is
# harmless, so there's no need to diff the current one.
source "$HOME/.config/sketchybar/position.sh"

sketchybar --bar position="$(bar_position)"

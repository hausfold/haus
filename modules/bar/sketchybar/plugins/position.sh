#!/bin/bash

# Auto-position hook for haus.bar.position = "auto". Subscribed to
# display_change + system_woke in sketchybarrc (added only in auto mode), so it
# fires whenever a display attaches/detaches or the machine wakes. bar_position()
# lives in the GENERATED position.sh: it echoes `bottom` when an external display
# is attached, `top` on the built-in alone. Re-asserting the same position is
# harmless, so there's no need to diff the current one.
#
# Position ONLY — deliberately not topmost. bar_topmost() answers from the mode
# rather than the resolved position, and in `auto` (the only mode this hook runs
# in) that answer is a constant, so there is nothing here to re-send. Just as
# well: unlike bar_manager_set_position, bar_manager_set_topmost has no
# unchanged-guard and calls bar_manager_reset() every time, which would turn
# each wake and each dock/undock into a full teardown-and-rebuild of every bar
# and item window. See bar_topmost() in the generated position.sh.
source "$HOME/.config/sketchybar/position.sh"

sketchybar --bar position="$(bar_position)"

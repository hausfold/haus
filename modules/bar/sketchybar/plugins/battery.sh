#!/bin/bash
# battery.sh — the battery pill (hausfold.co/docs/haus/rooms/bar-widgets).
# The header carries the interval and the one builtin event this pill cares
# about; identity (icon padding, colour keys) has no rung of its own and
# stays in the Nix style.
# widget: interval   = 30
# widget: subscribes = power_source_change

BAR_ITEM=battery
source "$HOME/.config/sketchybar/barlib.sh"
[ -f "$HOME/.config/sketchybar/battery_config.sh" ] && source "$HOME/.config/sketchybar/battery_config.sh"

fetch() {
    local info percentage charging=0
    info=$(pmset -g batt)
    percentage=$(echo "$info" | grep -Eo '[0-9]+%' | cut -d% -f1)
    echo "$info" | grep -q 'AC Power' && charging=1
    emit percentage="${percentage:-0}" charging="$charging"
}

# Over BAR_BATTERY_HIDE_OVER the pill has nothing worth a glance, and
# `pill --hide` is the door that keeps hearing the tick so it can come back
# the moment the charge drops again — see AGENTS.md's box on updates=on.
render() {
    if [ -n "${BAR_BATTERY_HIDE_OVER:-}" ] && [ "$percentage" -gt "$BAR_BATTERY_HIDE_OVER" ]; then
        pill --hide
        return 0
    fi
    local icon tone
    if [ "$charging" = 1 ]; then
        icon="󰂄"; tone=ok
    elif [ "$percentage" -gt 80 ]; then icon="󰁹"; tone=ok
    elif [ "$percentage" -gt 60 ]; then icon="󰂀"; tone=ok
    elif [ "$percentage" -gt 40 ]; then icon="󰁿"; tone=watch
    elif [ "$percentage" -gt 20 ]; then icon="󰁼"; tone=watch
    else icon="󰁺"; tone=bad
    fi
    pill --icon "$icon" --label "${percentage}%" --tone "$tone"
}

on_click() {
    open -a 'System Settings' 'x-apple.systempreferences:com.apple.preference.battery'
}

barlib_main "$@"

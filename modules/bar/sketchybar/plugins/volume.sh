#!/bin/bash
# volume.sh — the output-volume pill (hausfold.co/docs/haus/rooms/bar-widgets).
# widget: interval = 5

BAR_ITEM=volume
source "$HOME/.config/sketchybar/barlib.sh"

fetch() {
    local vol muted
    vol=$(osascript -e 'output volume of (get volume settings)')
    muted=$(osascript -e 'output muted of (get volume settings)')
    emit vol="${vol:-0}" muted="${muted:-false}"
}

render() {
    local icon label
    if [ "$muted" = "true" ]; then
        icon="󰖁"; label="Muted"
    elif [ "$vol" -gt 66 ]; then
        icon="󰕾"; label="${vol}%"
    elif [ "$vol" -gt 33 ]; then
        icon="󰖀"; label="${vol}%"
    elif [ "$vol" -gt 0 ]; then
        icon="󰕿"; label="${vol}%"
    else
        icon="󰖁"; label="0%"
    fi
    pill --icon "$icon" --label "$label"
}

on_click() {
    open -a 'System Settings' 'x-apple.systempreferences:com.apple.Sound-Settings.extension'
}

barlib_main "$@"

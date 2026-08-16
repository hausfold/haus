#!/bin/bash

[ -f "$HOME/.config/sketchybar/battery_config.sh" ] && source "$HOME/.config/sketchybar/battery_config.sh"

source "$HOME/.config/sketchybar/colors.sh"
BAR_ITEM=battery
source "$HOME/.config/sketchybar/bar.sh"

# Get battery info
BATTERY_INFO=$(pmset -g batt)
PERCENTAGE=$(echo "$BATTERY_INFO" | grep -Eo "\d+%" | cut -d% -f1)
CHARGING=$(echo "$BATTERY_INFO" | grep 'AC Power')

# Hide pill if over threshold
if [ -n "${BAR_BATTERY_HIDE_OVER:-}" ] && [ "$PERCENTAGE" -gt "$BAR_BATTERY_HIDE_OVER" ]; then
    "$SB" --set "$NAME" drawing=off
    exit 0
fi

# Determine icon and color
if [ -n "$CHARGING" ]; then
    ICON="󰂄"
    COLOR=$GREEN
else
    if [ "$PERCENTAGE" -gt 80 ]; then
        ICON="󰁹"
        COLOR=$GREEN
    elif [ "$PERCENTAGE" -gt 60 ]; then
        ICON="󰂀"
        COLOR=$GREEN
    elif [ "$PERCENTAGE" -gt 40 ]; then
        ICON="󰁿"
        COLOR=$YELLOW
    elif [ "$PERCENTAGE" -gt 20 ]; then
        ICON="󰁼"
        COLOR=$YELLOW
    else
        ICON="󰁺"
        COLOR=$RED
    fi
fi

# Update the bar item
"$SB" --set "$NAME" \
    drawing=on \
    icon="$ICON" \
    icon.color=$COLOR \
    label="${PERCENTAGE}%"

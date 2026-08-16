#!/bin/bash

source "$HOME/.config/sketchybar/colors.sh"
BAR_ITEM=wifi
source "$HOME/.config/sketchybar/bar.sh"

# Get Wi-Fi status using ipconfig (more reliable than networksetup on newer macOS)
INFO=$(ipconfig getsummary en0)
LINK_STATUS=$(echo "$INFO" | grep "LinkStatusActive" | awk -F': ' '{print $2}')
SSID=$(echo "$INFO" | grep "SSID" | awk -F': ' '{print $2}')

if [ "$LINK_STATUS" = "TRUE" ]; then
    LABEL="$SSID"
    # Fallback if SSID is redacted or missing
    if [[ "$SSID" == *"<redacted>"* ]] || [ -z "$SSID" ]; then
        LABEL="Connected"
    fi
    
    "$SB" --set "$NAME" \
        icon=󰖩 \
        label.drawing=off \
        icon.color=$TEAL
else
    "$SB" --set "$NAME" \
        icon=󰖪 \
        label.drawing=off \
        icon.color=$RED
fi

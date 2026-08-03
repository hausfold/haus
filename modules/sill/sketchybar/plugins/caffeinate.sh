#!/bin/bash
# The optional keep-awake pill. All process/state ownership lives in the
# rice-level `awake` command; this script only relays clicks and paints status.

source "$HOME/.config/sketchybar/colors.sh"

AWAKE="/run/current-system/sw/bin/awake"

if [ "${1:-}" = "custom" ]; then
    sketchybar --set caffeinate popup.drawing=off
    HOURS=$(/usr/bin/osascript -e \
        'text returned of (display dialog "Stay awake for how many whole hours?" default answer "3" with title "Keep Awake" buttons {"Cancel", "Start"} default button "Start" cancel button "Cancel")' \
        2>/dev/null) || exit 0
    if ! "$AWAKE" "${HOURS}h" >/dev/null 2>&1; then
        /usr/bin/osascript -e \
            'display notification "Use a whole number from 1 to 8760." with title "Keep Awake"' \
            >/dev/null 2>&1 || true
    fi
    exit 0
fi

if [ "${SENDER:-}" = "mouse.clicked" ]; then
    if [ "${BUTTON:-}" = "right" ]; then
        "$AWAKE" off >/dev/null 2>&1 || true
        sketchybar --set caffeinate popup.drawing=off
    else
        # Through sillpop, so the menu closes on the next click anywhere else
        # (sketchybar only ever sees clicks on its own items). Falls back to the
        # click-the-pill-again toggle if the binary isn't there.
        /run/current-system/sw/bin/sillpop toggle caffeinate 2>/dev/null ||
            sketchybar --set caffeinate popup.drawing=toggle
    fi
fi

STATUS=$("$AWAKE" status --raw 2>/dev/null || printf 'off\t0\t0\n')
IFS="$(printf '\t')" read -r MODE REMAINING _ <<EOF
$STATUS
EOF

case "$MODE" in
    indefinite)
        LABEL="∞"
        ACTIVE=1
        ;;
    timed)
        MINUTES=$(((REMAINING + 59) / 60))
        HOURS=$((MINUTES / 60))
        MINUTES=$((MINUTES % 60))
        if [ "$HOURS" -gt 0 ] && [ "$MINUTES" -gt 0 ]; then
            LABEL="${HOURS}h ${MINUTES}m"
        elif [ "$HOURS" -gt 0 ]; then
            LABEL="${HOURS}h"
        else
            LABEL="${MINUTES}m"
        fi
        ACTIVE=1
        ;;
    *)
        LABEL=""
        ACTIVE=0
        ;;
esac

if [ "$ACTIVE" -eq 1 ]; then
    # Label is drawing: tuck the icon close to it (idle padding is symmetric so
    # the lone icon stays centred; the countdown needs the tighter gap).
    sketchybar --set caffeinate \
        icon.color="$BASE" \
        icon.padding_right=4 \
        label="$LABEL" \
        label.drawing=on \
        label.color="$BASE" \
        background.color="$PEACH" \
        --set caffeinate.stop label.color="$RED"
else
    sketchybar --set caffeinate \
        icon.color="$TEXT" \
        icon.padding_right=10 \
        label.drawing=off \
        background.color="$SURFACE0" \
        --set caffeinate.stop label.color="$OVERLAY0"
fi

#!/bin/bash
# The optional keep-awake pill. All process/state ownership lives in the
# rice-level `awake` command; this script only relays clicks and paints status.

source "$HOME/.config/sketchybar/colors.sh"
# $SB — which bar this pill lives on. haus.bar.bottom.items can move it to
# the second (bottom) bar, and the two instances are addressed by different
# binaries; a bare `sketchybar` would always mean the menu bar one. bar.sh
# reads $BAR_NAME, which SketchyBar exports into everything it runs.
BAR_ITEM=caffeinate
source "$HOME/.config/sketchybar/bar.sh"


AWAKE="/run/current-system/sw/bin/awake"

if [ "${1:-}" = "custom" ]; then
    "$SB" --set caffeinate popup.drawing=off
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
        "$SB" --set caffeinate popup.drawing=off
    else
        # The toggle first and alone, so opening costs what it always did; then
        # barpop guards it in the background so the menu also closes on a click
        # anywhere else (sketchybar only ever sees clicks on its own items).
        "$SB" --set caffeinate popup.drawing=toggle
        # SKETCHYBAR_BIN is what barpop resolves its own client from: unset, it
        # queries the TOP bar, finds no such item on a pill that moved to the
        # bottom one, and exits before it ever arms — leaving a dropdown nothing
        # closes but a second click on the pill.
        SKETCHYBAR_BIN="$SB" /run/current-system/sw/bin/barpop arm caffeinate 2>/dev/null &
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
    "$SB" --set caffeinate \
        icon.color="$BASE" \
        icon.padding_right=4 \
        label="$LABEL" \
        label.drawing=on \
        label.color="$BASE" \
        background.color="$PEACH" \
        --set caffeinate.stop label.color="$RED"
else
    "$SB" --set caffeinate \
        icon.color="$TEXT" \
        icon.padding_right=10 \
        label.drawing=off \
        background.color="$SURFACE0" \
        --set caffeinate.stop label.color="$OVERLAY0"
fi

#!/bin/bash
# The optional keep-awake pill. All process/state ownership lives in the
# haus-level `awake` command; this script only relays clicks and paints status.

source "$HOME/.config/sketchybar/colors.sh"
# $SB — which bar this pill lives on. haus.bar.bottom.items can move it to
# the second (bottom) bar, and the two instances are addressed by different
# binaries; a bare `sketchybar` would always mean the menu bar one. bar.sh
# reads $BAR_NAME, which SketchyBar exports into everything it runs.
BAR_ITEM=caffeinate
source "$HOME/.config/sketchybar/bar.sh"


AWAKE="/run/current-system/sw/bin/awake"
# An agent hold, which is NOT yours: haus.ai.keepAwake's agent creates this
# while it is holding a caffeinate assertion for a coding agent that is mid-turn
# (modules/lib/state-files.nix registers the path; a rename on either side is
# invisible, hence the entry). Absent on a machine with the AI room off, with
# keepAwake off, or with nothing working right now -- all three read the same
# here, and correctly so: the question this pill answers is "is something
# keeping this Mac awake", not "could something".
#
# Only the shallow half has a file. `keepAwake = "lid"` also runs core's root
# daemon over `disablesleep`, whose receipt is /var/db/haus-lidawake.held -- but
# that stop runs the agent too, so this file is up either way and the pill never
# needs to read root's. A machine using haus.power.lidAwake DIRECTLY, with no
# keepAwake, gets no pill state: that is the power room's feature, and it has
# never had one.
HELD="$HOME/.local/state/haus/lidawake/holding"

if [ "${1:-}" = "custom" ]; then
    "$SB" --set caffeinate popup.drawing=off
    HOURS=$(/usr/bin/osascript -e \
        'text returned of (display dialog "Stay awake for how many whole hours?" default answer "3" with title "Keep Awake" buttons {"Cancel", "Start"} default button "Start" cancel button "Cancel")' \
        2>/dev/null) || exit 0
    if ! "$AWAKE" "${HOURS}h" >/dev/null 2>&1; then
        # Through haus-notify, so trill draws it when it can and `rules.json`
        # can route it. Absolute: SketchyBar runs plugins under launchd's bare
        # PATH. `|| true` — a failed banner must not fail the arm reporting a
        # failure.
        /run/current-system/sw/bin/haus-notify --source haus.bar.awake --kind fault \
            --symbol exclamationmark.triangle --title "Keep Awake" \
            --body "Use a whole number from 1 to 8760." >/dev/null 2>&1 || true
    fi
    exit 0
fi

if [ "${SENDER:-}" = "mouse.clicked" ]; then
    if [ "${BUTTON:-}" = "right" ]; then
        # Right-click means "allow sleep", and it can only ever speak for YOUR
        # assertion. An agent hold is released by the agent finishing its turn
        # and by nothing else -- so when that is the only thing holding, say so
        # instead of running a command that silently changes nothing. A control
        # that appears to do nothing is how someone concludes the pill is broken.
        if [ -e "$HELD" ] && [ "$("$AWAKE" status --raw 2>/dev/null | cut -f1)" = "off" ]; then
            /run/current-system/sw/bin/haus-notify --source haus.bar.awake --symbol robot \
                --title "Agents are holding this Mac awake" \
                --body "It releases when they stop." >/dev/null 2>&1 || true
        else
            "$AWAKE" off >/dev/null 2>&1 || true
        fi
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

# Three things can be true at once, and the pill has to distinguish them
# because they have different answers to "can I make this stop":
#
#   yours          you asked for it; right-click ends it
#   agents         nobody asked; it ends when the turn does
#   both           yours is the one you can act on, so yours takes the label
#
# The BACKGROUND says whose it is and the ICON COLOUR says whether agents are in
# it, which is what lets the two compose without a fourth combination to draw. A
# plain agent hold deliberately keeps the idle background: it is not a state you
# put the Mac in, so a pill lit up like one you chose would misreport who is
# responsible every night.
AGENTS=0
[ -e "$HELD" ] && AGENTS=1

if [ "$ACTIVE" -eq 1 ]; then
    # Label is drawing: tuck the icon close to it (idle padding is symmetric so
    # the lone icon stays centred; the countdown needs the tighter gap).
    "$SB" --set caffeinate \
        icon.color="$([ "$AGENTS" -eq 1 ] && printf '%s' "$SAPPHIRE" || printf '%s' "$BASE")" \
        icon.padding_right=4 \
        label="$LABEL" \
        label.drawing=on \
        label.color="$BASE" \
        background.color="$PEACH" \
        --set caffeinate.stop label.color="$RED"
elif [ "$AGENTS" -eq 1 ]; then
    "$SB" --set caffeinate \
        icon.color="$SAPPHIRE" \
        icon.padding_right=4 \
        label="ai" \
        label.drawing=on \
        label.color="$SAPPHIRE" \
        background.color="$SURFACE0" \
        --set caffeinate.stop label.color="$OVERLAY0"
else
    "$SB" --set caffeinate \
        icon.color="$TEXT" \
        icon.padding_right=10 \
        label.drawing=off \
        background.color="$SURFACE0" \
        --set caffeinate.stop label.color="$OVERLAY0"
fi

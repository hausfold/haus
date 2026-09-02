#!/bin/bash
# The optional keep-awake pill. All process/state ownership lives in the
# haus-level `awake` command; this script only relays clicks and paints status.
#
# A barlib widget (hausfold.co/docs/haus/rooms/bar-widgets): the header below
# is the pill's whole wiring — the item's block, the popup frame, the barpop
# arm and the drawing=off/updates=on pairing are the runtime's and the
# emitter's now, and the seven hand-written popup items this pill used to keep
# in modules/bar/default.nix are popup_rows() here, rebuilt on every open so
# the "Allow sleep" row can wear the state it is about instead of being
# repainted from afar on every tick.
# widget: interval   = 30
# widget: popup      = true
# widget: subscribes = caffeinate_change
BAR_ITEM=caffeinate
source "$HOME/.config/sketchybar/barlib.sh"

AWAKE="/run/current-system/sw/bin/awake"
# This file, by the path SketchyBar knows it as — a popup row's click_script is
# a string SketchyBar runs later in a fresh process, so it can't call functions
# from here.
SELF="$HOME/.config/sketchybar/plugins/caffeinate.sh"
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

notify() { # notify <title> <body> <sf-symbol>
    # Through haus-notify, so trill draws it when it can and `rules.json`
    # can route it. Absolute: SketchyBar runs plugins under launchd's bare
    # PATH. `|| true` — a failed banner must not fail the arm reporting a
    # failure.
    /run/current-system/sw/bin/haus-notify --source haus.bar.awake --kind fault \
        --symbol "$3" --title "$1" --body "$2" >/dev/null 2>&1 || true
}

# The "Custom hours…" row. A CLI mode rather than a handler because it is a
# popup row's click_script — a fresh process — and it ends `barlib_tick; exit 0`
# without ever reaching barlib_main, the same shape github.sh's CLI modes have
# and for the same reason: barlib_main routes on whatever $SENDER this process
# inherited. The popup is closed here FIRST: the runtime appends its close
# AFTER the row's action, and this action blocks on a modal dialog — which
# would otherwise sit on top of a dropdown that only comes down once the
# dialog is answered.
if [ "${1:-}" = "custom" ]; then
    popup_close
    barlib_flush
    HOURS=$(/usr/bin/osascript -e \
        'text returned of (display dialog "Stay awake for how many whole hours?" default answer "3" with title "Keep Awake" buttons {"Cancel", "Start"} default button "Start" cancel button "Cancel")' \
        2>/dev/null) || exit 0
    if ! "$AWAKE" "${HOURS}h" >/dev/null 2>&1; then
        notify "Keep Awake" "Use a whole number from 1 to 8760." exclamationmark.triangle
    fi
    barlib_tick
    exit 0
fi

# `awake status --raw` is the machine face of the CLI: `mode<TAB>remaining<TAB>
# until`, byte-exact by test/awake-ui.bats precisely because this parse is its
# consumer.
read_awake() { # sets MODE, REMAINING
    local status
    status=$("$AWAKE" status --raw 2>/dev/null || printf 'off\t0\t0\n')
    IFS="$(printf '\t')" read -r MODE REMAINING _ <<EOF
$status
EOF
}

fetch() {
    read_awake
    local label='' active=0
    case "$MODE" in
        indefinite)
            label="∞"
            active=1
            ;;
        timed)
            local minutes hours
            minutes=$(((REMAINING + 59) / 60))
            hours=$((minutes / 60))
            minutes=$((minutes % 60))
            if [ "$hours" -gt 0 ] && [ "$minutes" -gt 0 ]; then
                label="${hours}h ${minutes}m"
            elif [ "$hours" -gt 0 ]; then
                label="${hours}h"
            else
                label="${minutes}m"
            fi
            active=1
            ;;
    esac
    local agents=0
    [ -e "$HELD" ] && agents=1
    emit label="$label" active="$active" agents="$agents"
}

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
#
# The colours are palette keys through sb_set rather than tones, deliberately:
# a FILLED pill ($PEACH behind $BASE type) is a shape the ladder cannot say —
# every tone is a foreground — and $SAPPHIRE-on-the-icon here is the agents'
# identity riding a pill that is otherwise yours. Same escape media.sh uses for
# its artwork tint; the icon glyph itself stays in the Nix style.
render() {
    if [ "$active" = 1 ]; then
        # Label is drawing: tuck the icon close to it (idle padding is
        # symmetric so the lone icon stays centred; the countdown needs the
        # tighter gap).
        pill --label "$label"
        sb_set icon.padding_right=4 label.color="$BASE" background.color="$PEACH"
        if [ "$agents" = 1 ]; then
            sb_set icon.color="$SAPPHIRE"
        else
            sb_set icon.color="$BASE"
        fi
    elif [ "$agents" = 1 ]; then
        pill --label "ai"
        sb_set icon.padding_right=4 icon.color="$SAPPHIRE" label.color="$SAPPHIRE" \
            background.color="$SURFACE0"
    else
        pill --label ""
        sb_set icon.padding_right=10 icon.color="$TEXT" background.color="$SURFACE0"
    fi
}

popup_rows() {
    popup_action --icon "1" --label "1 hour" --run "$AWAKE 1h >/dev/null"
    popup_action --icon "2" --label "2 hours" --run "$AWAKE 2h >/dev/null"
    popup_action --icon "4" --label "4 hours" --run "$AWAKE 4h >/dev/null"
    popup_action --icon "8" --label "8 hours" --run "$AWAKE 8h >/dev/null"
    popup_action --icon "󰅐" --label "Custom hours…" --run "$SELF custom"
    popup_action --icon "∞" --label "Until stopped" --run "$AWAKE indefinitely >/dev/null"
    # The stop row wears the state it acts on: red while YOUR assertion is the
    # thing it would end, mute when there is nothing it could end — an agent
    # hold included, since that one is released by the agent finishing its turn
    # and by nothing else. Rebuilt on every open, which is what retired the
    # tick-path repaint of this row's colour.
    read_awake
    if [ "$MODE" != "off" ]; then
        popup_action --icon "󰅖" --tone bad --label "Allow sleep" --run "$AWAKE off >/dev/null"
    else
        popup_action --icon "󰅖" --tone mute --label "Allow sleep" --run "$AWAKE off >/dev/null"
    fi
}

on_click() { popup_toggle; }

on_right_click() {
    popup_close
    # Right-click means "allow sleep", and it can only ever speak for YOUR
    # assertion. An agent hold is released by the agent finishing its turn
    # and by nothing else -- so when that is the only thing holding, say so
    # instead of running a command that silently changes nothing. A control
    # that appears to do nothing is how someone concludes the pill is broken.
    read_awake
    if [ -e "$HELD" ] && [ "$MODE" = "off" ]; then
        /run/current-system/sw/bin/haus-notify --source haus.bar.awake --symbol robot \
            --title "Agents are holding this Mac awake" \
            --body "It releases when they stop." >/dev/null 2>&1 || true
    else
        "$AWAKE" off >/dev/null 2>&1 || true
    fi
    barlib_tick
}

barlib_main

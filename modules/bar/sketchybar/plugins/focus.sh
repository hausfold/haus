#!/bin/bash
# focus.sh — the Focus (Do-Not-Disturb) pill
# (hausfold.co/docs/haus/rooms/bar-widgets). All logic lives in the focus
# engine (modules/focus → ~/.local/bin/focus); this script only relays clicks
# and renders state. Kept honest three ways: the engine fires focus_change
# after its own toggles, the focus-watcher launchd agent fires it when the
# Focus DB changes (Control Center / iPhone), and the header's interval polls
# as a backstop — which the diff now makes free when nothing moved, where the
# hand-written pill used to `--set` on every tick whether the state changed
# or not.
#
# The label is what is left of a `focus 25`, and nothing at all otherwise — the
# engine owns the countdown and this only draws it.
#
# It was a bell (md-bell / md-bell_off) until plugins/trill.sh wanted one. A
# bell is what a notification IS, so it belongs to the pill that opens the
# notification inbox; a moon is what every OS that ships a Do-Not-Disturb
# switch draws on it, macOS's own Control Center included.
# widget: interval   = 30
# widget: subscribes = focus_change

BAR_ITEM=focus
source "$HOME/.config/sketchybar/barlib.sh"

FOCUS="$HOME/.local/bin/focus"

# `focus status --raw` is the machine face of the CLI: `state<TAB>seconds`,
# where the seconds are what is left of a `focus 25` and 0 when nothing is
# counting. One call rather than two, and the engine's own claim check is what
# decides whether there is a countdown at all — a fuse that no longer owns the
# quiet it armed reads 0 here, so the pill can never show a timer over a quiet
# somebody switched on by hand.
fetch() {
    local raw
    raw=$("$FOCUS" status --raw 2>/dev/null || printf 'off\t0\n')
    IFS="$(printf '\t')" read -r STATE LEFT <<EOF
$raw
EOF
    emit state="$STATE" left="${LEFT:-0}"
}

# Minutes, rounded up, so the label reads "1m" through the final minute rather
# than "0m" for sixty seconds. Hours only past the hour — the pill's label sits
# beside a glyph and has room for one number, not two.
fmt_left() { # $1 = seconds
    local minutes hours
    minutes=$((($1 + 59) / 60))
    hours=$((minutes / 60))
    minutes=$((minutes % 60))
    if [ "$hours" -gt 0 ] && [ "$minutes" -gt 0 ]; then
        printf '%dh %dm' "$hours" "$minutes"
    elif [ "$hours" -gt 0 ]; then
        printf '%dh' "$hours"
    else
        printf '%dm' "$minutes"
    fi
}

# MAUVE fills the whole pill rather than just the glyph — the same escape
# calendar.sh's own render() uses for its own fill — so this is sb_set on
# raw palette keys rather than a tone: quiet is this pill's IDENTITY turning
# the background over, not a verdict on the ladder.
render() {
    if [ "$state" = on ]; then
        # The countdown is the label when there is one, and quiet with no fuse
        # keeps the bare moon it always had — a pill that grew a permanent empty
        # label would move every pill to its right for nothing. Both flags are
        # passed either way, which is what hands the icon padding to the runtime:
        # a lone glyph stays centred, a glyph with a number beside it tucks in.
        # The label rides the fill like the glyph does, hence $BASE on it too.
        if [ "${left:-0}" -gt 0 ]; then
            pill --icon "󰖔" --label "$(fmt_left "$left")"
            sb_set label.color="$BASE"
        else
            pill --icon "󰖔" --label ""
        fi
        sb_set background.color="$MAUVE" icon.color="$BASE"
    else
        pill --icon "󰽥" --label ""
        sb_set background.color="$SURFACE0" icon.color="$TEXT"
    fi
}

on_click() {
    # On failure (no Accessibility grant yet) the engine posts its own
    # "run focus doctor" notification — nothing to handle here.
    "$FOCUS" toggle || true
    barlib_tick
}

barlib_main "$@"

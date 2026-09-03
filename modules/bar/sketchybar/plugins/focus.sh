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
# It was a bell (md-bell / md-bell_off) until plugins/trill.sh wanted one. A
# bell is what a notification IS, so it belongs to the pill that opens the
# notification inbox; a moon is what every OS that ships a Do-Not-Disturb
# switch draws on it, macOS's own Control Center included.
# widget: interval   = 30
# widget: subscribes = focus_change

BAR_ITEM=focus
source "$HOME/.config/sketchybar/barlib.sh"

FOCUS="$HOME/.local/bin/focus"

fetch() {
    emit state="$("$FOCUS" status 2>/dev/null)"
}

# MAUVE fills the whole pill rather than just the glyph — the same escape
# calendar.sh's own render() uses for its own fill — so this is sb_set on
# raw palette keys rather than a tone: quiet is this pill's IDENTITY turning
# the background over, not a verdict on the ladder.
render() {
    if [ "$state" = on ]; then
        pill --icon "󰖔" --label ""
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

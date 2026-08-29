#!/bin/bash
# clock.sh — the clock pill, as the first barlib widget (docs/bar-framework.md).
# The item's block is emitted from this header by modules/bar/default.nix's
# frameworkBlock; only the pill's static look (fonts, the pink icon) stays on
# the Nix side, because it interpolates options this file cannot see.
# widget: interval = 10

BAR_ITEM=clock
source "$HOME/.config/sketchybar/barlib.sh"
if [ -f "$HOME/.config/sketchybar/clock_config.sh" ]; then
    source "$HOME/.config/sketchybar/clock_config.sh"
fi

fetch() {
    if [ "${BAR_CLOCK_MODE:-full}" = "compact" ]; then
        emit mode=compact \
            label="$(date '+%a') $(date '+%d/%m' | sed 's/^0//; s/\/0/\//') $(date '+%l:%M' | tr -d ' ')"
    else
        emit mode=full label="$(date '+%a %b %d')  $(date '+%I:%M %p')"
    fi
}

render() {
    if [ "$mode" = "compact" ]; then
        pill --icon "" --label "$label"
    else
        pill --icon "" --label "$label"
    fi
}

on_click() { open -a 'Notion Calendar'; }

barlib_main "$@"

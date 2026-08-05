#!/bin/bash
# pounce: name = Haus Tour
# pounce: description = A guided lap of the four moves
# pounce: icon = pawprint
# pounce: cheat = tour
#
# Running this IS step 4 of the haus tour ("press ⌘Space, type tour, hit ↵") —
# the palette proves itself by finishing its own tutorial. With no tour
# mid-flight it (re)starts one instead, so ⌘Space → tour is also the re-entry
# point after the first-run hint is gone. All state lives in the bar's
# tour.sh (sill); this is just the palette-shaped door to it — a quiet no-op
# when sill isn't installed to teach in.
TOUR="$HOME/.config/sketchybar/plugins/tour.sh"
[ -x "$TOUR" ] && exec "$TOUR" event palette

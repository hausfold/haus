#!/bin/bash

# Get the front app name
FRONT_APP=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true')

# While AeroSpace's resize or navigate mode is armed (see resize_mode.sh /
# navigate_mode.sh), keep that mode's glyph appended — moving focus repaints this
# label, which would otherwise drop it. fa-arrows-h (U+F07E) for resize,
# fa-arrows (U+F047) for navigate; keep in sync with those scripts.
if [ -f /tmp/sketchybar_resize_state ]; then
    GLYPH=$(printf '\xEF\x81\xBE')
    /opt/homebrew/bin/sketchybar --set "$NAME" label="$FRONT_APP $GLYPH"
elif [ -f /tmp/sketchybar_navigate_state ]; then
    GLYPH=$(printf '\xEF\x81\x87')
    /opt/homebrew/bin/sketchybar --set "$NAME" label="$FRONT_APP $GLYPH"
else
    /opt/homebrew/bin/sketchybar --set "$NAME" label="$FRONT_APP"
fi

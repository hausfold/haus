#!/bin/bash
# aerospace_lib.sh — "is the focused window fullscreen", and the two pill paints
# it drives. Sourced, never executed.
#
# AeroSpace's <mod>f fullscreen is a MODE with no other tell: the window fills
# the workspace, its siblings vanish, and nothing on screen says they still
# exist. The bar says it — in two channels at once, on two pills that already
# sit side by side in the left cluster, so they read as one signal:
#
#   SHAPE   an expand glyph in the front-app pill's icon slot, which is empty
#           in every other state, so its mere presence is the message.
#   COLOUR  the focused workspace pill goes peach instead of mauve — the
#           highest-salience object on the left changing temperature.
#
# Two channels rather than one because neither pill has a slot free enough to
# carry it alone. front_app's BACKGROUND belongs to resize_mode.sh and
# navigate_mode.sh (yellow / sky while those modes are armed, lavender when they
# disarm), so a fullscreen colour there would be clobbered the moment you tapped
# the leader — and silently, since those scripts restore lavender unconditionally.
# The workspace pill's only ink is the app's own glyph, so shape there is spoken
# for. Splitting the state across the two means it never fights another
# indicator for a slot, and it survives a reader who can't separate mauve from
# peach.
#
# Requires colors.sh to be sourced first (BASE, MAUVE, PEACH).

# nf-fa-expand (U+F065) as raw UTF-8 bytes — /bin/bash is 3.2, whose printf has
# no \u/\U; \xHH works. Same trick as the mode glyphs in front_app.sh.
AEROSPACE_FS_GLYPH=$(printf '\xEF\x81\xA5')

# 1 when the FOCUSED window is AeroSpace-fullscreen, 0 otherwise — including
# when there is no focused window at all. The test is on the VALUE, not the exit
# code: a workspace with no windows prints nothing and still exits 0, so `-eq 0`
# on the status would read an empty workspace as fullscreen.
aerospace_fullscreen() {
    if [ "$(/opt/homebrew/bin/aerospace list-windows --focused --format '%{window-is-fullscreen}' 2>/dev/null)" = "true" ]; then
        echo 1
    else
        echo 0
    fi
}

# The `--set front_app …` property arguments carrying the glyph, for the
# caller's own batch. Only the icon and the label's left padding are touched —
# the pill's background and label text belong to the mode scripts and to
# front_app.sh, and this must never write either.
#
# Both branches state label.padding_left rather than letting the icon's own
# padding do the work: whether a hidden icon still occupies its padding is a
# sketchybar detail nobody should have to remember, and stating it makes the
# pill's geometry identical whichever path last wrote it. The echoed words are
# space-free by construction, so the caller splits them without quoting.
fullscreen_front_app_args() {
    if [ "$1" = 1 ]; then
        echo "icon=$AEROSPACE_FS_GLYPH icon.color=$BASE icon.drawing=on icon.padding_left=8 icon.padding_right=0 label.padding_left=6"
    else
        echo "icon.drawing=off label.padding_left=8"
    fi
}

# The FOCUSED workspace pill's fill. Inactive pills are unaffected: fullscreen
# is a property of the focused window, so only the pill you're standing on can
# be showing it. Called by every writer of that colour — space.sh,
# aerospace_watcher.sh and launch_mode.sh's disarm — so none of them can restore
# a mauve pill over a fullscreen one.
fullscreen_active_ws_color() {
    if [ "$1" = 1 ]; then echo "$PEACH"; else echo "$MAUVE"; fi
}

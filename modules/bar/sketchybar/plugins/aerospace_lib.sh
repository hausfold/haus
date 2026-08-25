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
# It also carries the TILING pill's paint, for the same "one more aerospace call
# per tick, no extra sketchybar call" reason — see aerospace_tiling_args below.
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

# ── the tiling pill ──────────────────────────────────────────────────────────
# Which shape leader→. last dealt the focused workspace into (windows/scripts/
# tiling-mode.sh), drawn only when there is more than one tiled window to shape.
# One window has no layout to be in, and a pill that said "Columns" over a
# single maximised window would be furniture rather than information.
#
# Two of the three modes are a record of the last PRESS ON THIS WORKSPACE
# rather than a live read of the tree: AeroSpace reports a workspace's ROOT
# layout, and both `columns` and `grid` are h_tiles there — the grid is nesting
# underneath — so telling them apart would cost a tree walk on a 2 s tick to
# answer a question the state file already answers exactly. Open a window after
# dealing a grid and the shape drifts from the label until the next press —
# which is the same press that fixes the shape, so the label is never wrong for
# long.
#
# ACCORDION is the exception and is read live, because AeroSpace holds it
# itself: h_accordion/v_accordion at the root is a fact about the workspace, it
# survives every window opened after the press with no drift to correct, and
# ⌥, (the "Accordion layout" chord, modules/windows/wm-bindings.nix) can put a
# workspace into it without the dial ever hearing. Reading it costs nothing —
# the format string of the `list-windows` call this already makes gains one
# field, and the same call still answers the window count.
#
# The `$1 == ws` is the whole reason that last sentence is true. The state file
# is keyed by workspace (windows/scripts/tiling-mode.sh), and was one
# machine-wide word until this pill existed: under that, switching to a
# workspace you had never cycled would light the pill with whatever the dial was
# last set to somewhere else, and no press was coming to make it true.
#
# FLOATING windows are excluded from the count, because they are not in the tree
# and tiling-mode.sh does not touch them: on this desk every Ghostty popup is
# one, so counting them would light the pill on a workspace holding one terminal
# and a peek window.
#
# nf-fa-th_large (U+F009), nf-fa-columns (U+F0DB) and nf-fa-clone (U+F24D) as
# raw UTF-8 — /bin/bash is 3.2, whose printf has no \u/\U. Same trick as the
# fullscreen glyph above. Clone's two offset panes are the accordion: one on
# top, the other showing past its edge.
AEROSPACE_GRID_GLYPH=$(printf '\xEF\x80\x89')
AEROSPACE_COLUMNS_GLYPH=$(printf '\xEF\x83\x9B')
AEROSPACE_ACCORDION_GLYPH=$(printf '\xEF\x89\x8D')

# The `--set tiling …` property arguments, for the caller's own batch. Takes the
# focused workspace as its one argument — the caller has already asked for it,
# and asking a second time would both cost another process on a 2 s tick and
# open a window where the two answers disagree. The echoed words are space-free
# by construction, so the caller splits them without quoting — the same contract
# fullscreen_front_app_args has.
aerospace_tiling_args() {
    local ws="$1" out root tiled mode
    [ -z "$ws" ] && { echo "drawing=off"; return; }
    # `<window-layout>|<workspace-root-container-layout>`, one line per window.
    # Spaces stripped the way tiling-mode.sh strips them, so the fields split
    # cleanly; the root layout is the same on every line, so the first will do.
    out=$(/opt/homebrew/bin/aerospace list-windows --workspace "$ws" \
        --format '%{window-layout}|%{workspace-root-container-layout}' \
        2>/dev/null | tr -d ' ')
    # Tested before anything reads it. The count below would already draw
    # nothing (`grep -c` over an empty stream answers 0), so this is not what
    # stops an unreachable AeroSpace lighting the pill — it is what keeps the
    # root-layout split below from matching against an empty string, which is
    # the line that would otherwise start guessing once the count path moves.
    [ -z "$out" ] && { echo "drawing=off"; return; }
    tiled=$(printf '%s\n' "$out" | grep -cv '^floating|')
    if [ "${tiled:-0}" -lt 2 ]; then
        echo "drawing=off"
        return
    fi
    root=${out%%$'\n'*}
    root=${root#*|}
    case "$root" in
        *accordion)
            echo "drawing=on icon=$AEROSPACE_ACCORDION_GLYPH label=Accordion"
            return
            ;;
    esac
    mode=$(awk -F'\t' -v ws="$ws" '$1 == ws { m = $2 } END { print m }' \
        "$HOME/.local/state/haus/aerospace-tiling-mode" 2>/dev/null)
    if [ "$mode" = grid ]; then
        echo "drawing=on icon=$AEROSPACE_GRID_GLYPH label=Grid"
    else
        echo "drawing=on icon=$AEROSPACE_COLUMNS_GLYPH label=Columns"
    fi
}

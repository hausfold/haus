#!/bin/bash

# Batch-update every workspace indicator in one pass, rather than triggering
# one space.sh run per pill.
#
# The roster comes from the generated workspaces.sh — the SAME WORKSPACES array
# sketchybarrc adds the pills from, so this loop cannot cover a different set
# than the one on screen. It used to be a hand-written `1 2 3 4 T N R S B F M H
# C D`, which was one host's workspaces frozen into a shared file: a workspace
# nobody on that list had never lit up, and one that had been renamed was
# updated by name forever. Raising haus.windows.numberedWorkspaces past four is
# what would have made that visible.
#
# It is also the sole writer of the FULLSCREEN state (plugins/aerospace_lib.sh)
# — the glyph on the front-app pill and the focused workspace pill's peach fill,
# both appended to the same batch this already sends. Sole writer on purpose:
# front_app.sh is subscribed to the same front_app_switched this is, but it
# shells out to osascript for the app name, so routing the fullscreen repaint
# through it would put an ~80 ms round trip on a state that changes by keypress.
# Here it costs one more `aerospace` call per tick and no extra sketchybar call
# at all.
#
# The <mod>f binding fires aerospace_fullscreen_change (see
# ../aerospace-notify.sh) so the paint lands on the keypress rather than up to
# 2 s later. The poll stays because that event is not the only route into the
# state: focusing another window OF THE SAME APP changes which window's
# fullscreen flag we're reading and fires no front_app_switched at all.

source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/workspaces.sh"
source "$HOME/.config/sketchybar/plugins/aerospace_lib.sh"

CURRENT=$(/opt/homebrew/bin/aerospace list-workspaces --focused 2>/dev/null)
WITH_WINDOWS=$(/opt/homebrew/bin/aerospace list-workspaces --monitor all --empty no 2>/dev/null)
FULLSCREEN=$(aerospace_fullscreen)
ACTIVE_COLOR=$(fullscreen_active_ws_color "$FULLSCREEN")

ARGS=()
# A PAGE counts as its workspace, in BOTH tests — the same rule plugins/space.sh
# and launch_mode.sh's restore apply, and this is the copy that runs most often
# (every 2 s, and on every app switch). The focused workspace may be `T/haus`,
# and there is no `space.T/haus` pill, only `space.T`; bare `T` also holds no
# windows once lanes tile onto their own pages, so an exact occupancy match
# hides it as empty. Matched exactly here, this loop would re-darken the pill
# space.sh had just lit, within two seconds, forever.
for workspace in "${WORKSPACES[@]}"; do
    if [ "$workspace" = "$CURRENT" ] || [ "${CURRENT#"$workspace"/}" != "$CURRENT" ]; then
        ARGS+=(--set space.$workspace background.color=$ACTIVE_COLOR icon.color=$BASE label.color=$BASE drawing=on)
    elif echo "$WITH_WINDOWS" | grep -qE "^${workspace}(/|\$)"; then
        ARGS+=(--set space.$workspace background.color=$SURFACE0 icon.color=$TEXT label.color=$TEXT drawing=on)
    else
        ARGS+=(--set space.$workspace drawing=off)
    fi
done

# Unquoted on purpose — the helper echoes space-separated `key=value` words with
# no spaces inside any value, and each has to reach sketchybar as its own arg.
ARGS+=(--set front_app $(fullscreen_front_app_args "$FULLSCREEN"))

/opt/homebrew/bin/sketchybar "${ARGS[@]}"

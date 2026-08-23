#!/bin/bash

exec 2>>/tmp/sketchybar_space.log
set -x

source "$HOME/.config/sketchybar/colors.sh"
# The focused pill's fill is peach rather than mauve while the focused window is
# AeroSpace-fullscreen. Shared with aerospace_watcher.sh and launch_mode.sh so
# this single-pill repaint — which fires on every workspace change — can't put
# a plain mauve pill back over a fullscreen one for the two seconds until the
# watcher's next tick.
source "$HOME/.config/sketchybar/plugins/aerospace_lib.sh"

# Get current workspace from AeroSpace
CURRENT_WORKSPACE=$(/opt/homebrew/bin/aerospace list-workspaces --focused)
AEROSPACE_EXIT_CODE=$?

# Get all non-empty workspaces (workspaces with windows)
WORKSPACES_WITH_WINDOWS=$(/opt/homebrew/bin/aerospace list-workspaces --monitor all --empty no)

# Log for debugging
echo "$(date) - Item: $NAME, ID: ${NAME#space.}, Current: $CURRENT_WORKSPACE (Exit: $AEROSPACE_EXIT_CODE), Windows: $WORKSPACES_WITH_WINDOWS" >> /tmp/sketchybar_space.log

# Extract workspace ID from item name (space.1 -> 1, space.C -> C)
WORKSPACE_ID="${NAME#space.}"

# Check if this workspace is the focused workspace.
#
# A PAGE counts as its workspace. The focused workspace may be `T/haus` — the
# per-repo page a lane's window tiles onto (terminal/lanes/lane-open.sh) — and
# there is no `space.T/haus` pill, only `space.T`. Matched by exact string alone
# this pill went DARK for the whole time a page was focused, which on this
# desktop is most of the time the bar is looked at: the terminal's own pill
# disappeared exactly while you were in the terminal. The `page` pill beside the
# front app names which page; this names which workspace, and the two only read
# as a pair if both are lit.
if [ "$WORKSPACE_ID" = "$CURRENT_WORKSPACE" ] || [ "${CURRENT_WORKSPACE#"$WORKSPACE_ID"/}" != "$CURRENT_WORKSPACE" ]; then
    echo "  -> Active" >> /tmp/sketchybar_space.log
    # Active workspace - highlight it
    /run/current-system/sw/bin/sketchybar --set $NAME \
        background.color=$(fullscreen_active_ws_color "$(aerospace_fullscreen)") \
        icon.color=$BASE \
        label.color=$BASE \
        drawing=on
# Check if this workspace has windows — in itself or on any of its pages, for
# the same reason. `caps t` resolves a bare workspace to its most recent live
# page (windows/scripts/workspace-mru.sh), so a `T` whose windows all live on
# `T/*` is somewhere you can go, not an empty workspace to hide.
elif echo "$WORKSPACES_WITH_WINDOWS" | grep -qE "^${WORKSPACE_ID}(/|\$)"; then
    echo "  -> Inactive with windows" >> /tmp/sketchybar_space.log
    # Inactive workspace with windows
    /run/current-system/sw/bin/sketchybar --set $NAME \
        background.color=$SURFACE0 \
        icon.color=$TEXT \
        label.color=$TEXT \
        drawing=on
else
    echo "  -> Empty" >> /tmp/sketchybar_space.log
    # Workspace is empty and not focused - hide it
    /run/current-system/sw/bin/sketchybar --set $NAME drawing=off
fi

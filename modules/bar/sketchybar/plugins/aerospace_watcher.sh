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

source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/workspaces.sh"

CURRENT=$(/opt/homebrew/bin/aerospace list-workspaces --focused 2>/dev/null)
WITH_WINDOWS=$(/opt/homebrew/bin/aerospace list-workspaces --monitor all --empty no 2>/dev/null)

ARGS=()
for workspace in "${WORKSPACES[@]}"; do
    if [ "$workspace" = "$CURRENT" ]; then
        ARGS+=(--set space.$workspace background.color=$MAUVE icon.color=$BASE label.color=$BASE drawing=on)
    elif echo "$WITH_WINDOWS" | grep -q "^${workspace}$"; then
        ARGS+=(--set space.$workspace background.color=$SURFACE0 icon.color=$TEXT label.color=$TEXT drawing=on)
    else
        ARGS+=(--set space.$workspace drawing=off)
    fi
done

/opt/homebrew/bin/sketchybar "${ARGS[@]}"

#!/bin/bash
# launch_mode.sh on|off
#
# Replaces the LEFT side of the bar with a launcher while AeroSpace's `launch`
# leader-mode is armed:
#   - the workspace pills AND the front-app pill are hidden, replaced by a
#     PICKER — one bubble per leader hotkey (launcher.<key>, defined in
#     sketchybarrc), colored by state: focused = mauve, open/running = green
#     letter, closed = grey;
#   - open/active hints are moved to the LEFT of the row (keeping their original
#     relative order) so the live state reads first;
#   - the Apple logo becomes a → "go-to" glyph.
# Nothing on the right side is touched. Tapping caps (F18) arms it; esc or any
# launch action disarms it.
#
# Concurrency: caps -> letter fires `on` and `off` as two near-simultaneous
# fire-and-forget processes. Each writes the desired state and runs a LOCKED
# reconcile that drives the bar toward the latest state, so the last keypress
# always wins and the two can never interleave into a half-armed mess.

export PATH="/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

STATE="/tmp/sketchybar_launch_state"   # desired: "on" | "off"
SNAP="/tmp/sketchybar_launch_apple.json"  # present == currently armed
LOCK="/tmp/sketchybar_launch.lock"

source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/sizes.sh"
# LAUNCHERS (leader key -> workspace map) is GENERATED from haus._roster
# into workspaces.sh — the same data-driven roster as the workspace pills, so the
# picker can't drift from the app roster. (bash 3.2 has no assoc arrays, hence a
# plain "<key>:<ws>" string.)
source "$HOME/.config/sketchybar/workspaces.sh"

# md-arrow-right-bold (U+F0734) as raw UTF-8 bytes — /bin/bash is 3.2, whose
# printf has no \u/\U; \xHH works.
ARROW=$(printf '\xF3\xB0\x9C\xB4')

spaces() { sketchybar --query bar | jq -r '.items[] | select(startswith("space."))'; }

acquire_lock() {
    local n=0
    until mkdir "$LOCK" 2>/dev/null; do
        sleep 0.02
        n=$((n + 1))
        [ $n -ge 75 ] && rmdir "$LOCK" 2>/dev/null   # ~1.5s: steal a crashed lock
    done
    trap 'rmdir "$LOCK" 2>/dev/null' EXIT
}

do_arm() {
    sketchybar --query apple.logo | jq '{
        icon: .icon.value, font: .icon.font,
        color: .icon.color, bg: .geometry.background.color }' > "$SNAP"

    local focused open
    focused=$(aerospace list-workspaces --focused 2>/dev/null)
    open=$(aerospace list-workspaces --monitor all --empty no 2>/dev/null)

    # Hide + freeze the workspace pills and their batch-updater, hide front-app.
    local hide="" sp
    for sp in $(spaces); do hide+=" --set $sp drawing=off updates=off"; done
    hide+=" --set aerospace_watcher updates=off --set front_app drawing=off"

    # Color the picker; collect open/active first for the left-ward ordering.
    local colors="" active="" closed=""
    for entry in $LAUNCHERS; do
        local key=${entry%%:*} ws=${entry#*:}
        if [ -n "$ws" ] && [ "$ws" = "$focused" ]; then
            colors+=" --set launcher.$key drawing=on background.color=$MAUVE icon.color=$BASE"
            active+=" launcher.$key"
        elif [ -n "$ws" ] && grep -qx "$ws" <<<"$open"; then
            colors+=" --set launcher.$key drawing=on background.color=$SURFACE0 icon.color=$GREEN"
            active+=" launcher.$key"
        else
            colors+=" --set launcher.$key drawing=on background.color=$MANTLE icon.color=$OVERLAY0"
            closed+=" launcher.$key"
        fi
    done

    eval "sketchybar $hide $colors"

    # Lead glyph (separate call: the byte-glyph + spaced font name need quoting).
    # Hide the ears image so the arrow glyph shows alone (the image otherwise
    # draws on top of it); do_disarm turns it back on from the snapshot.
    sketchybar --set apple.logo icon="$ARROW" icon.font="${BAR_FONT}:Bold:$FS_ICON" \
               icon.color=$BASE background.color=$MAUVE background.image.drawing=off

    # Move open/active hints to the left, original relative order preserved.
    sketchybar --reorder $active $closed
}

do_disarm() {
    # Query occupancy up front so the whole left side repaints in ONE batch —
    # no intermediate frame (the old mid-disarm aerospace_watcher.sh call left a
    # visible gap that flashed).
    local focused open
    focused=$(aerospace list-workspaces --focused 2>/dev/null)
    open=$(aerospace list-workspaces --monitor all --empty no 2>/dev/null)

    local a="" sp ws
    # Hide the picker bubbles.
    for entry in $LAUNCHERS; do a+=" --set launcher.${entry%%:*} drawing=off"; done
    # Thaw + repaint the workspace pills to live occupancy (mirrors space.sh).
    for sp in $(spaces); do
        ws=${sp#space.}
        if [ "$ws" = "$focused" ]; then
            a+=" --set $sp updates=when_shown drawing=on background.color=$MAUVE icon.color=$BASE label.color=$BASE"
        elif grep -qx "$ws" <<<"$open"; then
            a+=" --set $sp updates=when_shown drawing=on background.color=$SURFACE0 icon.color=$TEXT label.color=$TEXT"
        else
            a+=" --set $sp updates=when_shown drawing=off"
        fi
    done
    a+=" --set aerospace_watcher updates=on --set front_app drawing=on"

    # Restore the Apple logo (glyph/font from the snapshot) in the SAME batch so
    # the left side repaints in a single frame.
    local ai af ac ab
    ai=$(jq -r '.icon'  "$SNAP"); af=$(jq -r '.font'  "$SNAP")
    ac=$(jq -r '.color' "$SNAP"); ab=$(jq -r '.bg'    "$SNAP")
    a+=" --set apple.logo icon=$ai icon.font='$af' icon.color=$ac background.color=$ab background.image.drawing=on"

    eval "sketchybar $a"
    rm -f "$SNAP"
}

# Drive the bar toward the latest desired state, re-reading STATE each pass so
# the LAST writer wins even if it wrote while we were mid-render (caps->letter
# fires `on` then `off`; the trailing `off` always settles us back to normal).
# SNAP present == armed, absent == normal, so steady-state passes are no-ops.
reconcile() {
    acquire_lock
    local desired n=0
    while [ $n -lt 6 ]; do
        n=$((n + 1))
        desired=$(cat "$STATE" 2>/dev/null)
        if [ "$desired" = on ] && [ ! -f "$SNAP" ]; then
            do_arm
        elif [ "$desired" = off ] && [ -f "$SNAP" ]; then
            do_disarm
        else
            break
        fi
    done
}

case "$1" in
    on)  echo on  > "$STATE"
         # Haus-tour hook — one stat when no tour is mid-flight (plugins/tour.sh).
         { [ -f "$HOME/.local/state/nebelhaus/tour" ] && "$HOME/.config/sketchybar/plugins/tour.sh" event launch; } >/dev/null 2>&1 &
         reconcile ;;
    off) echo off > "$STATE"; reconcile ;;
    *)   echo "usage: $0 on|off" >&2; exit 1 ;;
esac

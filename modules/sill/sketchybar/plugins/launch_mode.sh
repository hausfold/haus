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
#   - the haus logo pill INVERTS — same glyph, accent background, BASE glyph —
#     so the lead reads as the same object in a different state. It used to be
#     replaced outright by a → "go-to" glyph, which made the leftmost pill a
#     different object every time the leader was armed, and left the swap
#     fighting the pill's own state colours (plugins/logo.sh) for the one
#     `icon.color` all of them have to share.
# Nothing on the right side is touched. Tapping caps (F18) arms it; esc or any
# launch action disarms it.
#
# Concurrency: caps -> letter fires `on` and `off` as two near-simultaneous
# fire-and-forget processes. Each writes the desired state and runs a LOCKED
# reconcile that drives the bar toward the latest state, so the last keypress
# always wins and the two can never interleave into a half-armed mess.

export PATH="/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

STATE="/tmp/sketchybar_launch_state"   # desired: "on" | "off"
# Present == currently armed. plugins/logo.sh reads this path too — it is the
# one signal that the logo pill is not its to paint — so the two agree on which
# of them owns the pill without either querying the other.
SNAP="/tmp/sketchybar_launch_logo.json"
LOCK="/tmp/sketchybar_launch.lock"

source "$HOME/.config/sketchybar/colors.sh"
# sizes.sh is deliberately not sourced any more: the only thing that needed it
# was the ${BAR_FONT}:Bold:$FS_ICON on the lead-glyph swap, and the swap is gone.
# SILL_LOGO_COLOR — the logo's resting accent, GENERATED from haus.sill.logo.*
# (after colors.sh, which is where the `$MAUVE` it holds comes from). The fill
# below is that same accent, so leader mode looks like the pill turned inside
# out rather than like a colour arriving from nowhere.
source "$HOME/.config/sketchybar/logo_config.sh"
# LAUNCHERS (leader key -> workspace map) is GENERATED from haus._roster
# into workspaces.sh — the same data-driven roster as the workspace pills, so the
# picker can't drift from the app roster. (bash 3.2 has no assoc arrays, hence a
# plain "<key>:<ws>" string.)
source "$HOME/.config/sketchybar/workspaces.sh"

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
    # Before the snapshot, and synchronously: the pointer can be sitting on the
    # logo pill when caps is tapped, and the hover sweep is a loop in another
    # process that would both overwrite the inverted pill and put a mid-tween
    # colour into the snapshot below. logo.sh owns the pidfile, so it is the one
    # that stops it — and it settles the pill un-animated on the way out, which
    # is what makes the next two lines record a real state colour.
    "$HOME/.config/sketchybar/plugins/logo.sh" sweep-stop 2>/dev/null

    # The glyph is not snapshotted any more — it no longer changes. Only the
    # two colours do, and only they are put back.
    sketchybar --query haus.logo | jq '{
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

    # Invert the lead: the accent moves from the glyph to the pill behind it.
    # Left in the same batch as everything else above (no separate call needed
    # now that no glyph or font name has to be quoted through it).
    sketchybar --set haus.logo icon.color=$BASE background.color="$SILL_LOGO_COLOR"

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

    # Restore the logo's two colours from the snapshot in the SAME batch, so the
    # left side repaints in a single frame. Restoring rather than recomputing is
    # deliberate: a state tick between arm and disarm is a sub-second window
    # nobody can hit, and logo.sh's next tick corrects it regardless.
    local ac ab
    ac=$(jq -r '.color' "$SNAP"); ab=$(jq -r '.bg' "$SNAP")
    a+=" --set haus.logo icon.color=$ac background.color=$ab"

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
         { [ -f "$HOME/.local/state/haus/tour" ] && "$HOME/.config/sketchybar/plugins/tour.sh" event launch; } >/dev/null 2>&1 &
         reconcile ;;
    off) echo off > "$STATE"; reconcile ;;
    *)   echo "usage: $0 on|off" >&2; exit 1 ;;
esac

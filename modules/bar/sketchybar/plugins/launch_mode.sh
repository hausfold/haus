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
# The focused workspace pill's fill (peach while the focused window is
# AeroSpace-fullscreen, mauve otherwise). do_disarm repaints that pill from
# scratch, so without this it would drop a fullscreen pill back to mauve every
# time the leader was tapped and released.
source "$HOME/.config/sketchybar/plugins/aerospace_lib.sh"
# BAR_FONT and FS_PIP — the pips' face, which do_disarm paints through
# plugins/workspace_lib.sh (sourced below, with the roster it walks).
source "$HOME/.config/sketchybar/sizes.sh"
# BAR_LOGO_COLOR — the logo's resting accent, GENERATED from haus.bar.logo.*
# (after colors.sh, which is where the `$MAUVE` it holds comes from). The fill
# below is that same accent, so leader mode looks like the pill turned inside
# out rather than like a colour arriving from nowhere.
source "$HOME/.config/sketchybar/logo_config.sh"
# LAUNCHERS (leader key -> workspace map) is GENERATED from haus._roster
# into workspaces.sh — the same data-driven roster as the workspace pills, so the
# picker can't drift from the app roster. (bash 3.2 has no assoc arrays, hence a
# plain "<key>:<ws>" string.)
source "$HOME/.config/sketchybar/workspaces.sh"
source "$HOME/.config/sketchybar/plugins/workspace_lib.sh"

# $BAR_PAGES / $BAR_TILING / $BAR_BURIED — GENERATED from haus.windows.enable
# (and haus.bar.workspaces.buried), the switches that decide whether
# sketchybarrc adds the `page`, `tiling` and `buried` items at all.
# Read here because this file eval's its whole repaint as ONE sketchybar
# invocation: a `--set` naming an item that was never added would land mid-batch.
# Unreachable today (launch mode is an AeroSpace mode, so the leader implies the
# tiler implies the pills), which is exactly why it would be a silent trap for
# whoever decouples them.
source "$HOME/.config/sketchybar/windows_config.sh"

# The workspace pills, by the generated roster rather than by asking the bar
# for every item named `space.*`: a pill's dropdown rows are items too
# (`space.T.popup.0`, plugins/space.sh), and a query by prefix would hand them
# to the disarm below to switch back ON.
spaces() { local ws; for ws in "${WORKSPACES[@]}"; do printf 'space.%s\n' "$ws"; done; }

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
    # `page` freezes and hides with the workspace pills — frozen as well as
    # hidden because a workspace change while the leader is armed (caps→letter
    # fires `on` then `off`) would otherwise re-run its script and flash it back
    # on over the picker row. It is restored by re-running its own plugin (see
    # do_disarm) rather than from a value computed here: its label is a
    # workspace name, and this batch is `eval`ed as one unquoted string.
    [ "${BAR_PAGES:-0}" = 1 ] && hide+=" --set page drawing=off updates=off"
    # `tiling` goes with it, and for the same reason: it lives in this same left
    # group, and the watcher's 2 s tick would otherwise paint it back on top of
    # the picker row a beat after the leader armed.
    [ "${BAR_TILING:-0}" = 1 ] && hide+=" --set tiling drawing=off updates=off"
    # `buried` too — the same group, the same watcher, the same flash.
    [ "${BAR_BURIED:-0}" = 1 ] && hide+=" --set buried drawing=off updates=off"

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
    sketchybar --set haus.logo icon.color=$BASE background.color="$BAR_LOGO_COLOR"

    # Move open/active hints to the left, original relative order preserved.
    sketchybar --reorder $active $closed
}

do_disarm() {
    # Query occupancy up front so the whole left side repaints in ONE batch —
    # no intermediate frame (the old mid-disarm aerospace_watcher.sh call left a
    # visible gap that flashed). The pills are painted by the same function the
    # watcher paints them with (plugins/workspace_lib.sh), so a pill comes back
    # from the leader saying exactly what it said going in: its pips, its
    # ring, the fullscreen peach. This used to be the third hand copy of that
    # rule, and the copies had already started to drift.
    ws_snapshot
    local active_color
    active_color=$(fullscreen_active_ws_color "$WS_FULLSCREEN")

    WS_ARGS=()
    local entry sp
    # Hide the picker bubbles.
    for entry in $LAUNCHERS; do WS_ARGS+=(--set "launcher.${entry%%:*}" drawing=off); done
    # Thaw the workspace pills, then paint them to live state.
    for sp in $(spaces); do WS_ARGS+=(--set "$sp" updates=when_shown); done
    ws_pills_args "$active_color"
    WS_ARGS+=(--set aerospace_watcher updates=on --set front_app drawing=on)
    [ "${BAR_PAGES:-0}" = 1 ] && WS_ARGS+=(--set page updates=on)
    [ "${BAR_TILING:-0}" = 1 ] && WS_ARGS+=(--set tiling updates=on)
    [ "${BAR_BURIED:-0}" = 1 ] && WS_ARGS+=(--set buried updates=on)

    # Restore the logo's two colours from the snapshot in the SAME batch, so the
    # left side repaints in a single frame. Restoring rather than recomputing is
    # deliberate: a state tick between arm and disarm is a sub-second window
    # nobody can hit, and logo.sh's next tick corrects it regardless.
    local ac ab
    ac=$(jq -r '.color' "$SNAP"); ab=$(jq -r '.bg' "$SNAP")
    WS_ARGS+=(--set haus.logo icon.color="$ac" background.color="$ab")

    # An ARRAY now, not the `eval`ed string this batch used to be: a pill's
    # label is its pips, and nothing that is drawn should have to survive a
    # second parse as shell.
    sketchybar "${WS_ARGS[@]}"
    # One extra process, on a keypress that already spawns several, and the only
    # honest way to restore a pill whose visibility depends on a name: its label
    # is a workspace name, and the page pill owns that repaint.
    [ "${BAR_PAGES:-0}" = 1 ] &&
      "$HOME/.config/sketchybar/plugins/page.sh" >/dev/null 2>&1 &
    rm -f "$SNAP"
    # `tiling` and `buried` need no second process: they are painted by
    # aerospace_watcher.sh, which the batch above has just un-frozen, so waking
    # it is one trigger. Without it they would come back on the watcher's own
    # tick — up to 2 s of a hole where a pill was, on every single leader tap.
    # After the rm: the watcher stands down while $SNAP says the leader is up.
    { [ "${BAR_TILING:-0}" = 1 ] || [ "${BAR_BURIED:-0}" = 1 ]; } &&
      sketchybar --trigger aerospace_tiling_change
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

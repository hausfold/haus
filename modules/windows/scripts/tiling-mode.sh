#!/bin/bash
# One-shot tiling reset for the FOCUSED workspace, cycled by leader -> period
# (modules/windows/launch-keys.nix reserves it, modules/windows/default.nix
# wires the binding). Three modes: columns (AeroSpace's own tiles-horizontal,
# what you already get with nothing pressed), spiral (nested splits that
# alternate orientation on every window, since "columns" never alternates on
# its own -- every new window just extends the row) and grid (evenly bucketed
# into ceil(sqrt(n)) columns).
#
# GLOBAL state on purpose (one file, not one per workspace): whichever
# workspace is focused when you press the key is the one that gets
# reshaped, and the state just remembers which mode comes NEXT. Pressing the
# key repeatedly cycles columns -> spiral -> grid -> columns..., so landing
# back on a mode you already picked reapplies it fresh -- the zellij-style
# "spin the dial until it's right again" feel, without a live daemon
# fighting your manual resizes in between presses. (AeroSpace fires no
# window-CLOSED event, only on-window-detected for opens, so a continuously
# -enforced mode would need to poll; a one-shot press needs nothing running
# between presses.)
#
# Every step below works purely off window ids ($ids), never focus, so this
# never disturbs which window you were actually looking at, and never
# touches any workspace other than the focused one.
#
# The tree-building primitive is `join-with`, which -- like i3/bspwm -- wraps
# the target and its nearest neighbour in a new parent oriented along the
# search axis (horizontal for left/right, vertical for up/down). Starting
# from a flat row, the only neighbour a not-yet-touched window is guaranteed
# to have is the one immediately to its LEFT -- `join-with ... left` is the
# only direction safe to use here, and it always wraps the pair
# HORIZONTALLY. The `layout --window-id ... v_tiles` call right after each
# join is what turns that pair vertical -- and it is a NO-OP unless that
# window-id is also the currently FOCUSED one, verified empirically
# (`--window-id` filters which window's own container gets touched; it does
# not by itself move the operation there). So every layout call below is
# preceded by an explicit `focus --window-id`.
#
# Getting to that flat row is its own trap. Neither `flatten-workspace-tree`
# nor forcing every window's own container to h_tiles reliably undoes a
# spiral/grid a PREVIOUS press already built -- both look right (five equal
# columns) yet leave the tree in a state where the next join/layout call
# silently no-ops or lands on the wrong container -- verified empirically
# across repeated runs, not assumed. The one reset that came back correct on
# every repeated trial is a full round-trip: move every window OUT to a
# scratch workspace and back. That forces AeroSpace to rebuild the tree from
# nothing rather than reshape whatever was already there, the same as it
# would for windows arriving fresh. The scratch workspace is an ad-hoc name,
# not one of haus's declared persistent-workspaces, so it exists only for the
# instant the windows are on it and drops back out of `list-workspaces` the
# moment it's empty again -- same as any other workspace with nothing on it.
#
# Original focus is restored at the end so cycling the mode never changes
# which window you were actually looking at.
set -u

STATE="$HOME/.local/state/haus/aerospace-tiling-mode"
mkdir -p "$(dirname "$STATE")"

ws=$(aerospace list-workspaces --focused 2>/dev/null) || exit 0
[ -z "$ws" ] && exit 0

focused_id=$(aerospace list-windows --focused --format '%{window-id}' 2>/dev/null | tr -d ' ')

current=$(cat "$STATE" 2>/dev/null || echo columns)
case "$current" in
    columns) next=spiral ;;
    spiral) next=grid ;;
    *) next=columns ;;
esac

ids=()
while IFS= read -r id; do
    [ -n "$id" ] && ids+=("$id")
done < <(aerospace list-windows --workspace "$ws" --format '%{window-id}' 2>/dev/null | tr -d ' ')
n=${#ids[@]}

SCRATCH_WS="haus-tiling-scratch"
for id in "${ids[@]}"; do
    aerospace move-node-to-workspace --window-id "$id" "$SCRATCH_WS" >/dev/null 2>&1 || true
done
for id in "${ids[@]}"; do
    aerospace move-node-to-workspace --window-id "$id" "$ws" >/dev/null 2>&1 || true
done
aerospace layout --workspace "$ws" --root h_tiles >/dev/null 2>&1 || true

case "$next" in
    columns)
        : # flatten + horizontal root above already is "columns"
        ;;
    spiral)
        orient=v_tiles
        i=1
        while [ "$i" -lt "$n" ]; do
            aerospace join-with --window-id "${ids[$i]}" left >/dev/null 2>&1 || true
            aerospace focus --window-id "${ids[$i]}" >/dev/null 2>&1 || true
            aerospace layout --window-id "${ids[$i]}" "$orient" >/dev/null 2>&1 || true
            if [ "$orient" = v_tiles ]; then orient=h_tiles; else orient=v_tiles; fi
            i=$((i + 1))
        done
        ;;
    grid)
        if [ "$n" -gt 0 ]; then
            cols=1
            while [ $((cols * cols)) -lt "$n" ]; do cols=$((cols + 1)); done
            rows=$(((n + cols - 1) / cols))
            i=0
            while [ "$i" -lt "$n" ]; do
                if [ $((i % rows)) -ne 0 ]; then
                    aerospace join-with --window-id "${ids[$i]}" left >/dev/null 2>&1 || true
                    aerospace focus --window-id "${ids[$i]}" >/dev/null 2>&1 || true
                    aerospace layout --window-id "${ids[$i]}" v_tiles >/dev/null 2>&1 || true
                fi
                i=$((i + 1))
            done
        fi
        ;;
esac

aerospace balance-sizes --workspace "$ws" >/dev/null 2>&1 || true
[ -n "$focused_id" ] && aerospace focus --window-id "$focused_id" >/dev/null 2>&1
echo "$next" >"$STATE"

#!/bin/bash
# One-shot tiling reset for the FOCUSED workspace, cycled by leader -> period
# (modules/windows/launch-keys.nix reserves the key, modules/windows/default.nix
# wires the binding). Two modes:
#
#   columns   AeroSpace's own flat row — what you get with nothing pressed,
#             every window a full-height column of equal width.
#   grid      ceil(sqrt(n)) columns, the windows dealt into them as evenly as
#             possible, and every column WIDENED in proportion to how many
#             windows it holds — so all n windows end up the same area. The
#             shapes that falls out as, for the counts a desk actually has:
#
#               2  side by side              6  3x2
#               3  one full-height third,    7  a 2-stack, a 2-stack, a 3-stack
#                  then two stacked          8  a 2-stack and two 3-stacks
#               4  2x2                       9  3x3
#               5  one full-height fifth,    n  ceil(sqrt(n)) columns, same rule
#                  then 2x2                     (no special case above 9)
#
# The state is PER WORKSPACE, keyed by name in one file: whichever workspace is
# focused when you press the key is the one that gets reshaped, and the file
# remembers which mode is on THERE. Pressing the key alternates, so landing back
# on a mode you already picked reapplies it fresh -- the "spin the dial until
# it's right again" feel, without a live daemon fighting your manual resizes in
# between presses. (AeroSpace fires no window-CLOSED event, only
# on-window-detected for opens, so a continuously-enforced mode would have to
# poll; a one-shot press needs nothing running between presses.)
#
# It was one machine-wide word until the bar started reading it. A global dial
# is defensible for the KEY -- you press it until the workspace in front of you
# looks right, and where the dial was last is as good a starting point as any --
# but it is not defensible for a PILL: switch to a workspace you have never
# cycled and a global state file would have the bar assert "Grid" over three
# plain columns, with no press coming that would make it true. Keyed by
# workspace, the pill can only ever claim what was actually done to the
# workspace you are looking at.
#
# Trimmed to the last 32 entries on every write, because pages are workspaces
# too (`T/<repo>`, made and evaporated by the lane machinery all day) and an
# untrimmed file would accrete one line per page forever. Falling off the end
# costs a workspace its remembered mode, which reads as "columns" and makes the
# next press deal a grid -- the same thing a workspace you have never cycled
# does.
#
# ── one eval, one reflow ─────────────────────────────────────────────────────
# EVERY aerospace command below is concatenated into a SINGLE `aerospace eval`.
# That is the whole reason this stopped looking janky: each `aerospace` process
# is a socket round trip that ends in its own layout pass, so the old
# command-per-step version painted twenty intermediate arrangements on the way
# to the final one -- windows visibly flying to a place they were never meant to
# stop at, for the better part of a second. `eval` runs the list inside one
# refresh session, so the windows are laid out ONCE, from where they were to
# where they belong. Measured at ~30 ms for the batch on nine windows.
#
# Nothing here focuses a window either, and that is also load-bearing: the old
# version had to `focus --window-id` before every `layout` call, and a focus
# change raises windows and can activate another app, which is the other half of
# what the flashing was. `join-with --window-id` and `move --window-id` do their
# work on the id alone.
#
# ── how the tree gets built ──────────────────────────────────────────────────
# `flatten-workspace-tree` really is enough to get back to a flat row -- the old
# comment here claimed it wasn't and paid for a full move-every-window-out-to-a-
# scratch-workspace-and-back round trip to avoid it. Re-measured on 0.21.3
# (frames read back with `hausrect`, not eyeballed): flatten from a three-deep
# grid returns n equal full-height columns every time. The scratch round trip is
# gone, and with it the biggest single source of the bounce.
#
# A column is then built from that flat row with TWO different primitives, which
# is the part that isn't obvious:
#
#   join-with --window-id <2nd> left    wraps the 1st and 2nd windows of the
#                                       column in a new container. Nesting
#                                       normalization (enable-normalization-
#                                       opposite-orientation-for-nested-
#                                       containers, on in aerospace.toml) makes
#                                       that container VERTICAL for free, so no
#                                       `layout v_tiles` call is needed.
#   move --window-id <3rd..> left       pushes each FURTHER window INTO that
#                                       container as a flat sibling.
#
# Using join-with for the third window instead wraps it with the container
# rather than adding to it — [[a,b],c] — and normalization then flips the inner
# pair back to horizontal, so a 3-stack comes out as two windows side by side
# above a wide one. Measured, not assumed. `move` is the only primitive that
# appends.
#
# ── why the widths need arithmetic ───────────────────────────────────────────
# join-with does NOT hand the new container the width of the two windows it
# swallowed: AeroSpace re-equalises the root's children, so three columns
# holding 2, 2 and 3 windows come out the same width and the windows in the
# 3-stack are two thirds the size of the others. Balanced areas therefore need
# an explicit `resize width`, in points -- which is what `hausrect` is for (see
# hausrect.swift: nothing inside AeroSpace will tell you how wide anything is).
#
# `resize --window-id X width D` moves X's column by D and spreads -D/(c-1) over
# every OTHER column, so the deltas can't just be "target minus current" -- each
# one disturbs the others. Solving that for c columns, resizing all but the last:
#
#     d_j = (t_j - t_last) * (c-1)/c        t_j = content * k_j / n
#
# where content is the tiled width minus the c-1 inner gaps, k_j the number of
# windows in column j, and n the total. d_j is zero whenever k_j equals the last
# column's count, so an even grid (4, 6, 9 windows) emits no resize at all.
#
# Both content and the gap are MEASURED from the windows that are already on
# screen rather than derived from display bounds and haus's gap options: the
# tiled row spans the usable rect exactly, so `max(x+w) - min(x)` is that rect's
# width with the notch, the bar inset and any per-monitor gap override already
# taken out.
set -u

AEROSPACE=/opt/homebrew/bin/aerospace
# Installed by modules/windows/default.nix into the system profile, so the path
# is stable across rebuilds — the same literal-path convention the bar's plugins
# use for barpop.
HAUSRECT=/run/current-system/sw/bin/hausrect

STATE="$HOME/.local/state/haus/aerospace-tiling-mode"
mkdir -p "$(dirname "$STATE")"

ws=$("$AEROSPACE" list-workspaces --focused 2>/dev/null) || exit 0
[ -z "$ws" ] && exit 0

# `<workspace>\t<mode>`, last line for a workspace wins. Anything that doesn't
# parse as a line for THIS workspace — a fresh machine, a workspace never
# cycled, or the single bare `columns`/`spiral`/`grid` word the file used to
# hold before it was keyed — reads as "not grid", so the first press lands on
# grid.
case "$(awk -F'\t' -v ws="$ws" '$1 == ws { m = $2 } END { print m }' "$STATE" 2>/dev/null)" in
    grid) next=columns ;;
    *) next=grid ;;
esac

# Floating windows are not in the tree and must not be counted: every Ghostty
# popup on this desk is one (aerospace.toml floats them all on detection, and
# terminal's launch.sh tiles back only the windows that are really terminals).
ids=()
while IFS='|' read -r id layout; do
    [ -z "$id" ] && continue
    [ "$layout" = floating ] && continue
    ids+=("$id")
done < <("$AEROSPACE" list-windows --workspace "$ws" --format '%{window-id}|%{window-layout}' 2>/dev/null | tr -d ' ')
n=${#ids[@]}

# The commands, accumulated as one `;`-joined string for the single eval below.
# balance-sizes runs on the flat row, before any joining: it is what makes every
# column start out equal, which is the assumption the width arithmetic rests on.
# The workspace name is quoted INSIDE the expression: `aerospace eval` splits on
# whitespace like a shell and honours double quotes, and a workspace name is
# haus.workspaces data — a name with a space in it would otherwise take the
# whole batch apart, silently, since the eval's stderr is dropped below.
cmds="flatten-workspace-tree --workspace \"$ws\""
cmds="$cmds; layout --workspace \"$ws\" --root h_tiles"
cmds="$cmds; balance-sizes --workspace \"$ws\""

if [ "$next" = grid ] && [ "$n" -gt 1 ]; then
    # ceil(sqrt(n)) columns, filled base-first so the SHORT columns come first:
    # at three windows that is one full-height window on the left and two
    # stacked beside it, which is the shape this mode is for.
    cols=1
    while [ $((cols * cols)) -lt "$n" ]; do cols=$((cols + 1)); done
    base=$((n / cols))
    rem=$((n % cols))

    counts=()
    j=0
    while [ "$j" -lt "$cols" ]; do
        k=$base
        [ "$j" -ge $((cols - rem)) ] && k=$((base + 1))
        counts+=("$k")
        j=$((j + 1))
    done

    # The rect, off the windows themselves. `gap` is the smallest positive space
    # between two adjacent edges in either axis — haus sets inner.horizontal and
    # inner.vertical to the same value, so whichever axis the current layout
    # happens to expose is the right answer.
    read -r width gap < <("$HAUSRECT" "${ids[@]}" 2>/dev/null | awk '
        { x[NR] = $2; y[NR] = $3; w[NR] = $4; h[NR] = $5
          if (lo == "" || $2 < lo) lo = $2
          # NR == 1 rather than a bare `>`: an uninitialised awk variable
          # compares as 0, so on a monitor whose tiled area ends left of the
          # origin — anything placed to the LEFT of the primary display, where
          # every x is negative — `hi` would stick at 0 and the width would come
          # out as -min(x). `lo` has the guard already; this is its other half.
          if (NR == 1 || $2 + $4 > hi) hi = $2 + $4 }
        END {
          for (i in x) for (j in x) if (i != j) {
            d = x[j] - (x[i] + w[i]); if (d > 0 && (g == 0 || d < g)) g = d
            d = y[j] - (y[i] + h[i]); if (d > 0 && (g == 0 || d < g)) g = d
          }
          printf "%d %d\n", hi - lo, g + 0
        }')

    starts=()
    start=0
    for k in "${counts[@]}"; do
        starts+=("$start")
        m=1
        while [ "$m" -lt "$k" ]; do
            if [ "$m" -eq 1 ]; then
                cmds="$cmds; join-with --window-id ${ids[$((start + 1))]} left"
            else
                cmds="$cmds; move --window-id ${ids[$((start + m))]} left"
            fi
            m=$((m + 1))
        done
        start=$((start + k))
    done

    # No measurement, no resize: a grid with equal columns is still a grid, and
    # guessing a width would put the windows somewhere nobody asked for.
    if [ "$cols" -gt 1 ] && [ "${width:-0}" -gt 100 ]; then
        content=$((width - (cols - 1) * gap))
        last=${counts[$((cols - 1))]}
        j=0
        while [ "$j" -lt $((cols - 1)) ]; do
            d=$(( content * (counts[j] - last) * (cols - 1) / (n * cols) ))
            # printf '%+d', never a bare "$d": `resize width <n>` takes an
            # UNSIGNED number as an ABSOLUTE width and only a signed one as a
            # delta. Every d here is negative today because `counts` is built
            # non-decreasing, so `last` is the widest and nothing needs to grow
            # — deal the columns tall-first instead and a bare "$d" would
            # quietly SET a column to 179 points rather than shrink it by that
            # much. Signed, the arithmetic stays true whatever the fill order.
            [ "$d" -ne 0 ] &&
                cmds="$cmds; resize --window-id ${ids[${starts[$j]}]} width $(printf '%+d' "$d")"
            j=$((j + 1))
        done
    fi
fi

# stderr is dropped because `layout --root h_tiles` prints a "already in the
# requested mode" tip (and exits 0) on a workspace that was already columns —
# every second press, on a keybinding nobody is reading a log for.
"$AEROSPACE" eval -- "$cmds" >/dev/null 2>&1

# Rewrite in place: this workspace's old line dropped, the new one appended, the
# whole thing trimmed from the FRONT so the most recently cycled workspaces are
# the ones that survive. Written through a temp file in the same directory so a
# reader (the bar, on its 2 s tick) never sees a half-written file.
tmp="$STATE.$$"
{
    awk -F'\t' -v ws="$ws" '$1 != ws' "$STATE" 2>/dev/null
    printf '%s\t%s\n' "$ws" "$next"
} | tail -n 32 >"$tmp" && mv "$tmp" "$STATE"

# Repaint the bar's tiling pill NOW rather than up to 2 s later on
# aerospace_watcher.sh's next tick. Same shape as the fullscreen keybinding's
# second command: the path to the menu bar's sketchybar is written in the bar's
# own tree and nowhere in this room.
notify="$HOME/.config/sketchybar/aerospace-notify.sh"
[ -x "$notify" ] && "$notify" tiling >/dev/null 2>&1 &

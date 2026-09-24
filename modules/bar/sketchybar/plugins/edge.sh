#!/bin/bash
# edge.sh <top|bottom> [init] — a bar's two side edges, per display.
#
# The bar's padding is the NARROWER of windows's two side gaps
# (modules/lib/gaps.nix; `barPadX` in ../../default.nix), because SketchyBar has
# one padding for every screen it draws on. The display class that wants more
# gets it from a spacer: `edge.left` / `edge.right`, the outermost item of each
# side group, background-less, $BAR_EDGE_EXTRA wide, and assigned (`display=`)
# only to the displays of class $BAR_EDGE_WIDE. So the outermost pill lands on
# the tiled window's edge on the built-in AND on an external, where one padding
# could only ever be right on one of them.
#
# Which display is which is answered the way windows answers it: by NAME.
# aerospace.toml keys the built-in's gaps on $BAR_EDGE_BUILTIN_NAME (the
# NSScreen name `hausdisp list` prints), so this matches the same string —
# anything else is an external. `sketchybar --query displays` gives the
# arrangement-id `display=` wants, and the UUID that joins it to hausdisp's row.
#
# The second job is the pill beside that spacer. Whichever pill is outermost
# gives up its outer padding (the bar's padding already IS the gap), and
# "outermost" is the first one DRAWN, not the first one added: when the head of
# a group hides (the agents pill with no lanes), the next pill's 4pt used to
# show at the edge. barlib's `pill` fires `haus_edge` when an edge-group widget
# repaints, and this re-picks the head.
#
# `init` runs synchronously from the rc, after every item exists and before
# anything has zeroed a padding: it records each edge pill's own outer padding
# (the number it goes back to when it stops being the head) in the cache, then
# does both jobs. Everything later reads that record, so a padding this script
# zeroed is never mistaken for the pill's own.

bar=${1:-top}
mode=${2:-}

source "$HOME/.config/sketchybar/bar.sh"
case "$bar" in
    bottom)
        SB="$BAR_BOTTOM"
        left_items="${BAR_EDGE_BOTTOM_LEFT:-}"
        right_items="${BAR_EDGE_BOTTOM_RIGHT:-}"
        ;;
    *)
        SB="$BAR_TOP"
        left_items=''
        right_items="${BAR_EDGE_TOP_RIGHT:-}"
        ;;
esac

cache_dir="$HOME/.cache/haus/bar"
cache="$cache_dir/edge.$bar"

drawing() { "$SB" --query "$1" 2>/dev/null | jq -r '.geometry.drawing // empty' 2>/dev/null; }

# init: one "<side> <drawn-item> <padded-item> <own padding>" line per edge pill,
# in the order SketchyBar packs them outward-in. A segmented pill is a bracket
# over its members: the BRACKET says whether it is drawn, the head member
# carries the padding (every member's is 0, see `segmented` in ../../default.nix).
record() {
    mkdir -p "$cache_dir"
    local side name draw pad tmp="$cache.tmp.$$"
    : >"$tmp"
    for side in left right; do
        # shellcheck disable=SC2086 # a space-separated item list, split on purpose
        if [ "$side" = left ]; then set -- $left_items; else set -- $right_items; fi
        for name in "$@"; do
            draw=$name
            if "$SB" --query "$name.pill" >/dev/null 2>&1; then draw="$name.pill"; fi
            pad=$("$SB" --query "$name" 2>/dev/null | jq -r ".geometry.background.padding_$side // 0" 2>/dev/null)
            echo "$side $draw $name ${pad:-0}" >>"$tmp"
        done
    done
    mv "$tmp" "$cache"
}

# The first drawn pill on each side gets 0, every other one its own padding
# back. One sketchybar call for the lot.
heads() {
    [ -f "$cache" ] || return 0
    local side draw name pad seen_left=0 seen_right=0 args=()
    while read -r side draw name pad; do
        [ -n "$name" ] || continue
        if [ "$side" = left ] && [ "$seen_left" = 0 ] && [ "$(drawing "$draw")" = on ]; then
            seen_left=1
            pad=0
        elif [ "$side" = right ] && [ "$seen_right" = 0 ] && [ "$(drawing "$draw")" = on ]; then
            seen_right=1
            pad=0
        fi
        args+=(--set "$name" "background.padding_$side=$pad")
    done <"$cache"
    if [ ${#args[@]} -gt 0 ]; then "$SB" "${args[@]}"; fi
}

# The spacers: drawn on the $BAR_EDGE_WIDE displays attached right now, off
# when there are none. If hausdisp can't answer, every display gets the spacer —
# the old single-padding behaviour, and the safe side of it (a pill inset
# further than the window reads as deliberate; one outboard of it looks broken).
spacers() {
    local extra="${BAR_EDGE_EXTRA:-0}" wide="${BAR_EDGE_WIDE:-}"
    if [ -z "$wide" ] || [ "$extra" = 0 ]; then
        "$SB" --set edge.left drawing=off --set edge.right drawing=off
        return 0
    fi
    local builtin_uuids listing ids='' aid uuid is_builtin
    listing=$(/run/current-system/sw/bin/hausdisp list 2>/dev/null)
    builtin_uuids=$(printf '%s\n' "$listing" \
        | grep -F "name=\"${BAR_EDGE_BUILTIN_NAME:-}\"" \
        | sed -n 's/.*uuid=\([^ ]*\).*/\1/p' | tr '\n' ' ')
    while read -r aid uuid; do
        [ -n "$aid" ] || continue
        if [ -z "$listing" ]; then
            ids="$ids${ids:+,}$aid"
            continue
        fi
        is_builtin=0
        case " $builtin_uuids " in *" $uuid "*) is_builtin=1 ;; esac
        if { [ "$wide" = builtin ] && [ "$is_builtin" = 1 ]; } \
            || { [ "$wide" = external ] && [ "$is_builtin" = 0 ]; }; then
            ids="$ids${ids:+,}$aid"
        fi
    done < <("$SB" --query displays 2>/dev/null | jq -r '.[] | "\(."arrangement-id") \(.UUID)"' 2>/dev/null)
    if [ -n "$ids" ]; then
        "$SB" --set edge.left drawing=on width="$extra" display="$ids" \
            --set edge.right drawing=on width="$extra" display="$ids"
    else
        "$SB" --set edge.left drawing=off --set edge.right drawing=off
    fi
}

case "$mode:${SENDER:-}" in
    init:*)
        # barlib's per-pill "last drawn" marks describe the bar before this
        # reload; clearing them makes every edge pill's first render report in,
        # rather than a stale "off" swallowing the flip after a reload.
        rm -f "$cache_dir"/*.drawn
        record
        spacers
        heads
        ;;
    *:haus_edge) heads ;;
    *)
        spacers
        heads
        ;;
esac

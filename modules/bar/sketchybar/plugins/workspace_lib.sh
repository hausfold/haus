#!/bin/bash
# workspace_lib.sh — what each workspace pill says, written ONCE. Sourced,
# never executed.
#
# A pill used to carry one bit: "something is here" (lit) or not (hidden). That
# bit was computed in three places — plugins/space.sh per pill, the watcher's
# batch, launch_mode.sh's disarm — each a hand copy of the other two, and none
# of them could tell one window from five, or a tiled window from a FLOATING one
# that had sunk behind the tiles. That last one is the case that made this file:
# AeroSpace's `floating` is a LAYOUT, not a stacking order, so a floating window
# on an occupied workspace vanishes behind the first tiled window you click, and
# nothing on screen says it still exists. haus can only PIN the popups it spawns
# itself (modules/terminal/floatpin.swift has the measurements); what the bar
# can do is notice, and hand you the way back.
#
# So every pill now reads what is ON it:
#
#   ●●○    one pip per window, from two windows up — filled for a tiled window,
#          hollow for one that is off the grid (floating, minimised, a hidden
#          app): the ones that can get lost. One window draws no pips; a lit
#          pill already says that much. Past six, the count as a number, with
#          the ring kept when any of them is loose.
#   ring   an outline on the pill of a workspace SHOWN on another display —
#          which, before this, simply vanished whenever it held nothing.
#
# and the `buried` pill beside the front app names the floating window you can
# no longer see, and raises it on a click (ws_buried_args, below).
#
# One snapshot per paint (ws_snapshot): four `aerospace` calls, ~10 ms each,
# and a `hausrect --visible` only when the focused workspace holds a floating
# window beside something that could cover it — which is almost never, so the
# common tick pays nothing for the feature.
#
# ⚠️ bash 3.2 (/bin/bash): no associative arrays, no `declare -g`, no `${x^^}`.
# The window table is a plain string walked with `while read`.
#
# Requires colors.sh (BASE, TEXT, SURFACE0, OVERLAY1, MAUVE, YELLOW) and
# sizes.sh (BAR_FONT, FS_TINY, FS_PIP) sourced first, and workspaces.sh for
# BAR_WS_WINDOWS / BAR_WS_BURIED.

WS_AEROSPACE="${WS_AEROSPACE:-/opt/homebrew/bin/aerospace}"
WS_HAUSRECT="${WS_HAUSRECT:-/run/current-system/sw/bin/hausrect}"
WS_US=$'\037'

# A window you can see less than this much of, in percent, is BURIED. A quarter
# is still a target you can click; less than that is a strip along an edge, and
# on a tiled desktop usually nothing at all.
WS_BURIED_BELOW=25

# ── the snapshot ─────────────────────────────────────────────────────────────
# WS_FOCUSED       the focused workspace (may be a page, `T/haus`)
# WS_FOCUSED_WIN   the focused window's id, empty on an empty workspace
# WS_FULLSCREEN    1 while that window is AeroSpace-fullscreen
# WS_VISIBLE       every workspace on screen, one per line (the focused one too)
# WS_WINDOWS       one line per window: ws US id US layout US app US title —
#                  the unit separator because a title is user text and may
#                  hold anything a tab or a pipe could be.
ws_snapshot() {
    WS_FOCUSED=$("$WS_AEROSPACE" list-workspaces --focused 2>/dev/null)
    local f
    f=$("$WS_AEROSPACE" list-windows --focused \
        --format "%{window-id}${WS_US}%{window-is-fullscreen}" 2>/dev/null)
    WS_FOCUSED_WIN=${f%%"$WS_US"*}
    WS_FULLSCREEN=0
    [ "${f#*"$WS_US"}" = true ] && WS_FULLSCREEN=1
    [ -n "$f" ] || WS_FOCUSED_WIN=""
    WS_VISIBLE=$("$WS_AEROSPACE" list-workspaces --monitor all --visible 2>/dev/null)
    WS_WINDOWS=$("$WS_AEROSPACE" list-windows --all \
        --format "%{workspace}${WS_US}%{window-id}${WS_US}%{window-layout}${WS_US}%{app-name}${WS_US}%{window-title}" \
        2>/dev/null)
    WS_BURIED=""
    WS_BURIED_READ=0
}

# ws_is_under <ws> <name> — is <name> the workspace <ws> itself or one of its
# pages? The slash rides in the prefix so `T` never claims `TT/x`.
ws_is_under() {
    [ "$2" = "$1" ] || [ "${2#"$1"/}" != "$2" ]
}

# ws_loose <layout> — 0 when the window is in the tiling tree. Everything else
# is off the grid: `floating`, and AeroSpace's `macos_native_*` states for a
# minimised window, a hidden app's, a native-fullscreen one.
ws_loose() {
    case "$1" in
        *tiles | *accordion) return 1 ;;
        *) return 0 ;;
    esac
}

# ws_count <ws> → WS_N_TILED, WS_N_LOOSE: the windows on the workspace AND its
# pages — the pill stands for both, exactly as its lit state always has.
ws_count() {
    local ws=$1 w id layout rest
    WS_N_TILED=0
    WS_N_LOOSE=0
    while IFS="$WS_US" read -r w id layout rest; do
        [ -n "$id" ] || continue
        ws_is_under "$ws" "$w" || continue
        if ws_loose "$layout"; then
            WS_N_LOOSE=$((WS_N_LOOSE + 1))
        else
            WS_N_TILED=$((WS_N_TILED + 1))
        fi
    done <<<"$WS_WINDOWS"
}

# ws_pips → WS_PIPS and WS_PIP_FONT, from the counts ws_count just left.
# Empty when there is nothing worth saying — one window, or the option off.
ws_pips() {
    local total=$((WS_N_TILED + WS_N_LOOSE)) i
    WS_PIPS=""
    WS_PIP_FONT="${BAR_FONT}:Bold:${FS_PIP:-10.0}"
    case "${BAR_WS_WINDOWS:-dots}" in
        off) return 0 ;;
    esac
    [ "$total" -ge 2 ] || return 0
    if [ "${BAR_WS_WINDOWS:-dots}" = count ] || [ "$total" -gt 6 ]; then
        WS_PIPS="$total"
        [ "$WS_N_LOOSE" -gt 0 ] && WS_PIPS="${WS_PIPS}○"
        WS_PIP_FONT="${BAR_FONT}:Bold:${FS_TINY:-12.0}"
        return 0
    fi
    for ((i = 0; i < WS_N_TILED; i++)); do WS_PIPS="${WS_PIPS}●"; done
    for ((i = 0; i < WS_N_LOOSE; i++)); do WS_PIPS="${WS_PIPS}○"; done
}

# ws_occupied <ws> — any window on it or its pages. Cheaper than ws_count for
# the callers that only need the bit.
ws_occupied() {
    local w rest
    while IFS="$WS_US" read -r w rest; do
        ws_is_under "$1" "$w" && return 0
    done <<<"$WS_WINDOWS"
    return 1
}

# ws_shown <ws> — on screen on ANOTHER display: the workspace or one of its
# pages is visible there.
ws_shown() {
    local v
    while IFS= read -r v; do
        [ -n "$v" ] && ws_is_under "$1" "$v" && return 0
    done <<<"$WS_VISIBLE"
    return 1
}

# ws_pill_args <ws> <active-colour> — append one pill's `--set` to WS_ARGS.
#
# Four states, and all four set EVERY property the others touch — label,
# paddings, border — because the pill is repainted from whatever state it was
# last in, and a property one state forgets is a property the previous state
# leaves standing.
ws_pill_args() {
    local ws=$1 active=$2 state
    if ws_is_under "$ws" "$WS_FOCUSED"; then
        state=focused
    elif ws_shown "$ws"; then
        state=shown
    elif ws_occupied "$ws"; then
        state=occupied
    else
        WS_ARGS+=(--set "space.$ws" drawing=off)
        return 0
    fi
    ws_count "$ws"
    ws_pips

    local bg=$SURFACE0 ink=$TEXT pipc=$OVERLAY1 border=0
    case "$state" in
        focused)
            bg=$active
            ink=$BASE
            # The pips are the pill's second reading, so they sit a step behind
            # its glyph: the same ink at two-thirds.
            pipc="0xaa${BASE#0x??}"
            ;;
        shown) border=2 ;;
    esac
    if [ -n "$WS_PIPS" ]; then
        WS_ARGS+=(--set "space.$ws" drawing=on
            background.color="$bg" background.border_width="$border"
            background.border_color="$MAUVE"
            icon.color="$ink" icon.padding_right=5
            label="$WS_PIPS" label.drawing=on label.color="$pipc"
            label.font="$WS_PIP_FONT" label.padding_left=0 label.padding_right=10)
    else
        WS_ARGS+=(--set "space.$ws" drawing=on
            background.color="$bg" background.border_width="$border"
            background.border_color="$MAUVE"
            icon.color="$ink" icon.padding_right=10
            label.drawing=off)
    fi
}

# ws_pills_args <active-colour> — every pill in WORKSPACES, in one go.
ws_pills_args() {
    local ws
    for ws in "${WORKSPACES[@]}"; do ws_pill_args "$ws" "$1"; done
}

# ── buried ───────────────────────────────────────────────────────────────────
# ws_buried → WS_BURIED: the floating windows on the FOCUSED workspace that you
# can see less than a quarter of, front-most first, one `id US app` per line.
#
# Only the focused workspace, because only its windows are on screen to be
# covered — AeroSpace parks every other workspace's windows in a screen corner,
# where they read as buried whatever they are. Only FLOATING ones, because a
# minimised window lives in the Dock and a hidden app on ⌘⇥, which both still
# show you where it went; a floating window behind a tile is the one with no
# trail at all. The focused window is never buried: it is the key window.
#
# Asked of hausrect only when there is something to ask: a floating window, and
# a second window that could be in front of it. Missing hausrect (the windows
# room off, or a generation mid-switch) means no answer, never a guess.
ws_buried() {
    [ "$WS_BURIED_READ" = 1 ] && return 0
    WS_BURIED_READ=1
    WS_BURIED=""
    [ -x "$WS_HAUSRECT" ] || return 0
    local w id layout app rest floats="" n=0 ids=""
    while IFS="$WS_US" read -r w id layout app rest; do
        [ "$w" = "$WS_FOCUSED" ] || continue
        n=$((n + 1))
        if [ "$layout" = floating ] && [ "$id" != "$WS_FOCUSED_WIN" ]; then
            floats="${floats}${id}${WS_US}${app}"$'\n'
            ids="$ids $id"
        fi
    done <<<"$WS_WINDOWS"
    [ -n "$ids" ] && [ "$n" -ge 2 ] || return 0
    local vid pct
    # shellcheck disable=SC2086 # ids are numbers AeroSpace printed
    while IFS=$'\t' read -r vid pct; do
        [ -n "$pct" ] && [ "$pct" -lt "$WS_BURIED_BELOW" ] 2>/dev/null || continue
        while IFS="$WS_US" read -r id app; do
            [ "$id" = "$vid" ] && WS_BURIED="${WS_BURIED}${id}${WS_US}${app}"$'\n'
        done <<<"$floats"
    done < <("$WS_HAUSRECT" --visible $ids 2>/dev/null)
    WS_BURIED=${WS_BURIED%$'\n'}
}

# ws_buried_args — append the `buried` pill's `--set` to WS_ARGS. The glyph is
# the app's own logo (sketchybar-app-font, the same face the workspace pills
# draw theirs in), yellow: `watch` on the tone ladder — worth knowing, nothing
# broken. The click raises the front-most one; a second is a `+1` and the next
# click.
ws_buried_args() {
    ws_buried
    if [ -z "$WS_BURIED" ]; then
        WS_ARGS+=(--set buried drawing=off)
        return 0
    fi
    local first=${WS_BURIED%%$'\n'*} n label
    local id=${first%%"$WS_US"*} app=${first#*"$WS_US"}
    n=$(printf '%s\n' "$WS_BURIED" | grep -c .)
    label=$app
    [ "$n" -gt 1 ] && label="$app +$((n - 1))"
    ws_app_glyph "$app"
    WS_ARGS+=(--set buried drawing=on
        icon="$WS_GLYPH" icon.color="$YELLOW"
        label="$label"
        click_script="$WS_AEROSPACE focus --window-id $id")
}

# ws_app_glyph <app-name> → WS_GLYPH: sketchybar-app-font's ligature for it
# (`:ghostty:`), `:default:` for an app the font has never heard of. The map
# ships inside the font's own package and is installed beside the rc, so the
# name and the glyph can never come from two versions.
ws_app_glyph() {
    if ! declare -F __icon_map >/dev/null 2>&1; then
        # shellcheck source=/dev/null
        [ -r "$HOME/.config/sketchybar/icon_map.sh" ] && . "$HOME/.config/sketchybar/icon_map.sh"
    fi
    WS_GLYPH=":default:"
    if declare -F __icon_map >/dev/null 2>&1; then
        icon_result=""
        __icon_map "$1"
        WS_GLYPH=${icon_result:-:default:}
    fi
}

#!/bin/bash
# barlib.sh — the bar widget runtime (docs/bar-framework.md). A framework
# widget sources this at the top, defines fetch()/render()/on_*() and calls
# `barlib_main "$@"` as its last line. Everything the old plugins had to know
# by hand lives here instead: which bar instance ($SB, via bar.sh), the
# drawing=off/updates=on pairing, tone→hex, state caching, and batching every
# component call into ONE sketchybar invocation.
#
# Runs under macOS /bin/bash (3.2): no declare -g, no ${var^^}, no
# associative arrays anywhere in this file.
#
# The contract:
#   fetch()   impure — gather the world, `emit key=value…` the result.
#   render()  pure — read the emitted state as shell variables, call
#             components (pill, sb_set). Runs ONLY when the state changed
#             since the last tick (or SENDER=forced), so a widget whose world
#             is quiet costs zero sketchybar traffic.
#   on_click / on_right_click / on_cmd_click / on_alt_click / on_shift_click /
#   on_ctrl_click / on_scroll — optional; mouse events route here and never
#   touch fetch or the cache.
#
# State values must be single-line: the cache is line-serialized, and a value
# with a newline in it would read back as a key that never matches. emit
# refuses those loudly rather than caching a diff that can never settle.

# The theme and the router. Guarded like ai-provider.sh's: a caller that
# already sourced either (a test harness, a widget run by hand in a shell
# that exported them) keeps its values.
[ -n "${FLAMINGO:-}" ] || source "$HOME/.config/sketchybar/colors.sh"
[ -n "${BAR_FONT:-}" ] || source "$HOME/.config/sketchybar/sizes.sh"
source "$HOME/.config/sketchybar/bar.sh"

# sketchybar exports $NAME to everything it spawns; a widget run by HAND (the
# debugging story: `BAR_ITEM=clock ./clock.sh`) has only the BAR_ITEM it set
# for bar.sh's routing, so fall back to that rather than --set an empty item.
[ -n "${NAME:-}" ] || NAME="${BAR_ITEM:-}"

_BARLIB_STATE=()
_BARLIB_ARGS=()

# ---- tones ------------------------------------------------------------------
# The semantic colour API — the ladder github.sh proved out, resolved to
# TONE_* exports the generated colors.sh carries (so nebelung stays the only
# resolver of names to hexes). Widgets name a tone, never a palette key and
# never a hex. An unknown tone is mute, not an error: a typo'd tone must cost
# a grey pill, never a pill that stops painting.
tone() {
    case "$1" in
        ok)     printf '%s' "$TONE_OK" ;;
        busy)   printf '%s' "$TONE_BUSY" ;;
        warn)   printf '%s' "$TONE_WARN" ;;
        bad)    printf '%s' "$TONE_BAD" ;;
        accent) printf '%s' "$TONE_ACCENT" ;;
        mute)   printf '%s' "$TONE_MUTE" ;;
        *)
            echo "barlib: unknown tone '$1' (mute|ok|busy|warn|bad|accent) — using mute" >&2
            printf '%s' "$TONE_MUTE"
            ;;
    esac
}

# ---- state ------------------------------------------------------------------
emit() {
    local kv key val
    for kv in "$@"; do
        key=${kv%%=*}
        val=${kv#*=}
        case "$key" in
            *[!A-Za-z0-9_]* | [0-9]* | '')
                echo "barlib: emit: '$kv' is not identifier=value — dropped" >&2
                continue
                ;;
        esac
        case "$val" in
            *$'\n'*)
                echo "barlib: emit: value of '$key' has a newline — dropped" >&2
                continue
                ;;
        esac
        _BARLIB_STATE+=("$kv")
    done
}

# ---- components -------------------------------------------------------------
# Every component ACCUMULATES into _BARLIB_ARGS; nothing talks to sketchybar
# until barlib_main applies the whole batch as one $SB call (the spawn tax is
# ~4 ms per invocation — twelve --sets ride one process, not twelve).

# The low-level escape: raw properties on this widget's own item. Fine to use
# for the odd knob a component doesn't cover; a widget leaning on it for
# everything is the signal a component is missing — file the gap.
sb_set() {
    _BARLIB_ARGS+=(--set "$NAME" "$@")
}

# pill --icon <glyph> --label <text> [--tone <tone>] [--label-tone <tone>]
#      [--hide]
# The standard readout. --hide performs the drawing=off/updates=on PAIR — the
# one-way door (a hidden item stops receiving events under the bars'
# updates=when_shown default) ceases to exist as a mistake a widget can make.
# An empty --icon means no icon (icon.drawing=off), not an invisible one.
pill() {
    local icon='' label='' icon_tone='' label_tone='' hide=0 have_icon=0 have_label=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --icon) icon=$2; have_icon=1; shift 2 ;;
            --label) label=$2; have_label=1; shift 2 ;;
            --tone) icon_tone=$2; shift 2 ;;
            --label-tone) label_tone=$2; shift 2 ;;
            --hide) hide=1; shift ;;
            *)
                echo "barlib: pill: unknown flag '$1' — dropped" >&2
                shift
                ;;
        esac
    done
    if [ "$hide" = 1 ]; then
        sb_set drawing=off updates=on
        return 0
    fi
    sb_set drawing=on
    if [ "$have_label" = 1 ]; then
        sb_set label="$label"
    fi
    if [ "$have_icon" = 1 ]; then
        if [ -n "$icon" ]; then
            sb_set icon="$icon" icon.drawing=on
        else
            sb_set icon.drawing=off
        fi
    fi
    if [ -n "$icon_tone" ]; then sb_set icon.color="$(tone "$icon_tone")"; fi
    if [ -n "$label_tone" ]; then sb_set label.color="$(tone "$label_tone")"; fi
    return 0
}

# ---- pubsub -----------------------------------------------------------------
# bar_emit <event> [key=value…] — fire a custom event. Both instances, always:
# "anything that pokes a bar pokes both" (AGENTS.md), as code. A bar that
# isn't running just eats the error.
bar_emit() {
    local event=$1
    shift
    "$BAR_TOP" --trigger "$event" "$@" 2>/dev/null || true
    if [ -n "${BAR_BOTTOM:-}" ]; then
        "$BAR_BOTTOM" --trigger "$event" "$@" 2>/dev/null || true
    fi
    return 0
}

# ---- dispatch ---------------------------------------------------------------
_barlib_click() {
    local handler=on_click
    case "${BUTTON:-}" in
        right) handler=on_right_click ;;
        other) handler=on_middle_click ;;
    esac
    case "${MODIFIER:-}" in
        cmd) handler=on_cmd_click ;;
        alt) handler=on_alt_click ;;
        shift) handler=on_shift_click ;;
        ctrl) handler=on_ctrl_click ;;
    esac
    # A chord nobody handled falls back to the plain click, and a widget with
    # no handlers at all swallows the click silently — same as a pill whose
    # click_script was never set.
    if ! declare -F "$handler" >/dev/null 2>&1; then handler=on_click; fi
    if declare -F "$handler" >/dev/null 2>&1; then "$handler"; fi
    return 0
}

_barlib_tick() {
    if ! declare -F fetch >/dev/null 2>&1; then
        # No fetch: an always-render widget. Legal, but it repaints every
        # tick — fine for a cheap render, wrong for one that forks.
        if declare -F render >/dev/null 2>&1; then render; fi
        return 0
    fi
    _BARLIB_STATE=()
    fetch || return 0

    local state=''
    if [ ${#_BARLIB_STATE[@]} -gt 0 ]; then
        state=$(printf '%s\n' "${_BARLIB_STATE[@]}" | LC_ALL=C sort)
    fi

    local cache_dir="$HOME/.cache/haus/bar"
    local cache="$cache_dir/${NAME:-unknown}.state"
    if [ "${SENDER:-}" != "forced" ] && [ -f "$cache" ] \
        && [ "$state" = "$(cat "$cache" 2>/dev/null)" ]; then
        return 0
    fi

    # The emitted state, as variables render can read. eval is safe here:
    # emit validated every key as a bare identifier, and the VALUE is passed
    # as a variable expansion, never re-parsed.
    local kv key val
    while IFS= read -r kv; do
        if [ -z "$kv" ]; then continue; fi
        key=${kv%%=*}
        val=${kv#*=}
        eval "$key=\$val"
    done <<<"$state"

    if declare -F render >/dev/null 2>&1; then render; fi
    mkdir -p "$cache_dir"
    printf '%s' "$state" >"$cache"
    return 0
}

# `if` statements rather than `&&` guards throughout: widgets are welcome to
# `set -e`, and a false `x && y` as a bare statement would end the script
# right there — before the batch below ever reaches the bar.
barlib_main() {
    case "${SENDER:-}" in
        mouse.clicked) _barlib_click ;;
        mouse.scrolled) if declare -F on_scroll >/dev/null 2>&1; then on_scroll; fi ;;
        mouse.entered) if declare -F on_hover >/dev/null 2>&1; then on_hover; fi ;;
        mouse.exited) if declare -F on_unhover >/dev/null 2>&1; then on_unhover; fi ;;
        *) _barlib_tick ;;
    esac
    if [ ${#_BARLIB_ARGS[@]} -gt 0 ]; then
        "$SB" "${_BARLIB_ARGS[@]}"
    fi
    return 0
}

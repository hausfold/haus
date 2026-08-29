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
#   on_click / on_right_click / on_middle_click / on_cmd_click /
#   on_alt_click / on_shift_click / on_ctrl_click / on_scroll / on_hover /
#   on_unhover — optional; mouse events route here and never touch fetch or
#   the cache. The button outranks the modifier (⌘-right-click is a right
#   click); an unhandled chord falls back to on_click.
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
# Emitted keys become shell VARIABLES in render's scope, so a key that names
# something the runtime itself lives on would clobber it — `emit state=busy`
# once corrupted the cache write and made the diff repaint every tick forever.
# The runtime keeps every internal name behind the _barlib/_BARLIB prefix and
# this list rejects the handful of environment names sketchybar and bar.sh
# hand us; everything else — `state`, `tone`, `label` included — is the
# widget's to use.
emit() {
    local _blib_kv _blib_key _blib_val
    for _blib_kv in "$@"; do
        _blib_key=${_blib_kv%%=*}
        _blib_val=${_blib_kv#*=}
        case "$_blib_key" in
            *[!A-Za-z0-9_]* | [0-9]* | '')
                echo "barlib: emit: '$_blib_kv' is not identifier=value — dropped" >&2
                continue
                ;;
            _barlib* | _BARLIB* | _blib* | NAME | BAR_ITEM | BAR_NAME | SENDER | BUTTON | MODIFIER | SB | BAR_TOP | BAR_BOTTOM | HOME | PATH | IFS)
                echo "barlib: emit: '$_blib_key' is a runtime name — dropped" >&2
                continue
                ;;
        esac
        case "$_blib_val" in
            *$'\n'*)
                echo "barlib: emit: value of '$_blib_key' has a newline — dropped" >&2
                continue
                ;;
        esac
        _BARLIB_STATE+=("$_blib_kv")
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
    # The button outranks the modifier: a right-click means the right-click
    # thing whatever the hand was holding (the weather pill's "right opens
    # the app" must not vanish under a stray ⌘). Modifier chords are a
    # left-button vocabulary.
    local handler=on_click
    case "${BUTTON:-}" in
        right) handler=on_right_click ;;
        other) handler=on_middle_click ;;
        *)
            case "${MODIFIER:-}" in
                cmd) handler=on_cmd_click ;;
                alt) handler=on_alt_click ;;
                shift) handler=on_shift_click ;;
                ctrl) handler=on_ctrl_click ;;
            esac
            ;;
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

    # Locals here wear the _blib prefix because the eval below writes the
    # WIDGET'S keys into this same dynamic scope — a bare `local state` would
    # be clobbered by `emit state=…` between the diff and the cache write.
    local _blib_state=''
    if [ ${#_BARLIB_STATE[@]} -gt 0 ]; then
        _blib_state=$(printf '%s\n' "${_BARLIB_STATE[@]}" | LC_ALL=C sort)
    fi

    # The skip is safe against a stale cache OUTLIVING the item only because
    # both rcs end with `--update`, which re-runs every script SENDER=forced
    # after each reload — and forced bypasses this check. Remove that line
    # from a rc and every framework pill comes back BLANK from a rebuild,
    # for as long as its state happens not to change.
    local _blib_cache_dir="$HOME/.cache/haus/bar"
    local _blib_cache="$_blib_cache_dir/${NAME:-unknown}.state"
    if [ "${SENDER:-}" != "forced" ] && [ -f "$_blib_cache" ] \
        && [ "$_blib_state" = "$(cat "$_blib_cache" 2>/dev/null)" ]; then
        return 0
    fi

    # The emitted state, as variables render can read. eval is safe here:
    # emit validated every key as a bare identifier outside the runtime's
    # reserved names, and the VALUE is passed as a variable expansion, never
    # re-parsed.
    local _blib_kv _blib_key _blib_val
    while IFS= read -r _blib_kv; do
        if [ -z "$_blib_kv" ]; then continue; fi
        _blib_key=${_blib_kv%%=*}
        _blib_val=${_blib_kv#*=}
        eval "$_blib_key=\$_blib_val"
    done <<<"$_blib_state"

    if declare -F render >/dev/null 2>&1; then render; fi
    mkdir -p "$_blib_cache_dir"
    printf '%s' "$_blib_state" >"$_blib_cache"
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

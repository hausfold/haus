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
#   popup_rows() optional — the dropdown's contents, in popup_heading /
#             popup_row / popup_action / popup_note calls. Never called on a
#             tick: popup_open runs it, which a click handler asks for.
#
# ⚠️ A WIDGET THAT DETACHES A COPY OF ITSELF must strip $SENDER (and $BUTTON /
# $MODIFIER) from the child's environment, and must not let that child reach
# barlib_main. The runtime routes on SENDER, the child inherits it, and a copy
# spawned from a click therefore re-enters the click handler that spawned it —
# an unbounded fork loop that no lock the widget holds can stop, because the
# parent has released them by then. github.sh's spawn_fetch is the worked
# example: `env -u SENDER -u BUTTON -u MODIFIER`, and a CLI mode that ends
# `barlib_tick; exit 0` rather than falling through.
#
# State values must be single-line: the cache is line-serialized, and a value
# with a newline in it would read back as a key that never matches. emit
# refuses those loudly rather than caching a diff that can never settle.

# The theme and the router. Guarded like ai-provider.sh's: a caller that
# already sourced either (a test harness, a widget run by hand in a shell
# that exported them) keeps its values.
#
# Every name read out of these two files below is read with a fallback, and
# that is not defensiveness for its own sake: barlib.sh, colors.sh and
# sizes.sh are three separate home.file entries, so a rebuild that adds a name
# to one of them lands it in some order, and under a widget's `set -u` an
# unset padding is not a misaligned icon — it is a pill that stops drawing
# until the next generation.
[ -n "${FLAMINGO:-}" ] || source "$HOME/.config/sketchybar/colors.sh"
[ -n "${BAR_FONT:-}" ] || source "$HOME/.config/sketchybar/sizes.sh"
source "$HOME/.config/sketchybar/bar.sh"

# sketchybar exports $NAME to everything it spawns; a widget run by HAND (the
# debugging story: `BAR_ITEM=clock ./clock.sh`) has only the BAR_ITEM it set
# for bar.sh's routing, so fall back to that rather than --set an empty item.
[ -n "${NAME:-}" ] || NAME="${BAR_ITEM:-}"

# A popup row's click_script that RE-ENTERS the widget (github's Refresh row)
# arrives with NAME set to the ROW's id, because sketchybar exports the item
# that was clicked. Every --set after that would land on a 25pt row instead of
# the pill — silently, since setting popup.drawing on a row is legal and does
# nothing. The row ids are the runtime's own (`<item>.popup.<n>`), so the
# runtime is exactly who can undo it.
case "${NAME:-}" in
    *.popup.*) NAME="${NAME%%.popup.*}" ;;
esac

_BARLIB_STATE=()
_BARLIB_ARGS=()

# ---- tones ------------------------------------------------------------------
# The semantic colour API. Widgets name a tone, never a palette key and never
# a hex; the names and what each resolves to are `modules/bar/tones.nix`, the
# generated colors.sh carries them as TONE_* exports (so nebelung stays the
# only resolver of names to hexes), and `bar-tones` in flake.nix diffs this
# case statement against that list. An unknown tone is mute, not an error: a
# typo'd tone must cost a grey pill, never a pill that stops painting — and
# that leniency is exactly why the check exists, since the warning below goes
# to sketchybar's log, where nobody looks.
#
# Read tones.nix for what each rung MEANS and which pills earned it. Three
# things about the shape of the ladder belong here, next to the code:
#
#   * TWO dim steps. `mute` (overlay0) is OFF — stale, inactive, absent.
#     `dim` (overlay1) is quiet but present — a heading, a row's name. Six
#     pills already use both as a hierarchy; one rung cannot say both, and a
#     widget with only `mute` can only ever get greyer.
#   * FOUR severity steps, not three: ok → watch → warn → bad. `watch` is
#     50% CPU and a battery at half — worth knowing, nothing to do yet.
#   * `action` is a thing you press, and it is NOT `accent`. accent follows
#     haus.theme.accent, whose enum contains red, peach, yellow, green and
#     sky — so on some machine accent IS the alarm, and a Refresh row wearing
#     it is unreadable there and nowhere else. accent is identity only.
# The arms are in the ladder's order, quietest first, and `bar-tones` pins
# that too — the doc table is meant to READ as the ladder, and an order that
# drifts is a table that has stopped being one. The check pins each arm's
# TONE_* as well as its name, because swapping two `printf` bodies inverts the
# severity ladder while leaving the list of names byte-identical.
#
# ⚠️ Every rung whose TONE_* is NEWER than barlib.sh itself falls back with
# `:-`, and that is the file header's rule at the top rather than caution:
# colors.sh and this file are separate home.file entries, so a rebuild lands
# them in some order and there is a window where a widget under `set -u`
# reads a TONE_* the live colors.sh has never heard of. Not a wrong colour —
# an unbound-variable abort that takes the whole batched --add with it, and
# `dim` and `action` are the DEFAULTS for popup_heading and popup_action, so
# every framework popup would be in it. Each falls back to the rung it
# replaced, which is also what it looked like one generation ago.
tone() {
    case "$1" in
        mute)   printf '%s' "$TONE_MUTE" ;;
        dim)    printf '%s' "${TONE_DIM:-$TONE_MUTE}" ;;
        text)   printf '%s' "${TONE_TEXT:-$TEXT}" ;;
        ok)     printf '%s' "$TONE_OK" ;;
        busy)   printf '%s' "$TONE_BUSY" ;;
        watch)  printf '%s' "${TONE_WATCH:-$TONE_WARN}" ;;
        warn)   printf '%s' "$TONE_WARN" ;;
        bad)    printf '%s' "$TONE_BAD" ;;
        action) printf '%s' "${TONE_ACTION:-$TONE_ACCENT}" ;;
        accent) printf '%s' "$TONE_ACCENT" ;;
        *)
            echo "barlib: unknown tone '$1' (mute|dim|text|ok|busy|watch|warn|bad|action|accent) — using mute" >&2
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

# Apply everything accumulated so far, as one call, and empty the batch.
# barlib_main calls this last; popup_open calls it early because barpop has to
# arm against rows that already exist. Calling it twice is harmless — the
# second finds nothing to send.
_barlib_flush() {
    if [ ${#_BARLIB_ARGS[@]} -gt 0 ]; then
        "$SB" "${_BARLIB_ARGS[@]}"
        _BARLIB_ARGS=()
    fi
    return 0
}

# pill --icon <glyph> --label <text> [--tone <tone>] [--label-tone <tone>]
#      [--hide]
# The standard readout, one or two tones: --tone paints the icon and
# --label-tone the label, which is the whole of the "two-tone pill" — the
# octocat saying how BAD while the number says how MANY. There is no separate
# component for it; passing both flags is it.
#
# --hide performs the drawing=off/updates=on PAIR — the one-way door (a hidden
# item stops receiving events under the bars' updates=when_shown default)
# ceases to exist as a mistake a widget can make.
#
# EMPTY MEANS ABSENT, for both halves. An empty --icon is icon.drawing=off,
# not an invisible glyph; an empty --label is label.drawing=off, and it also
# re-centres the icon. That second half is why the rule is the runtime's: the
# bar's --default padding is 8/4 on the icon and 4/8 on the label, which reads
# centred while both are drawn and visibly left-heavy the moment the label
# goes away — which for a pill that hides a zero is its RESTING state. A
# widget that toggles its label would have to know those four numbers, and
# the one that did (github) is where they came from.
#
# The padding is only written when a widget passes BOTH flags, i.e. when it is
# a pill that can lose its label. A widget with custom padding in its Nix
# style keeps it otherwise, and can take it back either way with an sb_set
# after the pill call — later --set args in the batch win.
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
        if [ -n "$label" ]; then
            sb_set label="$label" label.drawing=on
        else
            sb_set label.drawing=off
        fi
    fi
    if [ "$have_icon" = 1 ]; then
        if [ -n "$icon" ]; then
            sb_set icon="$icon" icon.drawing=on
        else
            sb_set icon.drawing=off
        fi
    fi
    if [ "$have_icon" = 1 ] && [ "$have_label" = 1 ]; then
        if [ -n "$icon" ] && [ -z "$label" ]; then
            sb_set icon.padding_left="${PAD_ICON_SOLO:-10}" icon.padding_right="${PAD_ICON_SOLO:-10}"
        else
            sb_set icon.padding_left="${PAD_ICON_L:-8}" icon.padding_right="${PAD_ICON_R:-4}"
        fi
    fi
    if [ -n "$icon_tone" ]; then sb_set icon.color="$(tone "$icon_tone")"; fi
    if [ -n "$label_tone" ]; then sb_set label.color="$(tone "$label_tone")"; fi
    return 0
}

# A percentage as sketchybar's graph wants it: 0…1, two decimals, clamped. A
# pushed value is drawn against the item's height with NO scaling of its own,
# so anything over 1 is drawn off the top of the pill and anything negative
# vanishes — neither of which looks like an error, which is why both are
# handled here rather than trusted from a widget.
_barlib_fraction() {
    awk -v p="${1:-0}" 'BEGIN {
        v = p / 100
        if (v < 0) v = 0
        if (v > 1) v = 1
        printf "%.2f", v
    }'
}

# graph <percent> — push one point onto the rolling window behind the label.
# Only for a widget whose header carries `graph = <width>`; on a plain item
# the push is accepted and drawn nowhere.
#
# ⚠️ CALL IT FROM fetch, NOT render. That is the one place the framework's own
# fetch/render split does not hold, and it is structural rather than a style
# note:
#
#   * render is DIFFED. A machine sitting at 3% emits identical state tick
#     after tick, render never runs, and a graph pushed from there would stop
#     advancing for exactly as long as nothing is happening — the flat line
#     would mean "quiet" and "stalled" at once, and the pill has no way to say
#     which. The window is `width × interval` seconds only if every tick
#     contributes a point.
#   * fetch does not run on a click at all — SENDER routes a mouse event
#     straight to its handler. The graph has no time axis of its own (it is
#     the last <width> values, evenly spaced), so a point pushed by the
#     POINTER would shove the history sideways at the speed of a mouse. Under
#     the old hand-written cpu pill that was a real bug and a guard; through
#     the runtime's own dispatch it is unreachable.
#
#     ⚠️ ONE handler can still reach it: barlib_tick runs fetch, which is the
#     whole point of it (github's Refresh row). A graph widget that offers a
#     refresh gesture is therefore back to pushing a point from the pointer —
#     have that handler do its work and let the next tick draw it, or accept
#     that the row is worth a data point.
#
# A graph pill costs one $SB call per tick even when the state is unchanged:
# the push IS the traffic, where a quiet non-graph pill sends nothing at all.
# That is the same one call the hand-written pill made, so it is a price
# already being paid rather than a new one — but it is a price, and the
# zero-traffic promise in this file's header is about widgets that do not
# push.
graph() {
    _BARLIB_ARGS+=(--push "$NAME" "$(_barlib_fraction "${1:-0}")")
    return 0
}

# ---- the dropdown -----------------------------------------------------------
# A widget declares its rows in popup_rows() and opens them with popup_open /
# popup_close / popup_toggle from a click handler. The runtime owns everything
# that used to be copied between pills: the --remove of the old rows, the
# per-row item ids, the one batched --add, the popup.drawing flip, and handing
# the result to barpop so the popup also closes on the first click ANYWHERE
# else (SketchyBar hears clicks on its own items and nothing else).
#
# FOUR ROW KINDS, and their typography is the runtime's, not the widget's:
#
#   popup_heading   a section title.      Bold, label size,   32pt tall
#   popup_row       a thing you can act on. Regular, small,   25pt
#   popup_action    a verb — Refresh, a command to copy. Bold, small, 25pt
#   popup_note      an aside — "nothing", "+4 more".  Italic, tiny, 20pt
#
# Four because that is what every popup in this bar already is; a widget
# naming ":Bold:${FS_SMALL}" itself is the hardcoded-hex mistake one layer up,
# and the fifth kind someone needs is a kind to add here rather than a --font
# to add to the signature.
#
# The three label colours below ARE palette keys rather than tones, and that
# is the line: TEXT/SUBTEXT0/OVERLAY0 are a reading hierarchy the runtime
# lays out with, the way it picks the fonts. Tones are what a WIDGET names,
# and a widget still only ever names one — the icon's.
_BARLIB_POP_I=0
_BARLIB_H_HEADING=32
_BARLIB_H_ROW=25
_BARLIB_H_NOTE=20
# A value row sits UNDER a heading, so it is indented past the heading's own
# 10 rather than sharing its left edge.
_BARLIB_ROW_INDENT=22

# ---- the value column -------------------------------------------------------
# A row that carries a NUMBER is two columns, not one sentence: a name on the
# left and a value that has to land on the same x as the value in every row
# above it. Getting that wrong is the one dropdown flaw you see immediately,
# so the arithmetic is the runtime's — the same reason the four row kinds own
# their fonts.
#
# The gap is a PIXEL PADDING derived from the monospace advance, never
# trailing spaces: sketchybar sizes an item from its TRIMMED label and then
# draws the untrimmed string, so a space-padded row is a row clipped by
# exactly the width of its own padding.
_BARLIB_COL_NAME=16   # widest name column before a value starts sliding right
_BARLIB_COL_GAP=12
_BARLIB_ADV=602       # mono advance per point, ×1000

# _barlib_name_pad <name> <extra-columns> <font-size> — the icon padding that
# lands every value on one column. A name longer than the column gets the
# minimum gap and pushes its own value right; that is one ragged row rather
# than a dropdown sized for the worst name on the machine.
#
# <extra-columns> is for what bash cannot measure — a Nerd Font glyph riding
# in the same slot, which `${#s}` counts as three bytes in the C locale a bar
# plugin inherits and as one character anywhere else. Two columns, named by
# the caller, beats a length that changes with $LANG.
#
# The advance is measured with awk, not bash arithmetic, because a font size
# out of the generated sizes.sh is a DECIMAL ("14.0") and $(( )) errors on
# one. It is cached against the size it was measured at, so a dropdown of a
# heading plus twelve rows forks awk twice rather than thirteen times — a
# popup is built inside a click, where the whole batch is one message and the
# forks would be the only thing in it that isn't.
_BARLIB_ADV_FOR=''
_BARLIB_ADV_PX=''
_barlib_name_pad() {
    local cols
    cols=$((_BARLIB_COL_NAME - ${#1} - ${2:-0}))
    if [ "$cols" -lt 1 ]; then cols=1; fi
    if [ "${3:-13}" != "$_BARLIB_ADV_FOR" ]; then
        _BARLIB_ADV_PX=$(awk -v s="${3:-13}" -v a="$_BARLIB_ADV" 'BEGIN { printf "%.0f", s * a }')
        _BARLIB_ADV_FOR="${3:-13}"
    fi
    printf '%s' $(((cols * _BARLIB_ADV_PX + _BARLIB_COL_GAP * 1000 + 500) / 1000))
}

# popup_quote <value> — single-quote a value for embedding in a click_script.
# A row's URL or copy text is DATA — a PR title with an apostrophe in it must
# not end the quote and hand the rest to the shell.
#
# `--run` deliberately does not go through this: it is a whole command, and
# quoting it would break it. That is exactly why this is PUBLIC rather than a
# `_barlib_` internal — a widget that builds a `--run` out of a fixed binary
# and some fetched data (github's "Fix with AI" rows: a branch name and a URL,
# both GitHub's to choose) has to quote the data half itself, and the
# alternative to lending it this one is every such widget writing its own sed.
popup_quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# One row. Every row closes the popup when clicked — a dropdown you have to
# dismiss separately from acting on it is a dropdown you dismiss by mistake —
# so `action` is prepended to that close rather than replacing it.
_barlib_pop_add() { # _barlib_pop_add <height> <font> <action> <set-args…>
    local height=$1 font=$2 action=$3
    shift 3
    local close="$SB --set $NAME popup.drawing=off"
    local click="$close"
    if [ -n "$action" ]; then click="$action; $close"; fi
    _BARLIB_ARGS+=(
        --add item "${NAME}.popup.${_BARLIB_POP_I}" "popup.${NAME}"
        --set "${NAME}.popup.${_BARLIB_POP_I}"
        icon="" icon.padding_left=10 icon.padding_right=8
        label="" label.padding_left=0 label.padding_right=14
        label.font="$font"
        background.drawing=off background.height="$height"
        click_script="$click"
        "$@"
    )
    _BARLIB_POP_I=$((_BARLIB_POP_I + 1))
}

# popup_heading --label <text> [--icon <glyph>] [--tone <tone>] [--count <n>]
# --count appends " · n" when n is above zero: a section that says "open PRs"
# over eight rows leaves you counting them to find out whether eight is all of
# them, and the rows below may be a truncation.
# The default is `dim`, not `mute`: a section title with no verdict of its own
# is still a title. Every hand-written popup in this bar already draws one that
# way — vitals_lib, agents, calendar and ai_usage all paint the section glyph
# overlay1 and reserve overlay0 for the meta row under it — and `mute` here
# made the heading read as absent rather than quiet.
popup_heading() {
    local label='' icon='' icon_tone=dim count=0 value='' have_value=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --label) label=$2; shift 2 ;;
            --icon) icon=$2; shift 2 ;;
            --tone) icon_tone=$2; shift 2 ;;
            --count) count=$2; shift 2 ;;
            --value) value=$2; have_value=1; shift 2 ;;
            *) echo "barlib: popup_heading: unknown flag '$1' — dropped" >&2; shift ;;
        esac
    done
    case "$count" in '' | *[!0-9]*) count=0 ;; esac
    if [ "$count" -gt 0 ]; then label="$label · $count"; fi
    if [ "$have_value" = 1 ]; then
        # Glyph and title travel TOGETHER in the icon, in ONE tone: they are
        # the same mark, and splitting them across the row's two colourable
        # halves would spend the value's colour on a word. That tone is the
        # heading's `dim` unless the widget says otherwise — the ladder has no
        # rung for a pill's own identity hue, deliberately, so a converted
        # pill's dropdown title is grey where a hand-written one was often the
        # pill's colour. The
        # value then lands on the column every row below it uses, so the
        # heading reads as the total of what follows rather than as a caption
        # sitting above it.
        local _blib_name="$label" _blib_cols=0
        if [ -n "$icon" ]; then
            _blib_name="$icon $label"
            _blib_cols=2
        fi
        _barlib_pop_add "$_BARLIB_H_HEADING" "${BAR_FONT:-}:Bold:${FS_LABEL:-}" '' \
            icon="$_blib_name" icon.color="$(tone "$icon_tone")" \
            icon.font="${BAR_FONT:-}:Bold:${FS_LABEL:-}" \
            icon.padding_left=10 \
            icon.padding_right="$(_barlib_name_pad "$label" "$_blib_cols" "${FS_LABEL:-13}")" \
            label="$value" label.color="${TEXT:-}"
        return 0
    fi
    _barlib_pop_add "$_BARLIB_H_HEADING" "${BAR_FONT:-}:Bold:${FS_LABEL:-}" '' \
        icon="$icon" icon.color="$(tone "$icon_tone")" \
        label="$label" label.color="${TEXT:-}"
}

# popup_row --label <text> [--icon <glyph>] [--tone <tone>]
#           [--open <url>] [--run <command>]
# A `mute` row loses a shade of its TEXT too, not only its glyph colour:
# otherwise a list of eight reads as eight equal claims on you when two of
# them are their author saying "not yet". Only `mute` — a `dim` row keeps its
# full-brightness label on purpose, because dim is the row still being ABOUT
# something; it is the glyph that is subordinate, not the sentence.
popup_row() {
    local label='' icon='' icon_tone=mute action='' value='' have_value=0 tone_set=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --label) label=$2; shift 2 ;;
            --icon) icon=$2; shift 2 ;;
            --tone) icon_tone=$2; tone_set=1; shift 2 ;;
            --value) value=$2; have_value=1; shift 2 ;;
            --open) action="/usr/bin/open $(popup_quote "$2")"; shift 2 ;;
            --run) action=$2; shift 2 ;;
            *) echo "barlib: popup_row: unknown flag '$1' — dropped" >&2; shift ;;
        esac
    done
    if [ "$have_value" = 1 ]; then
        # ⚠️ With a --value the tone follows the NUMBER, not the glyph. That is
        # the row saying which half carries the verdict: the name is the
        # question ("user", "load", "Safari") and is always dim, the value is
        # the answer and is the only thing on the ladder. A two-column row
        # whose name climbed to `bad` with it would be one row shouting twice.
        # `text` is the default rather than `mute`, because a measurement with
        # no verdict is a live readout, not an absence.
        if [ "$tone_set" = 0 ]; then icon_tone=text; fi
        local _blib_name="$label" _blib_cols=0
        if [ -n "$icon" ]; then
            _blib_name="$icon $label"
            _blib_cols=2
        fi
        _barlib_pop_add "$_BARLIB_H_ROW" "${BAR_FONT:-}:Bold:${FS_SMALL:-}" "$action" \
            icon="$_blib_name" icon.color="$(tone dim)" \
            icon.font="${BAR_FONT:-}:Regular:${FS_SMALL:-}" \
            icon.padding_left="$_BARLIB_ROW_INDENT" \
            icon.padding_right="$(_barlib_name_pad "$label" "$_blib_cols" "${FS_SMALL:-12}")" \
            label="$value" label.color="$(tone "$icon_tone")"
        return 0
    fi
    local lcolor="${SUBTEXT0:-}"
    if [ "$icon_tone" = mute ]; then lcolor="${OVERLAY0:-}"; fi
    _barlib_pop_add "$_BARLIB_H_ROW" "${BAR_FONT:-}:Regular:${FS_SMALL:-}" "$action" \
        icon="$icon" icon.color="$(tone "$icon_tone")" \
        label="$label" label.color="$lcolor"
}

# popup_action --label <text> [--icon <glyph>] [--tone <tone>]
#              [--run <command>] [--copy <text>]
# The verb row. --copy exists because the useful answer is often a command
# you have to run somewhere with a terminal in front of it: `gh auth login`
# wants a browser, a protocol choice and a paste-back code, and there is no
# shell behind a bar popup to give it any of that.
#
# It defaults to `action`, and defaulting to `accent` was a real bug rather
# than a shade: accent follows haus.theme.accent, an enum of fourteen names
# that includes red, peach, yellow, green and sky, so on those machines every
# verb row in every framework popup was painted the same colour as the alarm
# — and `haus.theme.accent`'s own doc promises the logo is the ONLY pill that
# follows it. A row you press is a fixed sapphire on every machine.
popup_action() {
    local label='' icon='' icon_tone=action action=''
    while [ $# -gt 0 ]; do
        case "$1" in
            --label) label=$2; shift 2 ;;
            --icon) icon=$2; shift 2 ;;
            --tone) icon_tone=$2; shift 2 ;;
            --run) action=$2; shift 2 ;;
            --copy) action="printf '%s' $(popup_quote "$2") | pbcopy"; shift 2 ;;
            *) echo "barlib: popup_action: unknown flag '$1' — dropped" >&2; shift ;;
        esac
    done
    _barlib_pop_add "$_BARLIB_H_ROW" "${BAR_FONT:-}:Bold:${FS_SMALL:-}" "$action" \
        icon="$icon" icon.color="$(tone "$icon_tone")" \
        label="$label" label.color="${SUBTEXT0:-}"
}

# popup_note --label <text> — the aside. No icon, no click of its own.
popup_note() {
    local label=''
    while [ $# -gt 0 ]; do
        case "$1" in
            --label) label=$2; shift 2 ;;
            *) echo "barlib: popup_note: unknown flag '$1' — dropped" >&2; shift ;;
        esac
    done
    _barlib_pop_add "$_BARLIB_H_NOTE" "${BAR_FONT:-}:Italic:${FS_TINY:-}" '' \
        icon="" label="$label" label.color="${OVERLAY0:-}"
}

# Is the dropdown up? `nil` for an item the bar could not answer about — the
# same distinction barpop's own gate draws, and for the same reason: an
# unanswered --query is not a closed popup, and treating it as one reopens a
# dropdown the user was closing.
_barlib_popup_drawing() {
    local ans
    ans=$("$SB" --query "$NAME" 2>/dev/null | jq -r '.popup.drawing // empty' 2>/dev/null)
    printf '%s' "$ans"
}

popup_close() {
    sb_set popup.drawing=off
    return 0
}

# Rebuild and show. The --remove goes out on its own, ahead of the batch: the
# adds below reuse the ids it is clearing, and the two cannot be reordered by
# being in one call.
#
# The batch is FLUSHED here rather than at the end of barlib_main, because
# barpop reads the popup's row rects at arm time — arming before the rows
# exist would guard a popup of the wrong shape.
popup_open() {
    "$SB" --remove "/${NAME}\.popup\..*/" 2>/dev/null
    _BARLIB_POP_I=0
    if declare -F popup_rows >/dev/null 2>&1; then popup_rows; fi
    sb_set popup.drawing=on
    _barlib_flush
    SKETCHYBAR_BIN="$SB" /run/current-system/sw/bin/barpop arm "$NAME" 2>/dev/null &
    return 0
}

# Closing is JUST hiding: a click while the popup is up must not rebuild the
# rows first, or closing it flashes through a re-layout on the way out.
popup_toggle() {
    if [ "$(_barlib_popup_drawing)" = "on" ]; then
        popup_close
    else
        popup_open
    fi
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

# barlib_tick — run fetch/diff/render now. For a handler (or a CLI mode) that
# just changed the world and wants the pill to say so without waiting out the
# interval. Still DIFFED, deliberately: a refresh that turns up the same
# numbers should cost nothing, and a pill that repaints on every click is a
# pill that flickers on every click.
barlib_tick() {
    _barlib_tick
    # Flushes, unlike the internal it wraps: a widget's CLI mode calls this and
    # then exits without reaching barlib_main, and a batch nobody sends is a
    # pill that silently did not repaint. Calling it inside a handler is still
    # fine — barlib_main's own flush then finds nothing left to send.
    _barlib_flush
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
    _barlib_flush
    return 0
}

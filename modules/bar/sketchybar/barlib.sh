#!/bin/bash
# barlib.sh — the bar widget runtime. Its design is written up in
# `todo/bar-framework.md` in hausfold/ops, which is private; this file and its
# comments are the normative half, and `plugins/clock.sh` is the smallest
# widget written against it.
#
# A framework widget sources this at the top, defines fetch()/render()/on_*()
# and calls `barlib_main "$@"` as its last line. Everything the old plugins had
# to know by hand lives here instead: which bar instance ($SB, via bar.sh), the
# drawing=off/updates=on pairing, tone→hex (tone() and mark() ride the
# generated colors.sh this file sources), state caching, and batching every
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
#             popup_row / popup_action / popup_note / popup_slider /
#             popup_image calls. Never called on a tick: popup_open runs it,
#             which a click handler asks for.
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
#
# And who can hand it back: $POPUP_CLICKED keeps the id the strip removed, for
# the one row that CHANGES ITSELF on a click instead of acting and closing.
# That is the slider — sketchybar does not move a knob on a click of its own
# accord, so the seek handler has to, and it is running in a fresh process
# whose only evidence of which row it belongs to is the NAME this line ate.
# Empty on every other entry, which is what `popup_set` checks.
#
# A plain global rather than an export: barlib is SOURCED into the widget's
# shell, and exporting would hand the id down to every child that widget
# spawns — including another row's click_script, which belongs to a different
# row. Read by widgets only, hence the disable.
POPUP_CLICKED=''
# shellcheck disable=SC2034
case "${NAME:-}" in
    *.popup.*)
        POPUP_CLICKED="$NAME"
        NAME="${NAME%%.popup.*}"
        ;;
esac

# ---- segmented pills: which item is the widget, and which holds the popup ----
# A pill whose header carries `segments =` is a BRACKET over N+1 items
# (modules/bar/manifest.nix). The running script has to know that, and it
# learns it from THE SAME HEADER the emitter reads — parsed out of $0, the
# widget's own file, because barlib is SOURCED and so $0 is the widget.
#
# ⚠️ It is read from the file rather than handed over on the command line, and
# that is not a preference. A script= and a click_script= are the only two
# argv sketchybar controls, and they are not the only ways this widget runs:
# agents-hook.sh invokes the reader DIRECTLY (`SENDER=refresh NAME=agents`)
# on every agent state change, and that push path is how the agents pill
# learns almost everything. A variable that rode the command line would be
# absent exactly there — every `segment` call dropped, the bracket left
# undrawn, and `_barlib_tick` writing the new state to the cache anyway, so
# the next tick would find no diff and never repaint. The counts would freeze
# until a reload. The header travels with the file, so it reaches every
# caller.
#
# Nix validates, the shell reads: manifest.nix refuses a bad `segments =` at
# EVAL, so anything that gets this far has already passed. $BARLIB_SEGMENTS
# stays as an override for a harness (test/barlib.bats sets it) and for a
# by-hand run of a file whose header you want to ignore.
# `mark = <name>` rides the same read: the widget's own hue on the identity
# axis (modules/bar/marks.nix), which is what its dropdown headings wear when
# they name no tone of their own. Validated by manifest.nix at eval, so a name
# that reaches here is one mark() resolves; $BARLIB_MARK is the harness
# override, exactly as $BARLIB_SEGMENTS is.
if { [ -z "${BARLIB_SEGMENTS:-}" ] || [ -z "${BARLIB_MARK:-}" ]; } && [ -n "${0:-}" ] && [ -r "${0:-}" ]; then
    _blib_hdr=$(sed -n \
        -e 's/^#[[:space:]]*widget:[[:space:]]*segments[[:space:]]*=[[:space:]]*/segments=/p' \
        -e 's/^#[[:space:]]*widget:[[:space:]]*mark[[:space:]]*=[[:space:]]*/mark=/p' "$0")
    # Word-splitting is the whitespace normaliser — one space between names,
    # none at either end, no fork — and it happens inside a function on
    # purpose: this file is SOURCED, so a `set --` up here would overwrite the
    # widget's own argv, and github's `refresh`/`fetch` CLI modes read $1
    # after the source.
    _barlib_words() { _BARLIB_WORDS="$*"; }
    while IFS= read -r _blib_line; do
        case "$_blib_line" in
            segments=*)
                if [ -z "${BARLIB_SEGMENTS:-}" ]; then
                    _blib_v=${_blib_line#segments=}
                    # shellcheck disable=SC2086
                    _barlib_words ${_blib_v//,/ }
                    BARLIB_SEGMENTS="$_BARLIB_WORDS"
                fi
                ;;
            mark=*)
                if [ -z "${BARLIB_MARK:-}" ]; then
                    # shellcheck disable=SC2086
                    _barlib_words ${_blib_line#mark=}
                    BARLIB_MARK="${_BARLIB_WORDS%% *}"
                fi
                ;;
        esac
    done <<<"$_blib_hdr"
    unset _blib_hdr _blib_line _blib_v
fi
# Two ids have to come back to the head, and both arrive as $NAME because
# sketchybar exports whichever item was actually touched:
#
#   * a SEGMENT's click_script — `agents.ready`. Stripped by name rather than
#     at the first dot, because the head's own id may contain one and a blind
#     `%%.*` would turn `media_lib.foo` into `media_lib`. The list is exact,
#     so the strip is exact.
#   * a popup ROW on a segmented pill — `agents.pill.popup.3`. The `.popup.*`
#     strip above leaves `agents.pill`, one suffix short, because the rows
#     hang off the BRACKET here rather than off the head.
#
# The popup owner is then the bracket, and every popup_* below addresses it
# instead of $NAME. A widget never says either name: it calls `popup_open`
# and the runtime knows where its dropdown lives.
_BARLIB_POPUP="$NAME"
if [ -n "${BARLIB_SEGMENTS:-}" ]; then
    case "$NAME" in
        *.pill) NAME="${NAME%.pill}" ;;
        *)
            for _blib_seg in $BARLIB_SEGMENTS; do
                case "$NAME" in
                    *".$_blib_seg")
                        NAME="${NAME%".$_blib_seg"}"
                        break
                        ;;
                esac
            done
            ;;
    esac
    unset _blib_seg
    _BARLIB_POPUP="${NAME}.pill"
fi

_BARLIB_STATE=()
_BARLIB_ARGS=()

# ---- tones & marks ----------------------------------------------------------
# The semantic colour API. Widgets name a TONE ("how is it going" — the
# ladder, quietest first: mute dim text ok busy watch warn bad action accent)
# or a MARK ("which one is this" — warm rust pink violet blue teal plum),
# never a palette key and never a hex. `--tone` is the only thing that may
# carry a VERDICT, and where a component takes both the two flags are
# last-wins on purpose — `--mark warm --tone mute` is how a widget greys out
# a block whose feed died without losing the mark it would draw when the
# feed comes back.
#
# tone() and mark() themselves arrive from colors.sh, sourced above.
# `modules/bar/tones.nix` and `modules/bar/marks.nix` are the two
# vocabularies and the whole argument (what each rung means, which pills
# earned it, why nothing carrying meaning may name `accent`), and
# `modules/bar/colors-fns.nix` emits both functions into the generated file
# right after the TONE_*/MARK_* exports they read — so a rung lives in one
# data file, and the functions can never skew against the exports they ride
# with. Both are lenient the same way: an unknown tone warns and paints
# mute, an unknown mark warns and paints plum (grey means STALE, and an
# unrecognised subject is reporting perfectly well) — a typo must cost the
# wrong hue, never a pill that stops painting. The warning goes to
# sketchybar's log, where nobody looks; `bar-tones` and `bar-marks` in
# flake.nix exist because of exactly that, pinning the two copies that still
# live outside the generation (test/barlib.bats's stub exports, and
# test/colors-fns.sh — the committed copy of the emitted functions the
# suite runs against).
#
# The guards below are for a shell that reached here without them: a by-hand
# run whose environment already carried the palette (FLAMINGO set skips the
# source at the top, and functions, unlike exports, never ride the
# environment) — one more read of the live file is what fixes that — or the
# one colors.sh that genuinely predates the functions, the generation being
# replaced when this change first lands (colors.sh and this file are
# separate home.file entries, so a rebuild lands them in some order), where
# the re-source is idempotent and the stubs are the last resort. Without
# them every widget dies on `command not found` mid-render, taking the
# whole batched --add with it; with them the bar paints mute/plum until the
# activation-end reload repaints it, which is the documented failure
# direction: wrong hue, never a pill that stops. `declare -F`, not `type`:
# type answers for anything on PATH, and a binary that happens to be named
# `mark` must not stand in for the resolver.
if ! declare -F tone >/dev/null 2>&1 && [ -r "$HOME/.config/sketchybar/colors.sh" ]; then
    source "$HOME/.config/sketchybar/colors.sh"
fi
if ! declare -F tone >/dev/null 2>&1; then
    tone() { printf '%s' "${TONE_MUTE:-}"; }
fi
if ! declare -F mark >/dev/null 2>&1; then
    mark() { printf '%s' "${MARK_PLUM:-${TONE_MUTE:-}}"; }
fi

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

# _barlib_set_on <item> <prop>=<val>… — sb_set aimed somewhere other than the
# widget's own item, on the same batch. The two callers are the runtime's own
# extra items: a segment (`<name>.<seg>`) and the bracket behind them
# (`<name>.pill`), neither of which a widget names for itself.
_barlib_set_on() {
    local item=$1
    shift
    _BARLIB_ARGS+=(--set "$item" "$@")
}

# barlib_flush — apply everything accumulated so far, as one call, and empty
# the batch. barlib_main calls it last; popup_open calls it early because barpop
# has to arm against rows that already exist. Calling it twice is harmless — the
# second finds nothing to send.
#
# Public, unlike the rest of the plumbing, for the CLI mode whose work was on
# the POPUP rather than on the pill: media's seek moves a slider's knob and
# nothing about what the pill SAYS, so `barlib_tick` would fetch, diff, find
# nothing and flush — the right answer reached through a fetch nobody asked
# for. A batch nobody sends is a knob that snaps back under your finger, which
# is the failure this is public to prevent.
barlib_flush() {
    if [ ${#_BARLIB_ARGS[@]} -gt 0 ]; then
        "$SB" "${_BARLIB_ARGS[@]}"
        _BARLIB_ARGS=()
    fi
    return 0
}

# pill --icon <glyph> --label <text> [--tone <tone>] [--mark <mark>]
#      [--label-tone <tone>] [--hide]
# The standard readout, one or two tones: --tone paints the icon and
# --label-tone the label, which is the whole of the "two-tone pill" — the
# octocat saying how BAD while the number says how MANY. There is no separate
# component for it; passing both flags is it.
#
# --mark is the icon half again, off the IDENTITY axis instead of the ladder,
# for a pill whose glyph says WHICH SUBJECT rather than how it is going: the
# media pill's note/podcast/video glyph is what earned it. It is last-wins
# against --tone exactly as it is on a heading, which is what lets a pill say
# "this is a podcast, and it is paused" as `--mark plum` followed by
# `--tone dim` — one glyph with two things to say and an order to say them in.
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
    local icon='' label='' icon_tone='' icon_mark='' label_tone='' hide=0
    local have_icon=0 have_label=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --icon) icon=$2; have_icon=1; shift 2 ;;
            --label) label=$2; have_label=1; shift 2 ;;
            --tone) icon_tone=$2; icon_mark=''; shift 2 ;;
            --mark) icon_mark=$2; icon_tone=''; shift 2 ;;
            --label-tone) label_tone=$2; shift 2 ;;
            --hide) hide=1; shift ;;
            *)
                echo "barlib: pill: unknown flag '$1' — dropped" >&2
                shift
                ;;
        esac
    done
    # The bracket follows the head, and it has to be said rather than
    # inferred: an all-hidden bracket still paints its own background, so a
    # segmented pill that hid every member would leave an empty capsule in
    # the bar exactly when the widget has nothing to report. Hiding the
    # members is the widget's job (a segment at zero draws nothing); hiding
    # the pill BEHIND them is the runtime's, because the widget never names
    # that item.
    if [ "$hide" = 1 ]; then
        sb_set drawing=off updates=on
        if [ -n "${BARLIB_SEGMENTS:-}" ]; then
            _barlib_set_on "$_BARLIB_POPUP" drawing=off
        fi
        return 0
    fi
    sb_set drawing=on
    if [ -n "${BARLIB_SEGMENTS:-}" ]; then
        _barlib_set_on "$_BARLIB_POPUP" drawing=on
    fi
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
    if [ -n "$icon_mark" ]; then
        sb_set icon.color="$(mark "$icon_mark")"
    elif [ -n "$icon_tone" ]; then
        sb_set icon.color="$(tone "$icon_tone")"
    fi
    if [ -n "$label_tone" ]; then sb_set label.color="$(tone "$label_tone")"; fi
    return 0
}

# segment <name> --icon <glyph> --label <text> [--tone <tone>] [--mark <mark>]
#         [--hide]
# ONE member of a segmented pill (`segments =` in the header). The pill is a
# bracket over a head item and these; the widget names them by their bare
# suffix and never spells the item id.
#
# ⚠️ ONE tone paints BOTH halves, and that is the component's whole opinion.
# A segment is a single reading — a mark and its count — that sketchybar
# forces into two colourable fields because it colours a label exactly once.
# Splitting the tone across them would put the item's implementation detail
# on screen as a design: the glyph and the number are the same answer, and a
# `--label-tone` here would let them disagree. A widget that wants two
# readings side by side wants two segments.
#
# --hide is drawing=off ALONE, unlike `pill --hide`. The `updates=on` half of
# that pair exists so a hidden item keeps ticking and can re-show itself, and
# a segment has neither a script nor an update_freq to tick with — the head
# is what wakes the pill up, and it is the head that carries the door.
segment() {
    local seg='' icon='' label='' tone_name='' mark_name='' hide=0
    local have_icon=0 have_label=0
    if [ $# -gt 0 ]; then
        case "$1" in
            --*) ;;
            *)
                seg=$1
                shift
                ;;
        esac
    fi
    while [ $# -gt 0 ]; do
        case "$1" in
            --icon) icon=$2; have_icon=1; shift 2 ;;
            --label) label=$2; have_label=1; shift 2 ;;
            --tone) tone_name=$2; mark_name=''; shift 2 ;;
            --mark) mark_name=$2; tone_name=''; shift 2 ;;
            --hide) hide=1; shift ;;
            *)
                echo "barlib: segment: unknown flag '$1' — dropped" >&2
                shift
                ;;
        esac
    done
    if [ -z "$seg" ]; then
        echo "barlib: segment: no name — nothing to set" >&2
        return 0
    fi
    # A name that is not one of this pill's declared segments is a typo, and
    # it must not reach sketchybar: `--set agents.redy` on an item that does
    # not exist is accepted in silence, so the segment simply never draws and
    # nothing anywhere says why.
    case " ${BARLIB_SEGMENTS:-} " in
        *" $seg "*) ;;
        *)
            echo "barlib: segment: '$seg' is not in segments (${BARLIB_SEGMENTS:-none}) — dropped" >&2
            return 0
            ;;
    esac
    local item="${NAME}.${seg}"
    if [ "$hide" = 1 ]; then
        _barlib_set_on "$item" drawing=off
        return 0
    fi
    local color=''
    if [ -n "$mark_name" ]; then
        color=$(mark "$mark_name")
    elif [ -n "$tone_name" ]; then
        color=$(tone "$tone_name")
    fi
    _barlib_set_on "$item" drawing=on
    if [ "$have_icon" = 1 ]; then
        _barlib_set_on "$item" icon="$icon"
    fi
    if [ "$have_label" = 1 ]; then
        _barlib_set_on "$item" label="$label"
    fi
    if [ -n "$color" ]; then
        _barlib_set_on "$item" icon.color="$color" label.color="$color"
    fi
    return 0
}

# sb_now <prop>=<val>… — the same raw properties as sb_set, sent RIGHT NOW
# instead of riding the batch.
#
# For a DETACHED job and nothing else. A widget that backgrounds a timer —
# media's hover marquee is the shipped one, a sweep that turns scroll_texts
# back off eight seconds later — is running long after barlib_main flushed and
# exited, so an sb_set from there accumulates into an array nobody will ever
# send. That is the silent failure this exists to remove; the batching rule
# still holds for everything on the tick and click paths, where the whole
# point is that twelve --sets ride one process.
sb_now() {
    "$SB" --set "$NAME" "$@"
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
# THE PANEL IS A GRID, and the grid is the runtime's. SketchyBar lays a popup
# out as a stack of left-aligned items, each as wide as its own content, with
# no alignment property and no notion of a column — which is why every
# hand-written dropdown in this bar's history was a ragged left edge of
# strings in three greys. Every row here is instead a FIXED-WIDTH item
# (`width=`), and inside that width the two text slots are placed by their
# own `width`/`align`, which SketchyBar does honour. That one decision is
# what buys everything below: a value that lands flush right on every row, a
# glyph column every row shares, a hover highlight that spans the row, a
# button that can be centred, a hairline that reaches both edges.
#
#   ┌ inset ┐┌ gutter ┐┌ well ┐┌ gap ┐┌── text ──────────────┐┌ gutter ┐┌ inset ┐
#   │       ││        ││ glyph││     ││ Title             38% ││        ││       │
#
# The numbers are POINTS at haus.ui.scale 1 and scale with the type: the row
# width, the columns and the heights all ride $BAR_SCALE (sizes.sh), so a
# large-print machine gets a wider panel rather than the same panel with
# bigger words falling off it.
#
# THE ROW KINDS, and their typography is the runtime's, not the widget's:
#
#   popup_heading   a section title, in the widget's own hue.  Bold, label size, 34pt
#   popup_row       a thing you can act on.                 Regular, small,   26pt
#   popup_action    a verb — Refresh, a command to copy.    Bold, small,      26pt
#   popup_button    a filled control, centred — the CTA.    Bold, small,      28pt
#   popup_bar       a name, a filled track and a value.     Regular, small,   26pt
#   popup_graph     a sparkline the width of the panel.                       40pt
#   popup_note      an aside — "nothing", "+4 more".        Italic, tiny,     18pt
#   popup_separator a hairline between two groups.                            12pt
#   popup_space     nothing, n points tall.                                    n
#   popup_slider    a track you aim at rather than press.                     26pt
#   popup_image     a row that is entirely a picture.       --box points tall
#
# A widget naming ":Bold:${FS_SMALL}" itself is the hardcoded-hex mistake one
# layer up, and the next kind someone needs is a kind to add here rather than
# a --font to add to a signature.
#
# COLOUR. The ladder and the marks (tones.nix, marks.nix) are still the only
# things a widget names, and the runtime still lays the reading hierarchy out
# in the palette's own TEXT/SUBTEXT0/OVERLAY0. What changed is where the
# widget's IDENTITY lands: a heading with no --tone and no --mark wears the
# mark the widget's `# widget: mark =` header declares, glyph and title both,
# so a converted pill's dropdown is no longer grey where its pill is coloured.
# Tints — the wells behind heading glyphs, the capsule behind a badge, the
# fill of a button — are that same hue at low alpha, derived here, never a
# second colour a widget could pick.
#
# HOVER. Every row that DOES something highlights under the pointer, the way a
# native menu does: a transparent full-width background the row's own
# mouse.entered/mouse.exited script turns SURFACE0 and back. It is one
# `/bin/sh -c` per crossing, on the pointer's schedule and never the tick's,
# and it is what makes a dropdown feel like a control rather than a printout.
# A row with nothing to click never lights, so lighting up is itself the
# affordance.

# ── geometry ──────────────────────────────────────────────────────────────────
# Base values at scale 1. `_barlib_pop_geo` scales them once per process and
# fills the _BARLIB_G_* set every kind below reads; a widget that wants a wider
# panel says `popup_width <points>` at the top of popup_rows and nothing else.
_BARLIB_POPUP_W=340    # the row width — the panel is this plus two insets
_BARLIB_INSET=6        # row inset from the frame: the hover pill's margin
_BARLIB_GUTTER=10      # text inset inside a row, both ends
_BARLIB_WELL=20        # the glyph column, and the well drawn behind a heading's
_BARLIB_GAP=8          # glyph column → text
_BARLIB_H_HEADING=34
_BARLIB_H_ROW=26
_BARLIB_H_BUTTON=28
_BARLIB_H_NOTE=18
_BARLIB_H_GRAPH=40
_BARLIB_H_BADGE=18
_BARLIB_H_PAD=6        # the panel's own top and bottom padding
_BARLIB_ROW_RADIUS=6
_BARLIB_BUTTON_RADIUS=8
# The mono advance as a share of the point size, ×100. JetBrains Mono, SF
# Mono and Fira are 0.60; Iosevka is 0.50. A column is sized from it, so it
# has to be an OVERestimate for every face haus.fonts.mono can name — a value
# column a shade too roomy is a wider gap, a column too narrow is a number
# with its first digit under the name. 65 clears them all.
_BARLIB_ADV100=65
# A value column pads the number by this many points on its inner side.
_BARLIB_COL_SLACK=4

_BARLIB_POPUP_W_REQ=''
_BARLIB_G_READY=0
_BARLIB_G_W=0 _BARLIB_G_INSET=0 _BARLIB_G_GUTTER=0 _BARLIB_G_WELL=0 _BARLIB_G_GAP=0
_BARLIB_G_TEXT_X=0
_BARLIB_G_H_HEADING=0 _BARLIB_G_H_ROW=0 _BARLIB_G_H_BUTTON=0 _BARLIB_G_H_NOTE=0
_BARLIB_G_H_GRAPH=0 _BARLIB_G_H_BADGE=0 _BARLIB_G_H_PAD=0

# popup_width <points> — a wider (or narrower) panel for this popup, at
# scale 1. For the widget whose rows are sentences (github's PR titles) or
# whose picture sets the width (media's cover). Say it before the first row;
# after that the grid is already laid.
popup_width() {
    case "${1:-}" in
        '' | *[!0-9]*) echo "barlib: popup_width: '${1:-}' is not a point count — ignored" >&2 ;;
        *) _BARLIB_POPUP_W_REQ=$1 ;;
    esac
    if [ "$_BARLIB_G_READY" = 1 ]; then
        echo "barlib: popup_width: rows are already laid out — say it before the first row" >&2
    fi
    return 0
}

# _barlib_scale100 — $BAR_SCALE ("1", "1.25") as an integer percentage, in
# bash alone: this runs on the click path and a fork for one number that
# never changes is the awk this file used to pay per row.
_BARLIB_SCALE100=100
_barlib_scale100() {
    local s=${BAR_SCALE:-1} i f
    i=${s%%.*}
    f=${s#*.}
    if [ "$f" = "$s" ]; then f=0; fi
    f="${f}00"
    f=${f:0:2}
    case "$i$f" in
        '' | *[!0-9]*) i=1; f=00 ;;
    esac
    _BARLIB_SCALE100=$((10#$i * 100 + 10#$f))
}

_barlib_px() { # _barlib_px <base> → _BARLIB_PX, the base scaled
    _BARLIB_PX=$((($1 * _BARLIB_SCALE100 + 50) / 100))
}

_barlib_pop_geo() {
    if [ "$_BARLIB_G_READY" = 1 ]; then return 0; fi
    _barlib_scale100
    _barlib_px "${_BARLIB_POPUP_W_REQ:-$_BARLIB_POPUP_W}"; _BARLIB_G_W=$_BARLIB_PX
    _barlib_px "$_BARLIB_INSET";     _BARLIB_G_INSET=$_BARLIB_PX
    _barlib_px "$_BARLIB_GUTTER";    _BARLIB_G_GUTTER=$_BARLIB_PX
    _barlib_px "$_BARLIB_WELL";      _BARLIB_G_WELL=$_BARLIB_PX
    _barlib_px "$_BARLIB_GAP";       _BARLIB_G_GAP=$_BARLIB_PX
    _barlib_px "$_BARLIB_H_HEADING"; _BARLIB_G_H_HEADING=$_BARLIB_PX
    _barlib_px "$_BARLIB_H_ROW";     _BARLIB_G_H_ROW=$_BARLIB_PX
    _barlib_px "$_BARLIB_H_BUTTON";  _BARLIB_G_H_BUTTON=$_BARLIB_PX
    _barlib_px "$_BARLIB_H_NOTE";    _BARLIB_G_H_NOTE=$_BARLIB_PX
    _barlib_px "$_BARLIB_H_GRAPH";   _BARLIB_G_H_GRAPH=$_BARLIB_PX
    _barlib_px "$_BARLIB_H_BADGE";   _BARLIB_G_H_BADGE=$_BARLIB_PX
    _barlib_px "$_BARLIB_H_PAD";     _BARLIB_G_H_PAD=$_BARLIB_PX
    _BARLIB_G_TEXT_X=$((_BARLIB_G_GUTTER + _BARLIB_G_WELL + _BARLIB_G_GAP))
    _BARLIB_G_READY=1
}

# ── measuring text without a fork ─────────────────────────────────────────────
# The bar draws in haus.fonts.mono, so a string's width IS its column count
# times the advance — which is what lets a value column be sized in bash on
# the click path. A Nerd Font glyph is drawn about two cells wide; it is
# three or four BYTES and one character, so columns = chars + (bytes − chars)
# / 2 counts it as two and an accented letter as one and a half. `local
# LC_ALL` is what makes ${#s} count what it is told to (bash re-reads the
# locale on assignment, 3.2 included); a machine without the UTF-8 locale
# counts bytes for both, over-measures glyphs, and gets a roomier column.
_BARLIB_N=0
_barlib_chars() { local LC_ALL=en_US.UTF-8; _BARLIB_N=${#1}; }
_barlib_bytes() { local LC_ALL=C; _BARLIB_N=${#1}; }
_BARLIB_COLS=0
_barlib_cols() { # _barlib_cols <string> → _BARLIB_COLS
    local c b
    _barlib_chars "$1"; c=$_BARLIB_N
    _barlib_bytes "$1"; b=$_BARLIB_N
    _BARLIB_COLS=$((c + (b - c) / 2))
}

# _barlib_adv <font-size> → _BARLIB_ADV, points per column at that size. Sizes
# out of sizes.sh are decimals ("12.0"); only the whole part matters at this
# precision.
_BARLIB_ADV=0
_barlib_adv() {
    local s=${1:-12}
    s=${s%%.*}
    case "$s" in '' | *[!0-9]*) s=12 ;; esac
    _BARLIB_ADV=$(((s * _BARLIB_ADV100 + 50) / 100))
}

# _barlib_fit <string> <max-columns> → _BARLIB_FIT: the string, cut to fit
# with an ellipsis. SketchyBar's max_chars cuts and draws nothing to say it
# did, so a row that lost its end reads as a row that ended there; this
# spends one column on saying so. Character-based, so a glyph is never cut
# in half.
_BARLIB_FIT=''
_barlib_fit() {
    local LC_ALL=en_US.UTF-8
    _barlib_cols "$1"
    if [ "$_BARLIB_COLS" -le "$2" ] || [ "$2" -lt 2 ]; then
        _BARLIB_FIT=$1
        return 0
    fi
    local s=$1
    while [ "${#s}" -gt 1 ]; do
        s=${s%?}
        _barlib_cols "$s"
        if [ "$_BARLIB_COLS" -le "$(($2 - 1))" ]; then break; fi
    done
    _BARLIB_FIT="${s%"${s##*[![:space:]]}"}…"
}

# _barlib_tint <0xAARRGGBB> [alpha-hex] → the same hue at that alpha. What a
# well, a badge's capsule and a button's fill are made of: the row's own
# colour, faded, never a second colour a widget could pick.
_BARLIB_TINT=''
_barlib_tint() {
    _BARLIB_TINT="0x${2:-30}${1#0x??}"
}

# ── the value column ──────────────────────────────────────────────────────────
# A row that carries a NUMBER is two columns, not one sentence: a name on the
# left and a value that has to land on the same x as the value in every row
# above it. That x is the RIGHT EDGE now, the way a native menu puts its
# shortcuts: the value slot gets a fixed `label.width` sized from the value's
# own column count and `label.align=right`, and the name slot takes the rest
# of the row (`_barlib_right_slot`, below the row builder). Getting that
# wrong is the one dropdown flaw you see immediately, so the arithmetic is
# the runtime's — the same reason the row kinds own their fonts.

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
#
# ⚠️ THE SLIDER IS THE ONE EXCEPTION, and it is the kind's property rather than
# a flag any row may pass. Scrubbing is something you do TWICE when the first
# landing was a second out, and a dropdown that vanishes under the pointer
# makes the correction impossible — you would have to reopen the popup, find
# the bar again and aim at a knob that has moved. So a slider's click_script is
# its action ALONE, with no close appended, and the only way to get that is to
# be a slider. A `--keep-open` on `popup_row` would have been the same code and
# a much worse rule: every dropdown in this bar would then have a way to leave
# itself up, and the reason exactly one row may is that exactly one row is a
# CONTROL you aim rather than a thing you press.
#
# <kind> is which of them this is. `slider:<width>` and `graph:<width>` branch
# — both are an item TYPE (`--add slider`, `--add graph`) rather than an
# `--add item`, and every other property below behaves identically. A slider
# is subscribed to mouse.clicked because that is what makes sketchybar hand
# the click's position back as $PERCENTAGE — the whole mechanism of a seek.
#
# <hover> is 1 for a row that should light under the pointer. It is derived
# by the caller from whether the row DOES anything, never passed by a widget:
# a row that lights and then does nothing is the broken-button feeling this
# exists to prevent.
#
# Every row is the panel's full width and carries a transparent background of
# its own height, and both are load-bearing rather than decoration: the width
# is what makes the popup one rectangle rather than a ragged stack, and
# SketchyBar counts a background toward an item's height ONLY while it is
# drawn — with `background.drawing=off` every row here was 30pt tall whatever
# height it named, because the popup's own cell floor (popup.height, 30 by
# default) won. popup_open sets that floor to 1, so the heights below are the
# heights you get.
#
# $POPUP_ID is the id of the row just added, for the rare widget that has to
# reach one again after the batch has gone out (media measures its dropdown
# and nudges an image into the corner). Read it immediately; the next row
# overwrites it.
POPUP_ID=''
_BARLIB_POP_I=0
# The panel's own two pads are numbered apart (`.popup.top`, `.popup.bottom`)
# so the widget's first row is `.popup.0` whether or not the runtime drew
# something above it — the ids are the runtime's, but a widget that caught
# one in $POPUP_ID, and every test that names one, expects the count to be
# the widget's rows.
_BARLIB_POP_PAD=''
_barlib_pop_add() { # _barlib_pop_add <kind> <height> <font> <action> <hover> <set-args…>
    local kind=$1 height=$2 font=$3 action=$4 hover=$5
    shift 5
    _barlib_pop_geo
    local width=''
    case "$kind" in
        slider:*) width=${kind#slider:}; kind=slider ;;
        bar:*) width=${kind#bar:}; kind=bar ;;
        graph:*) width=${kind#graph:}; kind=graph ;;
    esac
    if [ -n "$_BARLIB_POP_PAD" ]; then
        POPUP_ID="${_BARLIB_POPUP}.popup.${_BARLIB_POP_PAD}"
    else
        POPUP_ID="${_BARLIB_POPUP}.popup.${_BARLIB_POP_I}"
    fi
    local close="$SB --set $_BARLIB_POPUP popup.drawing=off"
    local click="$close"
    if [ -n "$action" ]; then click="$action; $close"; fi
    case "$kind" in
        slider)
            click="$action"
            _BARLIB_ARGS+=(--add slider "$POPUP_ID" "popup.${_BARLIB_POPUP}" "$width")
            ;;
        bar)
            _BARLIB_ARGS+=(--add slider "$POPUP_ID" "popup.${_BARLIB_POPUP}" "$width")
            ;;
        graph)
            _BARLIB_ARGS+=(--add graph "$POPUP_ID" "popup.${_BARLIB_POPUP}" "$width")
            ;;
        *)
            _BARLIB_ARGS+=(--add item "$POPUP_ID" "popup.${_BARLIB_POPUP}")
            ;;
    esac
    _BARLIB_ARGS+=(
        --set "$POPUP_ID"
        width="$_BARLIB_G_W"
        padding_left="$_BARLIB_G_INSET" padding_right="$_BARLIB_G_INSET"
        icon="" icon.font="${BAR_FONT:-}:Bold:${FS_LABEL:-}"
        icon.width="$((_BARLIB_G_GUTTER + _BARLIB_G_WELL))" icon.align=center
        icon.padding_left="$_BARLIB_G_GUTTER" icon.padding_right=0
        label="" label.padding_left="$_BARLIB_G_GAP" label.padding_right="$_BARLIB_G_GUTTER"
        label.font="$font"
        background.drawing=on background.color=0x00000000
        background.height="$height" background.corner_radius="$_BARLIB_ROW_RADIUS"
        click_script="$click"
        "$@"
    )
    if [ "$hover" = 1 ]; then
        # $NAME is the row's own id when sketchybar runs this — it exports the
        # item the pointer touched — so the script needs no id baked in and
        # the two colours are the only thing in it. Single-quoted at the shell
        # level so the case runs in the spawned /bin/sh, not here.
        _BARLIB_ARGS+=(
            --set "$POPUP_ID"
            script="case \"\$SENDER\" in mouse.entered) $SB --set \"\$NAME\" background.color=${SURFACE0:-0x00000000} ;; mouse.exited) $SB --set \"\$NAME\" background.color=0x00000000 ;; esac"
            --subscribe "$POPUP_ID" mouse.entered mouse.exited
        )
    fi
    if [ "$kind" = slider ]; then
        _BARLIB_ARGS+=(--subscribe "$POPUP_ID" mouse.clicked)
    fi
    if [ -z "$_BARLIB_POP_PAD" ]; then _BARLIB_POP_I=$((_BARLIB_POP_I + 1)); fi
}

# popup_set <row-id> <prop>=<val>… — raw properties on ONE popup row, batched
# like everything else. The dropdown's counterpart to `sb_set`, and it is the
# escape hatch for the same two jobs a component cannot cover:
#
#   * a row that CHANGES ITSELF on a click. The slider's knob is the whole
#     list: sketchybar does not move it on a click of its own accord, so it
#     would sit where it was until the popup was next rebuilt — i.e. until the
#     next time you opened it. The handler passes $POPUP_CLICKED, which is the
#     id the runtime stripped off $NAME on the way in.
#   * a row placed from a MEASUREMENT, which can only be taken once the popup
#     has been drawn — so it cannot be an argument to the row that made it.
#     The id comes from $POPUP_ID, captured when the row was added.
#
# Anything else wanting this is a component that is missing; file the gap.
popup_set() {
    local id=$1
    shift
    if [ -z "$id" ]; then
        echo "barlib: popup_set: no row id — nothing to set" >&2
        return 0
    fi
    _BARLIB_ARGS+=(--set "$id" "$@")
    return 0
}

# _barlib_pop_cap <max-chars> <marquee 0|1> — the two label properties a row
# of DATA wants and a row of the widget's own words does not, applied to the
# row $POPUP_ID names.
#
# They are separate on purpose. max_chars is a CAP — it is what keeps one long
# title from setting the width of the whole dropdown, and a row that loses it
# is a popup as wide as the worst string the machine can produce. scroll_texts
# is MOTION, which is a taste (and an accessibility) question: haus.appearance
# .reduceMotion turns media's off, and with it off the row simply clips at the
# cap. Folding them into one flag would make "don't move" mean "and be as wide
# as you like".
#
# With the grid, a row that names NEITHER is cut to the column by the runtime
# itself (`_barlib_fit`, with an ellipsis) before it is emitted — so these two
# are for the row that wants sketchybar's own cap, which is the row that
# scrolls: a marquee has to hold the whole string to sweep it past.
_barlib_pop_cap() {
    if [ "${1:-0}" -gt 0 ] 2>/dev/null; then
        _BARLIB_ARGS+=(--set "$POPUP_ID" label.max_chars="$1")
    fi
    if [ "${2:-0}" = 1 ]; then
        _BARLIB_ARGS+=(--set "$POPUP_ID" scroll_texts=on)
    fi
    return 0
}

# _barlib_text_cap <font-size> <lead> → _BARLIB_CAP: how many columns of that
# size fit between <lead> and the right gutter of a single-column row.
_BARLIB_CAP=0
_barlib_text_cap() {
    _barlib_pop_geo
    _barlib_adv "$1"
    _BARLIB_CAP=$(((_BARLIB_G_W - $2 - _BARLIB_G_GUTTER - _BARLIB_COL_SLACK) / _BARLIB_ADV))
}

# _barlib_right_slot <text> <font> <font-size> <colour> [capsule-tint] — the
# --set args that put <text> flush right, and the icon slot sized to
# everything left of it. Sets the _BARLIB_RIGHT array for the caller to
# splice in (a subshell could not hand an array back) and _BARLIB_NAME_W,
# the width the name slot was left with.
#
# Two shapes. A plain value gets a fixed `label.width` and `label.align=right`,
# so it lands on the gutter EXACTLY whatever the advance estimate was — the
# estimate only has to be generous. A capsule cannot: a text's background is
# as wide as its slot, so a fixed slot would be a capsule as wide as the
# column. The label stays dynamic there, its padding is what gives the words
# their room inside the capsule, and the icon slot is cut so the capsule's
# far edge lands on the gutter — to within the estimate's error, which on a
# four-character badge is a pixel or two.
_BARLIB_RIGHT=()
_barlib_right_slot() {
    local text=$1 font=$2 size=$3 color=$4 tint=${5:-}
    # A value that right-aligned its own number with leading blanks (`%3s%%`)
    # asked for exactly what the slot now does — and a label is the one place
    # those blanks cannot stay: sketchybar sizes a string TRIMMED and draws it
    # untrimmed, so they would push the digits past the edge of a slot sized
    # without them.
    text="${text#"${text%%[! ]*}"}"
    _barlib_cols "$text"
    _barlib_adv "$size"
    local w
    if [ -n "$tint" ]; then
        w=$((_BARLIB_COLS * _BARLIB_ADV + 2 * _BARLIB_G_GAP + _BARLIB_COL_SLACK))
        _BARLIB_RIGHT=(
            label="$text" label.font="$font" label.color="$color"
            label.width=dynamic
            label.padding_left="$_BARLIB_G_GAP" label.padding_right="$_BARLIB_G_GAP"
            label.background.drawing=on label.background.color="$tint"
            label.background.height="$_BARLIB_G_H_BADGE"
            label.background.corner_radius="$((_BARLIB_G_H_BADGE / 2))"
            icon.width="$((_BARLIB_G_W - w - _BARLIB_G_GUTTER))" icon.align=left
        )
        _BARLIB_NAME_W=$((_BARLIB_G_W - w - _BARLIB_G_GUTTER))
    else
        w=$((_BARLIB_COLS * _BARLIB_ADV + _BARLIB_G_GUTTER + _BARLIB_COL_SLACK))
        _BARLIB_RIGHT=(
            label="$text" label.font="$font" label.color="$color"
            label.width="$w" label.align=right
            label.padding_left=0 label.padding_right="$_BARLIB_G_GUTTER"
            icon.width="$((_BARLIB_G_W - w))" icon.align=left
        )
        _BARLIB_NAME_W=$((_BARLIB_G_W - w))
    fi
    return 0
}

# _barlib_name_cap <font-size> <lead> → _BARLIB_CAP: the columns the NAME slot
# a right slot just left has room for, past <lead> points of padding.
_barlib_name_cap() {
    _barlib_adv "$1"
    _BARLIB_CAP=$(((_BARLIB_NAME_W - $2 - _BARLIB_COL_SLACK) / _BARLIB_ADV))
}

# popup_heading --label <text> [--icon <glyph>] [--icon-font <font>]
#               [--tone <tone>] [--mark <mark>] [--label-tone <tone>]
#               [--count <n>] [--badge <text>] [--badge-tone <tone>]
#               [--value <text>] [--run <command>]
#               [--max-chars <n>] [--marquee]
# The section title. Glyph in a tinted WELL on the glyph column, title beside
# it, both in ONE hue — and that hue is, in order: --tone or --mark if the
# widget said one (last wins, so `--mark warm --tone mute` is "this is Claude,
# and its feed is dead"), else the mark its `# widget: mark =` header
# declares, else `dim`. The header is the whole reason a converted pill's
# dropdown stopped being grey: the ladder has no rung for "this pill's own
# colour" on purpose (a heading is not a verdict), and the identity axis is
# where that colour lives.
#
# --count appends " · n" to the title when n is above zero: a section that
# says "open PRs" over eight rows leaves you counting them to find out whether
# eight is all of them, and the rows below may be a truncation. It rides the
# title rather than a badge so the well stays — a count is part of the name
# of the section, not a reading about it.
# --badge <text> is a CAPSULE flush right, in --badge-tone's tint with its
# words in that tone (the heading's hue by default): "41%", "critical",
# "paused". A reading about the section, set apart from its name.
# --value <text> is the older two-column shape — the value flush right in
# --label-tone, no capsule. Both of those need the label slot, so glyph and
# title share the icon slot in one hue and the well is not drawn: three
# things, two slots, and the heading that asks for a third pays with the
# well.
# --run makes the heading CLICKABLE, on the same terms as a row: the command,
# then the popup closes. It is for a block whose rows all mean one thing —
# the agents pill's per-agent block is a name line and a detail line that
# both mean "this pane", and a heading a few pixels tall is a bad target for
# "this is the one I meant". Give both rows the same --run and the block
# becomes one hit area, which is what a widget is really asking for when it
# wants a clickable heading.
# --label-tone paints the TITLE half alone, for a section whose subject has
# gone quiet as a BLOCK (`--tone dim --label-tone dim`): a dim mark under a
# full-brightness name reads as a rendering bug rather than as a feed that
# stopped reporting.
# --icon-font is for a glyph that does not exist in the bar's own face —
# sketchybar-app-font's `:claude:` and `:openai:` are the shipped case. It is
# NOT a typography flag: the runtime still owns the weight and the size of
# everything a heading draws.
popup_heading() {
    local label='' icon='' icon_font='' tone_name='' mark_name='' count=0
    local value='' have_value=0 label_tone='' cap=0 marquee=0 action=''
    local badge='' badge_tone=''
    while [ $# -gt 0 ]; do
        case "$1" in
            --label) label=$2; shift 2 ;;
            --run) action=$2; shift 2 ;;
            --icon) icon=$2; shift 2 ;;
            --icon-font) icon_font=$2; shift 2 ;;
            --tone) tone_name=$2; mark_name=''; shift 2 ;;
            --mark) mark_name=$2; tone_name=''; shift 2 ;;
            --label-tone) label_tone=$2; shift 2 ;;
            --count) count=$2; shift 2 ;;
            --badge) badge=$2; shift 2 ;;
            --badge-tone) badge_tone=$2; shift 2 ;;
            --value) value=$2; have_value=1; shift 2 ;;
            --max-chars) cap=$2; shift 2 ;;
            --marquee) marquee=1; shift ;;
            *) echo "barlib: popup_heading: unknown flag '$1' — dropped" >&2; shift ;;
        esac
    done
    _barlib_pop_geo
    local hue
    if [ -n "$mark_name" ]; then
        hue=$(mark "$mark_name")
    elif [ -n "$tone_name" ]; then
        hue=$(tone "$tone_name")
    elif [ -n "${BARLIB_MARK:-}" ]; then
        hue=$(mark "$BARLIB_MARK")
    else
        hue=$(tone dim)
    fi
    local title_color="$hue"
    if [ -n "$label_tone" ]; then title_color=$(tone "$label_tone"); fi
    _barlib_tint "$hue"
    local well="$_BARLIB_TINT"
    local hover=0
    if [ -n "$action" ]; then hover=1; fi
    local hfont="${BAR_FONT:-}:Bold:${FS_LABEL:-}"
    case "$count" in '' | *[!0-9]*) count=0 ;; esac
    if [ "$count" -gt 0 ]; then label="$label · $count"; fi

    if [ "$have_value" = 1 ]; then
        # Glyph and title travel TOGETHER in the icon, in ONE tone — they are
        # the same mark, and the value takes the label slot flush right. That
        # merge is also why --icon-font cannot apply here: a glyph-only face
        # would draw the title as tofu. Warned rather than silently dropping
        # the glyph — a mark in the wrong face is a thing someone reports.
        if [ -n "$icon_font" ]; then
            echo "barlib: popup_heading: --icon-font is ignored with --value (glyph and title share one item)" >&2
        fi
        local vcolor="${TEXT:-}"
        if [ -n "$label_tone" ]; then vcolor=$(tone "$label_tone"); fi
        local name="$label"
        if [ -n "$icon" ]; then name="$icon $label"; fi
        _barlib_right_slot "$value" "$hfont" "${FS_LABEL:-13}" "$vcolor"
        _barlib_name_cap "${FS_LABEL:-13}" "$_BARLIB_G_GUTTER"
        _barlib_fit "$name" "$_BARLIB_CAP"
        _barlib_pop_add heading "$_BARLIB_G_H_HEADING" "$hfont" "$action" "$hover" \
            icon="$_BARLIB_FIT" icon.color="$hue" icon.font="$hfont" \
            icon.padding_left="$_BARLIB_G_GUTTER" icon.padding_right=0 \
            "${_BARLIB_RIGHT[@]}"
        _barlib_pop_cap "$cap" "$marquee"
        return 0
    fi

    # The well: the icon slot is exactly the well wide, its background is the
    # hue's tint drawn as a circle, and the glyph is centred in it. The
    # gutter is paid as icon.padding_left (inside the slot, so the centring
    # accounts for it) and given back to the background as x_offset (which is
    # outside it), so the circle sits at the gutter and the glyph sits in the
    # circle. No icon, no well — the title starts on the text column either
    # way.
    local -a well_args=()
    if [ -n "$icon" ]; then
        well_args=(
            icon.background.drawing=on icon.background.color="$well"
            icon.background.height="$_BARLIB_G_WELL"
            icon.background.corner_radius="$((_BARLIB_G_WELL / 2))"
            icon.background.x_offset="$_BARLIB_G_GUTTER"
        )
    fi
    if [ -n "$badge" ]; then
        local bcolor="$hue"
        if [ -n "$badge_tone" ]; then bcolor=$(tone "$badge_tone"); fi
        _barlib_tint "$bcolor"
        _barlib_right_slot "$badge" "${BAR_FONT:-}:Bold:${FS_TINY:-}" "${FS_TINY:-10}" "$bcolor" "$_BARLIB_TINT"
        if [ -n "$icon_font" ]; then
            echo "barlib: popup_heading: --icon-font is ignored with --badge (glyph and title share one item)" >&2
        fi
        local name="$label"
        if [ -n "$icon" ]; then name="$icon $label"; fi
        _barlib_name_cap "${FS_LABEL:-13}" "$_BARLIB_G_GUTTER"
        _barlib_fit "$name" "$_BARLIB_CAP"
        _barlib_pop_add heading "$_BARLIB_G_H_HEADING" "$hfont" "$action" "$hover" \
            icon="$_BARLIB_FIT" icon.color="$hue" icon.font="$hfont" \
            icon.padding_left="$_BARLIB_G_GUTTER" icon.padding_right=0 \
            "${_BARLIB_RIGHT[@]}"
        _barlib_pop_cap "$cap" "$marquee"
        return 0
    fi
    _barlib_text_cap "${FS_LABEL:-13}" "$_BARLIB_G_TEXT_X"
    if [ "$cap" -gt 0 ] 2>/dev/null; then _BARLIB_FIT=$label; else _barlib_fit "$label" "$_BARLIB_CAP"; fi
    _barlib_pop_add heading "$_BARLIB_G_H_HEADING" "$hfont" "$action" "$hover" \
        icon="$icon" icon.color="$hue" \
        icon.font="${icon_font:-${BAR_FONT:-}:Bold:${FS_LABEL:-}}" \
        icon.width="$_BARLIB_G_WELL" icon.align=center \
        icon.padding_left="$_BARLIB_G_WELL" icon.padding_right=0 \
        "${well_args[@]}" \
        label="$_BARLIB_FIT" label.color="$title_color" \
        label.padding_left="$((_BARLIB_G_GUTTER + _BARLIB_G_GAP))"
    _barlib_pop_cap "$cap" "$marquee"
}

# popup_row --label <text> [--icon <glyph>] [--tone <tone>] [--value <text>]
#           [--badge <text>] [--badge-tone <tone>] [--hint <text>]
#           [--name-tone <tone>] [--open <url>] [--run <command>]
#           [--max-chars <n>] [--marquee]
# A `mute` row loses a shade of its TEXT too, not only its glyph colour:
# otherwise a list of eight reads as eight equal claims on you when two of
# them are their author saying "not yet". Only `mute` — a `dim` row keeps its
# full-brightness label on purpose, because dim is the row still being ABOUT
# something; it is the glyph that is subordinate, not the sentence.
#
# The right column, one of three: --value is the ANSWER (small, on the
# ladder, flush right); --badge is a capsule (tiny, bold, the tone's tint
# behind it) for a state word or a count; --hint is meta (tiny, dim) — a
# time, a shortcut, a "2 of 4". They share one slot, so a row takes one.
popup_row() {
    local label='' icon='' icon_tone=mute action='' value='' have_value=0 tone_set=0
    local cap=0 marquee=0 name_tone=dim name_tone_set=0
    local badge='' badge_tone='' hint=''
    while [ $# -gt 0 ]; do
        case "$1" in
            --label) label=$2; shift 2 ;;
            --name-tone) name_tone=$2; name_tone_set=1; shift 2 ;;
            --icon) icon=$2; shift 2 ;;
            --tone) icon_tone=$2; tone_set=1; shift 2 ;;
            --value) value=$2; have_value=1; shift 2 ;;
            --badge) badge=$2; shift 2 ;;
            --badge-tone) badge_tone=$2; shift 2 ;;
            --hint) hint=$2; shift 2 ;;
            --open) action="/usr/bin/open $(popup_quote "$2")"; shift 2 ;;
            --run) action=$2; shift 2 ;;
            --max-chars) cap=$2; shift 2 ;;
            --marquee) marquee=1; shift ;;
            *) echo "barlib: popup_row: unknown flag '$1' — dropped" >&2; shift ;;
        esac
    done
    _barlib_pop_geo
    local hover=0
    if [ -n "$action" ]; then hover=1; fi
    local rfont="${BAR_FONT:-}:Regular:${FS_SMALL:-}"
    # --name-tone only means anything in the two-column shape: without a
    # --value there is no name column to tone, `--tone` already paints the
    # glyph, and a flag that quietly does nothing is the silent ignore this
    # runtime refuses everywhere else.
    if [ "$name_tone_set" = 1 ] && [ "$have_value" = 0 ]; then
        echo "barlib: popup_row: --name-tone needs a --value (there is no name column without one)" >&2
    fi
    if [ "$have_value" = 1 ]; then
        # ⚠️ With a --value the tone follows the NUMBER, not the glyph. That is
        # the row saying which half carries the verdict: the name is the
        # question ("user", "load", "Safari") and is always dim, the value is
        # the answer and is the only thing on the ladder. A two-column row
        # whose name climbed to `bad` with it would be one row shouting twice.
        # `text` is the default rather than `mute`, because a measurement with
        # no verdict is a live readout, not an absence.
        #
        # --name-tone is the exception, and it is narrow on purpose: a row
        # whose two halves are two ANSWERS rather than a question and an
        # answer. The agents pill's detail line is the one — "working · 12m ·
        # haus" on the left is this lane's state, "+2 unshipped" on the right
        # is its PR's, and neither is labelling the other. Dim would say the
        # left half is a descriptor, which is exactly the reading that is
        # wrong. Everything with a descriptor column keeps the default and
        # should: naming this flag to save a shade is how the "one row
        # shouting twice" rule above gets lost.
        if [ "$tone_set" = 0 ]; then icon_tone=text; fi
        local name="$label" lead="$_BARLIB_G_TEXT_X"
        if [ -n "$icon" ]; then name="$icon $label"; lead="$_BARLIB_G_GUTTER"; fi
        # An EMPTY --label is a continuation row: the name slot is left blank
        # and the value still lands flush right, so the second line of a block
        # sits under the first instead of beside it.
        _barlib_right_slot "$value" "${BAR_FONT:-}:Bold:${FS_SMALL:-}" "${FS_SMALL:-12}" "$(tone "$icon_tone")"
        _barlib_name_cap "${FS_SMALL:-12}" "$lead"
        _barlib_fit "$name" "$_BARLIB_CAP"
        _barlib_pop_add row "$_BARLIB_G_H_ROW" "$rfont" "$action" "$hover" \
            icon="$_BARLIB_FIT" icon.color="$(tone "$name_tone")" icon.font="$rfont" \
            icon.padding_left="$lead" icon.padding_right=0 \
            "${_BARLIB_RIGHT[@]}"
        _barlib_pop_cap "$cap" "$marquee"
        return 0
    fi
    local lcolor="${SUBTEXT0:-}"
    if [ "$icon_tone" = mute ]; then lcolor="${OVERLAY0:-}"; fi
    if [ -n "$badge" ] || [ -n "$hint" ]; then
        # The glyph keeps its column; the label carries the sentence and the
        # right slot goes to the badge or the hint — so the sentence moves
        # into the icon slot beside the glyph, in the label's own colour, and
        # the glyph's tone is spent on the glyph alone when there is no glyph.
        # A badge row's glyph and words therefore share one colour: the
        # words'. That is the price of a third thing on a two-slot row, and it
        # is paid by the row that asked for it.
        local name="$label" lead="$_BARLIB_G_TEXT_X"
        if [ -n "$icon" ]; then name="$icon $label"; lead="$_BARLIB_G_GUTTER"; fi
        if [ -n "$badge" ]; then
            local bcolor
            if [ -n "$badge_tone" ]; then bcolor=$(tone "$badge_tone"); else bcolor=$(tone "$icon_tone"); fi
            _barlib_tint "$bcolor"
            _barlib_right_slot "$badge" "${BAR_FONT:-}:Bold:${FS_TINY:-}" "${FS_TINY:-10}" "$bcolor" "$_BARLIB_TINT"
        else
            _barlib_right_slot "$hint" "${BAR_FONT:-}:Regular:${FS_TINY:-}" "${FS_TINY:-10}" "${OVERLAY0:-}"
        fi
        _barlib_name_cap "${FS_SMALL:-12}" "$lead"
        _barlib_fit "$name" "$_BARLIB_CAP"
        _barlib_pop_add row "$_BARLIB_G_H_ROW" "$rfont" "$action" "$hover" \
            icon="$_BARLIB_FIT" icon.color="$lcolor" icon.font="$rfont" \
            icon.padding_left="$lead" icon.padding_right=0 \
            "${_BARLIB_RIGHT[@]}"
        _barlib_pop_cap "$cap" "$marquee"
        return 0
    fi
    _barlib_text_cap "${FS_SMALL:-12}" "$_BARLIB_G_TEXT_X"
    if [ "$cap" -gt 0 ] 2>/dev/null; then _BARLIB_FIT=$label; else _barlib_fit "$label" "$_BARLIB_CAP"; fi
    _barlib_pop_add row "$_BARLIB_G_H_ROW" "$rfont" "$action" "$hover" \
        icon="$icon" icon.color="$(tone "$icon_tone")" \
        label="$_BARLIB_FIT" label.color="$lcolor"
    _barlib_pop_cap "$cap" "$marquee"
}

# popup_action --label <text> [--icon <glyph>] [--tone <tone>] [--hint <text>]
#              [--run <command>] [--copy <text>]
# The verb row — a menu item. --copy exists because the useful answer is often
# a command you have to run somewhere with a terminal in front of it: `gh auth
# login` wants a browser, a protocol choice and a paste-back code, and there
# is no shell behind a bar popup to give it any of that.
#
# It defaults to `action`, and defaulting to `accent` was a real bug rather
# than a shade: accent follows haus.theme.accent, an enum of fourteen names
# that includes red, peach, yellow, green and sky, so on those machines every
# verb row in every framework popup was painted the same colour as the alarm
# — and `haus.theme.accent`'s own doc promises the logo is the ONLY pill that
# follows it. A row you press is a fixed sapphire on every machine.
#
# --hint puts a tiny dim caption flush right — "2m ago" on a Refresh, the
# gesture that does the same thing — where the old row spelled it into the
# label with a middle dot.
popup_action() {
    local label='' icon='' icon_tone=action action='' hint=''
    while [ $# -gt 0 ]; do
        case "$1" in
            --label) label=$2; shift 2 ;;
            --icon) icon=$2; shift 2 ;;
            --tone) icon_tone=$2; shift 2 ;;
            --hint) hint=$2; shift 2 ;;
            --run) action=$2; shift 2 ;;
            --copy) action="printf '%s' $(popup_quote "$2") | pbcopy"; shift 2 ;;
            *) echo "barlib: popup_action: unknown flag '$1' — dropped" >&2; shift ;;
        esac
    done
    _barlib_pop_geo
    local afont="${BAR_FONT:-}:Bold:${FS_SMALL:-}"
    if [ -n "$hint" ]; then
        local name="$label" lead="$_BARLIB_G_TEXT_X"
        if [ -n "$icon" ]; then name="$icon $label"; lead="$_BARLIB_G_GUTTER"; fi
        _barlib_right_slot "$hint" "${BAR_FONT:-}:Regular:${FS_TINY:-}" "${FS_TINY:-10}" "${OVERLAY0:-}"
        _barlib_name_cap "${FS_SMALL:-12}" "$lead"
        _barlib_fit "$name" "$_BARLIB_CAP"
        _barlib_pop_add action "$_BARLIB_G_H_ROW" "$afont" "$action" 1 \
            icon="$_BARLIB_FIT" icon.color="$(tone "$icon_tone")" icon.font="$afont" \
            icon.padding_left="$lead" icon.padding_right=0 \
            "${_BARLIB_RIGHT[@]}"
        return 0
    fi
    _barlib_text_cap "${FS_SMALL:-12}" "$_BARLIB_G_TEXT_X"
    _barlib_fit "$label" "$_BARLIB_CAP"
    _barlib_pop_add action "$_BARLIB_G_H_ROW" "$afont" "$action" 1 \
        icon="$icon" icon.color="$(tone "$icon_tone")" \
        label="$_BARLIB_FIT" label.color="${SUBTEXT0:-}"
}

# ── the button ────────────────────────────────────────────────────────────────
# popup_button --label <text> [--icon <glyph>] [--tone <tone>] [--mark <mark>]
#              [--solid] [--run <command>] [--open <url>] [--copy <text>]
#
# The one row that LOOKS like a control: a filled capsule the width of the
# panel less a gutter each side, its words centred, in the row's hue. Tinted
# by default — the hue at low alpha behind the hue's own text, which is what a
# secondary button is on every Apple surface — and `--solid` for the primary
# one: the hue itself, with the panel's base colour for the words. Two shapes
# and no third; a popup with two solid buttons has not decided what it wants
# you to do.
#
# It defaults to `action` for the same reason popup_action does. A verb with a
# verdict names one — "Allow sleep" while an assertion is held is `bad` — and
# the fill follows, which is how a destructive button reads as one.
#
# Hover brightens a tinted fill one step; a solid fill is already as loud as
# it gets and stays put.
_BARLIB_ALPHA_TINT=30
_BARLIB_ALPHA_HOVER=50
popup_button() {
    local label='' icon='' tone_name=action mark_name='' solid=0 action=''
    while [ $# -gt 0 ]; do
        case "$1" in
            --label) label=$2; shift 2 ;;
            --icon) icon=$2; shift 2 ;;
            --tone) tone_name=$2; mark_name=''; shift 2 ;;
            --mark) mark_name=$2; tone_name=''; shift 2 ;;
            --solid) solid=1; shift ;;
            --run) action=$2; shift 2 ;;
            --open) action="/usr/bin/open $(popup_quote "$2")"; shift 2 ;;
            --copy) action="printf '%s' $(popup_quote "$2") | pbcopy"; shift 2 ;;
            *) echo "barlib: popup_button: unknown flag '$1' — dropped" >&2; shift ;;
        esac
    done
    _barlib_pop_geo
    local hue
    if [ -n "$mark_name" ]; then hue=$(mark "$mark_name"); else hue=$(tone "$tone_name"); fi
    local fill text hover_fill
    if [ "$solid" = 1 ]; then
        fill="$hue"; text="${BASE:-}"; hover_fill="$hue"
    else
        _barlib_tint "$hue" "$_BARLIB_ALPHA_TINT"; fill="$_BARLIB_TINT"
        _barlib_tint "$hue" "$_BARLIB_ALPHA_HOVER"; hover_fill="$_BARLIB_TINT"
        text="$hue"
    fi
    local bfont="${BAR_FONT:-}:Bold:${FS_SMALL:-}"
    local w=$((_BARLIB_G_W - 2 * _BARLIB_G_GUTTER))
    local ipad=0
    if [ -n "$icon" ]; then ipad=$_BARLIB_G_GAP; fi
    _barlib_text_cap "${FS_SMALL:-12}" "$((_BARLIB_G_GUTTER + _BARLIB_G_WELL + ipad))"
    _barlib_fit "$label" "$_BARLIB_CAP"
    # No hover through _barlib_pop_add — a button's rest state is already a
    # fill, so its own script swaps the two tints rather than the row grey.
    _barlib_pop_add button "$_BARLIB_G_H_BUTTON" "$bfont" "$action" 0 \
        width="$w" align=center \
        padding_left="$((_BARLIB_G_INSET + _BARLIB_G_GUTTER))" \
        padding_right="$((_BARLIB_G_INSET + _BARLIB_G_GUTTER))" \
        icon="$icon" icon.color="$text" icon.font="$bfont" \
        icon.width=dynamic icon.align=left icon.padding_left=0 icon.padding_right="$ipad" \
        label="$_BARLIB_FIT" label.color="$text" label.padding_left=0 label.padding_right=0 \
        background.color="$fill" background.corner_radius="$_BARLIB_BUTTON_RADIUS"
    if [ "$solid" = 0 ]; then
        _BARLIB_ARGS+=(
            --set "$POPUP_ID"
            script="case \"\$SENDER\" in mouse.entered) $SB --set \"\$NAME\" background.color=$hover_fill ;; mouse.exited) $SB --set \"\$NAME\" background.color=$fill ;; esac"
            --subscribe "$POPUP_ID" mouse.entered mouse.exited
        )
    fi
    return 0
}

# ── the bar ───────────────────────────────────────────────────────────────────
# popup_bar --label <name> --percentage <0-100> [--value <text>] [--tone <tone>]
#           [--mark <mark>] [--name-tone <tone>]
#
# A readout with a FILL in it: the name on the left, a track that is as full
# as the number, the number flush right. What every "38%" in a dropdown wants
# to be, and what ai_usage drew in block glyphs because one item can carry
# only one colour — a slider carries three (the groove, the fill, the words),
# so the track is a real 4pt bar in the row's tone against the runtime's
# groove. It is the slider component with no knob and no gesture: SketchyBar's
# slider IS a progress bar once nothing subscribes it to a click. The
# interactive cousin is popup_slider, one section down, and they are two
# kinds rather than one flag because one of them may leave the popup open
# under your hand and the other never may.
#
# The columns are FIXED across rows — the name gets a set share of the panel
# and the value a set share — so that three bars under one heading are three
# tracks of one length starting on one x. That is the alignment the eye reads
# as "a chart"; ragged tracks read as three unrelated rows.
_BARLIB_BAR_NAME_COLS=14
_BARLIB_BAR_VALUE_COLS=5
popup_bar() {
    local label='' pct=0 value='' tone_name=text mark_name='' name_tone=dim
    while [ $# -gt 0 ]; do
        case "$1" in
            --label) label=$2; shift 2 ;;
            --percentage) pct=$2; shift 2 ;;
            --value) value=$2; shift 2 ;;
            --tone) tone_name=$2; mark_name=''; shift 2 ;;
            --mark) mark_name=$2; tone_name=''; shift 2 ;;
            --name-tone) name_tone=$2; shift 2 ;;
            *) echo "barlib: popup_bar: unknown flag '$1' — dropped" >&2; shift ;;
        esac
    done
    _barlib_pop_geo
    case "$pct" in '' | *[!0-9]*) pct=0 ;; esac
    if [ "$pct" -gt 100 ]; then pct=100; fi
    local fill
    if [ -n "$mark_name" ]; then fill=$(mark "$mark_name"); else fill=$(tone "$tone_name"); fi
    local sfont="${BAR_FONT:-}:Regular:${FS_SMALL:-}"
    _barlib_adv "${FS_SMALL:-12}"
    local name_w=$((_BARLIB_G_TEXT_X + _BARLIB_BAR_NAME_COLS * _BARLIB_ADV))
    local value_w=$((_BARLIB_BAR_VALUE_COLS * _BARLIB_ADV + _BARLIB_G_GUTTER + _BARLIB_COL_SLACK))
    local track=$((_BARLIB_G_W - name_w - value_w - _BARLIB_G_GAP))
    if [ "$track" -lt 40 ]; then track=40; fi
    _barlib_fit "$label" "$_BARLIB_BAR_NAME_COLS"
    _barlib_pop_add "bar:$track" "$_BARLIB_G_H_ROW" "$sfont" '' 0 \
        icon="$_BARLIB_FIT" icon.color="$(tone "$name_tone")" icon.font="$sfont" \
        icon.width="$name_w" icon.align=left \
        icon.padding_left="$_BARLIB_G_TEXT_X" icon.padding_right="$_BARLIB_G_GAP" \
        label="$value" label.color="$fill" label.font="${BAR_FONT:-}:Bold:${FS_SMALL:-}" \
        label.width="$value_w" label.align=right \
        label.padding_left=0 label.padding_right="$_BARLIB_G_GUTTER" \
        slider.percentage="$pct" \
        slider.background.height=4 \
        slider.background.corner_radius=2 \
        slider.background.color="${SURFACE1:-}" \
        slider.highlight_color="$fill" \
        slider.knob="" slider.knob.drawing=off
    return 0
}

# ── the sparkline ─────────────────────────────────────────────────────────────
# popup_graph --points "<p1> <p2> …" [--tone <tone>] [--mark <mark>]
#
# A graph the width of the panel, fed the last N readings as PERCENTAGES
# (0…100, the same unit `graph` on the pill takes; clamped the same way). Its
# line is the hue and its fill the hue's tint, the pairing the pill's own
# graph gets from the emitter. The points are pushed on the same batch the row
# rides, oldest first, so the newest reading lands at the right edge — which
# is where a rolling window puts "now".
#
# A widget has to KEEP the readings to have any to push here: the pill's own
# graph is inside SketchyBar and cannot be read back. vitals_lib's ring is the
# shipped example — one line appended per tick, the last width kept.
popup_graph() {
    local points='' tone_name='' mark_name=''
    while [ $# -gt 0 ]; do
        case "$1" in
            --points) points=$2; shift 2 ;;
            --tone) tone_name=$2; mark_name=''; shift 2 ;;
            --mark) mark_name=$2; tone_name=''; shift 2 ;;
            *) echo "barlib: popup_graph: unknown flag '$1' — dropped" >&2; shift ;;
        esac
    done
    _barlib_pop_geo
    local hue
    if [ -n "$mark_name" ]; then
        hue=$(mark "$mark_name")
    elif [ -n "$tone_name" ]; then
        hue=$(tone "$tone_name")
    elif [ -n "${BARLIB_MARK:-}" ]; then
        hue=$(mark "$BARLIB_MARK")
    else
        hue=$(tone dim)
    fi
    _barlib_tint "$hue"
    local w=$((_BARLIB_G_W - 2 * _BARLIB_G_GUTTER))
    _barlib_pop_add "graph:$w" "$_BARLIB_G_H_GRAPH" "${BAR_FONT:-}:Regular:${FS_TINY:-}" '' 0 \
        width="$w" \
        padding_left="$((_BARLIB_G_INSET + _BARLIB_G_GUTTER))" \
        padding_right="$((_BARLIB_G_INSET + _BARLIB_G_GUTTER))" \
        icon.drawing=off label.drawing=off \
        graph.color="$hue" graph.fill_color="$_BARLIB_TINT" graph.line_width=1.5
    local id="$POPUP_ID" p
    for p in $points; do
        _BARLIB_ARGS+=(--push "$id" "$(_barlib_fraction "$p")")
    done
    return 0
}

# ── the scrubber ──────────────────────────────────────────────────────────────
# popup_slider --percentage <0-100> [--width <points>] [--icon <text>]
#              [--label <text>] [--tone <tone>] [--mark <mark>] [--run <cmd>]
#
# The one row kind that is a CONTROL: a track you aim at rather than a thing
# you press. Everything above is a menu item — you read it, you click it, the
# dropdown gets out of the way. A scrubber is the opposite gesture, which is
# why it is a kind rather than a `popup_bar` with a click on it, and why
# `_barlib_pop_add` gives it the one click_script in this file with no close
# appended. Read the ⚠️ there; it is the whole design.
#
# --icon and --label are the two CAPTIONS, left and right of the track — the
# elapsed time and the total, in the shipped consumer. They are plain text in
# the note's tiny face rather than glyphs, because a scrubber's flanks are
# where a duration goes and nothing else has asked to be there.
#
# The tone/mark pair paints the FILLED half and the knob together, and defaults
# to `action`: a slider nobody has coloured is still a thing you reach for. The
# unfilled track is `surface1` and is the runtime's, the way the row fonts are
# — it is the groove, not a value. Media names a mark instead, because its
# scrubber is the same hue as the glyph on the pill and the title above it: one
# subject, three places, one colour.
#
# ⚠️ THE PERCENTAGE IS NOT A FRACTION. `graph` clamps to 0…1 because sketchybar
# scales a pushed point against the item's height; `slider.percentage` is a
# whole 0…100 and a 0.42 there is a bar that never leaves its left edge. Same
# clamp, different scale, and they are two lines apart in a widget that draws
# both — so this one takes what it is named for and says so.
#
# The click hands the position back as $PERCENTAGE, to a FRESH process (a
# click_script is a spawn, not a call). What that process can do about it is
# `popup_set "$POPUP_CLICKED" slider.percentage=…` — see popup_set for why the
# knob is the widget's to move.
#
# --width is the TRACK's; without it the track is whatever the panel has left
# after two caption columns, and the whole thing is centred in the row.
_BARLIB_SLIDER_CAPTION_COLS=5
# The knob is a runtime constant rather than a flag: it is typography, the same
# as the row fonts, and a second consumer wanting a different one is a flag to
# add then rather than a decision to hand out now.
_BARLIB_SLIDER_KNOB='󰝥'
popup_slider() {
    local pct=0 width='' icon='' label=''
    local tone_name=action mark_name='' action=''
    while [ $# -gt 0 ]; do
        case "$1" in
            --percentage) pct=$2; shift 2 ;;
            --width) width=$2; shift 2 ;;
            --icon) icon=$2; shift 2 ;;
            --label) label=$2; shift 2 ;;
            --tone) tone_name=$2; mark_name=''; shift 2 ;;
            --mark) mark_name=$2; shift 2 ;;
            --run) action=$2; shift 2 ;;
            *) echo "barlib: popup_slider: unknown flag '$1' — dropped" >&2; shift ;;
        esac
    done
    _barlib_pop_geo
    case "$pct" in '' | *[!0-9]*) pct=0 ;; esac
    if [ "$pct" -gt 100 ]; then pct=100; fi
    local fill
    if [ -n "$mark_name" ]; then
        fill=$(mark "$mark_name")
    else
        fill=$(tone "$tone_name")
    fi
    _barlib_adv "${FS_TINY:-10}"
    local cap_w=$((_BARLIB_SLIDER_CAPTION_COLS * _BARLIB_ADV))
    if [ -z "$width" ]; then
        width=$((_BARLIB_G_W - 2 * _BARLIB_G_GUTTER - 2 * cap_w - 2 * _BARLIB_G_GAP))
        if [ "$width" -lt 60 ]; then width=60; fi
    fi
    local cfont="${BAR_FONT:-}:Regular:${FS_TINY:-}"
    _barlib_pop_add "slider:$width" "$_BARLIB_G_H_ROW" "$cfont" "$action" 0 \
        align=center \
        icon="$icon" icon.color="${SUBTEXT0:-}" icon.font="$cfont" \
        icon.width=dynamic icon.align=left \
        icon.padding_left="$_BARLIB_G_GUTTER" icon.padding_right="$_BARLIB_G_GAP" \
        label="$label" label.color="${SUBTEXT0:-}" \
        label.padding_left="$_BARLIB_G_GAP" label.padding_right="$_BARLIB_G_GUTTER" \
        slider.percentage="$pct" \
        slider.background.height=4 \
        slider.background.corner_radius=2 \
        slider.background.color="${SURFACE1:-}" \
        slider.highlight_color="$fill" \
        slider.knob="$_BARLIB_SLIDER_KNOB" slider.knob.color="$fill"
}

# ── a picture ─────────────────────────────────────────────────────────────────
# popup_image --source <path|app.Name> --box <points> [--scale <n>]
#             [--corner <n>] [--pad-left <px>] [--run <command>]
#
# A row that is entirely an IMAGE — no icon, no label, no padding of its own.
# Two shapes, both in the shipped consumer, which is what earned it a kind
# rather than a pile of sb_sets:
#
#   * a WELL — `--box <n>` alone. The item is a fixed n-point square and the
#     image is drawn in it. Media's cover art.
#   * a CORNER MARK — `--box <n> --pad-left <px>`. No fixed width; the padding
#     both offsets the image rightwards AND grows the item to fit, so an item
#     whose only content is the image draws it hard against the right edge of a
#     row exactly as wide as the popup already was. Media's app-icon badge.
#
# The <px> is a MEASUREMENT of the drawn popup, so it cannot come from here —
# the widget takes it, because the widget knows which of its own rows can be
# the widest; $POPUP_ID and `popup_set` are how it puts the answer back. Both
# shapes are the one place a row is NOT the panel's width: a well is its box,
# a corner mark is its padding, and the grid leaves them alone.
#
# `--source` is a file path or SketchyBar's own `app.<Name>` form, which
# resolves against the RUNNING application — so a widget drawing one has to
# have checked that the app is running, or it draws nothing and says nothing.
popup_image() {
    local source='' box=0 scale=1 corner=6 pad='' action=''
    while [ $# -gt 0 ]; do
        case "$1" in
            --source) source=$2; shift 2 ;;
            --box) box=$2; shift 2 ;;
            --scale) scale=$2; shift 2 ;;
            --corner) corner=$2; shift 2 ;;
            --pad-left) pad=$2; shift 2 ;;
            --run) action=$2; shift 2 ;;
            *) echo "barlib: popup_image: unknown flag '$1' — dropped" >&2; shift ;;
        esac
    done
    if [ -z "$source" ]; then
        echo "barlib: popup_image: no --source — nothing to draw" >&2
        return 0
    fi
    # A box is the row's HEIGHT as well as its width, so a missing one is not a
    # small picture — it is a zero-height row that is added, laid out and
    # invisible, which reads as "the cover didn't load" rather than as a bug.
    case "$box" in
        '' | 0 | *[!0-9]*)
            echo "barlib: popup_image: --box <points> is required — nothing to draw" >&2
            return 0
            ;;
    esac
    _barlib_pop_geo
    _barlib_pop_add image "$box" "${BAR_FONT:-}:Regular:${FS_SMALL:-}" "$action" 0 \
        icon.drawing=off icon.padding_left=0 icon.padding_right=0 \
        label.drawing=off label.padding_left=0 label.padding_right=0 \
        background.corner_radius=0 \
        background.image="$source" \
        background.image.scale="$scale" \
        background.image.corner_radius="$corner" \
        background.image.drawing=on
    # A well is SIZED; a corner mark is OFFSET. Setting both would pin the item
    # to the box and then push the image out of it.
    if [ -n "$pad" ]; then
        _BARLIB_ARGS+=(--set "$POPUP_ID" width=dynamic background.image.padding_left="$pad")
    else
        _BARLIB_ARGS+=(--set "$POPUP_ID" width="$box" padding_left="$((_BARLIB_G_INSET + _BARLIB_G_GUTTER))")
    fi
    return 0
}

# popup_note --label <text> — the aside. No icon, no click of its own, on the
# text column like everything else.
popup_note() {
    local label=''
    while [ $# -gt 0 ]; do
        case "$1" in
            --label) label=$2; shift 2 ;;
            *) echo "barlib: popup_note: unknown flag '$1' — dropped" >&2; shift ;;
        esac
    done
    _barlib_pop_geo
    _barlib_text_cap "${FS_TINY:-10}" "$_BARLIB_G_TEXT_X"
    _barlib_fit "$label" "$_BARLIB_CAP"
    _barlib_pop_add note "$_BARLIB_G_H_NOTE" "${BAR_FONT:-}:Italic:${FS_TINY:-}" '' 0 \
        icon="" label="$_BARLIB_FIT" label.color="${OVERLAY0:-}"
}

# popup_separator — a hairline from gutter to gutter, with a note's worth of
# air around it. An item whose only visible part is a one-point background:
# the row is as tall as a blank tiny-face label (which is what gives the line
# its margins), and the line is centred in it.
popup_separator() {
    _barlib_pop_geo
    _barlib_pop_add separator 1 "${BAR_FONT:-}:Regular:${FS_TINY:-}" '' 0 \
        width="$((_BARLIB_G_W - 2 * _BARLIB_G_GUTTER))" \
        padding_left="$((_BARLIB_G_INSET + _BARLIB_G_GUTTER))" \
        padding_right="$((_BARLIB_G_INSET + _BARLIB_G_GUTTER))" \
        icon=" " icon.font="${BAR_FONT:-}:Regular:${FS_TINY:-}" icon.width=dynamic \
        icon.padding_left=0 icon.padding_right=0 \
        label.drawing=off \
        background.height=1 background.corner_radius=0 \
        background.color="${SURFACE1:-}"
    return 0
}

# popup_space [points] — nothing, that tall. The panel's own padding is drawn
# with it (popup_open adds one above the first row and one below the last);
# a widget wants one between two buttons, or under a picture.
popup_space() {
    local h=${1:-}
    _barlib_pop_geo
    case "$h" in
        '' | *[!0-9]*) h=$_BARLIB_G_H_PAD ;;
        *) _barlib_px "$h"; h=$_BARLIB_PX ;;
    esac
    _barlib_pop_add space "$h" "${BAR_FONT:-}:Regular:${FS_TINY:-}" '' 0 \
        icon.drawing=off label.drawing=off background.corner_radius=0
    return 0
}

# Is the dropdown up? `nil` for an item the bar could not answer about — the
# same distinction barpop's own gate draws, and for the same reason: an
# unanswered --query is not a closed popup, and treating it as one reopens a
# dropdown the user was closing.
_barlib_popup_drawing() {
    local ans
    ans=$("$SB" --query "$_BARLIB_POPUP" 2>/dev/null | jq -r '.popup.drawing // empty' 2>/dev/null)
    printf '%s' "$ans"
}

popup_close() {
    _barlib_set_on "$_BARLIB_POPUP" popup.drawing=off
    return 0
}

# Rebuild and show. The --remove goes out on its own, ahead of the batch: the
# adds below reuse the ids it is clearing, and the two cannot be reordered by
# being in one call.
#
# The batch is FLUSHED here rather than at the end of barlib_main, because
# barpop reads the popup's row rects at arm time — arming before the rows
# exist would guard a popup of the wrong shape.
#
# The panel's own padding is drawn here — one spacer above the first row and
# one below the last — and so is the CELL FLOOR: `popup.height` is SketchyBar's
# minimum slot per popup item, 30 by default, and with it in place every row
# kind's height was a fiction (a 18pt note sat in a 30pt cell). Set to 1, the
# rows are exactly as tall as they say.
popup_open() {
    "$SB" --remove "/${_BARLIB_POPUP}\.popup\..*/" 2>/dev/null
    _BARLIB_POP_I=0
    _BARLIB_POP_PAD=top; popup_space; _BARLIB_POP_PAD=''
    if declare -F popup_rows >/dev/null 2>&1; then popup_rows; fi
    _BARLIB_POP_PAD=bottom; popup_space; _BARLIB_POP_PAD=''
    _barlib_set_on "$_BARLIB_POPUP" popup.height=1 popup.drawing=on
    barlib_flush
    SKETCHYBAR_BIN="$SB" /run/current-system/sw/bin/barpop arm "$_BARLIB_POPUP" 2>/dev/null &
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
# "anything that pokes a bar pokes both" (AGENTS.md), as code.
#
# A one-line wrapper over `haus-bar-poke`, which is where the pair actually
# lives (modules/core/haus-bar-poke.sh). It moved OUT of here because this file
# is sourced by framework widgets and by nothing else, while EVERY producer of a
# both-bars trigger other than this function is something else — two plain CLIs,
# a bar script AeroSpace spawns, and two that cannot meaningfully source a
# `$HOME` path at all: a `writeShellScript` and a launchd argv. The name stays
# because a widget should not have to spell an absolute path to signal one, and
# `subscribes =` is documented against it.
#
# Absolute, for the same reason `barpop` above is: a plugin runs on SketchyBar's
# PATH, which names nothing of ours. It costs one extra fork over writing the
# two `--trigger`s here (~4 ms, measured by barpop) on an event that fires when
# something CHANGED — never on a tick — which is the whole budget for having one
# copy of this rule instead of six.
#
# `_BARLIB_`-prefixed, not `BARLIB_`: emitted keys are written into the widget's
# scope by name (see the reject list near the top), so a plain `BARLIB_BAR_POKE`
# would be a name a widget could `emit` and silently redirect every subsequent
# `bar_emit` from that widget to a path of its choosing.
#
# stderr is NOT swallowed, and that is the point of the `|| true` beside it: the
# only thing `haus-bar-poke` ever writes there is its usage error — it sends the
# bars' own noise to /dev/null itself — and a widget calling `bar_emit` with no
# event is a bug that has to reach sketchybar's log rather than repaint nothing.
bar_emit() {
    "${_BARLIB_BAR_POKE:-/run/current-system/sw/bin/haus-bar-poke}" "$@" || true
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
    barlib_flush
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
        # .global is the same event with belt and braces on: the per-item
        # mouse.exited can be MISSED when the pointer is flicked straight off
        # the bar, and a widget whose hover state is a latch (media's pill
        # un-collapses on hover) is then stuck in it until the next one. Both
        # land on the same handler, so on_unhover has to be idempotent — which
        # "the pointer is not here" already is.
        mouse.exited | mouse.exited.global)
            if declare -F on_unhover >/dev/null 2>&1; then on_unhover; fi
            ;;
        *) _barlib_tick ;;
    esac
    barlib_flush
    return 0
}

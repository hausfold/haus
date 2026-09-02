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
if [ -z "${BARLIB_SEGMENTS:-}" ] && [ -n "${0:-}" ] && [ -r "${0:-}" ]; then
    BARLIB_SEGMENTS=$(
        sed -n 's/^#[[:space:]]*widget:[[:space:]]*segments[[:space:]]*=[[:space:]]*//p' "$0" \
            | head -1 | tr ',' ' ' | tr -s '[:space:]' ' '
    )
    BARLIB_SEGMENTS="${BARLIB_SEGMENTS#"${BARLIB_SEGMENTS%%[![:space:]]*}"}"
    BARLIB_SEGMENTS="${BARLIB_SEGMENTS%"${BARLIB_SEGMENTS##*[![:space:]]}"}"
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

# ---- marks ------------------------------------------------------------------
# The IDENTITY axis, beside the ladder: which subject is this, for one the bar
# cannot know until it runs. `modules/bar/marks.nix` is the set and the whole
# argument; `bar-marks` in flake.nix diffs this case statement against it and
# refuses a mark whose palette key is also a tone's, which is the invariant —
# identity and status never share a hue.
#
# A widget names a mark exactly where it would otherwise have to spell a hex:
# a popup heading whose subject is chosen at runtime. `--tone` is still the
# only thing that may carry a VERDICT, and the two flags are last-wins on
# purpose — `--mark warm --tone mute` is how a widget greys out a block whose
# feed died without losing the mark it would draw when the feed comes back.
#
# The fallback is `plum`, the catch-all mark, and NOT grey: grey is what a
# dead feed is painted, so an unrecognised subject drawn in it would read as
# stale rather than as unfamiliar. Same leniency as tone() and for the same
# reason — a typo costs the wrong hue, never a pill that stops painting.
mark() {
    case "$1" in
        warm)   printf '%s' "${MARK_WARM:-$TONE_MUTE}" ;;
        rust)   printf '%s' "${MARK_RUST:-$TONE_MUTE}" ;;
        pink)   printf '%s' "${MARK_PINK:-$TONE_MUTE}" ;;
        violet) printf '%s' "${MARK_VIOLET:-$TONE_MUTE}" ;;
        blue)   printf '%s' "${MARK_BLUE:-$TONE_MUTE}" ;;
        teal)   printf '%s' "${MARK_TEAL:-$TONE_MUTE}" ;;
        plum)   printf '%s' "${MARK_PLUM:-$TONE_MUTE}" ;;
        *)
            echo "barlib: unknown mark '$1' (warm|rust|pink|violet|blue|teal|plum) — using plum" >&2
            printf '%s' "${MARK_PLUM:-$TONE_MUTE}"
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
# SIX ROW KINDS, and their typography is the runtime's, not the widget's:
#
#   popup_heading   a section title.      Bold, label size,   32pt tall
#   popup_row       a thing you can act on. Regular, small,   25pt
#   popup_action    a verb — Refresh, a command to copy. Bold, small, 25pt
#   popup_note      an aside — "nothing", "+4 more".  Italic, tiny, 20pt
#   popup_slider    a track you aim at rather than press.     25pt
#   popup_image     a row that is entirely a picture. --box points tall
#
# Six because that is what every popup in this bar already is; a widget
# naming ":Bold:${FS_SMALL}" itself is the hardcoded-hex mistake one layer up,
# and the seventh kind someone needs is a kind to add here rather than a --font
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
# so the arithmetic is the runtime's — the same reason the six row kinds own
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
# It goes NEGATIVE, and that is the other half: a value that right-aligns its
# own number asks for leading blanks a label may not carry (_barlib_unpad
# below), and paying for them here is what turns them back into space the row
# actually gets. So the argument is "columns the name owes the gutter",
# whichever side of zero that lands on.
#
# The advance is measured with awk, not bash arithmetic, because a font size
# out of the generated sizes.sh is a DECIMAL ("14.0") and $(( )) errors on
# one. It is cached against the size it was measured at, so a dropdown of a
# heading plus twelve rows forks awk twice rather than thirteen times — a
# popup is built inside a click, where the whole batch is one message and the
# forks would be the only thing in it that isn't.
#
# ⚠️ Which is why this SETS A GLOBAL rather than printing. It printed until
# ai_usage converted, and every call site was `$(_barlib_name_pad …)` — a
# SUBSHELL, so the cache above was written in a process that exited one line
# later and the next row measured the advance again. The comment was simply
# false: a 17-row dropdown forked awk 15 times, on the click path, for one
# number that never changes within a popup. `_barlib_unpad` below states the
# same rule from the other end. Read the answer out of $_BARLIB_PAD.
_BARLIB_ADV_FOR=''
_BARLIB_ADV_PX=''
_BARLIB_PAD=0
_barlib_name_pad() {
    local cols
    cols=$((_BARLIB_COL_NAME - ${#1} - ${2:-0}))
    if [ "$cols" -lt 1 ]; then cols=1; fi
    if [ "${3:-13}" != "$_BARLIB_ADV_FOR" ]; then
        _BARLIB_ADV_PX=$(awk -v s="${3:-13}" -v a="$_BARLIB_ADV" 'BEGIN { printf "%.0f", s * a }')
        _BARLIB_ADV_FOR="${3:-13}"
    fi
    _BARLIB_PAD=$(((cols * _BARLIB_ADV_PX + _BARLIB_COL_GAP * 1000 + 500) / 1000))
}

# A value that RIGHT-aligns its number — ` 7%` under `46%`, ` 733M` under
# `6.14B` — asks for leading blanks, and a label is the one place they cannot
# go: sketchybar sizes an item from the TRIMMED string and then draws the
# untrimmed one, so the row loses exactly its own indent off the right edge.
# (A no-break space is trimmed just the same. That is the obvious fix and it
# does not work.) It is the same trap as padding with trailing spaces, which
# the value column already exists to avoid — so the runtime honours leading
# blanks the only way that works, by turning them back into the column count
# the caller is already paying for in padding.
#
# Sets two globals rather than printing: `$(_barlib_unpad …)` is a subshell
# and the count would never come back out of one.
_BARLIB_UNPADDED=''
_BARLIB_LEAD=0
_barlib_unpad() { # _barlib_unpad <value> → _BARLIB_UNPADDED, _BARLIB_LEAD
    _BARLIB_UNPADDED="${1#"${1%%[! ]*}"}"
    _BARLIB_LEAD=$(( ${#1} - ${#_BARLIB_UNPADDED} ))
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
# <kind> is which of them this is. Only `slider:<width>` branches — the other
# five are one word of self-description in the emission, and the next kind that
# needs to behave differently adds an arm here rather than a flag upstream.
# The slider is also the one that is not an `--add item`: `--add slider <id>
# <parent> <width>` is an item TYPE, the same shape `frameworkBlock` uses for
# `--add graph`, and every other property below behaves identically. It is
# subscribed to mouse.clicked because that is what makes sketchybar hand the
# click's position back as $PERCENTAGE — the whole mechanism of a seek.
#
# $POPUP_ID is the id of the row just added, for the rare widget that has to
# reach one again after the batch has gone out (media measures its dropdown
# and nudges an image into the corner). Read it immediately; the next row
# overwrites it.
POPUP_ID=''
_barlib_pop_add() { # _barlib_pop_add <kind> <height> <font> <action> <set-args…>
    local kind=$1 height=$2 font=$3 action=$4
    shift 4
    local width=''
    case "$kind" in
        slider:*)
            width=${kind#slider:}
            kind=slider
            ;;
    esac
    POPUP_ID="${_BARLIB_POPUP}.popup.${_BARLIB_POP_I}"
    local close="$SB --set $_BARLIB_POPUP popup.drawing=off"
    local click="$close"
    if [ -n "$action" ]; then click="$action; $close"; fi
    if [ "$kind" = slider ]; then
        click="$action"
        _BARLIB_ARGS+=(--add slider "$POPUP_ID" "popup.${_BARLIB_POPUP}" "$width")
    else
        _BARLIB_ARGS+=(--add item "$POPUP_ID" "popup.${_BARLIB_POPUP}")
    fi
    _BARLIB_ARGS+=(
        --set "$POPUP_ID"
        icon="" icon.padding_left=10 icon.padding_right=8
        label="" label.padding_left=0 label.padding_right=14
        label.font="$font"
        background.drawing=off background.height="$height"
        click_script="$click"
        "$@"
    )
    if [ "$kind" = slider ]; then
        _BARLIB_ARGS+=(--subscribe "$POPUP_ID" mouse.clicked)
    fi
    _BARLIB_POP_I=$((_BARLIB_POP_I + 1))
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
# ⚠️ A `width` would not do the cap's job: sketchybar's is a STATIC size, not a
# maximum, so setting one pads a three-word title out to the same wide box. Two
# separate --sets on the same batched call, so an unwanted one is simply absent
# rather than set to a value meaning "off".
_barlib_pop_cap() {
    if [ "${1:-0}" -gt 0 ] 2>/dev/null; then
        _BARLIB_ARGS+=(--set "$POPUP_ID" label.max_chars="$1")
    fi
    if [ "${2:-0}" = 1 ]; then
        _BARLIB_ARGS+=(--set "$POPUP_ID" scroll_texts=on)
    fi
    return 0
}

# popup_heading --label <text> [--icon <glyph>] [--icon-font <font>]
#               [--tone <tone>] [--mark <mark>] [--label-tone <tone>]
#               [--count <n>] [--value <text>] [--run <command>]
#               [--max-chars <n>] [--marquee]
# --run makes the heading CLICKABLE, on the same terms as a row: the command,
# then the popup closes. It is for a block whose rows all mean one thing —
# the agents pill's per-agent block is a name line and a detail line that
# both mean "this pane", and a heading a few pixels tall is a bad target for
# "this is the one I meant". Give both rows the same --run and the block
# becomes one hit area, which is what a widget is really asking for when it
# wants a clickable heading.
# --count appends " · n" when n is above zero: a section that says "open PRs"
# over eight rows leaves you counting them to find out whether eight is all of
# them, and the rows below may be a truncation.
# The default is `dim`, not `mute`: a section title with no verdict of its own
# is still a title. Every popup in this bar already drew one that way — agents
# and calendar still paint the section glyph overlay1 and reserve overlay0 for
# the meta row under it, as vitals_lib and ai_usage did before they converted —
# and `mute` here made the heading read as absent rather than quiet.
#
# --mark is the IDENTITY half (see mark() above), for a heading whose subject
# the bar cannot know until it runs. --tone and --mark are LAST-WINS rather
# than an error together: `--mark warm --tone mute` is a widget saying "this
# is Claude, and its feed is dead", which is one heading with two things to
# say and a legitimate order to say them in.
#
# --label-tone paints the LABEL half, and defaults to the ordinary foreground
# — which is what every heading drew before the flag existed, so nothing moves
# unless a widget asks. It is the same two-tone shape `pill` has and exists for
# the same job one layer down: a section whose subject has gone quiet greys as
# a BLOCK, mark and title together. A dim mark under a full-brightness name
# reads as a rendering bug rather than as a feed that stopped reporting, and
# `--tone dim` alone could only ever reach the mark. In the two-column form the
# label half is the VALUE, and the flag colours that — it is "the label's
# tone" either way.
#
# --icon-font is for a glyph that does not exist in the bar's own face —
# sketchybar-app-font's `:claude:` and `:openai:` are the shipped case. It is
# NOT a typography flag: the runtime still owns the weight and the size of
# everything a heading draws, and the fifth row KIND someone needs is still a
# kind to add rather than a --font to add here. This is which font the GLYPH
# lives in, which is a fact about the glyph and not a choice about the row.
popup_heading() {
    local label='' icon='' icon_font='' tone_name=dim mark_name='' count=0
    local value='' have_value=0 label_tone='' cap=0 marquee=0 action=''
    while [ $# -gt 0 ]; do
        case "$1" in
            --label) label=$2; shift 2 ;;
            --run) action=$2; shift 2 ;;
            --icon) icon=$2; shift 2 ;;
            --icon-font) icon_font=$2; shift 2 ;;
            --tone) tone_name=$2; mark_name=''; shift 2 ;;
            --mark) mark_name=$2; shift 2 ;;
            --label-tone) label_tone=$2; shift 2 ;;
            --count) count=$2; shift 2 ;;
            --value) value=$2; have_value=1; shift 2 ;;
            --max-chars) cap=$2; shift 2 ;;
            --marquee) marquee=1; shift ;;
            *) echo "barlib: popup_heading: unknown flag '$1' — dropped" >&2; shift ;;
        esac
    done
    local icon_color
    if [ -n "$mark_name" ]; then
        icon_color=$(mark "$mark_name")
    else
        icon_color=$(tone "$tone_name")
    fi
    local label_color="${TEXT:-}"
    if [ -n "$label_tone" ]; then label_color=$(tone "$label_tone"); fi
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
        #
        # ⚠️ That merge is also why --icon-font cannot apply here: the glyph and
        # the title share ONE item, so a glyph-only face would draw the title as
        # tofu. Warned and ignored rather than silently dropping the glyph — a
        # mark in the wrong face is a thing someone reports, a mark that is
        # missing is a thing nobody notices.
        if [ -n "$icon_font" ]; then
            echo "barlib: popup_heading: --icon-font is ignored with --value (glyph and title share one item)" >&2
        fi
        local _blib_name="$label" _blib_cols=0
        if [ -n "$icon" ]; then
            _blib_name="$icon $label"
            _blib_cols=2
        fi
        _barlib_unpad "$value"
        _barlib_name_pad "$label" "$((_blib_cols - _BARLIB_LEAD))" "${FS_LABEL:-13}"
        _barlib_pop_add heading "$_BARLIB_H_HEADING" "${BAR_FONT:-}:Bold:${FS_LABEL:-}" "$action" \
            icon="$_blib_name" icon.color="$icon_color" \
            icon.font="${BAR_FONT:-}:Bold:${FS_LABEL:-}" \
            icon.padding_left=10 \
            icon.padding_right="$_BARLIB_PAD" \
            label="$_BARLIB_UNPADDED" label.color="$label_color"
        _barlib_pop_cap "$cap" "$marquee"
        return 0
    fi
    # The default is spelled out rather than left inherited, so there is one
    # code path instead of two: it is byte-identical to the icon.font every
    # popup row already gets from sketchybarrc's `--default`, so a heading
    # that names no font draws exactly as it did before this flag existed.
    _barlib_pop_add heading "$_BARLIB_H_HEADING" "${BAR_FONT:-}:Bold:${FS_LABEL:-}" "$action" \
        icon="$icon" icon.color="$icon_color" \
        icon.font="${icon_font:-${BAR_FONT:-}:Bold:${FS_ICON:-}}" \
        label="$label" label.color="$label_color"
    _barlib_pop_cap "$cap" "$marquee"
}

# popup_row --label <text> [--icon <glyph>] [--tone <tone>] [--value <text>]
#           [--name-tone <tone>] [--open <url>] [--run <command>]
#           [--max-chars <n>] [--marquee]
# A `mute` row loses a shade of its TEXT too, not only its glyph colour:
# otherwise a list of eight reads as eight equal claims on you when two of
# them are their author saying "not yet". Only `mute` — a `dim` row keeps its
# full-brightness label on purpose, because dim is the row still being ABOUT
# something; it is the glyph that is subordinate, not the sentence.
popup_row() {
    local label='' icon='' icon_tone=mute action='' value='' have_value=0 tone_set=0
    local cap=0 marquee=0 name_tone=dim name_tone_set=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --label) label=$2; shift 2 ;;
            --name-tone) name_tone=$2; name_tone_set=1; shift 2 ;;
            --icon) icon=$2; shift 2 ;;
            --tone) icon_tone=$2; tone_set=1; shift 2 ;;
            --value) value=$2; have_value=1; shift 2 ;;
            --open) action="/usr/bin/open $(popup_quote "$2")"; shift 2 ;;
            --run) action=$2; shift 2 ;;
            --max-chars) cap=$2; shift 2 ;;
            --marquee) marquee=1; shift ;;
            *) echo "barlib: popup_row: unknown flag '$1' — dropped" >&2; shift ;;
        esac
    done
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
        local _blib_name="$label" _blib_cols=0
        if [ -n "$icon" ]; then
            _blib_name="$icon $label"
            _blib_cols=2
        fi
        # An EMPTY --label is a continuation row: the name column is left
        # blank and the value still lands on it, so the second line of a block
        # sits under the first instead of beside it. It needs no branch of its
        # own — an empty icon still reserves its padding, which is the whole
        # mechanism — but it is a shape worth knowing is available.
        _barlib_unpad "$value"
        _barlib_name_pad "$label" "$((_blib_cols - _BARLIB_LEAD))" "${FS_SMALL:-12}"
        _barlib_pop_add row "$_BARLIB_H_ROW" "${BAR_FONT:-}:Bold:${FS_SMALL:-}" "$action" \
            icon="$_blib_name" icon.color="$(tone "$name_tone")" \
            icon.font="${BAR_FONT:-}:Regular:${FS_SMALL:-}" \
            icon.padding_left="$_BARLIB_ROW_INDENT" \
            icon.padding_right="$_BARLIB_PAD" \
            label="$_BARLIB_UNPADDED" label.color="$(tone "$icon_tone")"
        _barlib_pop_cap "$cap" "$marquee"
        return 0
    fi
    local lcolor="${SUBTEXT0:-}"
    if [ "$icon_tone" = mute ]; then lcolor="${OVERLAY0:-}"; fi
    _barlib_pop_add row "$_BARLIB_H_ROW" "${BAR_FONT:-}:Regular:${FS_SMALL:-}" "$action" \
        icon="$icon" icon.color="$(tone "$icon_tone")" \
        label="$label" label.color="$lcolor"
    _barlib_pop_cap "$cap" "$marquee"
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
    _barlib_pop_add action "$_BARLIB_H_ROW" "${BAR_FONT:-}:Bold:${FS_SMALL:-}" "$action" \
        icon="$icon" icon.color="$(tone "$icon_tone")" \
        label="$label" label.color="${SUBTEXT0:-}"
}

# ---- the scrubber -----------------------------------------------------------
# popup_slider --percentage <0-100> [--width <points>] [--icon <text>]
#              [--label <text>] [--tone <tone>] [--mark <mark>] [--run <cmd>]
#
# The fifth row kind, and the only CONTROL among them: a track you aim at
# rather than a thing you press. Everything above is a menu item — you read it,
# you click it, the dropdown gets out of the way. A scrubber is the opposite
# gesture, which is why it is a kind rather than a `popup_row` with a bar drawn
# in it, and why `_barlib_pop_add` gives it the one click_script in this file
# with no close appended. Read the ⚠️ there; it is the whole design.
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
_BARLIB_SLIDER_W=150
# The knob is a runtime constant rather than a flag: it is typography, the same
# as the row fonts, and a second consumer wanting a different one is a flag to
# add then rather than a decision to hand out now.
_BARLIB_SLIDER_KNOB='󰝥'
popup_slider() {
    local pct=0 width="$_BARLIB_SLIDER_W" icon='' label=''
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
    case "$pct" in '' | *[!0-9]*) pct=0 ;; esac
    if [ "$pct" -gt 100 ]; then pct=100; fi
    local fill
    if [ -n "$mark_name" ]; then
        fill=$(mark "$mark_name")
    else
        fill=$(tone "$tone_name")
    fi
    _barlib_pop_add "slider:$width" "$_BARLIB_H_ROW" \
        "${BAR_FONT:-}:Regular:${FS_TINY:-}" "$action" \
        icon="$icon" icon.color="${SUBTEXT0:-}" \
        icon.font="${BAR_FONT:-}:Regular:${FS_TINY:-}" \
        icon.padding_left=10 icon.padding_right=8 \
        label="$label" label.color="${SUBTEXT0:-}" \
        label.padding_left=8 label.padding_right=12 \
        slider.percentage="$pct" \
        slider.background.height=4 \
        slider.background.corner_radius=2 \
        slider.background.color="${SURFACE1:-}" \
        slider.highlight_color="$fill" \
        slider.knob="$_BARLIB_SLIDER_KNOB" slider.knob.color="$fill"
}

# ---- a picture --------------------------------------------------------------
# popup_image --source <path|app.Name> --box <points> [--scale <n>]
#             [--corner <n>] [--pad-left <px>] [--run <command>]
#
# The sixth kind: a row that is entirely an IMAGE — no icon, no label, no
# padding of its own. Two shapes, both in the shipped consumer, which is what
# earned it a kind rather than a pile of sb_sets:
#
#   * a WELL — `--box <n>` alone. The item is a fixed n-point square and the
#     image is drawn in it. Media's cover art.
#   * a CORNER MARK — `--box <n> --pad-left <px>`. No fixed width; the padding
#     both offsets the image rightwards AND grows the item to fit, so an item
#     whose only content is the image draws it hard against the right edge of a
#     row exactly as wide as the popup already was. That is the only right-align
#     sketchybar has: a popup is a stack of LEFT-aligned items, every item's
#     background is as wide as its own content, and there is no alignment
#     property. Media's app-icon badge.
#
# The <px> is a MEASUREMENT of the drawn popup, so it cannot come from here —
# a row cannot know how wide the rows below it will be, and nothing has any
# width at all until the popup has been on screen once. The widget takes it,
# because the widget knows which of its own rows can be the widest; $POPUP_ID
# and `popup_set` are how it puts the answer back.
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
    _barlib_pop_add image "$box" "${BAR_FONT:-}:Regular:${FS_SMALL:-}" "$action" \
        icon.drawing=off icon.padding_left=0 icon.padding_right=0 \
        label.drawing=off label.padding_left=0 label.padding_right=0 \
        background.drawing=on background.color=0x00000000 \
        background.image="$source" \
        background.image.scale="$scale" \
        background.image.corner_radius="$corner" \
        background.image.drawing=on
    # A well is SIZED; a corner mark is OFFSET. Setting both would pin the item
    # to the box and then push the image out of it.
    if [ -n "$pad" ]; then
        _BARLIB_ARGS+=(--set "$POPUP_ID" background.image.padding_left="$pad")
    else
        _BARLIB_ARGS+=(--set "$POPUP_ID" width="$box")
    fi
    return 0
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
    _barlib_pop_add note "$_BARLIB_H_NOTE" "${BAR_FONT:-}:Italic:${FS_TINY:-}" '' \
        icon="" label="$label" label.color="${OVERLAY0:-}"
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
popup_open() {
    "$SB" --remove "/${_BARLIB_POPUP}\.popup\..*/" 2>/dev/null
    _BARLIB_POP_I=0
    if declare -F popup_rows >/dev/null 2>&1; then popup_rows; fi
    _barlib_set_on "$_BARLIB_POPUP" popup.drawing=on
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
# is sourced by framework widgets and by nothing else, while three of the four
# producers of a both-bars trigger are not widgets — a `writeShellScript`, a
# launchd argv and two plain CLIs, none of which can meaningfully source a
# `$HOME` path. The name stays because a widget should not have to spell an
# absolute path to signal one, and `subscribes =` is documented against it.
#
# Absolute, for the same reason `barpop` above is: a plugin runs on SketchyBar's
# PATH, which names nothing of ours. It costs one extra fork over writing the
# two `--trigger`s here (~4 ms, measured by barpop) on an event that fires when
# something CHANGED — never on a tick — which is the whole budget for having one
# copy of this rule instead of five.
bar_emit() {
    "${BARLIB_BAR_POKE:-/run/current-system/sw/bin/haus-bar-poke}" "$@" 2>/dev/null || true
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

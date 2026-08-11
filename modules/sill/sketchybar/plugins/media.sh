#!/bin/bash

# The media pill's hands: its tick, its gestures, and the dropdown behind it.
# Rendering the pill itself is media_lib.sh's `media_render`, fed by
# plugins/media_stream.sh — the pill is driven by a long-running
# `media-control stream` rather than by SketchyBar's `media_change` event, which
# Apple killed in macOS 15.4 (see modules/sill/media-control.nix).
#
# THE GESTURES, in one place, because they are also what the option reference
# promises:
#
#   left click        the dropdown          cover, scrubber, transport
#   right click       play / pause          the one thing you do most
#   ⌥ + click         next track
#   ⇧ + click         previous track
#   ⌘ + click         focus the TAB the sound is coming from (not just the app)
#   scroll            seek ±10s
#   hover             sweep a long title once, start to finish (see below)
#
# Left-click is the dropdown, the same as weather, agents, ai_usage and the
# calendar — every pill on this bar that HAS a dropdown opens it on a left
# click, and this one used to be the exception. (The elgato pill's left click
# still toggles the light: it has no dropdown to be inconsistent about.) The argument for the exception was that the pill is a CONTROL
# rather than a readout, so its most-pressed action should be its cheapest; what
# that missed is that "click the pill, get the thing" is the rule you learn ONCE
# and then apply to a bar full of pills, and being made to remember which single
# pill inverts it costs more than the button swap saves. Play/pause moves to the
# right button, where it is still one click and still on the pill.

export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/usr/bin:/bin:$PATH"

source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/sizes.sh"
source "$HOME/.config/sketchybar/media_config.sh"
source "$HOME/.config/sketchybar/plugins/media_lib.sh"
SILL_ITEM=media
source "$HOME/.config/sketchybar/bar.sh"

# Keyed on the plugin directory, so a copy of these plugins run from anywhere
# else cannot capture this bar's streamer — media_stream.sh carries the whole
# reasoning, including why the directory is the invoked path and not the resolved
# one. These three lines are deliberately IDENTICAL there, character for
# character, rather than factored into media_lib.sh: the lib is sourced through a
# hardcoded ~/.config path, so a stray copy would source the real one and derive
# the real key, which is precisely the isolation this is buying. Duplicated on
# purpose; keep them in step.
SILL_PLUGIN_DIR="$(dirname "${BASH_SOURCE[0]}")"
SILL_STREAM_KEY="$(id -u).$(printf '%s' "$SILL_PLUGIN_DIR" | shasum -a 256 | cut -c1-12)"
PIDFILE="/tmp/sketchybar_media_stream.$SILL_STREAM_KEY.pid"

[ -n "$SILL_MEDIA_CONTROL" ] && [ -x "$SILL_MEDIA_CONTROL" ] || exit 0

mkdir -p "$SILL_MEDIA_STATE_DIR" 2>/dev/null

close_popup() { $SB --set media popup.drawing=off; }

# ── the marquee ──────────────────────────────────────────────────────────────
# Hover is the ONLY thing that starts a sweep — nothing fires one off a track
# change or on any kind of interval. One hover, one full pass through the title
# back to its start, no matter how briefly the pointer was actually on the pill:
# the lock makes a sweep a promise it keeps once made, so mouse.exited below
# does not (and must not) cut it off early. Re-entering while a sweep is still
# running is a no-op — mkdir fails, the in-flight one is left alone — so
# hovering on and off mid-sweep can't restart it from the top.
MARQUEE_SECONDS=8

start_marquee() {
    mkdir "$SILL_MEDIA_STATE_DIR/marquee.lock" 2>/dev/null || return
    $SB --set media scroll_texts=on
    (
        sleep "$MARQUEE_SECONDS"
        $SB --set media scroll_texts=off
        rmdir "$SILL_MEDIA_STATE_DIR/marquee.lock" 2>/dev/null
    ) &
}

# ── the dropdown ─────────────────────────────────────────────────────────────
# Built on open, from the state file, never kept warm: a popup nobody has opened
# is a set of items sketchybar still lays out on every repaint. Every row is
# accumulated into ARGS and handed over in ONE call, so it appears fully formed
# instead of growing a row at a time — the same lesson ai_usage.sh's dropdown
# learned the visible way.
build_popup() {
    local kind icon accent art scale sub elapsed dur pct label_app badge
    media_read_now || return 1

    kind="$(media_kind "$MEDIA_BUNDLE" "$MEDIA_TITLE" "$MEDIA_ARTIST" "$MEDIA_ALBUM" "$MEDIA_DURATION")"
    icon="$(media_icon "$kind" "$MEDIA_BUNDLE")"
    accent="$(media_color "$kind")"
    label_app="$(media_app_name "$MEDIA_PID" "$MEDIA_BUNDLE")"

    $SB --remove '/media\.popup\..*/' 2>/dev/null

    # Shared row geometry. The click_script is NOT in here: every row has one,
    # but only some of them act — the rest just close the dropdown, the way a
    # menu item you didn't mean to press should.
    ROW=(
        background.drawing=off
        background.height=26
        icon.padding_left=10
        icon.padding_right=8
        label.padding_right=12
        icon.font="$BAR_FONT:Bold:$FS_APP_ICON"
        label.font="$BAR_FONT:Regular:$FS_SMALL"
    )
    CLOSE="$HOME/.config/sketchybar/plugins/media.sh close"
    ARGS=()
    n=0
    row() { # row <icon> <label> <icon.color> <label.color> [action]
        local click="$CLOSE"
        [ -n "${5:-}" ] && click="$HOME/.config/sketchybar/plugins/media.sh do $5"
        ARGS+=(--add item "media.popup.$n" popup.media
            --set "media.popup.$n" "${ROW[@]}"
            icon="$1" label="$2" icon.color="$3" label.color="$4"
            click_script="$click")
        n=$((n + 1))
    }

    # ── the cover ────────────────────────────────────────────────────────────
    # Only when the source actually published one — no Firefox-family browser
    # ever does. There is deliberately no app-icon stand-in here any more: a
    # 56pt icon in an 84pt cover well read as an ill-fitting hero image (a lot
    # of dead space around something too small to be one). Nothing else at the
    # top has to fill that gap — the title row below carries the kind glyph,
    # and the source app gets named in the "Show in <App>" row down in the
    # transport, plus a small icon badge in the bottom-right corner. RUNNING is
    # checked separately, right where that badge is built, well below — a cover
    # well only ever holds a real cover now.
    art="$(ls -1 "$SILL_MEDIA_ART".* 2>/dev/null | head -1)"
    if [ -n "$art" ] && [ -s "$art" ]; then
        scale="$(cat "$SILL_MEDIA_ART_SCALE" 2>/dev/null)"
        [ -n "$scale" ] || scale=0.16
        ARGS+=(--add item media.popup.art popup.media
            --set media.popup.art
            icon.drawing=off icon.padding_left=0 icon.padding_right=0
            label.drawing=off label.padding_left=0 label.padding_right=0
            width="$SILL_MEDIA_ART_BOX" background.height="$SILL_MEDIA_ART_BOX"
            background.drawing=on background.color=0x00000000
            background.image="$art"
            background.image.scale="$scale"
            background.image.corner_radius=6
            background.image.drawing=on
            click_script="$CLOSE")
    fi

    # ── what it is ───────────────────────────────────────────────────────────
    # max_chars, not a fixed width: sketchybar's `width` is a static size, not
    # a cap, and setting one forced every title — a three-word one included —
    # to the same wide box. max_chars leaves a short title sized to itself and
    # only kicks in once one actually runs long, at which point scroll_texts
    # sweeps the part it cut off — the popup's answer to the pill's own hover
    # marquee, just running for as long as the dropdown stays open rather than
    # one timed pass.
    ARGS+=(--add item media.popup.title popup.media
        --set media.popup.title "${ROW[@]}"
        icon="$icon" icon.color="$accent"
        label="$MEDIA_TITLE" label.color="$TEXT"
        label.font="$BAR_FONT:Bold:$FS_SMALL"
        label.max_chars="$SILL_MEDIA_POPUP_MAX_CHARS" scroll_texts=on)

    sub="$MEDIA_ARTIST"
    [ -n "$MEDIA_ALBUM" ] && sub="${sub:+$sub — }$MEDIA_ALBUM"
    if [ -n "$sub" ]; then
        ARGS+=(--add item media.popup.sub popup.media
            --set media.popup.sub "${ROW[@]}"
            icon="" icon.padding_left=0 icon.padding_right=0
            label="$sub" label.color="$SUBTEXT0"
            label.padding_left=38
            label.max_chars="$SILL_MEDIA_POPUP_MAX_CHARS" scroll_texts=on)
    fi

    # ── the scrubber ─────────────────────────────────────────────────────────
    # A slider, not a progress read-out: clicking it seeks. SketchyBar hands the
    # click's position back as $PERCENTAGE, which is the whole mechanism — see
    # the `seek` action below.
    dur="${MEDIA_DURATION%%.*}"
    if [ -n "$dur" ] && [ "$dur" -gt 0 ] 2>/dev/null; then
        elapsed="$(media_elapsed_now "$MEDIA_ELAPSED" "$MEDIA_STAMP" "$MEDIA_PLAYING" "$MEDIA_RATE")"
        pct=$((${elapsed:-0} * 100 / dur))
        [ "$pct" -gt 100 ] && pct=100
        [ "$pct" -lt 0 ] && pct=0
        ARGS+=(--add slider media.popup.seek popup.media 150
            --set media.popup.seek
            background.drawing=off
            icon="$(media_fmt_time "$elapsed")" icon.color="$SUBTEXT0"
            icon.font="$BAR_FONT:Regular:$FS_TINY"
            icon.padding_left=10 icon.padding_right=8
            label="$(media_fmt_time "$dur")" label.color="$SUBTEXT0"
            label.font="$BAR_FONT:Regular:$FS_TINY"
            label.padding_left=8 label.padding_right=12
            slider.percentage="$pct"
            slider.background.height=4
            slider.background.corner_radius=2
            slider.background.color="$SURFACE1"
            slider.highlight_color="$accent"
            slider.knob="󰝥" slider.knob.color="$accent"
            click_script="$HOME/.config/sketchybar/plugins/media.sh do seek"
            --subscribe media.popup.seek mouse.clicked)
    fi

    # ── the transport ────────────────────────────────────────────────────────
    # A vertical menu rather than a ⏮⏯⏭ button strip: labelled rows teach the
    # pill's own gestures, which is what the keyboard-free half of this
    # dropdown is for.
    if [ "$MEDIA_PLAYING" = "true" ]; then
        row "󰏤" "Pause" "$accent" "$TEXT" "toggle"
    else
        row "󰐊" "Play" "$accent" "$TEXT" "toggle"
    fi
    row "󰒭" "Next" "$SUBTEXT1" "$TEXT" "next"
    row "󰒮" "Previous" "$SUBTEXT1" "$TEXT" "prev"
    row "󰒝" "Shuffle" "$SUBTEXT1" "$SUBTEXT0" "shuffle"
    row "󰑖" "Repeat" "$SUBTEXT1" "$SUBTEXT0" "repeat"
    badge=0
    if [ -n "$label_app" ]; then
        row "󰏋" "Show in $label_app" "$SUBTEXT1" "$SUBTEXT0" "focus"
        # A small app-icon badge FLOATING in the bottom-right corner, below the
        # last row — the source's identity, sized and placed as the aside it is.
        # It spent a while as a row of its own directly above "Show in …" and
        # that read wrong: a full-width row of nothing but an icon looks like a
        # menu entry you're meant to click, wedged between two you are. The
        # corner is where a "this came from over there" mark belongs.
        #
        # Only when there's no real cover (next to actual artwork it is pure
        # clutter — and the cover already answers the same question) and only
        # while the app is confirmed RUNNING, since SketchyBar resolves
        # `app.<Name>` off the running application. The right-alignment can't be
        # expressed here; media_badge_align does it once the popup's width is
        # measurable, immediately after this batch.
        if { [ -z "$art" ] || [ ! -s "$art" ]; } &&
            [ -n "$MEDIA_PID" ] && ps -p "$MEDIA_PID" >/dev/null 2>&1; then
            badge=1
            ARGS+=(--add item media.popup.appicon popup.media
                --set media.popup.appicon
                icon.drawing=off icon.padding_left=0 icon.padding_right=0
                label.drawing=off label.padding_left=0 label.padding_right=0
                background.height="$SILL_MEDIA_BADGE_BOX"
                background.drawing=on background.color=0x00000000
                background.image="app.$label_app"
                background.image.scale="$SILL_MEDIA_BADGE_SCALE"
                background.image.corner_radius=6
                background.image.drawing=on
                click_script="$HOME/.config/sketchybar/plugins/media.sh do focus")
        fi
    fi

    [ ${#ARGS[@]} -gt 0 ] && $SB "${ARGS[@]}" 2>/dev/null

    # Right-align the badge before anything is on screen. It can only measure
    # once this popup has been drawn at least once (see media_badge_align), so
    # on the very first open it reports back that it guessed, and open_popup
    # runs it again the moment there is a laid-out popup to measure.
    MEDIA_BADGE_PENDING=0
    if [ "$badge" = 1 ]; then
        media_badge_align || MEDIA_BADGE_PENDING=1
    fi
    return 0
}

open_popup() {
    # Closing is just hiding: a click while the dropdown is up must not rebuild
    # the rows first, or closing flashes through a relayout on the way out.
    if [ "$($SB --query media 2>/dev/null | jq -r '.popup.drawing' 2>/dev/null)" = "on" ]; then
        close_popup
        return
    fi
    build_popup || return
    $SB --set media popup.drawing=on
    [ "${MEDIA_BADGE_PENDING:-0}" = 1 ] && media_badge_align
    # Then hand it to sillpop so it also closes on the first click anywhere else
    # — the dismissal sketchybar can't do, since it only hears clicks on its own
    # items. Backgrounded and after the reveal, so opening costs what it did
    # above. SKETCHYBAR_BIN is what tells sillpop WHICH bar to guard: unset, it
    # queries the top one, finds no such item on a pill that moved to the bottom
    # bar, and exits before it ever arms.
    SKETCHYBAR_BIN="$SB" /run/current-system/sw/bin/sillpop arm media 2>/dev/null &
}

# ── actions ──────────────────────────────────────────────────────────────────
# Everything the dropdown's rows and the pill's gestures actually do. No repaint
# afterwards on purpose: the stream sees the state change and repaints on its
# own, which is both faster than doing it here and the only version that stays
# right when the change came from somewhere else entirely.
do_action() {
    case "$1" in
    toggle) "$SILL_MEDIA_CONTROL" toggle-play-pause >/dev/null 2>&1 ;;
    next) "$SILL_MEDIA_CONTROL" next-track >/dev/null 2>&1 ;;
    prev) "$SILL_MEDIA_CONTROL" previous-track >/dev/null 2>&1 ;;
    shuffle) "$SILL_MEDIA_CONTROL" toggle-shuffle >/dev/null 2>&1 ;;
    repeat) "$SILL_MEDIA_CONTROL" toggle-repeat >/dev/null 2>&1 ;;
    focus)
        # Closed first and then done in the background, unlike every other
        # action here: reaching a browser TAB can take a second of scripted
        # typing (see media_focus_tab_firefox), and neither a dropdown still
        # sitting open over the window you're being sent to nor a click_script
        # holding a SketchyBar worker thread for that long is acceptable.
        close_popup
        media_read_now || return
        (media_focus_source "$MEDIA_BUNDLE" "$MEDIA_TITLE" \
            "$(media_app_name "$MEDIA_PID" "$MEDIA_BUNDLE")" &) 2>/dev/null
        return
        ;;
    seek)
        # $PERCENTAGE is where in the slider the click landed. Only meaningful
        # with a duration, which is why the slider isn't drawn without one.
        #
        # This is the one action that does NOT close the dropdown: scrubbing is
        # something you do twice when the first landing was a second out, and a
        # menu that vanishes under the pointer makes the correction impossible.
        # The knob is moved here too — SketchyBar does not move it on a click of
        # its own accord, and it would otherwise sit where it was until the popup
        # was rebuilt, i.e. until the next time you opened it.
        media_read_now || return
        local dur="${MEDIA_DURATION%%.*}" target
        [ -n "$dur" ] && [ "$dur" -gt 0 ] 2>/dev/null || return
        [ -n "${PERCENTAGE:-}" ] || return
        target=$((dur * PERCENTAGE / 100))
        "$SILL_MEDIA_CONTROL" seek "$target" >/dev/null 2>&1
        $SB --set media.popup.seek slider.percentage="$PERCENTAGE" \
            icon="$(media_fmt_time "$target")"
        return
        ;;
    esac
    close_popup
}

# Scrolling the pill nudges playback. Rate-limited with a lock a sleeper drops,
# because a trackpad flick is dozens of events and each one is a perl re-exec —
# unthrottled, a single swipe would queue seconds of seeking.
scroll_seek() {
    local delta="${SCROLL_DELTA:-0}" dur elapsed target
    case "$delta" in 0 | "") return ;; esac
    mkdir "$SILL_MEDIA_STATE_DIR/scroll.lock" 2>/dev/null || return
    (
        sleep 0.4
        rmdir "$SILL_MEDIA_STATE_DIR/scroll.lock" 2>/dev/null
    ) &

    media_read_now || return
    dur="${MEDIA_DURATION%%.*}"
    [ -n "$dur" ] && [ "$dur" -gt 0 ] 2>/dev/null || return
    elapsed="$(media_elapsed_now "$MEDIA_ELAPSED" "$MEDIA_STAMP" "$MEDIA_PLAYING" "$MEDIA_RATE")"
    case "$delta" in
    -*) target=$((${elapsed:-0} - 10)) ;;
    *) target=$((${elapsed:-0} + 10)) ;;
    esac
    [ "$target" -lt 0 ] && target=0
    [ "$target" -gt "$dur" ] && target="$dur"
    "$SILL_MEDIA_CONTROL" seek "$target" >/dev/null 2>&1
}

# ── the watchdog ─────────────────────────────────────────────────────────────
# The tick's first job is noticing a stream that died (the adapter is a
# private-framework trick; assuming it runs forever would mean a pill that goes
# dark until the next login). Restarting it repaints from the current state.
#
# The pid is matched against the process's own command line, not just kill -0: a
# streamer killed without running its trap leaves the pidfile behind, and PIDs
# get reused, so a live-looking pid is not on its own evidence the stream is up.
# The match is against the FULL path we would launch, not the bare basename: a
# copy of the script run from elsewhere satisfied the loose form, which made this
# watchdog certify a stranger's stream as ours and stop restarting the real one.
# It is launched from the same variable it is matched on, so the two cannot drift.
tick() {
    local pid
    pid="$(cat "$PIDFILE" 2>/dev/null)"
    if [ -z "$pid" ] || ! ps -p "$pid" -o command= 2>/dev/null |
        grep -qF "$SILL_PLUGIN_DIR/media_stream.sh"; then
        ("$SILL_PLUGIN_DIR/media_stream.sh" >/dev/null 2>&1 &)
        return
    fi
    # Stream alive: the only thing left that can be stale is a long-form
    # countdown, which nothing pushes because nothing about the track changed.
    if media_read_now && [ "$MEDIA_PLAYING" = "true" ]; then
        media_render
    fi
}

case "${1:-}" in
close)
    close_popup
    exit 0
    ;;
do)
    do_action "${2:-}"
    exit 0
    ;;
click)
    # A plain click sends MODIFIER=none (not empty), so test against "none".
    case "${BUTTON:-left}" in
    right) do_action toggle ;;
    *)
        case "${MODIFIER:-none}" in
        *alt*) do_action next ;;
        *shift*) do_action prev ;;
        *cmd*) do_action focus ;;
        *) open_popup ;;
        esac
        ;;
    esac
    exit 0
    ;;
esac

case "${SENDER:-}" in
mouse.entered)
    # Hovering is the "show me the whole thing" gesture: it un-collapses a
    # collapsed pill and starts a one-shot marquee sweep (a no-op if one is
    # already running — see start_marquee).
    : >"$SILL_MEDIA_STATE_DIR/hover"
    media_read_now && media_render
    start_marquee
    ;;
mouse.exited | mouse.exited.global)
    # The .global twin is belt and braces: the per-item mouse.exited can be
    # missed when the pointer is flicked straight off the bar, and a stranded
    # hover flag means a collapsed pill stays expanded forever. Only the hover
    # flag is cleared here — an in-flight sweep runs to completion regardless of
    # hover, so scroll_texts is deliberately left alone; start_marquee's own
    # timer is what turns it back off.
    rm -f "$SILL_MEDIA_STATE_DIR/hover" 2>/dev/null
    media_read_now && media_render
    ;;
mouse.scrolled)
    scroll_seek
    ;;
*)
    tick
    ;;
esac

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
#   left click        play / pause          the one thing you do most
#   right click       the dropdown          cover, scrubber, transport, history
#   ⌥ + click         next track
#   ⇧ + click         previous track
#   ⌘ + click         focus the app the sound is coming from
#   scroll            seek ±10s
#   hover             sweep a long title once, start to finish (see below)
#
# Left-click stays play/pause rather than becoming the dropdown (which is what
# weather, agents and ai_usage do with a left click) because this pill is a
# CONTROL, not a readout: the elgato pill sets the same precedent, and moving the
# machine's most-pressed bar action behind a menu to gain consistency would be a
# bad trade. The dropdown takes the right button instead.

export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/usr/bin:/bin:$PATH"

source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/sizes.sh"
source "$HOME/.config/sketchybar/media_config.sh"
source "$HOME/.config/sketchybar/plugins/media_lib.sh"
SILL_ITEM=media
source "$HOME/.config/sketchybar/bar.sh"

PIDFILE="/tmp/sketchybar_media_stream.pid"

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
    local kind icon accent art scale sub elapsed dur pct label_app
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
    # A real cover when the source published one; the source app's own icon when
    # it didn't, which is most of the time — no Firefox-family browser publishes
    # artwork at all. SketchyBar resolves `app.<Name>` by application NAME, not
    # by bundle id, which is why media_app_name reads it off the running process.
    art="$(ls -1 "$SILL_MEDIA_ART".* 2>/dev/null | head -1)"
    if [ -n "$art" ] && [ -s "$art" ]; then
        scale="$(cat "$SILL_MEDIA_ART_SCALE" 2>/dev/null)"
        [ -n "$scale" ] || scale=0.2
        ARGS+=(--add item media.popup.art popup.media
            --set media.popup.art
            icon.drawing=off label.drawing=off
            width=84 background.height=84
            background.drawing=on background.color=0x00000000
            background.image="$art"
            background.image.scale="$scale"
            background.image.corner_radius=6
            background.image.drawing=on
            click_script="$CLOSE")
    elif [ -n "$label_app" ] && [ -n "$MEDIA_PID" ] && ps -p "$MEDIA_PID" >/dev/null 2>&1; then
        # Only while the source app is actually RUNNING. SketchyBar resolves
        # `app.<Name>` against live applications and logs "Invalid application
        # name" for anything else — and once the pid is gone media_app_name is
        # down to the bundle id's last component, which is a lowercase
        # executable stub ("zen"), not an application name ("Zen").
        ARGS+=(--add item media.popup.art popup.media
            --set media.popup.art
            icon.drawing=off label.drawing=off
            width=56 background.height=56
            background.drawing=on background.color=0x00000000
            background.image="app.$label_app"
            background.image.scale=0.9
            background.image.drawing=on
            click_script="$CLOSE")
    fi

    # ── what it is ───────────────────────────────────────────────────────────
    ARGS+=(--add item media.popup.title popup.media
        --set media.popup.title "${ROW[@]}"
        icon="$icon" icon.color="$accent"
        label="$MEDIA_TITLE" label.color="$TEXT"
        label.font="$BAR_FONT:Bold:$FS_SMALL"
        label.max_chars=42)

    sub="$MEDIA_ARTIST"
    [ -n "$MEDIA_ALBUM" ] && sub="${sub:+$sub — }$MEDIA_ALBUM"
    if [ -n "$sub" ]; then
        ARGS+=(--add item media.popup.sub popup.media
            --set media.popup.sub "${ROW[@]}"
            icon="" icon.padding_left=0 icon.padding_right=0
            label="$sub" label.color="$SUBTEXT0"
            label.padding_left=38 label.max_chars=42)
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
    # A vertical menu rather than a ⏮⏯⏭ button strip: SketchyBar lays a popup out
    # in ONE direction, and a horizontal popup would have cost the history list
    # below. Labelled rows also teach the pill's own gestures, which is what the
    # keyboard-free half of this dropdown is for.
    if [ "$MEDIA_PLAYING" = "true" ]; then
        row "󰏤" "Pause" "$accent" "$TEXT" "toggle"
    else
        row "󰐊" "Play" "$accent" "$TEXT" "toggle"
    fi
    row "󰒭" "Next" "$SUBTEXT1" "$TEXT" "next"
    row "󰒮" "Previous" "$SUBTEXT1" "$TEXT" "prev"
    row "󰒝" "Shuffle" "$SUBTEXT1" "$SUBTEXT0" "shuffle"
    row "󰑖" "Repeat" "$SUBTEXT1" "$SUBTEXT0" "repeat"
    [ -n "$label_app" ] && row "󰏋" "Show in $label_app" "$SUBTEXT1" "$SUBTEXT0" "focus"

    # ── what came before ─────────────────────────────────────────────────────
    # macOS keeps no now-playing history — nothing on the machine can answer
    # "what was that track before this one" ten seconds after it ends. So the
    # streamer writes each change down, and this is the only place it surfaces.
    # The rows are deliberately inert: there is no track identifier in the
    # payload that anything could be asked to play again.
    if [ -s "$SILL_MEDIA_HISTORY" ]; then
        local h_epoch h_title h_artist h_bundle h_kind shown=0
        ARGS+=(--add item media.popup.hist popup.media
            --set media.popup.hist "${ROW[@]}"
            icon="" icon.padding_left=0 icon.padding_right=0
            label="recently played" label.color="$OVERLAY1"
            label.font="$BAR_FONT:Italic:$FS_TINY"
            label.padding_left=12)
        # Newest first, and never the track that is playing right now.
        while IFS="$SILL_MEDIA_FS" read -r h_epoch h_title h_artist h_bundle; do
            [ -n "$h_title" ] || continue
            [ "$h_title" = "$MEDIA_TITLE" ] && continue
            h_kind="$(media_kind "$h_bundle" "$h_title" "$h_artist" "" "")"
            row "$(media_icon "$h_kind" "$h_bundle")" \
                "$h_title${h_artist:+ — $h_artist}" "$OVERLAY1" "$SUBTEXT0"
            shown=$((shown + 1))
            [ "$shown" -ge 4 ] && break
        done < <(tail -r "$SILL_MEDIA_HISTORY" 2>/dev/null)
    fi

    [ ${#ARGS[@]} -gt 0 ] && $SB "${ARGS[@]}" 2>/dev/null
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
        media_read_now || return
        [ -n "$MEDIA_BUNDLE" ] && open -b "$MEDIA_BUNDLE" 2>/dev/null
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
tick() {
    local pid
    pid="$(cat "$PIDFILE" 2>/dev/null)"
    if [ -z "$pid" ] || ! ps -p "$pid" -o command= 2>/dev/null | grep -q media_stream.sh; then
        ("$HOME/.config/sketchybar/plugins/media_stream.sh" >/dev/null 2>&1 &)
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
    right) open_popup ;;
    *)
        case "${MODIFIER:-none}" in
        *alt*) do_action next ;;
        *shift*) do_action prev ;;
        *cmd*) do_action focus ;;
        *) do_action toggle ;;
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

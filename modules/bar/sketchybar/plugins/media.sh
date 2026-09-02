#!/bin/bash
# widget: interval   = 30
# widget: popup      = true
# widget: subscribes = mouse.entered, mouse.exited, mouse.exited.global, mouse.scrolled
#
# The media pill: what is playing, the gestures that drive it, and the dropdown
# behind it. A framework widget (ops/todo/bar-framework.md) — the header above is
# the whole of its wiring, and barlib owns the bar instance, the batching, the
# state diff, the dropdown's rows and every colour. What is left here is the
# pill's actual subject: what a now-playing session says, what you can do to it
# from a menu bar, and the one control on this bar you AIM rather than press.
#
# It is fed by a long-running `media-control stream` (plugins/media_stream.sh)
# rather than by SketchyBar's `media_change` event, which Apple killed in macOS
# 15.4 — see modules/bar/media-control.nix. The stream asks for a repaint
# through `media_paint`, which re-enters this file's `paint` mode; the interval
# above is the watchdog that notices a stream that died, and the tick that
# advances a long-form countdown nothing publishes a payload for.
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
# still toggles the light: it has no dropdown to be inconsistent about.) The
# argument for the exception was that the pill is a CONTROL rather than a
# readout, so its most-pressed action should be its cheapest; what that missed
# is that "click the pill, get the thing" is the rule you learn ONCE and then
# apply to a bar full of pills, and being made to remember which single pill
# inverts it costs more than the button swap saves. Play/pause moves to the
# right button, where it is still one click and still on the pill.
#
# ── what the conversion gave up, deliberately ────────────────────────────────
# Four of the seven hues this pill spent on WHAT IS PLAYING were the tone
# ladder's: Spotify was `ok`, VLC was `warn`, a video in a browser tab was
# `bad`, and music in one was `action`. They are marks now (media_lib.sh's
# `media_mark`), which is the invariant marks exist for — identity and status
# never share a hue — and it is the one thing about this pill that looks
# different afterwards. The transport rows lost their per-row greys to the row
# kinds, and the popup's title lost a couple of points of height to
# `popup_heading`; both are the framework owning typography, which is what
# stops the next pill inventing a fifth grey.

export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/usr/bin:/bin:$PATH"

# BAR_ITEM is what bar.sh routes on when there is no $BAR_NAME — which is every
# invocation that did not come from SketchyBar: the stream's repaint, the art
# fetch's, and the dropdown's own click_scripts. The pill is movable via
# haus.bar.bottom.items, so a bare `sketchybar` would keep talking to a top-bar
# item that is no longer there.
BAR_ITEM=media
source "$HOME/.config/sketchybar/barlib.sh"
source "$HOME/.config/sketchybar/media_config.sh"
# shellcheck source=./media_lib.sh
source "$HOME/.config/sketchybar/plugins/media_lib.sh"

SELF="$HOME/.config/sketchybar/plugins/media.sh"

# Keyed on the plugin directory, so a copy of these plugins run from anywhere
# else cannot capture this bar's streamer — media_stream.sh carries the whole
# reasoning, including why the directory is the invoked path and not the resolved
# one. These three lines are deliberately IDENTICAL there, character for
# character, rather than factored into media_lib.sh: the lib is sourced through a
# hardcoded ~/.config path, so a stray copy would source the real one and derive
# the real key, which is precisely the isolation this is buying. Duplicated on
# purpose; keep them in step.
BAR_PLUGIN_DIR="$(dirname "${BASH_SOURCE[0]}")"
BAR_STREAM_KEY="$(id -u).$(printf '%s' "$BAR_PLUGIN_DIR" | shasum -a 256 | cut -c1-12)"
PIDFILE="/tmp/sketchybar_media_stream.$BAR_STREAM_KEY.pid"

[ -n "$BAR_MEDIA_CONTROL" ] && [ -x "$BAR_MEDIA_CONTROL" ] || exit 0

mkdir -p "$BAR_MEDIA_STATE_DIR" 2>/dev/null

# ── the tick ─────────────────────────────────────────────────────────────────
# The watchdog first. The adapter is a private-framework trick, so assuming the
# stream runs forever would mean a pill that goes dark until the next login.
# Restarting it repaints from the current state on its own.
#
# The pid is matched against the process's own command line, not just kill -0: a
# streamer killed without running its trap leaves the pidfile behind, and PIDs
# get reused, so a live-looking pid is not on its own evidence the stream is up.
# The match is against the FULL path we would launch, not the bare basename: a
# copy of the script run from elsewhere satisfied the loose form, which made this
# watchdog certify a stranger's stream as ours and stop restarting the real one.
# It is launched from the same variable it is matched on, so the two cannot drift.
watchdog() {
    local pid
    pid="$(cat "$PIDFILE" 2>/dev/null)"
    if [ -z "$pid" ] || ! ps -p "$pid" -o command= 2>/dev/null |
        grep -qF "$BAR_PLUGIN_DIR/media_stream.sh"; then
        ("$BAR_PLUGIN_DIR/media_stream.sh" >/dev/null 2>&1 &)
    fi
}

# Everything the pill SAYS, as state barlib diffs. The tick, the stream's
# repaint, the hover and the unhover all arrive here, so a payload that changed
# nothing — media-control republishes on every seek and every rate change —
# costs no sketchybar traffic at all, which the old in-process render could not
# manage.
#
# ⚠️ The long-form countdown is why `elapsed` is folded into `label` rather than
# emitted beside it: the label is what the diff is ABOUT. A countdown that moved
# from -13m to -12m is a repaint; a track that advanced eleven seconds inside
# the same minute is not, and emitting the raw elapsed would make every tick of
# every long video a repaint that drew the identical string.
fetch() {
    # ⚠️ Not on the stream's path. `fetch` is reached from `media_paint` too —
    # once per payload, which media-control republishes on every seek and every
    # rate change — and a stream asking us to paint is itself the proof that
    # the stream is alive. Checking would be a `cat`, a `ps` and a `grep` per
    # payload to re-establish what the caller's existence already said. The
    # 30 s tick is what actually watches, and it is the only caller that can
    # be right about a stream that has died.
    [ "${BAR_MEDIA_PAINTING:-0}" = 1 ] || watchdog

    # No session at all: gone, not an empty box — the way the pill has always
    # behaved. The dropdown goes with it, or it would be left describing a
    # track that stopped existing.
    if ! media_read_now; then
        emit hidden=1
        return 0
    fi

    local kind label dur elapsed remain tint=""
    kind="$(media_kind "$MEDIA_BUNDLE" "$MEDIA_TITLE" "$MEDIA_ARTIST" "$MEDIA_ALBUM" "$MEDIA_DURATION")"

    label="$MEDIA_TITLE"
    [ -n "$MEDIA_ARTIST" ] && label="$MEDIA_TITLE — $MEDIA_ARTIST"

    # Long-form gets a countdown instead of a scrolling title. An hour-long video
    # or a podcast is a thing you already know the name of; what you keep
    # glancing at the bar for is how much of it is left.
    dur="${MEDIA_DURATION%%.*}"
    if [ -n "$dur" ] && [ "$dur" -ge "$BAR_MEDIA_LONGFORM" ] 2>/dev/null; then
        elapsed="$(media_elapsed_now "$MEDIA_ELAPSED" "$MEDIA_STAMP" "$MEDIA_PLAYING" "$MEDIA_RATE")"
        remain=$((dur - ${elapsed:-0}))
        [ "$remain" -lt 0 ] && remain=0
        label="$MEDIA_TITLE  ·  -$(media_fmt_remaining "$remain")"
    fi

    # Collapsed: the glyph alone until the pointer arrives. Worth having because
    # the bar's centre span is under the notch on a MacBook and every character
    # of title is rent — see haus.bar.media.collapse. An EMPTY label is what
    # `pill` reads as "absent", and it re-centres the icon on the way — which
    # the hand-written version never did, so a collapsed pill used to sit
    # visibly left of centre in its own background.
    if [ "${BAR_MEDIA_COLLAPSE:-0}" = "1" ] && ! media_hovered; then
        label=""
    fi

    # The artwork tint, when it's on and a track has one: a colour sampled from
    # the cover and then SNAPPED to the nearest nebelung member (see
    # media_art.sh). So the pill picks up the record's mood without ever drawing
    # a colour that isn't in haus's palette.
    #
    # It is the one hex a framework widget in this repo names, and it is the
    # case the rule is not about: a mark is a colour chosen from a set the bar
    # knows, and this is a colour MEASURED off a photograph. There is no name
    # for it to have.
    #
    # ⚠️ Only while PLAYING, and that is not an optimisation. Paused is said by
    # dimming the glyph, and a tint painted over the top of it takes that away
    # — on a collapsed pill, where the glyph is the entire pill, it would take
    # away the only thing left saying which state you are in. The hand-written
    # render got this by overwriting `color` in its paused branch, AFTER the
    # tint; the tint is emitted as state here, so the state is where it has to
    # be decided.
    if [ "$MEDIA_PLAYING" = "true" ] &&
        [ "${BAR_MEDIA_ARTWORK_TINT:-0}" = "1" ] && [ -r "$BAR_MEDIA_TINT" ]; then
        tint="$(cat "$BAR_MEDIA_TINT" 2>/dev/null)"
        case "$tint" in 0x????????) ;; *) tint="" ;; esac
    fi

    emit hidden=0 \
        icon="$(media_icon "$kind" "$MEDIA_BUNDLE")" \
        imark="$(media_mark "$kind")" \
        label="$label" \
        playing="$MEDIA_PLAYING" \
        tint="$tint"
}

# Paused stays on the bar (Control Center keeps it too — it's how you find your
# way back to it) but dims, so "playing" is still readable at a glance without
# spending a second glyph on it. `--mark` then `--tone dim` is the last-wins
# pair barlib gives a glyph with two things to say: this is a podcast, and it
# is not playing.
render() {
    if [ "$hidden" = 1 ]; then
        pill --hide
        popup_close
        return 0
    fi
    if [ "$playing" = "true" ]; then
        pill --icon "$icon" --label "$label" --mark "$imark" --label-tone text
    else
        pill --icon "$icon" --label "$label" --mark "$imark" --tone dim --label-tone dim
    fi
    if [ -n "$tint" ]; then sb_set icon.color="$tint"; fi
}

# ── the marquee ──────────────────────────────────────────────────────────────
# Hover is the ONLY thing that starts a sweep — nothing fires one off a track
# change or on any kind of interval. One hover, one full pass through the title
# back to its start, no matter how briefly the pointer was actually on the pill:
# the lock makes a sweep a promise it keeps once made, so on_unhover below does
# not (and must not) cut it off early. Re-entering while a sweep is still
# running is a no-op — mkdir fails, the in-flight one is left alone — so
# hovering on and off mid-sweep can't restart it from the top.
MARQUEE_SECONDS=8

start_marquee() {
    # haus.bar.media.marquee, which haus.appearance.reduceMotion sets off. The
    # guard is HERE rather than at the call sites because both of them (hover,
    # and the render that follows it) want the same answer, and a sweep that is
    # never started needs no stopping — scroll_texts is only ever turned on in
    # this function, so with it off the pill simply clips.
    [ "${BAR_MEDIA_MARQUEE:-1}" = "1" ] || return 0
    mkdir "$BAR_MEDIA_STATE_DIR/marquee.lock" 2>/dev/null || return 0
    sb_set scroll_texts=on
    # `sb_now`, not `sb_set`, in the detached half: barlib_main flushed and this
    # process exited eight seconds ago, so a batched --set here would go into an
    # array nobody sends and the title would sweep forever.
    (
        sleep "$MARQUEE_SECONDS"
        sb_now scroll_texts=off
        rmdir "$BAR_MEDIA_STATE_DIR/marquee.lock" 2>/dev/null
    ) &
}

# ── the dropdown ─────────────────────────────────────────────────────────────
# Built on open, from the state file, never kept warm: a popup nobody has opened
# is a set of items sketchybar still lays out on every repaint. barlib owns the
# --remove of the old rows, the ids, the one batched --add and the barpop arm
# that closes it on the first click anywhere else.
#
# The two ids caught out of $POPUP_ID are the badge's alignment problem, and
# only that: see media_badge_measure. Cleared first, because popup_rows runs
# again on every open and a stale id from the last one would be measured
# against a dropdown that no longer has that row.
MEDIA_TITLE_ROW=""
MEDIA_SUB_ROW=""
MEDIA_BADGE_ROW=""

popup_rows() {
    local kind icon imark art scale sub elapsed dur pct label_app marquee=""
    MEDIA_TITLE_ROW=""
    MEDIA_SUB_ROW=""
    MEDIA_BADGE_ROW=""
    media_read_now || return 0

    kind="$(media_kind "$MEDIA_BUNDLE" "$MEDIA_TITLE" "$MEDIA_ARTIST" "$MEDIA_ALBUM" "$MEDIA_DURATION")"
    icon="$(media_icon "$kind" "$MEDIA_BUNDLE")"
    imark="$(media_mark "$kind")"
    label_app="$(media_app_name "$MEDIA_PID" "$MEDIA_BUNDLE")"

    # The dropdown's two long rows sweep for as long as the popup is OPEN, which
    # makes them the most persistent motion on the bar and the first thing
    # haus.bar.media.marquee has to reach — a hover sweep at least ends by
    # itself. Off, --max-chars still caps them, so the row clips instead.
    [ "${BAR_MEDIA_MARQUEE:-1}" = "1" ] && marquee="--marquee"

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
    art="$(ls -1 "$BAR_MEDIA_ART".* 2>/dev/null | head -1)"
    if [ -n "$art" ] && [ -s "$art" ]; then
        scale="$(cat "$BAR_MEDIA_ART_SCALE" 2>/dev/null)"
        [ -n "$scale" ] || scale=0.16
        popup_image --source "$art" --box "$BAR_MEDIA_ART_BOX" --scale "$scale"
    fi

    # ── what it is ───────────────────────────────────────────────────────────
    # The title is the dropdown's heading, and the kind glyph beside it is the
    # pill's own mark — the same colour as the pill outside it and as the
    # scrubber below. One subject, three places, one hue.
    # shellcheck disable=SC2086
    popup_heading --icon "$icon" --mark "$imark" --label "$MEDIA_TITLE" \
        --max-chars "$BAR_MEDIA_POPUP_MAX_CHARS" $marquee
    MEDIA_TITLE_ROW="$POPUP_ID"

    # `--tone dim` on a row with no glyph is not decoration: `mute` is
    # popup_row's default and takes the LABEL down a shade with it, and this
    # subtitle is the row still being about something rather than an absence.
    sub="$MEDIA_ARTIST"
    [ -n "$MEDIA_ALBUM" ] && sub="${sub:+$sub — }$MEDIA_ALBUM"
    if [ -n "$sub" ]; then
        # shellcheck disable=SC2086
        popup_row --label "$sub" --tone dim \
            --max-chars "$BAR_MEDIA_POPUP_MAX_CHARS" $marquee
        MEDIA_SUB_ROW="$POPUP_ID"
    fi

    # ── the scrubber ─────────────────────────────────────────────────────────
    # A slider, not a progress read-out: clicking it seeks. SketchyBar hands the
    # click's position back as $PERCENTAGE, which is the whole mechanism — see
    # the `seek` action below, and popup_slider for why this is the one row in
    # the bar that does not close the dropdown under your hand.
    dur="${MEDIA_DURATION%%.*}"
    if [ -n "$dur" ] && [ "$dur" -gt 0 ] 2>/dev/null; then
        elapsed="$(media_elapsed_now "$MEDIA_ELAPSED" "$MEDIA_STAMP" "$MEDIA_PLAYING" "$MEDIA_RATE")"
        pct=$((${elapsed:-0} * 100 / dur))
        [ "$pct" -lt 0 ] && pct=0
        popup_slider --percentage "$pct" --mark "$imark" \
            --icon "$(media_fmt_time "$elapsed")" \
            --label "$(media_fmt_time "$dur")" \
            --run "$SELF do seek"
    fi

    # ── the transport ────────────────────────────────────────────────────────
    # A vertical menu rather than a ⏮⏯⏭ button strip: labelled rows teach the
    # pill's own gestures, which is what the keyboard-free half of this
    # dropdown is for.
    #
    # Play/pause is the one `popup_action` — the verb you opened this for, and
    # `action` is the rung for a thing you press. The rest are `popup_row`s:
    # things you can act on, in the two greys the row kind already owns. That
    # is one grey fewer than the hand-written version had, which is the
    # framework taking a decision back rather than a shade being lost.
    if [ "$MEDIA_PLAYING" = "true" ]; then
        popup_action --icon "󰏤" --label "Pause" --run "$SELF do toggle"
    else
        popup_action --icon "󰐊" --label "Play" --run "$SELF do toggle"
    fi
    popup_row --icon "󰒭" --label "Next" --tone dim --run "$SELF do next"
    popup_row --icon "󰒮" --label "Previous" --tone dim --run "$SELF do prev"
    popup_row --icon "󰒝" --label "Shuffle" --tone dim --run "$SELF do shuffle"
    popup_row --icon "󰑖" --label "Repeat" --tone dim --run "$SELF do repeat"

    [ -n "$label_app" ] || return 0
    popup_row --icon "󰏋" --label "Show in $label_app" --tone dim --run "$SELF do focus"

    # A small app-icon badge FLOATING in the bottom-right corner, below the
    # last row — the source's identity, sized and placed as the aside it is.
    # It spent a while as a row of its own directly above "Show in …" and that
    # read wrong: a full-width row of nothing but an icon looks like a menu
    # entry you're meant to click, wedged between two you are. The corner is
    # where a "this came from over there" mark belongs.
    #
    # Only when there's no real cover (next to actual artwork it is pure
    # clutter — and the cover already answers the same question) and only while
    # the app is confirmed RUNNING, since SketchyBar resolves `app.<Name>` off
    # the running application.
    if { [ -z "$art" ] || [ ! -s "$art" ]; } &&
        [ -n "$MEDIA_PID" ] && ps -p "$MEDIA_PID" >/dev/null 2>&1; then
        popup_image --source "app.$label_app" \
            --box "$BAR_MEDIA_BADGE_BOX" --scale "$BAR_MEDIA_BADGE_SCALE" \
            --pad-left "$(media_badge_pad)" \
            --run "$SELF do focus"
        MEDIA_BADGE_ROW="$POPUP_ID"
    fi
    return 0
}

# ── actions ──────────────────────────────────────────────────────────────────
# Everything the dropdown's rows and the pill's gestures actually do. No repaint
# afterwards on purpose: the stream sees the state change and repaints on its
# own, which is both faster than doing it here and the only version that stays
# right when the change came from somewhere else entirely.
#
# The CLOSE is not here either, and that is barlib's doing rather than an
# omission: every popup row's click_script ends in one, so a row that acts and a
# row that only dismisses are the same shape and neither has to remember.
do_action() {
    case "$1" in
    toggle) "$BAR_MEDIA_CONTROL" toggle-play-pause >/dev/null 2>&1 ;;
    next) "$BAR_MEDIA_CONTROL" next-track >/dev/null 2>&1 ;;
    prev) "$BAR_MEDIA_CONTROL" previous-track >/dev/null 2>&1 ;;
    shuffle) "$BAR_MEDIA_CONTROL" toggle-shuffle >/dev/null 2>&1 ;;
    repeat) "$BAR_MEDIA_CONTROL" toggle-repeat >/dev/null 2>&1 ;;
    focus)
        # Closed first and then done in the background, unlike every other
        # action here: reaching a browser TAB can take a second of scripted
        # typing (see media_focus_tab_firefox), and neither a dropdown still
        # sitting open over the window you're being sent to nor a click_script
        # holding a SketchyBar worker thread for that long is acceptable. A row
        # closes on its own way out too, but that close is the LAST thing in
        # the click_script and this is a whole second earlier.
        popup_close
        barlib_flush
        media_read_now || return 0
        (media_focus_source "$MEDIA_BUNDLE" "$MEDIA_TITLE" \
            "$(media_app_name "$MEDIA_PID" "$MEDIA_BUNDLE")" &) 2>/dev/null
        ;;
    seek)
        # $PERCENTAGE is where in the slider the click landed. Only meaningful
        # with a duration, which is why the slider isn't drawn without one.
        #
        # The knob is moved here too — SketchyBar does not move it on a click
        # of its own accord, and it would otherwise sit where it was until the
        # popup was rebuilt, i.e. until the next time you opened it. That is
        # what `popup_set` is for, and $POPUP_CLICKED is how a fresh process
        # knows which row it belongs to: this is a click_script, so it is a
        # spawn rather than a call, and the row's id arrived as $NAME before
        # the runtime stripped it back to the pill.
        media_read_now || return 0
        local dur="${MEDIA_DURATION%%.*}" target
        [ -n "$dur" ] && [ "$dur" -gt 0 ] 2>/dev/null || return 0
        # Digits only before it reaches `$(( ))`, which EVALUATES its operand
        # rather than reading it — the same clamp popup_slider puts on the way
        # in, on the way back out.
        case "${PERCENTAGE:-}" in '' | *[!0-9]*) return 0 ;; esac
        [ "$PERCENTAGE" -le 100 ] || PERCENTAGE=100
        target=$((dur * PERCENTAGE / 100))
        "$BAR_MEDIA_CONTROL" seek "$target" >/dev/null 2>&1
        popup_set "$POPUP_CLICKED" slider.percentage="$PERCENTAGE" \
            icon="$(media_fmt_time "$target")"
        ;;
    esac
    return 0
}

# ── clicks ───────────────────────────────────────────────────────────────────
# The gesture table at the top of this file, as handlers. barlib routes the
# button and the modifier (the button outranks the modifier, and a chord nobody
# handles falls back to on_click), so the nested case statement this used to be
# is gone.
on_click() {
    popup_toggle
    # The badge can only be placed from a measurement of the DRAWN popup, so it
    # is taken here rather than inside popup_rows — one query per candidate row,
    # on the click path, and only when there is a badge to place. It is
    # remembered, so the next open puts the badge in its corner before anything
    # is on screen; this call is what makes that answer exist. Harmless after a
    # close, where the rows are merely hidden and still measure the same.
    if [ -n "$MEDIA_BADGE_ROW" ]; then
        media_badge_measure "$MEDIA_BADGE_ROW" "$MEDIA_TITLE_ROW" "$MEDIA_SUB_ROW"
    fi
}

# Every gesture on the PILL that is not "open the dropdown" also dismisses one
# that is already up — which is what the hand-written version got for free from
# the `close_popup` that ended `do_action`. That one close served two callers:
# the pill's gestures, and every popup ROW whose click_script ran an action
# (rows with nothing to do carried a bare close instead). It cannot live there
# any more, because barlib now appends a close to every row's click_script and
# one inside `do_action` would be the second — so the half the rows no longer
# need has to be spelled out on the half that still does. Scroll is the
# deliberate exception, the same as before: seeking ±10s is something you do
# repeatedly, and the pill is where you do it whether the dropdown is up or not.
on_right_click() {
    do_action toggle
    popup_close
}
on_alt_click() {
    do_action next
    popup_close
}
on_shift_click() {
    do_action prev
    popup_close
}
# focus closes first thing itself, a whole second before the tab search returns.
on_cmd_click() { do_action focus; }

# Scrolling the pill nudges playback. Rate-limited with a lock a sleeper drops,
# because a trackpad flick is dozens of events and each one is a perl re-exec —
# unthrottled, a single swipe would queue seconds of seeking.
on_scroll() {
    local delta="${SCROLL_DELTA:-0}" dur elapsed target
    case "$delta" in 0 | "") return 0 ;; esac
    mkdir "$BAR_MEDIA_STATE_DIR/scroll.lock" 2>/dev/null || return 0
    (
        sleep 0.4
        rmdir "$BAR_MEDIA_STATE_DIR/scroll.lock" 2>/dev/null
    ) &

    media_read_now || return 0
    dur="${MEDIA_DURATION%%.*}"
    [ -n "$dur" ] && [ "$dur" -gt 0 ] 2>/dev/null || return 0
    elapsed="$(media_elapsed_now "$MEDIA_ELAPSED" "$MEDIA_STAMP" "$MEDIA_PLAYING" "$MEDIA_RATE")"
    case "$delta" in
    -*) target=$((${elapsed:-0} - 10)) ;;
    *) target=$((${elapsed:-0} + 10)) ;;
    esac
    [ "$target" -lt 0 ] && target=0
    [ "$target" -gt "$dur" ] && target="$dur"
    "$BAR_MEDIA_CONTROL" seek "$target" >/dev/null 2>&1
}

# Hovering is the "show me the whole thing" gesture: it un-collapses a collapsed
# pill and starts a one-shot marquee sweep (a no-op if one is already running —
# see start_marquee). The flag is a file because `fetch` wants the answer and
# a --query on the click path would be a round trip for something two events
# already know.
on_hover() {
    : >"$BAR_MEDIA_STATE_DIR/hover"
    barlib_tick
    start_marquee
}

# Both mouse.exited and its .global twin land here — the per-item one can be
# missed when the pointer is flicked straight off the bar, and a stranded hover
# flag means a collapsed pill stays expanded forever. Only the flag is cleared:
# an in-flight sweep runs to completion regardless of hover, so scroll_texts is
# deliberately left alone and start_marquee's own timer turns it back off.
on_unhover() {
    rm -f "$BAR_MEDIA_STATE_DIR/hover" 2>/dev/null
    barlib_tick
}

# ── entry points ─────────────────────────────────────────────────────────────
# Two CLI modes, both re-entering this file rather than being separate scripts,
# and both ending in `exit 0` so they NEVER fall through to barlib_main — which
# routes on $SENDER, and a CLI invocation's SENDER is whatever it inherited.
# `paint` is spawned from inside the streamer, which has one; landing back in a
# click handler from there is the fork loop barlib.sh's header describes.
#
# `do` ends in a flush rather than a tick: the action already told
# media-control, and the stream is what says so on the pill. The flush is for
# the knob the seek just moved and the popup the focus just closed — a batch
# nobody sends is a slider that snaps back under your finger.
case "${1:-}" in
paint)
    BAR_MEDIA_PAINTING=1
    barlib_tick
    exit 0
    ;;
do)
    do_action "${2:-}"
    barlib_flush
    exit 0
    ;;
esac

barlib_main "$@"

#!/bin/bash

# The vocabulary the three halves of the media pill share: what is playing, what
# KIND of thing it is, which glyph and colour that earns, and where the little
# bit of state they pass between each other lives.
#
# Sourced, never run. media_stream.sh (the live renderer), media.sh (the tick and
# the click router) and the dropdown media.sh builds all classify the same track
# the same way — a glyph table written twice is a glyph table that ends up being
# two, which is the same reason colors.sh and sizes.sh are generated once.
#
# THE THING THIS FILE CANNOT DO, so nobody re-discovers it the hard way: name the
# SITE a browser is playing. media-control's payload is
#   playing, title, artist, album, duration, elapsedTime, timestamp,
#   playbackRate, bundleIdentifier, processIdentifier, contentItemIdentifier
# and that is all of it — there is no URL, and macOS's now-playing session simply
# does not carry one. Three routes were tried and all three are dead ends:
#   * window titles (aerospace/AX) — only ever the FOREGROUND tab, and the tab
#     playing audio is usually a background one; measured directly.
#   * artwork shape (16:9 = video, 1:1 = music) — Firefox-family browsers publish
#     no artwork at all, so the discriminator is missing exactly where it's needed.
#   * lsof on processIdentifier — that pid is the browser's PARENT process; the
#     sockets live in content/socket processes it doesn't own.
# So the classification below is honest about what it knows: it splits VIDEO from
# MUSIC (an album is published by every music service and by no video site) and
# draws a neutral glyph for each, rather than guessing a brand and being wrong on
# Netflix. A rice that knows better overrides the glyph through
# haus.sill.media.icons — that option is this limitation's escape hatch.

SILL_MEDIA_STATE_DIR="$HOME/.local/state/nebelhaus/media"
SILL_MEDIA_NOW="$SILL_MEDIA_STATE_DIR/now"

# The field separator for both of those files, and it is deliberately NOT a tab.
# Tab is IFS *whitespace*, which bash collapses: a run of them is one delimiter,
# so `IFS=$'\t' read a b c` on "x<TAB><TAB>z" puts z in b and leaves c empty.
# Every one of these records has an optional field in the middle (an empty album
# is the normal case for anything that isn't music), so that collapse silently
# shifted the bundle id into the album and the duration into the bundle — the
# pill drew the wrong glyph for every browser tab. US (0x1f) is not whitespace,
# so empty fields survive.
SILL_MEDIA_FS=$'\037'
SILL_MEDIA_ART="$SILL_MEDIA_STATE_DIR/cover"
SILL_MEDIA_ART_SCALE="$SILL_MEDIA_STATE_DIR/cover-scale"
SILL_MEDIA_TINT="$SILL_MEDIA_STATE_DIR/tint"

# The dropdown's cover well: the outer box a real cover sits in, and the inner
# target size the image is scaled to. The gap between the two is deliberate
# margin, so a square cover doesn't sit flush against the well's edges (and,
# by extension, the dropdown's own rounded corner). Only ever holds a real
# cover — see media.sh for why there's no app-icon stand-in here any more.
SILL_MEDIA_ART_BOX=84
SILL_MEDIA_ART_TARGET=68

# The small app-icon badge next to "Show in <App>", for when there's no cover
# to name the source instead. Deliberately its own (smaller) size rather than
# the cover well's — it is an aside, not a hero image.
SILL_MEDIA_BADGE_BOX=56

# The dropdown's title/album rows are capped to this many characters — not a
# fixed width, which sketchybar treats as static rather than a maximum, and
# would keep even a three-word title padded out to it. A short label still
# sizes to itself; only past this cap does scroll_texts sweep the rest, the
# popup's answer to the pill's own hover marquee.
SILL_MEDIA_POPUP_MAX_CHARS=30

# Every browser whose media session lands on the bar as "a tab". Kept as one list
# because the two things done with it — classify, and pick the fallback glyph —
# must agree; a browser in one and not the other draws a music note for YouTube.
media_is_browser() {
    case "$1" in
    com.apple.Safari | com.apple.SafariTechnologyPreview | com.google.Chrome | \
        com.google.Chrome.canary | org.mozilla.firefox | org.mozilla.firefoxdeveloperedition | \
        app.zen-browser.zen | company.thebrowser.Browser | company.thebrowser.dia | \
        com.brave.Browser | com.microsoft.edgemac | com.vivaldi.Vivaldi | com.operasoftware.Opera)
        return 0
        ;;
    esac
    return 1
}

# bundle title artist album duration -> a KIND, which is what everything else
# keys off. Kinds are deliberately coarse: they are what the payload can actually
# support, not what we wish it could (see the header).
media_kind() {
    local bundle="$1" album="$4"

    case "$bundle" in
    com.apple.Music | com.apple.iTunes) echo "music" ;;
    com.spotify.client) echo "spotify" ;;
    com.apple.podcasts | fm.overcast.overcast* | com.pocketcasts*) echo "podcast" ;;
    com.apple.TV | com.apple.QuickTimePlayerX) echo "video" ;;
    org.videolan.vlc) echo "vlc" ;;
    *)
        if media_is_browser "$bundle"; then
            # An album is the tell, and it is the only one that holds up: every
            # music service publishes one (Spotify Web, YouTube Music, Apple
            # Music on the web, SoundCloud) and no video site does. Video is the
            # base case rather than the exception because a browser's now-playing
            # session is far more often a video than a track.
            if [ -n "$album" ]; then echo "browser.music"; else echo "browser.video"; fi
        else
            echo "other"
        fi
        ;;
    esac
}

# kind bundle -> glyph. haus.sill.media.icons wins over both, keyed by bundle id
# first (most specific) and then by kind, so a rice can say "YouTube, actually"
# for its own browser without the rice guessing that for everyone.
media_icon() {
    local kind="$1" bundle="$2" override=""

    if [ -n "${SILL_MEDIA_ICONS:-}" ]; then
        override="$(media_icon_override "$bundle")"
        [ -z "$override" ] && override="$(media_icon_override "$kind")"
        if [ -n "$override" ]; then
            printf '%s' "$override"
            return
        fi
    fi

    case "$kind" in
    music) printf '󰝚' ;;
    spotify) printf '󰓇' ;;
    podcast) printf '󰦔' ;;
    video) printf '󰠹' ;;
    vlc) printf '󰕼' ;;
    browser.video) printf '󰕧' ;;
    browser.music) printf '󰎆' ;;
    *) printf '󰕾' ;;
    esac
}

# The override table is a newline-separated "key<TAB>glyph" list generated from
# haus.sill.media.icons into media_config.sh — a flat string rather than a bash
# associative array so it survives being sourced by /bin/sh-ish contexts and so
# an empty option costs exactly one empty variable.
media_icon_override() {
    [ -n "$1" ] || return 0
    printf '%s\n' "$SILL_MEDIA_ICONS" | awk -F'\t' -v k="$1" '$1 == k { print $2; exit }'
}

# The accent a kind earns, as a colors.sh name resolved by the caller. Brand
# colours are deliberately NOT used: the bar is one palette (nebelung), and a
# Spotify green sampled from Spotify's own brand sheet is the one pill on the
# strip that doesn't belong to the rice. These are the palette's nearest members.
media_color() {
    case "$1" in
    music) printf '%s' "$PINK" ;;
    spotify) printf '%s' "$GREEN" ;;
    podcast) printf '%s' "$MAUVE" ;;
    video) printf '%s' "$LAVENDER" ;;
    vlc) printf '%s' "$PEACH" ;;
    browser.video) printf '%s' "$RED" ;;
    browser.music) printf '%s' "$SAPPHIRE" ;;
    *) printf '%s' "$PINK" ;;
    esac
}

# The human name of the app the sound is coming from — for the dropdown's "Show
# in …" row and for its app-icon fallback, which SketchyBar resolves by app NAME
# (`background.image=app.Zen`), not by bundle id. Read off the running process
# rather than kept in a table: the pid is in the payload, every macOS app's
# executable lives under <Name>.app/Contents/MacOS/, and a table would go stale
# the first time somebody plays audio from something not in it.
media_app_name() {
    local pid="$1" bundle="$2" comm=""

    if [ -n "$pid" ] && [ "$pid" != "0" ]; then
        comm="$(ps -p "$pid" -o comm= 2>/dev/null)"
        case "$comm" in
        */*.app/Contents/MacOS/*)
            printf '%s' "$(basename "${comm%%.app/Contents/MacOS/*}")"
            return
            ;;
        esac
    fi

    # No usable pid: the last component of the bundle id is the best guess left
    # ("com.spotify.client" -> "client" is poor, so prefer the second-to-last
    # component when the last one is a generic suffix).
    case "$bundle" in
    "") printf '' ;;
    *.client | *.app) printf '%s' "$(printf '%s' "$bundle" | awk -F. '{print $(NF-1)}')" ;;
    *) printf '%s' "${bundle##*.}" ;;
    esac
}

# Seconds -> m:ss, or h:mm:ss once it earns the hour. Takes a float (the payload
# is one) and never prints a bare "0:00" for a missing duration — callers test
# for emptiness, and "0:00" would read as a real zero-length track.
media_fmt_time() {
    local secs="${1%%.*}"
    [ -n "$secs" ] || return 0
    [ "$secs" -ge 0 ] 2>/dev/null || return 0
    if [ "$secs" -ge 3600 ]; then
        printf '%d:%02d:%02d' $((secs / 3600)) $((secs % 3600 / 60)) $((secs % 60))
    else
        printf '%d:%02d' $((secs / 60)) $((secs % 60))
    fi
}

# Where playback actually is NOW. The payload's elapsedTime is a snapshot taken
# at its timestamp, so a pill that printed it back would freeze the moment the
# stream went quiet — which is most of a song. Advancing it by wall-clock (only
# while playing, and only at the reported rate) is what upstream's own docs
# recommend over polling `get` in a loop, and it costs nothing.
media_elapsed_now() {
    local elapsed="${1%%.*}" stamp="$2" playing="$3" rate="${4:-1}" now delta
    [ -n "$elapsed" ] || return 0
    if [ "$playing" != "true" ] || [ -z "$stamp" ]; then
        printf '%s' "$elapsed"
        return
    fi
    now="$(date +%s)"
    delta=$((now - stamp))
    [ "$delta" -lt 0 ] && delta=0
    # A non-1 rate is rare (podcast apps at 1.5×) and integer maths is plenty for
    # a readout whose smallest unit is a second.
    case "$rate" in
    "" | 0 | 0.*) rate=1 ;;
    esac
    printf '%s' $((elapsed + delta * ${rate%%.*}))
}

# How much is LEFT, in the coarsest unit that still says something. A 58-minute
# video counts down in minutes because that is the decision it supports ("finish
# it now, or after lunch"); only the last minute is worth a second hand.
media_fmt_remaining() {
    local secs="${1%%.*}"
    [ -n "$secs" ] || return 0
    [ "$secs" -lt 0 ] 2>/dev/null && secs=0
    if [ "$secs" -ge 3600 ]; then
        printf '%dh%02dm' $((secs / 3600)) $((secs % 3600 / 60))
    elif [ "$secs" -ge 60 ]; then
        printf '%dm' $((secs / 60))
    else
        printf '%ds' "$secs"
    fi
}

# Anything at least this long is long-form, and the pill counts it down instead
# of scrolling a title through a 25-character window for the next hour.
SILL_MEDIA_LONGFORM=1200

# The `now` record -> MEDIA_* in the caller's shell. One line, US-separated,
# written by media_stream.sh on every payload; read by the tick and by the
# dropdown so neither has to spawn media-control (a perl re-exec) just to know
# the title.
media_read_now() {
    MEDIA_PLAYING=""; MEDIA_TITLE=""; MEDIA_ARTIST=""; MEDIA_ALBUM=""
    MEDIA_BUNDLE=""; MEDIA_DURATION=""; MEDIA_ELAPSED=""; MEDIA_STAMP=""
    MEDIA_RATE=""; MEDIA_PID=""; MEDIA_ID=""
    [ -r "$SILL_MEDIA_NOW" ] || return 1
    IFS="$SILL_MEDIA_FS" read -r MEDIA_PLAYING MEDIA_TITLE MEDIA_ARTIST MEDIA_ALBUM \
        MEDIA_BUNDLE MEDIA_DURATION MEDIA_ELAPSED MEDIA_STAMP \
        MEDIA_RATE MEDIA_PID MEDIA_ID <"$SILL_MEDIA_NOW" || return 1
    [ -n "$MEDIA_TITLE" ]
}

# What counts as "a different track", from whatever media_read_now last read.
#
# NOT contentItemIdentifier on its own: plenty of sources publish none at all —
# the browsers this pill spends most of its design on among them — and an id that
# is always the empty string makes every change look like no change, so the
# cover and the marquee would both freeze after the first switch into such a
# source. Title+artist+bundle is what's left, and it is
# a fine key: two consecutive tracks agreeing on all three are the same track.
media_change_key() {
    if [ -n "$MEDIA_ID" ]; then
        printf '%s' "$MEDIA_ID"
    else
        printf '%s|%s|%s' "$MEDIA_TITLE" "$MEDIA_ARTIST" "$MEDIA_BUNDLE"
    fi
}

# Is the pointer on the pill right now? A file rather than a `--query`, because
# the answer is wanted inside a render that already has one sketchybar round trip
# to spend and mouse.entered/exited are the only two things that ever write it.
media_hovered() { [ -f "$SILL_MEDIA_STATE_DIR/hover" ]; }

# Paint the pill from whatever media_read_now last put in MEDIA_*. Lives here,
# not in the streamer, because the tick repaints too: a long-form countdown has
# to move while the stream is silent (nothing about a video CHANGES between
# minute 12 and minute 13, so no payload arrives to trigger a repaint).
media_render() {
    local kind icon color label label_color label_drawing dur elapsed remain tint

    # No session at all: gone, not an empty box — the way the pill has always
    # behaved. The dropdown goes with it, or it would be left describing a track
    # that stopped existing.
    if [ -z "$MEDIA_TITLE" ]; then
        $SB --set media drawing=off popup.drawing=off
        return
    fi

    kind="$(media_kind "$MEDIA_BUNDLE" "$MEDIA_TITLE" "$MEDIA_ARTIST" "$MEDIA_ALBUM" "$MEDIA_DURATION")"
    icon="$(media_icon "$kind" "$MEDIA_BUNDLE")"
    color="$(media_color "$kind")"

    # The artwork tint, when it's on and a track has one: a colour sampled from
    # the cover and then SNAPPED to the nearest nebelung member (see
    # media_art.sh). So the pill picks up the record's mood without ever drawing
    # a colour that isn't in the rice's palette.
    if [ "${SILL_MEDIA_ARTWORK_TINT:-0}" = "1" ] && [ -r "$SILL_MEDIA_TINT" ]; then
        tint="$(cat "$SILL_MEDIA_TINT" 2>/dev/null)"
        case "$tint" in 0x????????) color="$tint" ;; esac
    fi

    label="$MEDIA_TITLE"
    [ -n "$MEDIA_ARTIST" ] && label="$MEDIA_TITLE — $MEDIA_ARTIST"

    # Long-form gets a countdown instead of a scrolling title. An hour-long video
    # or a podcast is a thing you already know the name of; what you keep
    # glancing at the bar for is how much of it is left.
    dur="${MEDIA_DURATION%%.*}"
    if [ -n "$dur" ] && [ "$dur" -ge "$SILL_MEDIA_LONGFORM" ] 2>/dev/null; then
        elapsed="$(media_elapsed_now "$MEDIA_ELAPSED" "$MEDIA_STAMP" "$MEDIA_PLAYING" "$MEDIA_RATE")"
        remain=$((dur - ${elapsed:-0}))
        [ "$remain" -lt 0 ] && remain=0
        label="$MEDIA_TITLE  ·  -$(media_fmt_remaining "$remain")"
    fi

    # Paused stays on the bar (Control Center keeps it too — it's how you find
    # your way back to it) but dims, so "playing" is still readable at a glance
    # without spending a second glyph on it.
    label_color="$TEXT"
    if [ "$MEDIA_PLAYING" != "true" ]; then
        label_color="$OVERLAY1"
        color="$OVERLAY1"
    fi

    # Collapsed: the glyph alone until the pointer arrives. Worth having because
    # the bar's centre span is under the notch on a MacBook and every character
    # of title is rent — see haus.sill.media.collapse.
    label_drawing=on
    if [ "${SILL_MEDIA_COLLAPSE:-0}" = "1" ] && ! media_hovered; then
        label_drawing=off
    fi

    $SB --set media \
        icon="$icon" \
        icon.color="$color" \
        label="$label" \
        label.color="$label_color" \
        label.drawing="$label_drawing" \
        drawing=on
}

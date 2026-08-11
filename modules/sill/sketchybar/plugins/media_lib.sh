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
#
# None of that stops ⌘-click from reaching the right TAB, which is a different
# question and has a different answer: it matches the track's title against the
# browser's own list of open tabs rather than trying to learn a URL. See
# media_focus_source below.
#
# And on a machine running haus.zen.tabBridge the URL is, in fact, right there —
# the rice's own extension publishes it beside the title. The classification
# above deliberately does NOT use it yet: it would be a Zen-only glyph rule, so
# the pill would name the site on one browser and shrug on the others, and this
# file's whole argument is that a guess you can't make everywhere is a guess you
# shouldn't make. Worth revisiting the day the bridge covers more than Zen.

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

# The small app-icon badge for when there's no cover to name the source instead.
# It does NOT sit in the stack as a row of its own any more: a 56pt icon
# occupying a full-width menu row read as a list ENTRY — something you were meant
# to click, wedged between two things you actually click — rather than as the
# aside it is. It now floats in the dropdown's bottom-right corner instead,
# below the last transport row and pushed right by media_badge_align, which is
# what the two numbers below are for: the row's height, and the scale the icon is
# drawn at inside it. `background.image.scale` is a factor on the image's own
# PIXELS — the same relationship media_art.sh computes per cover — and SketchyBar
# hands back an app icon about 27px square, so 0.9 lands the badge at ~24pt: read
# as a mark, small enough not to read as a row.
SILL_MEDIA_BADGE_BOX=28
SILL_MEDIA_BADGE_SCALE=0.9

# How far the badge sits from the dropdown's right edge, and the widest a popup
# row is ever assumed to be when its width can't be read back (see
# media_badge_align). The floor matters more than it looks: too small and the
# badge lands mid-row instead of in the corner; too large and IT becomes the
# widest item and stretches the whole dropdown to fit.
SILL_MEDIA_BADGE_INSET=12
SILL_MEDIA_BADGE_MIN_WIDTH=180

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
        app.zen-browser.zen | io.gitlab.librewolf-community.librewolf | \
        company.thebrowser.Browser | company.thebrowser.dia | \
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

# Push the app-icon badge into the dropdown's bottom-right corner.
#
# SketchyBar has no alignment for this: a popup is a vertical stack of
# LEFT-aligned items, every item's background is only as wide as ITS OWN content
# (a full-width row background is something popups simply don't do — measured),
# and there is no right-align property. What there IS: `background.image
# .padding_left` both offsets the image rightwards AND grows the item to fit, so
# an item whose only content is the image, given a padding equal to the
# dropdown's width minus the badge, draws that badge hard against the right edge
# of a row exactly as wide as the popup already was — no wider, so it never
# stretches the dropdown.
#
# Which means we need the popup's width, and only SketchyBar knows it. The two
# rows that can be the widest are the title and its artist/album subtitle (both
# capped at SILL_MEDIA_POPUP_MAX_CHARS, so a long one settles there); everything
# below them is a short labelled row or the fixed-width slider, which is what the
# floor is for.
#
# THE CATCH, which cost a round of head-scratching: a popup item has NO
# bounding_rects until the popup has actually been drawn once. Freshly built and
# still hidden, every row queries back as an empty rect list — so measuring
# before the reveal, which is what you'd want, silently measures nothing and
# falls through to the floor. Hence the return code: the caller reveals the
# popup and calls again when this said it had nothing to go on, which is only
# ever the first open after a rebuild. Every later open measures up front and
# lands the badge before anything is on screen.
media_badge_align() {
    local widest="$SILL_MEDIA_BADGE_MIN_WIDTH" w item measured=1 pad
    for item in media.popup.title media.popup.sub; do
        w="$($SB --query "$item" 2>/dev/null |
            jq -r '[.bounding_rects[]?.size[0]] | max // empty' 2>/dev/null)"
        w="${w%%.*}"
        [ -n "$w" ] || continue
        measured=0
        [ "$w" -gt "$widest" ] 2>/dev/null && widest="$w"
    done
    pad=$((widest - SILL_MEDIA_BADGE_BOX - SILL_MEDIA_BADGE_INSET))
    [ "$pad" -lt 0 ] && pad=0
    $SB --set media.popup.appicon background.image.padding_left="$pad" 2>/dev/null
    return "$measured"
}

# Bring the source forward — and, when the source is a browser, the TAB, not just
# the app. "Something is making noise and I can't find the tab" is the whole
# reason ⌘-click exists, and landing you in the right window with the wrong tab
# in front only answered half of it.
#
# The match is on the TITLE, because that is all there is: the now-playing
# session carries no URL (see this file's header — that limitation is unchanged,
# and this is the way around it rather than a fix for it). A tab's title contains
# the track's title as a prefix on every service worth naming — "<video> -
# YouTube", "<track> • <artist> | Spotify" — so a substring test is enough, and a
# miss costs nothing but the old behaviour.
#
# Three families, three completely different mechanisms, and only two of them are
# clean:
#   * Safari and the Chromium browsers expose their tabs to AppleScript, so this
#     is a genuine lookup: find the tab, make it current, raise its window. The
#     first ⌘-click on such a source raises macOS's "SketchyBar wants to control
#     <Browser>" Automation prompt; refused, osascript fails and the fallback at
#     the bottom of media_focus_source is the old behaviour.
#   * Firefox and its forks (Zen among them) expose NOTHING. No AppleScript
#     dictionary at all, and no accessibility tree either — verified directly on
#     Zen: the tab strip is absent from the AX tree even after forcing Firefox's
#     a11y engine on with AXEnhancedUserInterface, which leaves only the window
#     title, which is only ever the FOREGROUND tab. Two routes, in order:
#       1. the rice's own extension, if haus.zen.tabBridge deployed it — an
#          exact tab id from inside the browser, which is the honest answer;
#       2. failing that, the one piece of switch-to-tab machinery Firefox does
#          ship: the address bar's `%` restriction token, which searches OPEN
#          TABS and switches to the one you pick, driven by synthetic
#          keystrokes. Typed into a fresh tab, so the worst case when nothing
#          matches is a search results page in a tab that wasn't there a second
#          ago, rather than navigating away from something you were reading.
media_focus_source() {
    local bundle="$1" title="$2" app="$3"
    [ -n "$bundle" ] || return 1

    if [ -n "$title" ]; then
        case "$bundle" in
        com.apple.Safari | com.apple.SafariTechnologyPreview)
            media_focus_tab_safari "$app" "$title" && return 0
            ;;
        # Arc and Dia are Chromium underneath but ship their OWN AppleScript
        # dictionary, without the `active tab index` this leans on — they are
        # deliberately absent, and fall through to plainly fronting the app.
        com.google.Chrome | com.google.Chrome.canary | com.brave.Browser | \
            com.microsoft.edgemac | com.vivaldi.Vivaldi | com.operasoftware.Opera)
            media_focus_tab_chromium "$bundle" "$title" && return 0
            ;;
        org.mozilla.firefox | org.mozilla.firefoxdeveloperedition | \
            app.zen-browser.zen | io.gitlab.librewolf-community.librewolf)
            media_focus_tab_bridge "$bundle" "$title" && return 0
            media_focus_tab_firefox "$bundle" "$app" "$title" && return 0
            ;;
        esac
    fi

    open -b "$bundle" 2>/dev/null
}

# Chromium's dictionary indexes tabs by position within a window, and `active tab
# index` is 1-based — hence the counter rather than `set active tab of w`, which
# it does not have. `set index of w to 1` is what raises the window; `activate`
# alone would front the app on whichever window was already topmost.
media_focus_tab_chromium() {
    osascript - "$2" >/dev/null 2>&1 <<EOF
on run argv
  set needle to item 1 of argv
  tell application id "$1"
    repeat with w in windows
      set i to 0
      repeat with t in tabs of w
        set i to i + 1
        if title of t contains needle then
          set active tab index of w to i
          set index of w to 1
          activate
          return "ok"
        end if
      end repeat
    end repeat
  end tell
  error "no match"
end run
EOF
}

# $1 is the app name, unused: Safari's dictionary is reached by its own fixed
# name, not by bundle id. Kept in the signature so all three routes are called
# the same way from media_focus_source.
media_focus_tab_safari() {
    osascript - "$2" >/dev/null 2>&1 <<'EOF'
on run argv
  set needle to item 1 of argv
  tell application "Safari"
    repeat with w in windows
      repeat with t in tabs of w
        if name of t contains needle then
          set current tab of w to t
          set index of w to 1
          activate
          return "ok"
        end if
      end repeat
    end repeat
  end tell
  error "no match"
end run
EOF
}

# The good Firefox-family route: ask the browser, through the rice's own
# extension (haus.zen.tabBridge — modules/hearth/zen-tabs). When it's there this
# is the whole job: an exact tab id, no keystrokes, no Accessibility permission,
# and it works on a tab in another window, another Zen workspace or another
# Space. When it isn't, media_focus_source falls through to the keystroke route
# below, so this file works either way and neither half knows about the other's
# failure modes.
#
# The PID file is the liveness test, and it has to be: the host dies with the
# browser and cleans up after itself, but a crashed Zen leaves tabs.json behind,
# and a browser sitting idle publishes nothing new for hours — so mtime cannot
# tell a live bridge from a dead one, and only a running process can.
#
# The command channel is APPENDED to, never truncated, because a bar click_script
# must not be able to block: see haustabs.swift's header for why this is a plain
# file rather than the FIFO or socket it looks like it wants to be.
#
# Audible wins over merely matching, because a title can match twice — the same
# video open in two tabs, a "watch later" duplicate — and the one making the
# noise is by definition the one you meant.
media_focus_tab_bridge() {
    local bundle="$1" needle="$2" state id pid
    state="$HOME/.local/state/nebelhaus/zen-tabs"
    [ -r "$state/tabs.json" ] && [ -w "$state/cmd" ] || return 1
    pid="$(cat "$state/pid" 2>/dev/null)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 1

    id="$(jq -r --arg n "$needle" '
        [.tabs[]? | select((.title // "") | contains($n))]
        | (map(select(.audible)) + .)
        | .[0].id // empty' "$state/tabs.json" 2>/dev/null)"
    case "$id" in
    "" | *[!0-9]*) return 1 ;;
    esac

    printf 'focus %s\n' "$id" >>"$state/cmd" 2>/dev/null || return 1
    # The extension raises the tab's window; this raises the APP. Both are
    # needed — a focused window belonging to a background app is still behind
    # whatever you were looking at.
    open -b "$bundle" 2>/dev/null
    return 0
}

# The fallback Firefox-family route, for a machine without the bridge. Three
# things about it are deliberate:
#
#   * The already-in-front case is checked FIRST and answered without typing
#     anything. That is the common one — you paused a video, you want it back —
#     and it would be absurd to open a tab and run a search to reach a tab that
#     is already the one you're looking at.
#   * It WAITS for the browser to actually be frontmost, rather than activating
#     and sleeping a fixed quarter-second. `keystroke` does not deliver to the
#     process you addressed it to: System Events posts to whatever has focus at
#     the instant it fires, and `tell process` only names where the events are
#     ROUTED FROM. So an activation slower than the sleep — a cold app, a window
#     on another AeroSpace workspace or Space — would have typed "% <track>" and
#     a Return into whatever you were looking at before. A terminal running an
#     agent would have submitted it as a prompt. The poll is bounded, and gives
#     up rather than typing into the wrong window.
#   * All of it needs System Events, i.e. the Accessibility permission of
#     whatever spawned this (SketchyBar, for the pill; see the palette's TCC
#     note for how that identity is inherited) — the front-window check
#     included. Denied, every osascript here fails, and media_focus_source falls
#     back to plainly activating the app, which is exactly what this gesture did
#     before: a machine that never grants it is no worse off than it was.
media_focus_tab_firefox() {
    local bundle="$1" app="$2" needle="$3" front

    front="$(osascript -e "tell application \"System Events\" to tell process \"$app\" to get name of window 1" 2>/dev/null)"
    case "$front" in
    *"$needle"*)
        open -b "$bundle" 2>/dev/null
        return 0
        ;;
    esac

    osascript - "$needle" >/dev/null 2>&1 <<EOF
on run argv
  set needle to item 1 of argv
  tell application id "$bundle" to activate
  tell application "System Events"
    set waited to 0
    repeat until (frontmost of process "$app") or waited > 20
      delay 0.1
      set waited to waited + 1
    end repeat
    if not (frontmost of process "$app") then error "never came forward"
    tell process "$app"
      keystroke "t" using command down
      delay 0.2
      keystroke ("% " & needle)
      delay 0.5
      key code 36
    end tell
  end tell
end run
EOF
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

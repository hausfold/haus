#!/bin/bash

# The vocabulary the three halves of the media pill share: what is playing, what
# KIND of thing it is, which glyph and colour that earns, and where the little
# bit of state they pass between each other lives.
#
# Sourced, never run. media.sh (the WIDGET — the pill, its gestures and its
# dropdown), media_stream.sh (the live feed) and media_art.sh (the cover) all
# classify the same track the same way — a glyph table written twice is a glyph
# table that ends up being two, which is the same reason colors.sh and sizes.sh
# are generated once.
#
# What is NOT here any more is the rendering. media.sh is a framework widget
# (hausfold.co/docs/haus/rooms/bar-widgets), so the pill's paint is its
# `render()` and barlib owns the batching, the state diff and every colour;
# `media_paint` at the bottom of this file is how the two processes that are
# not the widget ask for one. Four more things went the same way: the popup's
# row geometry and fonts are barlib's row kinds, its scrubber is
# `popup_slider`, its cover and badge are `popup_image`, and `media_color`'s
# palette keys are `media_mark`'s marks.
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
# Netflix. A desktop that knows better overrides the glyph through
# haus.bar.media.icons — that option is this limitation's escape hatch.
#
# None of that stops ⌘-click from reaching the right TAB, which is a different
# question and has a different answer: it matches the track's title against the
# browser's own list of open tabs rather than trying to learn a URL. See
# media_focus_source below.
#
# And on a machine running haus.zen.tabBridge the URL is, in fact, right there —
# haus's own extension publishes it beside the title. The classification
# above deliberately does NOT use it yet: it would be a Zen-only glyph rule, so
# the pill would name the site on one browser and shrug on the others, and this
# file's whole argument is that a guess you can't make everywhere is a guess you
# shouldn't make. Worth revisiting the day the bridge covers more than Zen.

BAR_MEDIA_STATE_DIR="$HOME/.local/state/haus/media"
BAR_MEDIA_NOW="$BAR_MEDIA_STATE_DIR/now"

# The field separator for both of those files, and it is deliberately NOT a tab.
# Tab is IFS *whitespace*, which bash collapses: a run of them is one delimiter,
# so `IFS=$'\t' read a b c` on "x<TAB><TAB>z" puts z in b and leaves c empty.
# Every one of these records has an optional field in the middle (an empty album
# is the normal case for anything that isn't music), so that collapse silently
# shifted the bundle id into the album and the duration into the bundle — the
# pill drew the wrong glyph for every browser tab. US (0x1f) is not whitespace,
# so empty fields survive.
BAR_MEDIA_FS=$'\037'
BAR_MEDIA_ART="$BAR_MEDIA_STATE_DIR/cover"
BAR_MEDIA_ART_SCALE="$BAR_MEDIA_STATE_DIR/cover-scale"
BAR_MEDIA_TINT="$BAR_MEDIA_STATE_DIR/tint"

# The dropdown's cover well: the outer box a real cover sits in, and the inner
# target size the image is scaled to. The gap between the two is deliberate
# margin, so a square cover doesn't sit flush against the well's edges (and,
# by extension, the dropdown's own rounded corner). Only ever holds a real
# cover — see media.sh for why there's no app-icon stand-in here any more.
BAR_MEDIA_ART_BOX=84
BAR_MEDIA_ART_TARGET=68

# The small app-icon badge for when there's no cover to name the source instead.
# It does NOT sit in the stack as a row of its own any more: a 56pt icon
# occupying a full-width menu row read as a list ENTRY — something you were meant
# to click, wedged between two things you actually click — rather than as the
# aside it is. It now floats in the dropdown's bottom-right corner instead,
# below the last transport row and pushed right by media_badge_pad, which is
# what the two numbers below are for: the row's height, and the scale the icon is
# drawn at inside it. `background.image.scale` is a factor on the image's own
# PIXELS — the same relationship media_art.sh computes per cover — and SketchyBar
# hands back an app icon about 27px square, so 0.9 lands the badge at ~24pt: read
# as a mark, small enough not to read as a row.
BAR_MEDIA_BADGE_BOX=28
BAR_MEDIA_BADGE_SCALE=0.9

# How far the badge sits from the dropdown's right edge, and the widest a popup
# row is ever assumed to be when its width has never been read back (see
# media_badge_pad). The floor matters more than it looks: too small and the
# badge lands mid-row instead of in the corner; too large and IT becomes the
# widest item and stretches the whole dropdown to fit.
BAR_MEDIA_BADGE_INSET=12
BAR_MEDIA_BADGE_MIN_WIDTH=180

# The dropdown's title/album rows are capped to this many characters — not a
# fixed width, which sketchybar treats as static rather than a maximum, and
# would keep even a three-word title padded out to it. A short label still
# sizes to itself; only past this cap does scroll_texts sweep the rest, the
# popup's answer to the pill's own hover marquee.
BAR_MEDIA_POPUP_MAX_CHARS=30

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

# kind bundle -> glyph. haus.bar.media.icons wins over both, keyed by bundle id
# first (most specific) and then by kind, so a desktop can say "YouTube, actually"
# for its own browser without haus guessing that for everyone.
media_icon() {
    local kind="$1" bundle="$2" override=""

    if [ -n "${BAR_MEDIA_ICONS:-}" ]; then
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
# haus.bar.media.icons into media_config.sh — a flat string rather than a bash
# associative array so it survives being sourced by /bin/sh-ish contexts and so
# an empty option costs exactly one empty variable.
media_icon_override() {
    [ -n "$1" ] || return 0
    printf '%s\n' "$BAR_MEDIA_ICONS" | awk -F'\t' -v k="$1" '$1 == k { print $2; exit }'
}

# The MARK a kind earns — barlib's identity axis (modules/bar/marks.nix), not a
# palette key and not a hex. Brand colours are deliberately not used either:
# the bar is one palette (nebelung), and a Spotify green sampled from Spotify's
# own brand sheet is the one pill on the strip that doesn't belong to haus.
#
# ⚠️ FOUR OF THESE MOVED when the pill converted, and the reason is the one
# thing marks exist to enforce: identity and status never share a hue. This
# table named `GREEN`, `PEACH`, `RED` and `SAPPHIRE` — which are the ladder's
# `ok`, `warn`, `bad` and `action` — so a Spotify pill was painted with the
# all-clear, VLC with a warning and a YouTube tab with the alarm, for as long
# as each was playing perfectly. `mauve` and `lavender` were already off the
# ladder and kept their colour exactly (`plum`, `violet`), as did `pink`.
#
# The kinds are still coarse on purpose — see this file's header for why the
# payload cannot support more — so the marks are too. A desktop that wants
# YouTube to look like YouTube overrides the GLYPH through
# haus.bar.media.icons; the hue stays haus's.
media_mark() {
    case "$1" in
    music) printf '%s' pink ;;
    spotify) printf '%s' teal ;;
    podcast) printf '%s' plum ;;
    video) printf '%s' violet ;;
    vlc) printf '%s' warm ;;
    browser.video) printf '%s' rust ;;
    browser.music) printf '%s' blue ;;
    *) printf '%s' pink ;;
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
# stretches the dropdown. `popup_image --pad-left` is that shape; this is the
# number it takes.
#
# Which means we need the popup's width, and only SketchyBar knows it. The two
# rows that can be the widest are the title and its artist/album subtitle (both
# capped at BAR_MEDIA_POPUP_MAX_CHARS, so a long one settles there); everything
# below them is a short labelled row or the fixed-width scrubber, which is what
# the floor is for.
#
# THE CATCH, which cost a round of head-scratching: a popup item has NO
# bounding_rects until the popup has actually been drawn once. Freshly built and
# still hidden, every row queries back as an empty rect list — so measuring
# before the reveal, which is what you'd want, silently measures nothing.
#
# So the answer is REMEMBERED rather than re-derived. The measurement happens
# after the popup is on screen and is written to a file; the next open reads it
# back and places the badge correctly before anything is drawn, which is the
# whole point — a badge that jumps into its corner a moment after the dropdown
# appears is worse than one that was never there. The file outlives a bar reload
# and a rebuild, so the one open that can be wrong is the first one on a machine
# that has never opened this dropdown at all, and it corrects itself on the way
# out.
BAR_MEDIA_BADGE_PAD="$BAR_MEDIA_STATE_DIR/badge-pad"

# What to place the badge at NOW, from the last measurement or from the floor.
media_badge_pad() {
    local pad
    pad="$(cat "$BAR_MEDIA_BADGE_PAD" 2>/dev/null)"
    case "$pad" in
    '' | *[!0-9]*) pad=$((BAR_MEDIA_BADGE_MIN_WIDTH - BAR_MEDIA_BADGE_BOX - BAR_MEDIA_BADGE_INSET)) ;;
    esac
    [ "$pad" -lt 0 ] && pad=0
    printf '%s' "$pad"
}

# media_badge_measure <badge-row> <candidate-row>… — read the drawn popup back,
# remember the answer, and nudge the badge if it moved. A row that queries back
# with no rects is a popup that has not been drawn yet, and the whole call is
# then a no-op: it must never overwrite a good measurement with the floor.
#
# The ids are barlib's, so they are passed in rather than known here — the
# runtime numbers its own rows, and $POPUP_ID is what a widget catches them
# with. The `--set` rides the widget's batch through popup_set; the `--query`
# does not, because a read is not traffic and there is nothing to batch it with.
#
# ⚠️ This is the ONE function in this file that needs barlib sourced, and this
# file is also sourced by media_stream.sh and media_art.sh, which do not source
# it. That is fine only because neither calls this — media.sh's `on_click` is
# the sole caller. Anything else added here that reaches for a `popup_*` breaks
# that, silently, in a process whose stderr goes nowhere.
media_badge_measure() {
    local badge="$1" widest="$BAR_MEDIA_BADGE_MIN_WIDTH" w item measured=0 pad
    shift
    [ -n "$badge" ] || return 0
    for item in "$@"; do
        [ -n "$item" ] || continue
        w="$($SB --query "$item" 2>/dev/null |
            jq -r '[.bounding_rects[]?.size[0]] | max // empty' 2>/dev/null)"
        w="${w%%.*}"
        [ -n "$w" ] || continue
        measured=1
        [ "$w" -gt "$widest" ] 2>/dev/null && widest="$w"
    done
    [ "$measured" = 1 ] || return 0
    pad=$((widest - BAR_MEDIA_BADGE_BOX - BAR_MEDIA_BADGE_INSET))
    [ "$pad" -lt 0 ] && pad=0
    printf '%s' "$pad" >"$BAR_MEDIA_BADGE_PAD"
    popup_set "$badge" background.image.padding_left="$pad"
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
#       1. haus's own extension, if haus.zen.tabBridge deployed it — an
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

# The good Firefox-family route: ask the browser, through haus's own
# extension (haus.zen.tabBridge — modules/terminal/zen-tabs). When it's there this
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
    # ZEN ONLY, and checked here rather than at the call site because the file
    # this reads holds ZEN's tabs and nothing else. Firefox and LibreWolf share
    # the Firefox-family branch above, and without this a title playing in
    # Firefox that happens to substring-match a Zen tab would switch Zen's tab
    # and then raise Firefox. The bridge is Zen-only for a signing reason (see
    # modules/terminal/zen-tabs); widen this the day that stops being true.
    [ "$bundle" = "app.zen-browser.zen" ] || return 1
    state="$HOME/.local/state/haus/zen-tabs"
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
BAR_MEDIA_LONGFORM=1200

# The `now` record -> MEDIA_* in the caller's shell. One line, US-separated,
# written by media_stream.sh on every payload; read by the tick and by the
# dropdown so neither has to spawn media-control (a perl re-exec) just to know
# the title.
media_read_now() {
    MEDIA_PLAYING=""; MEDIA_TITLE=""; MEDIA_ARTIST=""; MEDIA_ALBUM=""
    MEDIA_BUNDLE=""; MEDIA_DURATION=""; MEDIA_ELAPSED=""; MEDIA_STAMP=""
    MEDIA_RATE=""; MEDIA_PID=""; MEDIA_ID=""
    [ -r "$BAR_MEDIA_NOW" ] || return 1
    IFS="$BAR_MEDIA_FS" read -r MEDIA_PLAYING MEDIA_TITLE MEDIA_ARTIST MEDIA_ALBUM \
        MEDIA_BUNDLE MEDIA_DURATION MEDIA_ELAPSED MEDIA_STAMP \
        MEDIA_RATE MEDIA_PID MEDIA_ID <"$BAR_MEDIA_NOW" || return 1
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
media_hovered() { [ -f "$BAR_MEDIA_STATE_DIR/hover" ]; }

# Repaint the pill, by re-entering the WIDGET.
#
# The pill's own render lives in media.sh now — it is a framework widget
# (hausfold.co/docs/haus/rooms/bar-widgets), so `render()` is barlib's to call
# and the state it reads is barlib's to diff. Two things outside that widget
# still have reason to ask for a repaint, and neither can call the function:
#
#   * media_stream.sh, on every payload. That is the whole point of the stream —
#     a track change or a play/pause repaints in the instant it happens rather
#     than on a poll.
#   * media_art.sh, when a cover lands after the track did and the artwork tint
#     is on, so the pill picks up the record's colour a beat later.
#
# ⚠️ `env -u SENDER` is the rule in barlib.sh's header, and it is load-bearing
# here twice over: the streamer is spawned from a `script=` run and the art
# fetch from the streamer, so BOTH carry a $SENDER the runtime routes on. A
# child that inherited `mouse.clicked` would land in the click handler that
# started this chain. The `paint` CLI mode ending in `exit 0` is the second half
# of the same guard, exactly as github's `fetch` mode is.
#
# Not backgrounded: the stream wants its payloads painted IN ORDER, and this is
# one fork against a 200 ms debounce.
#
# It is DIFFED on the other side, which the old in-process render was not — so a
# payload that changes nothing about what the pill says now costs zero
# sketchybar traffic instead of a full repaint. media-control re-publishes on
# every seek and every rate change; most of those said nothing new.
media_paint() {
    (env -u SENDER -u BUTTON -u MODIFIER \
        "$HOME/.config/sketchybar/plugins/media.sh" paint >/dev/null 2>&1)
}

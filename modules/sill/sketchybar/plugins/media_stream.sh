#!/bin/bash

# The living half of the media pill.
#
# SketchyBar's own `media_change` event has been dead since macOS 15.4: Apple
# made mediaremoted check the CALLER's entitlement and the bar doesn't have one,
# so the event simply never fires and the pill stayed dark forever. See
# modules/sill/media-control.nix for the whole story and for why the replacement
# has to run inside /usr/bin/perl.
#
# This is that replacement: one long-running `media-control stream` whose JSON
# lines are pushed straight into `sketchybar --set`. The pill stays event-driven
# — a track change or a play/pause repaints it in the same instant it happens —
# rather than dropping to a poll, which is what the old event bought us and what
# a `get` on an update_freq would have quietly given up.
#
# It lives in its own script rather than inside media.sh because sketchybar reaps
# its `script=` runs: a stream started from one would be killed by the next tick.
# sketchybarrc launches it detached, and media.sh restarts it if it ever dies.

export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/usr/bin:/bin:$PATH"

source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/media_config.sh"

SKETCHYBAR="/opt/homebrew/bin/sketchybar"
PIDFILE="/tmp/sketchybar_media_stream.pid"

[ -n "$SILL_MEDIA_CONTROL" ] && [ -x "$SILL_MEDIA_CONTROL" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# One streamer per bar. A reload runs sketchybarrc again without killing what the
# last one spawned, so the previous stream (and the perl adapter under it) has to
# go first, or every track change repaints twice.
if [ -f "$PIDFILE" ]; then
    OLD="$(cat "$PIDFILE" 2>/dev/null)"
    if [ -n "$OLD" ] && [ "$OLD" != "$$" ] && kill -0 "$OLD" 2>/dev/null; then
        pkill -P "$OLD" 2>/dev/null
        kill "$OLD" 2>/dev/null
    fi
fi
echo $$ >"$PIDFILE"
trap 'pkill -P $$ 2>/dev/null; rm -f "$PIDFILE"' EXIT

# Which app the sound is coming from, since this is the one thing Control Center
# shows that a text pill otherwise loses. Anything unrecognised — and that is
# most things, because any app with a media session lands here — gets the plain
# note rather than a wrong guess.
source_icon() {
    case "$1" in
    com.apple.Music | com.apple.iTunes) echo "󰝚" ;;
    com.spotify.client) echo "󰓇" ;;
    com.apple.podcasts) echo "󰦔" ;;
    com.apple.TV | com.apple.QuickTimePlayerX) echo "󰠹" ;;
    org.videolan.vlc) echo "󰕼" ;;
    com.apple.Safari | com.apple.SafariTechnologyPreview | com.google.Chrome | \
        org.mozilla.firefox | app.zen-browser.zen | company.thebrowser.Browser | \
        com.brave.Browser | com.microsoft.edgemac | com.vivaldi.Vivaldi)
        echo "󰖟"
        ;;
    *) echo "" ;;
    esac
}

render() {
    local playing="$1" title="$2" artist="$3" bundle="$4"

    # No session at all: back to how the pill has always behaved when nothing is
    # playing — gone, not an empty box. media-control also emits an empty payload
    # as its first line, which is what makes a fresh bar start out hidden.
    if [ -z "$title" ]; then
        $SKETCHYBAR --set media drawing=off
        return
    fi

    local label="$title"
    [ -n "$artist" ] && label="$title — $artist"

    # Paused media stays on the bar (Control Center keeps it too — it's how you
    # find your way back to it) but dims, so "playing" is still readable at a
    # glance without spending a second glyph on it.
    local label_color="$TEXT" icon_color="$PINK"
    if [ "$playing" != "true" ]; then
        label_color="$OVERLAY1"
        icon_color="$OVERLAY1"
    fi

    $SKETCHYBAR --set media \
        icon="$(source_icon "$bundle")" \
        icon.color="$icon_color" \
        label="$label" \
        label.color="$label_color" \
        drawing=on
}

# --no-artwork keeps several hundred KB of base64 per update out of a pipe that
# only ever renders text; --no-diff means every line is a complete payload, so
# there is no state to merge here and a missed line can't leave the pill stale.
"$SILL_MEDIA_CONTROL" stream --no-diff --no-artwork --debounce=200 2>/dev/null |
    while IFS= read -r line; do
        parsed="$(printf '%s' "$line" | jq -r '
            select(.type == "data")
            | .payload
            | [(.playing // false | tostring), (.title // ""), (.artist // ""), (.bundleIdentifier // "")]
            | @tsv' 2>/dev/null)"
        [ -n "$parsed" ] || continue
        IFS=$'\t' read -r playing title artist bundle <<<"$parsed"
        render "$playing" "$title" "$artist" "$bundle"
    done

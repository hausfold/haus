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
# lines become the pill. The pill stays event-driven — a track change or a
# play/pause repaints it in the same instant it happens — rather than dropping to
# a poll, which is what the old event bought us and what a `get` on an
# update_freq would have quietly given up.
#
# It lives in its own script rather than inside media.sh because sketchybar reaps
# its `script=` runs: a stream started from one would be killed by the next tick.
# sketchybarrc launches it detached, and media.sh restarts it if it ever dies.
#
# Rendering itself is in media_lib.sh, not here, because the TICK repaints too: a
# long-form countdown has to keep moving while the stream is silent. This file's
# own job is narrower — turn each payload into the `now` record, notice when the
# TRACK (not the state) changed, and paint.

export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/usr/bin:/bin:$PATH"

source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/media_config.sh"
source "$HOME/.config/sketchybar/plugins/media_lib.sh"
SILL_ITEM=media
source "$HOME/.config/sketchybar/bar.sh"

PIDFILE="/tmp/sketchybar_media_stream.pid"

[ -n "$SILL_MEDIA_CONTROL" ] && [ -x "$SILL_MEDIA_CONTROL" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

mkdir -p "$SILL_MEDIA_STATE_DIR" 2>/dev/null

# Start from a clean slate, because the LAST stream may not have got to run its
# trap. bash does not run an EXIT trap on an untrapped SIGKILL, and a bar reload
# signals the whole process group — so an artwork fetch or a scroll-seek caught
# mid-flight leaves its lock directory behind, and a lock nothing ever releases
# is a feature switched off forever, silently, across reboots. The hover flag and
# the marquee get the same treatment: both are cleared by events that a pointer
# flicked off the bar can miss, and neither should outlive the stream that set
# them.
rmdir "$SILL_MEDIA_STATE_DIR/art.lock" "$SILL_MEDIA_STATE_DIR/scroll.lock" 2>/dev/null
rm -f "$SILL_MEDIA_STATE_DIR/hover" 2>/dev/null
$SB --set media scroll_texts=off 2>/dev/null

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

# ── the marquee, on a timer ──────────────────────────────────────────────────
# scroll_texts used to be on forever, which meant a title longer than the pill
# scrolled for as long as the track played — permanent motion in the corner of
# your eye, on a bar you are not looking at. It earns its scroll for a few
# seconds after a track CHANGES (when you actually want to read the whole name)
# and then settles into the truncated form. Hovering brings it back; that's what
# media.sh's mouse.entered does.
MARQUEE_SECONDS=8

arm_marquee() {
    local key="$1"
    $SB --set media scroll_texts=on
    (
        sleep "$MARQUEE_SECONDS"
        # Only settle if this is still the track we armed for, and the pointer
        # isn't on the pill — otherwise a fast skip would stop the NEXT title
        # mid-scroll, and a hover would be yanked out from under the reader.
        media_read_now || exit 0
        [ "$(media_change_key)" = "$key" ] || exit 0
        media_hovered && exit 0
        $SB --set media scroll_texts=off
    ) &
}

# ── the stream ───────────────────────────────────────────────────────────────
# --no-artwork keeps several hundred KB of base64 per update out of a pipe that
# only ever renders text (media_art.sh fetches the cover separately, once per
# track); --no-diff means every line is a complete payload, so there is no state
# to merge here and a missed line can't leave the pill stale.
#
# Three things the record format does on purpose:
#
#   * `timestamp` is folded to epoch seconds by jq rather than by a `date -j` per
#     payload — it is what media_elapsed_now advances a countdown from, and
#     spawning date(1) in a stream's hot path is how a track change earns a
#     visible stutter. The sub() strips a fractional part first: v0.7.6 never
#     emits one, but fromdateiso8601 rejects "...:05.123Z" outright, jq's error
#     is swallowed by the 2>/dev/null, and the pill would go dark for good on a
#     media-control bump nobody would think to connect to it.
#   * control characters in the VALUES are flattened to spaces before joining
#     rather than escaped by @tsv. @tsv also escapes backslashes, and nothing
#     downstream un-escapes them, so a track called `AC\DC` reached the bar as
#     `AC\\DC`. A title has no business carrying a newline anyway.
#   * the join is US (0x1f), not tab — see SILL_MEDIA_FS in media_lib.sh.
PREV_KEY=""
media_read_now && PREV_KEY="$(media_change_key)"

"$SILL_MEDIA_CONTROL" stream --no-diff --no-artwork --debounce=200 2>/dev/null |
    while IFS= read -r line; do
        parsed="$(printf '%s' "$line" | jq -r '
            select(.type == "data")
            | .payload
            | [ (.playing // false | tostring),
                (.title // ""),
                (.artist // ""),
                (.album // ""),
                (.bundleIdentifier // ""),
                (.duration // 0 | tostring),
                (.elapsedTime // 0 | tostring),
                (if (.timestamp // "") == "" then ""
                 else (.timestamp | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601 | tostring) end),
                (.playbackRate // 1 | tostring),
                (.processIdentifier // 0 | tostring),
                (.contentItemIdentifier // "") ]
            | map(gsub("[\u0001-\u001f]"; " "))
            | join("\u001f")' 2>/dev/null)"
        [ -n "$parsed" ] || continue

        printf '%s\n' "$parsed" >"$SILL_MEDIA_NOW"
        media_read_now
        # media_read_now returns non-zero on an empty title, which is a real
        # state (nothing is playing) and not a read failure — MEDIA_* is still
        # populated either way, and media_render hides the pill on it.

        key="$(media_change_key)"
        if [ "$key" != "$PREV_KEY" ]; then
            PREV_KEY="$key"
            if [ -n "$MEDIA_TITLE" ]; then
                # Recently played, for the dropdown. Written on the change rather
                # than sampled on open, because by the time you go looking for
                # "what was that one before this" it is gone from every API on
                # the machine — macOS keeps no now-playing history at all.
                printf '%s%s%s%s%s%s%s\n' \
                    "$(date +%s)" "$SILL_MEDIA_FS" "$MEDIA_TITLE" "$SILL_MEDIA_FS" \
                    "$MEDIA_ARTIST" "$SILL_MEDIA_FS" "$MEDIA_BUNDLE" \
                    >>"$SILL_MEDIA_HISTORY"
                tail -n "$SILL_MEDIA_HISTORY_MAX" "$SILL_MEDIA_HISTORY" \
                    >"$SILL_MEDIA_HISTORY.tmp" 2>/dev/null &&
                    mv "$SILL_MEDIA_HISTORY.tmp" "$SILL_MEDIA_HISTORY"

                ("$HOME/.config/sketchybar/plugins/media_art.sh" "$MEDIA_ID" >/dev/null 2>&1 &)
                arm_marquee "$key"
            else
                rm -f "$SILL_MEDIA_ART".* "$SILL_MEDIA_ART_SCALE" "$SILL_MEDIA_TINT" 2>/dev/null
            fi
        fi

        media_render
    done

#!/bin/bash

# Fetch the current track's cover art and work out the accent it earns.
#
# Run detached, once per TRACK change, by media_stream.sh — never in the stream's
# own loop. Two reasons it can't live there: the stream deliberately runs with
# --no-artwork (several hundred KB of base64 per update, through a pipe that
# renders text), and this makes a second media-control call, which is a perl
# re-exec costing ~200 ms. A song lasts three minutes; that is a fine price once
# and an absurd one per payload.
#
# It produces two things:
#   * the image itself, for the dropdown's thumbnail
#   * a TINT — the cover's average colour, snapped to the nearest member of the
#     nebelung palette. Snapping is the whole idea: the pill picks up the mood of
#     the record without ever drawing a colour that isn't in the rice's palette,
#     so an album cover can't smuggle a brand green onto a bar that is one theme.
#     Only read when haus.sill.media.artworkTint is on (see media_lib.sh).
#
# Plenty of sources publish no artwork at all — every Firefox-family browser, for
# one — and that is not an error: the files are simply cleared and the dropdown
# falls back to the source app's own icon.

export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/usr/bin:/bin:$PATH"

source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/media_config.sh"
source "$HOME/.config/sketchybar/plugins/media_lib.sh"
SILL_ITEM=media
source "$HOME/.config/sketchybar/bar.sh"

[ -n "$SILL_MEDIA_CONTROL" ] && [ -x "$SILL_MEDIA_CONTROL" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

TRACK_ID="${1:-}"
mkdir -p "$SILL_MEDIA_STATE_DIR" 2>/dev/null

# One fetch at a time. Skipping to the fifth track in a playlist fires five of
# these in a second, and the loser of that race would otherwise finish last and
# leave the fourth track's cover on screen.
LOCK="$SILL_MEDIA_STATE_DIR/art.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

PAYLOAD="$("$SILL_MEDIA_CONTROL" get 2>/dev/null)"
[ -n "$PAYLOAD" ] || exit 0

# The track moved on while we were in perl — whatever we fetched is already
# stale, and the change that superseded us has queued its own run.
CURRENT_ID="$(printf '%s' "$PAYLOAD" | jq -r '.contentItemIdentifier // ""' 2>/dev/null)"
if [ -n "$TRACK_ID" ] && [ -n "$CURRENT_ID" ] && [ "$TRACK_ID" != "$CURRENT_ID" ]; then
    exit 0
fi

MIME="$(printf '%s' "$PAYLOAD" | jq -r '.artworkMimeType // ""' 2>/dev/null)"
case "$MIME" in
image/png) EXT=png ;;
image/jpeg | image/jpg) EXT=jpg ;;
image/*) EXT=img ;;
*) EXT="" ;;
esac

rm -f "$SILL_MEDIA_ART".* "$SILL_MEDIA_ART_SCALE" "$SILL_MEDIA_TINT" 2>/dev/null
[ -n "$EXT" ] || exit 0

# The file name carries the track id so SketchyBar is always handed a path it has
# not drawn before — an image set from the same path twice is exactly the case
# where a cached decode would leave the previous cover up.
ART="$SILL_MEDIA_ART.${CURRENT_ID:0:8}.$EXT"
printf '%s' "$PAYLOAD" | jq -r '.artworkData // ""' 2>/dev/null | base64 -d >"$ART" 2>/dev/null
if [ ! -s "$ART" ]; then
    rm -f "$ART"
    exit 0
fi

# SketchyBar draws a background image at its natural size times `scale`, and
# covers arrive at anything from 300 to 3000 px square — so the factor that fits
# one into the dropdown's art well has to be computed per image, here, rather
# than guessed once in the popup builder. Targeting SILL_MEDIA_ART_TARGET rather
# than the well's own width (SILL_MEDIA_ART_BOX) is what leaves the cover its
# margin instead of filling the well edge to edge.
ART_W="$(sips -g pixelWidth "$ART" 2>/dev/null | awk '/pixelWidth/ { print $2 }')"
if [ -n "$ART_W" ] && [ "$ART_W" -gt 0 ] 2>/dev/null; then
    awk -v w="$ART_W" -v t="$SILL_MEDIA_ART_TARGET" 'BEGIN { printf "%.4f\n", t / w }' >"$SILL_MEDIA_ART_SCALE"
fi

# ── the tint ─────────────────────────────────────────────────────────────────
# Average colour the cheap way: sips scales the cover to a single pixel, which IS
# the average, and a 1×1 BMP is uncompressed so that pixel can be read with xxd
# and no image library at all. The pixel-data offset is read out of the header
# (bytes 10..13, little-endian) rather than assumed to be 54, because sips emits
# a V4/V5 header for some inputs and a hardcoded 54 would sample the header.
BMP="$SILL_MEDIA_STATE_DIR/avg.bmp"
if sips -s format bmp -Z 1 "$ART" --out "$BMP" >/dev/null 2>&1 && [ -s "$BMP" ]; then
    off_le="$(xxd -p -s 10 -l 4 "$BMP" 2>/dev/null)"
    if [ ${#off_le} -eq 8 ]; then
        off=$((0x${off_le:6:2}${off_le:4:2}${off_le:2:2}${off_le:0:2}))
        px="$(xxd -p -s "$off" -l 3 "$BMP" 2>/dev/null)"
        if [ ${#px} -eq 6 ]; then
            # BMP stores BGR, not RGB.
            avg_b=$((0x${px:0:2}))
            avg_g=$((0x${px:2:2}))
            avg_r=$((0x${px:4:2}))

            # Nearest palette member by squared distance in RGB. Only the accents
            # are candidates: snapping a dark cover to BASE or SURFACE0 would
            # paint the glyph the same colour as the pill behind it.
            #
            # In bash rather than awk on purpose — awk(1) on macOS is the one true
            # awk, which has no strtonum(), and fourteen comparisons is not worth
            # depending on gawk being installed to get one.
            best=""
            pick=""
            for c in "$BLUE" "$FLAMINGO" "$GREEN" "$LAVENDER" "$MAROON" "$MAUVE" \
                "$PEACH" "$PINK" "$RED" "$ROSEWATER" "$SAPPHIRE" "$SKY" \
                "$TEAL" "$YELLOW"; do
                hex="${c#0x}"
                hex="${hex:2}" # drop the alpha byte
                dr=$((0x${hex:0:2} - avg_r))
                dg=$((0x${hex:2:2} - avg_g))
                db=$((0x${hex:4:2} - avg_b))
                d=$((dr * dr + dg * dg + db * db))
                if [ -z "$best" ] || [ "$d" -lt "$best" ]; then
                    best="$d"
                    pick="$c"
                fi
            done
            [ -n "$pick" ] && printf '%s\n' "$pick" >"$SILL_MEDIA_TINT"
        fi
    fi
fi
rm -f "$BMP" 2>/dev/null

# Repaint, so a cover that arrived after the track did still colours the pill.
# Only when the tint is actually wanted — otherwise the artwork was fetched for
# the dropdown alone and nothing on the bar changed.
if [ "${SILL_MEDIA_ARTWORK_TINT:-0}" = "1" ] && media_read_now; then
    media_render
fi

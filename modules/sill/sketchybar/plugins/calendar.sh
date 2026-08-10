#!/bin/bash

# Calendar plugin using icalBuddy
ICALBUDDY="/opt/homebrew/bin/icalBuddy"
# The bar this pill lives on — either one (haus.sill.bottom.items moves it),
# so the client comes from bar.sh rather than a hardcoded Homebrew path.
source "$HOME/.config/sketchybar/bar.sh"
SKETCHYBAR="$SB"

# ── the sweep ────────────────────────────────────────────────────────────────
# The title used to be chopped to 15 characters with an ellipsis, which is the
# one thing a meeting name can least afford: "Design review w…" and "Design
# review r…" are the same pill. It now sweeps instead, on exactly the bargain
# the media pill strikes — the label scrolls for a few seconds when the NEXT
# event changes (which is when you'd actually want to read the whole thing) and
# then settles into the clipped form, so nothing moves in the corner of your eye
# forever. Hovering brings it back.
#
# How wide the clipped form is comes from `haus.sill.calendar.width`, applied as
# the item's label.max_chars at add time (modules/sill/default.nix) — SketchyBar
# owns the clip, so nothing here has to know the number.
STATE_DIR="$HOME/.local/state/nebelhaus/calendar"
HOVER="$STATE_DIR/hover"
LAST="$STATE_DIR/last-event"
SWEEP_SECONDS=8
mkdir -p "$STATE_DIR" 2>/dev/null

# Hover is answered without touching icalBuddy: the pointer crossing the bar
# fires this script, and re-reading the calendar for a mouse move would spawn a
# binary per twitch. mouse.exited.global is the belt-and-braces twin — the
# per-item exit is missed when the pointer is flicked straight off the bar, and
# a stranded hover means the sweep runs forever, which is the whole thing this
# design exists to stop.
case "${SENDER:-}" in
mouse.entered)
    : >"$HOVER"
    $SKETCHYBAR --set "$NAME" scroll_texts=on
    exit 0
    ;;
mouse.exited | mouse.exited.global)
    rm -f "$HOVER" 2>/dev/null
    $SKETCHYBAR --set "$NAME" scroll_texts=off
    exit 0
    ;;
esac

# Start sweeping, and settle once the window is up — unless the event changed
# again in the meantime (a fast reshuffle shouldn't cut the NEW title short) or
# the pointer is on the pill.
arm_sweep() {
    local key="$1"
    $SKETCHYBAR --set "$NAME" scroll_texts=on
    (
        sleep "$SWEEP_SECONDS"
        [ "$(cat "$LAST" 2>/dev/null)" = "$key" ] || exit 0
        [ -f "$HOVER" ] && exit 0
        $SKETCHYBAR --set "$NAME" scroll_texts=off
    ) &
}

# Called on every tick with the event that's showing (the empty string for "no
# events"). Arms the sweep when that changed; otherwise makes sure the sweep is
# OFF. That second half is the backstop: SketchyBar reaps a script= run's
# children, so the timer above can be killed before it settles — by the next
# tick, or by any mouse.exited.global, which this item now hears every time the
# pointer leaves the bar for any reason. A pill left permanently scrolling is
# the exact failure mode this replaced truncation to avoid, so it is worth a
# second, slower guarantee.
settle() {
    local key="$1" prev
    prev="$(cat "$LAST" 2>/dev/null)"
    printf '%s\n' "$key" >"$LAST"
    # An empty key never arms: "No events" is short enough that it could not
    # scroll anyway, and sweeping it would only be motion announcing nothing.
    if [ -n "$key" ] && [ "$key" != "$prev" ]; then
        arm_sweep "$key"
    elif [ ! -f "$HOVER" ]; then
        $SKETCHYBAR --set "$NAME" scroll_texts=off
    fi
}

# Get next timed event (exclude all-day events)
# -n: limit to next event
# -nc: no calendar names
# -nrd: no relative dates
# -ea: exclude all-day events
# -df: date format
# -tf: time format
EVENT=$($ICALBUDDY -n -nc -nrd -ea -df "%Y-%m-%d" -tf "%H:%M" -iep "title,datetime" -b "" -ps "| @ |" eventsToday+7 2>/dev/null | head -1)

if [ -z "$EVENT" ] || [ "$EVENT" = "" ]; then
    $SKETCHYBAR --set $NAME label="No events"
    settle ""
    # Clear popup items
    for i in 1 2 3 4 5; do
        $SKETCHYBAR --set calendar.event.$i label="" icon="" drawing=off 2>/dev/null
    done
    exit 0
fi

# Parse title and datetime
# Format: "Title @ 2026-01-28 at 09:00 - 09:20"
TITLE=$(echo "$EVENT" | sed 's/ @ [0-9].*//')
DATETIME=$(echo "$EVENT" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2} at [0-9]{2}:[0-9]{2}' | sed 's/ at / /')

if [ -z "$DATETIME" ]; then
    $SKETCHYBAR --set $NAME label="No events"
    settle ""
    exit 0
fi

# Calculate time until event
EVENT_EPOCH=$(date -j -f "%Y-%m-%d %H:%M" "$DATETIME" "+%s" 2>/dev/null)
NOW_EPOCH=$(date "+%s")
DIFF=$((EVENT_EPOCH - NOW_EPOCH))

if [ $DIFF -lt 0 ] || [ $DIFF -gt 86400 ]; then
    # Event is in progress, passed, or more than 24h away
    $SKETCHYBAR --set $NAME label="No events"
    settle ""
    exit 0
fi

# Calculate hours and minutes
HOURS=$((DIFF / 3600))
MINUTES=$(((DIFF % 3600) / 60))

# Format time string
if [ $HOURS -gt 0 ]; then
    if [ $MINUTES -gt 0 ]; then
        TIME_STR="${HOURS}h${MINUTES}m"
    else
        TIME_STR="${HOURS}h"
    fi
else
    TIME_STR="${MINUTES}m"
fi

# The countdown leads, and this is why: SketchyBar clips a label to
# label.max_chars from the START, so whatever is last is what a long name eats.
# The old "<title> in 12m" put the one number the pill exists for in exactly
# that spot — settled (which is ~52 seconds out of every 60) a long meeting name
# would leave "Design review with Ac…" and no time at all. Countdown first pins
# it; the title is the part that sweeps.
#
# The title goes on whole, and keying the sweep on the TITLE rather than the
# whole label is deliberate: the countdown changes every minute, and a pill that
# re-armed on that would scroll eight seconds out of every sixty, forever.
$SKETCHYBAR --set $NAME label="in $TIME_STR · $TITLE"
settle "$TITLE"

# Update popup with next 5 events
EVENTS=$($ICALBUDDY -n 5 -nc -nrd -ea -df "%Y-%m-%d" -tf "%H:%M" -iep "title,datetime" -b "" -ps "| @ |" eventsToday+7 2>/dev/null)

i=1
while IFS= read -r line && [ $i -le 5 ]; do
    if [ -n "$line" ]; then
        POPUP_TITLE=$(echo "$line" | sed 's/ @ [0-9].*//')
        POPUP_TIME=$(echo "$line" | grep -oE '[0-9]{2}:[0-9]{2}' | head -1)

        # Truncate popup title
        if [ ${#POPUP_TITLE} -gt 25 ]; then
            POPUP_TITLE="${POPUP_TITLE:0:22}..."
        fi

        $SKETCHYBAR --set calendar.event.$i icon="󰃭" label="$POPUP_TIME $POPUP_TITLE" drawing=on 2>/dev/null
        ((i++))
    fi
done <<< "$EVENTS"

# Hide unused popup items
while [ $i -le 5 ]; do
    $SKETCHYBAR --set calendar.event.$i label="" icon="" drawing=off 2>/dev/null
    ((i++))
done

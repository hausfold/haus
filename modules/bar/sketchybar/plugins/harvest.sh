#!/bin/bash

source "$HOME/.config/sketchybar/harvest_secrets.sh"

# API Configuration
HARVEST_API_URL="https://api.harvestapp.com/v2"

# Add timestamp to bust any caching
TIMESTAMP=$(date +%s)

HEADERS=(
  -H "Authorization: Bearer $HARVEST_ACCESS_TOKEN"
  -H "Harvest-Account-ID: $HARVEST_ACCOUNT_ID"
  -H "User-Agent: Sketchybar Plugin"
  -H "Content-Type: application/json"
  -H "Cache-Control: no-cache, no-store, must-revalidate"
  -H "Pragma: no-cache"
)

source "$HOME/.config/sketchybar/colors.sh"
# $SB — which bar this pill lives on. haus.bar.bottom.items can move it to
# the second (bottom) bar, and the two instances are addressed by different
# binaries; a bare `sketchybar` would always mean the menu bar one. bar.sh
# reads $BAR_NAME, which SketchyBar exports into everything it runs.
source "$HOME/.config/sketchybar/bar.sh"


# Helper to format duration
format_duration() {
  local hours=$1
  local total_mins=$(printf "%.0f" $(echo "$hours * 60" | bc))
  local h=$((total_mins / 60))
  local m=$((total_mins % 60))
  if [ $h -gt 0 ]; then
    echo "${h}h${m}m"
  else
    echo "${m}m"
  fi
}

# The haus tour hides this pill for the length of its tutorial (tour.sh mute()).
# Our own paints must honor that: at update_freq=3 a poll tick is almost always
# mid-curl when the tour fires, so an unconditional `drawing=on` below would
# race the tour's `drawing=off` — and, landing last, win — popping the pill back
# over the step labels for the rest of the tour. Evaluated right before each
# --set (never cached up top) so a mute that lands during our curls still wins.
tour_drawing() {
  local muted="$HOME/.local/state/haus/tour-muted"
  if [ -f "$muted" ] && grep -qxF harvest "$muted" 2>/dev/null; then
    echo off
  else
    echo on
  fi
}

# One bounded GET, and the only way this plugin reads Harvest. It prints the
# body only when the body is JSON we can actually read, so every caller can
# tell "Harvest says nothing is running" apart from "Harvest was unreachable".
#
# Those two used to be the same thing here, and the mix-up was visible: an
# empty body puts nothing on jq's stdout, `RUNNING_COUNT` comes out empty, and
# `[ "" -gt "0" ]` is a bash *error* that the `if` reads as false. So a poll
# with no network fell into the STOPPED arm and repainted a RUNNING timer as
# "Start Timer", every three seconds, until the network came back — the one
# lie this pill must never tell, because the fix a person reaches for is to
# click it and start a second entry against the same hours.
#
# Three guards, because there are three ways to get a body that is not an
# answer, and only the first is about the network:
#
#   -f          Harvest replies to an expired or rotated token with HTTP 401 and
#               a JSON error body. `curl -s` alone exits 0 on that, the body
#               parses, and `.time_entries | length` on it is `null | length` —
#               which is 0, not an error. Straight back into the STOPPED arm and
#               the "Start Timer" lie, with the network working perfectly.
#   jq -e has() the shape, not just the parseability. The body has to be the
#               thing this plugin reads before any caller treats it as data.
#   --max-time  a SketchyBar plugin is synchronous. Wi-Fi off fails fast on DNS
#               and was never the hazard; a captive portal or a half-up VPN
#               accepts the connection and never answers. Two seconds because
#               the poll's update_freq is three and its STOPPED path makes TWO
#               of these calls — a bound above the tick lets one poll still be
#               waiting when the next starts.
harvest_get() {
  local body
  body=$(curl -sf --max-time 2 "${HEADERS[@]}" "$1") || return 1
  printf '%s' "$body" | jq -e 'has("time_entries")' >/dev/null 2>&1 || return 1
  printf '%s' "$body"
}

# Unreachable is a third state, not a stopped timer. Dim what is ALREADY on the
# pill instead of repainting it: the label still names whatever was running, and
# the muted colours say the duration behind it has stopped moving. Only the
# colours are set, so the next successful poll restores them on its own.
harvest_unreachable() {
  # Whether there is anything worth keeping is a THREE-way question, and the
  # middle answer is the one that bites: a `--query` fired while another pill is
  # rebuilding its rows comes back EMPTY rather than with a value, because
  # sketchybar's mach service cannot answer for ~150 ms while it works (the same
  # window barpop polls through — modules/bar/barpop.swift). Reading that as
  # "nothing to keep" would draw the em dash OVER the running timer's name,
  # which is what this function exists to protect. So: a parseable answer with
  # an empty label means never painted, and no parseable answer at all means
  # keep what's there — the safe reading in both cases.
  local shown
  if shown=$("$SB" --query $NAME 2>/dev/null | jq -er '.label.value // ""' 2>/dev/null) \
     && [ -z "$shown" ]; then
    # Never painted — a bar that started with no network. An em dash is the same
    # "no answer" the github pill draws.
    "$SB" --set $NAME icon="󰔟" icon.color=$OVERLAY0 label="—" \
      label.color=$OVERLAY0 background.color=$SURFACE0 drawing=$(tour_drawing)
  else
    "$SB" --set $NAME icon.color=$OVERLAY0 label.color=$OVERLAY0 \
      background.color=$SURFACE0 drawing=$(tour_drawing)
  fi
}

# Handle click events
if [ "$SENDER" = "mouse.clicked" ]; then
  # Right-click or modifier: Open Harvest app
  if [ "$BUTTON" = "right" ] || [ "$MODIFIER" = "shift" ] || [ "$MODIFIER" = "cmd" ]; then
    open -a "Swather"
    exit 0
  fi

  # Left-click: Toggle timer
  CURRENT_ENTRY=$(harvest_get "$HARVEST_API_URL/time_entries?is_running=true&_=$TIMESTAMP") || {
    # Say which thing went wrong. Falling through here used to reach the
    # START arm with an empty entry list and report "No previous timer to
    # restart" — a true sentence about a question nobody asked.
    osascript -e 'display notification "Harvest is unreachable" with title "Harvest"'
    harvest_unreachable
    exit 0
  }
  IS_RUNNING=$(echo "$CURRENT_ENTRY" | jq -r '.time_entries | length')

  if [ "$IS_RUNNING" -gt "0" ]; then
    # STOP the running timer
    ENTRY_ID=$(echo "$CURRENT_ENTRY" | jq -r '.time_entries[0].id')
    PROJECT_NAME=$(echo "$CURRENT_ENTRY" | jq -r '.time_entries[0].client.name // .time_entries[0].project.name // "Timer"')

    # Optimistic UI update
    "$SB" --set $NAME \
      icon.color=$TEXT \
      label.color=$TEXT \
      background.color=$SURFACE0 \
      label="$PROJECT_NAME"

    # Stop the timer
    HTTP_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" -X PATCH "${HEADERS[@]}" "$HARVEST_API_URL/time_entries/$ENTRY_ID/stop")

    if [ "$HTTP_CODE" -ne 200 ]; then
      osascript -e 'display notification "Failed to stop timer" with title "Harvest"'
      "$SB" --trigger harvest_update
    fi

  else
    # START/RESTART the most recently used timer (sort by updated_at desc, skip running)
    LAST_ENTRIES=$(harvest_get "$HARVEST_API_URL/time_entries?per_page=10&_=$TIMESTAMP") || {
      osascript -e 'display notification "Harvest is unreachable" with title "Harvest"'
      harvest_unreachable
      exit 0
    }
    ENTRY_ID=$(echo "$LAST_ENTRIES" | jq -r '[.time_entries[] | select(.is_running == false)] | sort_by(.updated_at) | reverse | .[0].id')
    PROJECT_NAME=$(echo "$LAST_ENTRIES" | jq -r '[.time_entries[] | select(.is_running == false)] | sort_by(.updated_at) | reverse | .[0] | .client.name // .project.name // "Timer"')

    if [ "$ENTRY_ID" != "null" ] && [ -n "$ENTRY_ID" ]; then
      # Optimistic UI update
      "$SB" --set $NAME \
        icon.color=$BASE \
        label.color=$BASE \
        background.color=$PEACH \
        label="$PROJECT_NAME"

      # Restart the timer
      HTTP_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" -X PATCH "${HEADERS[@]}" "$HARVEST_API_URL/time_entries/$ENTRY_ID/restart")

      if [ "$HTTP_CODE" -ne 200 ] && [ "$HTTP_CODE" -ne 201 ]; then
        osascript -e 'display notification "Failed to restart timer" with title "Harvest"'
        "$SB" --trigger harvest_update
      fi
    else
      osascript -e 'display notification "No previous timer to restart" with title "Harvest"'
    fi
  fi

  exit 0
fi

# Regular update: Always fetch fresh data from server
RUNNING_ENTRY=$(harvest_get "$HARVEST_API_URL/time_entries?is_running=true&_=$TIMESTAMP") || {
  harvest_unreachable
  exit 0
}
RUNNING_COUNT=$(echo "$RUNNING_ENTRY" | jq -r '.time_entries | length // 0')

if [ "$RUNNING_COUNT" -gt "0" ]; then
  # Timer is RUNNING
  CLIENT=$(echo "$RUNNING_ENTRY" | jq -r '.time_entries[0].client.name // empty')
  PROJECT=$(echo "$RUNNING_ENTRY" | jq -r '.time_entries[0].project.name // empty')
  TASK=$(echo "$RUNNING_ENTRY" | jq -r '.time_entries[0].task.name // empty')
  NOTES=$(echo "$RUNNING_ENTRY" | jq -r '.time_entries[0].notes // empty')
  HOURS=$(echo "$RUNNING_ENTRY" | jq -r '.time_entries[0].hours // 0')

  # Build label: prefer client name, fall back to project, add duration
  if [ -n "$CLIENT" ] && [ "$CLIENT" != "null" ]; then
    LABEL="$CLIENT"
  elif [ -n "$PROJECT" ] && [ "$PROJECT" != "null" ]; then
    LABEL="$PROJECT"
  else
    LABEL="Running"
  fi

  # Add duration if available
  if [ -n "$HOURS" ] && [ "$HOURS" != "null" ] && [ "$HOURS" != "0" ]; then
    DURATION=$(format_duration "$HOURS")
    LABEL="$LABEL · $DURATION"
  fi

  "$SB" --set $NAME \
    icon="󰔟" \
    icon.color=$BASE \
    label.color=$BASE \
    background.color=$PEACH \
    label="$LABEL" \
    drawing=$(tour_drawing)
else
  # Timer is STOPPED - show most recently used entry for quick resume
  LATEST_ENTRIES=$(harvest_get "$HARVEST_API_URL/time_entries?per_page=10&_=$TIMESTAMP") || {
    harvest_unreachable
    exit 0
  }
  LATEST_ENTRY=$(echo "$LATEST_ENTRIES" | jq '[.time_entries[] | select(.is_running == false)] | sort_by(.updated_at) | reverse | .[0]')
  CLIENT=$(echo "$LATEST_ENTRY" | jq -r '.client.name // empty')
  PROJECT=$(echo "$LATEST_ENTRY" | jq -r '.project.name // empty')

  if [ -n "$CLIENT" ] && [ "$CLIENT" != "null" ]; then
    LABEL="$CLIENT"
  elif [ -n "$PROJECT" ] && [ "$PROJECT" != "null" ]; then
    LABEL="$PROJECT"
  else
    LABEL="Start Timer"
  fi

  "$SB" --set $NAME \
    icon="󰔟" \
    icon.color=$TEXT \
    label.color=$TEXT \
    background.color=$SURFACE0 \
    label="$LABEL" \
    drawing=$(tour_drawing)
fi

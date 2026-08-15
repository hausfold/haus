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
# $SB — which bar this pill lives on. haus.sill.bottom.items can move it to
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

# Handle click events
if [ "$SENDER" = "mouse.clicked" ]; then
  # Right-click or modifier: Open Harvest app
  if [ "$BUTTON" = "right" ] || [ "$MODIFIER" = "shift" ] || [ "$MODIFIER" = "cmd" ]; then
    open -a "Swather"
    exit 0
  fi

  # Left-click: Toggle timer
  CURRENT_ENTRY=$(curl -s "${HEADERS[@]}" "$HARVEST_API_URL/time_entries?is_running=true&_=$TIMESTAMP")
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
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH "${HEADERS[@]}" "$HARVEST_API_URL/time_entries/$ENTRY_ID/stop")

    if [ "$HTTP_CODE" -ne 200 ]; then
      osascript -e 'display notification "Failed to stop timer" with title "Harvest"'
      "$SB" --trigger harvest_update
    fi

  else
    # START/RESTART the most recently used timer (sort by updated_at desc, skip running)
    LAST_ENTRIES=$(curl -s "${HEADERS[@]}" "$HARVEST_API_URL/time_entries?per_page=10&_=$TIMESTAMP")
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
      HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH "${HEADERS[@]}" "$HARVEST_API_URL/time_entries/$ENTRY_ID/restart")

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
RUNNING_ENTRY=$(curl -s "${HEADERS[@]}" "$HARVEST_API_URL/time_entries?is_running=true&_=$TIMESTAMP")
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
  LATEST_ENTRIES=$(curl -s "${HEADERS[@]}" "$HARVEST_API_URL/time_entries?per_page=10&_=$TIMESTAMP")
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

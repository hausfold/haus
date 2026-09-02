#!/bin/bash
# harvest.sh — the Harvest time-tracking pill. Left-click toggles the timer
# (stop the running one, else restart the most recent), right/⇧/⌘-click opens
# the app, and the pill draws dim when Harvest can't be reached — an API it
# can't ask is not the same thing as a timer that isn't running, and the two
# used to look identical here (see harvest_get for the whole story).
#
# A barlib widget (hausfold.co/docs/haus/rooms/bar-widgets): the header below
# is the pill's wiring, and the runtime owns the $SB routing, the diffed
# repaint and the click dispatch this file used to case out by hand.
# widget: interval   = 3
# widget: subscribes = harvest_update
export USER="${USER:-$(id -un)}"
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"

source "$HOME/.config/sketchybar/harvest_secrets.sh"
BAR_ITEM=harvest
source "$HOME/.config/sketchybar/barlib.sh"

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

# The label the last successful poll painted, so the unreachable state can
# keep naming what was running instead of blanking a pill you were reading.
# A FILE rather than the `--query` the pre-framework pill did: a query fired
# while another pill rebuilds its rows comes back EMPTY for ~150 ms (the same
# window barpop polls through), and the three-way dance that guarded against
# reading that as "nothing to keep" is exactly the kind of race a cache on
# disk never has. Absent — a bar that has never reached Harvest — the pill
# draws the same "no answer" em dash the github pill uses.
STATE_DIR="$HOME/.local/state/haus/harvest"
LABEL_CACHE="$STATE_DIR/label"
mkdir -p "$STATE_DIR" 2>/dev/null

# Everything this pill puts on screen goes through `haus-notify`: trill draws
# it when its daemon answers, macOS's own banner when it doesn't, and
# `~/.config/trill/rules.json` routes or silences it by the `--source` below
# — which matters more here than anywhere else in the bar, because a Harvest
# outage means one of these per click for as long as it lasts.
#
# Addressed absolutely: SketchyBar runs its plugins under launchd, whose PATH
# names nothing of ours. `/run/current-system/sw/bin` is
# `environment.systemPackages`, stable across rebuilds.
#
# `|| true` because most callers are arms that report a failure — a notifier
# that could itself fail the script would swallow the message it carries.
#
#   notify <body> [kind] [sf-symbol]
#
# The kind is a parameter rather than a constant because one of these is not a
# failure: "no previous timer to restart" is an answer, and trill colours a
# fault differently from a note.
notify() {
  /run/current-system/sw/bin/haus-notify --source haus.bar.harvest \
    --kind "${2:-fault}" --symbol "${3:-exclamationmark.triangle}" \
    --title Harvest --body "$1" >/dev/null 2>&1 || true
}

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

# The haus tour hides this pill for the length of its tutorial (tour.sh
# mute()). Our own paints must honor that: at a 3 s tick a poll is almost
# always mid-curl when the tour fires, so an unconditional `drawing=on` would
# race the tour's `drawing=off` — and, landing last, win — popping the pill
# back over the step labels for the rest of the tour. It is EMITTED STATE
# rather than something render reads for itself, because the runtime skips
# render when nothing changed: the mute has to be a change the diff can see,
# or it only takes effect the next time Harvest's numbers happen to move.
# Read right before each emit, never cached at the top of fetch — the curls
# above an emit are seconds long, and a value read before them re-opens the
# exact race this function exists to close.
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
#               the poll's tick is three and its STOPPED path makes TWO of
#               these calls — a bound above the tick lets one poll still be
#               waiting when the next starts.
harvest_get() {
  local body
  body=$(curl -sf --max-time 2 "${HEADERS[@]}" "$1") || return 1
  printf '%s' "$body" | jq -e 'has("time_entries")' >/dev/null 2>&1 || return 1
  printf '%s' "$body"
}

# Remember what the pill says, for the unreachable state to keep saying it.
# tmp + mv so a reader never sees a half-written line.
save_label() {
  printf '%s' "$1" >"$LABEL_CACHE.tmp" 2>/dev/null &&
    mv -f "$LABEL_CACHE.tmp" "$LABEL_CACHE" 2>/dev/null
}

last_label() {
  local l
  l=$(cat "$LABEL_CACHE" 2>/dev/null)
  printf '%s' "${l:-—}"
}

fetch() {
  local entry count label=''
  entry=$(harvest_get "$HARVEST_API_URL/time_entries?is_running=true&_=$TIMESTAMP") || {
    emit state=unreachable label="$(last_label)" drawing="$(tour_drawing)"
    return 0
  }
  count=$(echo "$entry" | jq -r '.time_entries | length // 0')

  if [ "$count" -gt "0" ]; then
    # Timer is RUNNING
    local client project hours
    client=$(echo "$entry" | jq -r '.time_entries[0].client.name // empty')
    project=$(echo "$entry" | jq -r '.time_entries[0].project.name // empty')
    hours=$(echo "$entry" | jq -r '.time_entries[0].hours // 0')

    # Build label: prefer client name, fall back to project, add duration
    if [ -n "$client" ] && [ "$client" != "null" ]; then
      label="$client"
    elif [ -n "$project" ] && [ "$project" != "null" ]; then
      label="$project"
    else
      label="Running"
    fi
    if [ -n "$hours" ] && [ "$hours" != "null" ] && [ "$hours" != "0" ]; then
      label="$label · $(format_duration "$hours")"
    fi
    save_label "$label"
    emit state=running label="$label" drawing="$(tour_drawing)"
    return 0
  fi

  # Timer is STOPPED - show most recently used entry for quick resume
  local latest
  latest=$(harvest_get "$HARVEST_API_URL/time_entries?per_page=10&_=$TIMESTAMP") || {
    emit state=unreachable label="$(last_label)" drawing="$(tour_drawing)"
    return 0
  }
  latest=$(echo "$latest" | jq '[.time_entries[] | select(.is_running == false)] | sort_by(.updated_at) | reverse | .[0]')
  local client project
  client=$(echo "$latest" | jq -r '.client.name // empty')
  project=$(echo "$latest" | jq -r '.project.name // empty')
  if [ -n "$client" ] && [ "$client" != "null" ]; then
    label="$client"
  elif [ -n "$project" ] && [ "$project" != "null" ]; then
    label="$project"
  else
    label="Start Timer"
  fi
  save_label "$label"
  emit state=stopped label="$label" drawing="$(tour_drawing)"
}

# Running is a FILLED pill ($PEACH behind $BASE type) and unreachable dims
# what the label already names — palette keys through sb_set rather than
# tones, because a filled pill is a shape the ladder cannot say (every tone is
# a foreground), and the dim pair has to hit both halves of a pill whose glyph
# is static Nix identity. Same escape media.sh uses for its artwork tint.
#
# drawing rides every paint WITH updates=on, because a hide is a PAIR: both
# bars default to updates=when_shown, which SketchyBar applies to event
# DELIVERY, so a bare drawing=off is a one-way door the tour would shut on
# this pill for good.
render() {
  case "$state" in
    running)
      pill --label "$label"
      sb_set icon.color="$BASE" label.color="$BASE" background.color="$PEACH"
      ;;
    unreachable)
      pill --label "$label"
      sb_set icon.color="$OVERLAY0" label.color="$OVERLAY0" background.color="$SURFACE0"
      ;;
    *)
      pill --label "$label"
      sb_set icon.color="$TEXT" label.color="$TEXT" background.color="$SURFACE0"
      ;;
  esac
  sb_set drawing="$drawing" updates=on
}

# The unreachable paint for the CLICK path. Through a FORCED tick rather than
# a hand `sb_set` dim, because the hand paint would sit outside the runtime's
# diff: with a stopped timer the emitted state is byte-identical tick after
# tick, so a one-off dim nothing emitted would survive every subsequent
# successful poll — the cache says nothing changed, render never runs, and the
# pill stays grey until Harvest's actual state moves. The forced tick fetches
# (fails, most likely), renders the unreachable state through the same path
# the poll uses, and CACHES it, so the next good poll is a diff that repaints.
click_unreachable() {
  notify "Harvest is unreachable"
  (SENDER=forced barlib_tick)
}

# Left-click: toggle the timer. The paints here are OPTIMISTIC — flushed
# before the PATCH so the pill answers the click at once rather than after a
# curl that may take ten seconds — and a failed PATCH repaints the truth with
# `SENDER=forced barlib_tick`: forced bypasses the runtime's diff, which would
# otherwise see "same state as the cache" and leave the optimistic lie up.
on_click() {
  local entry running
  entry=$(harvest_get "$HARVEST_API_URL/time_entries?is_running=true&_=$TIMESTAMP") || {
    # Say which thing went wrong. Falling through here used to reach the
    # START arm with an empty entry list and report "No previous timer to
    # restart" — a true sentence about a question nobody asked.
    click_unreachable
    return 0
  }
  running=$(echo "$entry" | jq -r '.time_entries | length')

  if [ "$running" -gt "0" ]; then
    # STOP the running timer
    local entry_id project http_code
    entry_id=$(echo "$entry" | jq -r '.time_entries[0].id')
    project=$(echo "$entry" | jq -r '.time_entries[0].client.name // .time_entries[0].project.name // "Timer"')

    sb_set icon.color="$TEXT" label.color="$TEXT" background.color="$SURFACE0" \
      label="$project"
    barlib_flush

    http_code=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" -X PATCH "${HEADERS[@]}" "$HARVEST_API_URL/time_entries/$entry_id/stop")
    if [ "$http_code" -ne 200 ]; then
      notify "Failed to stop timer"
      (SENDER=forced barlib_tick)
    fi
    return 0
  fi

  # START/RESTART the most recently used timer (sort by updated_at desc, skip running)
  local latest entry_id project http_code
  latest=$(harvest_get "$HARVEST_API_URL/time_entries?per_page=10&_=$TIMESTAMP") || {
    click_unreachable
    return 0
  }
  entry_id=$(echo "$latest" | jq -r '[.time_entries[] | select(.is_running == false)] | sort_by(.updated_at) | reverse | .[0].id')
  project=$(echo "$latest" | jq -r '[.time_entries[] | select(.is_running == false)] | sort_by(.updated_at) | reverse | .[0] | .client.name // .project.name // "Timer"')

  if [ "$entry_id" != "null" ] && [ -n "$entry_id" ]; then
    sb_set icon.color="$BASE" label.color="$BASE" background.color="$PEACH" \
      label="$project"
    barlib_flush

    http_code=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" -X PATCH "${HEADERS[@]}" "$HARVEST_API_URL/time_entries/$entry_id/restart")
    if [ "$http_code" -ne 200 ] && [ "$http_code" -ne 201 ]; then
      notify "Failed to restart timer"
      (SENDER=forced barlib_tick)
    fi
  else
    notify "No previous timer to restart" note clock.badge.questionmark
  fi
}

# Right-click or a ⇧/⌘ chord: open the Harvest app instead of touching the
# timer. Three handlers, one body — the runtime's dispatch replaced the
# BUTTON/MODIFIER case this file used to carry.
open_app() { open -a "Swather"; }
on_right_click() { open_app; }
on_shift_click() { open_app; }
on_cmd_click() { open_app; }

barlib_main

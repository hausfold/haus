#!/bin/bash
# The Elgato Key Light pill: click toggles the light, colour reflects its state.
#
# The light's address is NOT baked in. haus.sill.elgato.host pins it when
# you want it pinned (a static lease, several lights, flaky mDNS); left empty —
# the default — the pill discovers the light over mDNS (_elg._tcp) and caches
# what it found in ~/.local/state/haus/elgato-host. A rice can't ship one
# person's device hostname, and a light that DHCPs a new address shouldn't need
# a rebuild to come back.
#
# THREE states, not two: unreachable draws dim (OVERLAY0), never as "off". A
# light that lost wifi or ran its battery flat used to render identically to a
# light someone switched off, so the pill just went quietly dead — clicks did
# nothing and nothing said why.

source "$HOME/.config/sketchybar/colors.sh"
# $SB — which bar this pill lives on. haus.sill.bottom.items can move it to
# the second (bottom) bar, and the two instances are addressed by different
# binaries; a bare `sketchybar` would always mean the menu bar one. bar.sh
# reads $BAR_NAME, which SketchyBar exports into everything it runs.
source "$HOME/.config/sketchybar/bar.sh"


# GENERATED from haus.sill.elgato.* — absent on an older generation, hence
# the guard rather than a bare source.
ELGATO_CONFIG="$HOME/.config/sketchybar/elgato_config.sh"
[ -f "$ELGATO_CONFIG" ] && source "$ELGATO_CONFIG"

STATE_DIR="$HOME/.local/state/haus"
CACHE="$STATE_DIR/elgato-host"
STAMP="$STATE_DIR/elgato-discover"
DISCOVER_TTL=60 # seconds between mDNS sweeps while the light is missing

mkdir -p "$STATE_DIR"

# One mDNS sweep, written to the cache as host:port. dns-sd has no timeout flag,
# so it runs in the background and gets killed; -Z (zone-file output) carries the
# SRV target host AND port, so one pass does what a -B/-L/-G chain needs three
# for. The awk walks fields because the SRV line ends in a "; Replace with…"
# comment — the target host is not the last field.
discover() {
  local tmp pid port host
  tmp="$(mktemp)"
  dns-sd -Z _elg._tcp local >"$tmp" 2>/dev/null &
  pid=$!
  sleep 2
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  read -r port host <<<"$(awk '{ for (i = 1; i + 4 <= NF; i++) if ($i == "SRV") { print $(i + 3), $(i + 4); exit } }' "$tmp")"
  rm -f "$tmp"
  [ -n "$host" ] || return 1
  echo "${host%.}:${port:-9123}" >"$CACHE"
}

# Where to talk to the light: the pinned host wins, else whatever we last found.
target() {
  local host="$SILL_ELGATO_HOST"
  if [ -n "$host" ]; then
    case "$host" in
    *:*) echo "$host" ;;
    *) echo "$host:9123" ;;
    esac
    return 0
  fi
  [ -s "$CACHE" ] || return 1
  cat "$CACHE"
}

# Throttle: the pill ticks every 5s and a sweep costs 2s, so only re-sweep once
# a minute — a missing light must never turn the bar into a stall.
sweep_due() {
  local last now
  last="$(cat "$STAMP" 2>/dev/null)"
  now="$(date +%s)"
  [ $((now - ${last:-0})) -ge "$DISCOVER_TTL" ]
}

fetch() { curl -s -m 2 "http://$1/elgato/lights"; }

ADDR="$(target)"
DATA=""
[ -n "$ADDR" ] && DATA="$(fetch "$ADDR")"

# Nothing there? The light may just have moved — re-sweep and try the new
# address. Pointless when the host is pinned by config, so skip it then.
if [ -z "$DATA" ] && [ -z "$SILL_ELGATO_HOST" ] && sweep_due; then
  date +%s >"$STAMP"
  if discover; then
    ADDR="$(target)"
    DATA="$(fetch "$ADDR")"
  fi
fi

if [ -n "$DATA" ] && [ "$SENDER" = "mouse.clicked" ]; then
  if [ "$(echo "$DATA" | jq -r '.lights[0].on')" = "1" ]; then NEW_STATE=0; else NEW_STATE=1; fi
  curl -s -m 2 -X PUT -d "{\"lights\":[{\"on\":$NEW_STATE}]}" "http://$ADDR/elgato/lights" >/dev/null
  # Wait a tiny bit for the light to update internally
  sleep 0.1
  DATA="$(fetch "$ADDR")"
fi

STATE="$(echo "$DATA" | jq -r '.lights[0].on' 2>/dev/null)"

case "$STATE" in
1)
  "$SB" --set "$NAME" \
    icon="" \
    icon.color=$BASE \
    background.color=$YELLOW \
    label.drawing=off
  ;;
0)
  "$SB" --set "$NAME" \
    icon="" \
    icon.color=$TEXT \
    background.color=$SURFACE0 \
    label.drawing=off
  ;;
*)
  # Unreachable: off the network, out of battery, or never discovered.
  "$SB" --set "$NAME" \
    icon="" \
    icon.color=$OVERLAY0 \
    background.color=$SURFACE0 \
    label.drawing=off
  ;;
esac

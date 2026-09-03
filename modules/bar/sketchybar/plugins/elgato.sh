#!/bin/bash
# elgato.sh — the Elgato Key Light pill (hausfold.co/docs/haus/rooms/
# bar-widgets): click toggles the light, colour reflects its state.
#
# The light's address is NOT baked in. haus.bar.elgato.host pins it when
# you want it pinned (a static lease, several lights, flaky mDNS); left empty —
# the default — the pill discovers the light over mDNS (_elg._tcp) and caches
# what it found in ~/.local/state/haus/elgato-host. A desktop can't ship one
# person's device hostname, and a light that DHCPs a new address shouldn't need
# a rebuild to come back.
#
# THREE states, not two: unreachable draws dim (mute), never as "off". A
# light that lost wifi or ran its battery flat used to render identically to a
# light someone switched off, so the pill just went quietly dead — clicks did
# nothing and nothing said why.
# widget: interval = 5

BAR_ITEM=elgato
source "$HOME/.config/sketchybar/barlib.sh"

# GENERATED from haus.bar.elgato.* — absent on an older generation, hence
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
    local host="${BAR_ELGATO_HOST:-}"
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

# Throttle: the tick runs every 5s and a sweep costs 2s, so only re-sweep once
# a minute — a missing light must never turn the bar into a stall.
sweep_due() {
    local last now
    last="$(cat "$STAMP" 2>/dev/null)"
    now="$(date +%s)"
    [ $((now - ${last:-0})) -ge "$DISCOVER_TTL" ]
}

fetch_light() { curl -s -m 2 "http://$1/elgato/lights"; }

fetch() {
    local addr data
    addr="$(target)"
    data=""
    [ -n "$addr" ] && data="$(fetch_light "$addr")"
    # Nothing there? The light may just have moved — re-sweep and try the new
    # address. Pointless when the host is pinned by config, so skip it then.
    if [ -z "$data" ] && [ -z "${BAR_ELGATO_HOST:-}" ] && sweep_due; then
        date +%s >"$STAMP"
        if discover; then
            addr="$(target)"
            data="$(fetch_light "$addr")"
        fi
    fi
    emit state="$(echo "$data" | jq -r '.lights[0].on' 2>/dev/null)"
}

render() {
    case "$state" in
        1)
            pill --icon "" --label "" --tone watch
            ;;
        0)
            pill --icon "" --label "" --tone text
            ;;
        *)
            # Unreachable: off the network, out of battery, or never discovered.
            pill --icon "" --label "" --tone mute
            ;;
    esac
}

on_click() {
    local addr data new
    addr="$(target)"
    [ -n "$addr" ] || return 0
    data="$(fetch_light "$addr")"
    if [ "$(echo "$data" | jq -r '.lights[0].on' 2>/dev/null)" = "1" ]; then new=0; else new=1; fi
    curl -s -m 2 -X PUT -d "{\"lights\":[{\"on\":$new}]}" "http://$addr/elgato/lights" >/dev/null
    # A tiny wait for the light to update internally, then repaint now rather
    # than waiting out the interval.
    sleep 0.1
    barlib_tick
}

barlib_main "$@"

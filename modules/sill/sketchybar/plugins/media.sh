#!/bin/bash

# The media pill's click target and its watchdog. Rendering is not done here —
# plugins/media_stream.sh owns that, because the pill is fed by a long-running
# `media-control stream` rather than by SketchyBar's `media_change` event, which
# Apple killed in macOS 15.4 (see modules/sill/media-control.nix).

export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/usr/bin:/bin:$PATH"

source "$HOME/.config/sketchybar/media_config.sh"

PIDFILE="/tmp/sketchybar_media_stream.pid"

[ -n "$SILL_MEDIA_CONTROL" ] && [ -x "$SILL_MEDIA_CONTROL" ] || exit 0

# Click: play/pause whatever the system considers current — the same target
# Control Center and the media keys act on, so it works for a browser tab you
# can no longer find as readily as for Music. No repaint here: the stream sees
# the state change and repaints on its own.
if [ "$1" = "toggle" ]; then
    exec "$SILL_MEDIA_CONTROL" toggle-play-pause
fi

# Otherwise this is the periodic tick, and its only job is to notice a stream
# that died (the adapter is a private-framework trick; assuming it runs forever
# would mean a pill that goes dark until the next login). Restarting it repaints
# from the current state, so there is nothing else to do on the happy path.
#
# The pid is matched against the process's own command line, not just kill -0:
# a streamer killed without running its trap leaves the pidfile behind, and PIDs
# get reused, so a live-looking pid is not on its own evidence the stream is up.
PID="$(cat "$PIDFILE" 2>/dev/null)"
if [ -n "$PID" ] && ps -p "$PID" -o command= 2>/dev/null | grep -q media_stream.sh; then
    exit 0
fi

("$HOME/.config/sketchybar/plugins/media_stream.sh" >/dev/null 2>&1 &)

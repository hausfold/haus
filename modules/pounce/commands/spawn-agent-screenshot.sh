#!/bin/bash
# pounce: name = Spawn Agent with Screenshot
# pounce: description = Capture an area, then start your default coding agent on a named worktree
# pounce: icon = camera.viewfinder
# pounce: submenu = true
#
# A separate entry is deliberate.  Putting an "Attach screenshot" row in Spawn
# Agent's free-text prompt picker makes a task that merely CONTAINS the word
# "screenshot" select that row on Return.  Here the palette first gets out of
# the way, macOS's own interactive capture UI does its one job, then the normal
# Spawn Agent flow receives the durable PNG as an ordinary command argument.

set -u

shots="$HOME/.cache/nebelhaus-agent-screenshots"
mkdir -p "$shots"
image="$shots/screenshot-$(date +%Y%m%d-%H%M%S).png"

# Cancel is a no-op. `screencapture -i` is the native crosshair/area UI, with no
# second capture implementation to keep in sync with macOS.
/usr/sbin/screencapture -i "$image" || { rm -f "$image"; exit 0; }
[ -s "$image" ] || { rm -f "$image"; exit 0; }

NEBELHAUS_AGENT_IMAGE="$image" exec "$(dirname "$0")/spawn-agent.sh"

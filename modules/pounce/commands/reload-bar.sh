#!/bin/bash
# pounce: name = Reload SketchyBar
# pounce: description = Reload bar configuration
# pounce: icon = arrow.clockwise
# pounce: cheat = bar
# Reload SketchyBar configuration.
#
# A launchd GUI agent's PATH is bare (/usr/bin:/bin:/usr/sbin:/sbin) and the
# pounce daemon hands its own environment straight to the command it spawns —
# so a bare `sketchybar` is `command not found` here even though it resolves in
# every interactive shell (it's a Homebrew binary). Resolve the tools
# explicitly, the same set add-app.sh bakes in, and only claim success if the
# reload actually happened — a notification that lies is worse than no command.
export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

notify() {
  osascript -e 'on run argv' \
    -e 'display notification (item 1 of argv) with title (item 2 of argv)' \
    -e 'end run' -- "$1" "$2" >/dev/null 2>&1
}

# Both bars, when there are two. haus.sill.bottom.enable runs a SECOND
# SketchyBar instance along the bottom of the screen — the same binary under the
# name `sill-bottom`, with its own mach service — and nothing restarts a bar on
# rebuild, so this command IS how a changed pill takes effect. Reloading only the
# top one leaves the bottom bar on the previous generation with nothing saying
# half the reload didn't happen. The second binary exists only on a machine that
# turned that bar on.
SILL_BOTTOM=/run/current-system/sw/bin/sill-bottom

if ! err="$(sketchybar --reload 2>&1)"; then
  notify "${err:-sketchybar --reload failed}" "SketchyBar reload failed"
elif [ -x "$SILL_BOTTOM" ] && ! err="$("$SILL_BOTTOM" --reload 2>&1)"; then
  notify "${err:-sill-bottom --reload failed}" "SketchyBar reload failed"
else
  notify "SketchyBar reloaded" "SketchyBar"
fi

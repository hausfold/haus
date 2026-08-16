#!/bin/bash
# pounce: name = Reload AeroSpace
# pounce: description = Reload AeroSpace configuration
# pounce: icon = rectangle.3.group
# pounce: cheat = aerospace
# Reload AeroSpace configuration.
#
# Same bare-PATH trap as reload-bar.sh: the pounce daemon is a launchd GUI agent
# (PATH = /usr/bin:/bin:/usr/sbin:/sbin) and passes its environment to the
# command it spawns, so Homebrew's `aerospace` isn't on PATH here. Resolve it
# explicitly and report the real outcome.
export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

notify() {
  osascript -e 'on run argv' \
    -e 'display notification (item 1 of argv) with title (item 2 of argv)' \
    -e 'end run' -- "$1" "$2" >/dev/null 2>&1
}

if err="$(aerospace reload-config 2>&1)"; then
  notify "AeroSpace config reloaded" "AeroSpace"
else
  notify "${err:-aerospace reload-config failed}" "AeroSpace reload failed"
fi

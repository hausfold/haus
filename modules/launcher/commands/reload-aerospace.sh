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

# Everything this desktop puts on screen goes through `haus-notify`: trill
# draws it when its daemon answers, macOS's own banner when it doesn't, and
# `~/.config/trill/rules.json` is where you route or silence it — matching on
# the `--source` below. It exits 0 whatever happens, so a missed banner can
# never be why this script failed.
#
# By name, not by path: the PATH exported just above starts with
# `/run/current-system/sw/bin`, which is where it lands.
notify() {
  haus-notify --source haus.windows --title "$2" --body "$1" >/dev/null 2>&1
}

if err="$(aerospace reload-config 2>&1)"; then
  notify "AeroSpace config reloaded" "AeroSpace"
else
  notify "${err:-aerospace reload-config failed}" "AeroSpace reload failed"
fi

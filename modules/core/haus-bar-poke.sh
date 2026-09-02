#!/usr/bin/env bash
# haus-bar-poke <event> [key=value…] — fire a SketchyBar custom event at BOTH
# bar instances.
#
# "Anything that pokes a bar pokes both" (AGENTS.md), as a binary rather than as
# a rule four producers each re-implemented. `haus.bar.bottom.enable` draws a
# second bar along the bottom, and SketchyBar has no two-bars-in-one-process
# mode: an instance is named `basename(argv[0])` and keys BOTH its lock file and
# its mach service on that name, so the bottom bar is the same binary under a
# second name with a mach service of its own. A `--trigger` therefore reaches
# exactly ONE instance, and a producer that writes only the top one leaves a
# pill that moved down silently un-repainted — same syntax, no error.
#
# A CLI and not a shell function, for the reason `haus-notify` is one: half the
# producers are not shell files that could source anything. `agentAwakePoke`
# (modules/ai) is a `writeShellScript` and the focus watcher (modules/focus) is
# a launchd `ProgramArguments`, neither of which can meaningfully source a
# `$HOME` path; and `bar_emit`, the framework's own spelling of this pair, lives
# in `barlib.sh`, which only a framework WIDGET sources. One binary on
# `environment.systemPackages` is the one address all four can spell — the same
# reason `haus-activate` sits at a stable /run/current-system path.
#
# It is the WRONG call for two of the three producer shapes ops/todo/bar-framework.md
# names, and those are decisions rather than conversions nobody got to:
#   - **Waking a watcher on the top bar alone** — `aerospace-notify.sh`'s
#     `fullscreen` and `tiling` arms, and `plugins/launch_mode.sh`. The trigger
#     only wakes `aerospace_watcher.sh`; the watcher reads the new state and
#     paints every pill on both bars itself, so poking the bottom instance here
#     is a spawn for nothing.
#   - **Repainting one pill on the instance drawing it** — `github_update`
#     (`plugins/github.sh`) and `harvest_update` (`plugins/harvest.sh`) go to
#     `$SB` alone, so a pill on the bottom bar is not woken by an event sent to
#     the menu bar's mach service.
#
# Never fails. A bar that isn't running, isn't installed, or never registered
# the event is a no-op, and every caller is a side effect on something else's
# success path — a repaint that didn't happen must not be why a focus toggle or
# an `awake 1h` reports failure.
set -euo pipefail

# @sketchybar@ is `haus.roster.sketchybar.binPath`, substituted by
# modules/core/default.nix: where the ROSTER put the bar's binary, rather than a
# profile path this script guesses at. Empty on a machine with no bar entry at
# all, which the `[ -n ]` below handles along with the `[ -x ]`.
BAR_TOP="${HAUS_BAR_POKE_TOP_BIN:-@sketchybar@}"
# The second instance: the same binary under a second name, in the system
# profile. Absent on a machine that never turned the bottom bar on.
BAR_BOTTOM="${HAUS_BAR_POKE_BOTTOM_BIN:-/run/current-system/sw/bin/bar-bottom}"

if [ "$#" -eq 0 ]; then
    printf 'haus-bar-poke: usage: haus-bar-poke <event> [key=value…]\n' >&2
    exit 64
fi

event=$1
shift

# Both instances, unconditionally: a `--trigger` for an event a bar never
# registered is already a harmless no-op, so poking both beats teaching each
# producer which bar drew the pill it cares about — the pill can move between
# them at any rebuild (`haus.bar.bottom.items`) and no producer would learn.
for bar in "$BAR_TOP" "$BAR_BOTTOM"; do
    [ -n "$bar" ] && [ -x "$bar" ] || continue
    "$bar" --trigger "$event" "$@" >/dev/null 2>&1 || true
done
exit 0

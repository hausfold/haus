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
# every interactive shell. Resolve the tools explicitly, the same set
# add-app.sh bakes in, and only claim success if the reload actually happened —
# a notification that lies is worse than no command.
#
# BOTH nix profiles are on the line below and both earn their place: the bar
# comes from nixpkgs now rather than Homebrew, and `haus.roster.sketchybar.scope`
# chooses which profile it lands in — either is a working bar (measured
# 2026-08-24), so a PATH carrying only one of them would break the other.
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
  haus-notify --source haus.bar --title "$2" --body "$1" >/dev/null 2>&1
}

# Both bars, when there are two. haus.bar.bottom.enable runs a SECOND
# SketchyBar instance along the bottom of the screen — the same binary under the
# name `bar-bottom`, with its own mach service. A rebuild that changes the bar's
# config now reloads both for you (the .haus-stamp onChange in
# modules/bar/default.nix), so this command is the manual fallback rather than
# the only way a changed pill takes effect — for a bar that went stale on its
# own, or to drop live `--set` state a script left behind. It still has to cover
# both: reloading only the top one leaves the bottom bar on the previous
# generation with nothing saying half the reload didn't happen. The second binary
# exists only on a machine that turned that bar on.
#
# EACH RELOAD NAMES ITS RC, and the ~/.config path is the load-bearing part. A
# bare `--reload` does not mean "re-read your config file", it means "re-run the
# path you resolved at STARTUP" — and SketchyBar resolves that path once,
# through the symlink, to a file in /nix/store. So an instance launched with
# `--config` re-runs the rc from the generation it BOOTED on, forever, reporting
# success every time. That is `bar-bottom`, and only `bar-bottom`: the menu bar
# is launched with no --config at all, so it lands on the live ~/.config path by
# accident, and is spelled out here only so both halves read the same. The full
# story, and the day the bottom bar's shadow lift spent on disk unapplied because
# of it, is in the reload comment in modules/bar/default.nix.
BAR_BOTTOM=/run/current-system/sw/bin/bar-bottom
SKETCHYBARRC="$HOME/.config/sketchybar/sketchybarrc"
BAR_BOTTOMRC="$HOME/.config/sketchybar/bar-bottomrc"

# Exit status is NOT the test, because naming the rc gave this command a way to
# fail quietly that the bare form didn't have: `sketchybar --reload /nope` prints
# `[?] Reload: Invalid config path` and exits 0. Any output at all is the
# failure — a reload that worked says nothing back to the client (the bar logs
# `configuration loaded..` to its own stdout, not down the socket).
reload() {
  local what="$1" bin="$2" rc="$3" err
  err="$("$bin" --reload "$rc" 2>&1)" || err="${err:-$what --reload failed}"
  [ -z "$err" ] || { notify "$err" "SketchyBar reload failed"; return 1; }
}

# A missing $BAR_BOTTOM is a pass, not a failure — it's the shape of a one-bar
# machine. `reload` has already notified on the way out of whichever half broke.
if reload sketchybar sketchybar "$SKETCHYBARRC" &&
  { [ ! -x "$BAR_BOTTOM" ] || reload bar-bottom "$BAR_BOTTOM" "$BAR_BOTTOMRC"; }; then
  notify "SketchyBar reloaded" "SketchyBar"
fi

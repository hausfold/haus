#!/bin/bash
# lane-spawn.sh — "start an agent here", bound OUTSIDE the multiplexer.
#
# This is the other half of the lane chord ⌘↵. lane-open.sh
# answers holt's open/resume seam (what a lane looks like once it exists); this
# answers the chord (which repo a new lane is FOR).
#
# ── why this is not a zellij bind ────────────────────────────────────────────
# ⌘A used to be `bind "Super a" { Run … }` in config.kdl, and zellij's only way
# to run a command IS to open a pane for it. Under the zellij backend that pane
# was the lane, so it cost nothing. Under zmx the lane is a window, and `holt
# new` returns in well under a second — so the pane appeared, flashed, and
# close_on_exit tore it down again. That flash isn't a bug in the pane, it is
# the pane being the wrong mechanism.
#
# It also couldn't reach half the machine. ⌘A arrives at zellij only because
# ghostty/config unbinds cmd+a and lets it fall through to the terminal app; a
# zmx lane window has no zellij in it, so the chord did nothing there — you
# could start an agent from a zellij pane and from nowhere else. Ghostty can't
# take over either: `ghostty +list-actions` on 1.3.1 has 85 actions and not one
# of them runs a command.
#
# ── who holds the chord, and why it changed ──────────────────────────────────
# It was AeroSpace's ⌃⌘A: the one layer that sees every window, so the chord
# worked over a browser too. On 2026-08-18 it became ⌘↵ — the guessable key for
# "go" — and that is exactly the key it cannot hold globally, because ⌘↵ means
# *send* in Slack, Claude, Linear and half the Mac. So it moved to pounce's
# app-scoped tap (modules/launcher, appHotkeys → `cmd:lane-here` → this file),
# consumed only while Ghostty is frontmost and passed through untouched
# everywhere else. That still covers every window the chord is really pressed
# from — a zellij pane and a lane's own window are both Ghostty — and the price,
# paid knowingly, is that a lane can no longer be started from a browser.
# Spawn Agent is the answer there: it asks which repo rather than inheriting the
# focused window's, which is why it is the palette row that survives off the
# terminal pages — New Agent Lane's row is scoped to them (see
# modules/launcher's `items."cmd:lane-here".workspaces`, written only where the
# windows room gives ghostty a page to be on) precisely because everything below
# this line has nothing to work with from a browser.
#
# ── the cost of living outside the multiplexer: no cwd ───────────────────────
# A zellij bind inherited the focused pane's directory for free. A chord bound
# above it has to ask; lane-cwd.sh (extracted so ⌘N's shell-here shares it)
# reads the focused window's title and asks zmx or zellij, whichever is behind
# it. Anything else — Finder, a plain shell — has no repo to speak of and falls
# back, because a lane in $HOME beats a refusal.
#
# It is asked with --page, so the PAGE you are standing on gets the last word
# about WHICH REPO: `T/<repo>` is a statement of intent, and a window whose
# directory belongs to some other repo (or to none) does not get to overrule
# it. The window still decides the exact directory inside that repo.
set -u

# Run from the pounce daemon (and formerly AeroSpace's exec-and-forget), neither
# of which carries a user PATH. Same prelude as lane-open.sh, for the same
# reason.
export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

# ── saying no out loud ───────────────────────────────────────────────────────
# This runs under the pounce daemon: no terminal, no stdout anyone
# will ever see. So `holt new` refusing ("not inside a git repo") is invisible,
# and a global chord that silently does nothing is worse than one that isn't
# bound — you press it again, harder, and conclude the rebuild didn't land.
# Everything below that gives up says so on screen first.
# Everything this desktop puts on screen goes through `haus-notify`: trill
# draws it when its daemon answers, macOS's own banner when it doesn't, and
# `~/.config/trill/rules.json` is where you route or silence it — matching on
# the `--source` below. It exits 0 whatever happens, so a missed banner can
# never be why this script failed.#
# Addressed absolutely because this runs under launchd (the pounce daemon /
# a bar plugin), whose PATH names nothing of ours. That path is
# `environment.systemPackages` — stable across rebuilds, the same reason
# `haus-activate` is reachable there.
#
# `--kind fault` because every caller of this is a refusal — that is what the
# header above is about — and trill colours a fault differently from a note.
say() { /run/current-system/sw/bin/haus-notify --source haus.lane --kind fault --symbol exclamationmark.triangle \
    --title "haus · agent lane" --body "$1" >/dev/null 2>&1; }

# Where a chord pressed over a browser puts you. It only helps if it happens to
# be a repo; when it isn't, `refuse` is what the user actually gets.
fallback="${HAUS_LANE_FALLBACK:-$HOME}"

command -v holt >/dev/null 2>&1 || {
  say "holt isn't on PATH — nothing to spawn a lane with."
  exit 0
}

# --page: the PAGE outranks the window. Standing on `T/<repo>` says which repo
# this lane is for more reliably than the window under the keystroke does — see
# lane-cwd.sh's own header. Without a page under you it changes nothing.
cwd="$("$(dirname "$0")/lane-cwd.sh" --page)"
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$fallback"

cd "$cwd" || {
  say "couldn't enter $cwd."
  exit 0
}

# `holt new` needs a repo, and refuses without one — to a terminal that isn't
# there. Ask the same question here, where the answer can still be shown. The
# check is git's own rather than a .git test, so a worktree, a submodule and a
# plain checkout all pass exactly as holt would judge them.
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  say "$(basename "$cwd") isn't a git repo — focus a window in one, then press ⌘↵."
  exit 0
fi

# `--open`, not bare `holt new`. holt 0.2.94 (its #42, 2026-08-17) split the two
# halves that used to share one spelling: bare `holt new` now CREATES the lane
# and prints its path — `cd "$(holt new)"` — and only `--open` still ends by
# opening a session in it. This line kept the old spelling, so from that release
# on ⌘↵ (and the palette's New Agent Lane behind it) made the worktree, printed
# the path to a daemon with no stdout, and exited 0: no window, no client, no
# error — the chord looked dead while `holt` quietly filled up with lanes.
#
# The agent is holt's own default (`agent = …` in ~/.config/holt/config.toml,
# generated from haus.ai.default), so no --agent here: the chord starts whatever
# the machine's default client is, which is what that option promises.
exec holt new --open

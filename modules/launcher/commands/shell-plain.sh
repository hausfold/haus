#!/bin/bash
# pounce: name = New Terminal Window
# pounce: description = Plain shell in your home directory, off any repo's page
# pounce: icon = macwindow
# pounce: cheat = new terminal

# ⌘T — the NEUTRAL terminal, and the escape hatch from page ownership.
#
# ⌘N (shell-here.sh) and ⌘↵ (lane-spawn.sh) both belong to a repo now: pressed
# on a lane page they open in that page's repo, on that page, beside the lanes
# already there. That is right nearly always and wrong exactly when you want a
# terminal that is about NOTHING — a scratch shell, an ssh, a `haus doctor`.
# There was no way to ask for one from a page: every chord that spawned a window
# inherited the page's repo or the focused window's directory, and even a window
# that did land on bare T went there without taking you with it (terminal's
# launch.sh moves it home un-followed, by design, so ⌘N can never move the
# screen under you).
#
# So this chord does the two things the others deliberately don't: it opens a
# shell in $HOME with nothing handed down, and it takes you WITH the window to
# the base workspace instead of sending it there behind your back.
#
# ── why ⌘T ───────────────────────────────────────────────────────────────────
# It is the chord every Mac terminal spells "new terminal", and this desktop had
# it free: modules/terminal/ghostty/config unbinds cmd+t because a window IS a
# pane here (windows/AeroSpace tiles them) and a Ghostty tab would nest a second
# layout model inside one tile. The letter is also the workspace this lands on,
# which is a coincidence worth keeping.
#
# ── why this script never touches AeroSpace ──────────────────────────────────
# The obvious shape — switch workspace, then spawn — is wrong twice. It moves
# the screen BEFORE it knows the spawn can even work, so a denied Automation
# grant teleports you off your page and then fails; and it hands focus to
# whatever the base workspace had, which the tile poll every other spawn script
# runs cannot then tell apart from the window being born.
#
# The window places ITSELF instead, from inside, where terminal's launch.sh
# knows with certainty which window it is — the same rule shell-here.sh's own
# "no move-node here" note states. Two variables carry the whole request:
# HAUS_TERM_WORKSPACE names where, and HAUS_TERM_FOLLOW says take the user with
# it, which is the half ⌘N deliberately does not ask for (a plain shell sent
# home to T must never drag you off the page you are reading).
set -u

# A palette command runs under the pounce daemon's launchd environment, whose
# PATH is bare. Same prelude as the other commands here.
export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

# ── where "off the page" is ──────────────────────────────────────────────────
# The BASE of the workspace you are on, not a hardcoded T: a page is
# `<base>/<repo>` (lanes/lane-open.sh), so stripping the page suffix is
# literally "the same place, minus the repo". On a workspace that is not a page
# that leaves it unchanged, which is the honest answer — a neutral terminal
# asked for on the browser workspace belongs there, not teleported to T.
#
# With no tiler at all there is no workspace to name; the window still opens,
# macOS still places it, and launch.sh's self-tile skips itself the same way.
base=""
if command -v aerospace >/dev/null 2>&1; then
  ws="$(aerospace list-workspaces --focused 2>/dev/null)"
  base="${ws%%/*}"
fi

# The ghostty-config DEFAULT command — terminal's scripts/launch.sh — not a bare
# login shell, for the reason shell-here.sh spells out: launch.sh claims a
# `term.<n>` zmx session and stamps the `window=` label every other chord joins
# on. A neutral window is still a real window; ⌘F, ⌘L and the bar's rows have to
# work in it. It is also what reads the two variables below.
shell="$HOME/.config/haus/term/launch.sh"

# ── hand over ────────────────────────────────────────────────────────────────
# terminal's scripts/new-window.sh does the spawning, and did before this file
# had a copy of the AppleScript: it owns the cold start, the quoting, the
# `open -na` fallback for a caller with no Automation grant — and the refusal
# that keeps this window out of a LANE's Ghostty process, whose instance-wide
# forced `--title` would name a fresh home-directory shell after whatever agent
# was in the window you pressed ⌘T in.
#
# --no-tile, which is this chord alone among the three: the window places ITSELF
# from inside (the note above), and the poll would un-float it on the page it
# was born on a beat before launch.sh walks it to the base workspace — a tile
# for that beat reflows the page you are standing on, which is precisely the
# page this chord exists to leave undisturbed.
args=(--cwd "$HOME" --no-tile)
if [ -n "$base" ]; then
  args+=(--env "HAUS_TERM_WORKSPACE=$base" --env "HAUS_TERM_FOLLOW=1")
fi

# The one spawn this room has, and the one thing this chord cannot do without.
# `exec` into a missing file is a silent death under the pounce daemon, which
# swallows stderr — the failure the deleted `say()` existed to prevent, so the
# check comes back rather than the helper. Absolute path for haus-notify because
# launchd's PATH names nothing of ours.
nw="$HOME/.config/haus/term/new-window.sh"
if [ ! -x "$nw" ]; then
  /run/current-system/sw/bin/haus-notify --source haus.terminal --kind fault \
    --symbol exclamationmark.triangle --title "haus · new terminal" \
    --body "new-window.sh is missing — is this generation half-applied?" >/dev/null 2>&1
  exit 0
fi

exec "$nw" "${args[@]}" -- "$shell"

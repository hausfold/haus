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

# Failing silently is the one sin a global chord can't afford — the classic
# cause here is the Automation (Apple Events) grant: the pounce daemon needs
# System Settings → Privacy & Security → Automation → Pounce → Ghostty, and a
# denied grant makes osascript error while the chord looks simply dead.
# Everything this desktop puts on screen goes through `haus-notify`: trill
# draws it when its daemon answers, macOS's own banner when it doesn't, and
# `~/.config/trill/rules.json` is where you route or silence it — matching on
# the `--source` below. It exits 0 whatever happens, so a missed banner can
# never be why this script failed.
#
# By name, not by path: the PATH exported just above names
# `/run/current-system/sw/bin`, which is where it lands.
say() { haus-notify --source haus.terminal --kind fault --symbol exclamationmark.triangle \
    --title "haus · new terminal" --body "$1" >/dev/null 2>&1; }

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

# AppleScript string literals escape backslash and double-quote and nothing
# else — the same hand-rolled quoting as terminal's new-window.sh, for the same
# reason: the workspace name comes from somewhere else.
osa_str() {
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//\"/\\\"}"
  printf '"%s"' "$v"
}

env_list=""
if [ -n "$base" ]; then
  env_list=", environment variables:{$(osa_str "HAUS_TERM_WORKSPACE=$base"), $(osa_str "HAUS_TERM_FOLLOW=1")}"
fi

if ! osascript -e "tell application \"Ghostty\" to new window with configuration {initial working directory:$(osa_str "$HOME"), command:$(osa_str "$shell")$env_list}" >/dev/null 2>&1; then
  say "couldn't ask Ghostty for a window — grant Pounce → Ghostty under Privacy & Security → Automation."
  exit 0
fi

exit 0

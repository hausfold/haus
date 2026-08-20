#!/bin/bash
# pounce: name = New Shell Window
# pounce: description = Shell window in the focused window's directory, on its page
# pounce: icon = terminal

# The heir of zellij's Super n. Pounce's Ghostty-scoped ⌘N fires
# `cmd:shell-here` and the spawned thing is a window rather than a pane —
# everything else about the chord survives (with the agent clients off this
# script isn't installed at all, same as focus.sh, and ⌘N is simply dead —
# Ghostty's config unbinds it rather than falling back to its own new_window,
# which knows nothing about "here"):
#
#   · the cwd is the focused window's, asked of zmx by lane-cwd.sh (the same
#     resolver ⌘↵'s lane-spawn.sh uses)
#   · the "no place for a human shell" hop OUT of an agent worktree still
#     happens, because it lives in terminal's zshrc — the fresh login shell
#     fires it wherever it's born
#   · --stay (⌘⇧N, via shell-here-stay.sh) still suppresses that hop, now as
#     HAUS_STAY=1 in the WINDOW's environment. This is why the spawn is
#     AppleScript (`surface configuration` carries `environment variables`)
#     rather than Ghostty's native new_window, which can't set env at all.
#   · and "here" is a PLACE as well as a directory: pressed in a window
#     standing on a lane page (T/<repo>), the chord hands that page down as
#     HAUS_TERM_WORKSPACE so the new window tiles beside the lane it was asked
#     for. Without it, terminal's launch.sh — which is this window's command,
#     and tiles itself from inside — sent every shell window to the shared T,
#     so ⌘N on a page answered two pages away.
#
# AppleScript rather than `open -na` also for its own sake: 252 ms vs 366 ms
# into the running instance, and no second Ghostty process per window. The
# forced --title that keeps lane-open.sh on `open -na` doesn't apply here — a
# plain shell window carries no name anything joins on.
set -u

export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

stay=""
[ "${1:-}" = "--stay" ] && stay=1

# Failing silently is the one sin a global chord can't afford — the classic
# cause here is the Automation (Apple Events) grant: the pounce daemon needs
# System Settings → Privacy & Security → Automation → Pounce → Ghostty, and a
# denied grant makes osascript error while the chord looks simply dead.
say() { osascript -e "display notification \"$1\" with title \"haus · shell here\"" >/dev/null 2>&1; }

# The resolver is installed by the terminal room's agents block; without it
# (which the laneCommands filter should have made unreachable) fall back to $HOME rather than
# dying on a missing file.
cwd=""
[ -x "$HOME/.config/haus/lanes/lane-cwd.sh" ] && cwd="$("$HOME/.config/haus/lanes/lane-cwd.sh")"
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$HOME"

# The ghostty-config DEFAULT command — terminal's scripts/launch.sh — not a bare
# login shell, and this is the difference between a ⌘N window being a real
# terminal window and being a lesser one. launch.sh claims a `term.<n>` zmx
# session and stamps the `window=` label on it, which is what every other chord
# joins on: without a session, ⌘F has nothing to search in this window, ⌘L has
# no scrollback to mine, ⌘N pressed FROM here can't tell where "here" is, and
# the bar can't take you back to it. Under zellij a ⌘N pane was in the session
# by construction; this is what keeps that true.
#
# The one thing it costs: launch.sh execs the session's own login shell, so
# $SHELL is honoured there rather than here.
shell="$HOME/.config/haus/term/launch.sh"

# The window AeroSpace sees before this one, so the tile poll below can tell
# the new window from the one the chord was pressed in (both are Ghostty). Its
# WORKSPACE comes out of the same line, because the two questions have one
# honest moment: the chord was just pressed, so the focused window is the one
# it was pressed in, and the workspace under it is the one the user is looking
# at.
focused="$(aerospace list-windows --focused --format '%{window-id}|%{workspace}' 2>/dev/null)"
before="${focused%%|*}"

# Only a PAGE is handed down — a workspace with a "/" in it, the same test
# windows/scripts/workspace-mru.sh uses. Bare T needs no passing on (it is what
# launch.sh does anyway), and any OTHER workspace a terminal window has been
# dragged to is not a place shell windows should accrete: "plain terminal
# windows live on T" survives, "…unless you are on a lane's page" is the new
# half. launch.sh checks the name against the live workspace list before it
# moves anything, so a page that evaporated between here and there is harmless.
page=""
case "$focused" in
  *\|*/*) page="${focused#*|}" ;;
esac

# One osascript for both chords, where there were two near-identical heredocs
# — the difference between them is now a VALUE. The list is built rather than
# written out because a variable number of entries has no `on run argv` shape,
# and because an entry is only worth SENDING when it has a value: nothing here
# passes `HAUS_STAY=` with an empty right-hand side to find out how Ghostty
# feels about it, on the one code path where being wrong costs the chord.
#
# AppleScript string literals escape backslash and double-quote and nothing
# else — the same hand-rolled quoting as terminal's new-window.sh, for the same
# reason: every value below comes from somewhere else (a cwd off a click, a
# workspace name out of AeroSpace).
osa_str() {
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//\"/\\\"}"
  printf '"%s"' "$v"
}

env_list=""
add_env() {
  [ -n "$env_list" ] && env_list="$env_list, "
  env_list="$env_list$(osa_str "$1")"
}
[ -n "$stay" ] && add_env "HAUS_STAY=1"
[ -n "$page" ] && add_env "HAUS_TERM_WORKSPACE=$page"
[ -n "$env_list" ] && env_list=", environment variables:{$env_list}"

osascript -e "tell application \"Ghostty\" to new window with configuration {initial working directory:$(osa_str "$cwd"), command:$(osa_str "$shell")$env_list}" >/dev/null 2>&1
if [ $? -ne 0 ]; then
  say "couldn't ask Ghostty for a window — grant Pounce → Ghostty under Privacy & Security → Automation."
  exit 0
fi

# windows floats every runtime-spawned ghostty window (the on-window-detected
# title race — see aerospace.toml), so tile this one by hand once it has focus.
# From outside the window, so the join is a before/after on focus: wait for it
# to land on a DIFFERENT window id than the one the chord started in. (The
# self-tiles that run from INSIDE their window — terminal's launch.sh and
# lanes/lane-open.sh — cannot use focus that way and no longer try; they walk
# up to their own Ghostty process instead. This one has a real "before", which
# is the guard that makes a focus poll honest.)
# No move-node here — the window places ITSELF, from inside, where launch.sh
# knows with certainty which window it is (T, or the page passed above). This
# side only un-floats it.
# (Until the next resort, that is: resort-windows.sh's catch-all sends plain
# Ghostty windows home to T, and a shell window carries no title to say
# otherwise. Accepted — a resort is an explicit "re-sort everything".)
for _ in $(seq 1 20); do
  wid="$(aerospace list-windows --focused --format '%{window-id}' 2>/dev/null)"
  [ -n "$wid" ] && [ "$wid" != "$before" ] && break
  sleep 0.05
done
[ -n "${wid:-}" ] && [ "$wid" != "$before" ] &&
  aerospace layout --window-id "$wid" tiling >/dev/null 2>&1

exit 0

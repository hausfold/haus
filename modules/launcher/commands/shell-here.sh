#!/bin/bash
# pounce: name = New Shell Window
# pounce: description = Shell window in the focused window's directory
# pounce: icon = terminal

# The zmx-backend heir of Super p. Under the zellij backend ⌘P is a zellij
# NewPane and this script isn't installed (modules/launcher strips it, same as
# focus.sh); under haus.terminal.lanes.backend = "zmx" pounce's Ghostty-scoped
# ⌘P fires `cmd:shell-here` and the spawned thing changes from pane to window —
# everything else about the chord survives:
#
#   · the cwd is the focused window's, asked of zmx or zellij by lane-cwd.sh
#     (the same resolver ⌃⌘A's lane-spawn.sh uses)
#   · the "no place for a human shell" hop OUT of an agent worktree still
#     happens, because it lives in terminal's zshrc, not in zellij — the fresh
#     login shell fires it wherever it's born
#   · --stay (⌘⇧P, via shell-here-stay.sh) still suppresses that hop, now as
#     HAUS_STAY=1 in the WINDOW's environment. This is why the spawn is
#     AppleScript (`surface configuration` carries `environment variables`)
#     rather than Ghostty's native new_window, which can't set env at all.
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
# (exotic: zmx backend with the AI room off) fall back to $HOME rather than
# dying on a missing file.
cwd=""
[ -x "$HOME/.config/haus/lanes/lane-cwd.sh" ] && cwd="$("$HOME/.config/haus/lanes/lane-cwd.sh")"
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$HOME"

# An explicit login shell, NOT the ghostty-config default command: that default
# is zellij/launch.sh, which would attach this window to the `main` zellij
# session — the exact thing a window-per-shell flow is walking away from.
shell="${SHELL:-/bin/zsh}"

# The window AeroSpace sees before this one, so the tile poll below can tell
# the new window from the one the chord was pressed in (both are Ghostty).
before="$(aerospace list-windows --focused --format '%{window-id}' 2>/dev/null)"

if [ -n "$stay" ]; then
  osascript - "$cwd" "$shell" <<'OSA' >/dev/null 2>&1
on run argv
    tell application "Ghostty"
        new window with configuration {initial working directory:item 1 of argv, command:(item 2 of argv) & " --login", environment variables:{"HAUS_STAY=1"}}
    end tell
end run
OSA
else
  osascript - "$cwd" "$shell" <<'OSA' >/dev/null 2>&1
on run argv
    tell application "Ghostty"
        new window with configuration {initial working directory:item 1 of argv, command:(item 2 of argv) & " --login"}
    end tell
end run
OSA
fi
if [ $? -ne 0 ]; then
  say "couldn't ask Ghostty for a window — grant Pounce → Ghostty under Privacy & Security → Automation."
  exit 0
fi

# windows floats every runtime-spawned ghostty window (the on-window-detected
# title race — see aerospace.toml), so tile this one by hand once it has focus.
# Same poll as lane-open.sh's self-tile, from outside the window: wait for
# focus to land on a DIFFERENT window id than the one the chord started in.
# No move-node — a shell window belongs on the workspace it was asked for.
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

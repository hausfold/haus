#!/bin/bash
# pounce: name = New Shell Window
# pounce: description = Shell window in this page's repo, beside the lanes on it
# pounce: icon = terminal

# The heir of zellij's Super n. Pounce's Ghostty-scoped ⌘N fires
# `cmd:shell-here` and the spawned thing is a window rather than a pane —
# everything else about the chord survives (with the agent clients off this
# script isn't installed at all, same as focus.sh, and ⌘N is simply dead —
# Ghostty's config unbinds it rather than falling back to its own new_window,
# which knows nothing about "here"):
#
#   · the cwd is the focused window's, asked of zmx by lane-cwd.sh (the same
#     resolver ⌘↵'s lane-spawn.sh uses) — with --page, so a window whose
#     directory belongs to some OTHER repo than the page you are standing on
#     does not get to decide. The page wins the repo, the window still wins the
#     subdirectory inside it. lane-cwd.sh's header has the why.
#   · the "no place for a human shell" hop OUT of an agent worktree still
#     happens, because it lives in terminal's zshrc — the fresh login shell
#     fires it wherever it's born
#   · --stay (⌘⇧N, via shell-here-stay.sh) still suppresses that hop, now as
#     HAUS_STAY=1 in the WINDOW's environment. That is why the chord cannot use
#     Ghostty's native new_window, which can't set env at all — new-window.sh
#     carries it either way (`surface configuration` has an environment
#     variables list; `open -na` gets a `/usr/bin/env K=V` prefix). It also
#     suppresses the page correction below, for the same one reason: --stay
#     means do not move me, and the page's repo is somewhere else to be moved to.
#   · and "here" is a PLACE as well as a directory: pressed in a window
#     standing on a lane page (T/<repo>), the chord hands that page down as
#     HAUS_TERM_WORKSPACE so the new window tiles beside the lane it was asked
#     for. Without it, terminal's launch.sh — which is this window's command,
#     and tiles itself from inside — sent every shell window to the shared T,
#     so ⌘N on a page answered two pages away.
#
# The spawn itself is terminal's scripts/new-window.sh — this script decides
# WHERE and hands over. It used to carry its own copy of the AppleScript, and
# what that cost was a title: the Apple Event lands in whichever Ghostty
# instance macOS routes it to, every agent lane is an instance of its own with
# an INSTANCE-WIDE forced `--title`, and so a ⌘N window pressed in a lane was
# born named `scruff.<repo>.<lane>` with no way to take the name back.
# new-window.sh is where the refusal and the `open -na` fallback that answers it
# live now, along with the cold start, the quoting and the tile poll this file
# used to spell out a second time.
set -u

export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

stay=""
[ "${1:-}" = "--stay" ] && stay=1

# The resolver is installed by the terminal room's agents block; without it
# (which the laneCommands filter should have made unreachable) fall back to $HOME rather than
# dying on a missing file.
cwd=""
# --page for the plain chord, NOTHING for --stay. Both halves of ⌘⇧N mean the
# same thing — do not move me — and the page correction is a move: a lane window
# of repo A that has been dragged onto page `T/B` would answer B's main checkout
# for a chord whose entire promise is "stay in this worktree". So the shifted key
# keeps the old, purely window-local answer, and the two chords differ in one
# idea spelled two ways rather than in two ideas.
#
# `${page_flag[@]+"${page_flag[@]}"}` and not a bare `"${page_flag[@]}"`: this
# script's shebang is /bin/bash, macOS ships 3.2, and there `set -u` makes an
# EMPTY array's expansion an unbound-variable error — the exact trap
# scripts/new-window.sh and float-term.sh already carry a note about. So the
# --stay branch, the one branch that empties the array, killed the command
# substitution outright (exit 127, stderr swallowed by the daemon), cwd came
# back empty and the fallback below sent every ⌘⇧N to $HOME. Which is to say
# the chord whose whole promise is "stay in this worktree" was, from the day it
# was written, the one chord guaranteed to leave it. Measured 2026-08-27.
page_flag=(--page)
[ -n "$stay" ] && page_flag=()
[ -x "$HOME/.config/haus/lanes/lane-cwd.sh" ] &&
  cwd="$("$HOME/.config/haus/lanes/lane-cwd.sh" ${page_flag[@]+"${page_flag[@]}"})"
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

# Only a PAGE is handed down — a workspace with a "/" in it, the same test
# windows/scripts/workspace-mru.sh uses. Bare T needs no passing on (it is what
# launch.sh does anyway), and any OTHER workspace a terminal window has been
# dragged to is not a place shell windows should accrete: "plain terminal
# windows live on T" survives, "…unless you are on a lane's page" is the new
# half. launch.sh checks the name against the live workspace list before it
# moves anything, so a page that evaporated between here and there is harmless.
#
# `list-workspaces --focused`, not the focused WINDOW's workspace: the page you
# are looking at is the question, and it is the same one lane-cwd.sh --page
# asked a moment ago — so the directory and the page can never disagree about
# which repo this window is for. They differ exactly when focus has not caught
# up with a page walk, which is the case this whole chord kept getting wrong.
page=""
ws="$(aerospace list-workspaces --focused 2>/dev/null)"
case "$ws" in
  */*) page="$ws" ;;
esac

# ── hand over ────────────────────────────────────────────────────────────────
# One array for both chords, where there were two near-identical heredocs — the
# difference between them is a VALUE now. An entry is only worth SENDING when it
# has one: nothing here passes `HAUS_STAY=` with an empty right-hand side to
# find out how Ghostty feels about it, on the one code path where being wrong
# costs the chord.
#
# `${args[@]}` unguarded is safe where `${page_flag[@]}` above is not — this one
# is never empty, since --cwd is always in it. macOS's bash 3.2 only trips over
# an EMPTY array under `set -u`.
#
# TILED from outside, which is new-window.sh's default and what this chord has
# always done: the window it opens belongs on the page the chord was pressed on.
# The poll is self-limiting where it shouldn't fire — it waits for focus to land
# on a window that is not the one we came from, and launch.sh's un-followed move
# to T never moves focus, so a window sent home is left alone.
args=(--cwd "$cwd")
[ -n "$stay" ] && args+=(--env "HAUS_STAY=1")
[ -n "$page" ] && args+=(--env "HAUS_TERM_WORKSPACE=$page")

# The one spawn this room has, and the one thing this chord cannot do without.
# `exec` into a missing file is a silent death under the pounce daemon, which
# swallows stderr — the failure the deleted `say()` existed to prevent, so the
# check comes back rather than the helper. Absolute path for haus-notify because
# launchd's PATH names nothing of ours.
nw="$HOME/.config/haus/term/new-window.sh"
if [ ! -x "$nw" ]; then
  /run/current-system/sw/bin/haus-notify --source haus.terminal --kind fault \
    --symbol exclamationmark.triangle --title "haus · shell here" \
    --body "new-window.sh is missing — is this generation half-applied?" >/dev/null 2>&1
  exit 0
fi

exec "$nw" "${args[@]}" -- "$shell"

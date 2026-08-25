#!/bin/bash
# new-window.sh — the ONE way this room opens a TILED Ghostty window running
# something. The floating counterpart is float-term.sh's `spawn`; the split is
# by intent, not by mechanism: a peek panel or a rebuild log is summoned OVER
# your work and floats, an editor or an ssh session joins the tiling.
#
# Usage:
#   new-window.sh [--cwd DIR] [--env K=V]… [--] [COMMAND ARG…]
#
# With no COMMAND the window gets a login shell in DIR — which is what the
# window's own launcher would have given it anyway, minus the zmx session (a
# window opened to run one command has nothing worth reattaching to).
#
# ── why AppleScript and not `open -na` ───────────────────────────────────────
# 252 ms into the running instance vs 366 ms and a whole second Ghostty process
# per window (measured 2026-08-16, notes/zellij-exit.md). More importantly a
# `surface configuration` record carries `initial working directory`, `command`
# and `environment variables` natively, where `open --args` has to spell each one
# out as a flag. It does still spell them out, below: `open -na` is the FALLBACK
# this takes when the caller has no Automation grant, and the block above the
# spawn is why that case exists at all.
#
# lanes/lane-open.sh must not use this on the AEROSPACE backend: a lane is
# found there by its window TITLE, and only `open -na --title` forces a title
# the client inside can't clobber with OSC 2. Nothing here carries a name
# anything joins on, so nothing here pays for that. On its ghostty backend it
# spawns exactly the way this script does and joins on the returned window id
# instead — inlined rather than shelling out here, because it needs that id
# back and this script's contract is "open a window", not "tell me which".
#
# ── why the tile poll ────────────────────────────────────────────────────────
# windows/aerospace.toml floats every runtime-spawned Ghostty window, because an
# `on-window-detected` title rule races window detection (the AX title lands
# after the window is mapped) and a popup tiled for a beat reflows the whole
# workspace. So a window that WANTS tiling asks for it by hand, once it has
# focus. Same poll as lane-open.sh's self-tile, run from outside the window:
# wait for focus to land on a different window id than the one we started from.
set -u

export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

cwd=""
envs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --cwd) cwd="$2"; shift 2 ;;
    --env) envs+=("$2"); shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done

[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$HOME"

# An explicit login shell, NOT the ghostty-config default command: that default
# is scripts/launch.sh, which would claim a `term.<n>` zmx session for a window
# whose whole life is one command.
shell="${SHELL:-/bin/zsh}"

# Single quotes, hand-rolled, rather than `printf %q`. %q escapes with
# BACKSLASHES outside any quotes (`a\ b`, `\$1`, `\;`), which would assume
# Ghostty's splitter implements backslash escaping — and that failure mode is the
# bad kind: the window opens and runs a not-quite-right command. Single quotes
# assume only that it implements quotes.
#
# The pattern and the replacement come from VARIABLES rather than being written
# inline, and that is not style: `${a//\'/…}` puts backslashes in the
# replacement, and bash keeps them literally — the round trip produced
# `'it\'"\'"\'s'`, which is a syntax error rather than a string. From variables
# there are no backslashes to survive.
sq="'"
esc="'\"'\"'"
shq() {
  local out="" a
  for a in "$@"; do
    out="$out$sq${a//$sq/$esc}$sq "
  done
  printf '%s' "$out"
}

if [ $# -gt 0 ]; then
  # `command` in a surface configuration is a shell-style STRING that Ghostty
  # splits, so each argument has to be quoted back into one. `initial-command`,
  # which the fallback below passes on the command line, is split the same way —
  # one quoting rule serves both spawns.
  #
  # MEASURED on Ghostty 1.3.1, not reasoned: a `zsh -c '…'` payload carrying
  # `a b.rs:12`, `+12` and `has$dollar` as separate single-quoted arguments came
  # back out of the surface as exactly those three argv entries. An embedded
  # single quote closes, adds a double-quoted one, and reopens — `'"'"'` — so
  # even that case needs no backslash.
  cmd="$(shq "$@")"
else
  cmd="$shell --login"
fi

# AppleScript string literals escape backslash and double-quote and nothing
# else, and every value below is attacker-adjacent (a filename from a click, an
# ssh host from the palette). Build the record by hand rather than through
# `on run argv`, because the environment-variables list has no argv shape.
osa_str() {
  local v="$1"
  v="${v//\\/\\\\}"
  v="${v//\"/\\\"}"
  printf '"%s"' "$v"
}

env_list=""
if [ "${#envs[@]}" -gt 0 ]; then
  for e in "${envs[@]}"; do
    [ -n "$env_list" ] && env_list="$env_list, "
    env_list="$env_list$(osa_str "$e")"
  done
  env_list=", environment variables:{$env_list}"
fi

# The window AeroSpace sees before this one, so the poll below can tell the new
# window from the one we were called from (both are Ghostty). Empty, and every
# AeroSpace line below skipped, on a machine with no tiler — the window still
# opens, macOS still places it, and scripts/launch.sh inside it still stamps
# the join label (a Ghostty window id there rather than an AeroSpace one).
tiler=0
command -v aerospace >/dev/null 2>&1 && [ "${HAUS_WINDOW_BACKEND:-aerospace}" = aerospace ] && tiler=1
before=""
[ "$tiler" = 1 ] && before="$(aerospace list-windows --focused --format '%{window-id}' 2>/dev/null)"

# Cold start: `open -a` returns as soon as LaunchServices accepts, and asking a
# not-yet-running Ghostty for a window over Apple Events just fails.
#
# `pgrep -ix ghostty`, not `pgrep -x Ghostty`: the executable inside the bundle
# is lowercase (`Ghostty.app/Contents/MacOS/ghostty`), so the capitalised form
# NEVER matched — every ⌘N took the cold-start branch, activated a Ghostty that
# was already running, and then polled for a full two seconds before asking for
# the window. Fixed 2026-08-19; the same one-word bug was in lanes/lane-open.sh.
if ! pgrep -ix ghostty >/dev/null 2>&1; then
  open -a Ghostty
  for _ in $(seq 1 40); do
    pgrep -ix ghostty >/dev/null 2>&1 && break
    sleep 0.05
  done
fi

# ── why there are two ways to spawn ─────────────────────────────────────
# The Apple Event needs an Automation grant keyed to whatever macOS holds
# RESPONSIBLE for this process. That is pounce for every chord and the bar for
# its rows — signed once, granted once, granted still. For a double-clicked file
# it is EditorOpen.app, which modules/terminal `osacompile`s fresh on EVERY
# activation and never signs: its cdhash moves each rebuild, so a grant can't
# stick even if someone answers the prompt (the same fact modules/launcher
# re-signs pounce to dodge). What that costs is a refusal, or a fresh consent
# prompt once per rebuild — neither of which ends in a window — and `do shell
# script` turns the exit 1 below into a "The command exited with a non-zero
# status. (1)" dialog on every double-click — which is what .md files got after
# #401 moved this room off zellij, whose opener depended on no event at all.
#
# `open -na` needs no grant at all, because launching an app is not automating
# one. It costs a second Ghostty process and ~366 ms against the event's ~252 ms
# (notes/zellij-exit.md, measured for exactly this argv shape), and it carries
# cwd and command as config flags rather than natively. `--initial-command=`, NOT
# `-e`: macOS refuses to run the terminal from the CLI at all, so `ghostty -e …`
# is unsupported there (scripts/float-term.sh:63) and every `open -na` this room
# already ships — lanes/lane-open.sh, float-term.sh — passes the command as a
# config flag. Ghostty has no environment flag to match, so an `--env` rides in
# as a `/usr/bin/env K=V …` prefix on that same string.
#
# Slower and coarser, so it stays the fallback. It is not purely worse, though:
# a window in an instance of its OWN closes cleanly when its command exits (the
# config's quit-after-last-window-closed ends the process), which is exactly the
# hazard AGENTS.md's "Ghostty does not close a TILED window" gotcha describes for
# the shared instance.
fallback=0
spawned=0
if osascript -e "tell application \"Ghostty\" to new window with configuration {initial working directory:$(osa_str "$cwd"), command:$(osa_str "$cmd")$env_list}" >/dev/null 2>&1; then
  spawned=1
  osascript -e 'tell application "Ghostty" to activate' >/dev/null 2>&1
else
  fallback=1
  # The env prefix is applied to `$cmd` whatever it holds — the command the
  # caller passed, or the plain login shell. peek-run.sh is the caller that
  # proves the second case matters: `--cwd <worktree> --env HAUS_STAY=1` and no
  # command at all, and a window that loses HAUS_STAY gets teleported out of the
  # worktree by the shell's own cd (modules/terminal/default.nix), silently.
  #
  # Guarded on ${#envs[@]} rather than expanding an empty array: /bin/bash is
  # 3.2, where `set -u` makes "${envs[@]}" an unbound-variable error when empty.
  ls_cmd="$cmd"
  if [ "${#envs[@]}" -gt 0 ]; then
    ls_cmd="/usr/bin/env $(shq "${envs[@]}")$ls_cmd"
  fi
  open -na Ghostty --args \
    "--working-directory=$cwd" "--initial-command=$ls_cmd" >/dev/null 2>&1 &&
    spawned=1
fi

if [ "$spawned" != 1 ]; then
  # Failing silently is the one sin a chord can't afford. Both paths gone means
  # something bigger than a missing grant — no Ghostty on the machine, usually.
  /run/current-system/sw/bin/haus-notify --source haus.terminal --kind fault \
    --symbol exclamationmark.triangle --title "haus · new window" \
    --body "couldn't open a Ghostty window — is Ghostty installed?" >/dev/null 2>&1
  exit 1
fi

if [ "$tiler" = 1 ]; then
  # The fallback gets a longer poll: `open -na` boots a whole second Ghostty, so
  # its window is mapped well after the running instance would have answered.
  tries=20
  [ "$fallback" = 1 ] && tries=60
  for _ in $(seq 1 $tries); do
    wid="$(aerospace list-windows --focused --format '%{window-id}' 2>/dev/null)"
    [ -n "$wid" ] && [ "$wid" != "$before" ] && break
    sleep 0.05
  done
  [ -n "${wid:-}" ] && [ "$wid" != "$before" ] &&
    aerospace layout --window-id "$wid" tiling >/dev/null 2>&1
fi

exit 0

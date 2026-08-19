#!/bin/bash
# lane-cwd.sh — "which directory is the focused window looking at?"
#
# The shared half of every window-layer chord. A zellij bind inherited the
# focused pane's directory for free; a chord bound outside the terminal (⌘↵'s
# lane-spawn.sh, ⌘N/⌘⇧N's shell-here, ⌘Y's peek, ⌘B, ⌃⌥⇧A) has no directory at
# all, so it has to ask.
#
# The answer is one hop past scripts/focused-session.sh, which does the hard
# half — window → zmx session, by forced title for a lane and by the `window=`
# label for everything else. `zmx ls` then reports that session's directory.
#
# A window with no session — a browser, Finder, the quick terminal — prints
# NOTHING; the caller picks its own fallback, because "from anywhere" beats a
# refusal and what "anywhere" should mean differs per chord.
#
# stdout: the directory, or empty. Exit 0 either way.
set -u

export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin${PATH:+:$PATH}"

command -v zmx >/dev/null 2>&1 || exit 0

sess="$("$HOME/.config/haus/term/focused-session.sh" 2>/dev/null)"
[ -n "$sess" ] || exit 0

# `zmx ls` is tab-separated k=v, with three traps that every copy of this parse
# (scripts/focused-session.sh, scripts/find.sh, scripts/launch.sh, the bar's
# agents.sh, the palette's lanes.sh) has to handle:
#
#   · The directory field is `start_dir` in zmx 0.7.0; older zmx called it `cwd`
#     and wrapped it in a file:// URL with the host in it. Both spellings are
#     accepted and the URL prefix is stripped when present. Reading only `cwd`
#     is what silently broke ⌘↵ once: no directory came back, the chord fell
#     through to $HOME, and $HOME isn't a git repo.
#   · zmx marks rows in the FIRST field ("→ ** name=…" for the session you are
#     attached to), so that row's first key arrives with the marker glued to it.
#     Strip everything before the key proper, or the session you pressed the
#     chord IN is the one row that fails to resolve.
#   · **`start_dir` is where the session was BORN, not where it is now.** It is
#     stamped once at `zmx attach` and never moves again, so a window opened in
#     $HOME still reports $HOME after you `cd` into a repo — which is the whole
#     of "⌘↵ says julienmartel isn't a git repo" while you are plainly standing
#     in one. zmx has no live-cwd field to ask for (0.7.0's `ls` emits exactly
#     name/pid/clients/created/start_dir/window), so the live answer has to come
#     from the kernel: `pid` is the session's own login shell, and a shell's cwd
#     IS the thing that tracks `cd`. That makes start_dir the FALLBACK — right
#     for a session whose shell has died or that we can't read — and the pid's
#     real cwd the answer.
row="$(
  zmx ls 2>/dev/null | awk -F'\t' -v want="$sess" '
    {
      name = ""; c = ""; pid = ""
      for (i = 1; i <= NF; i++) {
        eq = index($i, "=")
        if (eq == 0) continue
        k = substr($i, 1, eq - 1); gsub(/^[ \t]+|[ \t]+$/, "", k)
        sub(/^[^A-Za-z_]*/, "", k)
        if (k == "name") name = substr($i, eq + 1)
        else if (k == "pid") pid = substr($i, eq + 1)
        else if (k == "start_dir") c = substr($i, eq + 1)
        else if (k == "cwd" && c == "") c = substr($i, eq + 1)
      }
      if (name == want && (c != "" || pid != "")) {
        sub(/^file:\/\/[^\/]*/, "", c)
        print pid "\t" c
        exit
      }
    }
  '
)"

pid="${row%%$'\t'*}"
cwd="${row#*$'\t'}"

# macOS has no /proc, so a process's cwd is lsof's to give — one pid, one fd,
# ~30 ms, paid only when a chord is pressed rather than on every `cd`. It lives
# in /usr/sbin, which is why the PATH prelude above carries that dir.
if [ -n "$pid" ]; then
  live="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)"
  [ -n "$live" ] && [ -d "$live" ] && cwd="$live"
fi

[ -n "$cwd" ] && [ -d "$cwd" ] && printf '%s\n' "$cwd"
exit 0

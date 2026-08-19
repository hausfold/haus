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

export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

command -v zmx >/dev/null 2>&1 || exit 0

sess="$("$HOME/.config/haus/term/focused-session.sh" 2>/dev/null)"
[ -n "$sess" ] || exit 0

# `zmx ls` is tab-separated k=v, with two traps that every copy of this parse
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
cwd="$(
  zmx ls 2>/dev/null | awk -F'\t' -v want="$sess" '
    {
      name = ""; c = ""
      for (i = 1; i <= NF; i++) {
        p = index($i, "=")
        if (p == 0) continue
        k = substr($i, 1, p - 1); gsub(/^[ \t]+|[ \t]+$/, "", k)
        sub(/^[^A-Za-z_]*/, "", k)
        if (k == "name") name = substr($i, p + 1)
        if (k == "start_dir") c = substr($i, p + 1)
        else if (k == "cwd" && c == "") c = substr($i, p + 1)
      }
      if (name == want && c != "") { sub(/^file:\/\/[^\/]*/, "", c); print c; exit }
    }
  '
)"

[ -n "$cwd" ] && [ -d "$cwd" ] && printf '%s\n' "$cwd"
exit 0

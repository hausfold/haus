#!/bin/bash
# lane-cwd.sh — "which directory is the focused window looking at?"
#
# The shared half of every window-layer chord. A zellij bind inherited the
# focused pane's directory for free; a chord bound at the window layer (⌃⌘A's
# lane-spawn.sh, ⌘P/⌘⇧P's shell-here) has no directory at all, so it has to
# ask. The window TITLE is the join in both worlds:
#
#   holt.<repo>.<lane>   a zmx lane window. lane-open.sh forced that title, and
#                        `zmx ls` reports that session's cwd.
#   <session name>       a zellij window — ghostty shows the zellij session name
#                        (verified: `aerospace list-windows` prints "Ghostty|main").
#                        `zellij action dump-layout` then carries the focused
#                        pane's LIVE cwd, not its launch cwd: a pane that
#                        chdir'd reports where it is now.
#
# Anything else — a browser, Finder, a plain shell — has no repo to speak of and
# prints NOTHING; the caller picks its own fallback, because "from anywhere"
# beats a refusal and what "anywhere" should mean differs per chord.
#
# stdout: the directory, or empty. Exit 0 either way.
set -u

export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

focused() { aerospace list-windows --focused --format "$1" 2>/dev/null; }

title="$(focused '%{window-title}')"
app="$(focused '%{app-name}')"
cwd=""

# ── a zmx lane window ────────────────────────────────────────────────────────
case "$title" in
  holt.*)
    if command -v zmx >/dev/null 2>&1; then
      # `zmx ls` is tab-separated k=v; cwd comes back as a file:// URL with the
      # host in it, which is the same shape (and the same strip) the bar's
      # agents.sh already parses.
      cwd="$(
        zmx ls 2>/dev/null | awk -F'\t' -v want="$title" '
          {
            name = ""; c = ""
            for (i = 1; i <= NF; i++) {
              p = index($i, "=")
              if (p == 0) { gsub(/^[ \t]+|[ \t]+$/, "", $i); if (name == "") name = $i; continue }
              k = substr($i, 1, p - 1); gsub(/^[ \t]+|[ \t]+$/, "", k)
              if (k == "name") name = substr($i, p + 1)
              if (k == "cwd")  c    = substr($i, p + 1)
            }
            if (name == want && c != "") { sub(/^file:\/\/[^\/]*/, "", c); print c; exit }
          }
        '
      )"
    fi
    ;;
esac

# ── a zellij window ──────────────────────────────────────────────────────────
# The title is the session name. Panes carry a cwd RELATIVE to the layout's own
# `cwd`, exactly one tab is focus=true and exactly one pane inside it is, so the
# answer is "the focused pane of the focused tab" — the depth tracking is what
# stops a focused pane in some other tab from winning.
if [ -z "$cwd" ] && [ "$app" = "Ghostty" ] && [ -n "$title" ] && command -v zellij >/dev/null 2>&1; then
  cwd="$(
    zellij --session "$title" action dump-layout 2>/dev/null | awk '
      BEGIN { depth = 0; tabdepth = -1; base = ""; found = "" }
      /^[ \t]*cwd[ \t]+"/ && base == "" {
        line = $0; sub(/^[ \t]*cwd[ \t]+"/, "", line); sub(/".*$/, "", line); base = line
      }
      {
        if ($0 ~ /^[ \t]*tab[ \t]/ && $0 ~ /focus=true/) tabdepth = depth
        if (tabdepth >= 0 && found == "" && $0 ~ /^[ \t]*pane/ && $0 ~ /focus=true/) {
          if (match($0, /cwd="[^"]*"/)) found = substr($0, RSTART + 5, RLENGTH - 6)
          else found = "."
        }
        n = gsub(/\{/, "{"); depth += n
        n = gsub(/\}/, "}"); depth -= n
        # <=, not <: tabdepth is recorded BEFORE the opening line s braces are
        # counted, so at the tab s closing brace depth is back to tabdepth
        # exactly. With < this never fired, and only zellij marking one
        # focus=true pane in the whole dump kept that from mattering.
        if (tabdepth >= 0 && depth <= tabdepth) tabdepth = -1
      }
      END {
        if (found == "" || found == ".") { print base; exit }
        if (found ~ /^\//) { print found; exit }
        print base "/" found
      }
    '
  )"
fi

[ -n "$cwd" ] && [ -d "$cwd" ] && printf '%s\n' "$cwd"
exit 0

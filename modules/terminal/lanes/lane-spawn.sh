#!/bin/bash
# lane-spawn.sh — "start an agent here", bound at the WINDOW layer.
#
# This is the other half of haus.terminal.lanes.backend = "zmx". lane-open.sh
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
# So the chord belongs to the only layer that sees every window: AeroSpace,
# which already owns the global chord table (modules/windows/wm-bindings.nix)
# and already tiles these windows. Same conclusion notes/zellij-exit.md reached
# for the whole keymap — "chords move to AeroSpace, not to Ghostty" — arrived at
# early, for the one chord that needed it first.
#
# ── the cost of that: no cwd ─────────────────────────────────────────────────
# A zellij bind inherited the focused pane's directory for free. A window-layer
# chord has no directory at all, so it has to ask. The window TITLE is the join
# in both worlds, which is the same property the zmx backend was designed
# around:
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
# falls back, because "⌘A from anywhere" is worth more than a refusal.
set -u

# Bound through AeroSpace's exec-and-forget, which runs with a bare environment.
# Same prelude as lane-open.sh, for the same reason.
export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

# ── saying no out loud ───────────────────────────────────────────────────────
# This runs under AeroSpace's exec-and-forget: no terminal, no stdout anyone
# will ever see. So `holt new` refusing ("not inside a git repo") is invisible,
# and a global chord that silently does nothing is worse than one that isn't
# bound — you press it again, harder, and conclude the rebuild didn't land.
# Everything below that gives up says so on screen first.
say() { osascript -e "display notification \"$1\" with title \"haus · agent lane\"" >/dev/null 2>&1; }

# Where a chord pressed over a browser puts you. It only helps if it happens to
# be a repo; when it isn't, `refuse` is what the user actually gets.
fallback="${HAUS_LANE_FALLBACK:-$HOME}"

command -v holt >/dev/null 2>&1 || {
  say "holt isn't on PATH — nothing to spawn a lane with."
  exit 0
}

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
  say "$(basename "$cwd") isn't a git repo — focus a window in one, then press ⌃⌘A."
  exit 0
fi

exec holt new

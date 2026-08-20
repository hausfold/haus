#!/bin/bash
# raise-session.sh — "go to the window running this zmx session."
#
# The mirror of scripts/focused-session.sh: that one asks the window layer
# which session is in front, this one asks it to put a named session in front.
# Three callers, and they had a copy each until 2026-08-19 — the bar's agents
# popup (bar/sketchybar/plugins/agents.sh, clicking an agent row), ⌘F's ⏎
# (scripts/find.sh, jumping to the window a hit came from) and the palette's
# Lanes command (launcher/commands/lanes.sh, both its rows and its `/` content
# search). All three had the same joins, all three spelled AeroSpace, and none
# of them worked on a machine without a tiler.
#
#   raise-session.sh [--or-open] <session>
#
# Exit 0 = a window was raised. Exit 1 = no window has this session; it is
# detached and still running (the whole point of zmx), and what to do about
# that is the caller's call — find.sh deliberately does nothing, and the bar
# passes --or-open, which opens a fresh window onto the session instead. That
# lives here rather than in the caller because "open a window onto a session"
# is the same backend question as "raise one", and the bar has no business
# knowing the answer.
#
# Backends are lanes/lane-open.sh's, read the same way, for the same reason:
#
#   aerospace  a LANE is an exact window-title match (lane-open.sh forces the
#              title to the session name). Anything else is found through the
#              `window=` label scripts/launch.sh stamps.
#   ghostty    both kinds are found through the `gwindow=` label — Ghostty's
#              own stable window id — and raised with `activate window`, which
#              needs no tiler and no Accessibility grant.
set -u

export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

or_open=0
if [ "${1:-}" = "--or-open" ]; then
  or_open=1
  shift
fi

sess="${1:-}"
[ -n "$sess" ] || exit 1
# Both backends put this name inside a quoted string (an AppleScript literal,
# or Ghostty's shell-split initial-command). zmx session names the rice writes
# are `term.<n>` and `holt.<repo>.<lane>`; anything else is a bug rather than
# an input, so refuse it instead of escaping it.
case "$sess" in
  *[!A-Za-z0-9._-]*) exit 1 ;;
esac
command -v zmx >/dev/null 2>&1 || exit 1

backend="${HAUS_WINDOW_BACKEND:-}"
if [ -z "$backend" ]; then
  if command -v aerospace >/dev/null 2>&1; then backend=aerospace; else backend=ghostty; fi
fi

# One session's label, by key. `zmx get` is tab-separated k=v like `zmx ls`,
# minus the attached-row marker, so a plain sed is enough here.
label() {
  zmx get "$sess" 2>/dev/null | tr '\t' '\n' | sed -n "s/^ *$1=//p" | head -1
}

# ── no window has it: open one, if the caller asked ──────────────────────────
# The session already exists (it is detached, not gone), so `zmx attach` walks
# straight back into the live conversation — this is never a restart.
open_window() {
  [ "$or_open" = 1 ] || return 1
  case "$backend" in
    aerospace)
      open -na Ghostty.app --args --title="$sess" --initial-command="zmx attach $sess"
      ;;
    ghostty)
      # Same spawn lanes/lane-open.sh uses on this backend, and the same
      # `gwindow=` stamp, so the window it opens is one this script can raise
      # next time. No retry loop around the `zmx set`: unlike a fresh lane,
      # the session is already there.
      gwid=$(
        /usr/bin/osascript 2>/dev/null <<APPLESCRIPT
tell application "Ghostty"
  set w to (new window with configuration {command:"zmx attach $sess"})
  activate
  return id of w
end tell
APPLESCRIPT
      )
      [ -n "$gwid" ] || return 1
      zmx set "$sess" "gwindow=$gwid" >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
  return 0
}

case "$backend" in
  aerospace)
    win=$(aerospace list-windows --all --format '%{window-id}|%{app-name}|%{window-title}' 2>/dev/null |
      awk -F'|' -v t="$sess" '$2 == "Ghostty" && $3 == t { print $1; exit }')
    if [ -z "$win" ]; then
      lw=$(label window)
      [ -n "$lw" ] && win=$(aerospace list-windows --all --format '%{window-id}' 2>/dev/null | grep -Fx "$lw")
    fi
    if [ -z "$win" ]; then
      open_window && exit 0
      exit 1
    fi
    aerospace focus --window-id "$win" >/dev/null 2>&1
    ;;

  ghostty)
    gw=$(label gwindow)
    if [ -z "$gw" ]; then
      open_window && exit 0
      exit 1
    fi
    # The label goes into an AppleScript string literal below. Ghostty's ids
    # are `window-<hex>`, so rather than escape a value that should never need
    # it, refuse anything that isn't shaped like one — a label is written by
    # this rice, and one that isn't is a bug, not an input.
    case "$gw" in
      *[!A-Za-z0-9._-]*) exit 1 ;;
    esac
    # Iterate rather than `first window whose id is …`: a whose-clause over a
    # scripting-bridge collection is the kind of thing that quietly returns the
    # wrong object when the property is a string, and there are never more than
    # a handful of windows to walk.
    #
    # `activate window` puts that window in front of Ghostty's own stack;
    # the bare `activate` is what puts Ghostty in front of everything else.
    # Both are needed — a window raised inside a background app is still
    # behind your browser.
    out=$(
      /usr/bin/osascript 2>/dev/null <<APPLESCRIPT
tell application "Ghostty"
  repeat with w in windows
    if (id of w as text) is "$gw" then
      activate window w
      activate
      return "ok"
    end if
  end repeat
  return ""
end tell
APPLESCRIPT
    )
    if [ "$out" != ok ]; then
      open_window && exit 0
      exit 1
    fi
    ;;

  *)
    exit 1
    ;;
esac

exit 0

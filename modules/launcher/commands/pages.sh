#!/bin/bash
# pounce: name = Pages
# pounce: description = Jump to a repo page, or throw this window onto one
# pounce: icon = square.stack
# pounce: submenu = true
#
# The picker for the terminal PAGES — `T` and the `T/<repo>` workspaces a lane's
# window tiles itself onto (terminal/lanes/lane-open.sh). Two acts on one list,
# because they are the same question asked in two directions:
#
#   ↵    go to that page
#   ⇧↵   throw the focused window onto it, and follow it there
#
# `pages.sh move` opens the same list with those two swapped, which is what the
# bar's `page` pill runs on a ⇧/right-click. One command, one list, one place to
# fix — a second "Move window to page" entry would fuzzy-match against the first
# every time you typed "page".
#
# ── why a palette command and not a keybind ──────────────────────────────────
# `caps `` (resort-windows.sh) already puts EVERY window back on its page, which
# is the bulk operation and rightly a chord. Moving ONE window somewhere it
# doesn't belong is the opposite: rare, and it needs an argument — which page —
# that no chord can carry. A chord per page would be a chord per repo.
#
# ── the focused window, captured first ───────────────────────────────────────
# $WID is read at the top, BEFORE any `pounce` call. That ordering is the whole
# correctness of the move: by the time a pick comes back, the palette has been
# on screen and taken the keyboard. It happens to be safe either way — pounce's
# palette is a borderless `.nonactivatingPanel`, which AeroSpace does not manage
# and does not list, so `--focused` keeps answering with the window underneath
# it — but that is a fact about another repo's window style, and this script
# should not be the thing that breaks if it ever changes.
set -u

# A palette command runs under the pounce daemon's launchd environment, whose
# PATH is bare. Same prelude as the other commands here.
export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

command -v aerospace >/dev/null 2>&1 || exit 0

MODE="${1:-go}"

WID="$(aerospace list-windows --focused --format '%{window-id}' 2>/dev/null | tr -d '[:space:]')"

# ── the rows ─────────────────────────────────────────────────────────────────
# One line per live page. `list-workspaces --monitor all` reports the persistent
# ones plus every non-persistent one currently holding a window — which is
# exactly the set of pages, since lane-open.sh deliberately keeps `T/<repo>` OUT
# of persistent-workspaces so an emptied page evaporates instead of accreting.
#
# Bare `T` is forced into the list rather than taken from that output: it is the
# page you most often want to throw something back to, and it is the one that is
# empty precisely when you need it (every terminal window has been paged away).
pages="$(
  { printf 'T\n'; aerospace list-workspaces --monitor all 2>/dev/null; } \
    | awk '$0 == "T" || $0 ~ /^T\// { if (!seen[$0]++) print }'
)"

# App names per workspace, counted in ONE pass — a `list-windows --workspace`
# call per page would be one subprocess per repo on the palette's interactive
# path. Tab-separated so a window title can never be mistaken for a delimiter.
summaries="$(
  aerospace list-windows --all --format '%{workspace}|%{app-name}' 2>/dev/null |
    awk -F'|' '
      { gsub(/^[ \t]+|[ \t]+$/, "", $1); gsub(/^[ \t]+|[ \t]+$/, "", $2)
        n[$1]++
        if (index(":" apps[$1] ":", ":" $2 ":") == 0)
          apps[$1] = (apps[$1] == "" ? $2 : apps[$1] ":" $2) }
      END { for (w in n) { a = apps[w]; gsub(/:/, ", ", a)
              printf "%s\t%d window%s · %s\n", w, n[w], (n[w] == 1 ? "" : "s"), a } }'
)"

if [ "$MODE" = move ]; then
  actions="Throw this window here|shift:Just go there"
  prompt="Throw this window onto which page?"
else
  actions="Go|shift:Throw this window here"
  prompt="Pages"
fi

current="$(aerospace list-workspaces --focused 2>/dev/null)"

rows="$(
  printf '%s\n' "$pages" | while IFS= read -r ws; do
    [ -n "$ws" ] || continue
    desc="$(printf '%s\n' "$summaries" | awk -F'\t' -v w="$ws" '$1 == w { print $2; exit }')"
    [ -n "$desc" ] || desc="empty"
    [ "$ws" = "$current" ] && desc="$desc  ·  you are here"
    # `T` is not a repo and shouldn't be dressed as one.
    if [ "$ws" = T ]; then
      icon="terminal"
      title="T"
    else
      icon="folder"
      title="$ws"
    fi
    printf '%s\t%s\t%s\t%s\tPages\t%s\n' "$title" "$desc" "$icon" "$actions" "$ws"
  done
)"

[ -n "$rows" ] || exit 0

sel="$(printf '%s\n' "$rows" | pounce -p "$prompt" -i "square.stack")" || exit 0
[ -n "$sel" ] || exit 0

# A reply is "<action>\t<the whole row>", so every column shifts by one and the
# hidden 6th field arrives as the 7th.
action="$(printf '%s' "$sel" | head -n1 | cut -f1)"
page="$(printf '%s' "$sel" | cut -f7)"

# Free text that matched no row: treat it as a page NAME. AeroSpace creates a
# workspace on first use, so throwing a window at `T/newthing` is a working act
# and not a typo to refuse — and it is how you page a repo whose first lane
# hasn't been opened yet. Anything already looking like a page is taken as-is.
if [ -z "$page" ]; then
  typed="$(printf '%s' "$sel" | cut -f2)"
  typed="$(printf '%s' "$typed" | tr -d '[:space:]')"
  [ -n "$typed" ] || exit 0
  case "$typed" in
    T | T/*) page="$typed" ;;
    *) page="T/$typed" ;;
  esac
fi

# Which act the pick meant. Enter is the mode's primary; ⇧ is the other one, so
# either mode can reach either act without reopening the picker in the other.
case "$MODE:$action" in
  move:enter | go:shift) act=move ;;
  *) act=go ;;
esac

if [ "$act" = move ]; then
  if [ -z "$WID" ]; then
    printf '%s\t%s\t%s\n' "No window to move" "Focus one, then try again" "exclamationmark.triangle" \
      | pounce -p "Pages" -i "square.stack" >/dev/null
    exit 0
  fi
  # --focus-follows-window: you threw it somewhere for a reason. Going with it
  # is also the only way to SEE that it landed, since the window you were just
  # looking at is now on another workspace.
  aerospace move-node-to-workspace --focus-follows-window --window-id "$WID" "$page" >/dev/null 2>&1
  # A window moved onto a page arrives floating if it was floating; a page is a
  # tiled workspace, and a float on it is the one thing resort-windows.sh can't
  # fix later.
  aerospace layout --window-id "$WID" tiling >/dev/null 2>&1
else
  aerospace workspace "$page" >/dev/null 2>&1
fi

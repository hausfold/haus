#!/bin/bash
# pounce: name = Pages
# pounce: description = Jump to a workspace page, or throw this window onto one
# pounce: icon = square.stack
# pounce: submenu = true
# pounce: whenFile = ~/.local/state/haus/any-page
# pounce: cheatWhen = while a page exists
#
# That `whenFile` is why this row can be missing: the palette hides it while the
# file says `0`, which is while there is no page ANYWHERE on this Mac — nothing
# to go to, and nothing this list could name but the bare `T` it forces in.
# windows/scripts/workspace-mru.sh writes the file on every workspace change,
# the same hook and the same directory the recency file it already writes lives
# in; a Mac with no tiler never writes it at all, and a file that does not exist
# is a yes, so the row simply stays.
#
# GLOBAL, deliberately, and not "does the workspace you are on have pages": this
# list is every base with a live page at once, which is exactly why it is worth
# opening from a browser on `R`. The per-workspace question belongs to the bar's
# `page` pill (bar/sketchybar/plugins/page.sh), which answers it by naming where
# you are. The one thing hiding costs: with no page anywhere, the free-text
# "throw this window onto a page nobody has opened yet" door below is shut until
# some page exists — one ⌘↵ away, and the case it serves (paging a repo whose
# first lane is not open) needs a lane to have been opened somewhere anyway.
#
# The picker for PAGES — any workspace with a `/` in its name, plus the
# workspace it hangs off. `T/<repo>`, the page a lane's window tiles itself onto
# (terminal/lanes/lane-open.sh), is the only producer haus ships, but AeroSpace
# makes a workspace on first use and the bar's page pill names the page of
# whatever workspace you are on — so this list follows the pill rather than the
# one producer. Two acts on one list, because they are the same question asked
# in two directions:
#
#   ↵    go to that page
#   ⌥↵   throw the focused window onto it, and follow it there
#
# `pages.sh move` opens the same list with those two swapped, which is what the
# bar's `page` pill runs on a ⇧/right-click. One command, one list, one place to
# fix — a second "Move window to page" entry would fuzzy-match against the first
# every time you typed "page".
#
# Not ⇧↵, which reads better and does not work: pounce treats Shift+Return as
# "insert a newline" in the text field and never commits on it (Rows.swift), so
# a `shift:` action is a HINT it draws and never delivers — the row would just
# navigate, silently doing the other thing. The committing modifiers are ⌘, ⌥
# and ⌃, which is why spawn-agent.sh's box reaches for ⌘↵/⌥↵.
#
# And ⌥ rather than ⌘ out of those, because ⌘↵ stopped being free: it is the
# Ghostty-scoped lane chord as of the ⌘N/⌘↵ move. That chord rides a consuming
# CGEventTap gated on `NSWorkspace.frontmostApplication` (pounce's
# AppScoped.swift), and a pounce picker is a `.nonactivatingPanel` — it never
# becomes frontmost, so with Ghostty behind it the tap plausibly eats ⌘↵ before
# the picker sees it and spawns a lane instead. Rather than depend on the
# answer, this takes the modifier nothing is scoped to. The pill's own ⇧-click
# is a third thing again and unaffected: that modifier arrives from SketchyBar,
# which has no such rule.
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

if ! command -v aerospace >/dev/null 2>&1; then
  printf '%s\t%s\t%s\n' "AeroSpace is unavailable" "Rebuild haus, then try again" \
    "exclamationmark.triangle" | pounce -p "Pages" -i "square.stack" >/dev/null
  exit 1
fi

MODE="${1:-go}"

WID="$(aerospace list-windows --focused --format '%{window-id}' 2>/dev/null | tr -d '[:space:]')"

# ── the rows ─────────────────────────────────────────────────────────────────
# One line per live page. `list-workspaces --monitor all` reports the persistent
# ones plus every non-persistent one currently holding a window — which is
# exactly the set of pages, since lane-open.sh deliberately keeps `T/<repo>` OUT
# of persistent-workspaces so an emptied page evaporates instead of accreting.
#
# A page is any workspace with a `/` in it, not a `T/` one: `T/<repo>` is the
# only producer haus ships (lane-open.sh), but AeroSpace makes a workspace on
# first use and the bar's page pill names the page of whatever workspace you are
# on, so a list that hardcoded `T` would light a pill whose click cannot reach
# its own page. Each page's BASE comes along, because "put this back where it
# belongs" is the other half of the question this list answers.
#
# Bare `T` is forced in on top of that rather than taken from the output: it is
# the page you most often want to throw something back to, and it is the one
# that is empty precisely when you need it (every terminal window has been paged
# away), so it would be missing from a purely live list at exactly that moment.
pages="$(
  { printf 'T\n'; aerospace list-workspaces --monitor all 2>/dev/null; } \
    | awk '
        function emit(w) { if (!seen[w]++) print w }
        { line[++n] = $0 }
        END {
          emit("T")
          # A base earns a row only when something under it is live, so it is
          # emitted from the page rather than from the input — and just before
          # it, which groups each workspace with its own pages.
          for (i = 1; i <= n; i++)
            if (line[i] ~ /\//) {
              base = line[i]; sub(/\/.*$/, "", base)
              emit(base); emit(line[i])
            }
        }
      '
)"

# App names per workspace, from ONE `aerospace` call — the alternative is a
# `list-windows --workspace` per page, and AeroSpace's own startup cost is what
# makes that N subprocesses too many on the palette's interactive path. (The
# awk that reads this table back below runs once per row, which is a fork over a
# string already in memory and not the thing worth avoiding.) Tab-separated so a
# window title can never be mistaken for a delimiter.
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
  actions="Throw this window here|opt:Just go there"
  prompt="Throw this window onto which page?"
else
  actions="Go|opt:Throw this window here"
  prompt="Pages"
fi

current="$(aerospace list-workspaces --focused 2>/dev/null)"

# ── NO APOSTROPHES OR BACKTICKS IN THE COMMENTS BELOW ────────────────────────
# They live inside a `$( )`, and bash 3.2 — which is `/bin/bash` on macOS, and
# so is this script's shebang — does not recognise `#` as starting a comment in
# there. A lone `'` opens a single-quoted string that never closes; a lone
# backtick opens a command substitution that never closes. Either way the
# failure is not local: the parse runs to EOF and the WHOLE FILE dies with
# `unexpected EOF`, at startup, before a single line has run.
#
# One word cost this picker exactly that. The row-icon comment read
# "shouldn't be dressed as one" from the day it landed, so `pages.sh` had never
# once parsed on a stock macOS — the Pages palette command and the page pill's
# click both did nothing at all, with the error going wherever pounce sends a
# command's stderr. Found 2026-08-19 by running the shipped file under
# `/bin/bash -n`, which is worth doing to any script here that a comment lands
# inside a command substitution in.
rows="$(
  printf '%s\n' "$pages" | while IFS= read -r ws; do
    [ -n "$ws" ] || continue
    desc="$(printf '%s\n' "$summaries" | awk -F'\t' -v w="$ws" '$1 == w { print $2; exit }')"
    [ -n "$desc" ] || desc="empty"
    [ "$ws" = "$current" ] && desc="$desc  ·  you are here"
    # T is not a repo, so it is not dressed as one.
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
  move:enter | go:opt) act=move ;;
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

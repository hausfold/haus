#!/bin/bash
# workspace-mru.sh — the one place workspace recency lives.
#
# Two verbs, one file (~/.local/state/haus/workspace-mru — most recent first,
# one workspace per line):
#
#   push             exec-on-workspace-change hook. AeroSpace hands the new
#                    workspace in $AEROSPACE_FOCUSED_WORKSPACE; prepend it,
#                    dedupe, cap. This is a PUSH, not a poll — the file is
#                    exact because AeroSpace tells us about every change,
#                    including ones no chord made (mouse, app activation).
#
#   resolve <base>   print the most recently used NON-EMPTY workspace that is
#                    <base> itself or a <base>/* page, falling back to <base>.
#                    This is what makes `caps t` mean "back to whichever lane
#                    page I was last on" now that lanes tile per-repo on
#                    T/<repo> (lane-open.sh) instead of one shared T: the
#                    letter chord still names T, and the resolver picks the
#                    page. Emptiness is asked of AeroSpace, not the file — a
#                    lane page whose windows all closed evaporates, and a
#                    stale MRU line must not resurrect it.
#
# pounce's ⌃⇥ page walk reads the SAME file (its `pages.mruFile` setting, wired
# by modules/launcher), so the chord walk and the letter chord agree about what
# "recent" means. Writers: this script only.
#
# `push` keeps a second, one-byte file beside it — `any-page`, `1` or `0` for
# "is there a page anywhere on this Mac". That is not recency and has no reader
# in this room: it is the palette's, whose `Pages` row declares
# `whenFile = ~/.local/state/haus/any-page` and is hidden while it says `0`
# (launcher/commands/pages.sh). It is written HERE because a summon may not fork
# — pounce reads this on the ⌘Space keystroke — and this hook is the only thing
# that already runs on every workspace change without the bar having to be on.
# The bar's `page` pill asks a narrower question (how many pages does the
# workspace you are on have) from its own `aerospace` call on the same event;
# these two are deliberately not shared, since one is a label and the other is a
# file a different process stats.
set -u

export PATH="/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

state_dir="$HOME/.local/state/haus"
mru="$state_dir/workspace-mru"

case "${1:-}" in
  push)
    ws="${AEROSPACE_FOCUSED_WORKSPACE:-${2:-}}"
    [ -n "$ws" ] || exit 0
    mkdir -p "$state_dir" || exit 0
    tmp="$mru.$$"
    {
      printf '%s\n' "$ws"
      [ -f "$mru" ] && grep -Fxv -- "$ws" "$mru"
    } 2>/dev/null | head -50 >"$tmp" && mv -f "$tmp" "$mru"

    # A page is any workspace with a `/` in it, and `--monitor all` lists the
    # persistent workspaces plus every non-persistent one currently holding a
    # window or visible — a page is never persistent (lane-open.sh keeps
    # `T/<repo>` out on purpose), so every `…/…` line in that output is a LIVE
    # page. Same call and same rule as the bar's page pill.
    #
    # Written only when AeroSpace actually answered: a tiler that is not running
    # exits non-zero, and an empty answer is not "no pages", it is "no answer".
    # Both leave the previous verdict in place, and a Mac that has never had one
    # has no file, which the palette reads as a yes. The row can then be listed
    # when it has nothing to show, which is the harmless direction; the other one
    # takes a working row away and says nothing.
    if live="$(aerospace list-workspaces --monitor all 2>/dev/null)" && [ -n "$live" ]; then
      if printf '%s\n' "$live" | grep -q /; then any=1; else any=0; fi
      tmp="$state_dir/any-page.$$"
      printf '%s\n' "$any" >"$tmp" && mv -f "$tmp" "$state_dir/any-page"
    fi
    ;;
  resolve)
    base="${2:-T}"
    if [ -f "$mru" ]; then
      # Emptiness from AeroSpace, order from the file. The awk builds a set of
      # the live non-empty workspaces, then the first MRU line in the set that
      # matches <base> or <base>/… wins.
      hit="$(
        aerospace list-workspaces --monitor all --empty no 2>/dev/null |
          awk -v base="$base" -v mru="$mru" '
            { live[$0] = 1 }
            END {
              while ((getline line < mru) > 0)
                if ((line == base || index(line, base "/") == 1) && line in live) {
                  print line; exit
                }
            }
          '
      )"
      [ -n "$hit" ] && { printf '%s\n' "$hit"; exit 0; }
    fi
    printf '%s\n' "$base"
    ;;
  *)
    echo "usage: workspace-mru.sh push | resolve <base>" >&2
    exit 2
    ;;
esac

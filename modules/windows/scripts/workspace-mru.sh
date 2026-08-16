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

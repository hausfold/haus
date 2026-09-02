#!/bin/bash
# vitals_lib.sh — everything the cpu and memory pills share: one sample, one
# ladder, and the two things a dropdown row can DO. Sourced, never executed.
#
# The two pills are the same pill twice — a number, a graph of that number and
# a dropdown of what's responsible — so the only things their own files hold are
# the words: which glyph, which unit, which rows. This is the rest.
#
# Both are framework widgets now (ops/todo/bar-framework.md), which is why this
# file is short: the row builders, the pixel alignment, the popup dance and
# the tone→hex ladder that used to live here are barlib's, written once for
# every pill on the bar rather than twice for these two.
#
# Every reading comes from `barvitals`, which does the Mach calls and the
# delta arithmetic (see modules/bar/barvitals.swift for why neither pill can
# get an honest number out of `ps` or `memory_pressure`). One run per tick
# serves the label, the graph point AND every row of the dropdown, so no two
# parts of a pill can ever be describing different moments.

# ── the sample ────────────────────────────────────────────────────────────────
# Sets the globals below from one `barvitals` run. Anything the sampler
# couldn't read stays EMPTY rather than becoming 0 — a bar that draws 0% is
# claiming an idle machine, which is the one wrong answer nobody double-checks.
#
#   CPU_TOTAL CPU_USER CPU_SYS LOAD NCPU
#   MEM_PCT MEM_USED MEM_TOTAL MEM_SWAP MEM_PRESSURE MEM_CACHED MEM_COMPRESSED
#   TOP_VALUE[] TOP_PID[] TOP_NAME[]   — biggest first, at most --rows of them
#   REST                               — what the rows above don't cover
#
# $VITALS_BIN is resolved by absolute store-independent path for the same reason
# barpop is: this runs from launchd's PATH, where nothing nix-shaped is on it.
# Overridable only so a throwaway bar instance can point at a freshly compiled
# one — every real caller takes the default, since a pill that read its sampler
# from the environment could be pointed anywhere by anything.
VITALS_BIN="${VITALS_BIN:-/run/current-system/sw/bin/barvitals}"

CPU_TOTAL=""; CPU_USER=""; CPU_SYS=""; LOAD=""; NCPU=""
MEM_PCT=""; MEM_USED=""; MEM_TOTAL=""; MEM_SWAP=""; MEM_PRESSURE=""
MEM_CACHED=""; MEM_COMPRESSED=""
REST=""
TOP_VALUE=(); TOP_PID=(); TOP_NAME=()

vitals_sample() { # vitals_sample <state-path> <cpu|mem|none> [rows]
  local kind a b c d e f g
  TOP_VALUE=(); TOP_PID=(); TOP_NAME=()
  [ -x "$VITALS_BIN" ] || return 1
  # Process substitution rather than a pipe: a `while read` on the right of a
  # pipe runs in a SUBSHELL, and every global above would be set in a process
  # that exits one line later. (bash 3.2 is what macOS ships and what sketchybar
  # runs these with — no `lastpipe` to rescue it.)
  while IFS=$'\t' read -r kind a b c d e f g; do
    case "$kind" in
    cpu) CPU_TOTAL="$a"; CPU_USER="$b"; CPU_SYS="$c"; LOAD="$d"; NCPU="$e" ;;
    mem)
      MEM_PCT="$a"; MEM_USED="$b"; MEM_TOTAL="$c"; MEM_SWAP="$d"
      MEM_PRESSURE="$e"; MEM_CACHED="$f"; MEM_COMPRESSED="$g"
      ;;
    top)
      TOP_VALUE+=("$a"); TOP_PID+=("$b"); TOP_NAME+=("$c")
      ;;
    rest) REST="$a" ;;
    esac
  done < <("$VITALS_BIN" sample --state "$1" --top "$2" --rows "${3:-5}" 2>/dev/null)
}

# ── the ladder ────────────────────────────────────────────────────────────────
# The same four steps the AI-usage pill climbs, so a percentage means the same
# thing wherever it appears on this bar — said in TONE NAMES, because a
# framework widget names a tone and never a palette entry (see
# ops/todo/bar-framework.md). It is the only spelling now: `vitals_color` was the
# hex half, kept alive only while one pill was converted and the other was not.
#
# The mapping onto the tone ladder is one-to-one because that ladder was
# widened to fit this one — bad/warn/watch/ok are the old RED/PEACH/YELLOW/
# GREEN, and `watch` exists precisely because 50% CPU is worth knowing and is
# not "wants a human here".
#
# Takes a decimal ("41.2"): the readouts are fractional and `[ 41.2 -ge 50 ]`
# is a syntax error rather than a comparison, so the point is cut off here
# rather than at every call site.
#
# The memory pill deliberately does NOT climb it — its colour is the kernel's
# pressure level, for the reason written above `pressure_verdict` in memory.sh.
vitals_tone() { # vitals_tone <percent>
  local whole="${1%%.*}"
  [ -n "$whole" ] || whole=0
  if   [ "$whole" -ge 90 ] 2>/dev/null; then printf '%s' bad
  elif [ "$whole" -ge 75 ] 2>/dev/null; then printf '%s' warn
  elif [ "$whole" -ge 50 ] 2>/dev/null; then printf '%s' watch
  else                                       printf '%s' ok
  fi
}

# ── the two actions a row can take ────────────────────────────────────────────

vitals_activity_monitor() { # vitals_activity_monitor <tab>
  # 0 = CPU, 1 = Memory. Activity Monitor reads SelectedTab when it LAUNCHES, so
  # this lands the right tab on a cold open and leaves an already-running one
  # wherever the user had it — deliberately: yanking the tab out from under a
  # window someone is reading is worse than opening on the one they last chose.
  defaults write com.apple.ActivityMonitor SelectedTab -int "$1" 2>/dev/null
  # pounce's own built-in, not a second `open -a`: the haus menu already offers
  # this row and one of the two would have gone stale.
  if command -v pounce-activity >/dev/null 2>&1; then
    pounce-activity
  else
    open -a "Activity Monitor"
  fi
}

vitals_focus() { # vitals_focus <name> — bring the app a row names to the front
  # Windows are aerospace's business (the agents pill focuses panes the same
  # way), and the app NAME is what both ends of this agree on: barvitals names
  # a process after its .app bundle precisely so this lookup can be a string
  # match rather than a pid-to-window guess.
  #
  # No window, no action. A row for a background process is not a broken button
  # — `open -a` on it would either launch a second copy or bounce a Dock icon
  # for something that has no UI at all. Same for a desktop running bar WITHOUT
  # windows: no aerospace, so no window lookup, so the row is inert rather than
  # noisy — `haus.bar.enable` doesn't imply `haus.windows.enable`.
  local wid
  command -v aerospace >/dev/null 2>&1 || return 0
  wid=$(aerospace list-windows --all --format '%{window-id}|%{app-name}' 2>/dev/null |
    awk -F'|' -v want="$1" 'tolower($2) == tolower(want) { print $1; exit }')
  [ -n "$wid" ] && aerospace focus --window-id "$wid" 2>/dev/null
}

# ── why there is no hover here ────────────────────────────────────────────────
# These pills used to swap in a long breakdown label while the pointer sat on
# them. A wider label is a WIDER PILL, and sketchybar re-lays-out the whole
# group to fit it: every pill to the left of it jumped sideways the moment the
# pointer grazed this one, and again when it left. Two pills doing that, on a
# bar you cross to reach anything else, read as the bar twitching rather than
# as a readout answering a question — so the breakdown lives only in the
# left-click dropdown now, which opens BELOW the bar and moves nothing.

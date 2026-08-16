#!/bin/bash
# vitals_lib.sh — everything the cpu and memory pills share: one sample, one
# colour ladder, one set of dropdown row builders. Sourced, never executed.
#
# The two pills are the same pill twice — a number, a graph of that number and
# a dropdown of what's responsible — so the only things their own files hold are
# the words: which glyph, which unit, which rows. This is the rest.
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
# thing wherever it appears on this bar. Takes a decimal ("41.2"): the readouts
# are fractional and `[ 41.2 -ge 50 ]` is a syntax error, not a comparison, so
# the point is cut off here rather than at every call site.
vitals_color() { # vitals_color <percent>
  local whole="${1%%.*}"
  [ -n "$whole" ] || whole=0
  if   [ "$whole" -ge 90 ] 2>/dev/null; then printf '%s' "$RED"
  elif [ "$whole" -ge 75 ] 2>/dev/null; then printf '%s' "$PEACH"
  elif [ "$whole" -ge 50 ] 2>/dev/null; then printf '%s' "$YELLOW"
  else                                       printf '%s' "$GREEN"
  fi
}

# A percentage as the graph wants it: 0…1, two decimals, clamped. sketchybar
# draws a pushed value against the item's height with no scaling of its own, so
# anything over 1 is simply drawn off the top of the pill and anything negative
# vanishes — neither of which looks like an error, which is why both are handled
# here instead of trusted upstream.
vitals_fraction() { # vitals_fraction <percent>
  awk -v p="${1:-0}" 'BEGIN {
    v = p / 100
    if (v < 0) v = 0
    if (v > 1) v = 1
    printf "%.2f", v
  }'
}

# ── dropdown rows ─────────────────────────────────────────────────────────────
# Same three weights of type the AI-usage dropdown uses — header / value /
# footnote — and the same reason: a row carries its meaning in size and hue, not
# in where it sits. The descriptor lives in the item's ICON and the number in
# its LABEL, because one item draws one colour and these rows need two: a dim
# name against a value on the ladder.
#
# Alignment is a PIXEL padding derived from the monospace advance, never
# trailing spaces — sketchybar sizes an item from its trimmed label and then
# draws the untrimmed string, so a space-padded row is a row clipped by exactly
# the width of its own padding. (Learned in ai_usage.sh; the trap is identical
# here and so is the workaround.)
VITALS_ROW_INDENT=22
VITALS_NAME_COLS=16   # widest name column before a value starts sliding right
VITALS_NAME_GAP=12
VITALS_H_HEADER=32
VITALS_H_ROW=25
VITALS_H_META=20

vitals_metrics() { # measure the font once per run, not once per row
  # Two advances, because the header draws one size up: pad a FS_LABEL row with
  # FS_SMALL columns and the header's number lands short of the column every row
  # below it uses, which is the one misalignment in a dropdown you actually see.
  VITALS_ADV=$(awk -v s="${FS_SMALL:-13}" 'BEGIN { printf "%.0f", s * 602 }')
  VITALS_ADV_LABEL=$(awk -v s="${FS_LABEL:-15}" 'BEGIN { printf "%.0f", s * 602 }')
}

vitals_px() { printf '%s' $((($1 + 500) / 1000)); }

vitals_name_pad() { # vitals_name_pad <name> [columns already spent] [advance] — icon
  # padding that lands every value on one column, whatever the app happens to be
  # called. A name longer than the column gets the minimum gap and pushes its own
  # value right; that is one ragged row rather than a dropdown sized for the
  # worst name on the machine.
  #
  # The second argument is for a descriptor carrying something bash can't
  # measure — the header's glyph, which `${#s}` counts as three bytes in the C
  # locale a bar plugin inherits and as one character anywhere else. Two columns,
  # named by the caller, beats a length that changes with $LANG.
  local cols=$((VITALS_NAME_COLS - ${#1} - ${2:-0}))
  [ "$cols" -lt 1 ] && cols=1
  vitals_px $((cols * ${3:-$VITALS_ADV} + VITALS_NAME_GAP * 1000))
}

# All builders append to ARGS and bump $i — nothing here talks to sketchybar, so
# a whole dropdown is still one message. Every row closes the popup when clicked
# unless the caller overrides click_script, because a row that does nothing
# should at least do the obvious thing.
vitals_pop_add() { # vitals_pop_add <property=value…>
  ARGS+=(--add item "${ITEM_NAME}.popup.$i" "popup.${ITEM_NAME}"
    --set "${ITEM_NAME}.popup.$i"
      icon="" icon.padding_left=0 icon.padding_right=0
      label="" label.padding_left=0 label.padding_right=14
      background.drawing=off background.height="$VITALS_H_ROW"
      click_script="$SB --set ${ITEM_NAME} popup.drawing=off"
    "$@")
  i=$((i + 1))
}

vitals_header() { # vitals_header <icon> <title> <value> <color>
  # Glyph and title travel together in the ICON, both in the pill's own hue —
  # they are the same mark, and splitting them across the row's two colourable
  # halves would spend the value's colour on a word. The value then lands on the
  # same column every row below it uses, so the header reads as the total of
  # what follows rather than as a caption sitting above it.
  vitals_pop_add icon="$1 $2" icon.color="$4" \
    icon.font="${BAR_FONT}:Bold:${FS_LABEL}" \
    icon.padding_left=10 icon.padding_right="$(vitals_name_pad "$2" 2 "$VITALS_ADV_LABEL")" \
    label="$3" label.color="$TEXT" \
    label.font="${BAR_FONT}:Bold:${FS_LABEL}" \
    background.height="$VITALS_H_HEADER"
}

vitals_row() { # vitals_row <name> <value> <color> [click_script]
  local extra=()
  [ -n "${4:-}" ] && extra=(click_script="$4")
  vitals_pop_add icon="$1" icon.color="$OVERLAY1" \
    icon.font="${BAR_FONT}:Regular:${FS_SMALL}" \
    icon.padding_left="$VITALS_ROW_INDENT" icon.padding_right="$(vitals_name_pad "$1")" \
    label="$2" label.color="$3" label.font="${BAR_FONT}:Bold:${FS_SMALL}" \
    ${extra[@]+"${extra[@]}"}
}

vitals_meta() { # vitals_meta <text> — a footnote: smallest, dimmest, shortest.
  vitals_pop_add label="$1" label.color="$OVERLAY0" \
    label.font="${BAR_FONT}:Italic:${FS_TINY}" \
    label.padding_left="$VITALS_ROW_INDENT" background.height="$VITALS_H_META"
}

vitals_action() { # vitals_action <icon> <text> <click_script> — the one row in a
  # dropdown that is a button. Accented rather than dimmed, because it is the
  # only thing here you can press, and a footer that looks like a footnote is a
  # footer nobody presses.
  vitals_pop_add icon="$1" icon.color="$BLUE" \
    icon.font="${BAR_FONT}:Bold:${FS_SMALL}" \
    icon.padding_left="$VITALS_ROW_INDENT" icon.padding_right=8 \
    label="$2" label.color="$BLUE" label.font="${BAR_FONT}:Bold:${FS_SMALL}" \
    click_script="$SB --set ${ITEM_NAME} popup.drawing=off; $3"
}

# ── opening the dropdown ──────────────────────────────────────────────────────
# The rows are already in ARGS; this sends them, reveals, and hands the popup to
# barpop so a click ANYWHERE closes it (sketchybar alone only hears clicks on
# its own items). Not `toggle`: the closed case exited long before we got here,
# and toggling a popup whose rows were just rebuilt is the double-open flash.
vitals_popup_show() {
  [ ${#ARGS[@]} -gt 0 ] && "$SB" "${ARGS[@]}" 2>/dev/null
  "$SB" --set "$ITEM_NAME" popup.drawing=on
  SKETCHYBAR_BIN="$SB" /run/current-system/sw/bin/barpop arm "$ITEM_NAME" 2>/dev/null &
}

vitals_popup_open() { # is the dropdown up right now?
  [ "$("$SB" --query "$ITEM_NAME" 2>/dev/null | jq -r '.popup.drawing')" = "on" ]
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

# The item a row belongs to. SketchyBar sets $NAME to the item that was
# CLICKED, and a popup row is its own item — `cpu.popup.7` — so a plugin
# re-entered from a row and reading $NAME straight would address the row rather
# than the pill. `--set cpu.popup.7 popup.drawing=off` is not an error: rows have
# a popup property like every item, so the call succeeds, does nothing, and
# leaves the dropdown floating over the window the row just raised.
vitals_pill_of() { printf '%s' "${1%%.popup.*}"; }

vitals_focus() { # vitals_focus <name> — bring the app a row names to the front
  # Windows are aerospace's business (the agents pill focuses panes the same
  # way), and the app NAME is what both ends of this agree on: barvitals names
  # a process after its .app bundle precisely so this lookup can be a string
  # match rather than a pid-to-window guess.
  #
  # No window, no action. A row for a background process is not a broken button
  # — `open -a` on it would either launch a second copy or bounce a Dock icon
  # for something that has no UI at all. Same for a rice running bar WITHOUT
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

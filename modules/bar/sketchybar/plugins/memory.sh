#!/bin/bash
# memory.sh — the memory pill: how much RAM is actually spoken for, a rolling
# graph of it, and a dropdown breaking it down and naming the biggest
# footprints.
#
# The reading comes from `barvitals` (modules/bar/barvitals.swift). What it
# replaces is `memory_pressure`'s "System-wide memory free percentage", which
# counts the FILE CACHE as used — and macOS fills idle RAM with cache on
# purpose, so that number sat near 90% on a machine doing nothing and had no
# dynamic range left to show anything with. This one adds up what Activity
# Monitor calls Memory Used: app memory + wired + compressed.
#
# Three entry paths:
#   • periodic (update_freq)          → repaint label + colour, push a graph point
#   • mouse.clicked                   → LEFT the dropdown, RIGHT Activity Monitor
#   • `memory.sh row <pid> <name>`    → a dropdown row: focus that app
#
# Deliberately NOT a fourth: the pointer — see cpu.sh and vitals_lib.sh.
set -u
export USER="${USER:-$(id -un)}"
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:/usr/bin:/bin:$PATH"

source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/sizes.sh"
# $SB — which bar this pill lives on; see cpu.sh, and bar.sh for the routing.
BAR_ITEM=memory
source "$HOME/.config/sketchybar/bar.sh"
source "$HOME/.config/sketchybar/plugins/vitals_lib.sh"

# $NAME is the CLICKED item, which on the row path is a popup child rather than
# the pill — see vitals_pill_of, and cpu.sh's note beside the same line.
ITEM_NAME="$(vitals_pill_of "${NAME:-memory}")"
SELF="$HOME/.config/sketchybar/plugins/memory.sh"
STATE="${TMPDIR:-/tmp}/bar-vitals-memory"

# Nerd Font memory icon (nf-md-memory, U+F049D). Literal glyph, not printf
# '\UXXXXXXXX' — macOS ships bash 3.2, whose printf has no \u/\U escapes and
# emits the escape text verbatim into the bar.
ICON="󰒝"

case "${1:-}" in
row)
  vitals_focus "${3:-}"
  "$SB" --set "$ITEM_NAME" popup.drawing=off
  exit 0
  ;;
activity)
  vitals_activity_monitor 1
  exit 0
  ;;
esac

WANT_POPUP=0
if [ "${SENDER:-}" = "mouse.clicked" ]; then
  case "${BUTTON:-left}" in
  right)
    vitals_activity_monitor 1
    exit 0
    ;;
  *)
    if vitals_popup_open; then
      "$SB" --set "$ITEM_NAME" popup.drawing=off
      exit 0
    fi
    WANT_POPUP=1
    ;;
  esac
fi

# Footprints are a quantity, not a rate, so unlike the CPU pill this one needs
# no baseline and can ask for rows only when it is about to draw them.
if [ "$WANT_POPUP" = 1 ]; then
  vitals_sample "$STATE" mem 5
else
  vitals_sample "$STATE" none
fi
[ -n "$MEM_PCT" ] || exit 0

PCT=$(printf '%.0f' "$MEM_PCT")

# ── colour: the kernel's verdict, not the percentage ──────────────────────────
# A memory pill that climbs the usual ladder is amber all day, because 60% of
# RAM in use is a Mac working correctly — the number is high by design and says
# nothing about whether you're in trouble. kern.memorystatus_vm_pressure_level
# does: 1 normal, 2 warning, 4 critical, and it is what decides whether the
# machine starts swapping. So the pill goes amber when the KERNEL is worried,
# and the percentage stays a number you read rather than a colour you react to.
case "${MEM_PRESSURE:-1}" in
4) COL="$RED";   PRESSURE_WORD="critical" ;;
2) COL="$PEACH"; PRESSURE_WORD="warning" ;;
*) COL="$GREEN"; PRESSURE_WORD="normal" ;;
esac

if [ "$WANT_POPUP" = 1 ]; then
  vitals_metrics
  "$SB" --remove "/${ITEM_NAME}\.popup\..*/" 2>/dev/null
  ARGS=()
  i=0

  vitals_header "$ICON" "Memory" "${MEM_USED} / ${MEM_TOTAL} GB" "$GREEN"
  vitals_row "used" "${MEM_USED} GB" "$TEXT"
  # Cache is drawn because it is the half of the old pill's lie worth keeping:
  # seeing 12 GB of file cache is what makes "54% used" legible on a 32 GB
  # machine that looks, in every other tool, like it is nearly full.
  vitals_row "cached" "${MEM_CACHED} GB" "$OVERLAY1"
  vitals_row "compressed" "${MEM_COMPRESSED} GB" "$TEXT"
  # Swap in use is the one row here that is always worth a colour: it is the
  # symptom the pressure level is there to predict, arriving.
  SWAP_COL="$TEXT"
  [ "${MEM_SWAP%%.*}" -gt 0 ] 2>/dev/null && SWAP_COL="$PEACH"
  vitals_row "swap" "${MEM_SWAP} GB" "$SWAP_COL"
  vitals_row "pressure" "$PRESSURE_WORD" "$COL"

  if [ ${#TOP_NAME[@]} -gt 0 ]; then
    vitals_meta "biggest footprints"
    n=0
    while [ "$n" -lt ${#TOP_NAME[@]} ]; do
      name="${TOP_NAME[$n]}"
      safe=$(printf '%q' "$name")   # see cpu.sh — the row is a shell string
      vitals_row "$name" "${TOP_VALUE[$n]} GB" "$TEXT" "$SELF row ${TOP_PID[$n]} $safe"
      n=$((n + 1))
    done
    # Same honesty as the CPU dropdown: these are processes we own, so anything
    # root runs — and every app too small for the list — is in here rather than
    # quietly missing from the sum.
    [ -n "$REST" ] && vitals_row "everything else" "${REST} GB" "$OVERLAY1"
  fi

  vitals_action "" "Activity Monitor" "$SELF activity"
  vitals_popup_show
  exit 0
fi

# One label, always the number — used/total and swap are dropdown rows. See
# cpu.sh: a label that grew under the pointer moved every pill beside it.
LABEL="${PCT}%"

# Only ticks reach here — every click path exits above — so the push needs no
# guard; see the same note in cpu.sh for what it used to be guarding against.
"$SB" --push "$ITEM_NAME" "$(vitals_fraction "$MEM_PCT")" \
  --set "$ITEM_NAME" icon="$ICON" label="$LABEL" label.color="$COL"

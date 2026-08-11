#!/bin/bash
# cpu.sh — the CPU pill: a number, a rolling graph of that number, a hover
# breakdown, and a dropdown naming what is responsible.
#
# The reading comes from `sillvitals` (modules/sill/sillvitals.swift), because
# the `ps -A -o %cpu` sum this used to print is a LIFETIME average per process:
# on a machine that has been up a week it barely moves while every core is
# pinned. The graph is the reason that mattered enough to fix — a meter that
# doesn't move is a static label with extra steps.
#
# Four entry paths:
#   • periodic (update_freq)          → repaint label + colour, push a graph point
#   • mouse.entered / exited          → swap the label for the breakdown, and back
#   • mouse.clicked                   → LEFT the dropdown, RIGHT Activity Monitor
#   • `cpu.sh row <pid> <name>`       → a dropdown row: focus that app
set -u
export USER="${USER:-$(id -un)}"
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:/usr/bin:/bin:$PATH"

source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/sizes.sh"
# $SB — which bar this pill lives on. It can be either one: the readouts are
# movable via haus.sill.bottom.items, and a bare `sketchybar` here would keep
# updating a top-bar item that no longer exists. SILL_ITEM is the fallback for
# the row-click path, which arrives with no $BAR_NAME of its own.
SILL_ITEM=cpu
source "$HOME/.config/sketchybar/bar.sh"
source "$HOME/.config/sketchybar/plugins/vitals_lib.sh"

ITEM_NAME="${NAME:-cpu}"
SELF="$HOME/.config/sketchybar/plugins/cpu.sh"
# Per-pill state, so this pill's percentages are always "since MY last look" —
# see sillvitals.swift on why the two pills can't share one baseline.
STATE="/tmp/sill-vitals-cpu-${USER}"

# Nerd Font CPU icon (nf-oct-cpu, U+F4BC). Literal glyph, not printf '\uXXXX' —
# macOS ships bash 3.2, whose printf has no \u/\U escapes and emits the escape
# text verbatim into the bar.
ICON=""

# ── a dropdown row was clicked ────────────────────────────────────────────────
case "${1:-}" in
row)
  vitals_focus "${3:-}"
  "$SB" --set "$ITEM_NAME" popup.drawing=off
  exit 0
  ;;
activity)
  vitals_activity_monitor 0
  exit 0
  ;;
esac

# ── hover ─────────────────────────────────────────────────────────────────────
# Entering falls through to the repaint below (the label has to CHANGE, and
# looking at the pill is also the cheapest cache-invalidation there is);
# leaving repaints and stops. mouse.exited.global is the belt-and-braces twin:
# the per-item exit is missed when the pointer is flicked straight off the bar,
# and a pill stranded in its long form pushes every pill beside it sideways.
case "${SENDER:-}" in
mouse.entered) vitals_hover_set ;;
mouse.exited | mouse.exited.global) vitals_hover_clear ;;
esac

# ── the click ─────────────────────────────────────────────────────────────────
WANT_POPUP=0
if [ "${SENDER:-}" = "mouse.clicked" ]; then
  case "${BUTTON:-left}" in
  right)
    # The native view, on the tab this pill is about. Right-click rather than a
    # modifier because the dropdown is the answer nine times in ten and this is
    # where you go when it isn't.
    vitals_activity_monitor 0
    exit 0
    ;;
  *)
    # Closing is just hiding: rebuilding a dozen rows first would re-lay-out a
    # popup the user can see. The rows are rebuilt on the way back IN, where
    # nothing shows.
    if vitals_popup_open; then
      "$SB" --set "$ITEM_NAME" popup.drawing=off
      exit 0
    fi
    WANT_POPUP=1
    ;;
  esac
fi

# ── the sample ────────────────────────────────────────────────────────────────
# One run serves the label, the graph point and every row of the dropdown, so
# the pill and the dropdown explaining it are always the same moment. Rows are
# only asked for when they'll be drawn — walking every process costs ~25 ms and
# the periodic tick has nothing to do with them.
if [ "$WANT_POPUP" = 1 ]; then
  vitals_sample "$STATE" cpu 5
else
  vitals_sample "$STATE" cpu 0
fi

# No `cpu` record means no previous sample to subtract — the first tick after a
# reload, and nothing else. Keep whatever the pill already says rather than
# drawing a confident 0%.
if [ -z "$CPU_TOTAL" ]; then
  [ "$WANT_POPUP" = 1 ] || exit 0
  CPU_TOTAL=0
fi

PCT=$(printf '%.0f' "$CPU_TOTAL")
COL=$(vitals_color "$CPU_TOTAL")

# ── the dropdown ──────────────────────────────────────────────────────────────
if [ "$WANT_POPUP" = 1 ]; then
  vitals_metrics
  "$SB" --remove "/${ITEM_NAME}\.popup\..*/" 2>/dev/null
  ARGS=()
  i=0

  vitals_header "$ICON" "CPU" "${PCT}%" "$PEACH"
  vitals_row "user" "${CPU_USER}%" "$TEXT"
  vitals_row "system" "${CPU_SYS}%" "$TEXT"
  # Load average is the queue, not the usage: 100% with a load of 2 is a machine
  # working, 100% with a load of 30 is a machine drowning. Cores are printed
  # beside it because the number means nothing without them.
  vitals_row "load" "${LOAD} · ${NCPU} cores" "$TEXT"

  if [ ${#TOP_NAME[@]} -gt 0 ]; then
    vitals_meta "what's using it"
    n=0
    while [ "$n" -lt ${#TOP_NAME[@]} ]; do
      name="${TOP_NAME[$n]}"
      # Rows are clickable and each one goes to its app's window. Single quotes
      # around the name (any of its own stripped first) because a click_script is
      # a shell string and half this machine's apps have a space in their name.
      safe="${name//\'/}"
      vitals_row "$name" "${TOP_VALUE[$n]}%" "$(vitals_color "${TOP_VALUE[$n]}")" \
        "$SELF row ${TOP_PID[$n]} '$safe'"
      n=$((n + 1))
    done
    # The remainder is drawn, never hidden: sillvitals can only read processes we
    # OWN, so a busy WindowServer or kernel_task lands here — and a big
    # "everything else" is the dropdown saying, correctly, that the answer is in
    # Activity Monitor rather than in this list.
    [ -n "$REST" ] && vitals_row "everything else" "${REST}%" "$OVERLAY1"
  fi

  vitals_action "" "Activity Monitor" "$SELF activity"
  vitals_popup_show
  exit 0
fi

# ── the pill ──────────────────────────────────────────────────────────────────
# Hover swaps in the split behind the number: user vs system is the difference
# between "my build is running" and "the machine is thrashing", and load says
# whether anything is queued behind it.
if vitals_hovering; then
  LABEL="${PCT}% · usr ${CPU_USER} sys ${CPU_SYS} · load ${LOAD}"
else
  LABEL="${PCT}%"
fi

# The graph carries the shape and the label carries the state, which is why the
# graph's colour is set once in the item definition and never here: a line that
# changed hue every two seconds would be the busiest thing on the bar.
"$SB" --push "$ITEM_NAME" "$(vitals_fraction "$CPU_TOTAL")" \
  --set "$ITEM_NAME" icon="$ICON" label="$LABEL" label.color="$COL"

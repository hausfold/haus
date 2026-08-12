#!/bin/bash
# cpu.sh — the CPU pill: a number, a rolling graph of that number, and a
# dropdown splitting it up and naming what is responsible.
#
# The reading comes from `sillvitals` (modules/sill/sillvitals.swift), because
# the `ps -A -o %cpu` sum this used to print is a LIFETIME average per process:
# on a machine that has been up a week it barely moves while every core is
# pinned. The graph is the reason that mattered enough to fix — a meter that
# doesn't move is a static label with extra steps.
#
# Three entry paths:
#   • periodic (update_freq)          → repaint label + colour, push a graph point
#   • mouse.clicked                   → LEFT the dropdown, RIGHT Activity Monitor
#   • `cpu.sh row <pid> <name>`       → a dropdown row: focus that app
#
# Deliberately NOT a fourth: the pointer. The breakdown is dropdown-only — see
# vitals_lib.sh on why a hover that widened the pill had to go.
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

# $NAME is the item that was CLICKED, which on the row path is a popup child
# (`cpu.popup.7`) rather than the pill — hence vitals_pill_of. See its comment
# for what addressing the row instead quietly fails to do.
ITEM_NAME="$(vitals_pill_of "${NAME:-cpu}")"
SELF="$HOME/.config/sketchybar/plugins/cpu.sh"
# Per-pill state, so this pill's percentages are always "since MY last look" —
# see sillvitals.swift on why the two pills can't share one baseline. In the
# session's own $TMPDIR (0700) rather than world-writable /tmp: a predictable
# name in a shared directory is a symlink away from writing somewhere else.
STATE="${TMPDIR:-/tmp}/sill-vitals-cpu"

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
# the pill and the dropdown explaining it are always the same moment.
#
# `cpu` mode on BOTH paths, and only the row count changes: a per-process delta
# needs a per-process baseline, so the periodic tick has to keep recording one
# even though it draws no rows. That is the tick's real cost — walking every
# process and rewriting the state file, ~25 ms of the 2-second budget — and it
# buys a dropdown that opens with numbers already in it.
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
  # Guarded on the split rather than drawn blank: the first click after a bar
  # reload has no previous sample behind it, and `user  %` / `load  · cores` is
  # a row claiming to know something it doesn't. One tick later they're all here.
  if [ -n "$CPU_USER" ]; then
    vitals_row "user" "${CPU_USER}%" "$TEXT"
    vitals_row "system" "${CPU_SYS}%" "$TEXT"
    # Load average is the queue, not the usage: 100% with a load of 2 is a
    # machine working, 100% with a load of 30 is a machine drowning. Cores are
    # printed beside it because the number means nothing without them.
    vitals_row "load" "${LOAD} · ${NCPU} cores" "$TEXT"
  else
    vitals_meta "measuring — the bar reloaded a moment ago"
  fi

  if [ ${#TOP_NAME[@]} -gt 0 ]; then
    vitals_meta "what's using it"
    n=0
    while [ "$n" -lt ${#TOP_NAME[@]} ]; do
      name="${TOP_NAME[$n]}"
      # Rows are clickable and each one goes to its app's window. `printf %q`
      # rather than hand-rolled quotes (the same thing calendar.sh does with its
      # join links): a click_script is a shell string the bar evaluates, half
      # this machine's apps have a space in their name, and an app with an
      # apostrophe must reach aerospace with the apostrophe still in it — a name
      # we edited to make quoting easy is a name that matches no window.
      safe=$(printf '%q' "$name")
      vitals_row "$name" "${TOP_VALUE[$n]}%" "$(vitals_color "${TOP_VALUE[$n]}")" \
        "$SELF row ${TOP_PID[$n]} $safe"
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
# One label, always the same width class: the number. user/system and the load
# average are in the dropdown, where widening something costs nobody a jump.
LABEL="${PCT}%"

# The graph carries the shape and the label carries the state, which is why the
# graph's colour is set once in the item definition and never here: a line that
# changed hue every two seconds would be the busiest thing on the bar.
#
# Every run that reaches here is a tick (a click has exited above, one way or
# another), so the push is unconditional. It used to be guarded against
# mouse-driven runs: the graph has no time axis of its own — it is the last 48
# values, evenly spaced — so a point pushed by the pointer crossing the pill
# would have shoved two minutes of history sideways at the speed of a mouse.
"$SB" --push "$ITEM_NAME" "$(vitals_fraction "$CPU_TOTAL")" \
  --set "$ITEM_NAME" icon="$ICON" label="$LABEL" label.color="$COL"

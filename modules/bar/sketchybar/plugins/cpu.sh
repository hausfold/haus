#!/bin/bash
# widget: interval = 2
# widget: graph = 48
# widget: popup = true
# widget: mark = warm
#
# cpu.sh — the CPU pill: a number, a rolling graph of that number, and a
# dropdown splitting it up and naming what is responsible. A framework widget
# (hausfold.co/docs/haus/rooms/bar-widgets): the header above is the whole of
# its wiring, and barlib owns the bar instance, the batching, the tones and the
# dropdown.
#
# The reading comes from `barvitals` (modules/bar/barvitals.swift), because
# the `ps -A -o %cpu` sum this used to print is a LIFETIME average per process:
# on a machine that has been up a week it barely moves while every core is
# pinned. The graph is the reason that mattered enough to fix — a meter that
# doesn't move is a static label with extra steps.
#
# The graph is pushed from fetch rather than render, and that is the runtime's
# rule rather than this pill's preference — see `graph` in barlib.sh. Two
# things fall out of it that used to be hand-guarded here: a tick whose
# numbers didn't change still advances the window, and a POINTER crossing the
# pill cannot advance it at all (a mouse event never reaches fetch), which is
# what used to shove two minutes of history sideways at the speed of a mouse.
set -u
export USER="${USER:-$(id -un)}"
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:/usr/bin:/bin:$PATH"

# BAR_ITEM is the fallback for the CLI paths below, which arrive with no
# $BAR_NAME of their own; barlib sources colors/sizes/bar.sh and resolves $SB
# from it. The readouts are movable via haus.bar.bottom.items, so a bare
# `sketchybar` here would keep updating a top-bar item that no longer exists.
BAR_ITEM=cpu
source "$HOME/.config/sketchybar/barlib.sh"
source "$HOME/.config/sketchybar/plugins/vitals_lib.sh"

SELF="$HOME/.config/sketchybar/plugins/cpu.sh"
# Per-pill state, so this pill's percentages are always "since MY last look" —
# see barvitals.swift on why the two pills can't share one baseline. In the
# session's own $TMPDIR (0700) rather than world-writable /tmp: a predictable
# name in a shared directory is a symlink away from writing somewhere else.
STATE="${TMPDIR:-/tmp}/bar-vitals-cpu"

# Nerd Font CPU icon (nf-oct-cpu, U+F4BC). Literal glyph, not printf '\uXXXX' —
# macOS ships bash 3.2, whose printf has no \u/\U escapes and emits the escape
# text verbatim into the bar.
ICON=""

# ── the CLI paths ─────────────────────────────────────────────────────────────
# A dropdown row's --run re-enters this file. Both modes exit before
# barlib_main: a CLI path that fell through would re-enter the dispatcher with
# the click's own $SENDER still in the environment, which is the fork loop the
# runtime's header warns about. Neither closes the popup: every barlib row
# runs its action and then closes, so the close is already in the row's own
# click_script and doing it here would be the second one.
case "${1:-}" in
row)
  vitals_focus "${3:-}"
  exit 0
  ;;
activity)
  vitals_activity_monitor 0
  exit 0
  ;;
esac

# ── the tick ──────────────────────────────────────────────────────────────────
# `cpu` mode with no rows: a per-process delta needs a per-process baseline, so
# the periodic tick has to keep recording one even though it draws none. That
# is the tick's real cost — walking every process and rewriting the state file,
# ~25 ms of the 2-second budget — and it buys a dropdown that opens with
# numbers already in it.
fetch() {
  vitals_sample "$STATE" cpu 0
  # No `cpu` record means no previous sample to subtract — the first tick after
  # a reload, and nothing else. Returning non-zero keeps whatever the pill
  # already says rather than drawing a confident 0%, and pushes no graph point:
  # a zero here is a dip in the history that never happened.
  if [ -z "$CPU_TOTAL" ]; then return 1; fi
  graph "$CPU_TOTAL"
  vitals_history_push "$STATE" "$CPU_TOTAL"
  emit pct="$(printf '%.0f' "$CPU_TOTAL")" tone="$(vitals_tone "$CPU_TOTAL")"
}

# One label, always the same width class: the number. user/system and the load
# average are in the dropdown, where widening something costs nobody a jump.
#
# Only the LABEL is toned. The icon and the graph line are identity — which
# readout is this — and are painted once in the item's Nix style; a pill under
# load must not turn into two things flashing different colours at once.
render() {
  pill --icon "$ICON" --label "${pct}%" --label-tone "$tone"
}

# ── the dropdown ──────────────────────────────────────────────────────────────
# Sampled again here, with rows this time, rather than read from the tick's
# state: popup_rows runs on a CLICK, where fetch never ran and the framework's
# emitted variables do not exist. One sample still serves the whole dropdown,
# so no two rows are describing different moments.
popup_rows() {
  local pct n name value
  vitals_sample "$STATE" cpu 5
  if [ -n "$CPU_TOTAL" ]; then pct="$(printf '%.0f' "$CPU_TOTAL")"; else pct=0; fi

  # The total is a BADGE on the heading, in the ladder's tone for it — the
  # one number the pill exists for, set apart from the section's name rather
  # than tacked onto it. The sparkline under it is the pill's own two
  # minutes, from the ring fetch keeps (vitals_lib).
  popup_heading --icon "$ICON" --label "CPU" --badge "${pct}%" --badge-tone "$(vitals_tone "$CPU_TOTAL")"
  vitals_history "$STATE"
  [ -n "$VITALS_POINTS" ] && popup_graph --points "$VITALS_POINTS"

  # Guarded on the split rather than drawn blank: the first click after a bar
  # reload has no previous sample behind it, and `user  %` / `load  · cores` is
  # a row claiming to know something it doesn't. One tick later they're all here.
  if [ -n "$CPU_USER" ]; then
    popup_row --label "user" --value "${CPU_USER}%"
    popup_row --label "system" --value "${CPU_SYS}%"
    # Load average is the queue, not the usage: 100% with a load of 2 is a
    # machine working, 100% with a load of 30 is a machine drowning. Cores are
    # printed beside it because the number means nothing without them.
    popup_row --label "load" --value "${LOAD} · ${NCPU} cores"
  else
    popup_note --label "measuring — the bar reloaded a moment ago"
  fi

  if [ ${#TOP_NAME[@]} -gt 0 ]; then
    popup_separator
    popup_heading --label "What's using it"
    n=0
    while [ "$n" -lt ${#TOP_NAME[@]} ]; do
      name="${TOP_NAME[$n]}"
      value="${TOP_VALUE[$n]}"
      # Rows are clickable and each one goes to its app's window. `printf %q`
      # rather than hand-rolled quotes: --run is a command, so barlib passes it
      # through unquoted (unlike --open/--copy, which are data), half this
      # machine's apps have a space in their name, and an app with an
      # apostrophe must reach aerospace with the apostrophe still in it — a
      # name we edited to make quoting easy is a name that matches no window.
      popup_row --label "$name" --value "${value}%" \
        --tone "$(vitals_tone "$value")" \
        --run "$SELF row ${TOP_PID[$n]} $(printf '%q' "$name")"
      n=$((n + 1))
    done
    # The remainder is drawn, never hidden: barvitals can only read processes we
    # OWN, so a busy WindowServer or kernel_task lands here — and a big
    # "everything else" is the dropdown saying, correctly, that the answer is in
    # Activity Monitor rather than in this list.
    if [ -n "$REST" ]; then
      popup_row --label "everything else" --value "${REST}%" --tone dim
    fi
  fi

  # The way out is a BUTTON, not a row: it is the one thing here that leaves
  # the bar, and the shape says so.
  popup_button --icon "" --label "Activity Monitor" --run "$SELF activity"
}

# ── the gestures ──────────────────────────────────────────────────────────────
on_click() { popup_toggle; }

# The native view, on the tab this pill is about. Right-click rather than a
# modifier because the dropdown is the answer nine times in ten and this is
# where you go when it isn't.
on_right_click() { vitals_activity_monitor 0; }

barlib_main "$@"

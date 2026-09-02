#!/bin/bash
# widget: interval = 5
# widget: graph = 48
# widget: popup = true
#
# memory.sh — the memory pill: how much RAM is actually spoken for, a rolling
# graph of it, and a dropdown breaking it down and naming the biggest
# footprints. A framework widget (hausfold.co/docs/haus/rooms/bar-widgets): the
# header above is the whole of its wiring, and barlib owns the bar instance,
# the batching, the tones and the dropdown. cpu.sh is this pill's twin — read
# it for the graph and the fetch/render split; what is only true here is the
# colour, below.
#
# The reading comes from `barvitals` (modules/bar/barvitals.swift). What it
# replaces is `memory_pressure`'s "System-wide memory free percentage", which
# counts the FILE CACHE as used — and macOS fills idle RAM with cache on
# purpose, so that number sat near 90% on a machine doing nothing and had no
# dynamic range left to show anything with. This one adds up what Activity
# Monitor calls Memory Used: app memory + wired + compressed.
#
# The graph is pushed from fetch rather than render, and that is the runtime's
# rule rather than this pill's preference — see `graph` in barlib.sh. The two
# things it buys (a tick whose numbers didn't change still advances the
# window; a POINTER crossing the pill cannot advance it at all) used to be a
# guard and a comment in both vitals pills.
set -u
export USER="${USER:-$(id -un)}"
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:/usr/bin:/bin:$PATH"

# BAR_ITEM is the fallback for the CLI paths below, which arrive with no
# $BAR_NAME of their own; barlib sources colors/sizes/bar.sh and resolves $SB
# from it. The readouts are movable via haus.bar.bottom.items, so a bare
# `sketchybar` here would keep updating a top-bar item that no longer exists.
BAR_ITEM=memory
source "$HOME/.config/sketchybar/barlib.sh"
source "$HOME/.config/sketchybar/plugins/vitals_lib.sh"

SELF="$HOME/.config/sketchybar/plugins/memory.sh"
# Per-pill state, though nothing this pill draws is a delta: `top` in mem mode
# is GIGABYTES, not a rate (barvitals.swift). The separate path is so this pill
# cannot move the CPU pill's baseline — barvitals rewrites the state file on
# every run, and a shared one would advance a baseline nobody measured against.
# In the session's own $TMPDIR (0700) rather than world-writable /tmp: a
# predictable name in a shared directory is a symlink away from writing
# somewhere else.
STATE="${TMPDIR:-/tmp}/bar-vitals-memory"

# Nerd Font memory icon (nf-md-memory, U+F049D). Literal glyph, not printf
# '\UXXXXXXXX' — macOS ships bash 3.2, whose printf has no \u/\U escapes and
# emits the escape text verbatim into the bar.
ICON="󰒝"

# ── colour: the kernel's verdict, not the percentage ──────────────────────────
# A memory pill that climbs the usual ladder is amber all day, because 60% of
# RAM in use is a Mac working correctly — the number is high by design and says
# nothing about whether you're in trouble. kern.memorystatus_vm_pressure_level
# does: 1 normal, 2 warning, 4 critical, and it is what decides whether the
# machine starts swapping. So the pill goes amber when the KERNEL is worried,
# and the percentage stays a number you read rather than a colour you react to.
# It is the one vitals pill that does NOT spend `vitals_tone`.
#
# One case setting two globals, rather than two functions: the label's colour
# and the dropdown's word are the same verdict said twice, and a second case
# statement beside this one is the half that silently drifts.
pressure_verdict() { # pressure_verdict <level> — sets PRESSURE_TONE, PRESSURE_WORD
  case "${1:-1}" in
  4) PRESSURE_TONE=bad;  PRESSURE_WORD=critical ;;
  2) PRESSURE_TONE=warn; PRESSURE_WORD=warning ;;
  *) PRESSURE_TONE=ok;   PRESSURE_WORD=normal ;;
  esac
}
PRESSURE_TONE=ok
PRESSURE_WORD=normal

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
  vitals_activity_monitor 1
  exit 0
  ;;
esac

# ── the tick ──────────────────────────────────────────────────────────────────
# `none` mode: footprints are a quantity rather than a rate, so unlike the CPU
# pill this one needs no per-process baseline and the tick can ask for no rows
# at all. That is why the dropdown can be sampled fresh on the click without
# losing anything.
fetch() {
  vitals_sample "$STATE" none
  # An empty reading is the sampler not answering, and nothing else. Returning
  # non-zero keeps whatever the pill already says rather than drawing a
  # confident 0%, and pushes no graph point: a zero here is a dip in the
  # history that never happened.
  if [ -z "$MEM_PCT" ]; then return 1; fi
  graph "$MEM_PCT"
  pressure_verdict "${MEM_PRESSURE:-1}"
  emit pct="$(printf '%.0f' "$MEM_PCT")" tone="$PRESSURE_TONE"
}

# One label, always the same width class: the number. used/total and swap are
# in the dropdown, where widening something costs nobody a jump.
#
# Only the LABEL is toned. The icon and the graph line are identity — which
# readout is this — and are painted once in the item's Nix style; a pill under
# pressure must not turn into two things flashing different colours at once.
render() {
  pill --icon "$ICON" --label "${pct}%" --label-tone "$tone"
}

# ── the dropdown ──────────────────────────────────────────────────────────────
# Sampled again here, with rows this time, rather than read from the tick's
# state: popup_rows runs on a CLICK, where fetch never ran and the framework's
# emitted variables do not exist. One sample still serves the whole dropdown,
# so no two rows are describing different moments.
popup_rows() {
  local n swap
  vitals_sample "$STATE" mem 5

  # No cpu-style "measuring" case: a footprint needs no previous sample to
  # subtract, so the first click after a bar reload has every row in it
  # already. An empty reading here is the sampler itself unreachable.
  if [ -z "$MEM_PCT" ]; then
    popup_heading --icon "$ICON" --label "Memory"
    popup_note --label "no reading — barvitals did not answer"
    return 0
  fi
  pressure_verdict "${MEM_PRESSURE:-1}"

  popup_heading --icon "$ICON" --label "Memory" --value "${MEM_USED} / ${MEM_TOTAL} GB"
  popup_row --label "used" --value "${MEM_USED} GB"
  # Cache is drawn because it is the half of the old pill's lie worth keeping:
  # seeing 12 GB of file cache is what makes "54% used" legible on a 32 GB
  # machine that looks, in every other tool, like it is nearly full. Dim
  # because it is the one figure here that is not a claim on your RAM.
  popup_row --label "cached" --value "${MEM_CACHED} GB" --tone dim
  popup_row --label "compressed" --value "${MEM_COMPRESSED} GB"
  # Swap in use is the one row here that is always worth a colour: it is the
  # symptom the pressure level is there to predict, arriving.
  swap=text
  if [ "${MEM_SWAP%%.*}" -gt 0 ] 2>/dev/null; then swap=warn; fi
  popup_row --label "swap" --value "${MEM_SWAP} GB" --tone "$swap"
  popup_row --label "pressure" --value "$PRESSURE_WORD" --tone "$PRESSURE_TONE"

  if [ ${#TOP_NAME[@]} -gt 0 ]; then
    popup_note --label "biggest footprints"
    n=0
    while [ "$n" -lt ${#TOP_NAME[@]} ]; do
      # Rows are clickable and each one goes to its app's window. `printf %q`
      # rather than hand-rolled quotes: --run is a command, so barlib passes it
      # through unquoted (unlike --open/--copy, which are data), half this
      # machine's apps have a space in their name, and an app with an
      # apostrophe must reach aerospace with the apostrophe still in it — a
      # name we edited to make quoting easy is a name that matches no window.
      #
      # No --tone: these are GIGABYTES, and the severity ladder is a
      # percentage ladder. A 4 GB app is Xcode being Xcode.
      popup_row --label "${TOP_NAME[$n]}" --value "${TOP_VALUE[$n]} GB" \
        --run "$SELF row ${TOP_PID[$n]} $(printf '%q' "${TOP_NAME[$n]}")"
      n=$((n + 1))
    done
    # Same honesty as the CPU dropdown: these are processes we own, so anything
    # root runs — and every app too small for the list — is in here rather than
    # quietly missing from the sum.
    if [ -n "$REST" ]; then
      popup_row --label "everything else" --value "${REST} GB" --tone dim
    fi
  fi

  popup_action --icon "" --label "Activity Monitor" --run "$SELF activity"
}

# ── the gestures ──────────────────────────────────────────────────────────────
on_click() { popup_toggle; }

# The native view, on the tab this pill is about. Right-click rather than a
# modifier because the dropdown is the answer nine times in ten and this is
# where you go when it isn't.
on_right_click() { vitals_activity_monitor 1; }

barlib_main "$@"

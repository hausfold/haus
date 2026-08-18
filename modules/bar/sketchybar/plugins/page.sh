#!/bin/bash
# page.sh — which repo PAGE you are looking at, and nothing else.
#
# A lane's window lives on `T/<repo>` (terminal/lanes/lane-open.sh), so the
# focused workspace's own name already IS the repo — there is no git call here,
# no cwd to resolve, and nothing to join. That is the entire reason this pill
# can be cheap enough to repaint on every workspace change: it reads one string
# and slices a prefix off it.
#
# ── when it draws ────────────────────────────────────────────────────────────
# Only on the terminal pages, because only there does "which repo" have an
# answer. Three cases:
#
#   T/<repo>   the repo, spelled out — the answer this pill exists to give
#   T          the glyph alone, no label: you are on the unpaged terminal
#              workspace, which is a real place and not an error
#   anything   drawing=off — Obsidian's workspace has no repo, and a pill that
#              else       said so in every window would be noise you learn to
#                         skip past on the pages that DO carry one
#
# ── why hiding it is reliable ────────────────────────────────────────────────
# The repaint is PUSHed, never polled: AeroSpace's exec-on-workspace-change runs
# aerospace-notify.sh, which fires `aerospace_workspace_change` at both bars.
# That is the same signal the menu bar's workspace pills have always repainted
# on, so this pill is exactly as prompt as those are — one event per switch, no
# tick to wait for.
#
# It is also why there is no update_freq. A drawing=off item's own update_freq
# never ticks (see the agents pill's note in modules/bar/default.nix), so a
# hidden pill could never re-show itself from a poll anyway; the event is not a
# supplement to a tick here, it is the whole mechanism.
set -u
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:$PATH"
source "$HOME/.config/sketchybar/colors.sh"
# $SB — which bar this pill was placed on. See bar.sh; BAR_ITEM is the fallback
# for an invocation that carries no $NAME.
BAR_ITEM=page
source "$HOME/.config/sketchybar/bar.sh"

# ── the click ────────────────────────────────────────────────────────────────
# Both gestures open the SAME picker, in its two directions: a plain click to go
# to a page, ⇧ (or a right-click) to throw this window onto one. The picker is a
# palette command, so this is the one place where a bar plugin names a file the
# LAUNCHER room installs — `~/.config/haus/pages.sh`, a stable path put there
# for exactly this (the palette's own copy lives in a store path no bar plugin
# could resolve). Missing, the click does nothing rather than erroring into a
# log nobody reads: the pill's job is the label, and it keeps doing that.
if [ "${1:-}" = click ]; then
  picker="$HOME/.config/haus/pages.sh"
  [ -x "$picker" ] || exit 0
  # A plain click sends MODIFIER=none, not empty — test against the word. Any
  # modifier means move mode, ⇧ included: this is SketchyBar's own modifier,
  # not pounce's text field, so ⇧ is a real gesture here even though a `shift:`
  # ACTION inside the picker would never fire (see pages.sh's header).
  if [ "${BUTTON:-left}" = "right" ] || [ "${MODIFIER:-none}" != "none" ]; then
    exec "$picker" move
  fi
  exec "$picker"
fi

ws="$(aerospace list-workspaces --focused 2>/dev/null)"

case "$ws" in
  T)
    "$SB" --set page drawing=on label.drawing=off icon.color="$OVERLAY1"
    ;;
  T/*)
    "$SB" --set page drawing=on label.drawing=on \
        label="${ws#T/}" label.color="$TEXT" icon.color="$TEAL"
    ;;
  *)
    "$SB" --set page drawing=off
    ;;
esac

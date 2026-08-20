#!/bin/bash
# page.sh — which PAGE of the focused workspace you are on, and nothing else.
#
# A PAGE is an AeroSpace workspace with a `/` in its name. `T/<repo>` is the one
# haus produces today (terminal/lanes/lane-open.sh gives every repo's lanes their
# own page), but nothing about the mechanism is terminal-specific: AeroSpace
# makes a workspace on first use, `caps <letter>` resolves any bare workspace to
# its most recent live page (windows/scripts/workspace-mru.sh resolve), and the
# Pages picker will throw a window onto a page of any workspace. So this pill
# asks one question of the NAME — is there a `/` in it — and answers with the
# part after it. There is no git call here, no cwd to resolve and no join, which
# is the entire reason it is cheap enough to repaint on every workspace change.
#
# ── when it draws ────────────────────────────────────────────────────────────
#   <ws>/<page>   the page, spelled out — the answer this pill exists to give
#   anything      drawing=off. A workspace with no pages under it has no page to
#   else          be on, and the workspace pill beside this one already says
#                 which workspace that is. A pill that said "no page" everywhere
#                 would be noise you learn to skip past on the pages that DO
#                 carry one.
#
# It drew only on `T` and `T/*` until 2026-08-19, when it moved from the second
# bar's movable readouts into the menu bar's hand-written left group — beside the
# front app, where the workspace pills are. Pages were never a terminal feature;
# only their one producer was.
#
# ── why hiding it is reliable ────────────────────────────────────────────────
# The repaint is PUSHed, never polled: AeroSpace's exec-on-workspace-change runs
# aerospace-notify.sh, which fires `aerospace_workspace_change` at both bars.
# That is the same signal the workspace pills repaint on, so this pill is exactly
# as prompt as those are — one event per switch, no tick to wait for.
#
# It is also why there is no update_freq. A drawing=off item's own update_freq
# never ticks (see the agents pill's note in modules/bar/default.nix), so a
# hidden pill could never re-show itself from a poll anyway; the event is not a
# supplement to a tick here, it is the whole mechanism. The rc pairs it with
# `updates=on` for the other half of the same fact.
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
  # ACTION inside the picker would never fire — and ⌘ there is the lane chord's
  # (see pages.sh's header for both).
  if [ "${BUTTON:-left}" = "right" ] || [ "${MODIFIER:-none}" != "none" ]; then
    exec "$picker" move
  fi
  exec "$picker"
fi

ws="$(aerospace list-workspaces --focused 2>/dev/null)"

# `${ws#*/}` — the FIRST slash, so a hypothetical `T/a/b` reads as page "a/b"
# rather than losing its tail. AeroSpace workspace names are opaque strings; the
# rice only ever writes one level, but truncating someone else's is a silent lie.
case "$ws" in
  */*)
    "$SB" --set page drawing=on label.drawing=on \
        label="${ws#*/}" label.color="$TEXT" icon.color="$TEAL"
    ;;
  *)
    "$SB" --set page drawing=off
    ;;
esac

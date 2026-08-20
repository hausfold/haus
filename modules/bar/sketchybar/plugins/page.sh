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
# The counter costs one more `aerospace` call, and only on a page: the answer
# hides the pill outright on a workspace that has none, so the common case is
# exactly as cheap as it was before the count existed.
#
# ── when it draws ────────────────────────────────────────────────────────────
#   <ws>/<page>   the page, spelled out — the answer this pill exists to give —
#                 followed by `2/3` whenever that workspace has more than one
#                 live page: which of them you are on, out of how many there
#                 are. On the only page of a workspace the counter is dropped
#                 rather than drawn as `1/1`; "1 of 1" is a fact you can already
#                 see, and a pill that always carries a fraction stops being
#                 read as one.
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
# rather than losing its tail, and `${ws%%/*}` for the workspace it hangs off.
# AeroSpace workspace names are opaque strings; the rice only ever writes one
# level, but truncating someone else's is a silent lie.
case "$ws" in
  */*) ;;
  *)   exec "$SB" --set page drawing=off ;;
esac

base="${ws%%/*}"
label="${ws#*/}"

# ── the counter ──────────────────────────────────────────────────────────────
# `list-workspaces --monitor all` reports the persistent workspaces plus every
# non-persistent one currently holding a window, and a page is never persistent
# (lane-open.sh keeps `T/<repo>` out of persistent-workspaces on purpose, so an
# emptied page evaporates instead of accreting) — which makes every `<base>/…`
# line in that output a LIVE page and the count of them the number this pill
# wants. Same set the Pages picker lists, from the same call, so the `2/3` here
# and the rows there can never disagree about how many there are.
#
# The focused workspace is appended rather than assumed to be in that list: a
# page you have just switched to and not yet put a window on is real, is where
# you are standing, and would otherwise make the pill say `1/1` on the second
# page of two. Appending it LAST while deduplicating by first sighting keeps
# AeroSpace's own ordering for the pages that were already there, so the index
# counts down the picker's rows and only a brand-new empty page lands at the end.
counts="$(
  { aerospace list-workspaces --monitor all 2>/dev/null; printf '%s\n' "$ws"; } |
    awk -v ws="$ws" -v pfx="$base/" '
      !seen[$0]++ && index($0, pfx) == 1 { n++; if ($0 == ws) idx = n }
      END { printf "%d %d\n", idx + 0, n + 0 }'
)"
idx="${counts%% *}"
total="${counts##* }"

# Two spaces, not a separator glyph: the fraction is a second reading of the
# same pill and wants to sit apart from the name without adding furniture to a
# label that is already the widest thing in this group.
if [ "$total" -gt 1 ] && [ "$idx" -gt 0 ]; then
  label="$label  $idx/$total"
fi

"$SB" --set page drawing=on label.drawing=on \
    label="$label" label.color="$TEXT" icon.color="$TEAL"

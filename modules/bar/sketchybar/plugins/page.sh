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
# The count costs one more `aerospace` call — the one thing here that is not
# already in hand — and it is unconditional now that the workspace itself is a
# state: two calls per workspace change, on the same push the workspace pills
# repaint on.
#
# ── when it draws ────────────────────────────────────────────────────────────
#   <ws>/<page>   the page, spelled out — the answer this pill exists to give —
#                 followed by `2/3` whenever that workspace has more than one
#                 live page: which of them you are on, out of how many there
#                 are. On the only page of a workspace the counter is dropped
#                 rather than drawn as `1/1`.
#   <ws>, with    the count alone, dimmed: `3`. You are not on a page, so there
#   pages under   is no page to name — but there are three, and this is both the
#   it            notice that they exist and the button that lists them.
#   anything      drawing=off. A workspace with no pages under it has no page to
#   else          be on and none to go to, and the workspace pill beside this
#                 one already says which workspace that is.
#
# The middle state is the one that took two goes to get right. The pill drew
# only on a page until 2026-08-20, which meant the single thing it could never
# tell you was that a page EXISTED — you had to already be on one to learn there
# were others. `T` with three lanes paged away looked exactly like `T` with
# none, and the picker that would have listed them hangs off a pill that wasn't
# there.
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

# `${ws%%/*}` — the workspace a page hangs off, and itself when it is not a
# page. Everything below is asked of that BASE, which is what lets the pill
# answer on `T` and on `T/haus` with one count.
base="${ws%%/*}"

# ── the count ────────────────────────────────────────────────────────────────
# `list-workspaces --monitor all` reports the persistent workspaces plus every
# non-persistent one currently holding a window or currently visible, and a page
# is never persistent (lane-open.sh keeps `T/<repo>` out of
# persistent-workspaces on purpose, so an emptied page evaporates instead of
# accreting) — which makes every `<base>/…` line in that output a LIVE page, and
# the number of them the number this pill wants. The Pages picker counts the
# same set from the same call (its list is longer: it forces a bare `T` in and
# draws a row for each base), so the two can never disagree about how many pages
# a workspace has.
#
# The focused workspace is appended defensively rather than because it is ever
# missing — a focused workspace is a visible one, so AeroSpace lists it whether
# or not it holds a window, including the page you just switched to and have not
# put anything on yet. `!seen[$0]++` absorbs the duplicate that normally is, and
# preserves AeroSpace's own ordering for everything already there, so the index
# counts down the picker's rows.
#
# `index($0, pfx) == 1` with the SLASH in pfx, never a bare-name compare: `T`
# must not match `TT/x`, and a base whose name is a prefix of another base is
# the one way this could silently over-count.
counts="$(
  { aerospace list-workspaces --monitor all 2>/dev/null; printf '%s\n' "$ws"; } |
    awk -v ws="$ws" -v pfx="$base/" '
      !seen[$0]++ && index($0, pfx) == 1 { n++; if ($0 == ws) idx = n }
      END { printf "%d %d\n", idx + 0, n + 0 }'
)"
idx="${counts%% *}"; idx="${idx:-0}"
total="${counts##* }"; total="${total:-0}"

# ── what that means on screen ────────────────────────────────────────────────
# Three states, and the muted one is the point: a pill that only ever appeared
# once you were already on a page could never tell you a page EXISTED, which is
# exactly when you want the picker its click opens.
case "$ws" in
  */*)
    # On a page: its name, and `2/3` when there is more than one to be on. Two
    # spaces rather than a separator glyph — the fraction is a second reading of
    # the same pill and wants to sit apart from the name without adding
    # furniture to a label that is already the widest thing in this group. The
    # only page of a workspace gets no counter at all: `1/1` is a fact you can
    # already see, and a pill that always carries a fraction stops being read as
    # one.
    label="${ws#*/}"
    [ "$total" -gt 1 ] && [ "$idx" -gt 0 ] && label="$label  $idx/$total"
    "$SB" --set page drawing=on label.drawing=on \
        label="$label" label.color="$TEXT" icon.color="$TEAL"
    ;;
  *)
    # On the workspace itself, with pages under it: the count alone, dimmed.
    # Dimmed because the pill is not naming where you are here — it is saying
    # "this is not the only place `T` has", which is a weaker claim than the
    # page name and should not read as loudly as one. The number is the same
    # number that is the denominator one state up, so `3` and `2/3` are the same
    # fact seen from either side.
    if [ "$total" -gt 0 ]; then
      "$SB" --set page drawing=on label.drawing=on \
          label="$total" label.color="$SUBTEXT0" icon.color="$OVERLAY1"
    else
      # No pages under it — nothing to say. The workspace pill beside this one
      # already says which workspace you are on, and a pill that said "no pages"
      # everywhere would be noise you learn to skip past on the workspaces that
      # DO have some.
      "$SB" --set page drawing=off
    fi
    ;;
esac

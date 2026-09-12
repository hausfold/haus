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
#                 followed by `3/4` whenever the workspace has more than one
#                 live page: which of them you are on, out of how many there
#                 are. The workspace ITSELF is the first of those and not the
#                 container the rest hang off — `T` is somewhere you stand and
#                 go back to, so it is counted exactly as a page is, whenever
#                 there is anything on it. A lone lane on `T/haus` with windows
#                 still on `T` therefore reads `2/2`, and the same lane with `T`
#                 emptied out reads `haus` alone: one place is not a fraction,
#                 and `1/1` is a fact you can already see.
#   <ws>, with    the count alone, dimmed: `4` — every place the workspace has,
#   a page under  itself included whenever there is anything on it. You are not
#   it            on a page, so there is no page to name, but there are others
#                 to be on: this is both the notice that they exist and the
#                 button that lists them.
#   anything      drawing=off. A workspace with no page under it has nowhere to
#   else          go that this pill could name — `T` on its own is `T` — and the
#                 workspace pill beside this one already says which that is.
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
# One rule, asked of every workspace the same way: a place counts when there is
# a window on it. `list-workspaces --monitor all --empty no` is that question,
# and the answer holds both halves of what this pill counts — the live pages
# under `<base>/`, and the BASE itself, which is a place you stand and go back
# to rather than the container the pages hang off.
#
# `--empty no` is what lets one call answer for both. A page is never persistent
# (lane-open.sh keeps `T/<repo>` out of persistent-workspaces on purpose, so an
# emptied page evaporates instead of accreting) but a base workspace always is,
# so a plain `--monitor all` lists `T` whether or not anything is on it —
# counting that unconditionally would hang a `/2` off every lone lane and put a
# `1` under every empty workspace on the Mac.
#
# The focused workspace is appended only when it is a PAGE: one you just
# switched to and have not put anything on yet is still the page you are on, and
# it needs to be in the set for `idx` to find it. The base is deliberately not
# appended — an emptied `T` is not a place anything IS, and the count has to
# read the same from either side of a switch: `3` on an emptied `T` with three
# lanes paged off it, then `2/3` once you are on one of them. `!seen[$0]++`
# absorbs the duplicate that normally is, and preserves AeroSpace's own ordering
# for everything already there.
#
# The base is counted FIRST, ahead of that ordering, because the Pages picker
# forces a bare `T` on top of its rows the same way. The two lists are not the
# same length, and deliberately: the picker offers everywhere you can GO, an
# empty `T` included, because an emptied `T` is exactly what you throw a window
# back to. This counts everywhere something IS.
#
# `index($0, pfx) == 1` with the SLASH in pfx, never a bare-name compare: `T`
# must not match `TT/x`, and a base whose name is a prefix of another base is
# the one way this could silently over-count.
# Decided out here, never inside the `$( )` below: `/bin/bash` is 3.2, whose
# command substitution is scanned for a matching `)` before it is parsed as
# shell, so the unbalanced one closing a `case` pattern — `*/*)` — ends the
# substitution early and takes the whole file down with `unexpected EOF`. Same
# hazard the apostrophe note in launcher/commands/pages.sh describes, and it
# survives `bash -n` under any bash 4+.
focused_page=""
case "$ws" in
  */*) focused_page="$ws" ;;
esac

counts="$(
  {
    aerospace list-workspaces --monitor all --empty no 2>/dev/null
    [ -n "$focused_page" ] && printf '%s\n' "$focused_page"
  } |
    awk -v ws="$ws" -v base="$base" -v pfx="$base/" '
      !seen[$0]++ {
        if ($0 == base) occupied = 1
        else if (index($0, pfx) == 1) page[++p] = $0
      }
      END {
        if (occupied) { n++; if (ws == base) idx = n }
        for (i = 1; i <= p; i++) { n++; if (page[i] == ws) idx = n }
        printf "%d %d %d\n", idx + 0, n + 0, p + 0
      }'
)"
# idx  where you are in that set, 0 when you are not in it (the base, empty).
# total what the fraction is out of, the base included when it is occupied.
# pages how many of those are pages — the base state draws on this and not on
#       `total`, which are the same number until the base is empty: standing on
#       an emptied `T` with one lane paged off it, `total` is 1 and there is
#       still a page to be told about.
read -r idx total pages <<<"$counts"
idx="${idx:-0}"; total="${total:-0}"; pages="${pages:-0}"

# ── what that means on screen ────────────────────────────────────────────────
# Three states, and the muted one is the point: a pill that only ever appeared
# once you were already on a page could never tell you a page EXISTED, which is
# exactly when you want the picker its click opens.
case "$ws" in
  */*)
    # On a page: its name, and `3/4` when there is more than one place to be.
    # Two spaces rather than a separator glyph — the fraction is a second
    # reading of the same pill and wants to sit apart from the name without
    # adding furniture to a label that is already the widest thing in this
    # group. One live place gets no counter at all — a lane on `T/haus` with
    # nothing left on `T` is just `haus`: `1/1` is a fact you can already see,
    # and a pill that always carries a fraction stops being read as one.
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
    # number that is the denominator one state up, so `4` and `3/4` are the same
    # fact seen from either side.
    if [ "$pages" -gt 0 ]; then
      "$SB" --set page drawing=on label.drawing=on \
          label="$total" label.color="$SUBTEXT0" icon.color="$OVERLAY1"
    else
      # Nowhere else to be — nothing to say. The workspace pill beside this one
      # already says which workspace you are on, and a pill that said "no pages"
      # everywhere would be noise you learn to skip past on the workspaces that
      # DO have some.
      "$SB" --set page drawing=off
    fi
    ;;
esac

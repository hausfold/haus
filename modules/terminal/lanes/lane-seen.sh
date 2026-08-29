#!/bin/bash
# lane-seen.sh — "you are looking at the lane; take its banner down."
#
# The other end of lanes/lane-focus.sh. That one answers a CLICK on a lane's
# trill banner by raising its window; this one answers the case the click never
# covered — you went to the window YOURSELF, with ⌘Tab, a page walk, the mouse
# — and the fin is still parked on the ledge asking you to go somewhere you are
# already standing.
#
# scruff's own hook (`scruff hook notify`) already resolves a lane's ask when the
# session MOVES: you typed an answer, or a permission prompt was approved and a
# tool ran. That is the honest signal for "the question was answered" and it
# stays. But it is not the signal for "I have seen it": you can focus a lane,
# read the question, and think for a minute before typing, and the ledge should
# not still be flagging it for you the whole time. Focus is the earlier, more
# forgiving event, and this file is the only place on the machine that can see
# it — the window layer.
#
# AeroSpace's `on-focus-changed` is what runs it (modules/windows), so it fires
# on EVERY focus change on this Mac. Everything below is ordered by what it
# costs, and the ordinary answer — no lane is waiting, or the focused thing is
# not a terminal — is reached with two stats and one 4 ms query.
#
# Nothing here is allowed to matter: no fin, no trill, no registry, no zmx all
# mean "do nothing", and every one of them exits 0.
set -u

export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

# How long the window has to KEEP focus before the fin comes down. Walking four
# pages to reach the fifth focuses a window on each one, and ⌘Tab held down
# passes through everything it offers — neither of those is "I looked at it".
dwell="${HAUS_LANE_SEEN_DWELL:-1}"

# ── is any fin up at all? ────────────────────────────────────────────────────
# scruff writes one empty file per fin it put up, under its state dir, and names
# it after the key it used — `scruff/<repo>/<lane>` with the slashes flattened
# to dots, which is byte-for-byte the zmx session name lanes/lane-open.sh gives
# that lane (`scruff.<repo>.<lane>`). So the join is string equality and there is
# nothing to parse: `<repo>` may itself carry a dot (hausfold.co), and no split
# of the session name can tell that dot from the separator.
#
# 🚨 Rename either half alone and the join stops matching SILENTLY: no error,
# no log, and every lane's fin stays parked on trill's ledge forever. The key
# is a literal in the tool (`askKeyPrefix`, internal/commands/notify.go), not
# something haus chooses, and the marker filename IS the session name.
#
# Both halves moved together at scruff 1.2.0 (its docs/rename.md §8.6) — and
# neither moved ALONE, which is why this still answers to `holt` too. A fin put
# up before that rebuild is keyed the old way and can only be resolved by the
# name that put it up, so the read arm below is what keeps it from being
# stranded. It comes out at 1.3.0, with scruff's own.
#
# It is scruff's CACHE, not its record — scruff says so at internal/commands/
# notify.go — so it is only ever read here, never written or removed, and a
# stale one costs one idempotent `trill resolve` that finds nothing.
#
# If scruff ever moves or renames it, `$asks` stops existing and the gate opens
# rather than closing: the fallback is to resolve on every lane focus, which is
# chattier but still correct. A rename of the FILES inside it would be the one
# shape that fails silently, which is why the naming is spelled out above.
#
# The state dir is scruff's own, full stop: $SCRUFF_STATE, then the
# scruff-named state dir. There is no second directory to probe.
state="${SCRUFF_STATE:-}"
if [ -z "$state" ]; then
  state="${XDG_STATE_HOME:-$HOME/.local/state}/scruff"
fi
asks="$state/asks"
if [ -d "$asks" ]; then
  # Fork-free on purpose: this runs on every focus change, and an `ls` here
  # would cost more than the window query it is there to save.
  shopt -s nullglob dotglob
  set -- "$asks"/*
  [ "$#" -gt 0 ] || exit 0
fi

# ── which lane is being looked at? ───────────────────────────────────────────
# scripts/focused-session.sh is the window → zmx session join every chord in
# this room uses. A lane's session is named `scruff.<repo>.<lane>`; anything
# else focused — a plain shell, a browser, Finder — either answers with a name
# that carries neither lane prefix, or answers nothing.
#
# A Claude pane running OUTSIDE any lane gets a fin too (scruff keys it by
# session id), and this file deliberately cannot resolve those: the window
# carries no id to join on, and the pane's own PostToolUse takes it down the
# moment you type anything.
focused="$HOME/.config/haus/term/focused-session.sh"
[ -x "$focused" ] || exit 0

sess="$("$focused" 2>/dev/null)"
case "$sess" in
  scruff.*|holt.*) ;;
  *) exit 0 ;;
esac

[ ! -d "$asks" ] || [ -e "$asks/$sess" ] || exit 0

# ── still looking at it a moment later? ──────────────────────────────────────
sleep "$dwell"
[ "$("$focused" 2>/dev/null)" = "$sess" ] || exit 0

# ── the session name, back as the key scruff gave the fin ──────────────────────
# scruff's registry is a TSV whose location is fixed by scruff's own SPEC (§10):
# name, main, branch, path, parent, agent. Read directly rather than through
# `scruff --json`, whose lsof sweep costs seconds, and rather than through
# scruff-cache, whose whole point is tolerating staleness — a lane that appeared
# thirty seconds ago is exactly the one waiting on you.
reg="${SCRUFF_BASE:-$(
  if [ -f "$HOME/.cache/scruff/registry.tsv" ]; then echo "$HOME/.cache/scruff"; \
  else echo "$HOME/.cache/claude-worktrees"; fi)}/registry.tsv"
[ -r "$reg" ] || exit 0

key="$(
  awk -F'\t' -v want="$sess" '
    {
      n = split($2, p, "/")
      if (n == 0 || $1 == "") next
      # Both spellings, and the key printed is the one that MATCHED: a lane
      # whose window predates the rename is keyed the old way on the ledge and
      # answers to nothing else. (No apostrophes in here — the whole awk
      # program is inside a single-quoted shell string.)
      if ("scruff." p[n] "." $1 == want) { print "scruff/" p[n] "/" $1; exit }
      if ("holt."   p[n] "." $1 == want) { print "holt/"   p[n] "/" $1; exit }
    }
  ' "$reg"
)"
[ -n "$key" ] || exit 0

# `trill resolve` is idempotent — a key with nothing parked under it prints 0
# and exits 0 — and the wrapper (modules/core/trill.sh) exits 127 with no
# Trill.app. Neither is this script's business to report.
trill resolve "$key" >/dev/null 2>&1 || exit 0
exit 0

#!/bin/bash
# lane-seen.sh — "you are looking at the lane; take its banner down."
#
# The other end of lanes/lane-focus.sh. That one answers a CLICK on a lane's
# trill banner by raising its window; this one answers the case the click never
# covered — you went to the window YOURSELF, with ⌘Tab, a page walk, the mouse
# — and the fin is still parked on the ledge asking you to go somewhere you are
# already standing.
#
# holt's own hook (`holt hook notify`) already resolves a lane's ask when the
# session MOVES: you typed an answer, or a permission prompt was approved and a
# tool ran. That is the honest signal for "the question was answered" and it
# stays. But it is not the signal for "I have seen it": you can focus a lane,
# read the question, and think for a minute before typing, and the ledge should
# not still be flagging it for you the whole time.
#
# ── seen means ON THE PAGE, not "has keyboard focus" ─────────────────────────
# The first version of this file asked only which window was focused, and that
# was too narrow by exactly the case a tiler creates: a lane tiled beside the
# thing you are typing in is in plain sight, fully drawn, on the page you are
# looking at — and its fin sat there flagging it anyway. So the question is the
# PAGE's: every lane window on the focused workspace has been seen, whichever
# one holds the keyboard.
#
# It is deliberately the FOCUSED workspace and not every visible one. On a Mac
# with a second display "visible" would include a page you have your back to,
# and clearing a fin nobody looked at is the one failure this file must not
# have.
#
# Two triggers, and they answer different halves:
#
#   AeroSpace's `on-focus-changed`   you arrived — a page walk, ⌘Tab, a click.
#   a launchd WatchPaths agent       the fin arrived while you were already
#                                    sitting here, so no focus ever changed.
#                                    It watches holt's marker dir, which is
#                                    written the moment a fin goes up, and runs
#                                    with a longer dwell so the banner has left
#                                    the screen before the ledge entry goes.
#
# The first fires on EVERY focus change on this Mac, so everything below is
# ordered by what it costs, and the ordinary answer — no lane is waiting — is
# reached with one directory read and no forks at all.
#
# Nothing here is allowed to matter: no fin, no trill, no registry, no zmx, no
# tiler all mean "do nothing", and every one of them exits 0.
set -u

export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

# Under launchd there is no promise of a HOME, and every path below is built
# from one. `set -u` would exit 1 on the bare expansion, which is the one code
# that reads as "this ran and failed" rather than "there was nothing to do".
[ -n "${HOME:-}" ] || exit 0

# How long the page has to KEEP focus before the fins come down. Walking four
# pages to reach the fifth focuses a window on each one, and ⌘Tab held down
# passes through everything it offers — neither of those is "I looked at it".
# The WatchPaths agent overrides it upward; see the header.
dwell="${HAUS_LANE_SEEN_DWELL:-1}"

# ── which lanes are waiting? ─────────────────────────────────────────────────
# holt writes one empty file per fin it put up, under its state dir, and names
# it after the key it used — `holt/<repo>/<lane>` with the slashes flattened to
# dots, which is byte-for-byte the zmx session name lanes/lane-open.sh gives
# that lane (`holt.<repo>.<lane>`). So the join is string equality and there is
# nothing to parse: `<repo>` may itself carry a dot (hausfold.co), and no split
# of the session name can tell that dot from the separator.
#
# It is holt's CACHE, not its record — holt says so at internal/commands/
# notify.go, and its own `clearAskOutstanding` is a bare remove — so the marker
# of a fin THIS script resolved is dropped at the bottom of the file. That is
# not bookkeeping, it is what keeps the gate below cheap: holt only prunes a
# marker on that lane's next tool call, so a lane closed while blocked leaves
# one behind forever, and a dir that is never empty turns "is anything waiting"
# into "yes" on every focus change for the life of the machine. Nothing else
# here writes to that dir.
#
# If holt ever moves the dir, the list comes back empty and the gate OPENS
# rather than closing: every lane on the page is resolved instead of only the
# waiting ones, which is chattier but still correct. (The room's activation
# creates the dir so launchd has something to watch, so in practice that means
# a machine this room never activated on — a checkout, a test.) A rename of the
# FILES inside it is the one shape that fails silently, which is why the naming
# is spelled out above.
state="${HOLT_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/holt}"
asks="$state/asks"
shopt -s nullglob dotglob
waiting=""
have_markers=0
if [ -d "$asks" ]; then
  have_markers=1
  for marker in "$asks"/*; do
    name="${marker##*/}"
    case "$name" in
      # A pane outside every lane gets a fin too, keyed by the client's session
      # id (`holt/session/<uuid>`). It has no window title to match and nothing
      # here can ever resolve it, so it must not count as "something is
      # waiting" — that would defeat the gate for every other pane on the Mac.
      holt.session.*) ;;
      holt.*) waiting="$waiting $name" ;;
    esac
  done
  # Nothing parked anywhere: the whole point of the marker dir. This is the
  # answer almost every focus change gets, and it costs one directory read.
  [ -n "$waiting" ] || exit 0
fi

# ── which lanes are in front of you? ─────────────────────────────────────────
# Same backend split as scripts/focused-session.sh, and HAUS_WINDOW_BACKEND
# forces one for the same reason: a machine WITH a tiler has to be able to feel
# the path a machine without one takes.
backend="${HAUS_WINDOW_BACKEND:-}"
if [ -z "$backend" ]; then
  if command -v aerospace >/dev/null 2>&1; then backend=aerospace; else backend=ghostty; fi
fi

# What "the same place" means for the dwell below — the page under you where
# there are pages, the focused window's session where there are none.
here() {
  case "$backend" in
    aerospace) aerospace list-workspaces --focused 2>/dev/null ;;
    *) "$HOME/.config/haus/term/focused-session.sh" 2>/dev/null ;;
  esac
}

# The lane sessions on screen, one per line.
#
# ⚠️ A plain shell window born inside a lane's Ghostty process wears that lane's
# FORCED title (Ghostty's `--title` is instance-wide, not per window — see
# scripts/focused-session.sh), so the title alone would hand us lanes that are
# not on this page at all, and clear their fins. The discriminator is the one
# raise-session.sh uses: a plain window carries a `window=` label that
# launch.sh stamps and a real lane never does, so an id some session has
# CLAIMED is exactly an impostor.
#
# The claimed list is SPACE-separated and must never carry a newline: `awk -v`
# is a piece of awk SOURCE, and macOS's one-true-awk refuses a literal newline
# inside a string literal — `awk: newline in string`, exit 2, nothing on
# stdout. That bug cost this room a silent outage once already (2026-08-26, see
# raise-session.sh); ids are digits, so a space is a safe join.
#
# ⚠️ test/lane-seen.bats runs the awk below on fixtures, extracting it by `sed`
# between its `BEGIN { n = split(c, a, " ")` line and its `$2 == "Ghostty"`
# line — the tiler is the one thing a hermetic test cannot stub, since this
# script's own PATH prelude puts the real `aerospace` ahead of anything a test
# could prepend. Reword either line and the fragment comes back empty and every
# case fails at once, which is the loud failure and why it is acceptable.
on_screen() {
  if [ "$backend" != "aerospace" ]; then
    # No pages, so "on screen" can only mean the focused window.
    sess="$("$HOME/.config/haus/term/focused-session.sh" 2>/dev/null)"
    case "$sess" in
      holt.*) printf '%s\n' "$sess" ;;
    esac
    return 0
  fi
  claimed="$(zmx ls 2>/dev/null | tr '\t' '\n' | sed -n 's/^window=//p' | tr '\n' ' ')"
  aerospace list-windows --workspace focused --format '%{window-id}|%{app-name}|%{window-title}' 2>/dev/null |
    awk -F'|' -v c="$claimed" '
      BEGIN { n = split(c, a, " "); for (i = 1; i <= n; i++) if (a[i] != "") skip[a[i]] = 1 }
      $2 == "Ghostty" && $3 ~ /^holt\./ && !($1 in skip) { print $3 }'
}

seen=""
while IFS= read -r sess; do
  [ -n "$sess" ] || continue
  # Only lanes that are actually waiting — unless holt's marker dir has moved
  # out from under us, in which case there is nothing to intersect against and
  # every lane on the page is a candidate.
  if [ "$have_markers" = 1 ]; then
    case " $waiting " in
      *" $sess "*) ;;
      *) continue ;;
    esac
  fi
  seen="$seen $sess"
done <<EOS
$(on_screen)
EOS
[ -n "$seen" ] || exit 0

# ── still looking at it a moment later? ──────────────────────────────────────
# The page, not the window: moving between two windows of the same page is not
# leaving it, and is the ordinary thing to do while a lane works.
where="$(here)"
sleep "$dwell"
[ "$(here)" = "$where" ] || exit 0

# ── those session names, back as the keys holt gave the fins ─────────────────
# holt's registry is a TSV whose location is fixed by holt's own SPEC (§10):
# name, main, branch, path, parent, agent. Read directly rather than through
# `holt --json`, whose lsof sweep costs seconds, and rather than through
# holt-cache, whose whole point is tolerating staleness — a lane that appeared
# thirty seconds ago is exactly the one waiting on you.
reg="${HOLT_BASE:-$HOME/.cache/claude-worktrees}/registry.tsv"
[ -r "$reg" ] || exit 0

keys=""
while IFS= read -r key; do
  [ -n "$key" ] || continue
  keys="$keys $key"
done <<EOS
$(
  awk -F'\t' -v want="$seen" '
    BEGIN { n = split(want, a, " "); for (i = 1; i <= n; i++) if (a[i] != "") w[a[i]] = 1 }
    {
      n2 = split($2, p, "/")
      if (n2 == 0 || $1 == "" || p[n2] == "") next
      if (("holt." p[n2] "." $1) in w) print "holt/" p[n2] "/" $1
    }
  ' "$reg"
)
EOS
[ -n "$keys" ] || exit 0

# `trill resolve` takes every key at once, is idempotent — a key with nothing
# parked under it prints 0 and exits 0 — and the wrapper (modules/core/trill.sh)
# exits 127 with no Trill.app. None of that is this script's to report.
#
# Unquoted on purpose: keys are `holt/<repo>/<lane>`, built above from a TSV
# whose fields cannot contain whitespace and have already been matched against
# a whitespace-separated list.
# shellcheck disable=SC2086
trill resolve $keys >/dev/null 2>&1 || exit 0

# The fins are down, so holt's markers for them are stale — drop them. See the
# note at the top: this is the only write this script makes, it is invalidating
# a cache holt documents as one, and skipping it would leave the marker dir
# permanently non-empty and the cheap gate above permanently open.
#
# Only what we actually resolved, and only when we read markers in the first
# place. Same unquoted-on-purpose expansion as `$keys`.
if [ "$have_markers" = 1 ]; then
  # shellcheck disable=SC2086
  for sess in $seen; do
    rm -f "$asks/$sess"
  done
fi
exit 0

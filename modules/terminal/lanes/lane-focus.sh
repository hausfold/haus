#!/bin/bash
# lane-focus.sh — scruff's `focus` seam: go to the window a lane is ALREADY in.
#
# `scruff focus <name>` is `scruff <name>` minus the reopening. scruff cannot answer
# it on its own — the join from a lane to a window belongs to whatever opened
# the window, which here is lanes/lane-open.sh — so scruff asks this hook and
# falls back to resume when it defers. Which is the whole trick: this script
# only ever RAISES, and every case where there is nothing to raise is an exit
# 3, handing the work back to the seam that knows how to open one properly.
#
# The caller is usually not a human. trill banners a lane when it blocks or
# finishes (scruff hook notify), and clicking that banner runs `scruff focus` —
# which means this script runs with a GUI app's environment: PATH is four
# system directories and nothing else. raise-session.sh repairs that for
# itself at its own top; nothing here may assume more than /bin and /usr/bin.
#
# ── why not raise-session.sh --or-open ───────────────────────────────────────
# Because --or-open opens a BARE window onto the session, and a lane's window
# is not bare: lane-open.sh tiles it onto T/<repo> and forces the title the
# AeroSpace backend joins on.
# Deferring instead sends scruff through resume → lane-open.sh, and the window
# that appears is a lane's, not a shell that happens to hold one.
#
# A background lane USUALLY has a window from the moment it spawns
# (lane-open.sh's background note), so the common path through here is a plain
# raise. The defer is for the lane whose window was closed with ⌘W while the
# session kept thinking, for the spawn whose window has not been tiled yet, and
# for the lane born with the display asleep — that one is windowless by design
# (lane-open.sh's no-display note), so this defer is how it gets its FIRST
# window rather than a replacement one, and ⌃⇥ cannot stand in because it walks
# tiled pages and that lane has never been on one. It is
# the reason not to "fix" this script by reaching for --or-open, which answers
# with a bare untiled window born on whatever page you are standing on instead
# of a lane's own window on T/<repo>.
set -u

# The situation arrives as SCRUFF_* (scruff's action-seam protocol; stdin belongs
# to the caller). Anything missing is scruff's business to answer, not ours.
[ -n "${SCRUFF_NAME:-}" ] || exit 3
main="${SCRUFF_MAIN:-}"
[ -n "$main" ] || exit 3

# The same name lane-open.sh gave the session, built the same way: qualified by
# the main checkout's basename, because `scruff child` puts one lane name in two
# repos. SCRUFF_MAIN, not SCRUFF_REPO — the latter is a remote slug and is empty
# for a repo that has never been pushed.
lane="$(/usr/bin/basename "$main").${SCRUFF_NAME}"
sess="scruff.$lane"

raise="$HOME/.config/haus/term/raise-session.sh"
[ -x "$raise" ] || exit 3

# --fullscreen, because of WHO clicks this. The banner is up because the lane
# blocked or finished, and a raise onto a page holding five tiled windows
# answers "which page wanted you" rather than "which window" — the one that
# asked is then found by its solid cursor, which is the hunt this flag exists
# to end.
#
# It is cheap to take because it is cheap to leave: AeroSpace drops the mode
# the moment you focus any other window on that page, so the page comes back
# by itself and <mod>f is only the deliberate way out. The take is that
# binding's own script, guard included — windows/scripts/fullscreen-toggle.sh,
# reached through raise-session.sh, whose header says why the rule lives there
# and not here.
#
# Exit 0 = a window was raised and scruff is done. Exit 1 from raise-session.sh
# means no window holds this session — it is detached and still running, which
# is a defer here, not a failure.
"$raise" --fullscreen "$sess" >/dev/null 2>&1 || exit 3
exit 0

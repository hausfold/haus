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
# A background lane HAS a window from the moment it spawns (lane-open.sh's
# background note), so the common path through here is a plain raise. The defer
# is for the lane whose window was closed with ⌘W while the session kept
# thinking, and for the spawn whose window has not been tiled yet — and it is
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

# Exit 0 = a window was raised and scruff is done. Exit 1 from raise-session.sh
# means no window holds this session — it is detached and still running, which
# is a defer here, not a failure.
"$raise" "$sess" >/dev/null 2>&1 || exit 3
exit 0

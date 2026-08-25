#!/bin/bash
# lane-focus.sh — holt's `focus` seam: go to the window a lane is ALREADY in.
#
# `holt focus <name>` is `holt <name>` minus the reopening. holt cannot answer
# it on its own — the join from a lane to a window belongs to whatever opened
# the window, which here is lanes/lane-open.sh — so holt asks this hook and
# falls back to resume when it defers. Which is the whole trick: this script
# only ever RAISES, and every case where there is nothing to raise is an exit
# 3, handing the work back to the seam that knows how to open one properly.
#
# The caller is usually not a human. trill banners a lane when it blocks or
# finishes (holt hook notify), and clicking that banner runs `holt focus` —
# which means this script runs with a GUI app's environment: PATH is four
# system directories and nothing else. raise-session.sh repairs that for
# itself at its own top; nothing here may assume more than /bin and /usr/bin.
#
# ── why not raise-session.sh --or-open ───────────────────────────────────────
# Because --or-open opens a BARE window onto the session, and a lane's window
# is not bare: lane-open.sh tiles it onto T/<repo>, forces the title the
# AeroSpace backend joins on, and hands focus back where the spawn found it.
# Deferring instead sends holt through resume → lane-open.sh, and the window
# that appears is a lane's, not a shell that happens to hold one.
set -u

# The situation arrives as HOLT_* (holt's action-seam protocol; stdin belongs
# to the caller). Anything missing is holt's business to answer, not ours.
[ -n "${HOLT_NAME:-}" ] || exit 3
main="${HOLT_MAIN:-}"
[ -n "$main" ] || exit 3

# The same name lane-open.sh gave the session, built the same way: qualified by
# the main checkout's basename, because `holt child` puts one lane name in two
# repos. HOLT_MAIN, not HOLT_REPO — the latter is a remote slug and is empty
# for a repo that has never been pushed.
sess="holt.$(/usr/bin/basename "$main").${HOLT_NAME}"

raise="$HOME/.config/haus/term/raise-session.sh"
[ -x "$raise" ] || exit 3

# Exit 0 = a window was raised and holt is done. Exit 1 from raise-session.sh
# means no window holds this session — it is detached and still running, which
# is a defer here, not a failure.
"$raise" "$sess" >/dev/null 2>&1 || exit 3
exit 0

#!/bin/bash
# Ghostty → zmx launcher. Configured as ghostty's `command`.
# Debug log: /tmp/haus-term-launch.log
#
# This is the heir of the zellij launcher, and it does two of the three jobs
# that one did. The third — "attach to the ONE `main` session" — is gone with
# the multiplexer: a window is a pane now, so there is no single session for
# every window to share. Each window gets its own.
#
# ── why a zmx session at all, when a window could just be a shell ────────────
# Persistence is the small half. The load-bearing half is that Ghostty's
# AppleScript API can CREATE a surface but cannot READ one — no dump-screen, no
# scrollback, no text property. Three shipped features read a window: ⌘F find
# (scripts/find.sh), ⌘L links (launcher/commands/links.sh) and the bar's agent
# peek (bar/…/agents.sh). Under zellij they all called
# `zellij action dump-screen`; the replacement is `zmx history` / `zmx tail`,
# and that only exists if the window's shell is INSIDE a session. So the session
# is the read API, exactly as it is for a lane — see notes/zellij-exit.md.
#
# ── the name, and why it is recycled ─────────────────────────────────────────
# `term.<n>`, lowest free n. "Free" means the session does not exist, or exists
# with `clients=0` — i.e. it was left behind by a closed window or a Ghostty
# quit. So reopening Ghostty walks back into the shells you had, in order, and
# closing a window parks its scrollback rather than burning it. Sessions whose
# name is not `term.*` are never touched: `holt.*` lanes belong to lane-open.sh
# and an `zmx attach` you typed yourself belongs to you.
set -u

export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"
export SHELL="/bin/zsh"

LOG=/tmp/haus-term-launch.log

log() { echo "[$(date '+%H:%M:%S')] $*" >>"$LOG"; }

log "---- launch ----"

run_shell() {
    log "→ exec /bin/zsh -l"
    exec /bin/zsh -l
}

# Guard: already inside a session (a nested ghostty, or a lane's own window),
# or the user opted out for this window.
if [ -n "${ZMX_SESSION:-}" ] || [ "${HAUS_NO_ZMX:-}" = "1" ]; then
    log "guard: nested or opted-out"
    run_shell
fi

# Quick-terminal detection (best-effort, ~100ms cost): the dropdown is a
# scratch surface, not a pane anything reads, so it stays a plain shell.
title=$(/usr/bin/osascript -e 'tell application "System Events" to tell (first process whose frontmost is true) to get title of front window' 2>>"$LOG" || true)
if [[ "${title}" == *quick-terminal* ]]; then
    log "guard: quick-terminal"
    run_shell
fi

# Which window backend this machine has — see lanes/lane-open.sh for the two
# and why they can't be mixed. HAUS_WINDOW_BACKEND forces one, so a machine
# that has a tiler can feel-test the path a machine without one takes.
BACKEND="${HAUS_WINDOW_BACKEND:-}"
if [ -z "$BACKEND" ]; then
    # The literal path is not belt-and-braces, it is the load-bearing half.
    # This script's PATH (line above) is whatever the window inherited, and a
    # Ghostty launched from the Dock or at login inherits launchd's — which on
    # this machine is empty, leaving `/usr/bin:/bin:/usr/sbin:/sbin`. AeroSpace
    # is a cask and lives ONLY at /opt/homebrew/bin, which is exactly why the
    # subshell below prepends it and every sibling script bakes it into its own
    # PATH. `command -v` alone would answer "no tiler" for a window opened one
    # way and "tiler" for the same window opened another, on the same machine,
    # and the two answers stamp DIFFERENT labels — so every plain window from
    # the unlucky half would resolve to no session at all.
    if command -v aerospace >/dev/null 2>&1 || [ -x /opt/homebrew/bin/aerospace ]; then
        BACKEND=aerospace
    else
        BACKEND=ghostty
    fi
fi
log "window backend: $BACKEND"

command -v zmx >/dev/null 2>&1 || {
    log "no zmx on PATH — plain shell"
    run_shell
}

# ── claiming a name ──────────────────────────────────────────────────────────
# Two windows opened in the same breath (⌘N twice, or a restored Ghostty
# session) would both read the same `zmx ls` and both pick term.1, and the
# second `attach` would then land a second client on the first one's session.
# mkdir is the mutex — atomic on every filesystem, no flock (macOS /bin has
# none), and self-healing because a stale lock older than a few seconds is
# simply removed.
lockdir="${TMPDIR:-/tmp}/haus-term-claim.lock"
tries=0
until /bin/mkdir "$lockdir" 2>/dev/null; do
    tries=$((tries + 1))
    # ~1s is an order of magnitude more than the one `zmx ls` below can take,
    # so a lock still held here is a crashed claim, not a slow one. Break it
    # and carry on: a duplicated claim costs one extra client on one session,
    # a deadlocked launcher costs the window.
    if [ "$tries" -ge 20 ]; then
        log "claim lock looked stale after ${tries} tries — breaking it"
        /bin/rmdir "$lockdir" 2>/dev/null
        tries=0
    fi
    sleep 0.05
done

# `clients=N` is a field zmx keeps itself (see `zmx ls`), so "is a window
# already looking at this" needs no bookkeeping of ours.
busy=$(zmx ls 2>/dev/null | awk -F'\t' '
  {
    name = ""; clients = ""
    for (i = 1; i <= NF; i++) {
      p = index($i, "=")
      if (p == 0) continue
      k = substr($i, 1, p - 1); gsub(/^[ \t]+|[ \t]+$/, "", k)
      # zmx marks the row you are ATTACHED to in its first field
      # ("-> ** name=..."), gluing the marker onto that key. Strip
      # anything before the key proper or the session you are
      # sitting in is the one row that never matches.
      sub(/^[^A-Za-z_]*/, "", k)
      if (k == "name")    name    = substr($i, p + 1)
      if (k == "clients") clients = substr($i, p + 1)
    }
    if (name ~ /^term\./ && clients != "0") print substr(name, 6)
  }')

n=1
while printf '%s\n' "$busy" | grep -qx "$n"; do
    n=$((n + 1))
done
SESSION="term.$n"
log "claimed $SESSION (busy: $(printf '%s' "$busy" | tr '\n' ' '))"

# The lock is released before the attach, not after: attach does not return
# until the window closes, and holding a global mutex for the life of a window
# would serialise every terminal on the machine down to one.
/bin/rmdir "$lockdir" 2>/dev/null

# This is a regular terminal window. windows floats every runtime ghostty
# window (see windows/aerospace.toml — popups must never be tiled, and title
# rules race detection), so tile ourselves onto workspace T. From in here the
# window certainly exists, and it has focus (it was just opened by the user),
# so targeting the focused window is race-free in practice.
#
# The same block stamps this window's id onto the session, because it is the
# one place that knows both halves. That label is the join
# scripts/focused-session.sh uses for every window that is NOT a lane: a lane
# carries its own identity (a forced title, or the id lanes/lane-open.sh
# stamps), and a plain window's title is whatever the program inside emits.
#
# WHICH id depends on the backend, exactly as it does for a lane — see
# lanes/lane-open.sh for the measurement behind the split:
#
#   aerospace   window=<aerospace id>, and the window is tiled onto T.
#   ghostty     gwindow=<ghostty id>, over Ghostty's own AppleScript API, on a
#               machine with no tiler at all. macOS placed the window; there is
#               nothing to tile it onto.
#
# Only ever ONE of the two, never both: the ids live in different spaces, and a
# label stamped from the wrong backend is a join that resolves confidently to
# the wrong window.
(
    export PATH="/opt/homebrew/bin:$PATH"

    LABEL=""
    if [ "$BACKEND" = aerospace ]; then
        WID=""
        for _ in $(seq 1 20); do
            WID=$(aerospace list-windows --focused --format '%{window-id}' 2>/dev/null)
            [ -n "$WID" ] && break
            sleep 0.05
        done
        if [ -n "$WID" ]; then
            aerospace move-node-to-workspace --window-id "$WID" T 2>>"$LOG"
            aerospace layout --window-id "$WID" tiling 2>>"$LOG"
            log "self-tiled window $WID onto workspace T"
            LABEL="window=$WID"
        else
            log "self-tile: no focused window found"
        fi
    else
        # `front window` rather than "the window this process is in", because
        # Ghostty exposes no such thing — the same assumption the tiler branch
        # makes, and true for the same reason: this window was just opened and
        # has focus. Costs ~150 ms, which is why it is HERE, in a backgrounded
        # subshell, and never on a keystroke path.
        #
        # Polled like the tiler branch, and for the weaker half of the same
        # reason: an empty answer (Ghostty still coming up, no window yet) is
        # worth waiting out. The stronger half it CANNOT reproduce is
        # new-window.sh's before/after check — there is no "before" from in
        # here — so a non-empty answer is trusted. That is only wrong if
        # another Ghostty window took front in the milliseconds since this one
        # opened, which on this backend means the user clicked away in that
        # window; the cost is one plain window whose chords answer for its
        # neighbour until the next attach re-stamps it.
        for _ in $(seq 1 20); do
            GWID=$(/usr/bin/osascript -e 'tell application "Ghostty" to return id of front window' 2>>"$LOG")
            [ -n "$GWID" ] && break
            sleep 0.05
        done
        if [ -n "$GWID" ]; then
            log "ghostty window id $GWID"
            LABEL="gwindow=$GWID"
        else
            log "no ghostty window id — this window has no label join"
        fi
    fi

    # The session may not exist for another few milliseconds — `zmx attach`
    # below is racing this subshell. Retry briefly rather than order the two,
    # because holding the window untiled until the session is up is the more
    # visible failure.
    if [ -n "$LABEL" ]; then
        for _ in $(seq 1 40); do
            zmx set "$SESSION" "$LABEL" >/dev/null 2>&1 && break
            sleep 0.05
        done
    fi
) &

# `zmx attach` creates the session if it isn't there and re-attaches if it is,
# so "restore" and "new" are the same call. No trailing command: we want the
# session's own login shell, which is $SHELL above.
zmx attach "$SESSION" 2> >(tee -a "$LOG" >&2)
rc=$?
log "zmx exited with code $rc"

# ── one ^D, not two ──────────────────────────────────────────────────────────
# A clean exit ends the WINDOW. `zmx attach <name>` with no trailing command
# returns 0 whenever the session is over — a detach, the shell exiting, and
# (measured 2026-08-19) whatever the shell exited WITH: `exit 7` inside the
# session still comes back 0 out here, because the code being read is zmx's
# own, not the shell's. So 0 means "the session is over" and nothing else, and
# the honest answer to that is to end this process too and let ghostty close
# the surface.
#
# This fell through to `run_shell` unconditionally until 2026-08-19, and that
# is what put TWO shells in every window: ^D ended the session and landed you
# in a sessionless login zsh that needed a SECOND ^D to close the window. The
# fallback is still here for the case it was actually written for — a non-zero
# rc is zmx failing rather than a session ending, and a window that vanishes
# takes the error with it — but only a failure reaches it now. Even then the
# screen is not the only copy: zmx's stderr is tee'd to $LOG above.
#
# A lane window has answered this way since it existed (lanes/lane-open.sh
# execs `zmx attach` and holds only on a non-zero rc). Same rule, same reason.
[ "$rc" -eq 0 ] && exit 0
run_shell

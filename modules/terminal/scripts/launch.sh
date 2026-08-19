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
# The same block stamps the window id onto the session as a `window=` label,
# because it is the one place that knows both halves. That label is the join
# scripts/focused-session.sh uses for every window that is NOT a lane: a lane's
# window carries the session name as a forced title, and a plain window's title
# is whatever the program inside emits.
(
    export PATH="/opt/homebrew/bin:$PATH"
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
        # The session may not exist for another few milliseconds — `zmx attach`
        # below is racing this subshell. Retry briefly rather than order the two,
        # because holding the window untiled until the session is up is the more
        # visible failure.
        for _ in $(seq 1 40); do
            zmx set "$SESSION" "window=$WID" >/dev/null 2>&1 && break
            sleep 0.05
        done
    else
        log "self-tile: no focused window found"
    fi
) &

# `zmx attach` creates the session if it isn't there and re-attaches if it is,
# so "restore" and "new" are the same call. No trailing command: we want the
# session's own login shell, which is $SHELL above.
zmx attach "$SESSION" 2> >(tee -a "$LOG" >&2)
log "zmx exited with code $?"

# zmx has exited (detach, the shell exited, or an error) — fall back to a plain
# shell so the ghostty window stays open rather than vanishing with the
# evidence.
run_shell

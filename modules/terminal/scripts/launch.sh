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
# is the read API, exactly as it is for a lane.
#
# ── the name ─────────────────────────────────────────────────────────────────
# `term.<n>`, lowest n that no session holds. A NEW window is always a new
# shell: closing a window parks its session rather than burning it, and a parked
# session is a live shell in some directory of its own, so handing one to the
# next ⌘N would break the only thing ⌘N promises. Walking back into a parked
# shell is `scripts/restore-windows.sh`'s job — automatic for the first window
# of a Ghostty, on demand from the palette — and the bar's, and ⌘F's, and the
# Lanes picker's. Sessions whose name is not `term.*` are never claimed here:
# `holt.*` lanes belong to lane-open.sh and a `zmx attach` you typed yourself
# belongs to you.
#
# So the pair to have in the fingers is ⌃D vs ⌘W. ⌃D ends the shell, which ends
# the session and frees its number; ⌘W closes the window and keeps everything
# running, to be handed back the next time Ghostty starts.
set -u

export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"
export SHELL="/bin/zsh"

# ── where this window belongs ────────────────────────────────────────────────
# A spawn chord that KNOWS says so here: launcher/commands/shell-here.sh (⌘N /
# ⌘⇧N) passes the lane page it was pressed on, so a shell asked for on
# `T/<repo>` opens beside that lane rather than on the shared T. Everything
# else passes nothing and means T — the Dock, a launcher letter, the restore
# fan-out, and ⌘N pressed on T itself.
#
# Read into a variable and dropped from the environment in the same breath,
# before any of the guards below can `exec` a shell: every path out of this
# file ends in a shell that would otherwise carry one page's name into
# everything it ever spawns. Same reason HAUS_ZMX_ATTACH is unset further
# down, taken one step earlier because this one has no branch that wants it.
WANT_WS="${HAUS_TERM_WORKSPACE:-}"
unset HAUS_TERM_WORKSPACE

# ── and whether to take the user WITH it ─────────────────────────────────────
# A move that leaves you behind is the right default and a deliberate one: it is
# what keeps ⌘N from ever moving the screen under you (the T branch below says
# so). But a chord whose whole point is "put me somewhere else" — ⌘T's neutral
# terminal, launcher/commands/shell-plain.sh — needs the other half, and it
# cannot do the move itself: the window is born on the page the chord was
# pressed on, and only this script, from inside it, knows with certainty which
# window it is.
#
# So the spawner says. Read and dropped in the same breath as the workspace name
# above, for the same reason — every path out of this file ends in a shell that
# would otherwise carry one chord's intent into everything it spawns.
WANT_FOLLOW="${HAUS_TERM_FOLLOW:-}"
unset HAUS_TERM_FOLLOW

LOG=/tmp/haus-term-launch.log

# Where the self-tile subshell leaves this window's AeroSpace id (and the pid of
# the ghostty that owns it) for the exit path at the bottom of the file to read.
# A FILE and not a variable because the id is worked out in a BACKGROUND
# subshell — it has ~1 s of polling to do and a window not to hold up — and a
# subshell cannot write back to its parent's environment.
#
# TRUNCATED on the way in, and that is the load-bearing line rather than
# tidiness. Neither of the two commonest exits removes it: ⌘W and ⌘Q both SIGHUP
# this script mid-`zmx attach`, so the `rm -f`s below never run and `$TMPDIR`
# keeps the file for days while pids wrap at 99999. A later window that inherits
# the pid AND fails its own self-tile (the "could not tell which window this is"
# branch, which writes nothing) would otherwise read a DEAD window's id out of
# it. Emptying it here means the worst that file can ever say is nothing.
WINFILE="${TMPDIR:-/tmp}/haus-term-win.$$"
: >"$WINFILE"

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

# ── which session this window is ─────────────────────────────────────────────
# Two answers, and they are different acts on purpose.
#
#   HAUS_ZMX_ATTACH=<name>   attach to THAT session, whatever its number. Set by
#                            scripts/restore-windows.sh, which is the ONLY thing
#                            that reattaches a session to a new window.
#   unset                    a name NOBODY holds: the lowest `term.<n>` that
#                            does not exist at all.
#
# That second rule used to read "the lowest n that is not ATTACHED", which
# silently made every new window a lottery: a `term.<n>` left behind by a closed
# window is a live shell sitting in some other directory, so ⌘N — whose entire
# promise is "a shell HERE" — would drop you into an old one somewhere else,
# with its scrollback and its cwd, roughly as often as you had parked a window.
# A new window is now always a new shell. Getting an old one back is the restore
# path's job, and the bar's, and the Lanes picker's — never a spawn chord's.
if [ -n "${HAUS_ZMX_ATTACH:-}" ]; then
    SESSION="$HAUS_ZMX_ATTACH"
    log "explicit attach: $SESSION"
else
    # Two windows opened in the same breath (⌘N twice, or the restore fan-out)
    # would both read the same `zmx ls` and both pick term.1, and the second
    # `attach` would then land a second client on the first one's session. mkdir
    # is the mutex — atomic on every filesystem, no flock (macOS /bin has none),
    # and self-healing because a stale lock is simply removed.
    lockdir="${TMPDIR:-/tmp}/haus-term-claim.lock"
    tries=0
    until /bin/mkdir "$lockdir" 2>/dev/null; do
        tries=$((tries + 1))
        # ~1s is an order of magnitude more than the one `zmx ls` below can
        # take, so a lock still held here is a crashed claim, not a slow one.
        # Break it and carry on: a duplicated claim costs one extra client on
        # one session, a deadlocked launcher costs the window.
        if [ "$tries" -ge 20 ]; then
            log "claim lock looked stale after ${tries} tries — breaking it"
            /bin/rmdir "$lockdir" 2>/dev/null
            tries=0
        fi
        sleep 0.05
    done

    # `clients=N` is a field zmx keeps itself, so "is a window already looking
    # at this" needs no bookkeeping of ours. One pass, three answers: every
    # `term.<n>` that EXISTS (what a new name must avoid), whether anything at
    # all is attached (are we the first window of this Ghostty), and the
    # detached sessions in name order (what restore has to reopen).
    sessions=$(zmx ls 2>/dev/null | awk -F'\t' '
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
        if (name != "") print name "\t" (clients == "" ? "0" : clients)
      }')

    taken=$(printf '%s\n' "$sessions" | awk -F'\t' '$1 ~ /^term\./ { print substr($1, 6) }')
    n=1
    while printf '%s\n' "$taken" | grep -qx "$n"; do
        n=$((n + 1))
    done
    SESSION="term.$n"

    # ── restoring the desk ───────────────────────────────────────────────────
    # A window looks like the FIRST of this Ghostty when nothing is attached
    # anywhere: every other window would be a client on some session, and this
    # one has not attached yet. So a ⌘Q (or a crash, or a logout that left the
    # daemon up) followed by opening Ghostty lands exactly here, with every
    # session it left behind sitting parked — and that is the one moment "put my
    # windows back" is what was meant. Opening a SECOND window is never that,
    # which is why this cannot live in the spawn chords.
    #
    # "Looks like" is doing real work in that sentence, and the marker below is
    # what makes it safe. This window does not become a client until `zmx
    # attach` at the very bottom of the file, long after it has to decide — so a
    # second window opened in the same breath (a double Dock click, two `open -a
    # Ghostty`) reads the same "nothing attached", adopts the same session and
    # fans out a second time. The marker is held across the whole fan-out by
    # restore-windows.sh, which owns releasing it; taking it HERE rather than
    # there is what also makes the adopt single, since the adopt is half of the
    # same act.
    #
    # This window adopts the first parked `term.<n>` itself rather than opening
    # a fresh session beside the restored ones, or you would come back to your
    # desk plus one empty window on top of it.
    parked_ours=$(printf '%s\n' "$sessions" |
        awk -F'\t' '$2 == "0" && ($1 ~ /^term\./ || $1 ~ /^scruff\./)' | grep -c .)
    if [ "@restore@" = 1 ] &&
       [ "$parked_ours" -gt 0 ] &&
       ! printf '%s\n' "$sessions" | awk -F'\t' '$2 != "0"' | grep -q . &&
       /bin/mkdir "${TMPDIR:-/tmp}/haus-term-restoring" 2>/dev/null; then
        adopt=$(printf '%s\n' "$sessions" |
            awk -F'\t' '$2 == "0" && $1 ~ /^term\./ { print substr($1, 6) }' | sort -n | head -1)
        if [ -n "$adopt" ]; then
            SESSION="term.$adopt"
            log "restore: adopting $SESSION"
        fi
        # The rest, in the background: this script has a window to attach.
        # --except keeps the fan-out from opening a second window onto the
        # session we are about to sit in. HAUS_RESTORE_LOCK hands over the
        # marker, including the job of removing it.
        HAUS_RESTORE_LOCK="${TMPDIR:-/tmp}/haus-term-restoring" \
            "$HOME/.config/haus/term/restore-windows.sh" --except "$SESSION" \
            </dev/null >>"$LOG" 2>&1 &
    fi

    log "claimed $SESSION (existing: $(printf '%s' "$taken" | tr '\n' ' '))"

    # The lock is released before the attach, not after: attach does not return
    # until the window closes, and holding a global mutex for the life of a
    # window would serialise every terminal on the machine down to one.
    /bin/rmdir "$lockdir" 2>/dev/null
fi

# This is a regular terminal window. windows floats every runtime ghostty
# window (see windows/aerospace.toml — popups must never be tiled, and title
# rules race detection), so tile ourselves onto workspace T — or onto the lane
# page the spawn chord named in WANT_WS. From in here the
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
#   aerospace   window=<aerospace id>, and the window is tiled onto T (or onto
#               the page it was asked for).
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
        # Which Ghostty process owns this window — walked up from here, because
        # this script IS the window's command and that process is its ancestor.
        # It is the only half of "which window am I in" that cannot race:
        # AeroSpace hands out focus on its own schedule, and a bare
        # `list-windows --focused` poll cannot wait for the right answer because
        # SOME window is always focused, so it returns whatever you were
        # standing in a moment ago. Believing that costs two things at once —
        # this window stays FLOATING at whatever size the last one had (windows
        # floats every runtime Ghostty window; the line below is the only thing
        # that ever un-floats it), and the `window=` label that every
        # window→session join reads gets stamped with a NEIGHBOUR's id, so ⌘F,
        # ⌘Y and ⌘↵'s cwd all answer for the wrong window. Same bug, same day,
        # as lanes/lane-open.sh's self-tile.
        #
        # Focus is still how the WINDOW is picked, because a plain window is
        # opened through Ghostty's AppleScript API into an instance that may
        # already have others (lanes/lane-open.sh explains why lanes get their
        # own process and these do not) — the pid narrows it to "ours", not to
        # "this one". So the poll now waits for a focused window that belongs to
        # our own process, and only falls back to the pid alone when that
        # instance turns out to have exactly one window anyway.
        gpid=""; p=$$
        while [ -n "$p" ] && [ "$p" != 1 ]; do
            case "$(ps -o comm= -p "$p" 2>/dev/null)" in
                # Both spellings — the executable inside the bundle is
                # lowercase, but `pgrep -x Ghostty` not matching it is a bug
                # this room has already shipped once (lanes/lane-open.sh's
                # cold-start note), and here the only symptom would be a window
                # that quietly never tiles.
                *ghostty|*Ghostty) gpid="$p"; break ;;
            esac
            p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
        done

        WID=""
        for _ in $(seq 1 20); do
            focused=$(aerospace list-windows --focused --format '%{window-id}|%{app-pid}' 2>/dev/null)
            if [ -n "$focused" ]; then
                if [ -z "$gpid" ] || [ "${focused#*|}" = "$gpid" ]; then
                    WID="${focused%%|*}"
                    break
                fi
            fi
            sleep 0.05
        done
        if [ -z "$WID" ] && [ -n "$gpid" ]; then
            mine=$(aerospace list-windows --monitor all --pid "$gpid" --format '%{window-id}' 2>/dev/null)
            [ "$(printf '%s\n' "$mine" | grep -c .)" = 1 ] && WID="$mine"
            [ -n "$WID" ] && log "self-tile: focus never landed here, took our process's only window $WID"
        fi
        if [ -n "$WID" ]; then
            # WHICH workspace — T, or the page WANT_WS named at the top of this
            # file. Two things are asked before anything moves: where this
            # window already is, and whether the named workspace is real.
            #
            # The name is CHECKED rather than trusted, because an unknown one is
            # not an error to AeroSpace — it CREATES that workspace and moves
            # the window there — and a page is deliberately not persistent, so a
            # page that evaporated between the chord and here would strand this
            # window where nothing can see it. `--monitor all` lists the
            # persistent workspaces plus every non-persistent one holding a
            # window, which is the same call and the same rule as
            # windows/scripts/workspace-mru.sh's page test. Only the CALLER
            # decides that a name is a page; anything live is honoured here.
            CUR="$(aerospace list-windows --monitor all --format '%{window-id}|%{workspace}' 2>/dev/null |
                     awk -F'|' -v w="$WID" '$1 == w { print $2; exit }')"
            WS=T
            if [ -n "$WANT_WS" ] &&
               { [ "$WANT_WS" = "$CUR" ] ||
                 aerospace list-workspaces --monitor all 2>/dev/null | grep -qxF "$WANT_WS"; }; then
                WS="$WANT_WS"
            fi

            if [ "$WS" = "$CUR" ]; then
                # Already home — and this is the NORMAL path for a page, since
                # the tiler drops a new window on the workspace that was focused
                # when it was born. Saying nothing is the point: the move below
                # is the only thing that could take you somewhere, so not making
                # it is what keeps ⌘N from ever moving the screen under you.
                log "self-tile: window $WID is already on $CUR"
            elif [ "$WS" = T ]; then
                # Un-followed, unless the spawner asked otherwise: a plain shell
                # window sent home to T must not drag you off the page you are
                # reading. HAUS_TERM_FOLLOW is the one caller that means the
                # opposite — see the note at the top of this file.
                if [ -n "$WANT_FOLLOW" ]; then
                    aerospace move-node-to-workspace --focus-follows-window \
                        --window-id "$WID" T 2>>"$LOG"
                else
                    aerospace move-node-to-workspace --window-id "$WID" T 2>>"$LOG"
                fi
            else
                # A page, and the window is NOT on it: the workspace changed in
                # the beat between the chord and this subshell. Follow the
                # window, the way lanes/lane-open.sh does — a window that
                # silently leaves for a page you are not looking at is worse
                # than one that takes you with it, and you did ask for it there.
                aerospace move-node-to-workspace --focus-follows-window \
                    --window-id "$WID" "$WS" 2>>"$LOG"
            fi
            aerospace layout --window-id "$WID" tiling 2>>"$LOG"
            log "self-tiled window $WID onto workspace $WS"
            LABEL="window=$WID"
            # And the same id to the exit path — see "closing our own window"
            # at the bottom. Written only on the branch that TILED, because
            # that is the only branch whose window ghostty then fails to close.
            # The ghostty pid rides along: it is what tells that path the id
            # still belongs to OUR instance rather than some other window a
            # reused number now names.
            printf '%s %s\n' "$WID" "$gpid" >"$WINFILE"
        else
            log "self-tile: could not tell which window this is — left floating, unlabelled"
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
#
# HAUS_ZMX_ATTACH is dropped first, and that is not tidiness. Attaching to a
# session that still exists never runs a shell, so the variable goes nowhere —
# but a session that DIED between the restore listing it and this line is
# created here instead, and its brand-new login shell would inherit the name of
# the session it is supposed to be. From that shell, anything that spawns a
# Ghostty inheriting the environment would put every window it opened onto that
# one session.
unset HAUS_ZMX_ATTACH
zmx attach "$SESSION" 2> >(tee -a "$LOG" >&2)
rc=$?
log "zmx exited with code $rc"

# ── one ^D, not two ──────────────────────────────────────────────────────────
# A clean exit ends the WINDOW. `zmx attach <name>` with no trailing command
# returns 0 whenever the session is over — a detach, the shell exiting, and
# (measured 2026-08-19) whatever the shell exited WITH: `exit 7` inside the
# session still comes back 0 out here, because the code being read is zmx's
# own, not the shell's. So 0 means "the session is over" and nothing else, and
# the honest answer to that is to end this process too — and then to close the
# window, which ghostty turns out not to do for us (next block).
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
#
# ── closing our own window ───────────────────────────────────────────────────
# …because exiting is not enough, and that is a MEASURED ghostty behaviour
# rather than a guess (2026-08-23, ghostty 1.3.1). `wait-after-command` is off,
# so `Surface.childExited` prints "Process exited. Press any key to close the
# terminal." and then calls `close()` — but for a window that AeroSpace has
# TILED, inside a ghostty instance that owns other windows, that close never
# lands. The window sits on the message until a keypress, which reaches the
# very same `close()` through the key path and works. A/B, one variable at a
# time, same instance, same script:
#
#   no AeroSpace call at all              → closes
#   moved to another workspace, floating  → closes
#   moved and tiled                       → HELD
#   tiled in place                        → HELD
#   moved and tiled, but `open -na` into  → closes (the instance QUITS, which
#   its own ghostty instance                takes the window with it)
#
# That last row is why lanes never had this: lanes/lane-open.sh spawns a
# dedicated instance, so `quit-after-last-window-closed` ends the process and
# the broken close is invisible. A ⌘N window shares an instance and has no such
# cover — and every window that reaches the self-tile above is tiled (the
# nested, opted-out and quick-terminal guards exec before it, and those windows
# are floating and close fine), so every ordinary one of them was asking for a
# keypress it never should have needed.
#
# So we close it ourselves. `aerospace close` on the id the self-tile already
# worked out, which is the same id the `window=` label joins on, and the same
# id the tiler was trusted with a moment ago.
#
# THREE signals have to agree before anything closes, because that id is not
# certain: the self-tile poll can answer for a SIBLING (the restore fan-out
# opens several windows in one breath, and AeroSpace hands out focus on its own
# schedule), which today costs a mis-tile and must never come to cost a
# mis-close.
#
#   the id       what the self-tile wrote, and only that branch writes
#   the owner    that window still belongs to the ghostty process we live in.
#                Kills the whole cross-instance half of the risk in one line —
#                every LANE is its own ghostty, so no answer here can ever
#                close one, whatever the number says
#   the focus    AeroSpace says that window is focused right now
#
# The focus test is the weakest of the three and is deliberately not asked to
# carry the argument alone. It is exact for a ^D — you typed it in the window
# that had focus — but `zmx attach` also returns 0 for a `zmx kill` fired from
# the bar or the Lanes picker, and for a script inside the session calling
# `exit`, and in those the focus can honestly be somewhere else. Then the
# agreement fails and this does nothing: the window keeps ghostty's message and
# the keypress it asks for, which is exactly where it was before this block.
close_own_window() {
    [ -s "$WINFILE" ] || return 0
    local wid gpid as owner focused
    read -r wid gpid <"$WINFILE" || return 0
    [ -n "$wid" ] && [ -n "$gpid" ] || return 0

    # The literal path for the same reason the backend probe above uses one: a
    # Ghostty opened from the Dock inherits launchd's PATH, and aerospace is a
    # cask that lives only under /opt/homebrew.
    as=$(command -v aerospace 2>/dev/null)
    [ -n "$as" ] || as=/opt/homebrew/bin/aerospace
    [ -x "$as" ] || return 0

    owner=$("$as" list-windows --monitor all --format '%{window-id}|%{app-pid}' 2>/dev/null |
        awk -F'|' -v w="$wid" '$1 == w { print $2; exit }')
    if [ "$owner" != "$gpid" ]; then
        log "not closing: window $wid belongs to ${owner:-nothing} now, not our ghostty $gpid"
        return 0
    fi

    focused=$("$as" list-windows --focused --format '%{window-id}' 2>/dev/null)
    if [ "$focused" != "$wid" ]; then
        log "not closing: window $wid is not the focused one (${focused:-none})"
        return 0
    fi

    log "closing our own window $wid"
    "$as" close --window-id "$wid" 2>>"$LOG"
}

if [ "$rc" -eq 0 ]; then
    close_own_window
    rm -f "$WINFILE"
    exit 0
fi
rm -f "$WINFILE"
run_shell

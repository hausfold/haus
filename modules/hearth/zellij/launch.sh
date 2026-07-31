#!/bin/bash
# Ghostty → zellij launcher. Configured as ghostty's `command`.
# Debug log: /tmp/zellij-launch.log
set -u

# ghostty is launched by macOS launchd, which hands us a minimal PATH
# (/etc/paths contents only — no nix profile dirs). Prepend the nix paths
# so the nix-managed zellij always wins, even if a stray /usr/local/bin
# binary exists. Also set SHELL so zellij spawns the right shell.
export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"
export SHELL="/bin/zsh"

LOG=/tmp/zellij-launch.log
SESSION="main"

log() { echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }

log "---- launch ----"

run_shell() {
    log "→ exec /bin/zsh -l"
    exec /bin/zsh -l
}

# Guard: already inside zellij, or user opted out.
if [ -n "${ZELLIJ:-}" ] || [ "${NO_ZELLIJ:-}" = "1" ]; then
    log "guard: nested or opted-out"
    run_shell
fi

# Quick-terminal detection (best-effort, ~100ms cost). Skip if you don't care.
title=$(/usr/bin/osascript -e 'tell application "System Events" to tell (first process whose frontmost is true) to get title of front window' 2>>"$LOG" || true)
if [[ "${title}" == *quick-terminal* ]]; then
    log "guard: quick-terminal"
    run_shell
fi

# This is a regular terminal window. Aerospace floats every runtime ghostty
# window (see prowl/aerospace.toml — popups must never be tiled, and title
# rules race detection), so tile ourselves onto workspace T. From in here the
# window certainly exists, and it has focus (it was just opened by the user),
# so targeting the focused window is race-free in practice.
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
    else
        log "self-tile: no focused window found"
    fi
) &

# Session policy: a normal launch attaches/creates `main`. After `zreload`, the
# external reload agent has already quit the OLD Ghostty process and deleted the
# zellij server; this newly-started launcher sees the request BEFORE a normal
# attach can accidentally create a blank session, and becomes the layout owner.
if command -v zellij >/dev/null 2>&1; then
    log "zellij=$(command -v zellij) version=$(zellij --version 2>&1) PATH=$PATH"
    reload_dir="$HOME/Library/Caches/org.nebelhaus.zellij-reload/$SESSION"
    request="$reload_dir/request"
    generation_file="$reload_dir/generation"
    manifest="$reload_dir/claude-panes.tsv"
    restart_roles="$reload_dir/restart-pane-roles.json"
    mkdir -p "$reload_dir"

    new_generation() {
        NEBELHAUS_ZELLIJ_GENERATION="$(date +%s)-$$-$RANDOM"
        export NEBELHAUS_ZELLIJ_GENERATION
        printf '%s\n' "$NEBELHAUS_ZELLIJ_GENERATION" >"${generation_file}.tmp"
        mv -f "${generation_file}.tmp" "$generation_file"
        rm -f "$manifest"
    }

    load_generation() {
        if [ -f "$generation_file" ]; then
            NEBELHAUS_ZELLIJ_GENERATION=$(cat "$generation_file")
            export NEBELHAUS_ZELLIJ_GENERATION
        fi
    }

    # Pair the recreated server's new pane ids with the restart roles in their
    # shared deterministic pane order. This is the durable identity source for
    # the next reload even while Claude's foreground process is an LSP/tool.
    write_claude_manifest() {
        [ -f "$restart_roles" ] || return 1
        panes_tmp="${manifest}.panes.$$"
        manifest_tmp="${manifest}.tmp.$$"
        zellij --session "$SESSION" action list-panes --all --json >"$panes_tmp" \
            || { rm -f "$panes_tmp"; return 1; }
        if jq -r --arg generation "$NEBELHAUS_ZELLIJ_GENERATION" \
          --slurpfile roles "$restart_roles" '
            ([.[] | select(.is_plugin == false)]) as $panes
            | ($roles[0]) as $roles
            | if ($panes | length) != ($roles | length)
              then error("pane/role count mismatch")
              else
                range(0; $roles | length) as $i
                | select($roles[$i].kind == "claude")
                | "\($generation)\t\($panes[$i].id)\t\($roles[$i].uuid)"
              end
          ' "$panes_tmp" >"$manifest_tmp"; then
            mv -f "$manifest_tmp" "$manifest"
            rm -f "$panes_tmp"
            log "reload: recorded Claude pane manifest"
            return 0
        fi
        rm -f "$panes_tmp" "$manifest_tmp" "$manifest"
        return 1
    }

    if [ -f "$request" ]; then
        # A macOS app restore can theoretically open more than one window.
        # Exactly one launcher creates the session; any siblings wait/attach.
        if mkdir "$reload_dir/claim" 2>/dev/null; then
            layout=$(cat "$request")
            if [ -f "$layout" ]; then
                log "reload: creating fresh '$SESSION' from $layout"
                new_generation
                (
                    for _ in $(seq 1 100); do
                        if zellij list-sessions --no-formatting 2>/dev/null \
                            | grep -Eq "^${SESSION}( |$)"; then
                            manifest_ready=0
                            for _manifest_try in $(seq 1 100); do
                                if write_claude_manifest; then
                                    manifest_ready=1
                                    break
                                fi
                                sleep 0.05
                            done
                            if [ "$manifest_ready" = 0 ]; then
                                log "reload: could not record Claude pane manifest; future reloads will fail safe"
                            fi
                            # Give every client disconnected from the old
                            # server time to observe the marker and join the
                            # follower path before making it disappear.
                            sleep 1
                            rm -f "$request"
                            rmdir "$reload_dir/claim" 2>/dev/null || true
                            exit 0
                        fi
                        sleep 0.05
                    done
                ) &
                zellij -s "$SESSION" -n "$layout" 2> >(tee -a "$LOG" >&2)
                log "reloaded zellij exited with code $?"
            else
                log "reload: requested layout is missing: $layout"
            fi
            rm -f "$request"
            rmdir "$reload_dir/claim" 2>/dev/null || true
        else
            log "reload: another client is creating '$SESSION'; waiting"
            load_generation
            for _ in $(seq 1 100); do
                if zellij list-sessions --no-formatting 2>/dev/null \
                    | grep -Eq "^${SESSION}( |$)"; then
                    zellij attach "$SESSION" 2> >(tee -a "$LOG" >&2)
                    break
                fi
                sleep 0.05
            done
        fi
    else
        if zellij list-sessions --no-formatting 2>/dev/null \
            | grep -Eq "^${SESSION}( |$)"; then
            load_generation
        else
            # This is a brand-new ordinary session, not a reload. Give every
            # pane a generation token so claude-statusline can publish mappings
            # that cannot collide with reused pane ids from an older server.
            new_generation
        fi
        log "attach-or-create '${SESSION}'"
        zellij attach --create "${SESSION}" 2> >(tee -a "$LOG" >&2)
        log "zellij exited with code $?"
    fi
fi

# zellij has exited (detach, normal close, or error) — fall back to a plain
# shell so the ghostty window stays open. User can re-launch zellij or quit.
run_shell

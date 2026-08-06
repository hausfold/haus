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

# Session policy: attach to `main`, or create it. There is no reload path to
# arbitrate any more. A rebuild's config.kdl is INSTALLED with a live mtime
# (hearth's zellijLiveConfig activation), so zellij's own watcher applies the new
# keybinds/theme/options to the running server within a second and the session
# never needs recreating — which is what the deleted zreload branch here existed
# to do, badly. Plugin wasm and the zellij binary itself still need a fresh
# server; that is `zscratch`'s job, in a throwaway window, and it never comes
# through this launcher.
if command -v zellij >/dev/null 2>&1; then
    log "zellij=$(command -v zellij) version=$(zellij --version 2>&1) PATH=$PATH"
    log "attach-or-create '${SESSION}'"
    zellij attach --create "${SESSION}" 2> >(tee -a "$LOG" >&2)
    log "zellij exited with code $?"
fi

# zellij has exited (detach, normal close, or error) — fall back to a plain
# shell so the ghostty window stays open. User can re-launch zellij or quit.
run_shell

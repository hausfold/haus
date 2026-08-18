#!/bin/bash
# peek-run.sh — runs INSIDE the peek ghostty instance (spawned by peek.sh).
#
# Single-shot: run yazi once against the passed cwd, and when yazi quits
# (q/Esc) exit so Ghostty closes the window (wait-after-command defaults off).
# No persistence, no fifo — each Super-y spawns a fresh instance and this
# script is its whole life. If Enter picks a directory (peek-open.yazi), open
# it as a new zellij tab in the session that summoned peek before exiting.

set -u
export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"

# macOS `open` forwards the caller's environment, so the zellij pane that ran
# peek.sh leaks $ZELLIJ_SESSION_NAME here — capture it (for the Enter→new-tab
# handoff below) BEFORE scrubbing, since this window is raw ghostty and the
# leaked $ZELLIJ vars would otherwise make yazi and image-preview.sh believe
# they're inside zellij and downgrade crisp kitty graphics to block art.
PEEK_SESSION="${ZELLIJ_SESSION_NAME:-}"
unset ZELLIJ ZELLIJ_SESSION_NAME ZELLIJ_PANE_ID

# PEEK=1 tells the peek-open yazi plugin (Enter) it's running inside peek, so a
# directory picks → new tab instead of yazi's default open. Unset everywhere
# else, so a plain `yy` session keeps the default Enter.
export PEEK=1

# --stay: peek.sh forwards its own Super-Shift-y flag here so the Enter-on-dir
# tab inherits the same intent. Without it, a tab spawned from a stayed peek
# would land in the worktree and then have terminal's zshrc hop it straight out
# to the main checkout at shell birth — undoing the one thing --stay is for.
STAY=0
[ "${1:-}" = "--stay" ] && STAY=1

CWDFILE="$HOME/.cache/peek.cwd"

# spawn_tab DIR — open a new zellij tab cwd'd at DIR in the session that
# summoned peek. We're a bare ghostty instance with no $ZELLIJ, so target the
# server explicitly with `zellij -s <session> action`. Name the tab after its
# git root (or dir basename), same as the link-handler. `new-tab --cwd` is
# silently ignored under a custom default_tab_template, so clone the active
# layout and inject a tab-level cwd (the only form zellij honors) — the same
# trick the link-handler uses.
spawn_tab() {
    local dir="$1" session name root layout_src esc gen
    session="$PEEK_SESSION"
    [ -n "$session" ] || return 0

    name="$(basename "$dir")"
    root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"
    [ -n "$root" ] && name="$(basename "$root")"

    layout_src="$HOME/.config/zellij/layouts/custom.kdl"
    gen=""
    if [ -f "$layout_src" ]; then
        # KDL-escape the path (backslash then double-quote) for the cwd string.
        esc="${dir//\\/\\\\}"; esc="${esc//\"/\\\"}"
        # Reused/overwritten each pick — no per-invocation temp to race cleanup.
        gen="${TMPDIR:-/tmp}/zellij-peek-tab-$USER.kdl"
        # Two substitutions into a clone of the live layout: the tab-level cwd
        # (always), and — under --stay only — the template's bare `pane` swapped
        # for the HAUS_STAY=1 login shell, the same incantation Super Shift n
        # runs. Both target the `tab name="~" { pane }` template custom.kdl
        # flags as pattern-matched; we edit our COPY, never that file.
        awk -v cwd="$esc" -v stay="$STAY" '
            /^    tab name="~" \{$/ && !done { print "    tab cwd=\"" cwd "\" {"; done=1; at_pane=1; next }
            # Only the line IMMEDIATELY after the template tab is a candidate,
            # so the identical `pane` lines in the swap layouts below are safe.
            at_pane {
                at_pane=0
                if (stay == "1" && $0 == "        pane") {
                    print "        pane command=\"sh\" {"
                    print "            args \"-c\" \"HAUS_STAY=1 exec \\\"$SHELL\\\"\""
                    print "        }"
                    next
                }
            }
            { print }
        ' "$layout_src" > "$gen"
        grep -q '^    tab cwd=' "$gen" || gen=""
    fi

    if [ -n "$gen" ]; then
        zellij -s "$session" action new-tab --layout "$gen" --name "$name" 2>/dev/null
    else
        # Fallback (layout missing/reshaped): name the tab; cwd may land in $HOME.
        zellij -s "$session" action new-tab --cwd "$dir" --name "$name" 2>/dev/null
    fi
}

dir="$PWD"
[ -d "$dir" ] || dir="$HOME"
# Clear any prior pick so only THIS session's Enter-on-dir counts.
rm -f "$CWDFILE"
yazi "$dir"
# Enter on a directory (peek-open.yazi) drops its path here and quits yazi.
picked=$(cat "$CWDFILE" 2>/dev/null); rm -f "$CWDFILE"
[ -n "$picked" ] && [ -d "$picked" ] && spawn_tab "$picked"
# Falling off the end exits the --command process; Ghostty closes the window.

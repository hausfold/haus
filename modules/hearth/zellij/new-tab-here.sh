#!/bin/bash
# new-tab-here.sh — open a new zellij tab cwd'd at the CURRENTLY FOCUSED pane's
# directory. Bound to Super-Shift-t (config.kdl). Runs briefly, as a throwaway
# 1%-corner floating pane, INSIDE the current session: it inherits the focused
# pane's cwd as $PWD and already has $ZELLIJ, so `zellij action` targets this
# session with no `-s <session>` needed.
#
# `zellij action new-tab --cwd` is silently ignored under our custom
# default_tab_template, so clone the active layout (custom.kdl) and inject a
# tab-level cwd — the only form zellij honors. Same trick as peek-run.sh's
# spawn_tab. The tab is named after its git root (or the dir basename),
# matching the auto-rename the shell does on cd.
#
# Note: if the focused pane sits in an agent worktree (~/.cache/claude-worktrees),
# the tab is aimed at the repo's MAIN checkout — cwd and name both. The new
# tab's fresh shell would hop there anyway (hearth's zshrc), but the name is
# stamped from here before that shell exists, so without the pre-hop the tab
# kept the agent's throwaway checkout name while its shell sat in the main
# repo. The "stay in the worktree" spawns are Super-Shift-p and the Enter-on-dir
# tab of a Super-Shift-y (--stay) peek, which set $ZJ_STAY; this one
# deliberately does not.
set -u
export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH"

dir="$PWD"
[ -d "$dir" ] || dir="$HOME"

case "$dir" in
    "$HOME/.cache/claude-worktrees/"*)
        # Same detection as the zshrc hop: the shared .git lives in the main
        # checkout, so its parent is the repo this worktree belongs to.
        common="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
        [ -n "$common" ] && dir="$(dirname "$common")"
        ;;
esac

name="$(basename "$dir")"
root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$root" ] && name="$(basename "$root")"

layout_src="$HOME/.config/zellij/layouts/custom.kdl"
gen=""
if [ -f "$layout_src" ]; then
    # KDL-escape the path (backslash then double-quote) for the cwd string.
    esc="${dir//\\/\\\\}"; esc="${esc//\"/\\\"}"
    # Reused/overwritten each invocation — no per-call temp to race cleanup.
    gen="${TMPDIR:-/tmp}/zellij-new-tab-here-$USER.kdl"
    awk -v cwd="$esc" '
        /^    tab name="~" \{$/ && !done { print "    tab cwd=\"" cwd "\" {"; done=1; next }
        { print }
    ' "$layout_src" > "$gen"
    grep -q '^    tab cwd=' "$gen" || gen=""
fi

if [ -n "$gen" ]; then
    zellij action new-tab --layout "$gen" --name "$name" 2>/dev/null
else
    # Fallback (layout missing/reshaped): name the tab; cwd may land in $HOME.
    zellij action new-tab --cwd "$dir" --name "$name" 2>/dev/null
fi

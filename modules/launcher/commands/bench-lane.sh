#!/bin/bash
# pounce: name = Build This Lane
# pounce: description = bench try lane switch — this worktree plus its holt children
# pounce: icon = hammer

# ⌘B's target. Build+activate the focused window's whole holt LANE — this
# worktree PLUS every `holt child` worktree spawned from it, however many repos
# it touches, in ONE rebuild ("b" for bench, since ⌘L is Links).
#
# Unlike try-batch (which needs an open PR per repo) this tests the LOCAL
# checkouts, uncommitted edits included, so it's the fast loop for a cross-repo
# change mid-flight. Press it from the lane's PARENT worktree; bench refuses if
# it isn't one, or if it has no holt children (see bench's own
# cmd_try/detect_lane).
#
# Runs UNGATED: bench's BENCH_AGENT_SWITCH check only fires for an agent
# process, and a real keypress is a human at the keyboard.
#
# Installed only when haus.developer.enable is on: `bench` lives at a hardcoded
# ~/code/workshop on the family developer's own machines and nowhere else.
#
# The CWD is the whole input. The zellij bind inherited the focused pane's
# directory for free; a chord hosted outside the terminal has none, so ask
# lane-cwd.sh — the same resolver ⌘↵ and ⌘N use. Falling back to $HOME would
# just make bench refuse, which is the honest failure anyway.
#
# ── why a float, not a new tiled window ──────────────────────────────────────
# This spawned a plain `new-window.sh` until 2026-08-20, which was wrong in the
# way ⌘F and ⌘Y were wrong before them: a chord scoped to ONE window that
# answers by rearranging the whole desktop. A ⌘B is about this lane and nothing
# else — the cwd it reads, the worktree it overrides, the children that worktree
# spawned all belong to the summoning window — so the output belongs OVER that
# window (--match-focused), floating and pinned, exactly like the search and the
# file browser. The tiled layout underneath is untouched: nothing reflows on the
# way in, nothing has to be put back on the way out.
#
# The build is also the reason it must not tile. `bench try lane switch` runs
# for a minute and then activates; a real tiled window would have shrunk every
# neighbour for that minute and left a shell behind afterwards, so the cost of
# feeling one branch was a layout you had to repair. A float costs the desktop
# nothing and closes when you're done reading it — and read-then-dismiss is
# also the only honest shape for a window that has no zmx session and therefore
# no working chords of its own (see the payload's own comment).
FLOAT_TERM="$HOME/.config/haus/term/float-term.sh"
WINDOW_TITLE="quick-terminal-bench-lane"

cwd=""
[ -x "$HOME/.config/haus/lanes/lane-cwd.sh" ] && cwd="$("$HOME/.config/haus/lanes/lane-cwd.sh")"
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$HOME"

# The payload, the Rebuild System convention: a command with a `;` in it does
# not survive being threaded through `open --args` as one ghostty --command
# string, so it goes in a file and --command runs the file.
#
# $TMPDIR rather than rebuild.sh's bare /tmp: on macOS $TMPDIR is a per-user
# directory (/var/folders/…/T/), so a fixed filename there can't be a symlink
# someone else planted or a file some other uid owns — which a fixed name in
# world-writable /tmp can, silently, with `cat`'s error going to a stdout no
# one reads. Same convention, one hazard fewer. Content is fully static, so
# two ⌘Bs racing write identical bytes.
RUN_TMP="${TMPDIR:-/tmp}/haus-bench-lane-run.sh"
cat >"$RUN_TMP" <<'EOF'
#!/bin/bash
# --command overrides ghostty's configured launcher, so this window never runs
# launch.sh and inherits only what `open` leaked from the pounce daemon —
# launchd's stock PATH plus float-term's own prelude. bench's shebang is
# `/usr/bin/env bash`, which on a stock PATH resolves macOS bash 3.2 and dies
# at its first `declare -gA` before its own PATH guard can run. So export the
# nix bindirs here, exactly as the rebuild payload does.
export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:$PATH"

"$HOME/code/workshop/bench" try lane switch

# Hold, don't hand back a shell. The build output and the post-switch
# activation banner are the whole point and a float that vanished with the last
# line would take a failure with it — but this window has no zmx session (a
# --command instance never reaches launch.sh, which refuses one to a
# quick-terminal title anyway), so every window-layer chord is dead in it: ⌘B
# again, ⌘↵ and ⌘N would resolve no cwd and fall back to $HOME, and ⌘F would
# find no scrollback to search. A popup you read and dismiss is the honest
# shape for that — the lane's own window is still underneath, unmoved, with all
# its chords working.
echo ""
echo "Press any key to close..."
read -n 1 -s
EOF
chmod 700 "$RUN_TMP"
xattr -d com.apple.quarantine "$RUN_TMP" 2>/dev/null || true

# cwd rides in on --working-directory (an EXTRA ghostty flag after `--`), the
# same way peek roots yazi.
exec "$FLOAT_TERM" spawn \
    --title "$WINDOW_TITLE" \
    --match-focused \
    --pin \
    --command "bash $RUN_TMP" \
    -- --working-directory="$cwd" >/dev/null

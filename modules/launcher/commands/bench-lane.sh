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
# nothing and closes when you're done reading it.
FLOAT_TERM="$HOME/.config/haus/term/float-term.sh"
WINDOW_TITLE="quick-terminal-bench-lane"

cwd=""
[ -x "$HOME/.config/haus/lanes/lane-cwd.sh" ] && cwd="$("$HOME/.config/haus/lanes/lane-cwd.sh")"
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="$HOME"

# Stable temp path, the rebuild command's convention: a payload with a `;` and
# an `exec` in it does not survive being threaded through `open --args` as one
# ghostty --command string. Overwritten on every invocation.
RUN_TMP="/tmp/bench-lane-run.sh"
cat >"$RUN_TMP" <<'EOF'
#!/bin/bash
# The window stays open after bench exits — the build output and the
# post-switch activation banner are worth reading, and a float that vanished
# with the last line would take the failure with it. `exec zsh` also leaves you
# standing in the lane, which is where the next command usually belongs.
"$HOME/code/workshop/bench" try lane switch
exec zsh
EOF
xattr -d com.apple.quarantine "$RUN_TMP" 2>/dev/null || true

# cwd rides in on --working-directory (an EXTRA ghostty flag after `--`), the
# same way peek roots yazi.
exec "$FLOAT_TERM" spawn \
    --title "$WINDOW_TITLE" \
    --match-focused \
    --pin \
    --command "bash $RUN_TMP" \
    -- --working-directory="$cwd"

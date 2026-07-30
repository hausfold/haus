#!/bin/bash
# agents-hook.sh — the single writer of agent state, for TWO readers. Claude Code
# runs this from its own hooks, and because those hooks are children of a `claude`
# process living INSIDE a zellij pane, they inherit $ZELLIJ_SESSION_NAME +
# $ZELLIJ_PANE_ID — so each agent self-reports its exact state AND its subscribe
# target. No pane-id discovery, no screen-scraping. (Wired in the host's
# settings.json: UserPromptSubmit→working, Notification→waiting, Stop→idle,
# SessionEnd→remove.)
#
# The two readers, both drawing the same paw in the same three colours:
#   • sill's `agents` menu-bar pill — reads the /tmp state files below
#     (modules/sill/default.nix → agents.sh).
#   • hearth's zellij tab-bar plugin — paints a paw beside the tab NAME of
#     whichever tab holds the pane (modules/hearth/zellij/tab-bar). It can't read
#     the state files (a plugin is WASI-sandboxed), so it gets a `zellij pipe`
#     broadcast instead. It lives here rather than in hearth because only a hook
#     inside the agent's own pane knows the state and the pane id.
#
#   usage: agents-hook.sh <working|waiting|idle|remove>
set -u
DIR=/tmp/nebelhaus-agents
# A Claude hook can arrive with a bare PATH, and the zellij broadcast below needs
# the nix profile on it (agents.sh fixes up its own — see its header).
export USER="${USER:-$(id -un)}"
export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"

# Only track claude panes that live in zellij — a bare-terminal claude has no
# pane to peek and no place on the bar, so stay invisible there.
[ -n "${ZELLIJ_PANE_ID:-}" ] || exit 0

st="${1:-working}"
sess="${ZELLIJ_SESSION_NAME:-nosession}"
pane="terminal_${ZELLIJ_PANE_ID}"
f="$DIR/${sess}__${pane}.state"
mkdir -p "$DIR"

if [ "$st" = remove ]; then
  rm -f "$f"
else
  # Label the agent by its checkout (worktree/repo basename) — far more useful in
  # the popup than the shared "main" session name every agent pane reports.
  label=$(basename "${CLAUDE_PROJECT_DIR:-$PWD}")
  printf '%s\t%s\t%s\t%s\t%s\n' "$st" "$sess" "$pane" "$label" "$(date +%s)" > "$f"
fi

# Reader 2: hearth's zellij tab-bar. Broadcast on a named pipe — no --plugin, so
# a hook never has to know a wasm path; the plugin filters on the name and every
# other plugin's default pipe() ignores it. Payload is one line of `key=value`
# (see AGENT_STATUS_PIPE in tab-bar/src/main.rs), deliberately agent-neutral so
# codex or anything else with lifecycle hooks can report on the same pipe.
#
# Two gotchas baked into this one line:
#   • the payload argument is MANDATORY — with none, `zellij pipe` falls back to
#     reading STDIN and hangs forever.
#   • a CLI pipe waits for the plugin to handle it, and an ungranted plugin never
#     will (hearth seeds ReadCliPipes, but a live server can clobber a fresh
#     seed until the session is bounced). A stalled hook stalls the agent, so
#     fire and forget in a background subshell.
if command -v zellij >/dev/null 2>&1; then
  ( zellij --session "$sess" pipe --name nebelhaus-agent-status \
      "state=$st pane=$ZELLIJ_PANE_ID agent=claude" >/dev/null 2>&1 & )
fi

# Repaint the bar now by running the reader directly — the only reliable path.
# A hidden item's own update_freq never ticks (so it could never re-show itself),
# and sketchybar delivers custom --trigger events inconsistently across reloads;
# a plain invocation of agents.sh (which fixes up its own PATH) always works.
SENDER=refresh NAME=agents "$(dirname "$0")/agents.sh" >/dev/null 2>&1 || true
exit 0

#!/bin/bash
# agents-hook.sh — the single writer of agent state, for TWO readers, and it is
# CLIENT-AGNOSTIC: Claude Code, Codex and OpenCode all report through this one
# script. Each client runs it from its own lifecycle hooks, and because those
# hooks are children of an agent process living INSIDE a zellij pane, they
# inherit $ZELLIJ_SESSION_NAME + $ZELLIJ_PANE_ID — so each agent self-reports its
# exact state AND its subscribe target. No pane-id discovery, no screen-scraping.
#
# den ships this same file on PATH as `agent-state`, which is the name the
# non-Claude wirings use (they must not know where sketchybar keeps its plugins):
#   • Claude Code  — hooks in ~/.claude/settings.json (wired by your host):
#                    UserPromptSubmit→working, Notification→waiting, Stop→idle,
#                    SessionEnd→remove. Passes no client id; detected from env.
#   • OpenCode     — ~/.config/opencode/plugin/nebelhaus-agent-state.js (written
#                    by hearth), which maps chat.message/permission.ask/
#                    session.idle/dispose onto the same four words.
#   • Codex        — ~/.codex/hooks.json (seeded by hearth when codex is
#                    installed): UserPromptSubmit/Stop/SessionEnd.
#
# The two readers, drawing agent state in the same three colours:
#   • sill's `agents` menu-bar pill — reads the /tmp state files below
#     (modules/sill/default.nix → agents.sh). It also reads the CLIENT written
#     into each state file, so a row can say which agent is sitting there.
#   • hearth's zellij tab-bar plugin — paints an agent count badge beside the tab NAME of
#     whichever tab holds the pane (modules/hearth/zellij/tab-bar). It can't read
#     the state files (a plugin is WASI-sandboxed), so it gets a `zellij pipe`
#     broadcast instead. It lives here rather than in hearth because only a hook
#     inside the agent's own pane knows the state and the pane id.
#
#   usage: agents-hook.sh <working|waiting|idle|remove> [claude|codex|opencode]
set -u
DIR=/tmp/nebelhaus-agents
# An agent hook can arrive with a bare PATH, and the zellij broadcast below needs
# the nix profile on it (agents.sh fixes up its own — see its header).
export USER="${USER:-$(id -un)}"
export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"

# Only track agent panes that live in zellij — a bare-terminal agent has no
# pane to peek and no place on the bar, so stay invisible there.
[ -n "${ZELLIJ_PANE_ID:-}" ] || exit 0

st="${1:-working}"

# Which client is reporting. An explicit second argument always wins — that's how
# the OpenCode plugin and the Codex hooks name themselves. Claude Code's hooks
# pass only the state (the wiring predates this argument and lives in the user's
# own settings.json), so fall back to sniffing the environment the client exports
# into its hook children, and finally to a neutral "agent" rather than guessing.
agent="${2:-${NEBELHAUS_AGENT:-}}"
if [ -z "$agent" ]; then
  if   [ -n "${CLAUDECODE:-}${CLAUDE_PROJECT_DIR:-}" ]; then agent=claude
  elif [ -n "${OPENCODE:-}${OPENCODE_BIN_PATH:-}" ];    then agent=opencode
  elif [ -n "${CODEX_HOME:-}${CODEX_SANDBOX:-}" ];      then agent=codex
  else agent=agent
  fi
fi

sess="${ZELLIJ_SESSION_NAME:-nosession}"
pane="terminal_${ZELLIJ_PANE_ID}"
f="$DIR/${sess}__${pane}.state"
mkdir -p "$DIR"

if [ "$st" = remove ]; then
  rm -f "$f"
else
  # Label the agent by its checkout (worktree/repo basename) — far more useful in
  # the popup than the shared "main" session name every agent pane reports.
  # $CLAUDE_PROJECT_DIR is Claude's; every other client runs its hooks in the
  # session cwd, which is the same checkout.
  label=$(basename "${CLAUDE_PROJECT_DIR:-$PWD}")
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$st" "$sess" "$pane" "$label" "$(date +%s)" "$agent" > "$f"
fi

# Reader 2: hearth's zellij tab-bar. Broadcast on a named pipe — no --plugin, so
# a hook never has to know a wasm path; the plugin filters on the name and every
# other plugin's default pipe() ignores it. Payload is one line of `key=value`
# (see AGENT_STATUS_PIPE in tab-bar/src/main.rs), deliberately agent-neutral so
# every client reports on the same pipe.
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
      "state=$st pane=$ZELLIJ_PANE_ID agent=$agent" >/dev/null 2>&1 & )
fi

# Repaint the bar now by running the reader directly — the only reliable path.
# A hidden item's own update_freq never ticks (so it could never re-show itself),
# and sketchybar delivers custom --trigger events inconsistently across reloads;
# a plain invocation of agents.sh (which fixes up its own PATH) always works.
# Two candidate paths because this script runs from two homes: beside agents.sh
# in the sketchybar plugin dir, and as `agent-state` from the nix store (where
# $0's directory holds no plugins at all).
reader="$(dirname "$0")/agents.sh"
[ -x "$reader" ] || reader="$HOME/.config/sketchybar/plugins/agents.sh"
[ -x "$reader" ] && SENDER=refresh NAME=agents "$reader" >/dev/null 2>&1
exit 0

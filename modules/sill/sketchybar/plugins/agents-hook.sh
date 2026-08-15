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
#   • OpenCode     — ~/.config/opencode/plugin/haus-agent-state.js (written
#                    by hearth), which maps chat.message/permission.ask/
#                    session.idle/dispose onto the same four words.
#   • Codex        — ~/.codex/hooks.json (seeded by hearth when codex is in
#                    haus.ai.clients): UserPromptSubmit→working,
#                    PermissionRequest→waiting, Stop→idle. Codex has NO
#                    session-end event, so nothing ever reports `remove` for one
#                    of its panes — agents.sh drops rows whose zellij pane is
#                    gone instead, which covers every client that dies quietly.
#
# TWO STORES, picked by where the agent is sitting. A zellij pane files its
# state under /tmp keyed by (session, pane-id); a zmx lane
# (haus.hearth.lanes.backend = "zmx") has no pane, so it sets LABELS on its own
# session instead — see the zmx branch below for why that is the better half of
# the pair and not just the other one.
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
# A THIRD reader, of a SECOND file this writes:
#   • hearth's ⌘F find overlay (modules/hearth/zellij/find.sh) — reads the
#     optional `.session` sibling below to learn WHICH conversation a client's
#     pane is showing, so it can search that conversation's stored history
#     instead of the pane's scrollback (an alt-screen TUI has none, so scrollback
#     is one screenful). Claude Code needs nothing here: claude-statusline
#     already writes a richer pane → transcript PATH join. This is for the
#     clients that have no statusline of their own to carry it.
#
#   usage: agents-hook.sh <working|waiting|idle|remove> [claude|codex|opencode] [session-id]
set -u
DIR=/tmp/haus-agents
# An agent hook can arrive with a bare PATH, and the zellij broadcast below needs
# the nix profile on it (agents.sh fixes up its own — see its header).
export USER="${USER:-$(id -un)}"
export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"

# Only track agents the rice can actually take you to. That is a zellij pane,
# or — since haus.hearth.lanes.backend = "zmx" — a zmx session, whose name
# ($ZMX_SESSION, injected into every process in it) is a lane's window title
# and its holt lane all at once. A bare-terminal agent is neither: no pane to
# peek, no window to raise, so it stays invisible here as it always has.
if [ -z "${ZELLIJ_PANE_ID:-}" ] && [ -z "${ZMX_SESSION:-}" ]; then
  exit 0
fi

st="${1:-working}"

# Which client is reporting. An explicit second argument always wins — that's how
# the OpenCode plugin and the Codex hooks name themselves. Claude Code's hooks
# pass only the state (the wiring predates this argument and lives in the user's
# own settings.json), so fall back to sniffing the environment the client exports
# into its hook children, and finally to a neutral "agent" rather than guessing.
agent="${2:-${HAUS_AGENT:-}}"
if [ -z "$agent" ]; then
  if   [ -n "${CLAUDECODE:-}${CLAUDE_PROJECT_DIR:-}" ]; then agent=claude
  elif [ -n "${OPENCODE:-}${OPENCODE_BIN_PATH:-}" ];    then agent=opencode
  elif [ -n "${CODEX_HOME:-}${CODEX_SANDBOX:-}" ];      then agent=codex
  else agent=agent
  fi
fi

# ── the zmx lane path ────────────────────────────────────────────────────────
# A lane under haus.hearth.lanes.backend = "zmx" has no pane, so there is no
# ${sess}__${pane} key to file it under — and nothing to sweep either. Its state
# goes on the session itself as LABELS, which zmx keeps in memory for exactly as
# long as the session lives. That is the whole reason this branch exists: the
# state file protocol needs pruning (agents.sh shells `zellij action list-panes`
# on a tick, plus a 12h backstop for clients like Codex that have no
# session-end event) precisely because a file outlives what it describes. A
# label cannot. A lane that dies takes its row with it, in every failure mode,
# with no reaper.
#
# `zmx set .` — "." is the current session, so the hook never has to know or
# quote the name. `k=` with an empty value unsets, which is what `remove` wants.
if [ -n "${ZMX_SESSION:-}" ]; then
  command -v zmx >/dev/null 2>&1 || exit 0
  if [ "$st" = remove ]; then
    zmx set . state= client= label= since= >/dev/null 2>&1
    exit 0
  fi
  # The lane name, not the cwd's basename. `holt child` runs a child lane's
  # CONVERSATION in the parent's checkout (holt's HOLT_CHAT), so for those the
  # cwd basename names the wrong lane — while the session name is
  # `holt.<repo>.<lane>` by construction (hearth/lanes/lane-open.sh). Anything
  # not opened by that hook keeps the old cwd-basename answer.
  label="${ZMX_SESSION##*.}"
  case "$ZMX_SESSION" in holt.*.*) ;; *) label=$(basename "${CLAUDE_PROJECT_DIR:-$PWD}") ;; esac
  # zmx rejects a label value containing anything outside [a-zA-Z0-9-_.], and it
  # rejects the WHOLE `set` when one value is bad — so an exotic directory name
  # would silently cost this lane its state, not just its label. Fold the rest
  # to `-`. Nothing needs the pane's cwd as a label for the same reason: `zmx
  # ls` already reports the session's own `cwd=`, unrestricted, which is the
  # checkout the launcher cd'd into.
  label=$(printf '%s' "$label" | tr -c 'a-zA-Z0-9._-' '-')
  zmx set . \
    "state=$st" \
    "client=$agent" \
    "label=$label" \
    "since=$(date +%s)" >/dev/null 2>&1
  # No zellij tab-bar to broadcast to (there is no tab), so go straight to
  # repainting the bar — the same call the file path makes at the bottom.
  reader="$(dirname "$0")/agents.sh"
  [ -x "$reader" ] || reader="$HOME/.config/sketchybar/plugins/agents.sh"
  [ -x "$reader" ] && SENDER=refresh NAME=agents "$reader" >/dev/null 2>&1
  exit 0
fi

sess="${ZELLIJ_SESSION_NAME:-nosession}"
pane="terminal_${ZELLIJ_PANE_ID}"
f="$DIR/${sess}__${pane}.state"
# The client's own conversation id, when it passes one. Kept in a SIBLING file
# rather than as a seventh column of `.state`: sill's pill and the tab-bar
# broadcast both parse that line, and neither has any use for a session id — a
# new column would be churn in two readers to serve a third. Same name, same
# lifecycle, so `remove` cleans up both and nothing needs to learn a new path.
sf="$DIR/${sess}__${pane}.session"
# The pane's checkout, as another sibling for the same reason: agents.sh joins
# it against `holt --json`'s lane `.path` to pull in repo/PR context, and
# neither the tab-bar pipe nor the `.session` reader has any use for it. Unlike
# the session id this is known on every call (CLAUDE_PROJECT_DIR or $PWD), so
# it's write-on-change rather than write-once — cheap, and self-heals if a pane
# somehow reports two different cwds across its life.
cf="$DIR/${sess}__${pane}.cwd"
mkdir -p "$DIR"

if [ "$st" = remove ]; then
  rm -f "$f" "$sf" "$cf"
else
  # Write-on-change only, and never blank an id we already hold: `chat.message`
  # is the one hook that carries the session id, so the other three states
  # (waiting/idle) arrive with argument 3 empty and must not erase it.
  if [ -n "${3:-}" ] && [ "$(cat "$sf" 2>/dev/null)" != "$3" ]; then
    printf '%s\n' "$3" >"$sf.$$" && mv -f "$sf.$$" "$sf"
  fi
  cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
  if [ "$(cat "$cf" 2>/dev/null)" != "$cwd" ]; then
    printf '%s\n' "$cwd" >"$cf.$$" && mv -f "$cf.$$" "$cf"
  fi
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
  ( zellij --session "$sess" pipe --name haus-agent-status \
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

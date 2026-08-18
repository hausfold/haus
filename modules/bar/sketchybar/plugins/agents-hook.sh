#!/bin/bash
# agents-hook.sh — the single writer of agent state, for TWO readers, and it is
# CLIENT-AGNOSTIC: Claude Code, Codex and OpenCode all report through this one
# script. Each client runs it from its own lifecycle hooks, and because those
# hooks are children of an agent process living INSIDE a zellij pane, they
# inherit $ZELLIJ_SESSION_NAME + $ZELLIJ_PANE_ID — so each agent self-reports its
# exact state AND its subscribe target. No pane-id discovery, no screen-scraping.
#
# core ships this same file on PATH as `agent-state`, which is the name the
# non-Claude wirings use (they must not know where sketchybar keeps its plugins):
#   • Claude Code  — hooks in ~/.claude/settings.json (wired by your host):
#                    UserPromptSubmit→working, Notification→waiting, Stop→idle,
#                    SessionEnd→remove. Passes no client id; detected from env.
#   • OpenCode     — ~/.config/opencode/plugin/haus-agent-state.js (written
#                    by terminal), which maps chat.message/permission.ask/
#                    session.idle/dispose onto the same four words.
#   • Codex        — ~/.codex/hooks.json (seeded by terminal when codex is in
#                    haus.ai.clients): UserPromptSubmit→working,
#                    PermissionRequest→waiting, Stop→idle. Codex has NO
#                    session-end event, so nothing ever reports `remove` for one
#                    of its panes — agents.sh drops rows whose zellij pane is
#                    gone instead, which covers every client that dies quietly.
#   • jcode        — JCODE_HOOK_* environment (exported by terminal when jcode
#                    is in haus.ai.clients — its own config.toml is a file jcode
#                    rewrites, so the rice stays out of it): turn_start→working,
#                    turn_end→waiting, session_start→idle, session_end→remove.
#                    jcode has no permission prompt, so `waiting` is end-of-turn
#                    — which is the same claim the amber pill makes: your move.
#                    Its hooks run from a SHARED server process, not from the
#                    pane, and still address the right pane: jcode re-exports the
#                    requesting client's ZELLIJ_PANE_ID/ZELLIJ_SESSION_NAME onto
#                    every hook it fires.
#
# TWO STORES, picked by where the agent is sitting. A zellij pane files its
# state under /tmp keyed by (session, pane-id); a zmx lane
# has no pane, so it sets LABELS on its own
# session instead — see the zmx branch below for why that is the better half of
# the pair and not just the other one.
#
# The two readers, drawing agent state in the same three colours:
#   • bar's `agents` menu-bar pill — reads the /tmp state files below
#     (modules/bar/default.nix → agents.sh). It also reads the CLIENT written
#     into each state file, so a row can say which agent is sitting there.
#   • terminal's zellij tab-bar plugin — paints an agent count badge beside the tab NAME of
#     whichever tab holds the pane (modules/terminal/zellij/tab-bar). It can't read
#     the state files (a plugin is WASI-sandboxed), so it gets a `zellij pipe`
#     broadcast instead. It lives here rather than in terminal because only a hook
#     inside the agent's own pane knows the state and the pane id.
#
# A THIRD reader, of a SECOND file this writes:
#   • terminal's ⌘F find overlay (modules/terminal/zellij/find.sh) — reads the
#     optional `.session` sibling below to learn WHICH conversation a client's
#     pane is showing, so it can search that conversation's stored history
#     instead of the pane's scrollback (an alt-screen TUI has none, so scrollback
#     is one screenful). Claude Code needs nothing here: claude-statusline
#     already writes a richer pane → transcript PATH join. This is for the
#     clients that have no statusline of their own to carry it.
#
#   usage: agents-hook.sh <working|waiting|idle|remove> [claude|codex|opencode|jcode] [session-id]
set -u
DIR=/tmp/haus-agents
# An agent hook can arrive with a bare PATH, and the zellij broadcast below needs
# the nix profile on it (agents.sh fixes up its own — see its header).
export USER="${USER:-$(id -un)}"
export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"

# Only track agents the rice can actually take you to. Three shapes qualify:
# a zellij pane; a lane's zmx session, whose name ($ZMX_SESSION, injected into
# every process in it) is a lane's window title and its holt lane all at once;
# and a DESKTOP-APP session, which has neither of those but does have a window.
# A bare-terminal agent is none of the three — no pane to peek, no window to
# raise — so it stays invisible here as it always has.
#
# The desktop client is the one that has to be recognised rather than deduced:
# it and a bare terminal both lack a pane and both export CLAUDECODE, so
# $CLAUDE_CODE_ENTRYPOINT (the client naming its own front end) is the only
# thing between them. The session id is required, not optional — it is the key
# the row is filed under AND what SessionEnd comes back with to remove it, and
# a row nothing can ever remove is worse than no row at all.
desktop=""
if [ -z "${ZELLIJ_PANE_ID:-}" ] && [ -z "${ZMX_SESSION:-}" ]; then
  case "${CLAUDE_CODE_ENTRYPOINT:-}" in
    *desktop*) desktop="${CLAUDE_CODE_SESSION_ID:-${3:-}}" ;;
  esac
  [ -n "$desktop" ] || exit 0
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
  elif [ -n "${JCODE_HOOK_EVENT:-}" ];                  then agent=jcode
  else agent=agent
  fi
fi

# ── the zmx lane path ────────────────────────────────────────────────────────
# A lane has no pane, so there is no
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
  # `holt.<repo>.<lane>` by construction (terminal/lanes/lane-open.sh). Anything
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

# ── the desktop-app path ─────────────────────────────────────────────────────
# A desktop-client session has no pane and no zmx session, so it is keyed by
# the client's own conversation id — stable for the life of the conversation,
# and the one thing SessionEnd can hand back to find this row again.
#
# The files carry a `.desk` extension rather than `.state`, and that is not
# cosmetic. agents.sh's pruner asks zellij whether each `.state` file's session
# still holds that pane, and treats "Session 'x' not found" as proof that every
# row of that session is dead. A desktop row has no session for zellij to know
# about, so filing it as `.state` under any session name at all would have the
# pruner reap it on its very first tick. A different extension is the one shape
# that cannot be mistaken for a pane; agents.sh reads it through its own
# desktop_records(), and its 12h backstop covers both.
#
# What "go to this agent" means here: raise the app, and nothing finer. The
# desktop client runs every conversation as a tab of ONE window (checked: one
# com.anthropic.claudefordesktop window however many are open), so there is no
# per-session window to focus and no honest way to pretend otherwise. The row
# still earns its place — the state and how long it has sat in it is the whole
# question the pill exists to answer, and until now it answered it for a
# shrinking fraction of the agents actually running.
if [ -n "$desktop" ]; then
  # Same sanitising as the zmx label, for a different reason: this one becomes
  # a FILENAME. A session id is a uuid today, so nothing here fires — it is
  # here so that a client which someday passes a path-shaped id writes one file
  # instead of a directory tree.
  key=$(printf '%s' "$desktop" | tr -c 'a-zA-Z0-9._-' '-')
  f="$DIR/${key}.desk"
  cf="$DIR/${key}.desk.cwd"
  mkdir -p "$DIR"
  if [ "$st" = remove ]; then
    rm -f "$f" "$cf"
  else
    # $CLAUDE_PROJECT_DIR before $PWD for the reason the pane path gives: it is
    # the client telling us, rather than us inferring from wherever the hook
    # process happened to start.
    cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
    if [ "$(cat "$cf" 2>/dev/null)" != "$cwd" ]; then
      printf '%s\n' "$cwd" >"$cf.$$" && mv -f "$cf.$$" "$cf"
    fi
    # The same six columns the pane path writes, so agents.sh's two readers
    # differ only in where they find the row and never in how they parse it.
    # The session slot says `desktop` because the popup shows it verbatim when
    # there is no holt lane to join against, and "desktop" is the true answer
    # to "where is this agent" in a way a uuid is not.
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$st" "desktop" "$key" "$(basename "$cwd")" "$(date +%s)" "$agent" > "$f"
  fi
  # No zellij pipe: there is no tab bar to broadcast to, exactly as the zmx
  # branch above finds. Straight to the repaint.
  reader="$(dirname "$0")/agents.sh"
  [ -x "$reader" ] || reader="$HOME/.config/sketchybar/plugins/agents.sh"
  [ -x "$reader" ] && SENDER=refresh NAME=agents "$reader" >/dev/null 2>&1
  exit 0
fi

sess="${ZELLIJ_SESSION_NAME:-nosession}"
pane="terminal_${ZELLIJ_PANE_ID}"
f="$DIR/${sess}__${pane}.state"
# The client's own conversation id, when it passes one. Kept in a SIBLING file
# rather than as a seventh column of `.state`: bar's pill and the tab-bar
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
  #
  # jcode reaches the same slot without an argument: a hook command in its
  # config is a fixed string with no way to interpolate the event, but every
  # jcode hook process is handed `JCODE_HOOK_SESSION_ID` in its environment. So
  # read that when argument 3 is empty — the id is recorded on every state, not
  # just one, and nothing else changes.
  sid="${3:-${JCODE_HOOK_SESSION_ID:-}}"
  if [ -n "$sid" ] && [ "$(cat "$sf" 2>/dev/null)" != "$sid" ]; then
    printf '%s\n' "$sid" >"$sf.$$" && mv -f "$sf.$$" "$sf"
  fi
  # $JCODE_HOOK_CWD before $PWD for the same reason $CLAUDE_PROJECT_DIR comes
  # first: it is the client TELLING us, rather than us inferring. jcode does
  # chdir its hook processes into the session's directory (hooks.rs sets
  # current_dir from the event), so $PWD is right today — but only while the
  # session HAS a recorded working dir, and the hooks run in a shared server
  # process whose own cwd is some other lane's. Reading the field closes that
  # tail instead of relying on it staying empty.
  cwd="${CLAUDE_PROJECT_DIR:-${JCODE_HOOK_CWD:-$PWD}}"
  if [ "$(cat "$cf" 2>/dev/null)" != "$cwd" ]; then
    printf '%s\n' "$cwd" >"$cf.$$" && mv -f "$cf.$$" "$cf"
  fi
  # Label the agent by its checkout (worktree/repo basename) — far more useful in
  # the popup than the shared "main" session name every agent pane reports.
  # Same resolution as the .cwd sibling above, so the row's label and the path
  # agents.sh joins on can never disagree.
  label=$(basename "$cwd")
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$st" "$sess" "$pane" "$label" "$(date +%s)" "$agent" > "$f"
fi

# Reader 2: terminal's zellij tab-bar. Broadcast on a named pipe — no --plugin, so
# a hook never has to know a wasm path; the plugin filters on the name and every
# other plugin's default pipe() ignores it. Payload is one line of `key=value`
# (see AGENT_STATUS_PIPE in tab-bar/src/main.rs), deliberately agent-neutral so
# every client reports on the same pipe.
#
# Two gotchas baked into this one line:
#   • the payload argument is MANDATORY — with none, `zellij pipe` falls back to
#     reading STDIN and hangs forever.
#   • a CLI pipe waits for the plugin to handle it, and an ungranted plugin never
#     will (terminal seeds ReadCliPipes, but a live server can clobber a fresh
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

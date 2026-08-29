#!/bin/bash
# agents-hook.sh — the single writer of agent state, and it is CLIENT-AGNOSTIC:
# Claude Code, Codex and OpenCode all report through this one script.
# Each client runs it from its own lifecycle hooks, and because those hooks are
# children of an agent process living INSIDE a zmx session, they inherit
# $ZMX_SESSION — so each agent self-reports its exact state AND the handle
# everything else uses to find it. No discovery, no screen-scraping.
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
#                    of its windows — and nothing has to: its state lives as
#                    LABELS on the zmx session and dies with it.
#
# TWO STORES, picked by where the agent is sitting:
#   • a zmx session — every terminal agent, lane or plain window. Its state goes
#     on the session itself as LABELS, which zmx keeps for exactly as long as the
#     session lives. There used to be a third store, /tmp state files keyed by
#     (zellij session, pane id), and it is worth saying why it went rather than
#     just that it did: a FILE outlives what it describes, so it needed a pruner
#     (`zellij action list-panes` on every tick) plus a 12h backstop for clients
#     with no session-end event. A label cannot outlive its session. Every one of
#     those failure modes closes by construction.
#   • a DESKTOP-APP session — no session and no window of its own, so it files
#     under its own conversation id with a `.desk` extension.
#
# The reader:
#   • bar's `agents` menu-bar pill (modules/bar/default.nix → agents.sh). It
#     reads the client name too, so a row can say which agent is sitting there.
#     There used to be a second reader — zellij's tab-bar plugin, fed a
#     `zellij pipe` broadcast from here because a WASI plugin can't read files.
#     There are no tabs and no plugins now; the pill is the whole surface.
#
# A THIRD thing this writes, for terminal's ⌘F find overlay
# (modules/terminal/scripts/find.sh): the `convo` label / `.session` sibling —
# WHICH conversation a client is showing, so find can search that conversation's
# stored history instead of the window's scrollback (an alt-screen TUI has
# none, so scrollback is one screenful). Claude Code needs nothing here:
# claude-statusline already writes a richer session → transcript PATH join. This
# is for the clients that have no statusline of their own to carry it.
#
#   usage: agents-hook.sh <working|waiting|idle|remove> [claude|codex|opencode] [session-id]
set -u
DIR=/tmp/haus-agents
# An agent hook can arrive with a bare PATH, and `zmx` lives on the nix profile
# (agents.sh fixes up its own — see its header).
export USER="${USER:-$(id -un)}"
export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"

# Only track agents the rice can actually take you to. Two shapes qualify: a zmx
# session — for a lane, $ZMX_SESSION is its window title and its scruff lane all at
# once — and a DESKTOP-APP session, which has no session but does have a window.
# A bare-terminal agent is neither — nothing to peek, no window to raise — so it
# stays invisible here as it always has.
#
# The desktop client is the one that has to be recognised rather than deduced:
# it and a bare terminal both lack a session and both export CLAUDECODE, so
# $CLAUDE_CODE_ENTRYPOINT (the client naming its own front end) is the only
# thing between them. The session id is required, not optional — it is the key
# the row is filed under AND what SessionEnd comes back with to remove it, and
# a row nothing can ever remove is worse than no row at all.
desktop=""
if [ -z "${ZMX_SESSION:-}" ]; then
  case "${CLAUDE_CODE_ENTRYPOINT:-}" in
    *desktop*)
      # A SUBAGENT is not an agent this pill should draw. It runs inside a
      # session that already has a row, it has its own $CLAUDE_CODE_SESSION_ID
      # (distinct from the host's — verified), and it gets no SessionEnd of its
      # own: a fan-out of ten subagents would file ten rows that only the 12h
      # sweep could ever clear, every one of them keyed to a conversation you
      # cannot be taken to. $CLAUDE_CODE_HOST_SESSION_ID is preferred for the
      # same reason turned around — it is the session a click should land on.
      [ -z "${CLAUDE_CODE_CHILD_SESSION:-}" ] || exit 0
      desktop="${CLAUDE_CODE_HOST_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-${3:-}}}"
      ;;
  esac
  [ -n "$desktop" ] || exit 0
fi

st="${1:-working}"

# ── the lid hold ──────────────────────────────────────────────────────────────
# haus.power.lidAwake's root daemon (modules/core/lidawake.sh) watches this
# directory and holds macOS's `disablesleep` for exactly as long as it is
# non-empty, so a closed lid does not end a turn that is still running. One
# empty file per agent, named for the row it belongs to.
#
# Only `working` holds. `waiting` is a permission prompt — blocked on a human
# who, the lid being shut, is not there — and `idle`/`remove` are the whole
# point of releasing.
#
# Written unconditionally, whether or not the option is on, for the same reason
# this script is the single writer of everything else: the files are inert
# without the daemon, and gating them behind a nix-substituted flag would put a
# rebuild between you and a hook that already knows every transition. The
# directory is the user's own; root only ever reads it.
#
# `mkdir -p` on every call rather than once at the top: a hold that fails to
# land must never cost the row its state, so this whole block is best-effort
# and the writes below do not depend on it.
# `${HOME:-}` for the reason $USER is defended at the top of this file: a hook
# can arrive with almost no environment, and `set -u` would make an unset $HOME
# abort the script HERE — before the state write below, costing the bar the row
# this call exists to draw. Best-effort means best-effort.
lid_dir="${HAUS_LIDAWAKE_DIR:-${HOME:-}/.local/state/haus/lidawake/holds}"
# ZMX_SESSION for a terminal agent, the conversation id for a desktop one —
# the same two keys the two stores below are filed under, so a row and its hold
# always name each other. Sanitised because it becomes a filename.
lid_key=$(printf '%s' "${ZMX_SESSION:-desk.$desktop}" | tr -c 'a-zA-Z0-9._-' '-')
if [ "$st" = working ]; then
  if mkdir -p "$lid_dir" 2>/dev/null; then
    : >"$lid_dir/$lid_key" 2>/dev/null || true
  fi
else
  rm -f "$lid_dir/$lid_key" 2>/dev/null || true
fi

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

# ── the zmx path — every terminal agent ─────────────────────────────────────
# State goes on the session itself as LABELS, which zmx keeps in memory for
# exactly as long as the session lives. A session that dies takes its row with
# it, in every failure mode, with no reaper.
#
# `zmx set .` — "." is the current session, so the hook never has to know or
# quote the name. `k=` with an empty value unsets, which is what `remove` wants.
if [ -n "${ZMX_SESSION:-}" ]; then
  command -v zmx >/dev/null 2>&1 || exit 0
  if [ "$st" = remove ]; then
    zmx set . state= client= label= since= convo= >/dev/null 2>&1
    exit 0
  fi
  # The lane name, not the cwd's basename. `scruff child` runs a child lane's
  # CONVERSATION in the parent's checkout (scruff's SCRUFF_CHAT), so for those the
  # cwd basename names the wrong lane — while the session name is
  # `scruff.<repo>.<lane>` by construction (terminal/lanes/lane-open.sh).
  # Anything not opened by that hook keeps the old cwd-basename answer.
  label="${ZMX_SESSION##*.}"
  case "$ZMX_SESSION" in scruff.*.*|holt.*.*) ;; *) label=$(basename "${CLAUDE_PROJECT_DIR:-$PWD}") ;; esac
  # zmx rejects a label value containing anything outside [a-zA-Z0-9-_.], and it
  # rejects the WHOLE `set` when one value is bad — so an exotic directory name
  # would silently cost this lane its state, not just its label. Fold the rest
  # to `-`. Nothing needs the cwd as a label for the same reason: `zmx ls`
  # already reports the session's own directory, unrestricted — as `start_dir=`
  # in 0.7.0, `cwd=` in a newer one; agents.sh reads either.
  label=$(printf '%s' "$label" | tr -c 'a-zA-Z0-9._-' '-')
  # The client's own conversation id, when it passes one — `chat.message` is the
  # one opencode hook that carries it. This is what lets ⌘F search an alt-screen
  # agent's stored history rather than its one screenful of scrollback. Set only
  # when we have one: the other three states arrive with argument 3 empty and must
  # not erase what `chat.message` recorded. A session id is a uuid, so the label
  # charset holds without sanitising — but sanitise anyway, because zmx rejects
  # the WHOLE `set` on one bad value and that would cost this row its state.
  convo="${3:-}"
  set -- "state=$st" "client=$agent" "label=$label" "since=$(date +%s)"
  [ -n "$convo" ] &&
    set -- "$@" "convo=$(printf '%s' "$convo" | tr -c 'a-zA-Z0-9._-' '-')"
  zmx set . "$@" >/dev/null 2>&1
  # Straight to repainting the bar — there is no second reader to broadcast to.
  reader="$(dirname "$0")/agents.sh"
  [ -x "$reader" ] || reader="$HOME/.config/sketchybar/plugins/agents.sh"
  [ -x "$reader" ] && SENDER=refresh NAME=agents "$reader" >/dev/null 2>&1
  exit 0
fi

# ── the desktop-app path ─────────────────────────────────────────────────────
# A desktop-client session has no zmx session, so it is keyed by the client's own
# conversation id — stable for the life of the conversation, and the one thing
# SessionEnd can hand back to find this row again.
#
# The files carry a `.desk` extension, which is the last surviving trace of the
# `.state` protocol the zellij panes used: it existed so agents.sh's pruner —
# which reaped any `.state` row whose zellij pane was gone — could not mistake a
# desktop row for a dead pane. The pruner went with the panes; the extension
# stays because agents.sh still reads these through their own desktop_records(),
# and its 12h backstop is what clears a row whose SessionEnd never came.
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
    # there is no scruff lane to join against, and "desktop" is the true answer
    # to "where is this agent" in a way a uuid is not.
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$st" "desktop" "$key" "$(basename "$cwd")" "$(date +%s)" "$agent" > "$f"
  fi
  # Straight to the repaint — no second reader to broadcast to.
  reader="$(dirname "$0")/agents.sh"
  [ -x "$reader" ] || reader="$HOME/.config/sketchybar/plugins/agents.sh"
  [ -x "$reader" ] && SENDER=refresh NAME=agents "$reader" >/dev/null 2>&1
  exit 0
fi

# Nothing below the desktop branch: both stores return above, and anything that
# reaches here has no row to write. That used to be impossible — the zellij pane
# path was the catch-all, a `.state` file keyed by (session, pane id) with
# `.session`/`.cwd` siblings and a `zellij pipe` broadcast to the tab-bar
# plugin. All three consumers are gone, and the two facts that made them
# necessary went with them: a WASI plugin that could not read files, and a pane
# id that outlived nothing.
#
# So exit rather than falling through to the repaint below. A bare-terminal
# agent — no zmx session, not the desktop app — is deliberately invisible here
# (the gate at the top says so), and re-rendering the whole pill on its every
# turn would be work for a row that can never exist.
exit 0
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

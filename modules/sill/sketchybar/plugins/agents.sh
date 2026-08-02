#!/bin/bash
# agents.sh — the reader half of the `agents` bar item (opt-in via
# nebelhaus.sill.plugins). Surfaces the state of your agent worktree panes in the
# menu bar so you never have to cycle zellij tabs hunting for the one that's
# blocked on you. Client-agnostic: Claude Code, Codex and Opencode panes all
# land here, and each popup row is marked with the client sitting in it.
#
# State is written by agents-hook.sh from each client's own lifecycle hooks
# (authoritative — no screen-scraping), one file per pane under
# /tmp/nebelhaus-agents/*.state, each:
#     <state>\t<session>\t<pane-id>\t<label>\t<epoch>\t<client>
# <client> is the newest field: a file written before it existed reads as empty,
# which provider_style draws as the generic mark rather than lying about a client.
#
# Four entry paths:
#   • agent_update / system_woke / periodic  → recount, repaint icon+label
#   • mouse.clicked                          → (re)build + toggle the popup list
#   • `agents.sh row <sess> <pane>`          → popup-row click: go-to (left) or
#                                              peek (⌥/right), per $BUTTON/$MODIFIER
set -u
# Work whether we're run by the bar (rich env) or invoked from a bare env (an
# agent's hook, or a popup click needing zellij/aerospace): guarantee the nix
# profile + Homebrew on PATH, and $USER (sketchybar-msg resolves its socket via
# it). Set USER before PATH since PATH interpolates it.
export USER="${USER:-$(id -un)}"
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"
source "$HOME/.config/sketchybar/colors.sh"
source "$HOME/.config/sketchybar/sizes.sh"
# provider_style() — the same client icon table the aiUsage pill draws from, so
# a Codex pane wears the same mark in both pills.
# shellcheck source=./ai-provider.sh
source "$HOME/.config/sketchybar/plugins/ai-provider.sh"

DIR=/tmp/nebelhaus-agents
PLUGINS="$HOME/.config/sketchybar/plugins"
PAW=$(printf '\xEF\x86\xB0')   # nf-fa-paw (U+F1B0) — on-theme for the cat rice

# state → colour + human tag. waiting (a permission prompt) is the urgent one.
state_style() {
  case "$1" in
    waiting) COL=$PEACH; TAG="needs you" ;;
    working) COL=$SKY;   TAG="working"   ;;
    idle)    COL=$GREEN; TAG="done"      ;;
    *)       COL=$TEXT;  TAG="$1"        ;;
  esac
}

# ── popup-row click: go to the agent (left) or peek it (⌥/right) ──────────────
if [ "${1:-}" = "row" ]; then
  sess="$2"; pane="$3"
  # A plain click sends MODIFIER=none (not empty), so test against "none" — any
  # real modifier (alt/cmd/shift/ctrl) or a right-click means "peek instead".
  if [ "${BUTTON:-left}" = "right" ] || [ "${MODIFIER:-none}" != "none" ]; then
    # peek: live-tail the pane in a throwaway Ghostty, without stealing focus.
    # float-term centers it on the current screen (this window used to spawn
    # wherever AppKit last left one) and floats it via the shared helper.
    "$HOME/.config/zellij/float-term.sh" spawn --title "peek" \
      --w 900 --h 560 --pin \
      --command "/bin/bash $PLUGINS/agents-peek.sh $sess $pane" >/dev/null
  else
    # go-to: focus the pane (zellij jumps to its tab), then raise the terminal
    # window showing that session. Match the Ghostty window whose title carries
    # the session name (zellij titles the terminal with it); fall back to just
    # activating Ghostty. Only works for an attached session — a detached one
    # (0 clients) isn't in any window, so nothing to raise.
    zellij --session "$sess" action focus-pane-id "$pane" 2>/dev/null
    win=$(aerospace list-windows --all --format '%{window-id} %{app-name} %{window-title}' 2>/dev/null \
          | grep -w Ghostty | grep -F "$sess" | head -1 | awk '{print $1}')
    if [ -n "$win" ]; then aerospace focus --window-id "$win" 2>/dev/null; else open -a Ghostty; fi
  fi
  sketchybar --set agents popup.drawing=off
  exit 0
fi

# ── drop rows whose pane is gone ─────────────────────────────────────────────
# The state files are self-reported, so a client that never says goodbye leaves
# its last row on the bar forever. Claude Code has SessionEnd and Opencode has
# dispose; CODEX HAS NEITHER — its hook events end at Stop — so without this a
# finished Codex pane would sit there as a green paw until the 12h sweep below.
#
# zellij knows, and answers from outside a session (the bar is not in one):
# `action list-panes` prints one `terminal_<id>` per line, the exact key these
# filenames carry. Two answers are actionable and everything else is left
# alone — a transient zellij failure must never wipe live agents:
#   • a real list (has the PANE_ID header) → drop the panes not in it
#   • "Session 'x' not found"              → drop every row of that session
# One call per session with rows, on a 10s while-visible tick. Cheap.
prune_dead_panes() {
  [ -d "$DIR" ] || return 0
  command -v zellij >/dev/null 2>&1 || return 0
  local f base sess pane panes
  for sess in $(
    for f in "$DIR"/*.state; do
      [ -e "$f" ] || continue
      base="${f##*/}"; printf '%s\n' "${base%%__*}"
    done | sort -u
  ); do
    panes="$(zellij --session "$sess" action list-panes 2>&1)"
    case "$panes" in
      *PANE_ID*) ;;                       # a real list — fall through and diff it
      *"not found"*) rm -f "$DIR/${sess}__"*.state; continue ;;
      *) continue ;;                      # anything else: leave the rows alone
    esac
    for f in "$DIR/${sess}__"*.state; do
      [ -e "$f" ] || continue
      base="${f##*/}"; pane="${base##*__}"; pane="${pane%.state}"
      printf '%s\n' "$panes" | grep -q "^${pane}[[:space:]]" || rm -f "$f"
    done
  done
}
prune_dead_panes

# Backstop cleanup for what that can't see (a whole zellij server gone, a client
# that wrote a row from a pane id zellij never knew): reap state files untouched
# for >12h. Live agents re-stamp their epoch on every hook.
[ -d "$DIR" ] && find "$DIR" -name '*.state' -mmin +720 -delete 2>/dev/null

# Iterate the glob with a -e guard rather than an array: macOS bash 3.2 under
# `set -u` throws on "${arr[@]}" when the array is empty, and "no agents" is the
# common case. The literal-pattern-when-no-match is caught by [ -e ].

# ── click: rebuild the popup as one row per agent, then toggle it ─────────────
if [ "${SENDER:-}" = "mouse.clicked" ]; then
  sketchybar --remove '/agents.popup\..*/' 2>/dev/null
  i=0
  for f in "$DIR"/*.state; do
    [ -e "$f" ] || continue
    IFS=$'\t' read -r st sess pane label epoch client < "$f"
    state_style "$st"
    # The row's icon is the CLIENT (claude/codex/opencode), painted in the STATE
    # colour — two facts in the space the paw used to spend on one. The pill
    # itself keeps the paw: it stands for "agents", not for any one client.
    provider_style "${client:-}" "" "$FS_SMALL"
    sketchybar --add item "agents.popup.$i" popup.agents 2>/dev/null \
      --set "agents.popup.$i" \
        icon="$P_ICON" icon.color="$COL" icon.font="$P_FONT" \
        label="$label · $TAG" label.color="$TEXT" \
        label.font="Hack Nerd Font:Regular:$FS_SMALL" \
        background.drawing=off \
        click_script="$PLUGINS/agents.sh row $sess $pane"
    i=$((i + 1))
  done
  if [ "$i" -eq 0 ]; then
    sketchybar --add item agents.popup.0 popup.agents 2>/dev/null \
      --set agents.popup.0 icon.drawing=off label="no active agents" label.color="$SUBTEXT0"
  fi
  sketchybar --set agents popup.drawing=toggle
  exit 0
fi

# ── update: count states, paint the pill by the most-urgent one present ───────
working=0 waiting=0 idle=0
for f in "$DIR"/*.state; do
  [ -e "$f" ] || continue
  IFS=$'\t' read -r st _ < "$f"
  case "$st" in
    working) working=$((working + 1)) ;;
    waiting) waiting=$((waiting + 1)) ;;
    idle)    idle=$((idle + 1)) ;;
  esac
done

if [ $((working + waiting + idle)) -eq 0 ]; then
  sketchybar --set agents drawing=off   # nothing running → no clutter
  exit 0
fi

if   [ "$waiting" -gt 0 ]; then state_style waiting; n=$waiting
elif [ "$working" -gt 0 ]; then state_style working; n=$working
else                           state_style idle;    n=$idle
fi
sketchybar --set agents drawing=on icon="$PAW" icon.color="$COL" \
  label="$n" label.color="$COL"

#!/usr/bin/env bash
# desktop-guard.sh — haus's PreToolUse hook for Claude Code (`agent-desktop-guard`).
#
# The problem it solves: `permissions.defaultMode` is "auto" (terminal's
# claudeCodeSettings sets it), so an agent that decides to foreground an app,
# move a window or click something just DOES it — while you are typing into
# something else. With N lanes running that lands as random focus theft, and no
# amount of prompt wording makes it never happen.
#
# What it is NOT: a blocklist. Nothing here is ever refused. The only verdict
# this hook ever returns is "ask" — it re-opens the permission prompt for one
# thin slice of tool calls and leaves auto-mode alone everywhere else. Automating
# a demo recording, driving a GUI you asked for, rebuilding when you said to:
# all still available, one keypress away.
#
# The line it draws is NOT "is this dangerous" — it is:
#
#     does this change what is in front of my eyes, within about two seconds?
#
# That test is why `screencapture -x` and a screenshot-only computer_batch pass
# silently (looking is free) while `open -a` and a click do not, and why
# `defaults write` is absent (invisible until something restarts) but
# `killall Dock` is present (instantly visible).
#
# Deliberately NOT gated: every mcp__claude-in-chrome__* tool. That browser is
# not the one on screen, so an agent driving it costs the user nothing.
#
# Escape hatch: HAUS_DESKTOP_OK=1 in a pane's environment turns the whole guard
# off for that pane — for a long unattended run where 40 prompts is the problem.
# Mirrors bench's BENCH_AGENT_SWITCH=1: a reminder, not a jail.
#
# Wired by modules/terminal (home.activation.claudeCodeSettings) as a PreToolUse
# hook matching "Bash|mcp__computer-use__.*". Contract:
# stdin is the hook JSON ({tool_name, tool_input, …}); stdout is either nothing
# (no opinion — normal permission flow) or a hookSpecificOutput verdict; exit 0
# always, because a nonzero exit from a PreToolUse hook means something else.
PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/$(id -un 2>/dev/null)/bin:/opt/homebrew/bin:/usr/bin:/bin:${PATH:-}"

set -u

# Never let the guard itself break a turn: any failure below exits 0 with no
# verdict, which is exactly "no opinion".
in=$(cat 2>/dev/null) || exit 0
[ -n "${HAUS_DESKTOP_OK:-}" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

ask() { # $1 = the reason the user reads in the prompt
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $r
    }
  }' 2>/dev/null
  exit 0
}

j() { printf '%s' "$in" | jq -r "$1 // empty" 2>/dev/null; }

tool=$(j '.tool_name')

case "$tool" in
  # ---- computer use -------------------------------------------------------
  # computer_batch is the ONLY interaction tool in this session's toolkit, so
  # its action list is where the whole read/write distinction lives. A batch of
  # nothing but screenshot/zoom/cursor_position/wait is a look — it moves no
  # pointer and steals no focus, and it is precisely what an agent should reach
  # for instead of clicking around. Anything else in the list, ask.
  mcp__computer-use__computer_batch)
    if printf '%s' "$in" | jq -e '
        [.tool_input.actions[]?.action] as $a
        | ($a | length) > 0
          and (($a - ["screenshot", "zoom", "cursor_position", "wait"]) | length) == 0
      ' >/dev/null 2>&1; then
      exit 0
    fi
    ask "This moves the pointer / types / scrolls on the Mac you are using. Prefer a screenshot-only batch, or hand the step back to the user."
    ;;

  # Launching an app is background-safe in one of the tool's two modes and
  # front-and-center in the other, and the hook cannot tell which from here — so
  # it asks. Approving is one keypress; guessing wrong costs the user their
  # window.
  mcp__computer-use__open_application)
    ask "Launching '$(j '.tool_input.app')' may bring it to the front of the screen the user is working on."
    ;;

  mcp__computer-use__write_clipboard)
    ask "Overwrites the user's clipboard, which they may be mid-way through using."
    ;;

  mcp__computer-use__teach_step | mcp__computer-use__teach_batch)
    ask "Teach mode drives the user's screen directly."
    ;;

  # screenshot, zoom, read_clipboard, list_granted_applications, request_access,
  # request_teach_access, switch_display: looking and asking. Silent.
  mcp__computer-use__*) exit 0 ;;

  Bash) ;;
  *) exit 0 ;;
esac

# ---- Bash ------------------------------------------------------------------
# Eight patterns, each one passing the two-second test above. Kept short on
# purpose: a long list stops being read and starts being clicked through.
cmd=$(j '.tool_input.command')
[ -n "$cmd" ] || exit 0

m() { printf '%s' "$cmd" | grep -Eq "$1"; }

# `open` foregrounds by default; `open -g` / --background does not, and neither
# does `open -R` (reveals in Finder without activating? it does activate — so it
# is not exempted). Only the explicitly-backgrounded form passes.
if m '(^|[;&|] *)open ' && ! m '(^|[;&|] *)open [^;&|]*(-g|--background)\b'; then
  ask "\`open\` brings an app or file to the front. Use \`open -g\` to launch it in the background, or ask the user to open it."
fi

m 'osascript[^;&|]*activate' &&
  ask "This AppleScript activates an app — it will take the user's focus."

m '(^|[;&|] *)aerospace +(focus|move|workspace|layout|fullscreen|flatten)' &&
  ask "This moves or refocuses the user's windows."

m 'sketchybar[^;&|]*--reload' &&
  ask "Reloading the bar redraws the user's menu bar."

m 'launchctl +kickstart' &&
  ask "Restarting this agent kills whatever the user has open from it (the Pounce palette, the Perch shelf)."

m '(^|[;&|] *)killall +(Dock|Finder|SystemUIServer|sketchybar|WindowServer)' &&
  ask "Restarting this process visibly redraws the user's desktop."

# screencapture's default plays the shutter and flashes the screen; -x is silent
# and is the form an agent should be reaching for.
if m '(^|[;&|] *)screencapture ' && ! m 'screencapture[^;&|]*-[a-zA-Z]*x'; then
  ask "\`screencapture\` without \`-x\` plays the shutter sound and flashes the screen. Add \`-x\` to take it silently."
fi

m '(darwin-rebuild +switch|haus +rebuild|BENCH_AGENT_SWITCH=[^ ]* +.*try +.*switch)' &&
  ask "Activation is machine-wide and serial — with several lanes running, the last one to switch silently wins."

exit 0

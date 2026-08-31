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
# not the one on screen, so an agent driving it costs the user nothing. Same
# reasoning, same answer, for anything run over `ssh` on another machine — a
# lane's own headless macOS VM above all (see the Bash section). The one thing
# that changes is which screen the command lands on.
#
# Escape hatch: HAUS_DESKTOP_OK=1 in a pane's environment turns the whole guard
# off for that pane — for a long unattended run where 40 prompts is the problem.
# Mirrors bench's BENCH_AGENT_SWITCH=1: a reminder, not a jail.
#
# Nothing wires this file as a hook directly any more. Claude Code's wired
# PreToolUse hook (matching "Bash|mcp__computer-use__.*", set by modules/
# terminal's home.activation.claudeCodeSettings) is `agent-desktop-ask`
# (modules/ai/desktop-ask.sh), which pipes its stdin here and decides WHERE a
# verdict's question is put — the pane prompt, or a trill banner. Contract:
# stdin is the hook JSON ({tool_name, tool_input, …}); stdout is either nothing
# (no opinion — normal permission flow) or a hookSpecificOutput verdict; exit 0
# always, because a nonzero exit from a PreToolUse hook means something else.
#
# TWO clients speak that contract. pi's `haus-desktop-guard.ts` extension
# (modules/terminal/pi/desktop-guard.ts) runs this same binary from `tool_call`
# with a synthesised {tool_name:"Bash"} payload, and blocks the call when the
# verdict comes back "ask" and the human says Deny. So the contract above is a
# real interface with two callers behind it, not a private detail of any one
# hook — the asker and the extension both parse `permissionDecision` and
# `permissionDecisionReason` by name, and the three files move together.
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

  # Looking and asking: silent. ENUMERATED, with everything else under the
  # prefix falling through to ask — the settings matcher is the broad
  # `mcp__computer-use__.*`, so a tool this list has never heard of is exactly
  # the case that must not fail open. The sibling browser server already exposes
  # a singular `computer` tool, so a new interaction verb here is one server
  # release away.
  mcp__computer-use__screenshot | mcp__computer-use__zoom \
    | mcp__computer-use__read_clipboard | mcp__computer-use__list_granted_applications \
    | mcp__computer-use__request_access | mcp__computer-use__request_teach_access \
    | mcp__computer-use__switch_display) exit 0 ;;

  mcp__computer-use__*)
    ask "Unrecognised computer-use tool '$tool' — it may drive the screen the user is working on."
    ;;

  Bash) ;;
  *) exit 0 ;;
esac

# ---- Bash ------------------------------------------------------------------
# Nine patterns, each one passing the two-second test above. Kept short on
# purpose: a long list stops being read and starts being clicked through.
cmd=$(j '.tool_input.command')
[ -n "$cmd" ] || exit 0

# ---- another machine's screen is not this screen ---------------------------
# A lane feel-tests the desktop in its OWN headless macOS VM (`scruff runtime up
# --backend tart`, written up in the workshop's `docs/agent-vm.md` — not a
# file in this repo), driven entirely over ssh: `ssh
# admin@<guest> 'haus rebuild'`, `… 'sketchybar --reload …'`, `… 'killall
# Dock'`. Not one of those is visible to the person at this Mac — the guest
# renders to nothing at all — and the guard used to prompt for three of them,
# because it matched the TEXT of a command rather than the machine it lands on.
# A prompt there is worse than useless: it is the thing that teaches
# click-through on the prompts that matter.
#
# So: split the command at unquoted `;`, `&&`, `||`, `|` and newlines, drop the
# segments that run somewhere else, and let the patterns below see only what
# is left — the part that can still reach this screen. Quote-aware on purpose,
# so `ssh h 'a; b'` is ONE remote segment rather than a remote one and a local
# `b`, and length-preserving, so a segment that IS kept is re-emitted as its
# own original text, quotes and all, never a masked copy.
#
# Two ssh shapes stay gated, because both really do draw here:
#   ssh -X / -Y   forwarded windows render on this display
#   this Mac      `localhost`, `127.0.0.1`, `::1`, any `.local` name, or this
#                 host's own $HOSTNAME — an ssh home is not a trip. Those are
#                 spellings, not a resolver: a host that IS this Mac under some
#                 fourth name is exempted, and no cheap check catches it. The
#                 lane flow never has that shape — `tart ip` hands back a
#                 192.168.64.x literal.
#
# Whatever the mask cannot classify stays local — a heredoc body, a `$(…)`, an
# ssh whose host is a variable — so the failure mode is one extra prompt, never
# a missed one. Same if awk is somehow missing: `cmd` is left exactly as it came.
#
# Two cheap gates in front of it, because this hook runs before EVERY Bash call
# in every lane and its own cost has to stay invisible. The char loop is O(n²)
# in one line's length — seconds at a few hundred KB, which an agent writing a
# file through a single-line heredoc reaches — and it can only ever DROP a
# segment whose first word is one of these four commands, so a command that
# does not contain the word cannot be changed by it. Past the size cap the
# filter is skipped rather than trusted, which gates a huge remote command
# instead of exempting it: the failure direction stays "one extra prompt".
# Together they put a ceiling on the guard's own latency: ~0.14s for the worst
# input that reaches the loop, against ~0.06s for everything that doesn't.
case $cmd in
  *ssh* | *scp* | *sftp* | *rsync*) ;;
  *) filter=no ;;
esac
[ "${#cmd}" -gt 32768 ] && filter=no
# bash sets HOSTNAME itself, so the this-Mac test below costs no fork in the
# normal case; the fallback is only reached in a shell that unset it.
self=${HOSTNAME:-$(hostname -s 2>/dev/null)}
if [ -z "${filter:-}" ] && filtered=$(printf '%s\n' "$cmd" | awk -v self="${self%%.*}" '
    function flush(   m) {
      if (seg == "") { mseg = ""; return }
      m = mseg
      sub(/^[[:space:]]+/, "", m)
      while (m ~ /^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+/)
        sub(/^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+/, "", m)
      sub(/^(exec|command|nohup)[[:space:]]+/, "", m)
      if (m ~ /^([^[:space:]]*\/)?(ssh|scp|sftp|rsync)[[:space:]]/ &&
          m !~ /[[:space:]]-[A-Za-z]*[XY]([[:space:]]|$)/ &&
          m !~ /(localhost|127\.0\.0\.1|::1|\.local([[:space:]]|:|$))/ &&
          (self == "" || index(m, self) == 0)) { seg = ""; mseg = ""; return }
      sub(/^[[:space:]]+/, "", seg)   # a kept segment starts the line: `^` anchors below want no indent
      print seg
      seg = ""; mseg = ""
    }
    {
      n = length($0)
      for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (q != "") {                                    # inside a quote
          if (q == "\"" && c == "\\" && i < n) { seg = seg c substr($0, i + 1, 1); mseg = mseg "__"; i++ }
          else if (c == q)                     { seg = seg c; mseg = mseg c; q = "" }
          else                                 { seg = seg c; mseg = mseg "_" }
          continue
        }
        if (c == "\"" || c == "'"'"'") { q = c; seg = seg c; mseg = mseg c; continue }
        if (c == "\\") {                                  # escaped: never a separator
          seg = seg c; mseg = mseg "_"
          if (i < n) { i++; seg = seg substr($0, i, 1); mseg = mseg "_" }
          continue
        }
        if (c == ";" || c == "&" || c == "|") { flush(); continue }
        seg = seg c; mseg = mseg c
      }
      if (q != "") { seg = seg "\n"; mseg = mseg "\n" }   # a quote spanning lines
      else flush()
    }
    END { flush() }
  ' 2>/dev/null); then
  cmd=$filtered
fi
# Every segment ran elsewhere: there is nothing here to have an opinion about.
[ -n "$cmd" ] || exit 0

m() { printf '%s' "$cmd" | grep -Eq "$1"; }

# Three of the rules below are PAIRS — a shape that asks, and a flag that
# exempts it (`open -g`, `screencapture -x`, `tart run --no-graphics`) — and
# `m` is the wrong question for those: it asks "anywhere in the command", so
# one segment's flag silently exempted another segment's bare call. `open -g a;
# open b` was silent, and so was `tart run vm --no-graphics; tart run other`.
# `unpaired` asks what those rules actually mean: is there a SEGMENT matching
# $1 that does not carry $2? Splitting on the separator characters is enough
# here — one inside a quoted argument splits a segment that then matches
# neither half, which asks, and asking is the safe direction.
unpaired() { printf '%s' "$cmd" | tr ';&|' '\n\n\n' | grep -E "$1" | grep -Eqv "$2"; }

# `open` foregrounds by default; only the explicitly-backgrounded form passes.
#
# Two shapes this deliberately does NOT match, both found by review:
#   - prose. grep is line-based, so a bare `^open ` would fire on any line of a
#     heredoc that happens to start with the word — `open the door` in a commit
#     message. Requiring a flag, a path-shaped argument or a URL keeps English
#     out. Nagging on prose is worse than not nagging: it trains click-through.
#   - `open -ga Ghostty`. The flag cluster is combined far more often than not,
#     so the background exemption looks for a `g` ANYWHERE in a whitespace-led
#     cluster rather than a standalone `-g`. The leading whitespace matters:
#     without it `open ./my-great-file` exempts itself on the `-g` of "great".
if unpaired '^ *open +(-[a-zA-Z]|[~./$"'"'"']|[a-z][a-z0-9+.-]*://)' 'open.*[[:space:]]-([a-zA-Z]*g|-background)'; then
  ask "\`open\` brings an app or file to the front. \`open -g\` launches without activating, but it does not promise a window — Ghostty under it opens none, and \`open\` exits 0 either way. Use it to RUN something, a VM to SEE something, or ask the user to open it."
fi

m 'osascript[^;&|]*activate' &&
  ask "This AppleScript activates an app — it will take the user's focus."

m '(^|[;&|]) *aerospace +(focus|move|workspace|layout|fullscreen|flatten)' &&
  ask "This moves or refocuses the user's windows."

m 'sketchybar[^;&|]*--reload' &&
  ask "Reloading the bar redraws the user's menu bar."

m 'launchctl +kickstart' &&
  ask "Restarting this agent kills whatever the user has open from it (the Pounce palette, the Perch shelf)."

m '(^|[;&|]) *killall +(Dock|Finder|SystemUIServer|sketchybar|WindowServer)' &&
  ask "Restarting this process visibly redraws the user's desktop."

# screencapture's default plays the shutter and flashes the screen; -x is silent
# and is the form an agent should be reaching for.
# The -x test needs the leading whitespace for the same reason `open -g` does:
# without it `screencapture ~/shot-x.png` exempts itself on its own filename.
if unpaired '^ *screencapture[[:space:]]' 'screencapture.*[[:space:]]-[a-zA-Z]*x'; then
  ask "\`screencapture\` without \`-x\` plays the shutter sound and flashes the screen. Add \`-x\` to take it silently."
fi

# The VM exemption above holds only while the VM is headless. `tart run`
# without --no-graphics opens the guest's window, full size, on this display —
# the one command in the whole tart flow that IS screen theft. `scruff runtime up
# --backend tart` already boots headless; this is for a hand-run one.
if unpaired '^ *tart +run([[:space:]]|$)' 'tart +run.*--no-graphics'; then
  ask "\`tart run\` without \`--no-graphics\` opens the VM's window on the user's display. Boot it headless — that is what \`scruff runtime up --backend tart\` does."
fi

m '(darwin-rebuild +switch|haus +rebuild|BENCH_AGENT_SWITCH=[^ ]* +.*try +.*switch)' &&
  ask "Activation is machine-wide and serial — with several lanes running, the last one to switch silently wins."

exit 0

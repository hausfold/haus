#!/usr/bin/env bash
# desktop-ask.sh — the banner door on Claude Code's desktop guard
# (`agent-desktop-ask`), the PreToolUse hook terminal wires in place of the
# bare `agent-desktop-guard`.
#
# ── what this is ────────────────────────────────────────────────────────────
# The guard's only verdict is "ask", which re-opens the permission prompt IN
# THE PANE. That is the right answer for a pane you are sitting at and the
# wrong one for a lane: the whole reason a lane runs in its own window is that
# nobody is watching it, and a question that can only be answered by finding
# the pane is a lane parked until you go looking. pi got the fix first
# (terminal's haus-desktop-guard.ts): put the question up as a `trill ask`
# with Allow/Deny pills, answerable in one click from wherever you are. This
# is the same door for Claude Code.
#
# pi races its banner against its own in-pane dialog because both exist at
# once. Claude Code cannot: its prompt only exists AFTER this hook returns
# "ask", so the two doors are sequential here, picked by where you are —
#
#   the pane's window is focused  → pass the guard's "ask" through; the pane
#                                   prompt opens exactly as it always has
#   anywhere else                 → hold the turn on a `trill ask`; Allow and
#                                   Deny come back as permissionDecision
#                                   "allow" / "deny", no pane trip needed
#   nobody answers the banner     → retract it and pass "ask" through; the
#                                   prompt opens and the Notification hook
#                                   parks the usual go-to-lane fin, so the
#                                   question survives — it just loses the
#                                   one-click answer
#
# A PreToolUse hook may hold the turn (hooks run to completion, and when
# several match, the most restrictive of their verdicts wins — deny > ask >
# allow — so a held "allow" can never overrule someone else's "ask").
#
# ── the ruleset is not here ─────────────────────────────────────────────────
# This file decides WHERE the question is put, never WHETHER there is one.
# It pipes its stdin to `agent-desktop-guard` — the one ruleset both Claude
# Code and pi run behind (modules/ai/desktop-guard.sh, pinned by
# test/desktop-guard.bats) — and acts only on the verdict that comes back.
# A pattern change lands there, for every client at once.
#
# ── which way each failure falls ────────────────────────────────────────────
# Two regimes, split by the moment the guard says "ask":
#   before it  — any failure (no jq, no guard, unparseable verdict) exits 0
#                silently: no opinion, exactly as if the guard itself failed.
#   after it   — the question EXISTS, and losing it means the call runs with
#                no prompt at all (these panes are permission mode "auto").
#                So every failure past that line — no trill, daemon down,
#                banner refused, timeout, a signal — emits the guard's "ask"
#                verdict and falls back to the pane. One extra prompt, never
#                a missed one.
#
# ── the clock, and why it is clamped ────────────────────────────────────────
# Claude Code kills a hook command at its timeout — 600s by default — and a
# timed-out PreToolUse hook does NOT block the call: it proceeds, which in an
# auto-mode pane means promptless, the exact inversion of the fail direction
# above. So this script must never meet that clock. The banner waits
# HAUS_CLAUDE_ASK_TIMEOUT seconds (default 570; clamped into 1..570 so the
# margin under 600 cannot be configured away — 0 included, in case trill ever
# reads it as "no clock"), then falls back to the pane prompt, whose fin
# waits forever. pi's HAUS_PI_ASK_TIMEOUT has no default because pi's hook
# may genuinely wait all night; this one may not.
#
# If Claude Code tears the hook down un-trappably (the trap below catches
# TERM/INT/HUP and retracts the banner), the orphaned `trill ask` keeps the
# fin up until its own timeout; an answer to it goes nowhere, because the
# tool call it was about is already gone. That window is at most the timeout
# above, and closing it needs a signal we never got.
#
# ── what a refusal may not say ──────────────────────────────────────────────
# A deny's reason is read by the MODEL, not by a human, so it may not name
# the escape hatch: pi's first draft said "re-run with HAUS_DESKTOP_OK=1" and
# the model did exactly that, five seconds later. The reason carries the why
# and one instruction — stop, hand it back. The env var lives here instead,
# where a human reads it:
#
#   HAUS_DESKTOP_OK=1        the whole guard off for this pane, all clients
#   HAUS_CLAUDE_ASK_TIMEOUT  seconds before the banner yields to the pane
#                            prompt (≤570; larger values are clamped)
#
# Wired by modules/terminal (home.activation.claudeCodeSettings) as the
# PreToolUse hook matching "Bash|mcp__computer-use__.*". Contract: stdin is
# the hook JSON; stdout is nothing, or a hookSpecificOutput verdict; exit 0
# always. Installed by modules/ai beside the guard it wraps.
#
# System paths are APPENDED to PATH rather than prepended, unlike the guard's
# own preamble: a pane's hook inherits the pane's full PATH already, the
# append only rescues a bare launchd-ish environment, and it is what lets
# test/desktop-ask.bats put stub binaries in front. The one non-PATH
# dependency, the focused-window join, is a terminal home file resolved under
# $HOME for the same reason.
PATH="${PATH:+$PATH:}/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/$(id -un 2>/dev/null)/bin:/opt/homebrew/bin:/usr/bin:/bin"
export PATH

set -u

in=$(cat 2>/dev/null) || exit 0
[ -n "${HAUS_DESKTOP_OK:-}" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

verdict=$(printf '%s' "$in" | agent-desktop-guard 2>/dev/null) || verdict=""
[ -n "$verdict" ] || exit 0

# The pane door: emit whatever the guard said, exactly. Also the shape a
# future non-"ask" guard verdict takes through here — untouched.
pane() {
  printf '%s\n' "$verdict"
  exit 0
}

decision=$(printf '%s' "$verdict" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
[ -n "$decision" ] || exit 0 # unparseable → no opinion, like a failed guard
[ "$decision" = "ask" ] || pane

# ── which door ──────────────────────────────────────────────────────────────
# No zmx session means this is not a haus pane (the desktop app, a bare
# `claude` somewhere) — nothing here knows where its window is, so the pane
# prompt it has always had is the honest answer. With one, ask the same
# window→session join every chord uses (terminal's focused-session.sh): the
# focused window running THIS session means someone is looking at the pane,
# and the in-pane prompt is one keypress where a banner is a mouse trip. Any
# other answer — another window, another app, no answer at all — means the
# banner, which lands on the same screen anyway if they are merely elsewhere.
[ -n "${ZMX_SESSION:-}" ] || pane
command -v trill >/dev/null 2>&1 || pane
join="$HOME/.config/haus/term/focused-session.sh"
if [ -r "$join" ]; then
  focused=$(bash "$join" 2>/dev/null) || focused=""
  [ "$focused" = "$ZMX_SESSION" ] && pane
fi

# ── the banner ──────────────────────────────────────────────────────────────
j() { printf '%s' "$in" | jq -r "$1 // empty" 2>/dev/null; }

reason=$(printf '%s' "$verdict" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)
[ -n "$reason" ] || reason="This touches the screen the user is working on."

# A banner is a card, not a terminal: command in the title so two asks read
# apart at a glance, and again in the body in full-ish — the card is the
# consent surface, and approving what you cannot see is the one thing a
# permission banner may not ask of anyone. (pi's asker draws the same card.)
clip() { # $1 = text, $2 = max chars
  local s
  s=$(printf '%s' "$1" | tr '\n\t' '  ' | sed -E 's/  +/ /g; s/^ //; s/ $//')
  if [ "${#s}" -gt "$2" ]; then printf '%s…' "${s:0:$(($2 - 1))}"; else printf '%s' "$s"; fi
}

tool=$(j '.tool_name')
cmd=$(j '.tool_input.command')
cwd=$(j '.cwd')
if [ "$tool" = "Bash" ] && [ -n "$cmd" ]; then
  title=$(clip "Run $cmd?" 90)
  body="$(clip "$cmd" 220)

$(clip "$reason" 200)"
else
  title=$(clip "Allow ${tool#mcp__computer-use__}?" 90)
  body=$(clip "$reason" 300)
fi
where=${cwd##*/}
[ -n "$where" ] || where=claude

t=${HAUS_CLAUDE_ASK_TIMEOUT:-570}
case $t in '' | *[!0-9]*) t=570 ;; esac
[ "$t" -ge 1 ] || t=570
[ "$t" -gt 570 ] && t=570

# The bar's pill goes red while the question is up — the Notification hook
# that normally reports `waiting` never fires on this path, because the
# prompt it announces never opens. Fire-and-forget, like every agent-state
# call everywhere.
command -v agent-state >/dev/null 2>&1 && agent-state waiting >/dev/null 2>&1 &

# Keyed per invocation, not per session: Claude Code runs parallel tool
# calls' hooks in parallel, and two questions under one key would have the
# second REPLACE the first's fin. A key that never repeats also never
# needs replacing — a fin here outlives nothing, the timeout sees to that.
trill ask "$title" \
  --pill Allow --pill Deny \
  --body "$body" \
  --subtitle "$where" \
  --source haus.ai.claude.desktop \
  --symbol hand.raised \
  --key "haus-claude-desktop-$$" \
  --timeout "$t" >/dev/null 2>&1 &
child=$!

# SIGINT is what retracts an ask (trill's own rule: a question with nobody
# behind it comes down). TERM/INT/HUP is what a torn-down hook can hope to
# see; `gone` tells a relayed kill apart from trill dying on its own, which
# must fall to the pane rather than to silence.
gone=0
trap 'gone=1; kill -INT "$child" 2>/dev/null' TERM INT HUP
wait "$child"
rc=$?
trap - TERM INT HUP
if [ "$gone" = 1 ]; then
  wait "$child" 2>/dev/null
  exit 0 # the turn is gone; nobody reads a verdict now
fi

case $rc in
  0) # first pill: Allow. The turn moves — say so on the pill.
    command -v agent-state >/dev/null 2>&1 && agent-state working >/dev/null 2>&1 &
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        permissionDecisionReason: "Approved from the banner."
      }
    }' 2>/dev/null || pane
    ;;
  1) # second pill: Deny. The refusal reads to the model — the why, one
    # instruction, and never the escape hatch (see the header).
    command -v agent-state >/dev/null 2>&1 && agent-state working >/dev/null 2>&1 &
    jq -n --arg r "$reason" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: ($r + "\n\nThe user said no. Do not retry this, and do not reach the same effect another way. Hand this step back to the user and carry on with the rest of the task.")
      }
    }' 2>/dev/null || pane
    ;;
  *) # 64 usage · 69 daemon unreachable · 70 refused · 75 nobody answered —
    # and anything else trill's exit could ever mean: the pane prompt, whose
    # Notification fin takes over the waiting.
    pane
    ;;
esac

exit 0

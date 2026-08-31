#!/usr/bin/env bats
# Hermetic tests for modules/ai/desktop-ask.sh — the banner door on the desktop
# guard: the PreToolUse hook that decides WHERE a guard question is put (the
# pane prompt for a watched window, a trill ask for everywhere else) and turns
# the banner's answer into a permissionDecision.
#
# Why a suite. The subject sits between permission mode "auto" and the screen,
# and its failure modes are directional: a lost question past the guard's "ask"
# is a tool call that runs with NO prompt at all, so every branch after that
# line must fall to the pane, never to silence. The suite pins the fall
# direction of each branch, the door choice, and the two verdicts a banner
# answer becomes — including the rule that a refusal never names the escape
# hatch (the model reads it, and pi's first draft taught us what it does with
# an escape hatch it has been told about).
#
# WHICH calls deserve a question at all is not tested here — that line is the
# guard's, pinned by test/desktop-guard.bats. Here the guard is a stub, so
# every case is one verdict string and the suite needs no Mac, no trill and no
# window server.
#
# The subject appends system paths to PATH instead of prepending exactly so
# that stubs like these can stand in front — and so that a run of this suite
# on a real haus machine drives the stub trill, never the real one (a real
# `trill ask` here would put an actual banner on the developer's screen).

bats_require_minimum_version 1.5.0

setup() {
  ASK="${DESKTOP_ASK_UNDER_TEST:-$BATS_TEST_DIRNAME/../modules/ai/desktop-ask.sh}"
  unset HAUS_DESKTOP_OK HAUS_CLAUDE_ASK_TIMEOUT GUARD_VERDICT TRILL_RC FOCUSED

  export HOME="$BATS_TEST_TMPDIR/home"
  STUBS="$BATS_TEST_TMPDIR/bin"
  LOG="$BATS_TEST_TMPDIR/log"
  mkdir -p "$HOME/.config/haus/term" "$STUBS" "$LOG"
  export PATH="$STUBS:$PATH"

  # The guard: echoes whatever verdict the test staged, and leaves a footprint
  # so a test can assert it was never consulted.
  cat > "$STUBS/agent-desktop-guard" <<EOF
#!/usr/bin/env bash
cat >/dev/null
touch "$LOG/guard.ran"
printf '%s' "\${GUARD_VERDICT:-}"
EOF

  # trill: records its argv (one per line) and exits the staged answer —
  # 0 Allow, 1 Deny, 69/75/… the no-answer family.
  cat > "$STUBS/trill" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$LOG/trill.argv"
exit "\${TRILL_RC:-0}"
EOF

  # agent-state: append-only, because the subject fires it twice on an
  # answered banner (waiting, then working).
  cat > "$STUBS/agent-state" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$LOG/agent-state.log"
EOF

  # The focused-window join, at the home path the subject resolves.
  cat > "$HOME/.config/haus/term/focused-session.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s' "${FOCUSED:-}"
EOF

  chmod +x "$STUBS"/* "$HOME/.config/haus/term/focused-session.sh"
}

invoke() { printf '%s' "$1" | bash "$ASK"; }

# One staged "ask" verdict and one Bash payload, shared by most cases.
stage_ask() {
  REASON="This moves or refocuses the user's windows."
  export GUARD_VERDICT
  GUARD_VERDICT=$(jq -n --arg r "$REASON" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $r
    }
  }')
  PAYLOAD=$(jq -n '{
    tool_name: "Bash",
    tool_input: { command: "aerospace focus left" },
    cwd: "/Users/someone/code/some-repo",
    session_id: "sess-1"
  }')
}

# The pane door emits the guard's verdict byte-for-byte in meaning.
assert_pane() {
  [ "$(printf '%s' "$1" | jq -cS .)" = "$(printf '%s' "$GUARD_VERDICT" | jq -cS .)" ] || {
    printf 'expected the pane pass-through, got: %s\n' "$1" >&2
    return 1
  }
}

# argv_after <flag> → the value following that flag in trill's recorded argv
argv_after() { awk -v f="$1" 'p { print; exit } $0 == f { p = 1 }' "$LOG/trill.argv"; }

# The agent-state report is fire-and-forget from the subject, so it can land
# just after the subject exits — poll briefly rather than flake.
state_reported() {
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    grep -qx "$1" "$LOG/agent-state.log" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}

# ---- before the guard says "ask": every failure is silence -----------------

@test "a silent guard stays silent, and no banner goes up" {
  export GUARD_VERDICT=""
  run -0 invoke '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
  [ -z "$output" ]
  [ ! -e "$LOG/trill.argv" ]
}

@test "HAUS_DESKTOP_OK short-circuits before the guard is even consulted" {
  stage_ask
  export HAUS_DESKTOP_OK=1
  run -0 invoke "$PAYLOAD"
  [ -z "$output" ]
  [ ! -e "$LOG/guard.ran" ]
  [ ! -e "$LOG/trill.argv" ]
}

@test "an unparseable verdict is no opinion, not a crash" {
  export GUARD_VERDICT='not json at all'
  run -0 invoke '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
  [ -z "$output" ]
  [ ! -e "$LOG/trill.argv" ]
}

# ---- the door choice -------------------------------------------------------

@test "no zmx session means the pane door, verbatim" {
  stage_ask
  unset ZMX_SESSION
  run -0 invoke "$PAYLOAD"
  assert_pane "$output"
  [ ! -e "$LOG/trill.argv" ]
}

@test "a focused pane keeps its in-pane prompt" {
  stage_ask
  export ZMX_SESSION="scruff.haus.mylane"
  export FOCUSED="scruff.haus.mylane"
  run -0 invoke "$PAYLOAD"
  assert_pane "$output"
  [ ! -e "$LOG/trill.argv" ]
}

@test "a non-ask verdict passes through untouched, whatever the focus" {
  stage_ask
  export GUARD_VERDICT='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"no"}}'
  export ZMX_SESSION="scruff.haus.mylane"
  export FOCUSED=""
  run -0 invoke "$PAYLOAD"
  assert_pane "$output"
  [ ! -e "$LOG/trill.argv" ]
}

# ---- the banner ------------------------------------------------------------

@test "an unwatched pane asks trill: pills, key, clock, and the command on the card" {
  stage_ask
  export ZMX_SESSION="scruff.haus.mylane"
  export FOCUSED="term.2"
  export TRILL_RC=0
  run -0 invoke "$PAYLOAD"

  # the card: command in the title AND the body (the card is the consent
  # surface), the guard's reason beside it, the lane naming the subtitle
  head -1 "$LOG/trill.argv" | grep -qx 'ask'
  argv_after --pill >/dev/null
  grep -qx -- 'Allow' "$LOG/trill.argv"
  grep -qx -- 'Deny' "$LOG/trill.argv"
  grep -q 'aerospace focus left' <<< "$(argv_after --body)"
  # the body is one multi-line argument, so its later lines land as later
  # lines of the record — the reason is asserted against the whole file
  grep -qF "$REASON" "$LOG/trill.argv"
  grep -q 'aerospace focus left' "$LOG/trill.argv"
  [ "$(argv_after --subtitle)" = "some-repo" ]
  [ "$(argv_after --source)" = "haus.ai.claude.desktop" ]
  # per-invocation key: parallel tool calls run parallel hooks, and a shared
  # key would have the second question REPLACE the first's fin
  argv_after --key | grep -Eqx 'haus-claude-desktop-[0-9]+'
  # the clock stays under Claude Code's 600s hook kill
  [ "$(argv_after --timeout)" = "570" ]

  # Allow → permissionDecision allow, and the pill hears about both moments
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "allow" ]
  state_reported waiting
  state_reported working
}

@test "Deny comes back as a deny that never names the escape hatch" {
  stage_ask
  export ZMX_SESSION="scruff.haus.mylane"
  export FOCUSED=""
  export TRILL_RC=1
  run -0 invoke "$PAYLOAD"
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "deny" ]
  reason=$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')
  grep -q "$REASON" <<< "$reason"
  grep -q 'The user said no' <<< "$reason"
  # not `! grep`: bash's set -e ignores a `!`-prefixed command's status, so a
  # leak would pass silently — the exact wrong direction for this assertion
  if grep -q 'HAUS_DESKTOP_OK' <<< "$reason"; then
    printf 'the refusal names the escape hatch:\n%s\n' "$reason" >&2
    return 1
  fi
}

@test "an unanswered banner falls back to the pane prompt" {
  stage_ask
  export ZMX_SESSION="scruff.haus.mylane"
  export FOCUSED=""
  export TRILL_RC=75 # nobody answered; 69/70/64 take the same branch
  run -0 invoke "$PAYLOAD"
  assert_pane "$output"
}

@test "a computer-use tool gets a card too, named after the tool" {
  stage_ask
  export ZMX_SESSION="scruff.haus.mylane"
  export FOCUSED=""
  export TRILL_RC=0
  PAYLOAD=$(jq -n '{
    tool_name: "mcp__computer-use__open_application",
    tool_input: { app: "Ghostty" },
    cwd: "/Users/someone/code/some-repo",
    session_id: "sess-1"
  }')
  run -0 invoke "$PAYLOAD"
  sed -n '2p' "$LOG/trill.argv" | grep -q 'open_application'
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "allow" ]
}

# ---- the clock -------------------------------------------------------------

@test "the timeout can shorten but never outlive the hook" {
  stage_ask
  export ZMX_SESSION="scruff.haus.mylane"
  export FOCUSED=""
  export TRILL_RC=0

  HAUS_CLAUDE_ASK_TIMEOUT=60 run -0 invoke "$PAYLOAD"
  [ "$(argv_after --timeout)" = "60" ]

  HAUS_CLAUDE_ASK_TIMEOUT=9999 run -0 invoke "$PAYLOAD"
  [ "$(argv_after --timeout)" = "570" ]

  # 0 is all-digits, so the numeric guard passes it — and if trill ever reads
  # 0 as "no clock", the hook would run to Claude Code's 600s kill, past
  # which the call PROCEEDS, promptless. The clamp floors it instead.
  HAUS_CLAUDE_ASK_TIMEOUT=0 run -0 invoke "$PAYLOAD"
  [ "$(argv_after --timeout)" = "570" ]

  HAUS_CLAUDE_ASK_TIMEOUT=soon run -0 invoke "$PAYLOAD"
  [ "$(argv_after --timeout)" = "570" ]
}

#!/usr/bin/env bats
# Hermetic tests for the field reading in
# modules/launcher/commands/spawn-agent.sh — the half of the ⇥ client dial that
# can silently eat somebody's task.
#
# `--dial` changes the SHAPE of a pounce commit: a step that passed the flag
# gets "<action>\t<name=value;…>\t<line-or-text>" where every other step here
# gets "<action>\t<line-or-text>". So the prompt step now has to decide, per
# commit, whether there is a middle field to skip — and every way of getting
# that decision wrong is invisible from the outside:
#
#   * a false YES drops the first line of a multi-line task, or the whole task
#     when it is one line. The lane still spawns; it spawns on the wrong brief.
#   * a false NO hands `scruff spawn --prompt-file -` a task beginning
#     "agent=pi", which is not an error either — it is just a lane briefed with
#     a stray field.
#
# Neither shows up in a feel-test, because both produce a lane. Hence this file.
#
# The subject is not sourceable — it is a command that runs top to bottom and
# opens windows — so the four readers are lifted out of it by name. That keeps
# the assertions pinned to the real source rather than to a copy: rename or
# reshape one of them and the extraction fails loudly instead of testing text
# that no longer exists.

bats_require_minimum_version 1.5.0

setup() {
  SUBJECT="$BATS_TEST_DIRNAME/../modules/launcher/commands/spawn-agent.sh"
  [ -f "$SUBJECT" ] || {
    echo "subject missing: $SUBJECT" >&2
    return 1
  }

  local lifted="$BATS_TEST_TMPDIR/readers.sh"
  : >"$lifted"
  local fn
  for fn in action_of payload_of dial_agent dial_payload resolve_agents; do
    awk -v fn="$fn" '
      $0 ~ "^" fn "\\(\\) \\{" { inside = 1 }
      inside { print }
      inside && /^}$/ { inside = 0; found = 1 }
      $0 ~ "^" fn "\\(\\) \\{.*; \\}$" { print; found = 1; inside = 0 }
      END { if (!found) exit 1 }
    ' "$SUBJECT" >>"$lifted" || {
      echo "could not lift $fn out of the subject" >&2
      return 1
    }
  done
  # shellcheck disable=SC1090
  . "$lifted"

  # What the command itself computes before the prompt step: the clients on
  # PATH, and the dial spec built from them.
  AGENTS="claude opencode pi"
  agent_dial="agent=claude|opencode|pi"
}

# A one-line task, dial present. The plain reader would keep "agent=pi".
@test "dial commit: the agent is read and the task starts after it" {
  local commit
  commit="$(printf 'enter\tagent=pi\tfix the bar pill flicker')"
  run dial_agent "$commit"
  [ "$status" -eq 0 ]
  [ "$output" = "pi" ]
  [ "$(dial_payload "$commit")" = "fix the bar pill flicker" ]
  [ "$(action_of "$commit")" = "enter" ]
}

# ⇧↵ makes the task multi-line, and only the FIRST line carries the fields.
@test "dial commit: later lines survive verbatim, tabs and all" {
  local commit expected
  commit="$(printf 'ctrl\tagent=opencode\t- one\n- two\twith a tab\n- three')"
  run dial_agent "$commit"
  [ "$status" -eq 0 ]
  [ "$output" = "opencode" ]
  expected="$(printf -- '- one\n- two\twith a tab\n- three')"
  [ "$(dial_payload "$commit")" = "$expected" ]
}

# A daemon older than --dial ignores the flag and answers in the two-field
# shape. The step must fall back rather than strip a field that isn't there.
@test "no dial field: falls back to the two-field reader" {
  local commit
  commit="$(printf 'enter\tfix the bar pill flicker')"
  run dial_agent "$commit"
  [ "$status" -ne 0 ]
  [ "$(payload_of "$commit")" = "fix the bar pill flicker" ]
}

# The whole reason the membership test exists: a task may begin with the
# literal text "agent=" and there is nothing wrong with that.
@test "a task that opens with agent= is a task, not a dial" {
  local commit
  commit="$(printf 'enter\tagent=pi is what I want to write about')"
  run dial_agent "$commit"
  [ "$status" -ne 0 ]
  [ "$(payload_of "$commit")" = "agent=pi is what I want to write about" ]
}

# Same text, but with a tab in it so the field count alone would say yes.
# The value is not one we offered, so it is still a task.
@test "agent=<something we never offered> is a task, not a dial" {
  local commit expected
  commit="$(printf 'enter\tagent=zed\tcompare it to ours')"
  run dial_agent "$commit"
  [ "$status" -ne 0 ]
  expected="$(printf 'agent=zed\tcompare it to ours')"
  [ "$(payload_of "$commit")" = "$expected" ]
}

# A machine with one client installed passes no --dial at all, so no commit
# can carry one — and a commit that somehow does must not be believed.
@test "no dial declared: the reader refuses whatever arrives" {
  agent_dial=""
  AGENTS="claude"
  run dial_agent "$(printf 'enter\tagent=claude\tfix it')"
  [ "$status" -ne 0 ]
}

# An empty task still commits (the step's own emptiness check is downstream),
# and must not be mistaken for a missing dial field.
@test "dial commit with an empty task keeps the agent" {
  local commit
  commit="$(printf 'opt\tagent=claude\t')"
  run dial_agent "$commit"
  [ "$status" -eq 0 ]
  [ "$output" = "claude" ]
  [ -z "$(dial_payload "$commit")" ]
}

# ── resolve_agents: what the chip is allowed to offer ────────────────────────
#
# The list is built from PATH rather than from `haus.ai.clients`, which is the
# whole point: the option set and "will actually start" are then the same
# question. These pin the three answers that are not the happy path.

# PATH is REPLACED, not prepended. The Mac this runs on has real clients in
# /etc/profiles/per-user/$USER/bin, so a prepended stub dir tests nothing —
# `command -v pi` finds the real pi and every "not installed" case passes for
# the wrong reason. /usr/bin and /bin are kept because `tr` lives there.
stub_clients() {
  local bin="$BATS_TEST_TMPDIR/bin"
  rm -rf "$bin"
  mkdir -p "$bin"
  local client
  for client in "$@"; do
    printf '#!/bin/sh\nexit 0\n' >"$bin/$client"
    chmod +x "$bin/$client"
  done
  PATH="$bin:/usr/bin:/bin"
}

# `scruff agent default` is the only other input. Called after stub_clients,
# which is what creates (and clears) the directory both write into.
stub_default() {
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  printf '#!/bin/sh\nprintf %%s %s\n' "$1" >"$bin/scruff"
  chmod +x "$bin/scruff"
  PATH="$bin:/usr/bin:/bin"
}

@test "resolve_agents: the default leads, the rest follow in scruff's order" {
  stub_clients claude opencode pi
  stub_default pi
  resolve_agents
  [ "$agent" = "pi" ]
  [ "$AGENTS" = "pi claude opencode" ]
  [ "$agent_dial" = "agent=pi|claude|opencode" ]
}

@test "resolve_agents: one client installed means no chip at all" {
  stub_clients claude
  stub_default claude
  resolve_agents
  [ "$agent" = "claude" ]
  [ "$AGENTS" = "claude" ]
  [ -z "$agent_dial" ]
}

@test "resolve_agents: a default that isn't installed falls to one that is" {
  stub_clients opencode pi
  stub_default codex
  resolve_agents
  [ "$agent" = "opencode" ]
  [ "$AGENTS" = "opencode pi" ]
  [ "$agent_dial" = "agent=opencode|pi" ]
}

@test "resolve_agents: nothing installed is a refusal, not a silent spawn" {
  stub_clients
  stub_default claude
  run resolve_agents
  [ "$status" -ne 0 ]
}

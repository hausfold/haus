#!/usr/bin/env bats
# Hermetic tests for the row filter in modules/launcher/commands/lanes.sh —
# the rule that decides which lanes the ⌘-palette's Lanes picker will offer.
#
# A lane spawned by `scruff child` has no pane, no panel and no transcript: it
# exists so one pane can edit a second repo, and its conversation lives in the
# pane that made it. Offering it here is a dud row in a picker whose whole job
# is "take me to that agent", so the filter drops it — and every way of getting
# that filter wrong hides something real:
#
#   * filtering on `parent` instead of `chat` hides a RUNNING AGENT. A lane
#     opened with ⌘↵ from inside another lane's pane is parented to that lane
#     exactly as a `scruff child` is, and it has a window.
#   * treating an absent `chat` as "no chat" empties the picker against any
#     scruff that predates the field.
#   * ignoring the live session table hides a lane you started ten seconds ago.
#
# None of those is visible in a feel-test: the picker still opens, and still
# shows lanes. It is the missing row nobody notices. Hence this file.
#
# The subject opens windows, so the jq program is LIFTED out of it by its own
# delimiters rather than copied — reshape the pipeline and the extraction fails
# loudly instead of testing a program that no longer exists.

bats_require_minimum_version 1.5.0

setup() {
  SUBJECT="$BATS_TEST_DIRNAME/../modules/launcher/commands/lanes.sh"
  [ -f "$SUBJECT" ] || {
    echo "subject missing: $SUBJECT" >&2
    return 1
  }

  # The program lives inside a single-quoted shell string, so every apostrophe
  # in it is written '"'"' — undo that once here and jq sees what the shell
  # would have handed it.
  PROG="$BATS_TEST_TMPDIR/lanes.jq"
  awk '
    /jq -r --arg states/ { inside = 1; next }
    inside && /^  '"'"' 2>\/dev\/null$/ { inside = 0; found = 1; next }
    inside { print }
    END { if (!found) exit 1 }
  ' "$SUBJECT" | sed "s/'\"'\"'/'/g" >"$PROG" || {
    echo "could not lift the jq program out of $SUBJECT" >&2
    return 1
  }
  [ -s "$PROG" ] || {
    echo "lifted an empty jq program" >&2
    return 1
  }
}

# rows <json-file> [states] — the picker's TSV, one row per offered lane.
rows() {
  jq -r -f "$PROG" --arg states "${2:-}" "$1"
}

# A parent lane with a chat of its own, and the lane it spawned in another repo.
fixture() { # fixture [chat-of-the-spawned-lane]
  local spawned_chat="${1-/w/parent}"
  local chat_field='"chat": "'"$spawned_chat"'",'
  [ "$spawned_chat" = OMIT ] && chat_field=''
  cat >"$BATS_TEST_TMPDIR/lanes.json" <<JSON
{ "scruff": "1.2.0", "schema": 2, "warnings": [], "lanes": [
  { "name": "par", "repo": "acme/workshop", "main": "/repos/workshop",
    "branch": "worktree-par", "path": "/w/parent", "parent": "/repos/workshop",
    "chat": "/w/parent", "agent": "claude", "state": "live",
    "last_commit": "parent work" },
  { "name": "par", "repo": "acme/haus", "main": "/repos/haus",
    "branch": "worktree-par", "path": "/w/child", "parent": "/w/parent",
    $chat_field "agent": "claude", "state": "live",
    "last_commit": "child work" }
] }
JSON
  printf '%s' "$BATS_TEST_TMPDIR/lanes.json"
}

@test "lanes: a spawned lane — chat somewhere else — is not offered" {
  run rows "$(fixture)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"workshop · par"* ]] || fail_with "the parent lane vanished" "$output"
  [[ "$output" != *"haus · par"* ]] || fail_with "a lane with no pane was offered" "$output"
}

@test "lanes: a spawned lane WITH a live session is offered anyway" {
  # The escape that matters most: ⌘↵ from inside a lane's pane records the same
  # parentage a `scruff child` does, and that lane has a window to jump to.
  run rows "$(fixture)" "$(printf 'scruff.haus.par\tworking\tclaude\t/w/child')"
  [ "$status" -eq 0 ]
  [[ "$output" == *"haus · par"* ]] || fail_with "a running agent was hidden" "$output"
}

@test "lanes: a scruff too old to report chat hides nothing" {
  run rows "$(fixture OMIT)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"haus · par"* ]] || fail_with "an absent chat must mean show it" "$output"
}

@test "lanes: an empty chat means undetermined, and hides nothing" {
  # scruff answers "" for any client whose transcripts it cannot probe — codex,
  # opencode, pi. A picker that read that as "no chat" would hide every lane on
  # a machine that does not run Claude.
  run rows "$(fixture '')"
  [ "$status" -eq 0 ]
  [[ "$output" == *"haus · par"* ]] || fail_with "an empty chat must mean show it" "$output"
}

@test "lanes: a lane whose chat is its own checkout is offered" {
  run rows "$(fixture /w/child)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"haus · par"* ]] || fail_with "a lane with its own chat was dropped" "$output"
}

@test "lanes: a session scruff has never heard of still gets a row" {
  # The other source the picker unions in — a lane spawned since the cache was
  # written. The filter must not reach it: it has no scruff record to read.
  run rows "$(fixture)" "$(printf 'scruff.perch.brandnew\tworking\tclaude\t/w/new')"
  [ "$status" -eq 0 ]
  [[ "$output" == *"perch · brandnew"* ]] || fail_with "a fresh session was dropped" "$output"
}

fail_with() { # fail_with <why> <output>
  printf '%s\n--- rows ---\n%s\n' "$1" "$2" >&2
  return 1
}

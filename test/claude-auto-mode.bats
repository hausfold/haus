#!/usr/bin/env bats
# The `autoMode` block of ~/.claude/settings.json — haus's half of Claude Code's
# safety classifier, and the first test it has ever had.
#
# Why a suite, and why now. `haus.ai.autoMode.*` is four lists of prose that
# decide what an agent may do on this Mac without asking, and every way the
# merge can be wrong is invisible from the outside: the file still parses, the
# rebuild still says `done`, and the difference only shows up as a refusal that
# stopped happening. Measured on a guest on 2026-09-21: after `haus reset` of
# `allow`, `environment` and `softDeny`, `haus get` answered `[]` for all three
# while the settings file still held every value and `claude auto-mode config`
# still printed the allow rule as EFFECTIVE. A lifted refusal outlived the
# config that asked for it, and no haus surface said so — `haus diff` did not
# mention `autoMode` once.
#
# Two subjects, because the fix has two halves and they fail differently:
#
#   modules/terminal/claude-settings.jq    the merge. Run here with the real jq
#                                          against fixtures — the whole reason
#                                          the program is a static file rather
#                                          than a quoted argument.
#   the `run sh -c` block in               the bookkeeping: the record of which
#   modules/terminal/default.nix           sections haus wrote, without which
#                                          the merge cannot tell an undeclared
#                                          section from one it never touched.
#
# The second is EXTRACTED from the module rather than retyped, so this suite
# fails when that block changes shape rather than quietly testing a copy that
# has stopped resembling it. Needs bash + bats + jq, no Nix and no Mac.

bats_require_minimum_version 1.5.0

setup() {
  REPO="$BATS_TEST_DIRNAME/.."
  PROG="$REPO/modules/terminal/claude-settings.jq"
  MODULE="$REPO/modules/terminal/default.nix"
  TMP="$BATS_TEST_TMPDIR"
  export HOME="$TMP/home"
  mkdir -p "$HOME"
}

# ---- the merge ---------------------------------------------------------------

# merge <auto json> <prev json> <base json> → the whole settings file on stdout.
# The two --slurpfile arguments are what the activation hands jq: the sections
# declared now, and the names haus wrote last time.
merge() {
  printf '%s' "$1" >"$TMP/auto.json"
  printf '%s' "$2" >"$TMP/prev.json"
  printf '%s' "$3" >"$TMP/base.json"
  jq -c --slurpfile auto "$TMP/auto.json" --slurpfile prev "$TMP/prev.json" \
    -f "$PROG" "$TMP/base.json"
}

# What a section haus has never named looks like: written by `claude auto-mode`,
# or by hand, and none of haus's business.
THEIRS='{"autoMode":{"hard_deny":["Keychain export: never, for any reason."]},"theme":"dark"}'

@test "a machine that has never named a section is left exactly as it was" {
  run -0 merge '{}' '[]' "$THEIRS"
  [ "$(jq -c '.autoMode' <<<"$output")" = '{"hard_deny":["Keychain export: never, for any reason."]}' ]
}

@test "a declared section is written beside the one haus does not own" {
  run -0 merge '{"allow":["$defaults","Lane VMs: ssh to a tart guest."]}' '[]' "$THEIRS"
  [ "$(jq -c '.autoMode.allow' <<<"$output")" = '["$defaults","Lane VMs: ssh to a tart guest."]' ]
  [ "$(jq -c '.autoMode.hard_deny' <<<"$output")" = '["Keychain export: never, for any reason."]' ]
}

@test "a section haus wrote and no longer declares is REMOVED" {
  base='{"autoMode":{"allow":["stale haus rule"],"hard_deny":["theirs"]}}'
  run -0 merge '{}' '["allow"]' "$base"
  [ "$(jq -c '.autoMode' <<<"$output")" = '{"hard_deny":["theirs"]}' ]
}

@test "a section haus never wrote survives the removal of one it did" {
  base='{"autoMode":{"allow":["stale haus rule"],"soft_deny":["mine, from the CLI"]}}'
  run -0 merge '{}' '["allow"]' "$base"
  [ "$(jq -c '.autoMode' <<<"$output")" = '{"soft_deny":["mine, from the CLI"]}' ]
}

@test "declaring one section does not remove another that is still declared" {
  base='{"autoMode":{"allow":["old"],"environment":["old"]}}'
  run -0 merge '{"allow":["new"],"environment":["new"]}' '["allow","environment"]' "$base"
  [ "$(jq -c '.autoMode' <<<"$output")" = '{"allow":["new"],"environment":["new"]}' ]
}

@test "the key itself goes when nothing is left in it" {
  base='{"autoMode":{"allow":["stale"],"environment":["stale"]},"theme":"dark"}'
  run -0 merge '{}' '["allow","environment"]' "$base"
  [ "$(jq -c 'has("autoMode")' <<<"$output")" = false ]
  [ "$(jq -r '.theme' <<<"$output")" = dark ]
}

@test "keepDefaults leaves no residue: the old list goes whole, marker included" {
  # The flip that was measured: `keepDefaults` on wrote `"$defaults"` into each
  # list, and turning it off left that marker behind in the sections haus had
  # stopped naming. The section leaving whole is what ends that class of bug —
  # there is no half of an old list to disagree with the new one.
  base='{"autoMode":{"soft_deny":["$defaults","stale"],"allow":["$defaults","stale"]}}'
  run -0 merge '{"allow":["mine alone"]}' '["allow","soft_deny"]' "$base"
  [ "$(jq -c '.autoMode' <<<"$output")" = '{"allow":["mine alone"]}' ]
}

@test "a malformed .autoMode costs its own contents, never the run" {
  run -0 merge '{"allow":["a rule"]}' '[]' '{"autoMode":"not an object"}'
  [ "$(jq -c '.autoMode' <<<"$output")" = '{"allow":["a rule"]}' ]
}

@test "a malformed .autoMode is not even touched when haus has no opinion" {
  run -0 merge '{}' '[]' '{"autoMode":"not an object"}'
  [ "$(jq -r '.autoMode' <<<"$output")" = "not an object" ]
}

@test "a corrupt record of what haus wrote deletes nothing and kills nothing" {
  # jq exiting non-zero here leaves settings.json untouched and says nothing —
  # the activation step still exits 0 — so a record in the wrong shape must fail
  # soft rather than cost the machine its hooks and statusline in silence.
  run -0 merge '{"allow":["a rule"]}' 'null' "$THEIRS"
  [ "$(jq -c '.autoMode.hard_deny' <<<"$output")" = '["Keychain export: never, for any reason."]' ]
}

@test "the rest of the program still merges: hooks appended, the user's kept" {
  base='{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"/usr/bin/say done"}]}]}}'
  run -0 merge '{}' '[]' "$base"
  [ "$(jq -c '[.hooks.Stop[].hooks[].command]' <<<"$output")" = \
    '["/usr/bin/say done","/run/current-system/sw/bin/scruff hook notify"]' ]
  [ "$(jq -r '.permissions.defaultMode' <<<"$output")" = auto ]
  [ "$(jq -r '.statusLine.command' <<<"$output")" = /run/current-system/sw/bin/claude-statusline ]
}

# ---- the bookkeeping ---------------------------------------------------------

# The activation's shell, lifted out of the module and pointed at fixtures. Four
# holes are filled the way Nix fills them, and `''${` — how a Nix indented
# string spells a shell expansion — is unwrapped. Anything else the block grows
# arrives here as an empty expansion and fails the cases below loudly, which is
# the point of extracting rather than retyping.
activation() {
  local sections="$1" auto="$2"
  awk '
    /home\.activation\.claudeCodeSettings/ { want = 1 }
    want && /run sh -c/                    { inblk = 1 }
    inblk                                  { print }
    inblk && /autoModeSectionNames/        { exit }
  ' "$MODULE" >"$TMP/block.nix"
  [ -s "$TMP/block.nix" ] || { echo "no claudeCodeSettings block found in $MODULE" >&2; return 1; }

  export SECTIONS="$sections" AUTOFILE="$TMP/declared.json" PROG
  printf '%s' "$auto" >"$AUTOFILE"

  {
    echo 'run() { "$@"; }'
    sed -e 's|${pkgs.jq}/bin/jq|jq|' \
      -e 's|${autoModeFile}|"$AUTOFILE"|' \
      -e 's|${./claude-settings.jq}|"$PROG"|' \
      -e 's|${lib.escapeShellArg autoModeSectionNames}|"$SECTIONS"|' \
      -e "s|''\${|\${|g" "$TMP/block.nix"
  } >"$TMP/act.sh"
  bash "$TMP/act.sh"
}

state() { cat "$HOME/.local/state/haus/claude-auto-mode-sections"; }
settings() { jq -c "$1" "$HOME/.claude/settings.json"; }

@test "the sections haus writes are recorded, and clear on the rebuild after" {
  mkdir -p "$HOME/.claude"
  printf '%s' "$THEIRS" >"$HOME/.claude/settings.json"

  run -0 activation '["allow","environment"]' \
    '{"allow":["$defaults","Lane VMs: ssh to a tart guest."],"environment":["$defaults","One-person org."]}'
  [ "$(state)" = '["allow","environment"]' ]
  [ "$(settings '.autoMode | keys_unsorted | sort')" = '["allow","environment","hard_deny"]' ]

  # `haus reset` of both: the next rebuild declares nothing.
  run -0 activation '[]' '{}'
  [ "$(state)" = '[]' ]
  [ "$(settings '.autoMode')" = '{"hard_deny":["Keychain export: never, for any reason."]}' ]

  # And again — the second reset in the measurement cleared nothing, because
  # there was nothing recorded to clear. Now there is, and it stays cleared.
  run -0 activation '[]' '{}'
  [ "$(state)" = '[]' ]
  [ "$(settings '.autoMode')" = '{"hard_deny":["Keychain export: never, for any reason."]}' ]
}

@test "a machine that never named a section gets no state file and no key" {
  run -0 activation '[]' '{}'
  [ ! -e "$HOME/.local/state/haus/claude-auto-mode-sections" ]
  [ "$(settings 'has("autoMode")')" = false ]
  # The seed and both temporaries clean up after themselves, so nothing sits
  # beside the real file looking like something Claude should read.
  run -0 ls -A "$HOME/.claude"
  [ "$output" = settings.json ]
}

@test "a record jq cannot parse costs what it knows, not the merge" {
  # The one input that could wedge every rebuild rather than one section: a
  # --slurpfile jq cannot parse fails the whole run, and the hooks, the
  # statusline and `permissions.defaultMode` go unmerged with it. So a
  # truncated record is dropped before jq ever opens it — the sections it
  # named survive, which is where this started, and the file still merges.
  mkdir -p "$HOME/.claude" "$HOME/.local/state/haus"
  printf '%s' "$THEIRS" >"$HOME/.claude/settings.json"
  printf '%s' '["allo' >"$HOME/.local/state/haus/claude-auto-mode-sections"

  run -0 activation '[]' '{}'
  [ "$(settings '.permissions.defaultMode')" = '"auto"' ]
  [ "$(settings '.autoMode')" = '{"hard_deny":["Keychain export: never, for any reason."]}' ]
  # And it does not stay corrupt: the record is rewritten on the way out, so the
  # next rebuild reads a record again rather than this one forever.
  [ "$(state)" = '[]' ]
}

@test "the record is not written when the merge did not land" {
  mkdir -p "$HOME/.claude"
  printf '%s' "$THEIRS" >"$HOME/.claude/settings.json"
  # A `--slurpfile` jq cannot parse: the `&& mv` short-circuits, so the file is
  # untouched and haus must not claim a section it never managed to write —
  # claiming one would delete a live section on the NEXT rebuild.
  run -0 activation '["allow"]' 'not json at all'
  [ ! -e "$HOME/.local/state/haus/claude-auto-mode-sections" ]
  [ "$(settings '.autoMode')" = '{"hard_deny":["Keychain export: never, for any reason."]}' ]
  [ "$(settings '.theme')" = '"dark"' ]
}

@test "the activation block carries exactly two apostrophes: its own delimiters" {
  # ⚠️ The whole script is ONE single-quoted `sh -c` argument. A third
  # apostrophe anywhere in it — a possessive in a COMMENT is how it happened on
  # 2026-08-27 — ends that argument early, and every word after it re-parses
  # into something that still builds and means something else. Nothing but
  # running it catches that, which is what the cases above do; this is what
  # catches it in review.
  awk '
    /home\.activation\.claudeCodeSettings/ { want = 1 }
    want && /run sh -c/                    { inblk = 1 }
    inblk                                  { print }
    inblk && /autoModeSectionNames/        { exit }
  ' "$MODULE" >"$TMP/block.nix"
  # `''${` is how a Nix indented string spells a shell expansion, and it is two
  # apostrophes that never reach the shell — unwrap those first, exactly as the
  # helper above does, and what is left is the argument as `sh` will read it.
  quotes=$(sed "s|''\${|\${|g" "$TMP/block.nix" | tr -cd "'" | wc -c | tr -d ' ')
  [ "$quotes" = 2 ]
}

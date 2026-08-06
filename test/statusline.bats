#!/usr/bin/env bats
# Hermetic tests for the statusline RENDER path (modules/den/statusline.sh) —
# the inline half of the agent-worktree bar, and specifically the Fable/Mythos
# row tint.
#
# Why a suite for a cosmetic feature. The tint is the one thing in this script
# whose correctness is a WIDTH invariant rather than a string: a background only
# paints where a character is, so every row has to be padded to exactly the same
# visible column count or the block renders as a ragged blob. That count is
# computed by stripping SGR *and* OSC 8 from a line that legitimately contains
# both — so it breaks quietly whenever someone adds a segment, and it breaks in
# a way that looks like "the terminal did something weird", not like a bug here.
# The other half is the reset dance: every segment ends in $R, which the tint
# re-arms, and a single stray bare reset punches a hole in the middle of the bar.
#
# Everything is substituted — HOME, CLAUDE_STATUSLINE_CACHE, cwd — so the suite
# never reads the real panel cache and never fires the detached refresher (it
# resolves to $HOME/.claude/statusline-refresh.sh, which does not exist here).
#
# One trap, since every assertion here matches escape bytes: an SGR sequence
# contains a '[', which `[[ x == $pat ]]` reads as a BRACKET EXPRESSION unless
# the pattern is quoted. `*"$RESET"*` is a literal match; *$'\033[0m'* silently
# means something else entirely and passes for the wrong reason. Always quote.

bats_require_minimum_version 1.5.0

fail() { printf '%s\n' "$*" >&2; return 1; }   # not a bats builtin

ESC=$'\033'
RESET="${ESC}[0m"
TINT="${ESC}[48;2;56;39;19m"

setup() {
  SL="${STATUSLINE_UNDER_TEST:-$BATS_TEST_DIRNAME/../modules/den/statusline.sh}"
  TMP="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"

  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=t@example.com
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=t@example.com

  export HOME="$TMP/home"
  export CLAUDE_STATUSLINE_CACHE="$TMP/cache"
  export COLUMNS=100
  WIDTH=92                      # COLUMNS - the script's RESERVE=8
  mkdir -p "$HOME" "$CLAUDE_STATUSLINE_CACHE"
  unset ZELLIJ_PANE_ID          # no pane→transcript upsert from a test

  REPO="$TMP/wtbase/demo/joyful-pond"
  mkdir -p "$REPO"
  git -C "$REPO" init -q -b main
  git -C "$REPO" remote add origin https://github.com/nebelhaus/demo.git
  git -C "$REPO" commit -q --allow-empty -m init
  git -C "$REPO" checkout -q -b worktree-joyful-pond

  # One child row, so the width invariant is tested across BOTH row shapes.
  printf 'nebelhaus/pounce\tsome-child\t2\t0\t0\t0\t#41 open\t%s\n' \
    "$REPO" >"$CLAUDE_STATUSLINE_CACHE/panel.tsv"
}

# render <model-id> — run the script with a minimal but realistic payload.
render() {
  printf '{"model":{"id":"%s"},"workspace":{"current_dir":"%s"},"cost":{"total_cost_usd":1.23},"context_window":{"used_percentage":42},"permission_mode":"acceptEdits"}' \
    "$1" "$REPO" | bash "$SL"
}

# vis <line> — visible column count: strip OSC 8 hyperlinks, then SGR. Same
# transform as the script's own plain(); duplicated on purpose, so a bug in
# plain() can't hide itself by being used to check its own output.
vis() {
  printf '%s' "$1" |
    sed 's/\x1b]8;;[^\\]*\x1b\\//g; s/\x1b\[[0-9;]*m//g' |
    LC_ALL=en_US.UTF-8 wc -m | tr -d ' '
}

@test "fable arms the row tint" {
  run -0 render claude-fable-5
  [[ "$output" == *"$TINT"* ]] || fail "no tint on fable"
}

@test "mythos arms the same tint as fable" {
  run -0 render claude-mythos-5
  [[ "$output" == *"$TINT"* ]] || fail "no tint on mythos"
}

@test "every other tier renders no background at all" {
  for m in claude-opus-5 claude-sonnet-5 claude-haiku-4-5-20251001 some-other-model; do
    run -0 render "$m"
    [[ "$output" != *"${ESC}[48"* ]] || fail "background leaked on $m"
  done
}

@test "tinted rows are all padded to the same visible width" {
  run -0 render claude-fable-5
  [ "${#lines[@]}" -ge 2 ] || fail "expected row 1 plus a child row"
  for l in "${lines[@]}"; do
    [ "$(vis "$l")" -eq "$WIDTH" ] || fail "row is $(vis "$l") cols, want $WIDTH"
  done
}

@test "a tinted row ends in a bare reset, never in whitespace" {
  # The pad sits BEFORE the final reset precisely so nothing downstream can trim
  # the tint back off the end of the line. Guard that ordering.
  run -0 render claude-fable-5
  for l in "${lines[@]}"; do
    [ "${l: -4}" = "$RESET" ] || fail "row does not end in a bare reset"
  done
}

@test "no bare reset punches a hole in the tint" {
  # Every reset except the line's last must be immediately followed by the tint
  # being re-armed — that is what $R does. A bare one mid-row is a gap in the bar.
  run -0 render claude-fable-5
  for l in "${lines[@]}"; do
    body="${l%"$RESET"}"                       # drop the one legitimate reset
    holes=$(printf '%s' "$body" |
      sed "s/$(printf '\033')\[0m$(printf '\033')\[48;2;[0-9;]*m//g" |
      grep -c "$(printf '\033')\[0m" || true)
    [ "$holes" -eq 0 ] || fail "$holes bare reset(s) left a gap in the tint"
  done
}

@test "tinting leaves the OSC 8 PR hyperlinks intact" {
  # printf %b would eat the ST's literal backslash and silently kill every link;
  # emit() uses %s. Assert both halves of the sequence survive.
  run -0 render claude-fable-5
  [[ "$output" == *"${ESC}]8;;https://github.com/nebelhaus/pounce/pull/41${ESC}\\"* ]] ||
    fail "the link's opening half did not survive the tint"
  [[ "$output" == *"${ESC}]8;;${ESC}\\"* ]] ||
    fail "the link's closing half did not survive the tint"
}

@test "the child-PR cluster rides the tail group, not the head of row 1" {
  # It used to be pinned to the far LEFT, which pushed this pane's own lead glyph
  # and worktree name rightwards by however many children happened to have PRs
  # open. Row 1 must start with the pane's own identity and end with
  # "<child PRs>  <chips>"; assert the ORDER on the stripped line, so a future
  # segment added to the tail can't quietly put the cluster back in front.
  run -0 render claude-opus-5
  local bare; bare=$(printf '%s' "${lines[0]}" |
    sed 's/\x1b]8;;[^\\]*\x1b\\//g; s/\x1b\[[0-9;]*m//g')
  [[ "$bare" == "⏏ joyful-pond"* ]] ||
    fail "row 1 no longer leads with its own status+name: $bare"
  [[ "$bare" == *"41  42% \$1.23"* ]] ||
    fail "the cluster is not sitting just left of the chips: $bare"
}

@test "an untinted row keeps its old ragged-right shape" {
  # The tint must be strictly additive: on any other model rows stay unpadded,
  # which is exactly what they were before emit() existed.
  run -0 render claude-opus-5
  [ "$(vis "${lines[-1]}")" -lt "$WIDTH" ] || fail "an untinted row got padded"
}

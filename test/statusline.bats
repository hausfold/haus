#!/usr/bin/env bats
# Hermetic tests for the statusline RENDER path (modules/core/statusline.sh) —
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
  SL="${STATUSLINE_UNDER_TEST:-$BATS_TEST_DIRNAME/../modules/core/statusline.sh}"
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

@test "child rows use their status token as the bullet" {
  run -0 render claude-opus-5
  local bare; bare=$(printf '%s' "${lines[1]}" |
    sed 's/\x1b]8;;[^\\]*\x1b\\//g; s/\x1b\[[0-9;]*m//g')
  [ "$bare" = "  2^ pounce #41 some-child" ] ||
    fail "child status is not its leading bullet: $bare"
  [[ "$bare" != *"○"* ]] || fail "the old circle bullet survived: $bare"
}

@test "active child rows stay above reapable rows before the row cap" {
  : >"$CLAUDE_STATUSLINE_CACHE/panel.tsv"
  for i in 1 2 3 4 5 6 7 8; do
    printf 'nebelhaus/pounce\tmerged-%s\t1\t0\t0\t0\t#%s merged\t%s\n' \
      "$i" "$i" "$REPO" >>"$CLAUDE_STATUSLINE_CACHE/panel.tsv"
  done
  printf 'nebelhaus/pounce\tactive\t1\t0\t0\t0\t#99 open\t%s\n' \
    "$REPO" >>"$CLAUDE_STATUSLINE_CACHE/panel.tsv"

  run -0 render claude-opus-5
  local bare; bare=$(printf '%s\n' "${lines[@]}" |
    sed 's/\x1b]8;;[^\\]*\x1b\\//g; s/\x1b\[[0-9;]*m//g')
  [ "${lines[1]}" ] || fail "no first child row rendered"
  local first_child; first_child=$(printf '%s' "${lines[1]}" |
    sed 's/\x1b]8;;[^\\]*\x1b\\//g; s/\x1b\[[0-9;]*m//g')
  [ "$first_child" = "  1^ pounce #99 active" ] ||
    fail "the active child did not lead: $first_child"
  [[ "$bare" != *"merged-8"* ]] ||
    fail "the last reapable row displaced active work instead of falling under the cap"
  [[ "$bare" == *"+1 more"* ]] || fail "the capped reapable row was not counted"
}

@test "an orphan worktree is marked, and only in the \$HOME pane" {
  # No recorded parent (trailing field empty) — a raw `git worktree add` that
  # skipped `holt child`, so nothing in the registry knows who owns it. The
  # $HOME pane is the only one that surfaces those, and the ◇ is the "adopt or
  # reap me" flag: a child and an orphan must not render identically.
  printf 'nebelhaus/pounce\tstray\t1\t0\t0\t0\t#7 open\t\n' \
    >"$CLAUDE_STATUSLINE_CACHE/panel.tsv"

  # From a worktree pane: not $HOME, so the orphan isn't surfaced at all.
  run -0 render claude-opus-5
  [[ "$output" != *"stray"* ]] || fail "an orphan leaked into a non-\$HOME pane"

  # From $HOME: surfaced, and marked.
  local out
  out=$(printf '{"model":{"id":"claude-opus-5"},"workspace":{"current_dir":"%s"},"cost":{"total_cost_usd":1.23},"context_window":{"used_percentage":42}}' \
    "$HOME" | bash "$SL")
  [[ "$out" == *"stray"* ]] || fail "the orphan is not surfaced at \$HOME: $out"
  [[ "$out" == *"◇"* ]] || fail "the orphan carries no ◇ marker: $out"
}

@test "a parented child carries no orphan marker" {
  run -0 render claude-opus-5
  [[ "$output" != *"◇"* ]] || fail "a parented child was marked as an orphan"
}

# --- ctx% colour banding ----------------------------------------------------
# The band is keyed to the ABSOLUTE token count, never the percentage: the same
# 42% is 84k tokens on a 200k model and 420k on a 1M one, so a percentage-keyed
# colour would mean two different things in two panes of the same fleet. Every
# case below therefore holds the percentage fixed at 42 and moves only the token
# counts, which is precisely the confusion these tests exist to catch.

# render_ctx <input-tokens> <output-tokens> — 42% in every case, on purpose.
render_ctx() {
  printf '{"model":{"id":"claude-opus-5"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":42,"total_input_tokens":%s,"total_output_tokens":%s}}' \
    "$REPO" "$1" "$2" | bash "$SL"
}

@test "ctx% is green under 100k tokens" {
  run -0 render_ctx 99000 999
  [[ "$output" == *"${ESC}[38;5;71m42%"* ]] || fail "99999 tokens is not green: $output"
}

@test "ctx% is yellow from 100k to 200k tokens" {
  run -0 render_ctx 100000 0
  [[ "$output" == *"${ESC}[38;5;179m42%"* ]] || fail "100k tokens is not yellow: $output"
  run -0 render_ctx 199000 999
  [[ "$output" == *"${ESC}[38;5;179m42%"* ]] || fail "199999 tokens is not yellow: $output"
}

@test "ctx% is red at 200k tokens and beyond" {
  run -0 render_ctx 200000 0
  [[ "$output" == *"${ESC}[38;5;167m42%"* ]] || fail "200k tokens is not red: $output"
  run -0 render_ctx 700000 12000
  [[ "$output" == *"${ESC}[38;5;167m42%"* ]] || fail "712k tokens is not red: $output"
}

@test "output tokens count toward the band, not just input" {
  # 99k input alone is green; the same input with 2k of output crosses into
  # yellow. A band computed from total_input_tokens only would stay green.
  run -0 render_ctx 99000 2000
  [[ "$output" == *"${ESC}[38;5;179m42%"* ]] || fail "output tokens were ignored: $output"
}

@test "ctx% falls back to dim gray when the payload carries no token counts" {
  # The one payload that reaches this path: a Claude Code old enough to predate
  # the two fields. Guess nothing, keep the colour the chip has always had. A
  # FRESH session is NOT this case — the payload builder defaults both counts to
  # 0 rather than omitting them, so it takes the green branch (next test).
  run -0 render claude-opus-5
  [[ "$output" == *"${ESC}[38;5;244m42%"* ]] || fail "no dim fallback: $output"
}

@test "a fresh session's real 0/0 payload is green, not the dim fallback" {
  run -0 render_ctx 0 0
  [[ "$output" == *"${ESC}[38;5;71m42%"* ]] || fail "0 tokens is not green: $output"
}

@test "an untinted row keeps its old ragged-right shape" {
  # The tint must be strictly additive: on any other model rows stay unpadded,
  # which is exactly what they were before emit() existed.
  run -0 render claude-opus-5
  [ "$(vis "${lines[-1]}")" -lt "$WIDTH" ] || fail "an untinted row got padded"
}

#!/usr/bin/env bats
# Hermetic tests for the statusline RENDER path (modules/ai/statusline.sh) —
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

# real_ui_sh — snug's bash painter, wherever this machine keeps it. The suite
# reads the ROLE ESCAPES back out of it rather than spelling them, which is the
# whole point of the move: a hardcoded `\033[38;2;171;225;166m` in here would be
# the same drift one layer up, and it would go stale the first time nebelung
# retunes a token or the machine changes flavour.
real_ui_sh() {
  local q
  for q in "${HAUS_UI_SH:-}" \
           "$BATS_TEST_DIRNAME/../../snug/share/ui.sh" \
           "$HOME/code/workshop/snug/share/ui.sh"; do
    [ -n "$q" ] && [ -r "$q" ] && { printf '%s' "$q"; return 0; }
  done
  return 1
}

setup() {
  SL="${STATUSLINE_UNDER_TEST:-$BATS_TEST_DIRNAME/../modules/ai/statusline.sh}"
  TMP="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"

  # ── the colour environment, pinned ─────────────────────────────────────────
  # Load-bearing since the script grew a gate. It has none of its own colour
  # any more: every escape below comes from ui.sh, whose profile is decided by
  # TERM/COLORTERM/NO_COLOR — and the two machines that run this suite disagree
  # about all three. A developer's terminal says truecolor; a GitHub runner sets
  # TERM=dumb for every `run:` step, which ui.sh honours absolutely. Unpinned,
  # every assertion here passes locally and fails in CI. (phase-painter.bats
  # pins the same three for the same reason, and says so at greater length.)
  export TERM=xterm-256color COLORTERM=truecolor
  unset NO_COLOR CLICOLOR_FORCE SNUG_VARIANT

  UI_SH_REAL="$(real_ui_sh || true)"
  R_OK=; R_WARN=; R_ERR=; R_MUTED=; R_SUBJECT=; R_ACCENT=
  if [ -n "$UI_SH_REAL" ]; then
    # A subshell, and UI_TTY forced the way the script itself forces it — the
    # suite has no terminal either, and it must resolve the SAME palette the
    # script will or every match below is a coincidence.
    # UI_TTY is set AFTER the source, never before: ui.sh measures fd 2 at load
    # and assigns UI_TTY itself, so a value set first is overwritten and the
    # palette resolves to `none`. That ordering is the script's too, and getting
    # it backwards here cost six SKIPPED tests that read as six passes.
    eval "$(env -u UI_SH bash -c '
      . "$1"; UI_TTY=1; ui__detect_profile; ui__resolve_palette
      for r in OK WARN ERR MUTED SUBJECT ACCENT; do
        eval "v=\$UI_$r"; printf "R_%s=%q\n" "$r" "$v"
      done' _ "$UI_SH_REAL")"
  fi

  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=t@example.com
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=t@example.com

  export HOME="$TMP/home"
  export CLAUDE_STATUSLINE_CACHE="$TMP/cache"
  export COLUMNS=100
  WIDTH=92                      # COLUMNS - the script's RESERVE=8
  mkdir -p "$HOME" "$CLAUDE_STATUSLINE_CACHE"
  unset ZMX_SESSION             # no session→transcript upsert from a test

  REPO="$TMP/wtbase/demo/joyful-pond"
  mkdir -p "$REPO"
  git -C "$REPO" init -q -b main
  git -C "$REPO" remote add origin https://github.com/hausfold/demo.git
  git -C "$REPO" commit -q --allow-empty -m init
  git -C "$REPO" checkout -q -b worktree-joyful-pond

  # One child row, so the width invariant is tested across BOTH row shapes.
  printf 'hausfold/pounce\tsome-child\t2\t0\t0\t0\t#41 open\t%s\n' \
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
  [[ "$output" == *"${ESC}]8;;https://github.com/hausfold/pounce/pull/41${ESC}\\"* ]] ||
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
  [[ "$bare" == "● joyful-pond"* ]] ||
    fail "row 1 no longer leads with its own status+name: $bare"
  [[ "$bare" == *"41  42% \$1.23"* ]] ||
    fail "the cluster is not sitting just left of the chips: $bare"
}

@test "a lane that has never committed leads with ●, not ⏏" {
  # ⏏ says "landed, and scruff reaps this on pane close" — and it is read as
  # "merged". A branch cut from main is trivially an ancestor of main, so the
  # ancestry test alone put that on every agent from the second it spawned.
  # The fixture branch is exactly that lane: created, never committed.
  run -0 render claude-opus-5
  local bare; bare=$(printf '%s' "${lines[0]}" | sed 's/\x1b]8;;[^\\]*\x1b\\//g; s/\x1b\[[0-9;]*m//g')
  [[ "$bare" == "● joyful-pond"* ]] || fail "an empty lane is not landed: $bare"
}

@test "a lane whose commit landed still leads with ⏏" {
  # The other direction, and the one that must not move: this branch committed
  # and main fast-forwarded onto it, so it has no commits of its own left to
  # count either. Only its reflog separates it from the empty lane above.
  git -C "$REPO" commit -q --allow-empty -m work
  git -C "$REPO" branch -f main HEAD
  run -0 render claude-opus-5
  local bare; bare=$(printf '%s' "${lines[0]}" | sed 's/\x1b]8;;[^\\]*\x1b\\//g; s/\x1b\[[0-9;]*m//g')
  [[ "$bare" == "⏏ joyful-pond"* ]] || fail "a landed lane lost its ⏏: $bare"
}

@test "a tip moved by anything but its own creation keeps ⏏" {
  # `commit:` is NOT every way git spells "something happened here": cherry-pick,
  # revert, rebase and reset each write their own reflog subject. So the rule is
  # inverted — nothing but `branch: Created from …` counts as empty — and this
  # pins it with a tip moved by `reset`, which a prefix hunt would call empty.
  git -C "$REPO" checkout -q main
  git -C "$REPO" commit -q --allow-empty -m "landed elsewhere"
  git -C "$REPO" checkout -q worktree-joyful-pond
  git -C "$REPO" reset -q --hard main
  run -0 render claude-opus-5
  local bare; bare=$(printf '%s' "${lines[0]}" | sed 's/\x1b]8;;[^\\]*\x1b\\//g; s/\x1b\[[0-9;]*m//g')
  [[ "$bare" == "⏏ joyful-pond"* ]] || fail "a hand-moved tip read as empty: $bare"
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
    printf 'hausfold/pounce\tmerged-%s\t1\t0\t0\t0\t#%s merged\t%s\n' \
      "$i" "$i" "$REPO" >>"$CLAUDE_STATUSLINE_CACHE/panel.tsv"
  done
  printf 'hausfold/pounce\tactive\t1\t0\t0\t0\t#99 open\t%s\n' \
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
  # skipped `scruff child`, so nothing in the registry knows who owns it. The
  # $HOME pane is the only one that surfaces those, and the ◇ is the "adopt or
  # reap me" flag: a child and an orphan must not render identically.
  printf 'hausfold/pounce\tstray\t1\t0\t0\t0\t#7 open\t\n' \
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

need_roles() { [ -n "$R_OK" ] || skip "no snug share/ui.sh on this machine"; }

# render_ctx <input-tokens> <output-tokens> — 42% in every case, on purpose.
render_ctx() {
  printf '{"model":{"id":"claude-opus-5"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":42,"total_input_tokens":%s,"total_output_tokens":%s}}' \
    "$REPO" "$1" "$2" | bash "$SL"
}

@test "ctx% takes the ok role under 100k tokens" {
  need_roles
  run -0 render_ctx 99000 999
  [[ "$output" == *"${R_OK}42%"* ]] || fail "99999 tokens is not ok: $output"
}

@test "ctx% takes the warn role from 100k to 200k tokens" {
  need_roles
  run -0 render_ctx 100000 0
  [[ "$output" == *"${R_WARN}42%"* ]] || fail "100k tokens is not warn: $output"
  run -0 render_ctx 199000 999
  [[ "$output" == *"${R_WARN}42%"* ]] || fail "199999 tokens is not warn: $output"
}

@test "ctx% takes the err role at 200k tokens and beyond" {
  need_roles
  run -0 render_ctx 200000 0
  [[ "$output" == *"${R_ERR}42%"* ]] || fail "200k tokens is not err: $output"
  run -0 render_ctx 700000 12000
  [[ "$output" == *"${R_ERR}42%"* ]] || fail "712k tokens is not err: $output"
}

@test "output tokens count toward the band, not just input" {
  # 99k input alone is green; the same input with 2k of output crosses into
  # yellow. A band computed from total_input_tokens only would stay green.
  need_roles
  run -0 render_ctx 99000 2000
  [[ "$output" == *"${R_WARN}42%"* ]] || fail "output tokens were ignored: $output"
}

@test "ctx% falls back to the muted role when the payload carries no token counts" {
  # The one payload that reaches this path: a Claude Code old enough to predate
  # the two fields. Guess nothing, keep the colour the chip has always had. A
  # FRESH session is NOT this case — the payload builder defaults both counts to
  # 0 rather than omitting them, so it takes the green branch (next test).
  need_roles
  run -0 render claude-opus-5
  [[ "$output" == *"${R_MUTED}42%"* ]] || fail "no muted fallback: $output"
}

@test "a fresh session's real 0/0 payload takes ok, not the muted fallback" {
  need_roles
  run -0 render_ctx 0 0
  [[ "$output" == *"${R_OK}42%"* ]] || fail "0 tokens is not ok: $output"
}

@test "an untinted row keeps its old ragged-right shape" {
  # The tint must be strictly additive: on any other model rows stay unpadded,
  # which is exactly what they were before emit() existed.
  run -0 render claude-opus-5
  [ "$(vis "${lines[-1]}")" -lt "$WIDTH" ] || fail "an untinted row got padded"
}

# no_csi <what> — assert the last run emitted no CSI sequence, which is every
# colour there is. Deliberately NOT "no ESC at all": the PR numbers are OSC 8
# hyperlinks (`ESC ] 8 ;;`), and a hyperlink is structure, not colour. It stays
# on a monochrome terminal for the same reason the ⏏ glyph does — turning colour
# off must not cost you the ability to click a PR. Measured: the first cut of
# these two tests banned ESC outright and failed on exactly that.
no_csi() {
  [[ "$output" != *"${ESC}["* ]] \
    || fail "$1: $(printf '%s' "$output" | sed -n l)"
}

# ── the colour gate ──────────────────────────────────────────────────────────
# New with the move onto snug's roles. Before it the script had no gate at all:
# it painted eleven hardcoded 256-colour indices unconditionally, so NO_COLOR
# and TERM=dumb did nothing here and there was nothing to test.

@test "NO_COLOR strips every colour, the row tint included" {
  # The tint is the trap. It is a RAW escape — snug's nine roles are all
  # foreground and there is no background among them — so unlike every other
  # colour in the file it does not go empty on its own. Measured before the
  # gate existed: NO_COLOR left the whole block on a warm band with the text
  # back to terminal default, which is worse than no gate at all.
  run -0 env NO_COLOR=1 bash -c 'printf "%s" "$1" | bash "$2"' _ \
    "$(printf '{"model":{"id":"claude-fable-5"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":42}}' "$REPO")" "$SL"
  no_csi "escape survived NO_COLOR"
}

@test "TERM=dumb strips every colour, the row tint included" {
  # dumb means it, and ui.sh honours it even under CLICOLOR_FORCE — there is no
  # escape a dumb terminal will not print at you literally. This is also the
  # shape of a GitHub runner, which is why setup() pins TERM for everything else.
  run -0 env TERM=dumb CLICOLOR_FORCE=1 bash -c 'printf "%s" "$1" | bash "$2"' _ \
    "$(printf '{"model":{"id":"claude-fable-5"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":42}}' "$REPO")" "$SL"
  no_csi "escape survived TERM=dumb"
}

@test "the tint needs truecolor, because it has no cube equivalent" {
  # #382713 is simultaneously darker and more saturated than anything in the
  # 256-colour cube, so a 256 terminal gets NO tint rather than an approximation
  # that would land somewhere else entirely. Foregrounds still resolve.
  run -0 env COLORTERM= TERM=xterm-256color bash -c 'printf "%s" "$1" | bash "$2"' _ \
    "$(printf '{"model":{"id":"claude-fable-5"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":42}}' "$REPO")" "$SL"
  [[ "$output" != *"${ESC}[48"* ]] || fail "tint painted on a 256 terminal"
  [[ "$output" == *"${ESC}[38;5;"* ]] || fail "no cube foreground on a 256 terminal: $output"
}

@test "colour survives having no terminal on either descriptor" {
  # THE thing this caller does differently from every other in the family. A
  # statusline renders with stdout captured by Claude Code, so `[ -t 2 ]` is
  # false and ui.sh's own gate would answer "no colour" for output that lands in
  # a terminal regardless. The script forces UI_TTY rather than measuring it.
  # Every other assertion in this file depends on that and none of them says so.
  need_roles
  run -0 render claude-opus-5
  [[ "$output" == *"${ESC}["* ]] || fail "no colour without a tty: $output"
}

@test "no retired 256-colour index is left in the rendered line" {
  # The eleven this script used to spell by hand. They are not merely gone from
  # the source (the ban in phase-painter.bats covers that) — they must not come
  # back through a helper either, and 244 in particular is one keystroke from
  # nebelung's overlay1.
  need_roles
  local idx
  run -0 render claude-fable-5
  for idx in 108 244 75 71 167 173 179 139; do
    [[ "$output" != *"${ESC}[38;5;${idx}m"* ]] || fail "hand-picked index $idx is back"
  done
}

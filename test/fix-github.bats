#!/usr/bin/env bats
# Hermetic tests for the pure halves of modules/ai/fix-github.sh — the binary
# behind the github pill's "Fix with AI" rows.
#
# The parts worth pinning are the ones whose failure mode is a LANE SPAWNED ON
# THE WRONG BRIEF, which no feel-test catches: the row's URL mis-parsed (an
# owner/repo from the wrong two path segments, and every prompt after it
# names the wrong repo), a verdict falling out of its arm (a conflict PR
# briefed as a CI failure, or worse: a selector read as a PR number when it
# was a branch), and a lane name that ate a slash (`haus/bar-fix` — branch
# names carry them, lane names may not).
#
# The subject is not sourceable — it is a command that dispatches on argv and
# spawns — so the three pure functions are lifted out of it by name. That
# keeps the assertions pinned to the real source rather than to a copy: rename
# or reshape one of them and the extraction fails loudly instead of testing
# text that no longer exists.

bats_require_minimum_version 1.5.0

# Lift named functions out of a script that is not sourceable, into a file the
# test can `.`. Keeps the assertions pinned to the real source rather than to a
# copy: rename or reshape one and the lift fails loudly instead of testing text
# that no longer exists.
lift() { # lift <script> <into> <fn>…
  local script="$1" into="$2" fn
  shift 2
  [ -f "$script" ] || {
    echo "subject missing: $script" >&2
    return 1
  }
  for fn in "$@"; do
    awk -v fn="$fn" '
      $0 ~ "^" fn "\\(\\) \\{" { inside = 1 }
      inside { print }
      inside && /^}$/ { inside = 0; found = 1 }
      !inside && $0 ~ "^" fn "\\(\\) \\{.*; \\}$" { print; found = 1 }
      END { if (!found) exit 1 }
    ' "$script" >>"$into" || {
      echo "could not lift $fn out of $script" >&2
      return 1
    }
  done
}

setup() {
  SUBJECT="$BATS_TEST_DIRNAME/../modules/ai/fix-github.sh"
  # The pill is the other half of the same feature and the same contract: it
  # WRITES the `<verdict>:<target>` field this binary is called with, so the
  # split and the argv check are pinned in one suite. A cache format agreed on
  # by two files and by nothing mechanical is the drift AGENTS.md keeps naming.
  PILL="$BATS_TEST_DIRNAME/../modules/bar/sketchybar/plugins/github.sh"

  local lifted="$BATS_TEST_TMPDIR/pure.sh"
  : >"$lifted"
  lift "$SUBJECT" "$lifted" \
    owner_repo_from_url build_prompt lane_name resolve_repo resolve_agent || return 1
  lift "$PILL" "$lifted" fix_split || return 1
  # shellcheck disable=SC1090
  . "$lifted"

  # resolve_repo touches $HOME (the scruff registry) and the filesystem (the
  # roots). The whole suite runs under a throwaway HOME — the lift never runs
  # the subject's own ROOTS=@repoRoots@ line, so ROOTS is per-test.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

# A real checkout, for remote-match tests: resolve_repo greps `git remote
# get-url origin`, so a bare .git directory can only ever match by basename.
# A shell function, not a fixture in setup — the tests below need different
# layouts.
real_repo() { # real_repo <path> <origin-url>
  git init -q "$1" && git -C "$1" remote add origin "$2"
}

# One of the pill's jq programs, lifted whole: from the line naming its root
# path down to the line that closes the single-quoted argument. Same reason as
# the function lift — the row format is the contract between the two files in
# this suite, and a copy of the program here would agree with itself forever.
jq_program() { # jq_program <script> <root-path-marker>
  awk -v m="$2" '
    index($0, m) { on = 1 }
    on { print }
    on && /'"'"'\)[ \t]*$/ { exit }
  ' "$1" | sed "s/')[ \t]*\$//"
}

# The row a fetch writes for one GraphQL node, with the unit separator turned
# into a newline so `sed -n 6p` is field 6 — the fix handoff.
fix_field() { # fix_field <rows>
  printf '%s' "$1" | tr '\037' '\n' | sed -n '6p'
}

# ── owner_repo_from_url ───────────────────────────────────────────────────────

@test "owner_repo_from_url: a plain repo URL" {
  run owner_repo_from_url "https://github.com/hausfold/haus"
  [ "$status" -eq 0 ]
  [ "$output" = "hausfold/haus" ]
}

@test "owner_repo_from_url: a PR URL (the pull path is dropped)" {
  run owner_repo_from_url "https://github.com/hausfold/haus/pull/597"
  [ "$status" -eq 0 ]
  [ "$output" = "hausfold/haus" ]
}

@test "owner_repo_from_url: a branch URL (the tree path is dropped)" {
  run owner_repo_from_url "https://github.com/hausfold/haus/tree/worktree-fix-ci"
  [ "$status" -eq 0 ]
  [ "$output" = "hausfold/haus" ]
}

@test "owner_repo_from_url: trailing slash and query string" {
  run owner_repo_from_url "https://github.com/hausfold/pounce/?x=1"
  [ "$status" -eq 0 ]
  [ "$output" = "hausfold/pounce" ]
}

@test "owner_repo_from_url: not github.com is a refusal, not a parse" {
  run owner_repo_from_url "https://gitlab.com/hausfold/haus"
  [ "$status" -ne 0 ]
  run owner_repo_from_url "not a url"
  [ "$status" -ne 0 ]
}

@test "owner_repo_from_url: a host-less fragment is not owner/repo" {
  run owner_repo_from_url "https://github.com/hausfold"
  [ "$status" -ne 0 ]
}

@test "owner_repo_from_url: an EMPTY segment is a refusal, not half an answer" {
  # `//haus` and `hausfold/` each parse to an owner or a repo named "", which
  # reaches the brief as "PR #12 in /haus" and resolve_repo as a basename of
  # "" that matches nothing. Refusing is a banner; half-answering is a lane.
  run owner_repo_from_url "https://github.com//haus"
  [ "$status" -ne 0 ]
  run owner_repo_from_url "https://github.com/hausfold/"
  [ "$status" -ne 0 ]
}

@test "owner_repo_from_url: a fragment is dropped like a query string" {
  run owner_repo_from_url "https://github.com/hausfold/haus/pull/12#issuecomment-1"
  [ "$status" -eq 0 ]
  [ "$output" = "hausfold/haus" ]
}

# ── fix_split (the pill's half of the same contract) ──────────────────────────

@test "fix_split: each verdict the fixer accepts round-trips" {
  fix_split "ci:main"
  [ "$FIX_VERDICT" = "ci" ] && [ "$FIX_TARGET" = "main" ]
  fix_split "checks-red:597"
  [ "$FIX_VERDICT" = "checks-red" ] && [ "$FIX_TARGET" = "597" ]
  fix_split "conflicts:12"
  [ "$FIX_VERDICT" = "conflicts" ] && [ "$FIX_TARGET" = "12" ]
}

@test "fix_split: a branch with colons keeps all of them" {
  # Branch names may carry a colon; only the FIRST one is the delimiter.
  fix_split "ci:release:2026-09"
  [ "$FIX_VERDICT" = "ci" ]
  [ "$FIX_TARGET" = "release:2026-09" ]
}

@test "fix_split: empty, target-less and unknown verdicts draw no button" {
  ! fix_split ""
  ! fix_split "ci"          # an older generation's cache: a bare target
  ! fix_split "ci:"         # a verdict with nothing to act on
  ! fix_split "597"         # the FIELD THIS PR'S FIRST DRAFT WROTE — a bare
                            # PR number. A rollback leaves those caches on
                            # disk, and they must not spawn anything.
  ! fix_split "changes-requested:3"
}

@test "fix_split: the pill's verdicts and the fixer's argv are the same list" {
  # The two lists live in two files and nothing else joins them. A verdict the
  # pill will draw a button for but the fixer's `case` refuses is a click that
  # ends in `usage`, exit 64, with no banner — the silent half of a rename.
  local argv fixer=" " v
  argv="$(grep -m1 '^case "\$verdict" in' "$SUBJECT")"
  [ -n "$argv" ] || {
    echo "could not find haus-fix-github's verdict case" >&2
    return 1
  }
  argv="${argv#*in }"
  argv="${argv%%)*}"
  for v in $argv; do
    [ "$v" = "|" ] || fixer="$fixer$v "
  done
  [ "$fixer" = " ci checks-red conflicts " ] || {
    echo "the fixer accepts '$fixer' — update fix_split in the pill to match" >&2
    return 1
  }
  for v in $argv; do
    [ "$v" = "|" ] && continue
    fix_split "$v:x" || {
      echo "the pill's fix_split rejects '$v', which the fixer accepts" >&2
      return 1
    }
  done
}

# ── the fetch's half: which rows get a fix field at all ───────────────────────
# The producer side of the same contract. Everything above tests what the pill
# does with field 6; this tests that the field says what it should, per verdict,
# straight out of the jq the pill actually runs. Without it the two halves can
# drift into "the button never appears" with every test green.

search_row() { # search_row <node json> → the row the search fetch would write
  local prog
  prog="$(jq_program "$PILL" '.data.search.nodes[]?')"
  [ -n "$prog" ] || {
    echo "could not lift the search fetch's jq program" >&2
    return 1
  }
  printf '{"data":{"search":{"nodes":[%s]}}}' "$1" | jq -r \
    --arg conflict C --arg failed F --arg running R --arg changes W \
    --arg ready A --arg green G --arg draft D --arg none - "$prog"
}

# A PullRequest node with everything the verdict chain reads, overridable.
pr_node() { # pr_node <n> <isDraft> <mergeable> <reviewDecision> <checks>
  printf '{"__typename":"PullRequest","number":%s,"title":"t","url":"https://github.com/o/r/pull/%s",
           "isDraft":%s,"mergeable":"%s","reviewDecision":%s,"repository":{"name":"r"},
           "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"%s"}}}]}}' \
    "$1" "$1" "$2" "$3" "$4" "$5"
}

@test "fetch_search: a conflicting PR carries conflicts:<n>" {
  command -v jq >/dev/null || skip "jq not on PATH"
  run fix_field "$(search_row "$(pr_node 1 false CONFLICTING null SUCCESS)")"
  [ "$output" = "conflicts:1" ]
}

@test "fetch_search: a red PR carries checks-red:<n>" {
  command -v jq >/dev/null || skip "jq not on PATH"
  run fix_field "$(search_row "$(pr_node 2 false MERGEABLE null FAILURE)")"
  [ "$output" = "checks-red:2" ]
}

@test "fetch_search: a DRAFT with red checks carries nothing" {
  # Draft outranks every verdict below it in the chain, and it must outrank
  # the button too: red checks on a work-in-progress are its author's problem
  # in the middle of solving it, not an agent's to jump into.
  command -v jq >/dev/null || skip "jq not on PATH"
  run fix_field "$(search_row "$(pr_node 3 true MERGEABLE null FAILURE)")"
  [ -z "$output" ]
}

@test "fetch_search: changes-requested, green and running carry nothing" {
  command -v jq >/dev/null || skip "jq not on PATH"
  local n
  for n in \
    "$(pr_node 4 false MERGEABLE '"CHANGES_REQUESTED"' SUCCESS)" \
    "$(pr_node 5 false MERGEABLE '"APPROVED"' SUCCESS)" \
    "$(pr_node 6 false MERGEABLE null PENDING)" \
    "$(pr_node 7 false UNKNOWN null SUCCESS)"; do
    run fix_field "$(search_row "$n")"
    [ -z "$output" ] || {
      echo "unexpected fix field '$output' for: $n" >&2
      return 1
    }
  done
}

@test "fetch_search: an Issue is never a fix target" {
  command -v jq >/dev/null || skip "jq not on PATH"
  run fix_field "$(search_row '{"__typename":"Issue","number":8,"title":"t",
    "url":"https://github.com/o/r/issues/8","repository":{"name":"r"}}')"
  [ -z "$output" ]
}

@test "fetch_ci: a red default branch carries ci:<branch>, a green repo no row" {
  command -v jq >/dev/null || skip "jq not on PATH"
  local prog rows
  prog="$(jq_program "$PILL" '.data.repositoryOwner.repositories.nodes[]?')"
  [ -n "$prog" ]
  rows="$(printf '{"data":{"repositoryOwner":{"repositories":{"nodes":[
    {"name":"haus","url":"https://github.com/hausfold/haus","isArchived":false,
     "defaultBranchRef":{"name":"release/2026","target":{"statusCheckRollup":{"state":"FAILURE"}}}},
    {"name":"pounce","url":"https://github.com/hausfold/pounce","isArchived":false,
     "defaultBranchRef":{"name":"main","target":{"statusCheckRollup":{"state":"SUCCESS"}}}}
  ]}}}}' | jq -r --arg failed F "$prog")"
  [ "$(printf '%s\n' "$rows" | grep -c '^row')" -eq 1 ]
  [ "$(fix_field "$rows")" = "ci:release/2026" ]
}

@test "every fix field a fetch writes is one fix_split accepts" {
  # The join. A verdict word spelled one way in the jq and another in the
  # split is a button that never draws, with no error on either side.
  command -v jq >/dev/null || skip "jq not on PATH"
  local field
  for field in \
    "$(fix_field "$(search_row "$(pr_node 1 false CONFLICTING null SUCCESS)")")" \
    "$(fix_field "$(search_row "$(pr_node 2 false MERGEABLE null ERROR)")")"; do
    fix_split "$field" || {
      echo "the pill writes '$field' and its own fix_split rejects it" >&2
      return 1
    }
  done
}

# ── build_prompt ──────────────────────────────────────────────────────────────

@test "build_prompt: ci names the branch and forbids pushing to it" {
  run build_prompt ci "main" "hausfold/haus" "https://github.com/hausfold/haus"
  [ "$status" -eq 0 ]
  [[ "$output" == *'`main`'* ]]
  [[ "$output" == *"do not push directly"* ]]
}

@test "build_prompt: the red-checks arm reads the selector as a PR number" {
  run build_prompt checks-red "597" "hausfold/haus" "https://github.com/hausfold/haus/pull/597"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PR #597 in hausfold/haus"* ]]
  [[ "$output" == *"gh pr checkout 597"* ]]
}

@test "build_prompt: the conflicts arm reads the selector as a PR number" {
  run build_prompt conflicts "12" "hausfold/pounce" "https://github.com/hausfold/pounce/pull/12"
  [ "$status" -eq 0 ]
  [[ "$output" == *"merge conflicts"* ]]
  [[ "$output" == *"PR #12"* ]]
}

@test "build_prompt: an unknown verdict has no arm — it does not silently become ci" {
  run build_prompt changes-requested "3" "hausfold/haus" "https://github.com/hausfold/haus"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── lane_name ─────────────────────────────────────────────────────────────────

@test "lane_name: a ci row names the branch, slashes flattened" {
  run lane_name ci "haus/fix-ci" "hausfold/haus"
  [ "$status" -eq 0 ]
  [ "$output" = "fix-haus-haus-fix-ci" ]
}

@test "lane_name: a PR row names the number, whatever the verdict" {
  run lane_name checks-red "597" "hausfold/haus"
  [ "$output" = "fix-haus-pr597" ]
  run lane_name conflicts "12" "hausfold/pounce"
  [ "$output" = "fix-pounce-pr12" ]
}

@test "lane_name: a branch of punctuation collapses, never vanishes" {
  run lane_name ci "---" "hausfold/haus"
  [ "$status" -eq 0 ]
  [ "$output" = "fix-haus-ci" ]
}

@test "lane_name: a long branch is cut to 48 and never ends on a dash" {
  # A lane name becomes a branch name, a zmx session name and a window title.
  # A trailing dash is legal in all three and reads as a truncation that lost
  # its last word, which is exactly what it is — so the cut takes it with it.
  run lane_name ci "release/2026-09-the-one-with-the-very-long-descriptive-name" "hausfold/haus"
  [ "$status" -eq 0 ]
  [ "${#output}" -le 48 ]
  [ "${output%-}" = "$output" ]
  case "$output" in fix-haus-release-2026-09-*) ;; *) return 1 ;; esac
}

# ── resolve_agent ─────────────────────────────────────────────────────────────

@test "resolve_agent: scruff's default wins when it is on PATH" {
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  printf '#!/bin/sh\necho codex\n' >"$bin/scruff"
  printf '#!/bin/sh\nexit 0\n' >"$bin/codex"
  printf '#!/bin/sh\nexit 0\n' >"$bin/claude"
  chmod +x "$bin/scruff" "$bin/codex" "$bin/claude"
  PATH="$bin:$PATH" run resolve_agent
  [ "$status" -eq 0 ]
  [ "$output" = "codex" ]
}

@test "resolve_agent: a default that is not installed falls to one that is" {
  # The gap the build-time gate cannot close: haus installs `claude`, the
  # person's ~/.config/scruff/config.toml names `codex`. Without this the lane
  # spawns into a pane that says "codex: command not found" — in the
  # BACKGROUND, where nobody is watching it.
  local bin="$BATS_TEST_TMPDIR/bin-missing"
  mkdir -p "$bin"
  printf '#!/bin/sh\necho codex\n' >"$bin/scruff"
  printf '#!/bin/sh\nexit 0\n' >"$bin/claude"
  chmod +x "$bin/scruff" "$bin/claude"
  PATH="$bin" run resolve_agent
  [ "$status" -eq 0 ]
  [ "$output" = "claude" ]
}

@test "resolve_agent: no client at all is a refusal, not a guess" {
  local bin="$BATS_TEST_TMPDIR/bin-empty"
  mkdir -p "$bin"
  PATH="$bin" run resolve_agent
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

# ── resolve_repo (filesystem-backed — the ROOTS split lives here) ─────────────

@test "resolve_repo: finds a repo under a configured colon-joined root" {
  local roots="$BATS_TEST_TMPDIR/roots"
  # Depth 3 — the workshop shape (~/code/workshop/haus/.git), the deepest the
  # walk reaches, mirroring spawn-agent.sh's documented depth.
  mkdir -p "$roots/workshop/haus/.git"
  ROOTS="$BATS_TEST_TMPDIR/roots"
  run resolve_repo "hausfold/haus"
  [ "$status" -eq 0 ]
  [ "$output" = "$roots/workshop/haus" ]
}

@test "resolve_repo: a root that is itself a repo is offered, not descended into" {
  local repo="$BATS_TEST_TMPDIR/roots-cfg/nix"
  mkdir -p "$repo/.git"
  ROOTS="$BATS_TEST_TMPDIR/roots-cfg/nix"
  run resolve_repo "whatever/nix"
  [ "$status" -eq 0 ]
  [ "$output" = "$repo" ]
}

@test "resolve_repo: the origin remote wins over a same-named checkout" {
  local base="$BATS_TEST_TMPDIR/remote-first"
  mkdir -p "$base"
  real_repo "$base/forks/haus" "https://gitlab.com/someone-else/haus.git"
  real_repo "$base/work/haus"  "git@github.com:hausfold/haus.git"   # SSH spelling
  ROOTS="$base"
  run resolve_repo "hausfold/haus"
  [ "$status" -eq 0 ]
  [ "$output" = "$base/work/haus" ]
}

@test "resolve_repo: SSH-only remotes match too, not just HTTPS" {
  local base="$BATS_TEST_TMPDIR/ssh-only"
  mkdir -p "$base"
  real_repo "$base/haus" "git@github.com:hausfold/haus.git"
  ROOTS="$base"
  run resolve_repo "hausfold/haus"
  [ "$status" -eq 0 ]
  [ "$output" = "$base/haus" ]
}

@test "resolve_repo: nothing under any root is a refusal" {
  local empty="$BATS_TEST_TMPDIR/empty-roots"
  mkdir -p "$empty"
  ROOTS="$empty"
  run resolve_repo "hausfold/nowhere"
  [ "$status" -ne 0 ]
}

@test "resolve_repo: a colon-joined list walks every root, not just the first" {
  local base="$BATS_TEST_TMPDIR/two-roots"
  mkdir -p "$base/a/nothing/.git" "$base/b/pounce/.git"
  ROOTS="$base/a:$base/b"
  run resolve_repo "hausfold/pounce"
  [ "$status" -eq 0 ]
  [ "$output" = "$base/b/pounce" ]
}

@test "resolve_repo: an empty ROOTS is zero roots, not an unbound array" {
  # `haus.ai.repoRoots = [ ]` bakes in an empty string, and under `set -u` a
  # bare "${roots[@]}" on bash 3.2 aborts rather than iterating zero times —
  # which the guard in the subject exists for and nothing else covered.
  mkdir -p "$HOME/.cache/scruff"
  printf 'lane\t%s\tbranch\n' "$BATS_TEST_TMPDIR/registry-only/haus" >"$HOME/.cache/scruff/registry.tsv"
  mkdir -p "$BATS_TEST_TMPDIR/registry-only/haus/.git"
  ROOTS=""
  run resolve_repo "hausfold/haus"
  [ "$status" -eq 0 ]
  [ "$output" = "$BATS_TEST_TMPDIR/registry-only/haus" ]
}

@test "resolve_repo: the scruff registry reaches a repo outside every root" {
  # Field 2 of each registry row is that worktree's MAIN checkout, so a repo
  # you have ever agent'd resolves from anywhere on disk. Untested until now,
  # and it is half of what makes the button work on a machine whose repos are
  # not under ~/code.
  local away="$BATS_TEST_TMPDIR/somewhere-else"
  real_repo "$away/perch" "https://github.com/hausfold/perch.git"
  mkdir -p "$HOME/.cache/scruff" "$BATS_TEST_TMPDIR/roots-none"
  printf 'demo\t%s\tworktree-demo\n' "$away/perch" >"$HOME/.cache/scruff/registry.tsv"
  ROOTS="$BATS_TEST_TMPDIR/roots-none"
  run resolve_repo "hausfold/perch"
  [ "$status" -eq 0 ]
  [ "$output" = "$away/perch" ]
}

@test "resolve_repo: a registry row pointing at a checkout that is gone is skipped" {
  # Reaped lanes and moved repos both leave rows behind. The walk must fall
  # through to a real candidate rather than return a path with no .git.
  local base="$BATS_TEST_TMPDIR/stale-registry"
  mkdir -p "$base/roots/haus/.git" "$HOME/.cache/scruff"
  printf 'ghost\t%s\tworktree-ghost\n' "$base/reaped/haus" >"$HOME/.cache/scruff/registry.tsv"
  ROOTS="$base/roots"
  run resolve_repo "hausfold/haus"
  [ "$status" -eq 0 ]
  [ "$output" = "$base/roots/haus" ]
}

@test "resolve_repo: a differently-named checkout of the same repo is not a match" {
  # The walk matches on basename first and confirms with the remote; a repo
  # cloned under another directory name is the documented gap, and pinning it
  # keeps the banner ("no local checkout") honest rather than silently
  # resolving to a neighbour.
  local base="$BATS_TEST_TMPDIR/renamed"
  real_repo "$base/haus-fork" "https://github.com/hausfold/haus.git"
  ROOTS="$base"
  run resolve_repo "hausfold/haus"
  [ "$status" -ne 0 ]
}

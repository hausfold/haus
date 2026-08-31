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

setup() {
  SUBJECT="$BATS_TEST_DIRNAME/../modules/ai/fix-github.sh"
  [ -f "$SUBJECT" ] || {
    echo "subject missing: $SUBJECT" >&2
    return 1
  }

  local lifted="$BATS_TEST_TMPDIR/pure.sh"
  : >"$lifted"
  local fn
  for fn in owner_repo_from_url build_prompt lane_name resolve_repo; do
    awk -v fn="$fn" '
      $0 ~ "^" fn "\\(\\) \\{" { inside = 1 }
      inside { print }
      inside && /^}$/ { inside = 0; found = 1 }
      !inside && $0 ~ "^" fn "\\(\\) \\{.*; \\}$" { print; found = 1 }
      END { if (!found) exit 1 }
    ' "$SUBJECT" >>"$lifted" || {
      echo "could not lift $fn out of the subject" >&2
      return 1
    }
  done
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

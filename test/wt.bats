#!/usr/bin/env bats
# Hermetic tests for `wt` — the agent-worktree manager (modules/den/wt.sh).
#
# Everything runs against throwaway repos in $BATS_TEST_TMPDIR: HOME, the
# worktree base (CLAUDE_WT_BASE, already an env knob) and every external tool
# wt shells out to (`gh`, `lsof`) are substituted, so the suite never touches
# the machine's real registry, real repos, or the network. `wt`'s bare-PATH
# rescue is APPENDED rather than prepended precisely so these shims win.
#
# What this pins down, roughly in the order a worktree lives:
#   create → park/unpark → list → resume → remove → reap → registry upkeep
#
# Tests marked `skip` document a KNOWN bug, with the symptom in the skip
# message. They are written to pass once the bug is fixed — deleting the skip
# line is the whole fix-verification step. Don't delete the test.

bats_require_minimum_version 1.5.0   # `run --separate-stderr`, used by the width test

setup() {
  WT="$BATS_TEST_DIRNAME/../modules/den/wt.sh"
  # macOS puts BATS_TEST_TMPDIR under /var/folders, a symlink to /private/var.
  # git resolves paths (`rev-parse --path-format=absolute`) while our fixtures
  # would carry the unresolved form, so registry rows and git's own answers
  # would never string-compare equal. Resolve once, up front.
  TMP="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"

  # Hermetic git: the machine's global config (gpgsign, hooks, default branch,
  # user identity) must not leak in or the same test passes here and fails in CI.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=t@example.com
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=t@example.com

  export HOME="$TMP/home"                 # wt_projdir + the WT_BASE default live here
  export CLAUDE_WT_BASE="$TMP/wtbase"
  REG="$CLAUDE_WT_BASE/registry.tsv"
  mkdir -p "$HOME"

  BIN="$TMP/bin"; mkdir -p "$BIN"
  export PATH="$BIN:$PATH"

  # ── shim: gh ───────────────────────────────────────────────────────────────
  # wt asks exactly one question of gh: "is there a MERGED PR for this branch,
  # and what SHA did it merge?" (branch_landed). FAKE_GH_MERGED=1 answers yes
  # with FAKE_GH_OID; unset answers "no merged PR" by printing nothing, which is
  # also how a real gh behaves offline.
  cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >>"${FAKE_GH_LOG:-/dev/null}"
[ "${FAKE_GH_MERGED:-0}" = 1 ] || exit 0
printf 'MERGED %s\n' "${FAKE_GH_OID:-}"
EOF

  # ── shim: lsof ─────────────────────────────────────────────────────────────
  # wt reads one dump of every process's cwd to decide "is a pane standing in
  # this worktree?". Always emit at least "/" so the dump is non-empty — an
  # EMPTY dump is wt's "lsof told me nothing, degrade to parked-only" signal,
  # which FAKE_LSOF_BROKEN=1 exercises deliberately.
  cat >"$BIN/lsof" <<'EOF'
#!/usr/bin/env bash
[ "${FAKE_LSOF_BROKEN:-0}" = 1 ] && exit 1
printf 'n/\n'
for c in ${FAKE_LSOF_CWDS:-}; do printf 'n%s\n' "$c"; done
EOF

  chmod +x "$BIN/gh" "$BIN/lsof"
  export FAKE_GH_LOG="$TMP/gh.log"
}

# ── fixtures ─────────────────────────────────────────────────────────────────

mkrepo() { # mkrepo <name> — a main checkout on `main`, with a GitHub origin
  local name="$1" main="$TMP/repos/$1"
  mkdir -p "$main"
  git -C "$main" init -q -b main
  git -C "$main" config commit.gpgsign false
  echo hello >"$main/README.md"
  git -C "$main" add -A
  git -C "$main" commit -qm init
  # repo_slug parses this for `gh -R`; a real-looking URL keeps that path honest.
  git -C "$main" remote add origin "https://github.com/acme/$name.git"
  printf '%s' "$main"
}

wt_run() { run bash "$WT" "$@"; }

hook_create() { # hook_create <main> <name> — drive the WorktreeCreate hook
  printf '{"name":"%s","cwd":"%s"}' "$2" "$1" | bash "$WT" create
}

hook_remove() { # hook_remove <worktree-path>
  printf '{"worktree_path":"%s"}' "$1" | bash "$WT" remove
}

commit_in() { # commit_in <checkout> <file> <msg> — give a branch real history
  echo "$RANDOM" >"$1/$2"
  git -C "$1" add -A
  git -C "$1" -c commit.gpgsign=false commit -qm "$3"
}

# A worktree with one commit of its own, so it is NOT ancestry-merged into main
# and therefore survives the self-heal sweep that every `wt` listing runs.
mkwt() { # mkwt <main> <name> — echo the checkout path
  local dir; dir="$(hook_create "$1" "$2")"
  commit_in "$dir" work.txt "work on $2"
  printf '%s' "$dir"
}

# awk, not `grep -c`: grep prints "0" AND exits 1 on an empty file, so the
# obvious `grep -c . "$REG" || echo 0` emits "0\n0" and every -eq blows up.
reg_rows() { awk 'NF' "$REG" 2>/dev/null | wc -l | tr -d ' '; }

fail() { printf '%s\n' "$*" >&2; return 1; }   # not a bats builtin

# ── create (WorktreeCreate hook) ─────────────────────────────────────────────

@test "create: makes <base>/<name> on worktree-<name> and prints ONLY the path" {
  local main; main="$(mkrepo alpha)"
  run bash -c "printf '{\"name\":\"sparkle\",\"cwd\":\"$main\"}' | bash '$WT' create 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$output" = "$CLAUDE_WT_BASE/alpha/sparkle" ]
  [ -e "$output/.git" ]
  [ "$(git -C "$output" branch --show-current)" = worktree-sparkle ]
}

@test "create: accepts the documented key names too (worktree_name/base_path)" {
  local main; main="$(mkrepo alpha)"
  run bash -c "printf '{\"worktree_name\":\"doc\",\"base_path\":\"$main\"}' | bash '$WT' create 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$(git -C "$output" branch --show-current)" = worktree-doc ]
}

@test "create: records main, branch, path and the spawning parent in the registry" {
  local main dir; main="$(mkrepo alpha)"; dir="$(hook_create "$main" sparkle)"
  run cat "$REG"
  [ "$output" = "$(printf 'sparkle\t%s\tworktree-sparkle\t%s\t%s' "$main" "$dir" "$main")" ]
}

@test "create: a name whose branch already exists fails instead of half-creating" {
  local main; main="$(mkrepo alpha)"
  hook_create "$main" dup >/dev/null 2>&1
  rm -rf "$CLAUDE_WT_BASE/alpha/dup"
  run bash -c "printf '{\"name\":\"dup\",\"cwd\":\"$main\"}' | bash '$WT' create"
  [ "$status" -ne 0 ]
  # NOTE: today this is a raw `git worktree add` error. cmd_child has friendly
  # collision guards; cmd_create does not. See the create-guard gap.
}

@test "create: a garbage hook payload fails loudly, naming the keys it wanted" {
  run bash -c "printf '{\"nope\":1}' | bash '$WT' create"
  [ "$status" -ne 0 ]
  [[ "$output" == *"none of"* ]]
}

# ── park ─────────────────────────────────────────────────────────────────────

@test "park: dirty tree becomes one wip: commit and the tree goes clean" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" p1)"
  echo edited >"$dir/README.md"
  echo new >"$dir/untracked.txt"
  cd "$dir"; wt_run park "mid refactor"
  [ "$status" -eq 0 ]
  [[ "$output" == *"parked 2 change(s)"* ]]
  [ -z "$(git -C "$dir" status --porcelain)" ]
  [[ "$(git -C "$dir" log -1 --format=%s)" == "wip: mid refactor (parked "* ]]
  # Untracked files are swept in too — that is the point of "set the tree aside".
  git -C "$dir" show --name-only --format= HEAD | grep -qx untracked.txt
}

@test "park: with no label still parks, under a generic subject" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" p2)"
  echo x >>"$dir/README.md"
  cd "$dir"; wt_run park
  [ "$status" -eq 0 ]
  [[ "$(git -C "$dir" log -1 --format=%s)" == "wip: parked "* ]]
}

@test "park: a clean tree is a no-op, not an empty commit" {
  local main dir head; main="$(mkrepo alpha)"; dir="$(mkwt "$main" p3)"
  head="$(git -C "$dir" rev-parse HEAD)"
  cd "$dir"; wt_run park
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to park"* ]]
  [ "$(git -C "$dir" rev-parse HEAD)" = "$head" ]
}

@test "park: refuses on detached HEAD — the commit would be unreachable" {
  local main dir head; main="$(mkrepo alpha)"; dir="$(mkwt "$main" p4)"
  git -C "$dir" checkout -q --detach
  head="$(git -C "$dir" rev-parse HEAD)"
  echo x >>"$dir/README.md"
  cd "$dir"; wt_run park
  [ "$status" -ne 0 ]
  [[ "$output" == *"detached"* ]]
  [ "$(git -C "$dir" rev-parse HEAD)" = "$head" ]
  [ -n "$(git -C "$dir" status --porcelain)" ]   # the edit is untouched
}

@test "park: on a non-agent branch it still parks, but warns not to push it" {
  local main; main="$(mkrepo alpha)"
  echo x >>"$main/README.md"
  cd "$main"; wt_run park
  [ "$status" -eq 0 ]
  [[ "$output" == *"isn't an agent branch"* ]]
}

@test "park: outside a git repo dies without touching anything" {
  mkdir -p "$TMP/notarepo"; cd "$TMP/notarepo"
  wt_run park
  [ "$status" -ne 0 ]
  [[ "$output" == *"not in a git repo"* ]]
}

# ── unpark ───────────────────────────────────────────────────────────────────

@test "unpark: rewinds the wip commit and gives the files back, uncommitted" {
  local main dir base; main="$(mkrepo alpha)"; dir="$(mkwt "$main" u1)"
  base="$(git -C "$dir" rev-parse HEAD)"
  echo edited >"$dir/README.md"
  cd "$dir"; bash "$WT" park >/dev/null 2>&1
  wt_run unpark
  [ "$status" -eq 0 ]
  [ "$(git -C "$dir" rev-parse HEAD)" = "$base" ]
  [ "$(cat "$dir/README.md")" = edited ]
  [ -n "$(git -C "$dir" status --porcelain)" ]
}

@test "unpark: a parked UNTRACKED file comes back untracked, not staged" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" u2)"
  echo new >"$dir/fresh.txt"
  cd "$dir"; bash "$WT" park >/dev/null 2>&1
  wt_run unpark
  [ "$status" -eq 0 ]
  [ "$(git -C "$dir" status --porcelain fresh.txt)" = "?? fresh.txt" ]
}

@test "unpark: refuses when HEAD isn't a wip: commit" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" u3)"
  cd "$dir"; wt_run unpark
  [ "$status" -ne 0 ]
  [[ "$output" == *"isn't a parked commit"* ]]
}

@test "unpark: refuses to rewrite a wip commit that is already pushed" {
  local main dir head; main="$(mkrepo alpha)"; dir="$(mkwt "$main" u4)"
  echo edited >"$dir/README.md"
  cd "$dir"; bash "$WT" park >/dev/null 2>&1
  head="$(git -C "$dir" rev-parse HEAD)"
  # Stand in for "pushed": a remote-tracking ref that contains the wip commit.
  git -C "$dir" update-ref refs/remotes/origin/worktree-u4 HEAD
  wt_run unpark
  [ "$status" -ne 0 ]
  [[ "$output" == *"already pushed"* ]]
  [ "$(git -C "$dir" rev-parse HEAD)" = "$head" ]   # never force-push behind your back
}

@test "unpark: refuses when the wip commit is the branch's root commit" {
  local root; root="$TMP/repos/rootonly"
  mkdir -p "$root"; git -C "$root" init -q -b main
  git -C "$root" config commit.gpgsign false
  echo a >"$root/a.txt"
  cd "$root"; bash "$WT" park >/dev/null 2>&1
  wt_run unpark
  [ "$status" -ne 0 ]
  [[ "$output" == *"first commit"* ]]
}

@test "unpark: two parks need two unparks — one call rewinds only the newest" {
  local main dir base; main="$(mkrepo alpha)"; dir="$(mkwt "$main" u5)"
  base="$(git -C "$dir" rev-parse HEAD)"
  cd "$dir"
  echo one >"$dir/one.txt";  bash "$WT" park first  >/dev/null 2>&1
  echo two >"$dir/two.txt";  bash "$WT" park second >/dev/null 2>&1
  bash "$WT" unpark >/dev/null 2>&1
  [ "$(git -C "$dir" rev-parse HEAD)" != "$base" ]        # the first park is still committed
  [[ "$(git -C "$dir" log -1 --format=%s)" == "wip: first"* ]]
  bash "$WT" unpark >/dev/null 2>&1
  [ "$(git -C "$dir" rev-parse HEAD)" = "$base" ]
  [ -f "$dir/one.txt" ] && [ -f "$dir/two.txt" ]
}

# ── list ─────────────────────────────────────────────────────────────────────

@test "list: says so plainly when there is nothing parked" {
  wt_run list
  [ "$status" -eq 0 ]
  [[ "$output" == *"none parked"* ]]
}

@test "list: shows a live checkout as live and a removed one as parked" {
  local main a b; main="$(mkrepo alpha)"
  a="$(mkwt "$main" alive)"; b="$(mkwt "$main" gone)"
  git -C "$main" worktree remove --force "$b"
  wt_run list
  [ "$status" -eq 0 ]
  [[ "$output" == *"alive"*"live"* ]]
  echo "$output" | grep -Eq '^\s+alpha\s+gone\s+parked'
}

@test "list: a checkout on a DIFFERENT branch than it was created for" {
  skip "BUG (branch/path desync): cmd_list trusts resume_rows' synthesized path \
instead of asking git where the branch actually is (wt_for_branch), so a renamed \
branch shows as 'parked' and its real checkout shows the wrong last commit"
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" orig)"
  git -C "$dir" checkout -qb worktree-renamed
  commit_in "$dir" more.txt "after the rename"
  wt_run list
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eq '^\s+alpha\s+renamed\s+live'
}

@test "list: stays one line per worktree in a narrow pane" {
  local main; main="$(mkrepo alpha)"
  mkwt "$main" a-rather-long-worktree-name >/dev/null
  # stdout is the table; stderr is `say`'s banner, which is a fixed sentence and
  # is allowed to be wider than the pane. Only the table has a width contract.
  COLUMNS=48 run --separate-stderr bash "$WT" list
  [ "$status" -eq 0 ]
  while IFS= read -r l; do
    [ "${#l}" -le 48 ] || fail "table line wider than COLUMNS=48: $l"
  done <<<"$(printf '%s' "$output" | sed $'s/\033\\[[0-9;]*m//g')"
}

@test "list: self-heals — a parked branch already merged into main is reaped" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" landed)"
  git -C "$main" merge -q --no-edit worktree-landed
  git -C "$main" worktree remove --force "$dir"
  wt_run list
  [ "$status" -eq 0 ]
  [[ "$output" == *"swept 1 merged worktree"* ]]
  run git -C "$main" show-ref -q --verify refs/heads/worktree-landed
  [ "$status" -ne 0 ]
}

# ── resume ───────────────────────────────────────────────────────────────────

@test "resume: rebuilds a parked checkout at its registered path" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" back)"
  git -C "$main" worktree remove --force "$dir"
  [ ! -e "$dir" ]
  wt_run resume back
  [ "$status" -eq 0 ]
  [ -e "$dir/.git" ]
  [ "$(git -C "$dir" branch --show-current)" = worktree-back ]
  [[ "$output" == *"claude --resume"* ]]     # no tty → prints the command, never execs
}

@test "resume: a live worktree is reported live, not rebuilt" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" here)"
  wt_run resume here
  [ "$status" -eq 0 ]
  [[ "$output" == *"still live at $dir"* ]]
}

@test "resume: an ambiguous name across two repos demands a repo qualifier" {
  local a b; a="$(mkrepo alpha)"; b="$(mkrepo beta)"
  mkwt "$a" twin >/dev/null; mkwt "$b" twin >/dev/null
  wt_run resume twin
  [ "$status" -ne 0 ]
  [[ "$output" == *"more than one repo"* ]]
  wt_run resume alpha/twin
  [ "$status" -eq 0 ]
}

@test "resume: an unknown name dies pointing at the listing" {
  wt_run resume nope
  [ "$status" -ne 0 ]
  [[ "$output" == *"no agent worktree named 'nope'"* ]]
}

@test "resume: a branch checked out under an unexpected path" {
  skip "BUG (branch/path desync): cmd_resume rebuilds at resume_rows' synthesized \
path without asking git where the branch already is, so this dies with 'already \
used by worktree' instead of reporting it live"
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" orig)"
  git -C "$dir" checkout -qb worktree-renamed
  commit_in "$dir" more.txt "after the rename"
  wt_run resume renamed
  [ "$status" -eq 0 ]
  [[ "$output" == *"still live at $dir"* ]]
}

# ── remove (WorktreeRemove hook) ─────────────────────────────────────────────

@test "remove: unmerged work survives — checkout gone, branch and registry kept" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" keep)"
  hook_remove "$dir"
  [ ! -e "$dir" ]
  git -C "$main" show-ref -q --verify refs/heads/worktree-keep
  [ "$(reg_rows)" -eq 1 ]
}

@test "remove: uncommitted edits are auto-parked as a wip commit, never dropped" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" dirty)"
  echo precious >"$dir/README.md"
  hook_remove "$dir"
  [[ "$(git -C "$main" log -1 --format=%s worktree-dirty)" == "wip: auto-saved on pane close"* ]]
  [ "$(git -C "$main" show worktree-dirty:README.md)" = precious ]
}

@test "remove: an ancestry-merged branch is reaped and its registry row dropped" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" done)"
  git -C "$main" merge -q --no-edit worktree-done
  hook_remove "$dir"
  run git -C "$main" show-ref -q --verify refs/heads/worktree-done
  [ "$status" -ne 0 ]
  [ "$(reg_rows)" -eq 0 ]
}

@test "remove: landed branch with ONLY untracked scratch reaps instead of parking" {
  # The regression that made merged worktrees pile up: WIP-committing build
  # scratch moves the tip past the merged PR's SHA, so the merge stops being
  # recognized and the worktree is falsely parked forever.
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" scratch)"
  export FAKE_GH_MERGED=1 FAKE_GH_OID="$(git -C "$dir" rev-parse HEAD)"
  mkdir -p "$dir/target"; echo junk >"$dir/target/o.o"
  hook_remove "$dir"
  run git -C "$main" show-ref -q --verify refs/heads/worktree-scratch
  [ "$status" -ne 0 ]
}

@test "remove: landed branch with TRACKED edits parks them and keeps the branch" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" late)"
  export FAKE_GH_MERGED=1 FAKE_GH_OID="$(git -C "$dir" rev-parse HEAD)"
  echo after-the-merge >"$dir/README.md"
  hook_remove "$dir"
  git -C "$main" show-ref -q --verify refs/heads/worktree-late
  [[ "$(git -C "$main" log -1 --format=%s worktree-late)" == "wip: auto-saved"* ]]
}

@test "remove: a squash-merged branch whose tip moved on is NOT reaped" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" moved)"
  export FAKE_GH_MERGED=1 FAKE_GH_OID="$(git -C "$dir" rev-parse HEAD)"
  commit_in "$dir" post.txt "work done after the PR merged"   # tip != headRefOid
  hook_remove "$dir"
  git -C "$main" show-ref -q --verify refs/heads/worktree-moved
}

# ── reap ─────────────────────────────────────────────────────────────────────

@test "reap: removes a clean, landed, unoccupied checkout and its branch" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" sweepme)"
  git -C "$main" merge -q --no-edit worktree-sweepme
  cd "$TMP"; wt_run reap
  [ "$status" -eq 0 ]
  [[ "$output" == *"reaped sweepme (alpha)"* ]]
  [ ! -e "$dir" ]
  [ "$(reg_rows)" -eq 0 ]
}

@test "reap: keeps a landed checkout that a pane is still standing in" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" busy)"
  git -C "$main" merge -q --no-edit worktree-busy
  export FAKE_LSOF_CWDS="$dir"
  cd "$TMP"; wt_run reap
  [ "$status" -eq 0 ]
  [[ "$output" == *"kept busy (alpha) — a pane is open in it"* ]]
  [ -e "$dir/.git" ]
}

@test "reap: keeps a landed checkout with uncommitted changes" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" messy)"
  git -C "$main" merge -q --no-edit worktree-messy
  echo edit >"$dir/README.md"
  cd "$TMP"; wt_run reap
  [ -e "$dir/.git" ]
  git -C "$main" show-ref -q --verify refs/heads/worktree-messy
}

@test "reap: keeps an unmerged checkout" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" unmerged)"
  cd "$TMP"; wt_run reap
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to reap"* ]]
  [ -e "$dir/.git" ]
}

@test "reap: never removes the checkout it is being run from" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" self)"
  git -C "$main" merge -q --no-edit worktree-self
  cd "$dir"; wt_run reap
  [ -e "$dir/.git" ]
  git -C "$main" show-ref -q --verify refs/heads/worktree-self
}

@test "reap: without a usable lsof it degrades to parked-only and says so" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" cautious)"
  git -C "$main" merge -q --no-edit worktree-cautious
  export FAKE_LSOF_BROKEN=1
  cd "$TMP"; wt_run reap
  [ "$status" -eq 0 ]
  [[ "$output" == *"no lsof"* ]]
  [ -e "$dir/.git" ]     # a live checkout is never guessed at
}

@test "reap: a squash-merged branch is recognized via its merged PR" {
  local main dir tip; main="$(mkrepo alpha)"; dir="$(mkwt "$main" squashed)"
  tip="$(git -C "$dir" rev-parse HEAD)"
  git -C "$main" merge -q --squash worktree-squashed && git -C "$main" commit -qm "squash merge"
  export FAKE_GH_MERGED=1 FAKE_GH_OID="$tip"
  cd "$TMP"; wt_run reap
  [[ "$output" == *"reaped squashed (alpha)"* ]]
}

@test "reap: a merged PR whose SHA no longer matches the tip is left alone" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" ahead)"
  export FAKE_GH_MERGED=1 FAKE_GH_OID="$(git -C "$dir" rev-parse HEAD)"
  commit_in "$dir" post.txt "un-landed work"
  cd "$TMP"; wt_run reap
  [ -e "$dir/.git" ]
  git -C "$main" show-ref -q --verify refs/heads/worktree-ahead
}

@test "reap: 'landed' means landed on the DEFAULT branch, not whatever main has checked out" {
  skip "BUG (landed-base): branch_landed derives its base from \`symbolic-ref HEAD\` \
of the main checkout, so a main checkout parked on a side branch that happens to \
contain the worktree branch reaps it though it never reached main"
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" sidequest)"
  git -C "$main" checkout -qb detour
  git -C "$main" merge -q --no-edit worktree-sidequest   # landed on `detour`, NOT on main
  cd "$TMP"; wt_run reap
  git -C "$main" show-ref -q --verify refs/heads/worktree-sidequest
}

@test "reap: is idempotent — a second run finds nothing and changes nothing" {
  local main; main="$(mkrepo alpha)"
  mkwt "$main" twice >/dev/null
  git -C "$main" merge -q --no-edit worktree-twice
  cd "$TMP"; bash "$WT" reap >/dev/null 2>&1
  wt_run reap
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to reap"* ]]
}

# ── child ────────────────────────────────────────────────────────────────────

@test "child: worktrees another repo and registers THIS pane as the parent" {
  local a b dir; a="$(mkrepo alpha)"; b="$(mkrepo beta)"
  cd "$a"
  run bash -c "cd '$a' && bash '$WT' child '$b' cross 2>/dev/null"
  [ "$status" -eq 0 ]
  dir="$output"
  [ "$dir" = "$CLAUDE_WT_BASE/beta/cross" ]
  [ "$(git -C "$dir" branch --show-current)" = worktree-cross ]
  # 5th registry field is the spawning cwd — this is what the statusline reads.
  [ "$(awk -F'\t' -v p="$dir" '$4==p{print $5}' "$REG")" = "$a" ]
}

@test "child: defaults the name to this pane's own worktree name" {
  local a b dir; a="$(mkrepo alpha)"; b="$(mkrepo beta)"
  dir="$(mkwt "$a" shared)"
  run bash -c "cd '$dir' && bash '$WT' child '$b' 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$output" = "$CLAUDE_WT_BASE/beta/shared" ]
}

@test "child: refuses a name whose branch or path already exists" {
  local a b; a="$(mkrepo alpha)"; b="$(mkrepo beta)"
  bash "$WT" child "$b" taken >/dev/null 2>&1
  run bash -c "cd '$a' && bash '$WT' child '$b' taken"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "child: refuses a path that isn't a repo, and a linked worktree" {
  run bash "$WT" child "$TMP/nope"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no such directory"* ]]
  mkdir -p "$TMP/plain"
  run bash "$WT" child "$TMP/plain"
  [ "$status" -ne 0 ]
  [[ "$output" == *"isn't inside a git repo"* ]]
}

@test "child: a resumed child inherits its parent's chat, not an empty picker" {
  local a b dir cdir; a="$(mkrepo alpha)"; b="$(mkrepo beta)"
  dir="$(mkwt "$a" par)"
  mkdir -p "$HOME/.claude/projects/$(printf '%s' "$dir" | sed 's/[/.]/-/g')"
  cdir="$(cd "$dir" && bash "$WT" child "$b" 2>/dev/null)"
  commit_in "$cdir" c.txt "child work"
  git -C "$b" worktree remove --force "$cdir"
  wt_run resume beta/par
  [ "$status" -eq 0 ]
  [[ "$output" == *"spawned from a session in $dir"* ]]
}

# ── registry upkeep ──────────────────────────────────────────────────────────

@test "registry: rows whose branch has vanished are pruned on the next listing" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" ghost)"
  git -C "$main" worktree remove --force "$dir"
  git -C "$main" branch -qD worktree-ghost
  [ "$(reg_rows)" -eq 1 ]
  bash "$WT" list >/dev/null 2>&1
  [ "$(reg_rows)" -eq 0 ]
}

@test "registry: a row pointing at a deleted main checkout doesn't invent a repo" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" orphan)"
  git -C "$main" worktree remove --force "$dir"
  rm -rf "$main"
  cd "$TMP"; wt_run list
  [ "$status" -eq 0 ]
  # The old bug listed the CURRENT repo's branches again under a repo named ".".
  ! [[ "$output" == *" . "* ]]
}

@test "registry: parallel creates must not lose rows to a read-modify-write race" {
  skip "BUG (registry race): reg_put reads the whole TSV, rewrites it and mv's it \
into place, so two panes creating a worktree at the same moment silently drop one \
row — the worktree still exists but goes invisible to the statusline"
  local main i; main="$(mkrepo alpha)"
  for i in 1 2 3 4 5 6 7 8; do hook_create "$main" "par$i" >/dev/null 2>&1 & done
  wait
  [ "$(reg_rows)" -eq 8 ]
}

# ── dispatch ─────────────────────────────────────────────────────────────────

@test "dispatch: --help prints the header block, including park/unpark" {
  wt_run --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"wt park [label]"* ]]
  [[ "$output" == *"wt unpark"* ]]
  [[ "$output" != *"#!/usr/bin/env"* ]]
}

@test "dispatch: a bare unknown token is treated as a worktree name" {
  wt_run gibberish
  [ "$status" -ne 0 ]
  [[ "$output" == *"no agent worktree named 'gibberish'"* ]]
}

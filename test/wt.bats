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
# Nothing here is skipped — every contract the suite states holds. To see what a
# given revision of the script breaks, point the suite at it:
#
#   git show <rev>:modules/den/wt.sh > /tmp/wt.sh
#   WT_UNDER_TEST=/tmp/wt.sh bats test/wt.bats
#
# That is the intended way to demonstrate a bug: write the test, watch it fail
# against the old copy, fix, watch it pass against both the new copy and the
# whole suite. A test that passes against BOTH copies is not reproducing the bug
# you think it is — two of these did exactly that on the first attempt.

bats_require_minimum_version 1.5.0   # `run --separate-stderr`, used by the width test

setup() {
  # WT_UNDER_TEST lets you point the whole suite at another copy of the script —
  # an older revision, a candidate rewrite — to see exactly which contracts it
  # breaks. That is how the fixes below were shown to fix something.
  WT="${WT_UNDER_TEST:-$BATS_TEST_DIRNAME/../modules/den/wt.sh}"
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

@test "create: records main, branch, path, parent, and its Claude client in the registry" {
  local main dir; main="$(mkrepo alpha)"; dir="$(hook_create "$main" sparkle)"
  run cat "$REG"
  [ "$output" = "$(printf 'sparkle\t%s\tworktree-sparkle\t%s\t%s\tclaude' "$main" "$dir" "$main")" ]
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

# An agent branch can be checked out somewhere `wt` never put it: a raw
# `git worktree add`, or another agent's own worktree feature (codex keeps its
# under ~/.codex/worktrees/). Such a branch is only ever discovered by the
# orphan scan, which SYNTHESIZES a path from the bucket convention — a path that
# does not exist. Trusting that guess files a very-much-live checkout as parked.
# (A rename INSIDE the base is not this case: the disk glob re-reads each live
# checkout's current branch, so it self-corrects.)
mk_stray() { # mk_stray <main> <name> — a worktree-<name> checkout outside WT_BASE
  local out="$TMP/elsewhere/$2"
  mkdir -p "$TMP/elsewhere"
  # wt discovers repos through the registry and the WT_BASE glob, so a repo whose
  # ONLY worktree is a stray is invisible entirely — a different (and correct)
  # behaviour. Anchor the repo with one ordinary worktree so the orphan scan runs
  # and the stray is actually reached. That is also the real-world shape.
  [ -n "$(awk -F'\t' -v m="$1" '$2==m' "$REG" 2>/dev/null)" ] || mkwt "$1" "${2}-anchor" >/dev/null
  git -C "$1" worktree add -q -b "worktree-$2" "$out" >/dev/null 2>&1
  commit_in "$out" stray.txt "work in an unregistered checkout"
  printf '%s' "$out"
}

@test "list: a branch checked out OUTSIDE the worktree base still reads as live" {
  local main out; main="$(mkrepo alpha)"; out="$(mk_stray "$main" manual)"
  wt_run list
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eq '^\s+alpha\s+manual\s+live'
  [ -e "$out/.git" ]
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

@test "resume: a branch checked out OUTSIDE the base is reported live, not re-added" {
  local main out; main="$(mkrepo alpha)"; out="$(mk_stray "$main" manual)"
  wt_run resume manual
  [ "$status" -eq 0 ]
  # Trusting the synthesized path here means `git worktree add` on a branch that
  # is already checked out — which fails outright, so the worktree is unreachable.
  [[ "$output" == *"still live at $out"* ]]
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

# ── spawn ────────────────────────────────────────────────────────────────────

@test "spawn: names the worktree and parents it to the repo, not to a pane" {
  local b dir; b="$(mkrepo beta)"
  # No cd: the palette runs under launchd, from wherever it happens to be.
  run bash -c "bash '$WT' spawn '$b' fix-the-notch 2>/dev/null"
  [ "$status" -eq 0 ]
  dir="$output"
  [ "$dir" = "$CLAUDE_WT_BASE/beta/fix-the-notch" ]
  [ "$(git -C "$dir" branch --show-current)" = worktree-fix-the-notch ]
  # Parent is the repo's own main checkout — a pane sitting there lists it.
  [ "$(awk -F'\t' -v p="$dir" '$4==p{print $5}' "$REG")" = "$b" ]
}

@test "spawn: a taken name takes the next free suffix instead of dying" {
  local b first second; b="$(mkrepo beta)"
  first="$(bash "$WT" spawn "$b" dupe 2>/dev/null)"
  run bash -c "bash '$WT' spawn '$b' dupe 2>/dev/null"
  [ "$status" -eq 0 ]
  second="$output"
  [ "$first" = "$CLAUDE_WT_BASE/beta/dupe" ]
  [ "$second" = "$CLAUDE_WT_BASE/beta/dupe-2" ]
  [ "$(git -C "$second" branch --show-current)" = worktree-dupe-2 ]
}

@test "spawn: a free path with a taken BRANCH still skips to a free name" {
  local b; b="$(mkrepo beta)"
  git -C "$b" branch worktree-held
  run bash -c "bash '$WT' spawn '$b' held 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$output" = "$CLAUDE_WT_BASE/beta/held-2" ]
}

@test "spawn: records its client, independently of the future default" {
  local b dir; b="$(mkrepo beta)"
  dir="$(bash "$WT" spawn "$b" codex-task codex 2>/dev/null)"
  [ "$(awk -F'\t' -v p="$dir" '$4==p{print $6}' "$REG")" = codex ]
  NEBELHAUS_AGENT_DEFAULT=opencode run bash "$WT" resume codex-task
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex resume"* ]]
  [[ "$output" != *"opencode --continue"* ]]
}

@test "resume: pre-client registry rows remain Claude worktrees" {
  local main dir; main="$(mkrepo alpha)"; dir="$CLAUDE_WT_BASE/alpha/legacy"
  git -C "$main" branch worktree-legacy
  mkdir -p "$(dirname "$REG")"
  printf 'legacy\t%s\tworktree-legacy\t%s\t%s\n' "$main" "$dir" "$main" >"$REG"
  NEBELHAUS_AGENT_DEFAULT=codex run bash "$WT" resume legacy
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude --resume"* ]]
}

@test "agent start: Codex receives a captured screenshot as an initial image" {
  cat >"$BIN/codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@"
EOF
  chmod +x "$BIN/codex"
  local image="$TMP/shot.png"; : >"$image"
  run bash "$WT" agent start codex --image "$image" -- "inspect this"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n%s\n%s' -i "$image" "inspect this")" ]
}

# ── new (the client-agnostic ⌘C) ─────────────────────────────────────────────
#
# `wt new` is what Super c runs when the default client isn't Claude Code — the
# only client that can make its own worktree. It must land the SAME checkout,
# branch and registry row the create hook does, parented to the pane's cwd, and
# then hand the pane over to the client. A shim client stands in for that exec.

shim_agent() { # shim_agent <name> — a client that prints how it was invoked
  cat >"$BIN/$1" <<EOF
#!/usr/bin/env bash
printf 'ran %s %s\n' "$1" "\$*"
EOF
  chmod +x "$BIN/$1"
}

@test "new: worktree of THIS repo, parented to the pane, then opens the client" {
  local b dir; b="$(mkrepo beta)"
  shim_agent opencode
  cd "$b"
  run bash "$WT" new notch-fix opencode
  [ "$status" -eq 0 ]
  dir="$CLAUDE_WT_BASE/beta/notch-fix"
  [ -e "$dir/.git" ]
  [ "$(git -C "$dir" branch --show-current)" = worktree-notch-fix ]
  # Parent is the PANE's cwd (as the create hook records it), not the repo, and
  # the row keeps the client so a later `wt notch-fix` reopens opencode.
  [ "$(awk -F'\t' -v p="$dir" '$4==p{print $5}' "$REG")" = "$b" ]
  [ "$(awk -F'\t' -v p="$dir" '$4==p{print $6}' "$REG")" = opencode ]
  [[ "$output" == *"ran opencode"* ]]
}

@test "new: an unnamed spawn names itself, and a taken name takes a suffix" {
  local b first second; b="$(mkrepo beta)"
  shim_agent claude
  cd "$b"
  run bash "$WT" new
  [ "$status" -eq 0 ]
  first="$(awk -F'\t' 'NR==1{print $1}' "$REG")"
  [ -n "$first" ]
  run bash "$WT" new "$first"          # ask for the taken one on purpose
  [ "$status" -eq 0 ]
  second="$(awk -F'\t' -v n="$first" '$1!=n{print $1}' "$REG")"
  [ "$second" = "$first-2" ]
}

@test "new: outside a repo it refuses rather than leaving a stray worktree" {
  shim_agent claude
  mkdir -p "$TMP/plain"
  cd "$TMP/plain"
  run bash "$WT" new
  [ "$status" -ne 0 ]
  [[ "$output" == *"not inside a git repo"* ]]
  [ "$(reg_rows)" -eq 0 ]
}

@test "new: an uninstalled client is named, and the checkout survives to resume" {
  local b; b="$(mkrepo beta)"
  cd "$b"
  # No shim for codex on PATH: it's the client that is missing, not the worktree.
  run bash "$WT" new stranded codex
  [ "$status" -ne 0 ]
  [[ "$output" == *"codex is unavailable"* ]]
  [ -e "$CLAUDE_WT_BASE/beta/stranded/.git" ]
}

@test "spawn: refuses a missing path, a non-repo, and a missing name" {
  local b; b="$(mkrepo beta)"
  run bash "$WT" spawn "$TMP/nope" x
  [ "$status" -ne 0 ]
  [[ "$output" == *"no such directory"* ]]
  mkdir -p "$TMP/plain"
  run bash "$WT" spawn "$TMP/plain" x
  [ "$status" -ne 0 ]
  [[ "$output" == *"isn't inside a git repo"* ]]
  run bash "$WT" spawn "$b"
  [ "$status" -ne 0 ]
  [[ "$output" == *"usage: wt spawn"* ]]
}

# ── dangling checkouts (husks) ───────────────────────────────────────────────
#
# `git worktree remove` deletes the repo's admin dir (.git/worktrees/<id>) BEFORE
# it deletes the working tree. When that second half fails — an ignored build dir
# it cannot unlink, a file another process holds — what's left is a directory
# whose .git file points at a gitdir that no longer exists. `[ -e "$wt/.git" ]`
# says "live"; every git command run inside says "fatal: not a git repository".
#
# husk() reproduces exactly that end state, which is all any caller can observe.

husk() { # husk <main> <checkout> — leave <checkout> on disk, unregistered
  local id; id="$(basename "$2")"
  rm -rf "$1/.git/worktrees/$id"
}

@test "husk: a checkout git has disowned lists as 'stray', not 'live'" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" ghosted)"
  husk "$main" "$dir"
  wt_run
  [ "$status" -eq 0 ]
  [[ "$output" == *ghosted* ]]
  # The whole point: the old `-e .git` test called this live, so the row lied and
  # `wt ghosted` refused to rebuild it — the branch was unreachable through wt.
  [[ "$output" != *"ghosted"*"live"* ]]
  [[ "$output" == *stray* ]]
}

@test "husk: the listing says what to do about it, and the sweep spares the branch" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" ghosted)"
  # Landed AND merged-by-PR: every reason the sweep has to reap, so the only thing
  # keeping the branch alive is the husk rule itself.
  git -C "$main" merge -q --no-ff -m merge worktree-ghosted
  husk "$main" "$dir"
  FAKE_GH_MERGED=1 FAKE_GH_OID="$(git -C "$main" rev-parse worktree-ghosted)" wt_run reap
  [ "$status" -eq 0 ]
  [[ "$output" == *dangling* ]]
  git -C "$main" show-ref -q --verify refs/heads/worktree-ghosted \
    || fail "the branch was reaped while its checkout was a husk — the husk's uncommitted files are now referenced by nothing"
  [ -d "$dir" ] || fail "the husk directory was deleted"
}

@test "husk: resume moves it aside — never deletes it — and rebuilds the checkout" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" ghosted)"
  # An edit that exists ONLY here: not committed, not on the branch. This is the
  # thing a husk can be holding, and the reason it is moved rather than removed.
  echo "only-copy" >"$dir/unsaved.txt"
  husk "$main" "$dir"
  wt_run resume ghosted
  [ "$status" -eq 0 ]
  # Rebuilt, and git can read it again.
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 \
    || fail "resume left the husk in place instead of rebuilding the checkout"
  [ "$(git -C "$dir" branch --show-current)" = worktree-ghosted ]
  # And the old contents survive beside it, named in the output.
  local moved; moved="$(echo "$dir".stray-*)"
  [ -f "$moved/unsaved.txt" ] || fail "the husk's only copy of unsaved.txt is gone"
  [[ "$output" == *"$moved"* ]]
}

# A git whose `worktree remove` fails the way the real one does when the delete
# breaks down half-way: admin dir gone, working tree still standing, non-zero
# exit. Everything else passes straight through to the real git. Scoped to the
# one test that needs it — PATH is shim-first, and wt appends its rescue path
# precisely so a shim wins.
git_husk_shim() { # git_husk_shim — echoes a dir to put at the front of PATH
  local shim="$TMP/gitshim"
  mkdir -p "$shim"
  cat >"$shim/git" <<EOF
#!/usr/bin/env bash
if [ "\$3" = worktree ] && [ "\$4" = remove ]; then
  for a in "\$@"; do last="\$a"; done
  rm -rf "\$2/.git/worktrees/\$(basename "\$last")"
  exit 1
fi
exec $(command -v git) "\$@"
EOF
  chmod +x "$shim/git"
  printf '%s' "$shim"
}

@test "husk: the remove hook finishes the deletion git abandoned" {
  local main dir shim; main="$(mkrepo alpha)"; dir="$(mkwt "$main" messy)"
  echo "edit" >>"$dir/work.txt"          # dirty, so the wip-commit path runs too
  shim="$(git_husk_shim)"
  PATH="$shim:$PATH" hook_remove "$dir"
  # The uncommitted edit went to a wip commit as always, so nothing on disk was
  # irreplaceable — and only then is the hook allowed to finish what git started.
  [ ! -e "$dir" ] || fail "the hook left a husk at $dir; it would read 'live' forever and freeze the statusline"
  git -C "$main" show-ref -q --verify refs/heads/worktree-messy \
    || fail "the branch was dropped along with the residue"
  [[ "$(git -C "$main" log -1 --format=%s worktree-messy)" == wip:* ]] \
    || fail "the dirty tree wasn't parked before the checkout was deleted"
}

@test "husk: residue nothing can delete is reported, not died on" {
  [ "$(id -u)" != 0 ] || skip "root ignores the directory permissions this test uses"
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" stubborn)"
  # An IGNORED directory that cannot be unlinked (no write permission on its
  # parent) defeats git's delete — and ours. The contract is that the hook still
  # exits cleanly, keeps the branch, and names what it left behind.
  mkdir -p "$dir/scratch"
  echo build >"$dir/scratch/out.o"
  echo scratch/ >"$dir/.gitignore"
  git -C "$dir" add -A
  git -C "$dir" -c commit.gpgsign=false commit -qm ignore
  chmod 555 "$dir/scratch"
  run hook_remove "$dir"
  chmod 755 "$dir/scratch" 2>/dev/null || true
  [ "$status" -eq 0 ] || fail "the remove hook died on a checkout it couldn't delete"
  git -C "$main" show-ref -q --verify refs/heads/worktree-stubborn \
    || fail "the branch was dropped even though the checkout survived"
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

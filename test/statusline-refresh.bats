#!/usr/bin/env bats
# Hermetic tests for the statusline refresher (modules/ai/statusline-refresh.sh)
# — the detached half of the agent-worktree bar.
#
# Why this suite exists, in one paragraph. The refresher runs under
# `set -euo pipefail`, DETACHED, with its output thrown away; the render path
# only ever reads the file it leaves behind. So any non-zero anywhere in it does
# not produce an error, a log line, or a broken pill — it produces a panel.tsv
# that simply stops changing, and a bar that keeps confidently displaying
# worktrees that were reaped hours ago. Two ordinary situations did exactly that:
# a checkout git could no longer read, and a worktree whose only change was an
# untracked file. Neither is exotic; both froze the whole bar for every pane on
# the machine. That is the failure mode every test here is aimed at.
#
# Everything is substituted — HOME, CLAUDE_WT_BASE, CLAUDE_STATUSLINE_CACHE,
# HAUS_CONSUMER, and `gh` — so the suite never touches the real registry, the
# real cache, or the network. The script APPENDS its PATH rescue (it used to
# prepend, which made the shim unreachable), so $BIN wins here.

bats_require_minimum_version 1.5.0

setup() {
  REFRESH="${REFRESH_UNDER_TEST:-$BATS_TEST_DIRNAME/../modules/ai/statusline-refresh.sh}"
  TMP="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"   # /var → /private/var, as git resolves it

  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=t@example.com
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=t@example.com

  export HOME="$TMP/home"
  export CLAUDE_WT_BASE="$TMP/wtbase"
  export CLAUDE_STATUSLINE_CACHE="$TMP/cache"
  # No flake.lock here, so the stale-haus nag short-circuits before its curl.
  # Every test would otherwise reach the network on a cold cache.
  export HAUS_CONSUMER="$TMP/no-consumer"
  REG="$CLAUDE_WT_BASE/registry.tsv"
  PANEL="$CLAUDE_STATUSLINE_CACHE/panel.tsv"
  mkdir -p "$HOME" "$CLAUDE_WT_BASE"

  BIN="$TMP/bin"; mkdir -p "$BIN"
  export PATH="$BIN:$PATH"

  # ── shim: gh ───────────────────────────────────────────────────────────────
  # The refresher asks gh two kinds of question — the repo-wide list, and the
  # per-branch fallback (--head) it runs when the list misses a branch — and
  # can ask about several repos in one pass. A test may therefore pin answers
  # per repo (FAKE_PRS_ACME_ALPHA, from the -R slug with / and . folded to _)
  # and per repo+fallback (FAKE_PRS_HEAD_ACME_ALPHA). Anything unset falls
  # through to FAKE_PRS, which keeps every single-answer test unchanged.
  cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >>"${FAKE_GH_LOG:-/dev/null}"
suffix=""; prev=""; is_head=0
for a in "$@"; do
  [ "$prev" = "-R" ] && suffix=$(printf '%s' "$a" | tr '/.' '__' | tr 'a-z' 'A-Z')
  [ "$a" = "--head" ] && is_head=1
  prev="$a"
done
answer=""
if [ -n "$suffix" ]; then
  if [ "$is_head" = 1 ]; then
    eval "answer=\${FAKE_PRS_HEAD_${suffix}:-}"
  else
    eval "answer=\${FAKE_PRS_${suffix}:-}"
  fi
fi
[ -n "$answer" ] && { printf '%s' "$answer"; exit 0; }
printf '%s' "${FAKE_PRS:-[]}"
EOF
  chmod +x "$BIN/gh"
  export FAKE_GH_LOG="$TMP/gh.log"

  # ── shim: security ─────────────────────────────────────────────────────────
  # Shimmed for the WHOLE suite, not just the tests that use it, and that is the
  # point: the Claude usage feed opts in on `[ -d ~/.claude ]`, which the token
  # tests all create. Without a shim in setup they would each reach the REAL
  # login keychain and raise a macOS prompt in the middle of a test run. The
  # default answer is 44 — SecKeychain's "no such item", i.e. a machine that
  # never logged into Claude Code.
  cat >"$BIN/security" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$SECURITY_LOG"
[ -n "${FAKE_KEYCHAIN:-}" ] || exit 44
printf '%s' "$FAKE_KEYCHAIN"
EOF
  chmod +x "$BIN/security"
  export SECURITY_LOG="$TMP/security.log"
  : >"$SECURITY_LOG"
}

# ── fixtures ─────────────────────────────────────────────────────────────────

mkrepo() { # mkrepo <name> — a main checkout on `main`, with a GitHub origin
  local main="$TMP/repos/$1"
  mkdir -p "$main"
  git -C "$main" init -q -b main
  git -C "$main" config commit.gpgsign false
  echo hello >"$main/README.md"
  git -C "$main" add -A
  git -C "$main" commit -qm init
  git -C "$main" remote add origin "https://github.com/acme/$1.git"
  printf '%s' "$main"
}

mkwt() { # mkwt <main> <name> [parent] — a registered worktree with one commit
  local main="$1" name="$2" parent="${3:-$1}"
  local dir="$CLAUDE_WT_BASE/$(basename "$main")/$name"
  mkdir -p "$(dirname "$dir")"
  git -C "$main" worktree add -q -b "worktree-$name" "$dir" >/dev/null 2>&1
  echo work >"$dir/work.txt"
  git -C "$dir" add -A
  git -C "$dir" -c commit.gpgsign=false commit -qm "work on $name"
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$main" "worktree-$name" "$dir" "$parent" >>"$REG"
  printf '%s' "$dir"
}

# The end state of a `git worktree remove` that deleted the repo's admin dir and
# then failed to delete the working tree: a directory whose .git file references
# a gitdir that is gone. Every git command inside exits 128.
husk() { # husk <main> <checkout>
  rm -rf "$1/.git/worktrees/$(basename "$2")"
}

refresh() { run bash "$REFRESH"; }

row_for() { # row_for <name> — the panel line for a worktree, or nothing
  awk -F'\t' -v n="$2" '$2==n' "$PANEL" 2>/dev/null
}
col() { # col <name> <n> — one field of that worktree's row
  awk -F'\t' -v n="$1" -v c="$2" '$2==n{print $c; exit}' "$PANEL" 2>/dev/null
}
names() { cut -f2 "$PANEL" 2>/dev/null | sort | tr '\n' ' '; }

fail() { printf '%s\n' "$*" >&2; return 1; }

# `stat -f` is BSD/macOS, where this ships — but CI runs the suite on Linux,
# where GNU coreutils reads -f as --file-system and happily prints the MOUNT
# POINT with exit 0. So neither exit status nor emptiness can pick the fallback:
# take the BSD answer only when it is all digits, then try GNU. (The refresher
# itself carries the same two-step in its own `mtime`.)
statnum() { # statnum <bsd-fmt> <gnu-fmt> <file> — a numeric stat field, or 0
  local v
  v=$(stat -f "$1" "$3" 2>/dev/null || true)
  case "$v" in '' | *[!0-9]*) v=$(stat -c "$2" "$3" 2>/dev/null || echo 0) ;; esac
  case "$v" in '' | *[!0-9]*) v=0 ;; esac
  printf '%s' "$v"
}
fmode() { statnum %Lp %a "$1"; }   # permission bits, e.g. 600
fmtime() { statnum %m %Y "$1"; }   # mtime in epoch seconds

# ── the panel it is supposed to write ────────────────────────────────────────

@test "writes a row per in-flight worktree: slug, name, ahead, parent" {
  local main; main="$(mkrepo alpha)"
  mkwt "$main" sparkle >/dev/null
  refresh
  [ "$status" -eq 0 ]
  [ "$(col sparkle 1)" = acme/alpha ]
  [ "$(col sparkle 3)" = 1 ]                      # one commit not on main
  [ "$(col sparkle 7)" = - ]                      # no PR — the sentinel, never empty
  [ "$(col sparkle 8)" = "$main" ]                # parent, as recorded at create time
}

@test "a worktree with nothing in flight is left out" {
  local main dir; main="$(mkrepo alpha)"
  dir="$CLAUDE_WT_BASE/alpha/idle"
  mkdir -p "$(dirname "$dir")"
  git -C "$main" worktree add -q -b worktree-idle "$dir" >/dev/null 2>&1
  printf 'idle\t%s\tworktree-idle\t%s\t%s\n' "$main" "$dir" "$main" >>"$REG"
  refresh
  [ "$status" -eq 0 ]
  [ -z "$(row_for x idle)" ] || fail "an idle worktree — no commits, clean, no PR — took a row"
}

@test "a PR from gh lands in the prstate column, state and all" {
  local main; main="$(mkrepo alpha)"
  mkwt "$main" sparkle >/dev/null
  FAKE_PRS='[{"number":7,"state":"MERGED","headRefName":"worktree-sparkle"}]' refresh
  [ "$status" -eq 0 ]
  [ "$(col sparkle 7)" = "#7 merged" ]
}

@test "a PR outside the repo-wide newest-100 window is recovered by the per-branch fallback" {
  # The repo-wide pass only sees a repo's newest 100 PRs (gh lists newest-first),
  # so in a busy repo a lane whose PR is older than that window rendered "-"
  # forever: the row was there, the PR existed, and every renderer dropped the
  # pill and the OSC 8 hyperlink.
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" sparkle)"
  FAKE_PRS='[]' FAKE_PRS_HEAD_ACME_ALPHA='[{"number":7,"state":"OPEN","headRefName":"worktree-sparkle"}]' refresh
  [ "$status" -eq 0 ]
  [ "$(col sparkle 7)" = "#7 open" ]
  grep -q -- "--head worktree-sparkle" "$FAKE_GH_LOG"
}

@test "the per-branch fallback cache does not leak between repos sharing a branch name" {
  # scruff child coins lane names per repo, so two live lanes in DIFFERENT repos
  # share one branch name routinely. A branch-keyed fallback cache would answer
  # alpha's PR for beta too — a bogus PR number and a hyperlink to the wrong
  # repo — recurring every cache window. Keyed on slug+branch, each repo gets
  # its own truth.
  local a b; a="$(mkrepo alpha)"; b="$(mkrepo beta)"
  mkwt "$a" sparkle >/dev/null
  mkwt "$b" sparkle >/dev/null
  FAKE_PRS='[]' FAKE_PRS_HEAD_ACME_ALPHA='[{"number":7,"state":"OPEN","headRefName":"worktree-sparkle"}]' refresh
  [ "$status" -eq 0 ]
  [ "$(awk -F'\t' -v s='acme/alpha' '$1==s{print $7}' "$PANEL")" = "#7 open" ]
  [ "$(awk -F'\t' -v s='acme/beta' '$1==s{print $7}' "$PANEL")" = "-" ]
}

@test "a merged PR whose branch kept committing reads as merged+K, not merged" {
  # The bar's ⏏ ("done, scruff reaps it") is driven by this cell. When a session keeps
  # committing after its PR merged, those commits have no PR and no remote branch
  # — a plain `merged` here is what made the pane look finished while un-shipped
  # work sat in it.
  local main dir oid; main="$(mkrepo alpha)"; dir="$(mkwt "$main" sparkle)"
  oid="$(git -C "$dir" rev-parse HEAD)"
  echo more >"$dir/post.txt"
  git -C "$dir" add -A
  git -C "$dir" -c commit.gpgsign=false commit -qm "after the merge"
  FAKE_PRS="[{\"number\":7,\"state\":\"MERGED\",\"headRefName\":\"worktree-sparkle\",\"headRefOid\":\"$oid\"}]" refresh
  [ "$status" -eq 0 ]
  [ "$(col sparkle 7)" = "#7 merged+1" ]
}

@test "post-merge commits that ALSO landed leave the state a plain merged" {
  local main dir oid; main="$(mkrepo alpha)"; dir="$(mkwt "$main" sparkle)"
  oid="$(git -C "$dir" rev-parse HEAD)"
  echo more >"$dir/post.txt"
  git -C "$dir" add -A
  git -C "$dir" -c commit.gpgsign=false commit -qm "after the merge"
  git -C "$main" merge -q --no-edit worktree-sparkle    # …and that landed too
  FAKE_PRS="[{\"number\":7,\"state\":\"MERGED\",\"headRefName\":\"worktree-sparkle\",\"headRefOid\":\"$oid\"}]" refresh
  [ "$status" -eq 0 ]
  [ "$(col sparkle 7)" = "#7 merged" ]
}

@test "a merged PR still at the branch tip stays a plain merged" {
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" sparkle)"
  FAKE_PRS="[{\"number\":7,\"state\":\"MERGED\",\"headRefName\":\"worktree-sparkle\",\"headRefOid\":\"$(git -C "$dir" rev-parse HEAD)\"}]" refresh
  [ "$status" -eq 0 ]
  [ "$(col sparkle 7)" = "#7 merged" ]
}

@test "a PR that closed before this branch existed belongs to the last lane of that name" {
  # scruff coins lane names from a small word list and a task name gets reused
  # outright, so one repo has carried `worktree-tidy-raccoon` twice and
  # `worktree-haus` five times. gh answers about the NAME, so the freshly cut
  # lane inherited the reaped one's merged PR: a #N pill it never opened, an ⏏
  # saying "done, reap me", and merged+K counting main's commits since that old
  # merge as un-shipped work.
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" sparkle)"
  # An oid this branch has never heard of — the previous lane's tip, whose
  # objects went with it. Ancestry says no; the date says how long ago.
  FAKE_PRS='[{"number":7,"state":"MERGED","headRefName":"worktree-sparkle",
              "headRefOid":"0000000000000000000000000000000000000001",
              "closedAt":"2020-01-01T00:00:00Z"}]' refresh
  [ "$status" -eq 0 ]
  [ "$(col sparkle 7)" = - ] || fail "a reaped lane's PR stuck to the new lane wearing its name"
  [ "$(col sparkle 3)" = 1 ]                      # …and the row itself is untouched
}

@test "a PR that closed after this branch was cut is kept, unreachable SHA and all" {
  # The other direction, and the one that must not over-fire: a lane that merged
  # and then rebased has a head SHA that is no longer reachable either, and its
  # PR is still very much its own. Only a PR that predates the branch is somebody
  # else's.
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" sparkle)"
  FAKE_PRS='[{"number":7,"state":"MERGED","headRefName":"worktree-sparkle",
              "headRefOid":"0000000000000000000000000000000000000001",
              "closedAt":"2099-01-01T00:00:00Z"}]' refresh
  [ "$status" -eq 0 ]
  # merged+1, not a plain merged: the merged+K arm below takes an unreachable
  # SHA as "the branch moved on since" and says so with K=1. What this test is
  # about is the PR surviving the gate at all.
  [ "$(col sparkle 7)" = "#7 merged+1" ]
}

@test "an OPEN PR on a reused name is kept — a push to that name lands on it" {
  # No closedAt to judge by, and that is the honest answer rather than a gap:
  # the branch name is the head ref, so pushing this lane updates that very PR.
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" sparkle)"
  FAKE_PRS='[{"number":7,"state":"OPEN","headRefName":"worktree-sparkle",
              "headRefOid":"0000000000000000000000000000000000000001"}]' refresh
  [ "$status" -eq 0 ]
  [ "$(col sparkle 7)" = "#7 open" ]
}

@test "a branch with no reflog dates itself by its own oldest commit" {
  # Reflogs can be off (core.logAllRefUpdates=false) or aged out by gc, and the
  # gate must still be able to fire — the commits a lane carries of its own are
  # the next-best "this branch did not exist before".
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" sparkle)"
  rm -f "$main/.git/logs/refs/heads/worktree-sparkle"
  FAKE_PRS='[{"number":7,"state":"MERGED","headRefName":"worktree-sparkle",
              "headRefOid":"0000000000000000000000000000000000000001",
              "closedAt":"2020-01-01T00:00:00Z"}]' refresh
  [ "$status" -eq 0 ]
  [ "$(col sparkle 7)" = - ] || fail "with no reflog the stale PR came back"
}

@test "the per-branch fallback asks gh for every field the reader selects on" {
  # It did not, and the omission was silent in exactly the way this suite exists
  # for: `--head` filtered the PRs, the reader then selected on `headRefName`,
  # gh had never been asked for it, and every fallback answer came back empty
  # from a cache file full of PRs. No error, no log, just "-" forever on any lane
  # whose PR fell out of the newest-100 window.
  local main; main="$(mkrepo alpha)"
  mkwt "$main" sparkle >/dev/null
  FAKE_PRS='[]' FAKE_PRS_HEAD_ACME_ALPHA='[{"number":7,"state":"OPEN","headRefName":"worktree-sparkle"}]' refresh
  [ "$status" -eq 0 ]
  local line; line=$(grep -- "--head worktree-sparkle" "$FAKE_GH_LOG" | head -1)
  case "$line" in *headRefName*) : ;; *) fail "the --head call never asked for headRefName: $line" ;; esac
}

@test "uncommitted work is counted, and untracked-only counts too" {
  local main dir; main="$(mkrepo alpha)"
  dir="$(mkwt "$main" sparkle)"
  echo more >>"$dir/work.txt"       # tracked edit
  echo new >"$dir/brand-new.txt"    # untracked file
  refresh
  [ "$status" -eq 0 ]
  [ "$(col sparkle 4)" = 2 ]        # two dirty entries
  [ "$(col sparkle 5)" = 1 ]        # one inserted line, from the tracked edit
}

# ── the freezes: one bad row must never cost the pass ────────────────────────

@test "a checkout git cannot read does not abort the refresh" {
  # THE regression. `git status` in a husk exits 128; under `set -e` that killed
  # the script before its `mv "$PANEL.tmp" "$PANEL"`, so panel.tsv kept its last
  # good content forever and the bar showed hours-dead worktrees with no error
  # anywhere. Registry order matters: the husk is listed FIRST, so a fragile
  # refresher never reaches the healthy worktrees behind it.
  local main dead; main="$(mkrepo alpha)"
  dead="$(mkwt "$main" ghosted)"
  mkwt "$main" healthy >/dev/null
  husk "$main" "$dead"
  refresh
  [ "$status" -eq 0 ] || fail "the refresher died on one unreadable checkout: $output"
  [ -n "$(row_for x healthy)" ] \
    || fail "a healthy worktree lost its row because an unrelated checkout was unreadable"
  # The husk's BRANCH is still real work — commits and a PR come from the main
  # checkout, not from the unreadable directory — so it keeps its row, with no
  # working-tree delta.
  [ "$(col ghosted 3)" = 1 ]
  [ "$(col ghosted 4)" = 0 ]
}

@test "a worktree whose only change is untracked does not abort the refresh" {
  # `diff HEAD --shortstat` prints NOTHING when every change is untracked, so awk
  # emitted nothing, `read` hit EOF and returned 1, and `set -e` took the whole
  # pass down. One new file in any worktree on the machine froze the entire bar.
  local main dir; main="$(mkrepo alpha)"
  dir="$(mkwt "$main" newfile)"
  mkwt "$main" healthy >/dev/null
  echo brand-new >"$dir/only-untracked.txt"
  refresh
  [ "$status" -eq 0 ] || fail "an untracked-only worktree killed the refresh: $output"
  [ "$(col newfile 4)" = 1 ]
  [ "$(col newfile 5)" = 0 ]
  [ -n "$(row_for x healthy)" ]
}

@test "a registry row pointing at a deleted main checkout invents nothing" {
  # A guard, not a repair: this one passes against the old script too. `dirname ""`
  # is "." and exits 0, so a failed rev-parse yields a main of ".", which every
  # later `git -C` resolves against the REFRESHER's own cwd — the exact trap that
  # made the old bash `wt` list a repo literally named "." (hence its git_main).
  # Only an unreachable ordering of failures kept it from biting here; the resolution is
  # now explicit, and this pins it so a later edit can't reopen it.
  local main gone; main="$(mkrepo alpha)"
  mkwt "$main" sparkle >/dev/null
  gone="$TMP/repos/deleted"
  printf 'phantom\t%s\tworktree-phantom\t%s\t\n' "$gone" "$CLAUDE_WT_BASE/deleted/phantom" >>"$REG"
  cd "$main"                       # a cwd that IS a repo, which is what made this bite
  refresh
  [ "$status" -eq 0 ]
  [ "$(names)" = "sparkle " ] || fail "phantom rows: $(cat "$PANEL")"
}

@test "one unreadable checkout costs its own row, not the ones after it" {
  # The general contract, independent of any single cause: rows are produced by a
  # function invoked as `panel_row … || true`, so an unanticipated non-zero can
  # only ever remove that row. Ten worktrees, every other one a husk.
  local main i dir; main="$(mkrepo alpha)"
  for i in 1 2 3 4 5 6 7 8 9 10; do
    dir="$(mkwt "$main" "w$i")"
    [ $(( i % 2 )) -eq 0 ] && husk "$main" "$dir"
  done
  refresh
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$PANEL" | tr -d ' ')" = 10 ] || fail "expected all ten rows, got: $(cat "$PANEL")"
}

# ── the cache file itself ────────────────────────────────────────────────────

@test "the panel is replaced whole — never left half-written" {
  # The render path reads this file on a 12s timer with no locking, so it must
  # only ever see a complete generation. That is what the .tmp + mv is for.
  local main; main="$(mkrepo alpha)"
  mkwt "$main" first >/dev/null
  refresh
  local before; before="$(cat "$PANEL")"
  mkwt "$main" second >/dev/null
  refresh
  [ "$status" -eq 0 ]
  [ ! -e "$PANEL.tmp" ] || fail "the scratch file survived the run"
  [ "$(names)" = "first second " ]
  [ "$before" != "$(cat "$PANEL")" ] || fail "the panel didn't move when a worktree was added"
}

@test "a second refresher finds the lock held and exits without touching the panel" {
  local main; main="$(mkrepo alpha)"
  mkwt "$main" sparkle >/dev/null
  refresh
  local before; before="$(cat "$PANEL")"
  mkwt "$main" second >/dev/null
  mkdir -p "$CLAUDE_STATUSLINE_CACHE/refresh.lock"   # a live refresher's lock
  refresh
  [ "$status" -eq 0 ]
  [ "$(cat "$PANEL")" = "$before" ] || fail "a locked-out refresher rewrote the panel anyway"
  rmdir "$CLAUDE_STATUSLINE_CACHE/refresh.lock"
}

@test "a lock left behind by a killed refresher is reclaimed, not honoured forever" {
  local main lock; main="$(mkrepo alpha)"
  mkwt "$main" sparkle >/dev/null
  lock="$CLAUDE_STATUSLINE_CACHE/refresh.lock"
  mkdir -p "$lock"
  # Older than the 60s breaker: a pane killed mid-write must not wedge the bar
  # for the rest of the session.
  touch -t 200001010000 "$lock"
  refresh
  [ "$status" -eq 0 ]
  [ -n "$(row_for x sparkle)" ] || fail "a stale lock blocked the refresh permanently"
  [ ! -d "$lock" ] || fail "the lock outlived the run that reclaimed it"
}

@test "no registry at all is an empty panel, not a crash" {
  refresh
  [ "$status" -eq 0 ]
  [ -f "$PANEL" ]
  [ ! -s "$PANEL" ]
}

# ── orphans: worktrees the registry never heard of ───────────────────────────

@test "a worktree made outside scruff still gets a row, with an empty parent" {
  # A raw `git worktree add` under the base skips the registry, so it has no
  # recorded parent. It is folded in anyway with parent empty — the statusline
  # surfaces those only in the $HOME pane, so a stray is never fully invisible.
  local main dir; main="$(mkrepo alpha)"
  dir="$CLAUDE_WT_BASE/alpha/manual"
  mkdir -p "$(dirname "$dir")"
  git -C "$main" worktree add -q -b worktree-manual "$dir" >/dev/null 2>&1
  echo work >"$dir/w.txt"
  git -C "$dir" add -A
  git -C "$dir" -c commit.gpgsign=false commit -qm manual
  refresh
  [ "$status" -eq 0 ]
  [ -n "$(row_for x manual)" ] || fail "a worktree scruff never made is invisible in the bar"
  [ -z "$(col manual 8)" ] || fail "an unregistered worktree claimed a parent"
}

@test "the registry's parent wins over the on-disk row for the same checkout" {
  local main dir; main="$(mkrepo alpha)"
  dir="$(mkwt "$main" sparkle "$TMP/some/spawning/pane")"
  [ -d "$dir" ]
  refresh
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$PANEL" | tr -d ' ')" = 1 ] || fail "the same worktree was listed twice"
  [ "$(col sparkle 8)" = "$TMP/some/spawning/pane" ]
}

# ── the Codex usage feed ─────────────────────────────────────────────────────
# This one is unlike its neighbours: Claude and Opencode leave usage on disk, so
# their feeds are pure reads, but Codex's only source is the account itself over
# the network — and reaching it means holding an OAuth token whose refresh
# ROTATES it server-side. Everything below exists because of the same asymmetry:
# a wrong percentage is a cosmetic bug, while a lost token is `codex login` from
# a terminal to fix a bar pill. Hence the fixtures for a refresh that half-fails.
#
# `curl` is shimmed exactly like `gh` is, and both endpoints are $CODEX_API /
# $CODEX_OAUTH knobs, so nothing here can reach the real chatgpt.com.

mkjwt() { # mkjwt <exp> — an UNSIGNED token; the script reads claims, never verifies
  local p
  p=$(printf '{"exp":%s,"client_id":"app_TEST"}' "$1" | base64 | tr -d '=\n' | tr '/+' '_-')
  printf 'eyJhbGciOiJub25lIn0.%s.sig' "$p"
}

mkauth() { # mkauth <exp> — a ~/.codex/auth.json whose access token expires then
  mkdir -p "$HOME/.codex"
  cat >"$HOME/.codex/auth.json" <<EOF
{"auth_mode":"chatgpt","OPENAI_API_KEY":null,
 "tokens":{"id_token":"ID.OLD","access_token":"$(mkjwt "$1")","refresh_token":"RT-OLD","account_id":"acct-1"},
 "last_refresh":"2026-07-23T09:42:54.708131Z"}
EOF
  chmod 600 "$HOME/.codex/auth.json"
}

mkcurl() { # shim curl: log every call, answer from FAKE_OAUTH / FAKE_USAGE
  # Three endpoints now, and the arm is chosen from the URL ALONE — `http*` — not
  # from whichever argument matches first. Headers are arguments too: Anthropic's
  # call carries `anthropic-beta: oauth-2025-04-20`, which an `*oauth*` arm reads
  # as the token endpoint and answers with OpenAI's empty refresh payload, three
  # arguments before the URL is ever looked at. The claude arm still precedes the
  # codex one, because both URLs end in `usage`.
  cat >"$BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CURL_LOG"
for a in "$@"; do
  case "$a" in
    http*claude-usage*) printf '%s' "${FAKE_CLAUDE_USAGE:-}"; exit "${FAKE_CLAUDE_USAGE_RC:-0}" ;;
    http*oauth*)        printf '%s' "${FAKE_OAUTH:-}"; exit "${FAKE_OAUTH_RC:-0}" ;;
    http*usage*)        printf '%s' "${FAKE_USAGE:-}"; exit "${FAKE_USAGE_RC:-0}" ;;
  esac
done
exit 1
EOF
  chmod +x "$BIN/curl"
  export CURL_LOG="$TMP/curl.log"
  export CODEX_API="http://127.0.0.1:0/usage" CODEX_OAUTH="http://127.0.0.1:0/oauth"
  export CLAUDE_API="http://127.0.0.1:0/claude-usage"
  : >"$CURL_LOG"
}

mkcreds() { # mkcreds [expiry-epoch] — Claude Code logged in, as the keychain has it
  # The opt-in: `projects/` is written by the CLIENT when it actually runs,
  # unlike ~/.claude itself, which haus writes for every machine.
  mkdir -p "$HOME/.claude/projects"
  export FAKE_KEYCHAIN
  FAKE_KEYCHAIN=$(printf '{"claudeAiOauth":{"accessToken":"AT-CLAUDE","refreshToken":"RT-CLAUDE","expiresAt":%s000,"subscriptionType":"max"}}' \
    "${1:-$(( $(date +%s) + 86400 ))}")
}

clrow() { # clrow <n> — one field of the claude usage row
  awk -F'\t' -v c="$1" '{print $c}' "$CLAUDE_STATUSLINE_CACHE/usage-claude.tsv" 2>/dev/null
}

cxrow() { # cxrow <n> — one field of the codex usage row
  awk -F'\t' -v c="$1" '{print $c}' "$CLAUDE_STATUSLINE_CACHE/usage-codex.tsv" 2>/dev/null
}

# Plus answers with ONE window — the weekly one, in the `primary` slot.
USAGE_PLUS='{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":37.4,"limit_window_seconds":604800,"reset_at":1786178866},"secondary_window":null}}'
# Other plans answer with both, 5-hourly first.
USAGE_BOTH='{"rate_limit":{"primary_window":{"used_percent":12,"limit_window_seconds":18000,"reset_at":1785600000},"secondary_window":{"used_percent":88,"limit_window_seconds":604800,"reset_at":1786178866}}}'

@test "codex: windows are matched by duration, not by position" {
  # The bug this forbids: reading primary→session, secondary→weekly. On Plus that
  # files a WEEKLY number in the 5-hour column, and the pill colours off it.
  mkcurl; mkauth "$(( $(date +%s) + 86400 ))"
  FAKE_USAGE="$USAGE_PLUS" refresh
  [ "$status" -eq 0 ]
  [ "$(cxrow 1)" = 0 ] || fail "invented a session figure from a 7-day window"
  [ "$(cxrow 2)" = 37 ] || fail "weekly percent wrong (want 37, the floor of 37.4)"
  [ "$(cxrow 4)" = 1786178866 ]
  [ "$(cxrow 6)" = codex ]

  rm -f "$CLAUDE_STATUSLINE_CACHE/usage-codex.tsv"
  FAKE_USAGE="$USAGE_BOTH" refresh
  [ "$(cxrow 1)" = 12 ] && [ "$(cxrow 2)" = 88 ] || fail "two windows landed in the wrong columns"
}

@test "codex: a healthy token is never refreshed, and a fresh row is not re-fetched" {
  mkcurl; mkauth "$(( $(date +%s) + 86400 ))"
  FAKE_USAGE="$USAGE_PLUS" refresh
  grep -q oauth "$CURL_LOG" && fail "rotated a token that had a day left"
  : >"$CURL_LOG"
  FAKE_USAGE="$USAGE_PLUS" refresh                      # inside CODEX_TTL
  grep -q usage "$CURL_LOG" && fail "spent an API call inside the TTL"
  return 0
}

@test "codex: an expiring token is refreshed and the rotation is persisted" {
  mkcurl; mkauth "$(( $(date +%s) - 10 ))"
  local before; before="$(cat "$HOME/.codex/auth.json")"
  FAKE_OAUTH='{"access_token":"AT-NEW","refresh_token":"RT-NEW","id_token":"ID-NEW"}' \
    FAKE_USAGE="$USAGE_PLUS" refresh
  [ "$status" -eq 0 ]
  grep -q RT-OLD "$CURL_LOG" || fail "the exchange did not send the stored refresh token"
  [ "$(jq -r .tokens.access_token "$HOME/.codex/auth.json")" = AT-NEW ]
  [ "$(jq -r .tokens.refresh_token "$HOME/.codex/auth.json")" = RT-NEW ] \
    || fail "the rotated refresh token was not written back — the login is now lost"
  [ "$(jq -r .tokens.id_token "$HOME/.codex/auth.json")" = ID-NEW ]
  [ "$(jq -r .tokens.account_id "$HOME/.codex/auth.json")" = acct-1 ] \
    || fail "rewriting the tokens dropped a field it does not own"
  [ "$(fmode "$HOME/.codex/auth.json")" = 600 ] || fail "auth.json left world-readable"
  [ "$(cat "$HOME/.codex/auth.json.bak")" = "$before" ] || fail ".bak is not the pre-refresh login"
  grep -q 'Bearer AT-NEW' "$CURL_LOG" || fail "polled with the token it had just replaced"
}

@test "codex: a response without a new refresh token keeps the old one" {
  # Rotation is the server's choice, not ours. Reading `.refresh_token // empty`
  # into the file unconditionally would blank the only credential that matters.
  mkcurl; mkauth "$(( $(date +%s) - 10 ))"
  FAKE_OAUTH='{"access_token":"AT-2"}' FAKE_USAGE="$USAGE_PLUS" refresh
  [ "$(jq -r .tokens.refresh_token "$HOME/.codex/auth.json")" = RT-OLD ] \
    || fail "the refresh token was clobbered by an absent field"
  [ "$(jq -r .tokens.id_token "$HOME/.codex/auth.json")" = ID.OLD ]
}

@test "codex: a failed exchange leaves auth.json byte for byte" {
  mkcurl; mkauth "$(( $(date +%s) - 10 ))"
  local before; before="$(cat "$HOME/.codex/auth.json")"
  FAKE_OAUTH_RC=22 FAKE_OAUTH='' FAKE_USAGE="$USAGE_PLUS" refresh
  [ "$status" -eq 0 ] || fail "a dead auth endpoint took the whole refresher down"
  [ "$(cat "$HOME/.codex/auth.json")" = "$before" ] || fail "a failed refresh still rewrote the login"
}

@test "codex: an unanswered poll keeps the last row and its own stamp" {
  # Touch, don't write. The pill dates rows from the stamp INSIDE the file, so
  # overwriting it with fresh-but-empty numbers would make the bar lie; touching
  # only backs the retry off a TTL while it keeps saying "as of Nm ago".
  mkcurl; mkauth "$(( $(date +%s) + 86400 ))"
  mkdir -p "$CLAUDE_STATUSLINE_CACHE"   # the refresher makes it; this row predates it
  printf '1\t2\t3\t4\t5\tcodex\n' >"$CLAUDE_STATUSLINE_CACHE/usage-codex.tsv"
  touch -t 202601010000 "$CLAUDE_STATUSLINE_CACHE/usage-codex.tsv"
  FAKE_USAGE_RC=7 FAKE_USAGE='' refresh
  [ "$status" -eq 0 ]
  [ "$(cxrow 5)" = 5 ] || fail "an empty answer overwrote the last known numbers"
  [ "$(( $(date +%s) - $(fmtime "$CLAUDE_STATUSLINE_CACHE/usage-codex.tsv") ))" -lt 60 ] \
    || fail "the retry was not backed off — this re-curls on every render"
}

@test "usage-only: refreshes the pulled feeds and leaves the panel untouched" {
  # The mode bar's aiUsage pill runs on a machine with no Claude session to kick
  # the refresher. It must do the two pulled feeds and NOTHING else: no panel
  # rewrite, and — the part that matters for a pill ticking every few minutes —
  # not one `gh` call.
  local main dir; main="$(mkrepo alpha)"; dir="$(mkwt "$main" sparkle)"
  refresh                                   # a full pass, to leave a real panel
  [ "$status" -eq 0 ]
  [ -n "$(row_for x sparkle)" ]
  local before; before="$(cat "$PANEL")"
  : >"$FAKE_GH_LOG"

  mkcurl; mkauth "$(( $(date +%s) + 86400 ))"
  FAKE_USAGE="$USAGE_BOTH" run bash "$REFRESH" --usage-only
  [ "$status" -eq 0 ]
  [ "$(cxrow 1)" = 12 ]
  [ "$(cat "$PANEL")" = "$before" ]
  [ ! -s "$FAKE_GH_LOG" ] || fail "usage-only spent a gh call on the panel"
}

# ── used vs written, the column the pill picks `latest` on ───────────────────
# Column 5 is when the row was WRITTEN and column 9 is when quota was last USED,
# and they are two columns because for a PULLED feed they are nothing alike: this
# block re-asks OpenAI every CODEX_TTL seconds whether Codex has been touched or
# not. While they were one column, the pill's `latest` provider was simply
# "whichever feed polls most often" — Codex, permanently, days after the last
# Codex session.

@test "codex: an idle poll carries the used stamp forward" {
  mkcurl; mkauth "$(( $(date +%s) + 86400 ))"
  FAKE_USAGE="$USAGE_BOTH" refresh
  [ "$status" -eq 0 ]
  local first; first="$(cxrow 9)"
  [ -n "$first" ] || fail "no used column was written at all"

  # Age the file past the TTL without touching its CONTENT — `rm` would work for
  # the fetch but takes the previous row with it, which is the thing under test.
  touch -t 202601010000 "$CLAUDE_STATUSLINE_CACHE/usage-codex.tsv"
  sleep 1
  FAKE_USAGE="$USAGE_BOTH" refresh                # same percentages: nobody used it
  [ "$(cxrow 5)" != "$first" ] || fail "the written stamp did not move on a real poll"
  [ "$(cxrow 9)" = "$first" ] \
    || fail "an idle poll counted as use — this is the bug that pinned the pill to Codex"
}

@test "codex: a percentage that rises is use, one that falls is a window rolling over" {
  mkcurl; mkauth "$(( $(date +%s) + 86400 ))"
  FAKE_USAGE="$USAGE_BOTH" refresh                # 12 / 88
  local first; first="$(cxrow 9)"

  touch -t 202601010000 "$CLAUDE_STATUSLINE_CACHE/usage-codex.tsv"
  sleep 1
  # 12 → 0: the 5-hour window reset. The opposite of use, and it must not bump.
  FAKE_USAGE='{"rate_limit":{"primary_window":{"used_percent":0,"limit_window_seconds":18000,"reset_at":1785600000},"secondary_window":{"used_percent":88,"limit_window_seconds":604800,"reset_at":1786178866}}}' \
    refresh
  [ "$(cxrow 9)" = "$first" ] || fail "a window rollover was counted as use"

  touch -t 202601010000 "$CLAUDE_STATUSLINE_CACHE/usage-codex.tsv"
  sleep 1
  # 0 → 5: somebody actually ran Codex.
  FAKE_USAGE='{"rate_limit":{"primary_window":{"used_percent":5,"limit_window_seconds":18000,"reset_at":1785600000},"secondary_window":{"used_percent":88,"limit_window_seconds":604800,"reset_at":1786178866}}}' \
    refresh
  [ "$(cxrow 9)" != "$first" ] || fail "a percentage that rose did not count as use"
  [ "$(( $(date +%s) - $(cxrow 9) ))" -lt 60 ] || fail "the used stamp is not now"
}

@test "codex: no column ever lands empty in the middle of the row" {
  # Tab is IFS whitespace, so `read` collapses a run of empty middle fields and
  # every later column shifts left — the used stamp would arrive in the reader's
  # `model` and the pill would order `latest` on a string. Columns 7/8 are filled
  # for exactly this reason, though provider_style's codex arm reads neither.
  mkcurl; mkauth "$(( $(date +%s) + 86400 ))"
  FAKE_USAGE="$USAGE_BOTH" refresh
  local n; n=$(awk -F'\t' '{print NF; exit}' "$CLAUDE_STATUSLINE_CACHE/usage-codex.tsv")
  [ "$n" = 9 ] || fail "wrote $n columns, want 9"
  local i
  for i in 1 2 3 4 5 6 7 8 9; do
    [ -n "$(cxrow $i)" ] || fail "column $i is empty — every later column has shifted left"
  done
  # And the reader's own parse gets the row back the way it was written.
  local a b; IFS=$'\t' read -r _ _ _ _ _ _ a b _ <"$CLAUDE_STATUSLINE_CACHE/usage-codex.tsv"
  [ "$a" = codex ] && [ "$b" = openai ] || fail "columns 7/8 did not survive a read"
}

@test "codex: no auth.json means no outbound call at all" {
  # The whole opt-in. A machine that never logged into Codex must not talk to
  # OpenAI because a bar pill exists.
  mkcurl
  rm -f "$HOME/.codex/auth.json"
  refresh
  [ "$status" -eq 0 ]
  grep -qE 'usage|oauth' "$CURL_LOG" && fail "called out with no Codex login on the machine"
  [ ! -f "$CLAUDE_STATUSLINE_CACHE/usage-codex.tsv" ]
}

# ── the Claude usage feed ────────────────────────────────────────────────────
# Claude's row is normally PUSHED by statusline.sh, for free, on every render —
# and that is still the primary source. This block is the hole underneath it: a
# statusline is a TUI feature, the Claude Code macOS app renders none, and a day
# driven from the desktop app leaves the pill on percentages from the last time
# a terminal pane was open. Same asymmetry as Codex, so: ask the account.
#
# The keychain is the delicate part here the way a rotating refresh token is
# delicate there. Nothing below may raise a macOS prompt on a machine that never
# logged in, and nothing may re-raise one every two minutes after a refusal.

CLAUDE_USAGE='{"five_hour":{"utilization":41,"resets_at":"2026-08-20T03:00:00Z"},"seven_day":{"utilization":63,"resets_at":"2026-08-24T00:00:00Z"},"seven_day_opus":{"utilization":12,"resets_at":"2026-08-24T00:00:00Z"}}'

@test "claude: a GUI-only machine still gets a row, pulled from the account" {
  # The regression in one line: no statusline ever ran here, so nothing pushed.
  mkcurl; mkcreds
  [ ! -f "$CLAUDE_STATUSLINE_CACHE/usage-claude.tsv" ]
  FAKE_CLAUDE_USAGE="$CLAUDE_USAGE" refresh
  [ "$status" -eq 0 ]
  [ "$(clrow 1)" = 41 ] || fail "5-hour percent wrong: $(clrow 1)"
  [ "$(clrow 2)" = 63 ] || fail "7-day percent wrong: $(clrow 2)"
  [ "$(clrow 6)" = claude ]
  grep -q 'Bearer AT-CLAUDE' "$CURL_LOG" || fail "polled without the keychain's token"
  # usage.tsv is the pre-per-provider name statusline.sh still copies to; the two
  # must not drift, or a machine mid-upgrade reads the older of them.
  [ "$(cat "$CLAUDE_STATUSLINE_CACHE/usage.tsv")" = "$(cat "$CLAUDE_STATUSLINE_CACHE/usage-claude.tsv")" ]
}

@test "claude: an ISO reset time becomes the epoch the pill compares against" {
  # The pill asks `[ "$r5" -gt "$now" ]`. A string there is not a late reset, it
  # is `integer expression expected` in the bar's log every fifteen seconds.
  mkcurl; mkcreds
  FAKE_CLAUDE_USAGE="$CLAUDE_USAGE" refresh
  [ "$(clrow 3)" = "$(jq -rn '"2026-08-20T03:00:00Z" | fromdateiso8601')" ]
  [ "$(clrow 4)" = "$(jq -rn '"2026-08-24T00:00:00Z" | fromdateiso8601')" ]

  # Fractional seconds and a +00:00 offset are the two shapes fromdateiso8601
  # refuses outright; both are filed off before it sees them.
  rm -f "$CLAUDE_STATUSLINE_CACHE/usage-claude.tsv"
  FAKE_CLAUDE_USAGE='{"five_hour":{"utilization":1,"resets_at":"2026-08-20T03:00:00.512Z"},
                      "seven_day":{"utilization":2,"resets_at":"2026-08-24T00:00:00+00:00"}}' \
    refresh
  [ "$(clrow 3)" = "$(jq -rn '"2026-08-20T03:00:00Z" | fromdateiso8601')" ]
  [ "$(clrow 4)" = "$(jq -rn '"2026-08-24T00:00:00Z" | fromdateiso8601')" ]
}

@test "claude: a token file wins, and the keychain is not touched at all" {
  # The file is the point of this feed, not a convenience. The keychain item is
  # the CLI's: `claude` renews it while a terminal pane is open and the macOS app
  # never writes it, so on a GUI-driven machine it is simply expired — which is
  # how it was found. A token from `claude setup-token` is nobody's to rotate.
  mkcurl; mkcreds
  mkdir -p "$HOME/.config/haus"
  printf '# from `claude setup-token`, 2026-08-19\nsk-ant-oat01-FILE\n' \
    >"$HOME/.config/haus/claude-usage-token"
  : >"$SECURITY_LOG"
  FAKE_CLAUDE_USAGE="$CLAUDE_USAGE" refresh
  [ "$status" -eq 0 ]
  [ "$(clrow 1)" = 41 ]
  grep -q 'Bearer sk-ant-oat01-FILE' "$CURL_LOG" || fail "polled with something other than the file's token"
  [ ! -s "$SECURITY_LOG" ] || fail "read the keychain anyway, with a token already in hand"
}

@test "claude: an expired keychain is the reason the file exists, and it still falls back" {
  # Order matters both ways: no file → the keychain is still worth asking, since
  # right after a TUI session it is fresh and costs nothing.
  mkcurl; mkcreds
  [ ! -e "$HOME/.config/haus/claude-usage-token" ]
  FAKE_CLAUDE_USAGE="$CLAUDE_USAGE" refresh
  [ "$(clrow 1)" = 41 ]
  grep -q 'Bearer AT-CLAUDE' "$CURL_LOG" || fail "did not fall back to the keychain"
}

@test "claude: no Claude Code on the machine means the keychain is never touched" {
  # The whole opt-in, and the reason it is a file test rather than a keychain
  # lookup: asking the keychain IS the prompt.
  mkcurl
  rm -rf "$HOME/.claude"
  refresh
  [ "$status" -eq 0 ]
  [ ! -s "$SECURITY_LOG" ] || fail "read the login keychain on a machine with no Claude Code"
  grep -q claude-usage "$CURL_LOG" && fail "called Anthropic anyway"
  return 0
}

@test "claude: haus's own ~/.claude files are not an opt-in" {
  # The AI room WRITES ~/.claude/CLAUDE.md and ~/.claude/skills/haus for any
  # machine whose haus.ai.clients names claude, so the directory's existence
  # says nothing about whether Claude Code was ever installed. Gating on it
  # drew an hourly keychain prompt on a Codex-only Mac that still had a stale
  # credentials item — a prompt from a feed the user never asked for.
  mkcurl
  rm -rf "$HOME/.claude"
  mkdir -p "$HOME/.claude/skills/haus"
  : >"$HOME/.claude/CLAUDE.md"
  refresh
  [ "$status" -eq 0 ]
  [ ! -s "$SECURITY_LOG" ] || fail "a haus-written CLAUDE.md was read as a Claude Code login"
}

@test "claude: a keychain that says no goes quiet for an hour" {
  # A denied prompt and a missing item look the same from here, and both must be
  # answered by backing off: this runs every couple of minutes, and `security`
  # re-prompts on the very next call after a plain Deny. Without the backoff the
  # feature is a popup loop.
  mkcurl; mkcreds; unset FAKE_KEYCHAIN         # ~/.claude exists, the item does not
  refresh
  [ "$status" -eq 0 ]
  [ -s "$SECURITY_LOG" ] || fail "never asked at all"
  [ -f "$CLAUDE_STATUSLINE_CACHE/.claude-usage-blocked" ] || fail "no backoff was recorded"
  : >"$SECURITY_LOG"
  refresh
  [ ! -s "$SECURITY_LOG" ] || fail "asked again two minutes later — this is the popup loop"

  # And the backoff lifts on its own, rather than needing a file deleted by hand.
  touch -t 202601010000 "$CLAUDE_STATUSLINE_CACHE/.claude-usage-blocked"
  mkcreds
  FAKE_CLAUDE_USAGE="$CLAUDE_USAGE" refresh
  [ "$(clrow 1)" = 41 ] || fail "the hour passed and it never tried again"
  [ ! -f "$CLAUDE_STATUSLINE_CACHE/.claude-usage-blocked" ] || fail "a success left the block in place"
}

@test "claude: an expired token is not spent, and never rotated here" {
  # Refreshing would mean writing the rotated pair back into the LOGIN keychain,
  # where losing the response costs a re-login in every client at once. Claude
  # Code renews it in place whenever you use it; this block just waits.
  mkcurl; mkcreds "$(( $(date +%s) - 10 ))"
  refresh
  [ "$status" -eq 0 ]
  grep -q claude-usage "$CURL_LOG" && fail "polled with a token it knew was expired"
  grep -qi 'add-generic-password\|-U ' "$SECURITY_LOG" && fail "wrote to the login keychain"
  return 0
}

@test "claude: an unanswered poll keeps the last row and its own stamp" {
  # Touch, don't write — the same contract the Codex feed keeps. A pushed row
  # from a real session is the LAST good data on the machine; replacing it with
  # zeroes because the network blinked is worse than showing it greyed.
  mkcurl; mkcreds
  mkdir -p "$CLAUDE_STATUSLINE_CACHE"
  printf '7\t9\t3\t4\t5\tclaude\tclaude\tanthropic\t5\n' >"$CLAUDE_STATUSLINE_CACHE/usage-claude.tsv"
  touch -t 202601010000 "$CLAUDE_STATUSLINE_CACHE/usage-claude.tsv"
  FAKE_CLAUDE_USAGE_RC=7 FAKE_CLAUDE_USAGE='' refresh
  [ "$status" -eq 0 ]
  [ "$(clrow 1)" = 7 ] && [ "$(clrow 5)" = 5 ] || fail "an empty answer overwrote real numbers"
  [ "$(( $(date +%s) - $(fmtime "$CLAUDE_STATUSLINE_CACHE/usage-claude.tsv") ))" -lt 60 ] \
    || fail "the retry was not backed off"

  # A body that parses but describes no window is the same event: leave it alone.
  touch -t 202601010000 "$CLAUDE_STATUSLINE_CACHE/usage-claude.tsv"
  FAKE_CLAUDE_USAGE='{"account":"x"}' refresh
  [ "$(clrow 1)" = 7 ] || fail "an unrecognised shape was written as zeroes"
}

@test "claude: a dead endpoint with no row yet still backs off" {
  # The normal state on the machine this feed is FOR: no statusline ever pushed,
  # so there is no file to touch — and touching nothing backs nothing off. This
  # is a poll every three minutes forever, and a keychain prompt every three
  # minutes for anyone who answered the ACL dialog "Allow" rather than "Always
  # Allow". The token was fine; only the endpoint was not.
  mkcurl; mkcreds
  [ ! -f "$CLAUDE_STATUSLINE_CACHE/usage-claude.tsv" ]
  FAKE_CLAUDE_USAGE_RC=7 FAKE_CLAUDE_USAGE='' refresh
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_STATUSLINE_CACHE/.claude-usage-blocked" ] || fail "no backoff, and nothing to touch"
  : >"$SECURITY_LOG"; : >"$CURL_LOG"
  refresh
  [ ! -s "$SECURITY_LOG" ] || fail "asked the keychain again three minutes later"
  grep -q claude-usage "$CURL_LOG" && fail "re-polled a dead endpoint inside the backoff"
  return 0
}

@test "opencode: a session with no model still writes nine full columns" {
  # `session.model` is nullable and the newest session may have been opened and
  # not yet used — and `jq` on EMPTY stdin prints nothing and exits 0, so the
  # `|| echo` fallbacks never fire. Two empty middle fields collapse under
  # `read` (tab is IFS whitespace), the used epoch lands in `model`, and
  # opencode wins `latest` forever while drawing its mark from an epoch. Which
  # is the exact bug the used column was added to remove.
  cat >"$BIN/sqlite3" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"ORDER BY time_updated DESC"*) printf '|1700000000000\n' ;;   # model is NULL
  *SUM\(cost\)*|*printf*)         printf '0.00\n' ;;
  *)                              printf '0\t0\t0\t0\n' ;;
esac
EOF
  chmod +x "$BIN/sqlite3"
  mkdir -p "$HOME/.local/share/opencode"
  : >"$HOME/.local/share/opencode/opencode-stable.db"
  refresh
  [ "$status" -eq 0 ]
  local f="$CLAUDE_STATUSLINE_CACHE/usage-opencode.tsv"
  [ "$(awk -F'\t' '{print NF; exit}' "$f")" = 9 ] || fail "not nine columns"
  local model prov used
  IFS=$'\t' read -r _ _ _ _ _ _ model prov used <"$f"
  [ "$model" = opencode ] || fail "column 7 is '$model' — the row has shifted left"
  [ "$prov" = google ] || fail "column 8 is '$prov'"
  [ "$used" = 1700000000 ] || fail "the used stamp is '$used', not the session's"
}

@test "claude: a fresh row is not re-fetched, pushed or pulled" {
  # The push is the cheap path and stays primary: while a TUI session is live it
  # rewrites this file every render, and each rewrite must hold the poll off.
  mkcurl; mkcreds
  FAKE_CLAUDE_USAGE="$CLAUDE_USAGE" refresh
  : >"$CURL_LOG"
  FAKE_CLAUDE_USAGE="$CLAUDE_USAGE" refresh                    # inside CLAUDE_TTL
  grep -q claude-usage "$CURL_LOG" && fail "spent an API call inside the TTL"
  return 0
}

# ── the lifetime token counter ───────────────────────────────────────────────
# The score in the aiUsage dropdown. Its whole design is an index that lets a
# pass skip transcripts it has already read, so the tests that matter are about
# what the index remembers, what it drops, and where the day boundary falls —
# not about the arithmetic, which is one line.

mkmsg() { # mkmsg <ts> <in> <out> <cacheWrite> <cacheRead> — one assistant record
  printf '{"type":"assistant","timestamp":"%s","message":{"usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s}}}\n' \
    "$1" "$2" "$4" "$5" "$3"
}

mktranscript() { # mktranscript <name> [ts in out cw cr]... — a transcript file
  local f="$HOME/.claude/projects/proj/$1.jsonl"; shift
  mkdir -p "$(dirname "$f")"
  : >"$f"
  while [ "$#" -ge 5 ]; do
    mkmsg "$1" "$2" "$3" "$4" "$5" >>"$f"
    shift 5
  done
  printf '%s' "$f"
}

utc() { # utc <offset seconds from now> — the transcript timestamp format
  local at=$(( $(date +%s) + $1 ))
  date -u -r "$at" '+%Y-%m-%dT%H:%M:%S.000Z' 2>/dev/null \
    || date -u -d "@$at" '+%Y-%m-%dT%H:%M:%S.000Z'
}

tok() { # tok <n> — one field of tokens-claude.tsv (1 day, 2 week, 3 month, 4 all)
  awk -F'\t' -v c="$1" '{print $c}' "$CLAUDE_STATUSLINE_CACHE/tokens-claude.tsv" 2>/dev/null
}

thaw() { # let the next pass past the TTL without waiting a quarter of an hour
  rm -f "$CLAUDE_STATUSLINE_CACHE/tokens-claude.tsv"
}

@test "tokens: all four counters are summed, across every transcript" {
  # Cache READS are the bulk of the number and the reason it is fun. A version
  # that counted only input+output would look plausible and be off by 100x.
  mktranscript a "$(utc -60)" 1 2 4 8 >/dev/null
  mktranscript b "$(utc -60)" 100 200 400 800 >/dev/null
  refresh
  [ "$status" -eq 0 ]
  [ "$(tok 4)" = 1515 ]
}

@test "tokens: a transcript whose size has not moved is never re-read" {
  # The entire point of the index. Proven by rewriting a file's CONTENT while
  # holding its size: a pass that re-read it would see the new number.
  local f; f="$(mktranscript a "$(utc -60)" 1 2 4 8)"
  refresh
  [ "$(tok 4)" = 15 ]

  local size; size=$(wc -c <"$f")
  mkmsg "$(utc -60)" 9 9 9 9 >"$f"
  [ "$(wc -c <"$f")" -eq "$size" ] || skip "fixture sizes drifted; nothing to prove"
  thaw; refresh
  [ "$(tok 4)" = 15 ] || fail "re-read a transcript that had not grown"
}

@test "tokens: a transcript that grew is re-read whole, not double-counted" {
  local f; f="$(mktranscript a "$(utc -60)" 1 2 4 8)"
  refresh
  [ "$(tok 4)" = 15 ]
  mkmsg "$(utc -60)" 10 20 30 40 >>"$f"
  thaw; refresh
  [ "$(tok 4)" = 115 ]
}

@test "tokens: a deleted transcript takes its tokens with it" {
  # Totals are re-summed from the index every pass rather than accumulated, so
  # `claude` clearing out old projects walks the score back instead of leaving
  # it stranded at a number nothing on disk supports.
  mktranscript a "$(utc -60)" 1 2 4 8 >/dev/null
  local b; b="$(mktranscript b "$(utc -60)" 100 200 400 800)"
  refresh
  [ "$(tok 4)" = 1515 ]
  rm -f "$b"
  thaw; refresh
  [ "$(tok 4)" = 15 ]
}

@test "tokens: today counts today, and yesterday keeps out of it" {
  # Today is bounded by LOCAL midnight even though the timestamps are UTC — the
  # cutoff is converted once and compared as a string.
  mktranscript old "$(utc -172800)" 1 2 4 8 >/dev/null
  mktranscript new "$(utc 0)" 100 200 400 800 >/dev/null
  refresh
  [ "$(tok 4)" = 1515 ]
  [ "$(tok 1)" = 1500 ]
}

@test "tokens: day, week and month each catch only what belongs to them" {
  # 40 days back is outside every period on any calendar; now is inside all three.
  mktranscript old "$(utc -3456000)" 1 2 4 8 >/dev/null
  mktranscript new "$(utc 0)" 100 200 400 800 >/dev/null
  refresh
  [ "$(tok 1)" = 1500 ]
  [ "$(tok 2)" = 1500 ]
  [ "$(tok 3)" = 1500 ]
  [ "$(tok 4)" = 1515 ]
}

@test "tokens: an idle transcript drops out of every period it has outlived" {
  # The carry-forward hazard. An unchanged file contributes its remembered
  # buckets for free, which is only correct while the periods they were banked
  # in are still running.
  mktranscript a "$(utc 0)" 100 200 400 800 >/dev/null
  refresh
  [ "$(tok 1)" = 1500 ]
  [ "$(tok 2)" = 1500 ]
  [ "$(tok 3)" = 1500 ]

  # Re-date the index entry into the last century, exactly as the first pass of a
  # new day — and week, and month — sees it.
  local idx="$CLAUDE_STATUSLINE_CACHE/tokens-claude.index"
  awk -F'\t' -v OFS='\t' '{ $4 = "1999-01-01"; print }' "$idx" >"$idx.aged"
  mv "$idx.aged" "$idx"
  thaw; refresh
  [ "$(tok 1)" = 0 ] || fail "yesterday's tokens are still on today's scoreboard"
  [ "$(tok 2)" = 0 ] || fail "last century is somehow still this week"
  [ "$(tok 3)" = 0 ] || fail "last century is somehow still this month"
  [ "$(tok 4)" = 1500 ]
}

@test "tokens: an index from an older haus is discarded, not read one column over" {
  # The columns have grown once already. A short row must send its transcript
  # back for a re-read rather than have its size land in the day bucket.
  mktranscript a "$(utc 0)" 100 200 400 800 >/dev/null
  refresh
  [ "$(tok 4)" = 1500 ]

  local idx="$CLAUDE_STATUSLINE_CACHE/tokens-claude.index"
  cut -f1-5 "$idx" >"$idx.old"          # the shape this file had one haus version ago
  mv "$idx.old" "$idx"
  thaw; refresh
  [ "$(tok 4)" = 1500 ] || fail "misread a short index row instead of rescanning"
  [ "$(tok 1)" = 1500 ]
}

@test "tokens: inside the TTL the score is left alone" {
  mktranscript a "$(utc -60)" 1 2 4 8 >/dev/null
  refresh
  [ "$(tok 4)" = 15 ]
  mktranscript b "$(utc -60)" 100 200 400 800 >/dev/null
  refresh                                   # no thaw: still fresh
  [ "$(tok 4)" = 15 ]
}

@test "tokens: no transcripts on the machine means no score file at all" {
  # A machine that has never run Claude Code gets no row in the dropdown, rather
  # than a proud zero.
  refresh
  [ "$status" -eq 0 ]
  [ ! -f "$CLAUDE_STATUSLINE_CACHE/tokens-claude.tsv" ]
}

# ── the lane base moved at scruff 1.1.0 ──────────────────────────────────────
# Every other test in this file pins CLAUDE_WT_BASE, which is exactly why the
# base move went unnoticed here: the env var short-circuits the path the real
# bar takes. These three drive the probe itself, with the var unset.

# base_probe <base> — a registry with one live lane under <base>, CLAUDE_WT_BASE
# unset, and the panel refreshed. Echoes nothing; assert on the panel.
base_probe() {
  local base="$1" main dir
  unset CLAUDE_WT_BASE
  mkdir -p "$base"
  REG="$base/registry.tsv"; : >"$REG"
  main="$(mkrepo alpha)"
  dir="$base/alpha/sparkle"
  mkdir -p "$(dirname "$dir")"
  git -C "$main" worktree add -q -b worktree-sparkle "$dir" >/dev/null 2>&1
  echo work >"$dir/work.txt"
  git -C "$dir" add -A
  git -C "$dir" -c commit.gpgsign=false commit -qm "work on sparkle"
  printf 'sparkle\t%s\tworktree-sparkle\t%s\t%s\n' "$main" "$dir" "$main" >>"$REG"
  refresh
}

@test "base: the default ~/.cache/scruff is found with no env var set" {
  base_probe "$HOME/.cache/scruff"
  [ "$status" -eq 0 ]
  [ -n "$(row_for x sparkle)" ] || fail "the bar found no lanes at the 1.1.0 base"
}

@test "base: a machine that never migrated is still read at the legacy path" {
  # `scruff doctor --migrate-base` is the user's step, and it may never be run.
  # Until it is, the registry lives at the old path and the bar has to see it —
  # this is the rung that keeps a skipped migration from blanking the bar.
  base_probe "$HOME/.cache/claude-worktrees"
  [ "$status" -eq 0 ]
  [ -n "$(row_for x sparkle)" ] || fail "the bar went blind on an un-migrated machine"
}

@test "base: the new path wins when both exist, as it does after the migration" {
  # The migration leaves ~/.cache/claude-worktrees behind as a symlink for one
  # release. A bar that picked the legacy rung first would be reading through it
  # forever, and would go blank at 1.2.0 when the symlink goes.
  mkdir -p "$HOME/.cache/claude-worktrees"
  printf 'stale\t/nope\tworktree-stale\t/nope\t/nope\n' \
    >"$HOME/.cache/claude-worktrees/registry.tsv"
  base_probe "$HOME/.cache/scruff"
  [ "$status" -eq 0 ]
  [ -n "$(row_for x sparkle)" ] || fail "the new base lost to the legacy one"
  [ -z "$(row_for x stale)" ] || fail "the legacy registry was read after the move"
}

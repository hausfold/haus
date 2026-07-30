#!/usr/bin/env bats
# Hermetic tests for the statusline refresher (modules/den/statusline-refresh.sh)
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
  REFRESH="${REFRESH_UNDER_TEST:-$BATS_TEST_DIRNAME/../modules/den/statusline-refresh.sh}"
  TMP="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"   # /var → /private/var, as git resolves it

  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=t@example.com
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=t@example.com

  export HOME="$TMP/home"
  export CLAUDE_WT_BASE="$TMP/wtbase"
  export CLAUDE_STATUSLINE_CACHE="$TMP/cache"
  # No flake.lock here, so the stale-rice nag short-circuits before its curl.
  # Every test would otherwise reach the network on a cold cache.
  export HAUS_CONSUMER="$TMP/no-consumer"
  REG="$CLAUDE_WT_BASE/registry.tsv"
  PANEL="$CLAUDE_STATUSLINE_CACHE/panel.tsv"
  mkdir -p "$HOME" "$CLAUDE_WT_BASE"

  BIN="$TMP/bin"; mkdir -p "$BIN"
  export PATH="$BIN:$PATH"

  # ── shim: gh ───────────────────────────────────────────────────────────────
  # One question is asked of gh: every PR in a repo, as JSON. FAKE_PRS is that
  # answer verbatim; the default is the empty list, which is also what a real gh
  # prints when it is unauthenticated or offline.
  cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >>"${FAKE_GH_LOG:-/dev/null}"
printf '%s' "${FAKE_PRS:-[]}"
EOF
  chmod +x "$BIN/gh"
  export FAKE_GH_LOG="$TMP/gh.log"
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
  # made `wt` list a repo literally named "." (hence its git_main). Only an
  # unreachable ordering of failures kept it from biting here; the resolution is
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

@test "a worktree made outside wt still gets a row, with an empty parent" {
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
  [ -n "$(row_for x manual)" ] || fail "a worktree wt never made is invisible in the bar"
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

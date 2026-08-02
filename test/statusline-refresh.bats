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
  cat >"$BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CURL_LOG"
for a in "$@"; do
  case "$a" in
    *oauth*) printf '%s' "${FAKE_OAUTH:-}"; exit "${FAKE_OAUTH_RC:-0}" ;;
    *usage*) printf '%s' "${FAKE_USAGE:-}"; exit "${FAKE_USAGE_RC:-0}" ;;
  esac
done
exit 1
EOF
  chmod +x "$BIN/curl"
  export CURL_LOG="$TMP/curl.log"
  export CODEX_API="http://127.0.0.1:0/usage" CODEX_OAUTH="http://127.0.0.1:0/oauth"
  : >"$CURL_LOG"
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
  # The mode sill's aiUsage pill runs on a machine with no Claude session to kick
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

@test "tokens: an index from an older rice is discarded, not read one column over" {
  # The columns have grown once already. A short row must send its transcript
  # back for a re-read rather than have its size land in the day bucket.
  mktranscript a "$(utc 0)" 100 200 400 800 >/dev/null
  refresh
  [ "$(tok 4)" = 1500 ]

  local idx="$CLAUDE_STATUSLINE_CACHE/tokens-claude.index"
  cut -f1-5 "$idx" >"$idx.old"          # the shape this file had one rice ago
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

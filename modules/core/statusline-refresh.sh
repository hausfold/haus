#!/usr/bin/env bash
# statusline-refresh.sh — the EXPENSIVE half of the haus statusline.
#
# Enumerates every in-flight agent worktree across ALL repos (via `holt`'s
# registry) and, per repo, asks GitHub once for PR state. Writes a raw-field TSV
# that statusline.sh renders with the SAME status-token logic as row 1. Run
# DETACHED by statusline.sh when its cache goes stale (stale-while-revalidate) —
# never in the render path, so the bar is never blocked by git/gh. Safe to run
# concurrently: a mkdir-lock elects one refresher; the rest exit immediately.
#
#   panel.tsv rows:  slug <TAB> name <TAB> ahead <TAB> files <TAB> ins <TAB> del <TAB> prstate <TAB> parent
#     slug    = owner/repo   (e.g. hausfold/pounce)
#     name    = worktree name (branch minus worktree- prefix)
#     ahead   = commits on the branch not in its default branch
#     files/ins/del = uncommitted working-tree delta (live checkouts only)
#     prstate = "#7 open" | "#7 merged" | "#7 closed" | "#7 merged+3" | "-"
#               ("-" = none; see below. merged+K = the PR merged and K commits
#                landed on the branch SINCE — un-shipped work no PR covers.)
#     parent  = the cwd this worktree was spawned FROM (registry col 5). The
#               statusline shows a session only the rows whose parent == its cwd.
#   Only IN-FLIGHT rows are written (ahead>0, or dirty, or has a PR).
#
# It also writes lock-nag.tsv (see below): how far this machine's pinned rice is
# behind upstream, on its own much longer TTL. Same reason it lives here — it
# needs the network, and the network must never be in the render path.
#
#   --usage-only   skip the panel + the lock nag; refresh ONLY the Codex and
#                  Opencode usage feeds at the bottom, then poke bar's pill.
#                  This is how the aiUsage pill stays alive on a machine driving
#                  Codex or Opencode rather than Claude: those two feeds are
#                  PULLED (an API call, a sqlite read) instead of pushed by the
#                  client, so with no Claude statusline rendering anywhere,
#                  nothing would ever run them and the pill would grey itself out
#                  within half an hour. The panel — and the `gh` traffic it costs
#                  — is deliberately excluded: only a statusline reads panel.tsv.
set -euo pipefail
usage_only=0
[ "${1:-}" = "--usage-only" ] && usage_only=1
# APPENDED, never prepended — same call `holt` makes, for the same two reasons: this
# is a rescue for the case where we're spawned with a bare PATH, not an override of
# the caller's environment; and prepending it made the script untestable, because
# test/statusline-refresh.bats drives it with a shim `gh` that a real /usr/bin/gh
# would win against every time. Guard the ':' — an empty inherited PATH would
# otherwise leave a leading one, which means "the current directory".
PATH="${PATH:+$PATH:}/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/$(id -un 2>/dev/null)/bin:/opt/homebrew/bin:/usr/bin:/bin"

WT_BASE="${CLAUDE_WT_BASE:-$HOME/.cache/claude-worktrees}"
WT_REGISTRY="$WT_BASE/registry.tsv"
CACHE_DIR="${CLAUDE_STATUSLINE_CACHE:-$HOME/.cache/claude-statusline}"
PANEL="$CACHE_DIR/panel.tsv"
LOCK="$CACHE_DIR/refresh.lock"
CONSUMER="${HAUS_CONSUMER:-$HOME/.config/nix}"   # same knob `haus` uses
NAG="$CACHE_DIR/lock-nag.tsv"
NAG_TTL=1800    # seconds; flake pins move on a human cadence, not a 15s one

mtime() { # mtime <file> — modification time in epoch seconds, 0 when unknown
  # `stat -f %m` is BSD/macOS, which is where this runs. On GNU coreutils -f means
  # --file-system and %m is the MOUNT POINT, so it prints "/" and exits 0 — the
  # fallback cannot be selected by exit status alone. Accept the BSD result only
  # when it is numeric, then try GNU stat; finally insist on digits so the caller's
  # arithmetic remains safe under `set -e`.
  local m
  m=$(stat -f %m "$1" 2>/dev/null || true)
  case "$m" in '' | *[!0-9]*) m=$(stat -c %Y "$1" 2>/dev/null || echo 0) ;; esac
  case "$m" in '' | *[!0-9]*) m=0 ;; esac
  printf '%s' "$m"
}

mkdir -p "$CACHE_DIR"
# Single-refresher election: mkdir is atomic. Stale lock (>60s) is reclaimed.
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -d "$LOCK" ]; then
    age=$(( $(date +%s) - $(mtime "$LOCK") ))
    [ "$age" -lt 60 ] && exit 0
    rmdir "$LOCK" 2>/dev/null || true
    mkdir "$LOCK" 2>/dev/null || exit 0
  else
    exit 0
  fi
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

# --- stale-rice nag: how far this machine's pinned haus is behind --------
# There is no "latest" in Nix — a flake input is whatever flake.lock pinned, and
# it only moves when `haus update` moves it. So the bar carries the one number
# that makes that pin visible: how many commits `haus update` would bring in.
#
# ONE unauthenticated GitHub compare call — the same endpoint `haus update` uses
# to list what's landing, so no gh auth, no token, works on a fresh machine.
# api.github.com allows 60 req/hr per IP unauthenticated; at NAG_TTL=30min this
# spends 2, and the render path spends none (it only reads the file below).
#
#   lock-nag.tsv:  behind <TAB> lockLastModified <TAB> compareUrl
#     behind      = commits upstream has that your pin doesn't (0 rows are not written)
#     lockLastMod = the pin's own lastModified epoch — the statusline reddens the
#                   chip once that's older than its NAG_ALERT_DAYS
#     compareUrl  = github.com/…/compare/<pin>…<ref>, so the chip can be an OSC 8
#                   link straight to the commits you haven't taken
# An EMPTY file means "definitively up to date" (chip hidden); a MISSING file
# means we've never got an answer. Either way the statusline renders nothing.
nag_fresh=$usage_only    # --usage-only: treat the nag as fresh, i.e. skip it
if [ "$nag_fresh" = 0 ] && [ -f "$NAG" ]; then
  age=$(( $(date +%s) - $(mtime "$NAG") ))
  [ "$age" -lt "$NAG_TTL" ] && nag_fresh=1
fi
if [ "$nag_fresh" = 0 ] && [ -f "$CONSUMER/flake.lock" ]; then
  lk() { jq -r "(.nodes.haus // .nodes.nebelhaus).$1 // \"$2\"" "$CONSUMER/flake.lock" 2>/dev/null || echo "$2"; }
  lockrev=$(lk 'locked.rev' '')
  lockdate=$(lk 'locked.lastModified' 0)
  owner=$(lk 'original.owner' hausfold)
  repo=$(lk 'original.repo' haus)
  ref=$(lk 'original.ref' HEAD)          # unset ref => compare against HEAD (default branch)
  behind=""
  if [ -n "$lockrev" ]; then
    # compare/BASE...HEAD — ahead_by counts what HEAD has that BASE doesn't,
    # i.e. how far BASE (your pin) is behind.
    behind=$(curl -fsSL --max-time 8 -H 'accept: application/vnd.github+json' \
      "https://api.github.com/repos/$owner/$repo/compare/$lockrev...$ref" 2>/dev/null \
      | jq -r '.ahead_by // empty' 2>/dev/null || true)
  fi
  case "${behind:-}" in ''|*[!0-9]*) behind="";; esac   # only a clean integer counts
  if [ -n "$behind" ] && [ "$behind" -gt 0 ]; then
    printf '%s\t%s\t%s\n' "$behind" "$lockdate" \
      "https://github.com/$owner/$repo/compare/$lockrev...$ref" >"$NAG"
  elif [ -n "$behind" ]; then
    : >"$NAG"                            # up to date — clear the chip
  else
    # No answer (offline, rate-limited, private fork, non-GitHub input). Touch
    # rather than write: keeps the last known count and backs off a full TTL, so
    # a plane ride doesn't burn a 8s curl on every 15s render cycle.
    touch "$NAG"
  fi
fi

git_default() { # default branch of a main checkout, e.g. main / master
  git -C "$1" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null \
    | sed 's@^origin/@@' && return 0
  for b in main master; do
    git -C "$1" show-ref -q --verify "refs/heads/$b" && { echo "$b"; return 0; }
  done
  echo main
}

repo_slug() { # owner/name from a main checkout's origin remote
  local url
  url=$(git -C "$1" remote get-url origin 2>/dev/null) || return 1
  url=${url%.git}
  url=${url#*://}      # drop scheme  (https://host/… -> host/…)
  url=${url#*@}        # drop user    (git@host:…    -> host:…)
  url=${url#*[:/]}     # drop host + first separator  -> owner/name
  [ -n "$url" ] && echo "$url" || return 1
}

# --- PR lookup, one gh call per repo, cached ~120s (PR state moves slowly) ------
pr_json_for_repo() { # $1=main ; echoes cached JSON of that repo's PRs
  local main="$1" slug cache age
  slug=$(repo_slug "$main") || { echo '[]'; return; }
  cache="$CACHE_DIR/pr-$(echo "$slug" | tr '/' '_').json"
  if [ -f "$cache" ]; then
    age=$(( $(date +%s) - $(mtime "$cache") ))
    [ "$age" -lt 120 ] && { cat "$cache"; return; }
  fi
  if gh pr list -R "$slug" --state all --limit 100 \
        --json number,state,headRefName,headRefOid >"$cache.tmp" 2>/dev/null; then
    mv "$cache.tmp" "$cache"
  else
    rm -f "$cache.tmp"; [ -f "$cache" ] || echo '[]' >"$cache"
  fi
  cat "$cache"
}

pr_state_for_branch() { # $1=main $2=branch -> "#N open|merged|closed|merged+K" or ""
  # `|| true`: a truncated cache (a gh run killed mid-write) makes jq exit 5, and
  # under `set -o pipefail` that status would propagate out of the `pr=$(…)`
  # substitution below and, with `set -e`, abort the whole pass. No PR state is a
  # blank cell; it is never a reason to stop refreshing the panel.
  local main="$1" b="$2" raw num state oid tip k
  raw=$(pr_json_for_repo "$main" | jq -r --arg b "$b" '
    map(select(.headRefName == $b)) | (.[0] // empty)
    | "\(.number) \(.state|ascii_downcase) \(.headRefOid // "")"' 2>/dev/null || true)
  [ -n "$raw" ] || return 0
  read -r num state oid <<<"$raw"
  # merged+K — the PR merged, then the branch kept committing. Those K commits are
  # on a branch whose remote counterpart GitHub deleted at merge: no PR covers
  # them and nothing is pushed. Rendering that as a plain `merged` is what put an
  # ⏏ on panes that were sitting on un-shipped work, so it gets its own state.
  # An older cache (or a gh that didn't return the SHA) has no oid — then it is
  # exactly the old `merged`, which is the honest answer with nothing to compare.
  # …unless the tip is already IN the default branch: then those later commits
  # landed too (a second PR, a direct merge), the branch is done, and ⏏ is right.
  if [ "$state" = merged ] && [ -n "${oid:-}" ] && [ "$oid" != null ] \
     && ! git -C "$main" merge-base --is-ancestor "$b" "$(git_default "$main")" 2>/dev/null; then
    tip=$(git -C "$main" rev-parse "$b" 2>/dev/null || true)
    if [ -n "$tip" ] && [ "$tip" != "$oid" ]; then
      k=$(git -C "$main" rev-list --count "$oid..$b" 2>/dev/null || echo 0)
      case "$k" in '' | *[!0-9]*) k=0 ;; esac
      [ "$k" -gt 0 ] || k=1     # the merged SHA isn't reachable here (rebase/amend)
      state="merged+$k"
    fi
  fi
  printf '#%s %s' "$num" "$state"
}

# checkout_readable <path> — 0 only if git can still resolve this checkout.
# `[ -e "$path/.git" ]` is NOT that test. `git worktree remove` deletes the
# repo's admin dir (.git/worktrees/<id>) BEFORE it deletes the working tree, so a
# removal that fails part-way — an ignored node_modules it cannot unlink, a busy
# file — leaves a directory whose .git file points at a gitdir that is gone.
# Every git command run there exits 128 with "not a git repository: (null)".
checkout_readable() {
  [ -e "$1/.git" ] || return 1
  git -C "$1" --no-optional-locks rev-parse --git-dir >/dev/null 2>&1
}

# --- worklist: registry rows UNION live on-disk worktrees, deduped ------------
# The registry (authoritative, carries each worktree's parent) is the primary
# source. But a worktree made with a raw `git worktree add` under $WT_BASE —
# bypassing `holt child` — never lands in the registry, so it would be invisible in
# the bar. Fold every such live checkout in too, with an EMPTY parent (an
# "orphan"): the statusline surfaces orphans ONLY in the $HOME pane, so a stray
# cross-repo worktree is never fully hidden without spamming every session. Dedup
# is by checkout path with the registry line first, so a recorded parent always
# wins over the parent-less on-disk row for the same worktree.
worklist() {
  [ -f "$WT_REGISTRY" ] && awk -F'\t' 'NF>=4 {print $1"\t"$2"\t"$3"\t"$4"\t"$5}' "$WT_REGISTRY"
  local d m b common
  for d in "$WT_BASE"/*/*; do
    [ -e "$d/.git" ] || continue
    # Resolve in two steps and require a non-empty answer: `dirname ""` is "." and
    # exits 0, so folding the rev-parse into the substitution turned an unreadable
    # checkout into a main of "." — which every later git -C then resolved against
    # the REFRESHER's own cwd, inventing rows for whatever repo it happened to run
    # in. (Same trap holt's own git-common-dir resolution exists to close.)
    common=$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || continue
    [ -n "$common" ] || continue
    m=$(dirname "$common")
    [ -d "$m/.git" ] || continue                 # real main checkout, not a nested worktree
    b=$(git -C "$d" --no-optional-locks branch --show-current 2>/dev/null) || continue
    [ -n "$b" ] || continue
    printf '%s\t%s\t%s\t%s\t%s\n' "${b#worktree-}" "$m" "$b" "$d" ""
  done
}

# panel_row <name> <main> <branch> <wtpath> <parent> — one panel line on stdout,
# or nothing when the worktree isn't in flight.
#
# A FUNCTION, not an inline loop body, purely so it can be called as
# `panel_row … || true`: that suspends `set -e` for the whole body, so an
# unanticipated non-zero — a git that dies on a checkout in a state we haven't
# met yet — costs this row and only this row. It used to cost the entire refresh
# (see the working-tree block below), and nothing surfaced the loss.
panel_row() {
  local name="$1" main="$2" branch="$3" wtpath="$4" parent="$5"
  local slug def ahead files ins del pr
  [ -n "${branch:-}" ] || return 0
  git -C "$main" show-ref -q --verify "refs/heads/$branch" 2>/dev/null || return 0
  slug=$(repo_slug "$main" || basename "$main")
  def=$(git_default "$main")
  ahead=$(git -C "$main" rev-list --count "$def..$branch" 2>/dev/null || echo 0)
  case "$ahead" in ''|*[!0-9]*) ahead=0 ;; esac

  # Working-tree delta, best-effort. A checkout that git cannot read (a dangling
  # husk — see checkout_readable) contributes no delta, but its BRANCH is still a
  # real row: it can carry commits and a PR, and those come from the main
  # checkout, not from here.
  #
  # Every git call in this loop is non-fatal by construction. This whole pipeline
  # runs under `set -euo pipefail`, so before this guard existed ONE unreadable
  # checkout exited 128, killed the subshell, failed the pipeline, and aborted the
  # script before its `mv "$PANEL.tmp" "$PANEL"` — freezing panel.tsv at its last
  # good content. The bar then showed hours-dead worktrees and no new ones, with
  # no error anywhere: the refresher is detached, so nobody ever sees its exit.
  # That is the failure mode to protect; a row must never cost the whole pass.
  files=0 ins=0 del=0
  if checkout_readable "$wtpath"; then
    files=$(git -C "$wtpath" --no-optional-locks status --porcelain 2>/dev/null | wc -l | tr -d ' ') || files=0
    case "$files" in ''|*[!0-9]*) files=0 ;; esac
    if [ "$files" -gt 0 ]; then
      # `|| true`: when every change is UNTRACKED, `diff HEAD --shortstat` prints
      # nothing, awk never runs its block, and `read` hits EOF and returns 1 —
      # which `set -e` turned into the same silent whole-pass abort as above. A
      # brand-new file in any worktree was enough to freeze the entire panel.
      read -r ins del < <(git -C "$wtpath" --no-optional-locks diff HEAD --shortstat 2>/dev/null \
        | awk '{i=0;d=0;for(k=1;k<=NF;k++){if($k~/insertion/)i=$(k-1);if($k~/deletion/)d=$(k-1)}print i" "d}') || true
      ins=${ins:-0}; del=${del:-0}
    fi
  fi

  pr=$(pr_state_for_branch "$main" "$branch")

  # in-flight only: unmerged commits, uncommitted edits, or a PR
  [ "$ahead" -gt 0 ] || [ "$files" -gt 0 ] || [ -n "$pr" ] || return 0

  # prstate defaults to "-" (never empty): tab is IFS-whitespace, so an empty
  # MIDDLE field would collapse under `read` and shift later columns left. parent
  # is the trailing field, so an empty one (old 4-col registry rows) is safe.
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$slug" "${branch#worktree-}" "$ahead" "$files" "$ins" "$del" "${pr:--}" "$parent"
}

if [ "$usage_only" = 0 ]; then
  : >"$PANEL.tmp"

  worklist | awk -F'\t' '!seen[$4]++' | while IFS=$'\t' read -r name main branch wtpath parent; do
    panel_row "$name" "$main" "$branch" "$wtpath" "$parent" >>"$PANEL.tmp" || true
  done

  mv "$PANEL.tmp" "$PANEL"
fi

# --- Opencode usage feed: query local sqlite db for daily/monthly API token cost ---
fed=0    # did either pulled feed write a row this pass → poke the pill at the end
OPENCODE_DB="$HOME/.local/share/opencode/opencode-stable.db"
if [ -f "$OPENCODE_DB" ] && command -v sqlite3 >/dev/null 2>&1; then
  oc_today=$(sqlite3 "$OPENCODE_DB" "SELECT printf('%.2f', COALESCE(SUM(cost), 0)) FROM session WHERE time_updated >= strftime('%s', 'now', 'start of day') * 1000;" 2>/dev/null || echo "0.00")
  oc_mtd=$(sqlite3 "$OPENCODE_DB" "SELECT printf('%.2f', COALESCE(SUM(cost), 0)) FROM session WHERE time_updated >= strftime('%s', 'now', 'start of month') * 1000;" 2>/dev/null || echo "0.00")
  oc_latest=$(sqlite3 "$OPENCODE_DB" "SELECT model, time_updated FROM session ORDER BY time_updated DESC LIMIT 1;" 2>/dev/null || echo "")

  if [ -n "$oc_latest" ]; then
    oc_raw_model=$(echo "$oc_latest" | cut -d'|' -f1)
    oc_ms_stamp=$(echo "$oc_latest" | cut -d'|' -f2)
    oc_sec_stamp=$(( oc_ms_stamp / 1000 ))
    oc_model_id=$(echo "$oc_raw_model" | jq -r '.id // "opencode"' 2>/dev/null || echo "opencode")
    oc_prov_id=$(echo "$oc_raw_model" | jq -r '.providerID // "google"' 2>/dev/null || echo "google")
  else
    oc_sec_stamp=$(date +%s)
    oc_model_id="opencode"
    oc_prov_id="google"
  fi

  printf "%s\t%s\t0\t0\t%s\topencode\t%s\t%s\n" "$oc_today" "$oc_mtd" "$oc_sec_stamp" "$oc_model_id" "$oc_prov_id" > "$CACHE_DIR/usage-opencode.tsv.tmp"
  mv "$CACHE_DIR/usage-opencode.tsv.tmp" "$CACHE_DIR/usage-opencode.tsv"
  fed=1

  # Opencode's token score, the same day/week/month/all-time row Claude gets at
  # the bottom of this file — and it is one more query over a table already open,
  # because opencode banks the counters per session instead of leaving them in a
  # transcript. `date(now, -6 days, weekday 1)` is the Monday of the current week
  # including when today IS Monday, which the tempting `weekday 1, -7 days` gets
  # wrong by a week.
  #
  # Two caveats inherited from the cost query right above, kept rather than fixed
  # so the two rows can never disagree: sqlite's day boundaries are UTC, and the
  # sums are per-SESSION totals filed by when the session was last touched, so a
  # session spanning midnight lands whole on the later day.
  oc_tok_cols='tokens_input + tokens_output + tokens_reasoning + tokens_cache_read + tokens_cache_write'
  oc_tok_row=$(sqlite3 -separator "$(printf '\t')" "$OPENCODE_DB" "
    SELECT COALESCE(SUM(CASE WHEN time_updated >= strftime('%s', 'now', 'start of day') * 1000 THEN $oc_tok_cols END), 0),
           COALESCE(SUM(CASE WHEN time_updated >= strftime('%s', date('now', '-6 days', 'weekday 1')) * 1000 THEN $oc_tok_cols END), 0),
           COALESCE(SUM(CASE WHEN time_updated >= strftime('%s', 'now', 'start of month') * 1000 THEN $oc_tok_cols END), 0),
           COALESCE(SUM($oc_tok_cols), 0)
    FROM session;" 2>/dev/null || true)
  if [ -n "$oc_tok_row" ]; then
    printf '%s\t%s\n' "$oc_tok_row" "$(date +%s)" >"$CACHE_DIR/tokens-opencode.tsv.tmp" \
      && mv "$CACHE_DIR/tokens-opencode.tsv.tmp" "$CACHE_DIR/tokens-opencode.tsv"
  fi
fi

# --- Codex (ChatGPT) usage feed: ask the account, not the client ---------------
# Claude and Opencode both leave their usage on disk, so their feeds above are
# pure reads. Codex does not: the desktop app keeps threads server-side and
# writes NO rate-limit data anywhere local (not ~/.codex, not its Chromium
# profile, not the login keychain) — only the CLI and the VS Code extension ever
# wrote it, inside their rollout-*.jsonl. So a pill fed from disk shows real
# numbers only while you use the terminal client, and silently freezes the day
# you switch to the GUI. This asks OpenAI directly instead, which is also the
# only source that counts GUI usage: the limits are per ACCOUNT, so it doesn't
# matter which client burned them.
#
#   GET chatgpt.com/backend-api/wham/usage   (bearer = ~/.codex/auth.json)
# That path is deliberate: /backend-api/{me,codex/usage,codex/rate_limits} all
# answer a plain curl with a Cloudflare interstitial (HTTP 403 + HTML), and only
# wham/ is reachable without a browser. Being undocumented, it's treated as
# best-effort throughout — any unexpected shape leaves the last row alone.
CODEX_AUTH="$HOME/.codex/auth.json"
CODEX_TSV="$CACHE_DIR/usage-codex.tsv"
CODEX_TTL=${CODEX_TTL:-120}    # seconds; percentages move on a per-request cadence
CODEX_SKEW=${CODEX_SKEW:-900}  # refresh the token this long before it actually expires
CODEX_API=${CODEX_API:-https://chatgpt.com/backend-api/wham/usage}
CODEX_OAUTH=${CODEX_OAUTH:-https://auth.openai.com/oauth/token}

codex_fresh=0
if [ -f "$CODEX_TSV" ]; then
  age=$(( $(date +%s) - $(mtime "$CODEX_TSV") ))
  [ "$age" -lt "$CODEX_TTL" ] && codex_fresh=1
fi

# auth.json is the whole opt-in: no Codex login on this machine, no calls out.
if [ "$codex_fresh" = 0 ] && [ -f "$CODEX_AUTH" ] && command -v jq >/dev/null 2>&1; then
  now=$(date +%s)
  cx_at=$(jq -r '.tokens.access_token // empty' "$CODEX_AUTH" 2>/dev/null || true)
  cx_rt=$(jq -r '.tokens.refresh_token // empty' "$CODEX_AUTH" 2>/dev/null || true)
  cx_acc=$(jq -r '.tokens.account_id // empty' "$CODEX_AUTH" 2>/dev/null || true)

  jwt_claim() { # jwt_claim <jwt> <field> — read our OWN token's payload
    # No signature check on purpose: the only questions asked here are "when does
    # this expire" and "which OAuth client issued it", both of which we hand
    # straight back to the issuer. base64url → base64, and the padding must be
    # restored by hand — `base64 --decode` silently truncates the last bytes of
    # an unpadded string rather than failing, which would have made exp unreadable.
    local p=${1#*.}; p=${p%%.*}
    case $(( ${#p} % 4 )) in 2) p="$p==" ;; 3) p="$p=" ;; esac
    printf '%s' "$p" | tr '_-' '/+' | base64 --decode 2>/dev/null \
      | jq -r ".$2 // empty" 2>/dev/null || true
  }

  cx_exp=$(jwt_claim "$cx_at" exp)
  case "${cx_exp:-}" in '' | *[!0-9]*) cx_exp=0 ;; esac
  cx_client=$(jwt_claim "$cx_at" client_id)

  # ── token refresh ───────────────────────────────────────────────────────────
  # These access tokens live ~10 days and NOTHING on a GUI-only machine renews
  # them: the desktop app never touches auth.json (its mtime sits at the day you
  # logged in), and `codex login` needs a CLI that isn't installed. Left alone
  # the pill would work until the token lapsed and then grey out for good, so
  # the refresh happens here or not at all.
  #
  # The write-back is the delicate part: a successful exchange can rotate the
  # refresh token server-side, so losing the response means losing the login —
  # `codex login` again, from a terminal, to fix a bar pill. Hence tmp+rename
  # (never a truncating redirect onto the real file), a .bak of the last good
  # copy, 0600 set BEFORE the rename, and the old refresh token carried forward
  # whenever the response omits a new one. Any failure leaves auth.json byte
  # for byte as it was and simply skips this pass.
  if [ -n "$cx_rt" ] && [ -n "$cx_client" ] && [ "$cx_exp" -lt "$(( now + CODEX_SKEW ))" ]; then
    cx_body=$(jq -nc --arg rt "$cx_rt" --arg cid "$cx_client" \
      '{client_id:$cid,grant_type:"refresh_token",refresh_token:$rt,scope:"openid profile email"}')
    cx_resp=$(curl -fsS --max-time 15 -H 'content-type: application/json' \
      -d "$cx_body" "$CODEX_OAUTH" 2>/dev/null || true)
    cx_new=$(printf '%s' "$cx_resp" | jq -r '.access_token // empty' 2>/dev/null || true)
    if [ -n "$cx_new" ]; then
      cx_new_rt=$(printf '%s' "$cx_resp" | jq -r '.refresh_token // empty' 2>/dev/null || true)
      cx_new_id=$(printf '%s' "$cx_resp" | jq -r '.id_token // empty' 2>/dev/null || true)
      cp -p "$CODEX_AUTH" "$CODEX_AUTH.bak" 2>/dev/null || true
      if jq --arg at "$cx_new" --arg rt "${cx_new_rt:-$cx_rt}" --arg it "$cx_new_id" \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            '.tokens.access_token = $at
             | .tokens.refresh_token = $rt
             | (if $it == "" then . else .tokens.id_token = $it end)
             | .last_refresh = $ts' \
            "$CODEX_AUTH" >"$CODEX_AUTH.tmp" 2>/dev/null \
         && [ -s "$CODEX_AUTH.tmp" ] \
         && chmod 600 "$CODEX_AUTH.tmp" \
         && mv "$CODEX_AUTH.tmp" "$CODEX_AUTH"; then
        cx_at=$cx_new
      else
        # The token rotated but we couldn't persist it — .bak still holds the
        # login, so say so loudly rather than silently burning the refresh token
        # on every pass from here on.
        rm -f "$CODEX_AUTH.tmp"
        printf 'statusline-refresh: codex token refreshed but %s was not writable\n' \
          "$CODEX_AUTH" >&2
      fi
    fi
  fi

  cx_row=""
  if [ -n "$cx_at" ]; then
    cx_json=$(curl -fsS --max-time 10 \
      -H "authorization: Bearer $cx_at" \
      -H "chatgpt-account-id: $cx_acc" \
      "$CODEX_API" 2>/dev/null || true)
    # Windows are matched by DURATION, not by position: `primary` is the 5-hour
    # window on some plans and the weekly one on others (Plus returns only the
    # weekly, with secondary null), and the pill's two columns are session/weekly.
    cx_row=$(printf '%s' "$cx_json" | jq -r --argjson now "$now" '
      def pct: (.used_percent // 0) | floor;
      def at:  ((.reset_at // (if .reset_after_seconds then $now + .reset_after_seconds else 0 end)) | floor);
      [.rate_limit.primary_window, .rate_limit.secondary_window]
      | map(select(type == "object"))
      | ((map(select((.limit_window_seconds // 0) < 86400)) | first)  // null) as $s
      | ((map(select((.limit_window_seconds // 0) >= 86400)) | first) // null) as $w
      | [ (if $s then ($s | pct) else 0 end), (if $w then ($w | pct) else 0 end),
          (if $s then ($s | at)  else 0 end), (if $w then ($w | at)  else 0 end) ]
      | @tsv' 2>/dev/null || true)
  fi

  if [ -n "$cx_row" ]; then
    printf '%s\t%s\tcodex\n' "$cx_row" "$now" >"$CODEX_TSV.tmp"
    mv "$CODEX_TSV.tmp" "$CODEX_TSV"
    fed=1
  else
    # Offline, revoked, or the endpoint moved. Touch, don't write: the pill dates
    # its rows from the stamp INSIDE the file, so this backs the retry off a full
    # TTL while the bar keeps telling the truth ("as of Nm ago") about the age of
    # the numbers it's showing.
    [ -f "$CODEX_TSV" ] && touch "$CODEX_TSV"
  fi
fi

# --- repaint the bar now that a pulled feed moved ------------------------------
# Same push the render path does for Claude's own row (statusline.sh): run the
# reader directly rather than trusting an update_freq. It matters most for the
# FIRST row a machine ever writes — until one exists the pill is drawing=off, and
# a hidden sketchybar item's own timer never ticks, so nothing else would ever
# reveal it. `|| true` because a bar that isn't running is not an error here.
if [ "$fed" = 1 ]; then
  pill="$HOME/.config/sketchybar/plugins/ai_usage.sh"
  [ -x "$pill" ] && (SENDER=refresh NAME=ai_usage "$pill" >/dev/null 2>&1 &) || true
fi

# --- lifetime token counter: the aiUsage dropdown's "tokens" rows --------------
# A SCORE, not a limit. The percentages above tell you when to stop; this is the
# number no client shows anywhere — how many tokens you have ever actually moved.
# "Tokens" here is all four counters added up (input + output + cache write +
# cache read), so it is dominated by cache reads and is gleefully enormous. That
# is the point; it is a counter to watch tick, and it is deliberately NOT wired
# into the pill's own label, which stays the one number you can act on.
#
# Claude Code's transcripts are the only place the raw figures exist — one
# `usage` object per assistant record, nothing aggregated. Reading all of them
# end to end costs ~17s per ~800MB, which is fine once and absurd every quarter
# hour, so an INDEX carries the answer between passes: one row per transcript
# holding the size it had when we last read it. jsonl is append-only, so a file
# whose size is unchanged contributes its remembered total for free, and only the
# handful of transcripts that grew are re-read. Steady state is one batched stat
# over the tree plus a few MB of today's sessions.
#
# Re-reading a grown file WHOLE, rather than seeking to the old size and reading
# the tail, is deliberate: the saving is a fraction of a second (a day's active
# transcripts are tens of MB) and the offset version has to reason about a
# partial trailing line left by a write that raced the stat. Not worth it for a
# leaderboard.
#
# Runs LAST, after the pill has already been repainted, so the one cold pass a
# machine ever does cannot delay the numbers someone is actually watching.
#
# NOT a bill: nothing here dedups, and a resumed or forked session re-lists the
# messages it inherited, so a heavily forked day counts some of them twice. Fine
# for a score. Don't grow this into cost accounting.
#
# Four buckets, because one number never moves and one number is not a game:
# today, this week, this month, all time. They are computed independently, NOT
# nested — a week that started before the 1st puts tokens in `week` that are not
# in `month`, and pretending otherwise would quietly lose them.
#
#   tokens-claude.index:  path <TAB> size <TAB> all <TAB> day <TAB> d <TAB> w <TAB> m
#   tokens-claude.tsv:    d <TAB> w <TAB> m <TAB> all <TAB> written
# Both are read back with a strict field count, so a cache written by an older
# rice is discarded rather than misread one column over.
TOKENS_TTL=${TOKENS_TTL:-900}
PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
TOK_TSV="$CACHE_DIR/tokens-claude.tsv"
TOK_IDX="$CACHE_DIR/tokens-claude.index"

tok_fresh=0
if [ -f "$TOK_TSV" ]; then
  age=$(( $(date +%s) - $(mtime "$TOK_TSV") ))
  [ "$age" -lt "$TOKENS_TTL" ] && tok_fresh=1
fi

if [ "$tok_fresh" = 0 ] && [ -d "$PROJECTS_DIR" ]; then
  tok_now=$(date +%s)
  tok_day=$(date '+%Y-%m-%d')

  # The three bucket edges, each as a UTC ISO-8601 string, because that is the
  # form the timestamps in a transcript are in and ISO-8601 UTC sorts
  # lexicographically — so "was this message this week" becomes a string compare
  # in awk, with no date parsing and no gawk-only mktime. Midnight comes from
  # subtracting the wall clock off `now`, and the week and month edges from
  # subtracting whole days off THAT, because `date -v` is BSD and `date -d` is
  # GNU and the index has to be computed on both. `%u` (1=Monday) and `%d` are
  # POSIX, so the arithmetic is the portable part. Across a DST change the edge
  # lands an hour either side of midnight; a scoreboard can live with that.
  read -r tok_h tok_m tok_s tok_dow tok_dom <<<"$(date '+%H %M %S %u %d')"
  tok_midnight=$(( tok_now - (10#$tok_h * 3600 + 10#$tok_m * 60 + 10#$tok_s) ))
  tok_weekstart=$(( tok_midnight - (10#$tok_dow - 1) * 86400 ))
  tok_monthstart=$(( tok_midnight - (10#$tok_dom - 1) * 86400 ))

  at_utc() { # at_utc <epoch> <fmt> — BSD -r, else GNU -d. Unlike `stat -f` below,
    # the wrong flag genuinely FAILS here (GNU's -r wants a filename), so exit
    # status can pick the winner. The 9999 fallback is deliberate: an unreadable
    # clock should leave every bucket empty, not file all of history under today.
    date -u -r "$1" "$2" 2>/dev/null || date -u -d "@$1" "$2" 2>/dev/null || printf '9999'
  }
  at_local() { # at_local <epoch> <fmt> — the same, in the zone the day names use
    date -r "$1" "$2" 2>/dev/null || date -d "@$1" "$2" 2>/dev/null || printf '9999'
  }
  tok_cut_d=$(at_utc "$tok_midnight" '+%Y-%m-%dT%H:%M:%S')
  tok_cut_w=$(at_utc "$tok_weekstart" '+%Y-%m-%dT%H:%M:%S')
  tok_cut_m=$(at_utc "$tok_monthstart" '+%Y-%m-%dT%H:%M:%S')
  # The week edge as a LOCAL date too, because that is what an index row is
  # stamped with: it is how a carried bucket knows it is still in this week. Not
  # at_utc — east of Greenwich, local midnight is the previous day in UTC, and
  # the week would roll over a day early.
  tok_weekday=$(at_local "$tok_weekstart" '+%Y-%m-%d')
  case "$tok_weekday" in 9999) tok_weekday=$tok_day ;; esac
  tok_month=${tok_day%-*}

  # `stat -f` is BSD; on GNU that flag means --file-system and does NOT fail on
  # an unknown directive (same trap as mtime() above), so only a numeric answer
  # proves which one we are holding. The separator is a REAL tab, written $'\t':
  # GNU stat expands escapes in its format and BSD stat does not, so a literal
  # backslash-t reaches awk unsplit on exactly the platform this runs on.
  tok_flag=-f tok_fmt=$'%z\t%N'
  case "$(stat -f '%z' "$0" 2>/dev/null || true)" in
    '' | *[!0-9]*) tok_flag=-c tok_fmt=$'%s\t%n' ;;
  esac

  [ -f "$TOK_IDX" ] || : >"$TOK_IDX"
  find "$PROJECTS_DIR" -type f -name '*.jsonl' -print0 2>/dev/null \
    | xargs -0 stat "$tok_flag" "$tok_fmt" >"$TOK_IDX.sizes" 2>/dev/null || true

  # Join the last index against the sizes just measured, and split the tree in
  # two: files at the size we remember carry their totals straight through, the
  # rest are named for a re-read.
  #
  # A carried BUCKET only survives while the period it was banked in is still
  # running — day by exact date, week by "not before this week's Monday", month
  # by year-month. All three are checked independently, because a week that began
  # in the previous month is real and its tokens belong in `week` but not in
  # `month`. Get this wrong and a session that fell quiet before midnight goes on
  # scoring tomorrow morning.
  : >"$TOK_IDX.keep"
  : >"$TOK_IDX.scan"
  # Which file a record came from is decided by FILENAME, not the NR==FNR idiom:
  # on the first pass a machine ever runs the index is EMPTY, and with an empty
  # first file NR==FNR stays true straight through the second one — every size
  # row would be read as an index row and nothing would ever be scanned. NF is
  # checked for the same class of reason: an index left by an older rice has
  # fewer columns, and reading it anyway would file its numbers one bucket over.
  awk -F'\t' -v OFS='\t' -v IDX="$TOK_IDX" -v KEEP="$TOK_IDX.keep" -v SCAN="$TOK_IDX.scan" \
      -v DAY="$tok_day" -v WEEK="$tok_weekday" -v MONTH="$tok_month" '
    FILENAME == IDX {
      if (NF == 7) { size[$1] = $2; all[$1] = $3; day[$1] = $4; d[$1] = $5; w[$1] = $6; m[$1] = $7 }
      next
    }
    {
      p = $2
      if (p in size && size[p] == $1) {
        row = p OFS $1 OFS all[p] OFS DAY \
          OFS (day[p] == DAY ? d[p] : 0) \
          OFS (day[p] >= WEEK ? w[p] : 0) \
          OFS (substr(day[p], 1, 7) == MONTH ? m[p] : 0)
        print row > KEEP
      } else print p > SCAN
    }' "$TOK_IDX" "$TOK_IDX.sizes"

  # Everything that needs reading, read in ONE awk: sum the four counters per
  # line, then drop the line into whichever of the three periods its timestamp
  # reaches. Three independent compares, not a nested if — see above for why the
  # week is not always inside the month. Keyed by FILENAME so one pass totals the
  # whole batch. `xargs -0` so a path with a space in it survives the trip; the
  # FNR==1 seed is what stops a transcript with no usage records at all (an
  # aborted session) from being missing from the index and re-read forever.
  if [ -s "$TOK_IDX.scan" ]; then
    tr '\n' '\0' <"$TOK_IDX.scan" \
      | xargs -0 awk -v CUT_D="$tok_cut_d" -v CUT_W="$tok_cut_w" -v CUT_M="$tok_cut_m" '
      function num(key,   L) {
        L = length(key)
        if (match($0, "\"" key "\":[0-9]+")) return substr($0, RSTART + L + 3, RLENGTH - L - 3) + 0
        return 0
      }
      FNR == 1 { all[FILENAME] += 0 }
      /"output_tokens":/ {
        t = num("input_tokens") + num("output_tokens") \
          + num("cache_creation_input_tokens") + num("cache_read_input_tokens")
        all[FILENAME] += t
        if (!match($0, /"timestamp":"[0-9-]+T[0-9:.]+Z"/)) next
        ts = substr($0, RSTART + 13, RLENGTH - 14)
        if (ts >= "" CUT_D) d[FILENAME] += t
        if (ts >= "" CUT_W) w[FILENAME] += t
        if (ts >= "" CUT_M) m[FILENAME] += t
      }
      END {
        for (f in all) printf "%s\t%.0f\t%.0f\t%.0f\t%.0f\n", f, all[f], d[f] + 0, w[f] + 0, m[f] + 0
      }' >"$TOK_IDX.scanned" 2>/dev/null || true

    # Bank the size the plan MEASURED, not the file's size now: a session that
    # appended while we were reading it has to look changed on the next pass, or
    # the bytes we raced past are lost for good.
    awk -F'\t' -v OFS='\t' -v DAY="$tok_day" -v SIZES="$TOK_IDX.sizes" '
      FILENAME == SIZES { size[$2] = $1; next }
      { print $1, ($1 in size ? size[$1] : 0), $2, DAY, $3, $4, $5 }' \
      "$TOK_IDX.sizes" "$TOK_IDX.scanned" >>"$TOK_IDX.keep"
  fi

  mv "$TOK_IDX.keep" "$TOK_IDX"
  rm -f "$TOK_IDX.sizes" "$TOK_IDX.scan" "$TOK_IDX.scanned"

  # Re-summed from the index every pass rather than accumulated, so a deleted
  # transcript takes its tokens with it and no drift can ever build up.
  awk -F'\t' -v NOW="$tok_now" '
    { all += $3; d += $5; w += $6; m += $7 }
    END { printf "%.0f\t%.0f\t%.0f\t%.0f\t%s\n", d + 0, w + 0, m + 0, all + 0, NOW }' \
    "$TOK_IDX" >"$TOK_TSV.tmp" && mv "$TOK_TSV.tmp" "$TOK_TSV"
fi

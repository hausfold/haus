#!/usr/bin/env bash
# statusline-refresh.sh — the EXPENSIVE half of the nebelhaus statusline.
#
# Enumerates every in-flight agent worktree across ALL repos (via `wt`'s
# registry) and, per repo, asks GitHub once for PR state. Writes a raw-field TSV
# that statusline.sh renders with the SAME status-token logic as row 1. Run
# DETACHED by statusline.sh when its cache goes stale (stale-while-revalidate) —
# never in the render path, so the bar is never blocked by git/gh. Safe to run
# concurrently: a mkdir-lock elects one refresher; the rest exit immediately.
#
#   panel.tsv rows:  slug <TAB> name <TAB> ahead <TAB> files <TAB> ins <TAB> del <TAB> prstate <TAB> parent
#     slug    = owner/repo   (e.g. nebelhaus/pounce)
#     name    = worktree name (branch minus worktree- prefix)
#     ahead   = commits on the branch not in its default branch
#     files/ins/del = uncommitted working-tree delta (live checkouts only)
#     prstate = "#7 open" | "#7 merged" | "#7 closed" | "-"  ("-" = none; see below)
#     parent  = the cwd this worktree was spawned FROM (registry col 5). The
#               statusline shows a session only the rows whose parent == its cwd.
#   Only IN-FLIGHT rows are written (ahead>0, or dirty, or has a PR).
#
# It also writes lock-nag.tsv (see below): how far this machine's pinned rice is
# behind upstream, on its own much longer TTL. Same reason it lives here — it
# needs the network, and the network must never be in the render path.
set -euo pipefail
# APPENDED, never prepended — same call `wt` makes, for the same two reasons: this
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

# --- stale-rice nag: how far this machine's pinned nebelhaus is behind --------
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
nag_fresh=0
if [ -f "$NAG" ]; then
  age=$(( $(date +%s) - $(mtime "$NAG") ))
  [ "$age" -lt "$NAG_TTL" ] && nag_fresh=1
fi
if [ "$nag_fresh" = 0 ] && [ -f "$CONSUMER/flake.lock" ]; then
  lk() { jq -r ".nodes.nebelhaus.$1 // \"$2\"" "$CONSUMER/flake.lock" 2>/dev/null || echo "$2"; }
  lockrev=$(lk 'locked.rev' '')
  lockdate=$(lk 'locked.lastModified' 0)
  owner=$(lk 'original.owner' nebelhaus)
  repo=$(lk 'original.repo' nebelhaus)
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
        --json number,state,headRefName >"$cache.tmp" 2>/dev/null; then
    mv "$cache.tmp" "$cache"
  else
    rm -f "$cache.tmp"; [ -f "$cache" ] || echo '[]' >"$cache"
  fi
  cat "$cache"
}

pr_state_for_branch() { # $1=main $2=branch -> "#N open|merged|closed" or ""
  # `|| true`: a truncated cache (a gh run killed mid-write) makes jq exit 5, and
  # under `set -o pipefail` that status would propagate out of the `pr=$(…)`
  # substitution below and, with `set -e`, abort the whole pass. No PR state is a
  # blank cell; it is never a reason to stop refreshing the panel.
  pr_json_for_repo "$1" | jq -r --arg b "$2" '
    map(select(.headRefName == $b)) | (.[0] // empty)
    | "#\(.number) \(.state|ascii_downcase)"' 2>/dev/null || true
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
# bypassing `wt child` — never lands in the registry, so it would be invisible in
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
    # in. (Same trap `wt`'s git_main exists to close.)
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

: >"$PANEL.tmp"

worklist | awk -F'\t' '!seen[$4]++' | while IFS=$'\t' read -r name main branch wtpath parent; do
  panel_row "$name" "$main" "$branch" "$wtpath" "$parent" >>"$PANEL.tmp" || true
done

mv "$PANEL.tmp" "$PANEL"

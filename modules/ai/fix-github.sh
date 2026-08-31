#!/usr/bin/env bash
# `haus-fix-github` — the binary behind the GitHub pill's "Fix with AI" rows.
#
# ── what this is ────────────────────────────────────────────────────────────
# The github pill's dropdown draws a button under the rows it can hand off: a
# red default branch, and a PR whose checks came back red or that conflicts
# (modules/bar/sketchybar/plugins/github.sh, which passes this exactly what the
# row already knew). Clicking it spawns ONE agent lane on that repo, briefed
# with the failure — scruff's own spawn, the same machinery pounce's Spawn
# Agent drives, so the lane has a worktree, a branch, a zmx session and the
# trill fin every other lane gets. Nothing is fixed HERE; the button is a
# dispatch, and the lane's transcript is the work.
#
# ── the boundary ────────────────────────────────────────────────────────────
# Unlike haus-fix (the rebuild fixer), this never runs a client itself and
# never commits anything: scruff's open seam starts the client interactively
# with its own permission gate, in its own checkout. The lane is where the
# undo question lands — git, there, as usual.
#
# The lane is BACKGROUND (HAUS_LANE_BACKGROUND=1): this is spawned from a bar
# popup, and a click in a dropdown must not take the screen. The receipt is a
# banner; the doors to the lane afterwards are the trill fin and the agents
# pill, as for any lane.
#
# ── which repo ──────────────────────────────────────────────────────────────
# The bar only knows owner/repo and a URL, so the local checkout is found the
# only way it can be: the same walk Spawn Agent does. @repoRoots@ (baked in at
# build time from haus.ai.repoRoots — a bar plugin has no daemon environment to
# read it from) is scanned three levels for main checkouts, and the scruff
# registry's main-checkout column is added, so a repo you have ever agent'd
# resolves even from outside the configured roots. A candidate matches on its
# origin URL first (owner/repo is unambiguous) and its basename second (a
# fork's own checkout when there is no shared remote). No match is a banner,
# not a silent nothing.
#
# ── one spawn per failure ───────────────────────────────────────────────────
# A click runs this detached from sketchybar's click_script (a bar must never
# wait on a spawn), which means a double-click is two spawns — so there is a
# lock, age-swept like the pill's own fetch lock. One fix lane per repo at a
# time; a second click inside the window is a no-op.
#
# ── contract ────────────────────────────────────────────────────────────────
#   haus-fix-github <selector> <verdict> <url>
#
#   selector   WHAT is broken, verbatim from the row: the PR number for a
#              search row, the branch name for a ci row.
#   verdict    one of  ci | checks-red | conflicts  — which selector means.
#   url        the row's URL; owner/repo is parsed out of it.
#
# Every path ends on a banner (haus-notify, --source haus.github.fix — that
# string is what rules.json matches on to silence this button).
PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/$(id -un 2>/dev/null)/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export PATH

set -u

ROOTS=@repoRoots@
LOG="${XDG_CACHE_HOME:-$HOME/.cache}/haus/github-fix.log"
LOCK="${XDG_STATE_HOME:-$HOME/.local/state}/haus/github-fix"
LOCK_TTL=120
banner() { # banner <kind> <title> [body]
  haus-notify --title "$2" --body "${3:-}" --kind "$1" \
    --source haus.github.fix --symbol wrench.and.screwdriver >/dev/null 2>&1 || true
}

usage() {
  printf 'usage: haus-fix-github <selector> <verdict> <url>\n' >&2
  printf '       verdict: ci | checks-red | conflicts\n' >&2
  exit 64
}
[ "$#" -eq 3 ] || usage
selector="$1" verdict="$2" url="$3"
case "$verdict" in ci | checks-red | conflicts) ;; *) usage ;; esac

# ── owner/repo, out of the row's URL ────────────────────────────────────────
# Testable on its own (test/fix-github.bats lifts this by name): everything
# before the github.com host is dropped, and the first two path segments are
# the answer. Anything the GraphQL search hands over is https; the rest of the
# URL is ignored rather than validated, because the row drew from it already.
owner_repo_from_url() { # owner_repo_from_url <url> → "owner/repo" or ""
  case "$1" in
    https://github.com/*) ;;
    *) return 1 ;;
  esac
  local rest
  rest="${1#https://github.com/}"
  rest="${rest%%\?*}"
  rest="${rest%%#*}"
  rest="${rest%/}"
  case "$rest" in
    */*) printf '%s' "${rest%%/*}/${rest#*/}" | cut -d/ -f1-2 ;;
    *) return 1 ;;
  esac
}

# ── the brief ───────────────────────────────────────────────────────────────
# One paragraph per verdict. Deliberately short: the lane's client has the
# haus skill and can read `gh`'s own help; what it cannot recover from the
# transcript is what the person CLICKED on, which is exactly the four facts
# below. Named apart so a future verdict is a new arm, not an edit to a
# string an older test lifts.
build_prompt() { # build_prompt <verdict> <selector> <owner/repo> <url> → prompt on stdout
  case "$1" in
    ci)
      printf '%s' "CI is failing on $3's default branch \`$2\` ($4). Find the failing check runs with gh (gh run list / gh run view), diagnose and fix the failure, then land the fix on a branch and open a PR — do not push directly to \`$2\`. Trim any failing-flake noise you find along the way if it is genuinely the cause."
      ;;
    checks-red)
      printf '%s' "PR #$2 in $3 has failing CI ($4). Check it out (gh pr checkout $2), find the failing checks, diagnose and fix them, and push the fixes to the PR's branch."
      ;;
    conflicts)
      printf '%s' "PR #$2 in $3 has merge conflicts ($4). Check it out (gh pr checkout $2), rebase onto the default branch resolving the conflicts, re-run whatever the PR's CI runs if it is quick, and push. Report in the PR what you resolved if the resolutions were not mechanical."
      ;;
  esac
}

# ── the lane's name ─────────────────────────────────────────────────────────
# Deterministic, from the four facts rather than from a model: `fix-<repo>-pr<n>`
# and `fix-<repo>-<branch>`. The namer that names pounce's spawn from a typed
# prompt has nothing typed here to name, and scruff's built-in costs 8-12s
# before the lane exists. A name given to `scruff spawn` always wins, so this
# is also "never ask".
lane_name() { # lane_name <verdict> <selector> <owner/repo> → name
  local repo="${3##*/}" tail
  tail="$2"
  case "$1" in
    checks-red | conflicts) tail="pr$2" ;;
  esac
  # Branch names carry slashes (`haus/bar-fix`); a lane name may not.
  tail="$(printf '%s' "$tail" | tr '/' '-' | tr -c 'a-zA-Z0-9-' '-' | sed 's/--*/-/g; s/^-//; s/-$//')"
  [ -n "$tail" ] || tail="ci"
  printf 'fix-%s-%s' "${repo:-repo}" "$tail" | cut -c1-48 | sed 's/-$//'
}

# ── resolve the local checkout ──────────────────────────────────────────────
# The same walk spawn-agent.sh does (modules/launcher/commands/spawn-agent.sh):
# ~-expanded roots, a root that IS a repo never descended into, depth 3, only
# .git DIRECTORIES are main checkouts. Registry column 2 is each worktree's
# main checkout, so ever-agent'd repos resolve from anywhere on disk.
resolve_repo() { # resolve_repo <owner/repo> → checkout path on stdout, or exit 1
  local orp="$1" repo="${1##*/}" owner="${1%%/*}" cand
  local candidates hits
  candidates="$(mktemp)" || return 1
  hits="$(mktemp)" || { rm -f "$candidates"; return 1; }

  # ROOTS arrives colon-joined (@repoRoots@, one escapeShellArg) — the same
  # shape the pounce daemon's HAUS_REPO_ROOTS has, so the split is spawn-
  # agent.sh's, not a parse of our own. A root that is ITSELF a repo is
  # offered as itself and never descended into; depth 3 because a root's
  # repos sit at depth 2 and a parent dir full of repos puts children at 3.
  local roots=()
  IFS=':' read -r -a roots <<< "$ROOTS"
  local root
  # The for-not-while guard is bash 3.2 under `set -u`: on a host that set
  # repoRoots = [] the array is empty and bare "${roots[@]}" is an unbound
  # variable rather than zero iterations.
  if [ "${#roots[@]}" -gt 0 ]; then
    for root in "${roots[@]}"; do
      [ -n "$root" ] || continue
      # The '~/'* branch's substitution PATTERN is the tilde, not a quoted-tilde
      # expansion — shellcheck's SC2088 doesn't see it; spawn-agent.sh carries
      # the same line with the same warning.
      # shellcheck disable=SC2088
      case "$root" in
        '~') root="$HOME" ;;
        '~/'*) root="$HOME/${root#\~/}" ;;
      esac
      [ -d "$root" ] || continue
      if [ -d "$root/.git" ]; then
        printf '%s\n' "${root%/}" >>"$candidates"
        continue
      fi
      find "$root" -mindepth 1 -maxdepth 3 -type d -name .git -prune 2>/dev/null |
        sed 's|/\.git$||' >>"$candidates"
    done
  fi

  # Repos scruff already knows: field 2 of the registry is each worktree's
  # main checkout, so ever-agent'd repos resolve even from outside the roots.
  # The three-way probe is spawn-agent.sh's — the scruff-named base while it
  # holds the registry, the legacy path while THAT holds it, else nothing.
  local reg=""
  if [ -f "$HOME/.cache/scruff/registry.tsv" ]; then
    reg="$HOME/.cache/scruff/registry.tsv"
  elif [ -f "$HOME/.cache/claude-worktrees/registry.tsv" ]; then
    reg="$HOME/.cache/claude-worktrees/registry.tsv"
  fi
  [ -n "$reg" ] && cut -f2 "$reg" 2>/dev/null >>"$candidates"

  # Remote match first, basename second; ties go to whichever sorted first.
  # Tagged R/B so the sort IS the precedence rather than a second pass over a
  # second list. The remote grep carries both remote spellings: HTTPS names
  # owner/repo after a slash, SSH (git@github.com:owner/repo.git) after a
  # colon — an SSH-only checkout must resolve the same way an HTTPS one does.
  sort -u "$candidates" | while IFS= read -r cand; do
    [ -n "$cand" ] && [ -d "$cand/.git" ] || continue
    [ "$(basename "$cand")" = "$repo" ] || continue
    # origin URL wins when it names the same owner/repo (a fork's checkout
    # with a shared upstream, or two same-named repos from different hosts).
    if git -C "$cand" remote get-url origin >/dev/null 2>&1 &&
      git -C "$cand" remote get-url origin 2>/dev/null |
      grep -qE "[/:]$owner/$repo(\.git)?/?$"; then
      printf 'R\t%s\n' "$cand"
    else
      printf 'B\t%s\n' "$cand"
    fi
  done >>"$hits"
  rm -f "$candidates"

  local hit
  hit="$(sed -n 's/^R\t//p' "$hits" | head -n1)"
  [ -n "$hit" ] || hit="$(sed -n 's/^B\t//p' "$hits" | head -n1)"
  rm -f "$hits"
  if [ -n "$hit" ] && [ -d "$hit/.git" ]; then
    printf '%s' "$hit"
    return 0
  fi
  return 1
}

# ── the spawn, detached ─────────────────────────────────────────────────────
# `scruff spawn` itself is what takes seconds (checkout, branch, registry row,
# then the open seam boots a client); the click must not wait for any of it.
# The lock is taken HERE, in the detached child, after resolution — so a
# double-click costs at most one resolve walk, never two lanes.
do_spawn() { # do_spawn <checkout> <prompt> <name>
  local repo="$1" prompt="$2" name="$3"
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || LOG=/dev/null

  agent="$(scruff agent default 2>/dev/null)"
  [ -n "$agent" ] || agent="claude"

  # Per-lane lock, not global: a fix click on repo B must not be swallowed
  # because repo A's lane spawned a minute ago.
  local lock="$LOCK/$name"
  mkdir -p "$LOCK" 2>/dev/null
  if ! mkdir "$lock" 2>/dev/null; then
    local age
    age=$(( $(date +%s) - $(stat -f %m "$lock" 2>/dev/null || echo 0) ))
    if [ "$age" -lt "$LOCK_TTL" ]; then
      banner pulse "Fix lane already running" "$name is already on it"
      exit 0
    fi
    rmdir "$lock" 2>/dev/null
    mkdir "$lock" 2>/dev/null || exit 0
  fi

  local argv=(spawn "$repo" "$name" --agent "$agent" --prompt-file -)

  dir="$(printf '%s' "$prompt" | HAUS_LANE_BACKGROUND=1 scruff "${argv[@]}" 2>>"$LOG")"
  rc=$?
  rmdir "$lock" 2>/dev/null

  if [ "$rc" -ne 0 ] || [ -z "$dir" ] || [ ! -d "$dir" ]; then
    banner fault "Could not spawn the fix lane" "Why, in $LOG"
    exit 1
  fi
  banner pulse "haus · fix lane" "$name is working on ${repo##*/}"
}

# ── dispatch ────────────────────────────────────────────────────────────────
orp="$(owner_repo_from_url "$url")" || {
  banner fault "Fix with AI" "Not a github.com URL: $url"
  exit 2
}
prompt="$(build_prompt "$verdict" "$selector" "$orp" "$url")"
name="$(lane_name "$verdict" "$selector" "$orp")"

checkout="$(resolve_repo "$orp")" || {
  banner pulse "No local checkout of $orp" "Clone it, or add its parent to haus.ai.repoRoots"
  exit 2
}

do_spawn "$checkout" "$prompt" "$name" &
exit 0

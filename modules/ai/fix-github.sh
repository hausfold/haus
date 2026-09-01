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
# The walk starts from the BASENAME, which is the known gap: a repo cloned as
# `haus-fork` is not found even with the right origin, and the answer is the
# same banner as no checkout at all. That is the safe direction — the
# alternative is running `git remote` on every directory under every root on
# the click path — and the banner names the option (clone it where it belongs,
# or add its parent to `haus.ai.repoRoots`).
#
# ── which client ────────────────────────────────────────────────────────────
# `scruff agent default`, then the first of claude/codex/opencode/pi that is
# actually on PATH. The Nix side gates this binary on the default client being
# installed, but that is a BUILD-time fact and scruff's default is read from a
# file a person edits, so the two can disagree — and this spawn is a background
# one, where "codex: command not found" lands in a pane nobody is watching.
#
# ── one spawn per failure, and no waiting ───────────────────────────────────
# SketchyBar runs a popup row's click_script and only THEN closes the popup —
# barlib puts the two in one string — so every millisecond this process spends
# in the foreground is a dropdown left open under a finger that has moved on.
# Argv validation is all that happens before the fork; the resolve walk and the
# spawn are both behind it.
#
# Which makes a double-click two spawns, so there is a lock, age-swept like the
# pill's own fetch lock. It is keyed on the LANE NAME and taken before the
# resolve, because the name comes from argv alone and the resolve is the
# expensive half. One fix lane per failure at a time; a second click inside the
# window is a banner, not a second lane.
#
# ── contract ────────────────────────────────────────────────────────────────
#   haus-fix-github <selector> <verdict> <url>
#
#   selector   WHAT is broken, verbatim from the row: the PR number for a
#              search row, the branch name for a ci row.
#   verdict    one of  ci | checks-red | conflicts  — which selector means.
#   url        the row's URL; owner/repo is parsed out of it.
#
# Every path a PERSON can reach ends on a banner (haus-notify, --source
# haus.github.fix — that string is what rules.json matches on to silence this
# button). Bad argv is the exception and stays `usage` on stderr with exit 64:
# the only way to reach it is a bug in the caller, and the caller is the bar.
PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/$(id -un 2>/dev/null)/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export PATH

set -u

ROOTS=@repoRoots@
# Both under ~/.local/state/haus, beside haus-fix's own fix.log: this is a
# transcript of something that happened to the machine, not a cache anything
# can rebuild, and `haus doctor`'s reader should only ever have one directory
# to look in. NOT in modules/lib/state-files.nix — that registry is for state
# ONE room writes and ANOTHER reads, and both of these are this script's alone.
LOG="${XDG_STATE_HOME:-$HOME/.local/state}/haus/github-fix.log"
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
  local rest owner repo
  rest="${1#https://github.com/}"
  rest="${rest%%\?*}"
  rest="${rest%%#*}"
  rest="${rest%/}"
  # Both segments have to be non-empty: `github.com//haus` and `github.com/x/`
  # are each a half-answer that would otherwise reach the brief as an owner or
  # a repo named "", and the lane would be briefed on a repo nobody has.
  case "$rest" in
    ?*/?*) ;;
    *) return 1 ;;
  esac
  owner="${rest%%/*}"
  rest="${rest#*/}"
  repo="${rest%%/*}"
  [ -n "$owner" ] && [ -n "$repo" ] || return 1
  printf '%s/%s' "$owner" "$repo"
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

# ── which client ────────────────────────────────────────────────────────────
# `scruff agent default` names a client; it does not promise one is installed.
# The Nix side gates this binary on `lib.elem cfg.default clients`, but that is
# a BUILD-time fact about what the room installs and scruff's default is read
# from ~/.config/scruff/config.toml, which a person edits — so the two can name
# different clients on a machine that only ever installed one. Falling to the
# first client that is actually here is spawn-agent.sh's answer to the same
# question ("Belt to the assertion's braces"), and it is the difference between
# a working lane and a lane whose pane says "codex: command not found" with
# nobody watching it, because this spawn is a BACKGROUND one.
#
# The four ids are scruff's own (`internal/registry`'s validAgent) — `scruff
# spawn --agent` refuses anything else — so a fifth client is a scruff change
# first and a line here second.
resolve_agent() { # resolve_agent → a client id on stdout, or exit 1
  local want client
  want="$(scruff agent default 2>/dev/null)"
  for client in "$want" claude codex opencode pi; do
    [ -n "$client" ] || continue
    command -v "$client" >/dev/null 2>&1 || continue
    printf '%s' "$client"
    return 0
  done
  return 1
}

# ── the spawn ───────────────────────────────────────────────────────────────
# `scruff spawn` takes seconds (checkout, branch, registry row, then the open
# seam boots a client). The whole of `run` is already detached from the click
# by the dispatch below; this is just the part that creates something.
do_spawn() { # do_spawn <checkout> <prompt> <name>
  local repo="$1" prompt="$2" name="$3" agent dir rc

  agent="$(resolve_agent)" || {
    banner fault "No coding agent to hand this to" "Nothing in haus.ai.clients is on PATH"
    return 1
  }

  # scruff prints the lane's path on stdout BEFORE it drives the open seam, so
  # this captures it whether the seam got as far as a session or not — which is
  # exactly what the cleanup below needs.
  dir="$(printf '%s' "$prompt" |
    HAUS_LANE_BACKGROUND=1 scruff spawn "$repo" "$name" --agent "$agent" --prompt-file - 2>>"$LOG")"
  rc=$?

  if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    banner fault "Could not spawn the fix lane" "Why, in $LOG"
    return 1
  fi

  # rc 0 is a lane that started; anything else is a lane that EXISTS with
  # nothing on it — the worktree, the branch and the registry row are all
  # there, and the seam refused. spawn-agent.sh's answer, for the same reason:
  # `scruff drop` rather than `git worktree remove`, because the raw remove
  # leaves the registry row behind and the lane goes on being listed by
  # `scruff`, `bench status` and the agents pill as a checkout that isn't
  # there. Nobody is watching this spawn, so litter here is litter forever.
  if [ "$rc" -ne 0 ]; then
    if scruff drop "$(basename "$dir")" >>"$LOG" 2>&1; then
      banner fault "Could not open the fix lane" "The lane was dropped; nothing changed"
    else
      banner fault "Could not open the fix lane" "Lane '$name' is still here — run scruff"
    fi
    return 1
  fi

  banner pulse "haus · fix lane" "$name is working on ${repo##*/}"
}

# ── the work, behind the lock ───────────────────────────────────────────────
# Everything past argv validation. The LOCK is taken before the resolve walk,
# not after it: the walk is a `find` over every configured root plus a `git
# remote` per candidate, so locking after it means a double-click pays for it
# twice. The name is computable from argv alone, which is what makes that
# possible — it depends on the verdict, the selector and the URL, none of which
# touch the disk.
#
# ⚠️ Released EXPLICITLY, in the one place that took it — never from an EXIT
# trap. Two reasons, and the first is measured: bash 3.2 does not run an EXIT
# trap set inside a function when that function is the body of a BACKGROUND
# job, which is precisely the shape below. `writeShellScriptBin` gives this
# bash 5, where it does fire, so a trap here is a release that works in
# production and silently doesn't when a person runs the file under /bin/bash
# to see what it does — the worst of the two directions. The second: a trap
# body is expanded when it FIRES, by which time `run` has returned and every
# `local` in it is out of scope, so the obvious `trap 'rmdir "$lock"' EXIT`
# is an `rmdir ""` under a redirect that hides it.
run() { # run <verdict> <selector> <url> <owner/repo> <name>
  local verdict="$1" selector="$2" url="$3" orp="$4" name="$5" lock age rc

  # Per-lane, not global: a fix click on repo B must not be swallowed because
  # repo A's lane spawned a minute ago. Age-swept like the pill's own fetch
  # lock, so a killed spawn cannot wedge the button forever.
  lock="$LOCK/$name"
  mkdir -p "$LOCK" 2>/dev/null
  if ! mkdir "$lock" 2>/dev/null; then
    age=$(($(date +%s) - $(stat -f %m "$lock" 2>/dev/null || echo 0)))
    if [ "$age" -lt "$LOCK_TTL" ]; then
      banner pulse "Fix lane already running" "$name is already on it"
      return 0
    fi
    rmdir "$lock" 2>/dev/null
    mkdir "$lock" 2>/dev/null || return 0
  fi

  # Everything that can fail is in `work`, so this is the only release and it
  # cannot be skipped by a `return` someone adds later — including the resolve
  # that finds nothing, which held the lock for its full TTL in the first draft
  # and so made "fix a repo you haven't cloned" a button that then ignored you
  # for two minutes after you cloned it.
  work "$verdict" "$selector" "$url" "$orp" "$name"
  rc=$?
  rmdir "$lock" 2>/dev/null
  return "$rc"
}

work() { # work <verdict> <selector> <url> <owner/repo> <name> — inside the lock
  local verdict="$1" selector="$2" url="$3" orp="$4" name="$5" checkout prompt
  checkout="$(resolve_repo "$orp")" || {
    banner pulse "No local checkout of $orp" "Clone it, or add its parent to haus.ai.repoRoots"
    return 2
  }
  prompt="$(build_prompt "$verdict" "$selector" "$orp" "$url")"
  do_spawn "$checkout" "$prompt" "$name"
}

# ── dispatch ────────────────────────────────────────────────────────────────
# The click path ends HERE, in milliseconds. barlib appends the popup's own
# `--set <pill> popup.drawing=off` AFTER this command in one click_script
# (modules/bar/sketchybar/barlib.sh's `_barlib_pop_add`), so anything this
# process still has to do is time the dropdown stays on screen under a finger
# that has already moved on. The first draft resolved the checkout before
# forking — a `find -maxdepth 3` over every root — and paid for it in exactly
# that visible place.
#
# Only the two failures that are about THE ARGUMENTS stay in front of the fork,
# because both are bugs in the caller rather than news for the person: a bad
# verdict is `usage` on stderr, and a URL that is not github.com's is a banner.
orp="$(owner_repo_from_url "$url")" || {
  banner fault "Fix with AI" "Not a github.com URL: $url"
  exit 2
}
name="$(lane_name "$verdict" "$selector" "$orp")"

# The log is append-only across spawns (two repos can be spawning at once, so
# fix.sh's rotate-on-entry would have them clobbering each other), which makes
# it the one file here that grows without a ceiling. Rolled at 256 KiB rather
# than truncated, so the failure you are reading about survives the roll.
mkdir -p "$(dirname "$LOG")" 2>/dev/null || LOG=/dev/null
if [ "$(stat -f %z "$LOG" 2>/dev/null || echo 0)" -gt 262144 ]; then
  mv -f "$LOG" "$LOG.prev" 2>/dev/null || true
fi

run "$verdict" "$selector" "$url" "$orp" "$name" >/dev/null 2>&1 &
exit 0

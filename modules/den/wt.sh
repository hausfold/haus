#!/usr/bin/env bash
# wt — manage coding-agent worktrees, for ANY git repo.
#
# `claude --worktree` (the Super-c / ⌘C zellij bind) fires Claude Code's
# WorktreeCreate/WorktreeRemove hooks; this script is what they call. It keeps
# agent checkouts under ~/.cache/claude-worktrees/<repo>/<name> (out of the repo
# so trees stay clean) on branch worktree-<name>, and — crucially — makes
# closing a pane safe and reversible:
#
#   wt                list every parked/live agent worktree, across ALL repos
#                     (self-heals first: reaps parked branches whose PR has merged).
#                     The state column is git's answer, not the disk's:
#                       live   — git resolves the checkout; a pane may be in it
#                       parked — no checkout on disk; the branch IS the work
#                       stray  — a directory is there but git has disowned it (a
#                                `worktree remove` that died between unregistering
#                                and deleting). `wt <name>` heals one.
#   wt <name>         resume one: rebuild its checkout + reopen its agent chat
#   wt resume <name>  (the same thing, spelled out)
#   wt reap           sweep every LANDED worktree NOW — parked ones, plus clean &
#                     merged live checkouts that NO pane is sitting in (dirty,
#                     unmerged, or occupied-by-any-open-pane ones are kept).
#                     The idempotent backstop for when a pane ends WITHOUT firing
#                     the remove hook (a manual pane close, a reboot, a crash) or
#                     for `wt child` checkouts, which the hook never reaps.
#   wt child <repo>   make a worktree of ANOTHER repo as a child of THIS pane —
#                     for cross-repo work (a workshop pane editing a sub-repo).
#                     Registers it so its PR shows in the statusline; prints the
#                     new checkout path, so: cd "$(wt child ~/code/…/rice)"
#   wt spawn <repo> <name>
#                     make a NAMED worktree for a spawner with no pane of its own
#                     (the pounce "Spawn Agent" command). Same registration as
#                     `child`, but parented to the repo itself, and a taken name
#                     takes the next free suffix rather than dying.
#   wt park [label]   set the working tree aside NOW, as a wip: commit on this
#                     branch — the on-demand form of what the remove hook does.
#                     Use this instead of `git stash`: the stash stack is SHARED
#                     by every worktree of a repo, so parallel agents pop each
#                     other's entries; a wip commit lives on YOUR branch alone.
#   wt unpark         undo the last wip: commit, putting those changes back in
#                     the working tree, uncommitted (the `git stash pop` half).
#   wt create         [hook] make a worktree for the current repo (JSON on stdin)
#   wt remove         [hook] retire one WITHOUT losing work (JSON on stdin)
#
# This is deliberately self-contained: pure git + filesystem, no knowledge of
# any particular repo, flake, or the nebelhaus workshop's `bench`. It works for
# whatever repo you happen to be in. State lives in the registry (see below).
set -euo pipefail

# Hooks run with a bare PATH; make sure git resolves (and claude, for resume).
# APPENDED, never prepended: this is a rescue for the bare-PATH hook case, not an
# override of the caller's environment. Prepending it made the script untestable —
# test/wt.bats drives it with shim `gh`/`lsof` on PATH, and the real ones under
# /run/current-system/sw/bin won every time.
_wt_rescue="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/$(id -un 2>/dev/null)/bin:/usr/bin:/bin"
# Guard the ':' — an empty inherited PATH would otherwise yield a leading one, which
# means "the current directory" and would let a repo drop a fake `git` in our lap.
PATH="${PATH:+$PATH:}$_wt_rescue"

WT_BASE="${CLAUDE_WT_BASE:-$HOME/.cache/claude-worktrees}"
# The registry is `wt`'s source of truth for parked worktrees: one tab-separated
# line per worktree — "name<TAB>main-checkout<TAB>branch<TAB>checkout-path" —
# written at create time. It lets `wt` rebuild a parked worktree and find its
# main checkout across ANY repo, even after the checkout dir is gone. Merged-away
# worktrees are pruned; unmerged ones linger exactly as long as their branch.
WT_REGISTRY="$WT_BASE/registry.tsv"

# The one client-specific seam in wt.  Every worktree records one of these ids
# in registry field 6, so changing the default later never makes a parked Codex
# branch reopen in Claude (or vice versa).  Clients intentionally own their
# transcript stores: only Claude exposes a cheap cwd → transcript-directory
# test; Codex and OpenCode reopen their cwd-filtered session pickers instead.
agent_known() { case "$1" in claude | codex | opencode) return 0 ;; *) return 1 ;; esac; }
agent_default() {
  local a="${NEBELHAUS_AGENT_DEFAULT:-claude}"
  agent_known "$a" || a="claude"
  printf '%s' "$a"
}
agent_for_worktree() { # agent_for_worktree <wt-path> — old registry rows mean Claude
  local a="" found=""
  if [ -f "$WT_REGISTRY" ]; then
    found="$(awk -F'\t' -v p="$1" '$4==p{print 1; exit}' "$WT_REGISTRY" 2>/dev/null)"
    a="$(awk -F'\t' -v p="$1" '$4==p{print $6; exit}' "$WT_REGISTRY" 2>/dev/null)"
  fi
  agent_known "$a" || { [ -n "$found" ] && a="claude" || a="$(agent_default)"; }
  printf '%s' "$a"
}
agent_has_chat() { # agent_has_chat <agent> <cwd> — only answer yes when knowable
  case "$1" in
    claude) [ -d "$(wt_projdir "$2")" ] ;;
    *) return 1 ;;
  esac
}
agent_start() { # agent_start <agent> [--image <png>] -- <prompt>; execs the client
  local a="${1:-}" image="" prompt=""
  shift || true
  case "${1:-}" in --image) image="${2:-}"; shift 2 ;; esac
  [ "${1:-}" = "--" ] && shift
  prompt="${1:-}"
  agent_known "$a" || die "unknown agent '$a' (expected claude, codex, or opencode)"
  command -v "$a" >/dev/null 2>&1 || die "$a is unavailable — install it, then try again"
  # Codex has a documented local-image flag.  The other interactive clients do
  # not, so name the durable captured file in their first turn instead of
  # pretending an unsupported flag attached it.
  if [ -n "$image" ] && [ -f "$image" ] && [ "$a" != codex ]; then
    prompt="$prompt

A screenshot for this task is at $image. Inspect it before drawing conclusions."
  fi
  case "$a" in
    claude) exec claude "$prompt" ;;
    codex)  if [ -n "$image" ] && [ -f "$image" ]; then exec codex -i "$image" "$prompt"; else exec codex "$prompt"; fi ;;
    opencode) exec opencode --prompt "$prompt" ;;
  esac
}
agent_resume() { # agent_resume <agent>; execs that client's cwd-filtered resume UI
  local a="${1:-}"
  agent_known "$a" || die "unknown agent '$a' (expected claude, codex, or opencode)"
  command -v "$a" >/dev/null 2>&1 || die "$a is unavailable — install it, then try again"
  case "$a" in
    claude) exec claude --resume ;;
    codex) exec codex resume ;;
    opencode) exec opencode --continue ;;
  esac
}

say() { printf '\033[38;5;103m🌫  %s\033[0m\n' "$*" >&2; }
die() { printf '\033[38;5;167m✗  %s\033[0m\n' "$*" >&2; exit 1; }

fit() { # fit <string> <maxlen> — trim to width, appending … when it overflowed
  local s="$1" n="$2"
  [ "$n" -lt 1 ] && n=1
  if [ "${#s}" -gt "$n" ]; then printf '%s…' "${s:0:n-1}"; else printf '%s' "$s"; fi
}

reg_lock() { # serialize the registry's read-modify-write across parallel panes
  # Every mutator below is read-whole-file → rewrite → mv. The mv is atomic, but
  # the read-then-write is not: two panes spawning a worktree in the same instant
  # both read the OLD file and the second one's mv drops the first one's row. The
  # worktree still exists and still works — it just goes invisible to `wt` and to
  # the statusline, which is precisely the "orphan worktree" we kept finding.
  # mkdir is the atomic primitive available everywhere; `flock` is not on macOS.
  local lock="$WT_REGISTRY.lock" i=0
  mkdir -p "$WT_BASE"
  while ! mkdir "$lock" 2>/dev/null; do
    # Nothing here holds the lock for more than a few milliseconds (no network,
    # no git), so 5s means the holder was killed mid-write — a pane close or a
    # reboot. Break it rather than wedge every future `wt` invocation forever.
    [ "$i" -ge 50 ] && { rm -rf "$lock"; continue; }
    i=$((i + 1)); sleep 0.1
  done
  # set -e means an unexpected failure mid-rewrite would skip reg_unlock; release
  # on exit too, so a crash costs at most this one invocation.
  trap 'rm -rf "$WT_REGISTRY.lock"' EXIT
}
reg_unlock() { rm -rf "$WT_REGISTRY.lock"; trap - EXIT; }

reg_put() { # reg_put <name> <main> <branch> <wt_path> [parent] [agent] — upsert, keyed on wt_path
  # The optional 5th field is the cwd the worktree was spawned FROM (its parent
  # pane) — recorded at create so the statusline can show a session only the
  # worktrees IT spawned. When omitted (e.g. resume, which doesn't know the
  # original spawner), the existing parent is preserved, never blanked.
  reg_lock
  local parent="${5:-}" agent="${6:-}"
  local tmp="$WT_REGISTRY.$$"
  if [ -f "$WT_REGISTRY" ]; then
    [ -z "$parent" ] && parent="$(awk -F'\t' -v p="$4" '$4==p{print $5; exit}' "$WT_REGISTRY")"
    [ -z "$agent" ] && agent="$(awk -F'\t' -v p="$4" '$4==p{print $6; exit}' "$WT_REGISTRY")"
    awk -F'\t' -v p="$4" '$4 != p' "$WT_REGISTRY" >"$tmp"
  else
    : >"$tmp"
  fi
  agent_known "$agent" || agent="$(agent_default)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$parent" "$agent" >>"$tmp"
  mv "$tmp" "$WT_REGISTRY"
  reg_unlock
}

reg_del() { # reg_del <wt_path> — drop the line for a worktree we've reaped
  [ -f "$WT_REGISTRY" ] || return 0
  reg_lock
  local tmp="$WT_REGISTRY.$$"
  awk -F'\t' -v p="$1" '$4 != p' "$WT_REGISTRY" >"$tmp"
  mv "$tmp" "$WT_REGISTRY"
  reg_unlock
}

reg_prune() { # drop every row that can no longer resume anything, and its empty bucket dir
  # reg_del only fires when WE reap a branch. A branch that vanishes any other way
  # — merged and deleted on GitHub, `git branch -D` by hand, a main checkout moved
  # or removed — leaves its row behind forever, and the rows outlive the repos:
  # 54 of 56 rows here were dead. Harmless, but they're the fuel every path-resolution
  # bug feeds on, so the sweep that already self-heals branches heals the registry too.
  [ -f "$WT_REGISTRY" ] || return 0
  reg_lock
  local tmp="$WT_REGISTRY.$$" name main branch wt parent agent
  while IFS=$'\t' read -r name main branch wt parent agent; do
    [ -n "$branch" ] || continue
    git -C "$main" show-ref -q --verify "refs/heads/$branch" 2>/dev/null || continue
    agent_known "$agent" || agent="claude" # backwards-compatible old registry rows
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$main" "$branch" "$wt" "$parent" "$agent"
  done <"$WT_REGISTRY" >"$tmp"
  mv "$tmp" "$WT_REGISTRY"
  reg_unlock
  rmdir "$WT_BASE"/*/ 2>/dev/null || true # per-repo buckets left empty by the last reap
}

git_main() { # git_main <dir> — the MAIN checkout backing any worktree of a repo
  # Fail (empty, non-zero) when <dir> is gone or isn't a repo. Without this the
  # rev-parse fails, `dirname ""` yields ".", and every caller then resolves that
  # against ITS OWN cwd — so a stale registry row pointing at a deleted checkout
  # made `wt` list the current repo's branches a second time under a repo literally
  # named ".", as bogus "parked" rows. Callers already handle a non-zero return.
  local common
  common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [ -n "$common" ] || return 1
  dirname "$common"
}

checkout_state() { # checkout_state <wt_path> — live | stray | parked
  # The liveness test USED to be `[ -e "$wt/.git" ]`, and that is not the same
  # question. `git worktree remove` deletes the repo's admin dir
  # (.git/worktrees/<id>) BEFORE it deletes the working tree, so a removal that
  # fails part-way — an ignored node_modules it cannot unlink, a file another
  # process holds — leaves a directory whose .git file references a gitdir that
  # is gone. `-e` calls that live; every git command run inside it exits 128 with
  # "fatal: not a git repository: (null)".
  #
  # Consequences of believing `-e`, all seen on this machine: `wt` listed the
  # husk as `live` forever; `wt <name>` said "still live at …" and refused to
  # rebuild it, so the branch was unreachable; the sweep treated it as an
  # occupied checkout and never swept it; and the statusline refresher — which
  # runs under `set -e` — died on it, freezing the whole bar at hours-old data.
  #
  #   live   — git resolves it: a real checkout, possibly with a pane in it
  #   stray  — a .git is there but git disowns it: a husk, contents preserved
  #   parked — nothing on disk; the branch is the work, `wt <name>` rebuilds it
  [ -e "$1/.git" ] || { echo parked; return; }
  if git -C "$1" --no-optional-locks rev-parse --git-dir >/dev/null 2>&1
  then echo live; else echo stray; fi
}

wt_projdir() { # wt_projdir <abs-cwd> — Claude Code's transcript dir for that cwd
  # Claude encodes the project by its cwd, replacing every '/' and '.' with '-'.
  printf '%s/.claude/projects/%s' "$HOME" "$(printf '%s' "$1" | sed 's/[/.]/-/g')"
}

chat_home() { # chat_home <agent> <wt_path> — echo the cwd whose client picker should open
  # Spawned worktrees never host an independent chat: their conversation lives in
  # the pane that made them. Claude lets us prove that with its project directory;
  # Codex and OpenCode keep private session indexes, so their cwd-filtered resume
  # UI is the authority and a genuine child simply inherits its parent's cwd.
  local agent="$1" w="$2" row main parent
  agent_has_chat "$agent" "$w" && { printf '%s' "$w"; return; }
  [ -f "$WT_REGISTRY" ] || { printf '%s' "$w"; return; }
  row="$(awk -F'\t' -v p="$w" '$4==p{print; exit}' "$WT_REGISTRY" 2>/dev/null)"
  main="$(printf '%s' "$row" | cut -f2)"
  parent="$(printf '%s' "$row" | cut -f5)"
  # Inherit the parent's chat only when the parent is a DIFFERENT context than this
  # worktree's own repo — a genuine spawned child. Two signatures:
  #   1. parent is itself an agent worktree (under WT_BASE) — a nested spawn.
  #   2. parent is a checkout of a DIFFERENT repo — a `wt child` (e.g. a workshop pane
  #      that spawned this sub-repo worktree). The chat is one session in that pane's pile.
  # A plain same-repo worktree's parent is its OWN main checkout, whose transcripts are the
  # user's unrelated on-main work — never hijack resume to that, so it falls through.
  case "$parent" in
    "$WT_BASE"/*)
      { [ "$agent" != claude ] || agent_has_chat "$agent" "$parent"; } && { printf '%s' "$parent"; return; }
      ;;
  esac
  # Cross-repo? Compare the two checkouts' git-common-dirs — both resolved by git, so
  # symlink-consistent (a raw string compare vs the stored path breaks on /var → /private).
  local pcommon mcommon
  pcommon="$(git -C "$parent" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || pcommon=""
  mcommon="$(git -C "$main" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || mcommon=""
  [ -n "$pcommon" ] && [ "$pcommon" != "$mcommon" ] \
    && { [ "$agent" != claude ] || agent_has_chat "$agent" "$parent"; } \
    && { printf '%s' "$parent"; return; }
  printf '%s' "$w"
}

repo_slug() { # repo_slug <checkout> — owner/name from its origin remote (for gh)
  local url
  url=$(git -C "$1" remote get-url origin 2>/dev/null) || return 1
  url=${url%.git}
  url=${url#*://}      # drop scheme  (https://host/… -> host/…)
  url=${url#*@}        # drop user    (git@host:…    -> host:…)
  url=${url#*[:/]}     # drop host + first separator  -> owner/name
  [ -n "$url" ] && printf '%s' "$url" || return 1
}

_gh() { # gh with a hard timeout so a stalled network can't hang pane teardown
  if command -v timeout >/dev/null 2>&1; then timeout 6 gh "$@"; else gh "$@"; fi
}

default_branch() { # default_branch <main> — the branch a PR here would land on
  # NOT `symbolic-ref HEAD`: that is whatever the main checkout happens to have
  # checked out RIGHT NOW. Land a side branch there that happens to contain an
  # agent branch and the agent branch reads as "merged" though it never reached
  # main — and gets reaped, taking the only copy of that work with it.
  local d
  d="$(git -C "$1" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)" \
    && [ -n "$d" ] && { printf '%s' "${d#origin/}"; return 0; }
  for d in main master trunk; do
    git -C "$1" show-ref -q --verify "refs/heads/$d" 2>/dev/null && { printf '%s' "$d"; return 0; }
  done
  # No conventional default and no origin/HEAD (a fresh repo, an odd remote):
  # fall back to HEAD, which is the old behaviour and the best guess left.
  git -C "$1" symbolic-ref --short HEAD 2>/dev/null || printf 'main'
}

branch_landed() { # branch_landed <main> <branch> -> 0 if it has ALREADY landed; read-only
  local main="$1" b="$2" base slug state head tip
  # Ancestry-merged (fast-forward / merge-commit / rebase that kept the commits):
  # offline, always-safe.
  base="$(default_branch "$main")"
  git -C "$main" merge-base --is-ancestor "$b" "$base" 2>/dev/null && return 0
  # Squash / rebase-collapse: the branch tip isn't an ancestor of the base, yet
  # the work may have LANDED under a new commit. The branch's merged PR is the
  # authoritative "it landed" signal (and survives the remote branch being deleted
  # on merge). Treat as landed ONLY when the local tip is exactly what that PR
  # merged (headRefOid) — a tip that moved on (post-merge commits, or an auto-WIP
  # commit) means there's un-landed work here, so it is NOT landed. No gh, offline,
  # or no merged PR => not landed, exactly as before.
  command -v gh >/dev/null 2>&1 || return 1
  slug="$(repo_slug "$main")" || return 1
  read -r state head < <(_gh pr list -R "$slug" --head "$b" --state merged \
      --limit 1 --json state,headRefOid \
      --jq '.[0] // empty | "\(.state) \(.headRefOid)"' 2>/dev/null) || return 1
  [ "$state" = "MERGED" ] || return 1
  tip="$(git -C "$main" rev-parse "$b" 2>/dev/null)" || return 1
  [ -n "$head" ] && [ "$head" = "$tip" ]
}

reap_branch() { # reap_branch <main> <branch> -> 0 if the branch was deleted
  local main="$1" b="$2"
  # branch_landed is the ONLY gate, and it is asked first. `git branch -d` used to
  # be the offline fast path, but -d measures against the main checkout's HEAD —
  # so it happily deletes a branch merged only into whatever side branch that
  # checkout is parked on. branch_landed measures against the repo's DEFAULT
  # branch (and the branch's merged PR for squash merges), which is the question
  # we actually mean. Having confirmed it landed, -d/-D is just the mechanism:
  # -d first so git's own safety net still gets a say, -D for the squash case it
  # cannot see.
  branch_landed "$main" "$b" || return 1
  git -C "$main" branch -d "$b" >/dev/null 2>&1 && return 0
  git -C "$main" branch -D "$b" >/dev/null 2>&1
}

OCCUPIED=""   # newline list of every cwd a live process is sitting in (see load_occupied)
load_occupied() {
  # "Landed and clean" does NOT mean "nobody is standing here". An agent whose PR
  # merged usually still has its pane OPEN — idle, or mid-/ship — and a merged
  # branch with everything committed looks exactly like an abandoned one. Removing
  # its checkout yanks the cwd out from under a running session: the shell and
  # Claude both keep running in a deleted directory, every subsequent tool call
  # fails, and the agent reports its worktree was pulled out from under it.
  # A zellij pane always has at least its login shell cwd'd into the worktree (and
  # Claude as a child), so "some process's cwd is inside this tree" is the signal.
  # One lsof dump for the whole sweep (~0.2s); prefix-matched per worktree below.
  command -v lsof >/dev/null 2>&1 || return 1
  OCCUPIED="$(lsof -w -d cwd -F n 2>/dev/null | sed -n 's/^n//p' | sort -u)"
  [ -n "$OCCUPIED" ]
}

occupied() { # occupied <path> — 0 if any live process's cwd is at or under <path>
  local p="$1" c
  while IFS= read -r c; do
    case "$c" in "$p" | "$p"/*) return 0 ;; esac
  done <<<"$OCCUPIED"
  return 1
}

checkout_map() { # main checkouts on STDIN → "main<TAB>branch<TAB>path" for every checked-out branch
  # git is the AUTHORITY on where a branch lives; the registry only records where
  # we PUT it. They diverge constantly — a branch renamed inside a worktree, a
  # `wt child` bucket keyed by owner-repo slug, an orphan worktree made by a raw
  # `git worktree add` — and every path that trusted the registry over git then
  # filed a very-much-live worktree as "parked": the listing lied, `wt <name>`
  # died with "already used by worktree", and the sweep lined the branch up for
  # reaping under a running pane. One porcelain dump per REPO (not per branch),
  # so resume_rows can correct every row it emits for the cost of one git call.
  # Paths arrive on stdin, not as arguments, so a checkout under a directory with
  # a space in it survives (word-splitting a newline list would not).
  local m
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    git -C "$m" worktree list --porcelain 2>/dev/null |
      awk -v m="$m" '/^worktree /{p=substr($0,10)} /^branch refs\/heads\//{print m"\t"substr($0,19)"\t"p}'
  done
}

# reap_sweep <parked|all> — the idempotent counterpart to the WorktreeRemove hook.
# The hook only fires on Claude's own graceful worktree teardown; anything else
# that ends a pane (a manual `zellij close-pane`, a reboot, a crash, ⌘C churn) or
# a `wt child` cross-repo checkout bypasses it, so merged worktrees pile up. This
# sweep reaps them independent of pane lifecycle. Sets REAPED to a newline list of
# "<name> (<repo>)" for what it dropped.
#   parked  — reap ONLY branches whose checkout is already gone (zero risk); the
#             self-heal that runs on every `wt` list.
#   all     — also reap LIVE checkouts, but only when clean AND landed AND nobody
#             is standing in them (our own pane, or ANY other open pane — see
#             load_occupied); dirty/unmerged/occupied work is always left.
reap_sweep() {
  local mode="${1:-parked}" main branch wt selftop state
  REAPED=""
  SKIPPED_LIVE=""
  STRAYS=""
  selftop="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
  # No lsof (or nothing readable) means we cannot tell an open pane from an
  # abandoned one — so don't guess: sweep parked worktrees only. A checkout left
  # behind costs a later `wt reap`; one pulled out from under a live agent costs
  # that session.
  NO_LSOF=""
  if [ "$mode" = "all" ] && ! load_occupied; then mode="parked"; NO_LSOF=1; fi
  while IFS=$'\t' read -r main branch wt; do
    [ -n "$branch" ] || continue
    git -C "$main" show-ref -q --verify "refs/heads/$branch" 2>/dev/null || continue
    # $wt is already git's answer where git has one — resume_rows corrects every
    # row it emits (see checkout_map), so a live worktree can't be filed as parked.
    state="$(checkout_state "$wt")"
    # A husk (checkout_state stray) is the one thing the sweep must NOT touch. Its
    # directory can hold the very edits it was killed mid-save — untracked files
    # and unstaged changes that live in no commit — and git can no longer read the
    # checkout to tell us whether it does. Reaping the branch would leave that
    # directory orphaned and unnamed by anything, so the branch stays and the husk
    # is REPORTED instead: `wt <name>` heals it (moves the husk aside, rebuilds).
    # Same invariant as everywhere else here — the failure direction is "a branch
    # lingers", never "work disappears".
    if [ "$state" = stray ]; then
      STRAYS+="${branch#worktree-} ($(basename "$main")) → $wt"$'\n'
      continue
    fi
    if [ "$state" = live ]; then
      # A live checkout. Parked-only mode leaves every live checkout untouched.
      [ "$mode" = "all" ] || continue
      [ "$wt" = "$selftop" ] && continue                                   # never our own pane
      # Another pane is still cwd'd in there — landed or not, it is IN USE.
      occupied "$wt" && { SKIPPED_LIVE+="${branch#worktree-} ($(basename "$main"))"$'\n'; continue; }
      [ -z "$(git -C "$wt" status --porcelain 2>/dev/null)" ] || continue  # dirty → leave for a human
      branch_landed "$main" "$branch" || continue                          # unmerged live work → leave
      git -C "$main" worktree remove "$wt" 2>/dev/null || continue         # free the branch, then reap it
    fi
    if reap_branch "$main" "$branch"; then
      reg_del "$wt"
      REAPED+="${branch#worktree-} ($(basename "$main"))"$'\n'
    fi
  done <<<"$(resume_rows)"
  reg_prune
}

hook_field() { # hook_field <json> <key>… — first key present in the payload
  # Key names drift across Claude Code versions (docs say worktree_name/base_path;
  # 2.1.x sends name/cwd) — accept either, first hit wins.
  local json="$1"
  shift
  python3 -c '
import json, sys
d = json.load(sys.stdin)
for k in sys.argv[1:]:
    if k in d:
        print(d[k]); break
else:
    print(f"hook payload has none of {sys.argv[1:]}: {d}", file=sys.stderr); sys.exit(1)
' "$@" <<<"$json"
}

cmd_create() { # [WorktreeCreate hook] JSON on stdin; ONLY the new path on stdout
  local json name base dir
  json="$(cat)"
  name="$(hook_field "$json" name worktree_name)"
  base="$(hook_field "$json" base_path cwd)"
  dir="$WT_BASE/$(basename "$base")/$name"
  git -C "$base" worktree add -b "worktree-$name" "$dir" HEAD >&2
  # Record it so `wt` can rebuild + reopen this worktree later — even after the
  # checkout is removed, and even for repos it has never otherwise heard of.
  # `$base` (the spawning pane's cwd) is stored as the parent so the statusline
  # can list a session only the worktrees it spawned.
  # This hook is Claude Code's native --worktree hook, so its client is known
  # even when the system-wide palette default is Codex or OpenCode.
  reg_put "$name" "$(git_main "$base")" "worktree-$name" "$dir" "$base" claude || true
  echo "$dir"
}

cmd_child() { # wt child <repo-path> [name] — worktree of ANOTHER repo, as a child
  # The cross-repo escape hatch. A workshop pane whose task belongs to a sub-repo
  # would otherwise reach for a raw `git worktree add` — which never touches the
  # registry, so the refresher never learns to ask THAT repo's GitHub for the
  # branch's PR, and the statusline stays blind to it. This does the same
  # worktree add but REGISTERS it with this pane's cwd as the parent, so the PR
  # surfaces as a child row under the session that spawned it.
  local target="${1:-}" name="${2:-}"
  [ -n "$target" ] || die "usage: wt child <repo-path> [name]"
  [ -d "$target" ] || die "no such directory: $target"
  local tmain agent
  tmain="$(git_main "$target")" || die "'$target' isn't inside a git repo"
  [ -d "$tmain/.git" ] || die "'$target' resolves to $tmain, which isn't a main checkout"
  # Default the child's name to THIS pane's worktree name, so a sub-worktree
  # shares the session's identity (…-sparkle in both repos). Fall back to the
  # cwd's basename when the pane isn't itself on a worktree-* branch.
  if [ -z "$name" ]; then
    local b; b="$(git -C "$PWD" branch --show-current 2>/dev/null || true)"
    case "$b" in worktree-*) name="${b#worktree-}" ;; *) name="$(basename "$PWD")" ;; esac
  fi
  # Bucket dir = target repo basename, EXCEPT when that would collide with the
  # spawning pane's own repo basename (the nested case: workshop `nebelhaus` vs
  # rice `nebelhaus/nebelhaus`) — then key it by the full owner-repo slug so the
  # child never lands on the parent's own checkout path. Buckets are cosmetic:
  # resume_rows re-derives each worktree's main from its checkout, not the dir.
  local bucket cur
  bucket="$(basename "$tmain")"
  cur="$(basename "$(git_main "$PWD" 2>/dev/null || echo "$PWD")")"
  [ "$bucket" = "$cur" ] && bucket="$(repo_slug "$tmain" 2>/dev/null | tr '/' '-')"
  [ -n "$bucket" ] || bucket="$(basename "$tmain")"
  local dir="$WT_BASE/$bucket/$name"
  [ -e "$dir" ] && die "a worktree already exists at $dir — pass another name: wt child $target <name>"
  git -C "$tmain" show-ref -q --verify "refs/heads/worktree-$name" 2>/dev/null \
    && die "branch worktree-$name already exists in $(basename "$tmain") — pass another name: wt child $target <name>"
  git -C "$tmain" worktree add -b "worktree-$name" "$dir" HEAD >&2
  # Register with THIS pane's cwd ($PWD) as parent — the same field cmd_create
  # stores — so the statusline lists the child under the session that spawned it,
  # and the refresher queries the CHILD repo's GitHub for its PR state.
  agent="$(agent_for_worktree "$PWD")"
  reg_put "$name" "$tmain" "worktree-$name" "$dir" "$PWD" "$agent" || true
  say "created $(basename "$tmain") worktree '$name' → $dir"
  echo "$dir"   # ONLY the path on stdout, so callers can: cd "$(wt child …)"
}

cmd_spawn() { # wt spawn <repo-path> <name> [agent] — a worktree for a spawner with no pane
  # `create` and `child` both assume a pane: they record the spawning cwd as the
  # parent, which is how the statusline files a worktree under the session that
  # made it. The palette has no pane — its command runs under launchd — and the
  # session it launches is a TOP-LEVEL one, not anybody's child. So this records
  # the repo's OWN main checkout as the parent: a pane sitting in that repo lists
  # it, which is where a human looks for it, instead of leaving it parentless
  # (which the statusline can only surface as an orphan ◇ in the $HOME pane).
  #
  # The other difference is that a taken name is not fatal. `child` dies and tells
  # you to pass another one; a palette has nobody to tell, so a dead end there is
  # just a command that silently did nothing. Take the first free -2/-3 suffix.
  local target="${1:-}" want="${2:-}" agent="${3:-$(agent_default)}"
  [ -n "$target" ] && [ -n "$want" ] || die "usage: wt spawn <repo-path> <name>"
  agent_known "$agent" || die "unknown agent '$agent' (expected claude, codex, or opencode)"
  [ -d "$target" ] || die "no such directory: $target"
  local tmain
  tmain="$(git_main "$target")" || die "'$target' isn't inside a git repo"
  [ -d "$tmain/.git" ] || die "'$target' resolves to $tmain, which isn't a main checkout"
  local bucket dir name n=1
  bucket="$(basename "$tmain")"
  name="$want"
  while [ -e "$WT_BASE/$bucket/$name" ] \
    || git -C "$tmain" show-ref -q --verify "refs/heads/worktree-$name" 2>/dev/null; do
    n=$((n + 1))
    [ "$n" -gt 99 ] && die "no free name near '$want' in $bucket"
    name="$want-$n"
  done
  dir="$WT_BASE/$bucket/$name"
  git -C "$tmain" worktree add -b "worktree-$name" "$dir" HEAD >&2
  reg_put "$name" "$tmain" "worktree-$name" "$dir" "$tmain" "$agent" || true
  say "created $bucket worktree '$name' → $dir"
  echo "$dir"   # ONLY the path on stdout, so callers can: cd "$(wt spawn …)"
}

wip_commit() { # wip_commit <checkout> <subject> — park the whole dirty tree as one commit
  # Shared by the remove hook (automatic, on pane close) and `wt park` (on demand),
  # so both produce the SAME thing: one `wip:` commit on the current branch holding
  # every tracked edit and untracked file. gpgsign off — the hook is non-interactive
  # and a signing prompt there would hang pane teardown; an agent calling `wt park`
  # is just as unable to answer one.
  git -C "$1" add -A >/dev/null 2>&1 || true
  git -C "$1" -c commit.gpgsign=false commit -q -m "$2" >/dev/null 2>&1
}

cmd_park() { # wt park [label] — stash-free "set this aside": a wip: commit on THIS branch
  # Why this exists at all: `git stash` looks per-worktree but ISN'T. The stash
  # stack lives in the common .git dir, so every agent worktree of a repo — and the
  # main checkout — share ONE stack. Two parallel panes stashing means either can
  # pop the other's entry, and the loser's edits land in a tree that never asked for
  # them (or vanish into a conflicted mess). A wip commit has no such stack: it sits
  # on the branch only this pane has checked out, it survives a pane close, `wt`
  # lists it as that worktree's last commit, and `wt unpark` puts it back.
  local top branch dirty label msg n
  top="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" || die "not in a git repo — nothing to park"
  branch="$(git -C "$top" branch --show-current 2>/dev/null || true)"
  # Detached HEAD is the one place this would recreate stash's failure mode: the
  # commit is reachable from nothing, so the next checkout orphans it.
  [ -n "$branch" ] || die "HEAD is detached — a parked commit here would be unreachable. Check out a branch first."
  dirty="$(git -C "$top" status --porcelain 2>/dev/null || true)"
  [ -n "$dirty" ] || { say "nothing to park — $branch is already clean."; return 0; }
  label="${1:-}"
  if [ -n "$label" ]; then msg="wip: $label (parked $(date '+%Y-%m-%d %H:%M'))"
  else msg="wip: parked $(date '+%Y-%m-%d %H:%M')"; fi
  wip_commit "$top" "$msg" || die "commit failed — nothing was parked; \`git -C $top status\` will say why."
  n="$(printf '%s\n' "$dirty" | grep -c . || true)"
  say "parked $n change(s) on $branch → $(git -C "$top" rev-parse --short HEAD)"
  case "$branch" in
    worktree-*) ;;
    *) say "note: '$branch' isn't an agent branch — don't push this wip commit." ;;
  esac
  say "bring them back with: wt unpark"
}

cmd_unpark() { # wt unpark — the `git stash pop` half: undo the last wip: commit
  local top branch subj
  top="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)" || die "not in a git repo — nothing to unpark"
  branch="$(git -C "$top" branch --show-current 2>/dev/null || true)"
  [ -n "$branch" ] || die "HEAD is detached — check out a branch first."
  subj="$(git -C "$top" log -1 --format='%s' 2>/dev/null || true)"
  case "$subj" in
    wip:*) ;;
    *) die "HEAD isn't a parked commit (it's \"$subj\") — nothing to unpark." ;;
  esac
  git -C "$top" rev-parse -q --verify 'HEAD^' >/dev/null 2>&1 \
    || die "that wip commit is the branch's first commit — there's nothing to rewind onto."
  # Refuse to rewrite anything already published. A parked commit that got pushed is
  # visible in an open PR (and to `bench status`), so rewinding it locally turns
  # "give me my files back" into a force-push — never do that behind the user's back.
  if [ -n "$(git -C "$top" branch -r --contains HEAD 2>/dev/null)" ]; then
    die "that wip commit is already pushed — unparking would rewrite published history. If you mean it: git reset --mixed HEAD^"
  fi
  # --mixed, not --hard: the files stay on disk exactly as parked and go back to
  # being uncommitted (staged adds become untracked again), which is what pop does.
  git -C "$top" reset -q --mixed 'HEAD^' || die "reset failed — the parked commit is untouched."
  say "unparked \"$subj\" on $branch — those changes are back in the working tree, uncommitted."
}

cmd_remove() { # [WorktreeRemove hook] JSON on stdin — retire without losing work
  local json dir main branch
  json="$(cat)"
  dir="$(hook_field "$json" worktree_path path)"
  main="$(git_main "$dir")" || die "worktree '$dir' isn't a git checkout — nothing to retire"
  branch="$(git -C "$dir" branch --show-current 2>/dev/null || true)"
  # A --force remove would silently discard UNCOMMITTED edits. Committed work
  # always survives on the branch; park the dirty remainder there too, as a WIP
  # commit (the same one `wt park` makes by hand), so closing a pane can never
  # cost you work.
  #
  # ONE exception, and it matters: a branch whose PR has ALREADY merged, whose only
  # remaining changes are UNTRACKED files, is holding build scratch (a .cargo-home/,
  # a target/ …) — not history. WIP-committing it would move the tip one commit past
  # the merged PR's SHA, so reap_branch below no longer recognizes the merge and the
  # worktree gets falsely PARKED instead of reaped (this is how merged worktrees piled
  # up). So when — and only when — the branch is landed AND every dirty entry is
  # untracked, skip the WIP and let the force-remove drop the scratch, so it reaps
  # cleanly. Tracked edits, or an unmerged branch, are real work → always preserved.
  # preserved=1 means nothing on disk is irreplaceable any more: either the tree was
  # clean, or the WIP commit above captured it, or it was landed-plus-untracked
  # scratch we chose to drop. It gates the husk cleanup below, and nothing else.
  local porcelain preserved=1
  porcelain="$(git -C "$dir" status --porcelain 2>/dev/null || true)"
  if [ -n "$porcelain" ]; then
    if printf '%s\n' "$porcelain" | grep -qv '^??' \
       || [ -z "$branch" ] || ! branch_landed "$main" "$branch"; then
      wip_commit "$dir" "wip: auto-saved on pane close ($(date '+%Y-%m-%d %H:%M'))" || preserved=0
    fi
  fi
  git -C "$main" worktree remove "$dir" 2>/dev/null \
    || git -C "$main" worktree remove --force "$dir" 2>/dev/null || true
  # Finish what git started. `git worktree remove` deletes the admin dir BEFORE it
  # deletes the working tree, so when the recursive delete fails part-way — most
  # often an ignored build dir it cannot unlink — git leaves a directory whose .git
  # references a gitdir that is gone: a husk (checkout_state). Nothing recovers on
  # its own; it sat in $WT_BASE reading `live` forever, and it killed the
  # statusline refresher outright. So when the removal left one behind AND the
  # work is preserved, delete the residue ourselves.
  #
  # If the WIP commit failed, that residue is the ONLY copy of those edits —
  # leave it and say so. `wt` lists it as `stray`, `wt reap` spares it, and
  # `wt <name>` moves it aside rather than deleting it. A husk that lingers is a
  # nuisance; a husk deleted with the work still in it is the thing wt exists to
  # never do.
  case "$([ -e "$dir" ] && checkout_state "$dir" || echo gone)" in
  stray)
    if [ "$preserved" = 1 ]; then
      # Best-effort: whatever defeated git's delete can defeat ours too (a
      # permission on a directory we don't own). Never fatal — a husk we can't
      # finish off is a nuisance `wt` now names and `wt <name>` heals, while a
      # hook that dies here leaves the branch unreaped and the registry stale.
      rm -rf "$dir" 2>/dev/null || true
      if [ -e "$dir" ]; then
        say "git left a partly-removed checkout at $dir and we couldn't finish it either — \`wt\` lists it as stray"
      fi
    else
      say "couldn't save this worktree's edits AND git couldn't remove it — left at $dir"
    fi
    ;;
  live)
    # Even --force refused, and git never got as far as unregistering. The branch
    # is still checked out here, so don't reap it out from under the checkout.
    say "git wouldn't remove $dir — the worktree is still registered; try: wt reap"
    return 0
    ;;
  esac
  # The branch is how unmerged work survives; only reap it once merged. Ancestry
  # merges reap offline (branch -d); squash/rebase merges are recognized via the
  # branch's merged PR, guarded so post-merge work is never dropped (reap_branch).
  # Keep the registry line in lockstep: gone when reaped, kept while resumable.
  if [ -n "$branch" ] && reap_branch "$main" "$branch"; then
    reg_del "$dir"
  fi
}

# resume_rows — every resumable/live agent worktree, deduped, one per line as
# "main<TAB>branch<TAB>wt_path". Fully generic: the set of repos is discovered,
# never hardcoded. Sources: the registry (authoritative paths, survives checkout
# deletion), every live checkout on disk (glob — this is "all repos with an open
# worktree"), and orphan worktree-* branches from any main we can reach via the
# first two. First hit per (main,branch) wins, so a real path beats a rebuilt one.
resume_rows() {
  local rows="" raw="" real="" d m b mdir ob mains actual
  [ -f "$WT_REGISTRY" ] && rows+="$(awk -F'\t' 'NF>=4 {print $2"\t"$3"\t"$4}' "$WT_REGISTRY")"$'\n'
  for d in "$WT_BASE"/*/*; do
    [ -e "$d/.git" ] || continue
    m="$(git_main "$d")" || continue
    b="$(git -C "$d" branch --show-current 2>/dev/null)" || continue
    [ -n "$b" ] && rows+="$m"$'\t'"$b"$'\t'"$d"$'\n'
    raw+="$m"$'\n'
  done
  [ -f "$WT_REGISTRY" ] && raw+="$(awk -F'\t' 'NF>=2 {print $2}' "$WT_REGISTRY")"$'\n'
  # Normalize each candidate to its real main (collapsing worktree paths), keep
  # only true main checkouts (.git is a DIR, not a worktree's .git file), dedup.
  while IFS= read -r mdir; do
    [ -n "$mdir" ] || continue
    m="$(git_main "$mdir" 2>/dev/null)" || continue
    [ -n "$m" ] && [ -d "$m/.git" ] && real+="$m"$'\n'
  done <<<"$raw"
  mains="$(printf '%s' "$real" | awk 'NF && !s[$0]++')"
  while IFS= read -r mdir; do
    [ -n "$mdir" ] || continue
    for ob in $(git -C "$mdir" branch --list 'worktree-*' --format='%(refname:short)' 2>/dev/null); do
      rows+="$mdir"$'\t'"$ob"$'\t'"$WT_BASE/$(basename "$mdir")/${ob#worktree-}"$'\n'
    done
  done <<<"$mains"
  # Correct every row's path against git before anyone reads it. The path a row
  # arrives with is a GUESS — the registry's record of where we put the checkout,
  # or (for an orphan branch) a name synthesized from the bucket convention.
  # checkout_map is the truth, so a branch that moved, or a checkout that was
  # never ours, is reported where it actually is. Rows git has no checkout for
  # keep their guess: that is exactly the "parked" case, and cmd_resume rebuilds
  # there. Every consumer — list, resume, reap — inherits this for free, which is
  # the point: correcting it at one call site (as the sweep used to) left the
  # listing and resume trusting the guess.
  actual="$(printf '%s\n' "$mains" | checkout_map)"
  # The map arrives as awk's FIRST FILE, not via -v: a -v assignment cannot carry
  # a value containing newlines (awk aborts with "newline in string"), and this
  # map is one line per checkout.
  printf '%s' "$rows" | awk -F'\t' 'NF>=3 && !seen[$1 FS $2]++' |
    awk -F'\t' 'NR==FNR { if (NF >= 3) A[$1 SUBSEP $2] = $3; next }
                { k = $1 SUBSEP $2; print $1 "\t" $2 "\t" (k in A ? A[k] : $3) }' \
        <(printf '%s\n' "$actual") -
}

cmd_list() {
  # Self-heal: reap parked branches whose PR has since merged. Parked-only, so it
  # never disturbs a live checkout that may still have an open pane; the risky live
  # sweep is opt-in via `wt reap`. Best-effort — a network hiccup must not break the
  # listing.
  reap_sweep parked || true
  [ -n "${REAPED:-}" ] && say "swept $(printf '%s' "$REAPED" | grep -c .) merged worktree(s)"
  # Husks can't be swept (reap_sweep leaves them deliberately), so the listing is
  # where they surface — otherwise a half-removed checkout is a `stray` row with
  # no hint of what to do about it.
  if [ -n "${STRAYS:-}" ]; then
    say "$(printf '%s' "$STRAYS" | grep -c .) dangling checkout(s) — git lost the link; \`wt <name>\` moves each aside and rebuilds:"
    printf '%s' "$STRAYS" | while IFS= read -r s; do [ -n "$s" ] && say "  $s"; done
  fi
  say "agent worktrees you can resume (wt <name>, or <repo>/<name>)"

  # Gather every row FIRST, so columns can be sized to their real content and the
  # commit message trimmed to whatever width the terminal actually has. The old
  # layout hardcoded 12/26-wide repo/name columns and a 56-char commit slice —
  # ~110 columns total — which wrapped into a mess in a narrow pane. Now repo/name
  # size to content (capped), and the commit fills the remaining width, so the
  # listing stays on one line per worktree however narrow the pane.
  local main branch wt agent
  local -a r_repo=() r_nm=() r_state=() r_agent=() r_last=()
  while IFS=$'\t' read -r main branch wt; do
    [ -n "$branch" ] || continue
    git -C "$main" show-ref -q --verify "refs/heads/$branch" 2>/dev/null || continue
    r_repo+=("$(basename "$main")")
    r_nm+=("${branch#worktree-}")
    r_state+=("$(checkout_state "$wt")")
    agent="$(agent_for_worktree "$wt")"
    r_agent+=("$agent")
    r_last+=("$(git -C "$main" log -1 --format='%cr — %s' "$branch" 2>/dev/null)")
  done <<<"$(resume_rows)"

  if [ "${#r_repo[@]}" -eq 0 ]; then
    say "none parked — every worktree branch is merged & cleaned up. The fog is even."
    return 0
  fi

  # Column widths: header labels set the floor, content grows them up to a cap so
  # one pathological name can't swallow the row. state/chat hold fixed values.
  local i rw=4 nw=4 sw=6 cw=4
  for i in "${!r_repo[@]}"; do
    [ "${#r_repo[$i]}" -gt "$rw" ] && rw=${#r_repo[$i]}
    [ "${#r_nm[$i]}"   -gt "$nw" ] && nw=${#r_nm[$i]}
  done
  [ "$rw" -gt 16 ] && rw=16
  [ "$nw" -gt 28 ] && nw=28

  # Terminal width: COLUMNS isn't exported into a script, so fall back to tput,
  # then to 80 when there's no tty (piped / redirected).
  local cols="${COLUMNS:-}"
  [ -n "$cols" ] || cols="$(tput cols 2>/dev/null || echo 80)"

  # Drop the client column first when space is tight, then let
  # the commit take whatever's left. 2 = indent, +1 per inter-column gap.
  local show_chat=1 used lastw
  used=$(( 2 + rw + 1 + nw + 1 + sw + 1 + cw + 1 ))
  if [ $(( cols - used )) -lt 20 ]; then
    show_chat=0
    used=$(( 2 + rw + 1 + nw + 1 + sw + 1 ))
  fi
  lastw=$(( cols - used ))
  # Truly tight pane: the fixed columns alone won't leave room for the commit.
  # `name` is the next most compressible, so shrink it (down to a floor) to buy
  # the commit a legible slice, rather than overflow the line.
  if [ "$lastw" -lt 12 ]; then
    local fixed_other=$(( 2 + rw + 1 + 1 + sw + 1 ))
    [ "$show_chat" = 1 ] && fixed_other=$(( fixed_other + cw + 1 ))
    nw=$(( cols - fixed_other - 12 ))
    [ "$nw" -lt 8 ] && nw=8
    lastw=12
  fi

  local hdr row
  if [ "$show_chat" = 1 ]; then
    hdr="  %-${rw}s %-${nw}s %-${sw}s %-${cw}s %s\n"
    printf "$hdr" "repo" "name" "state" "agent" "last commit"
    for i in "${!r_repo[@]}"; do
      printf "$hdr" "$(fit "${r_repo[$i]}" "$rw")" "$(fit "${r_nm[$i]}" "$nw")" \
        "${r_state[$i]}" "${r_agent[$i]}" "$(fit "${r_last[$i]}" "$lastw")"
    done
  else
    hdr="  %-${rw}s %-${nw}s %-${sw}s %s\n"
    printf "$hdr" "repo" "name" "state" "last commit"
    for i in "${!r_repo[@]}"; do
      printf "$hdr" "$(fit "${r_repo[$i]}" "$rw")" "$(fit "${r_nm[$i]}" "$nw")" \
        "${r_state[$i]}" "$(fit "${r_last[$i]}" "$lastw")"
    done
  fi
}

cmd_resume() { # cmd_resume <name|repo/name>
  local want="${1:-}"
  [ -n "$want" ] || { cmd_list; return 0; }
  local rrepo="" rname="$want" sel="" matches=0 main branch wt agent
  case "$want" in */*) rrepo="${want%%/*}"; rname="${want##*/}" ;; esac
  while IFS=$'\t' read -r main branch wt; do
    [ -n "$branch" ] || continue
    git -C "$main" show-ref -q --verify "refs/heads/$branch" 2>/dev/null || continue
    [ "${branch#worktree-}" = "$rname" ] || continue
    [ -z "$rrepo" ] || [ "$(basename "$main")" = "$rrepo" ] || continue
    sel="$main"$'\t'"$branch"$'\t'"$wt"
    matches=$((matches + 1))
  done <<<"$(resume_rows)"

  [ "$matches" = "0" ] && die "no agent worktree named '$want' — run: wt"
  [ "$matches" -gt 1 ] && die "'$rname' exists in more than one repo — qualify it: wt <repo>/$rname"

  IFS=$'\t' read -r main branch wt <<<"$sel"
  # Resolve this before a parked checkout is re-registered: a five-column
  # registry row predates the client field and is therefore Claude forever,
  # even if the machine's current default has since changed.
  agent="$(agent_for_worktree "$wt")"
  case "$(checkout_state "$wt")" in
  live)
    say "'$branch' is still live at $wt"
    ;;
  stray)
    # A husk: the directory is there, git disowns it (checkout_state). It is in the
    # way — `git worktree add` refuses a non-empty directory — and it may hold real
    # uncommitted work, so it is MOVED, never deleted. The rebuilt checkout beside
    # it has the branch's committed state; whatever was only in the husk is one
    # `diff -ru` away, and the path is printed so it can't be lost silently.
    local husk
    husk="$wt.stray-$(date +%Y%m%d-%H%M%S)"
    mv "$wt" "$husk" || die "couldn't move the dangling checkout aside: $wt"
    say "dangling checkout moved to $husk (nothing deleted — it may hold uncommitted work)"
    say "rebuilding checkout for $branch → $wt"
    mkdir -p "$(dirname "$wt")"
    git -C "$main" worktree add "$wt" "$branch" >&2
    reg_put "${branch#worktree-}" "$main" "$branch" "$wt" "" "$agent" || true
    say "compare what the husk had: diff -ru $husk $wt"
    ;;
  *)
    say "rebuilding checkout for $branch → $wt"
    mkdir -p "$(dirname "$wt")"
    git -C "$main" worktree add "$wt" "$branch" >&2
    reg_put "${branch#worktree-}" "$main" "$branch" "$wt" "" "$agent" || true
    ;;
  esac
  # A spawned worktree (`wt child`, nested) has no chat of its own — resume the parent
  # session that spawned it (see chat_home). The checkout above is still rebuilt so the
  # branch's files are on disk; we just cd to where the transcript lives to reopen it.
  local chat; chat="$(chat_home "$agent" "$wt")"
  if [ "$chat" != "$wt" ]; then
    say "no chat in this worktree — it was spawned from a session in $chat"
    # When that parent is a shared checkout (a workshop pane that spawned several children),
    # its picker lists many sessions — point at the one that touched THIS branch.
    say "in the picker, pick the session for '$branch' — last commit:"
    say "  $(git -C "$main" log -1 --format='%s' "$branch" 2>/dev/null)"
    # Claude keys the transcript off the cwd, so that dir must exist. If the parent
    # checkout was reaped, anchor a bare dir just to reopen the chat (your work is safe
    # on $branch; the child checkout with the files is rebuilt at $wt above).
    [ -d "$chat" ] || mkdir -p "$chat"
  fi
  if [ -t 1 ] && command -v "$agent" >/dev/null 2>&1; then
    say "reopening the $agent chat …"
    cd "$chat" && agent_resume "$agent"
  else
    say "checkout ready. Reopen the $agent chat with:"
    case "$agent" in
      claude) printf '    cd %q && claude --resume\n' "$chat" ;;
      codex) printf '    cd %q && codex resume\n' "$chat" ;;
      opencode) printf '    cd %q && opencode --continue\n' "$chat" ;;
    esac
  fi
}

cmd_reap() { # wt reap — sweep every LANDED worktree across all repos, now
  say "reaping landed worktrees (parked, plus clean & merged UNOCCUPIED checkouts) …"
  reap_sweep all
  [ -n "${NO_LSOF:-}" ] && say "no lsof — can't tell an open pane from an abandoned one; swept parked only."
  if [ -n "${REAPED:-}" ]; then
    printf '%s' "$REAPED" | while IFS= read -r r; do
      [ -n "$r" ] && printf '\033[38;5;103m  ✓ reaped %s\033[0m\n' "$r" >&2
    done
  else
    say "nothing to reap — every worktree is unmerged, dirty, or has a pane open in it."
  fi
  # Name what was spared, so "reap did nothing" never reads as a bug. These are the
  # ones a human closes: landed, but someone is still sitting in them.
  if [ -n "${SKIPPED_LIVE:-}" ]; then
    printf '%s' "$SKIPPED_LIVE" | while IFS= read -r r; do
      [ -n "$r" ] && printf '\033[38;5;103m  ⏸ kept %s — a pane is open in it\033[0m\n' "$r" >&2
    done
  fi
  # Husks are spared on purpose (see reap_sweep) — say so, with the one command
  # that resolves them, or "reap did nothing" hides a checkout that needs a human.
  if [ -n "${STRAYS:-}" ]; then
    printf '%s' "$STRAYS" | while IFS= read -r r; do
      [ -n "$r" ] && printf '\033[38;5;173m  ◇ kept %s — dangling; `wt <name>` moves it aside and rebuilds\033[0m\n' "$r" >&2
    done
  fi
}

cmd_agent() { # wt agent <default|start|resume> … — the public client-table seam
  case "${1:-}" in
    default) agent_default ;;
    start) shift; agent_start "$@" ;;
    resume) shift; agent_resume "${1:-}" ;;
    *) die "usage: wt agent <default|start|resume>" ;;
  esac
}

case "${1:-}" in
create) cmd_create ;;
remove) cmd_remove ;;
child) cmd_child "${2:-}" "${3:-}" ;;
spawn) cmd_spawn "${2:-}" "${3:-}" "${4:-}" ;;
agent) shift; cmd_agent "$@" ;;
park) cmd_park "${2:-}" ;;
unpark) cmd_unpark ;;
resume) cmd_resume "${2:-}" ;;
reap | gc) cmd_reap ;;
list | ls) cmd_list ;;
# Help is the header block itself — printed by shape (every leading-# line after
# the shebang), not by line number, so adding a command can't silently truncate it.
"" | -h | --help | help)
  [ "${1:-}" = "" ] && cmd_list \
    || awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0" ;;
*) cmd_resume "$1" ;; # bare token → treat as a worktree name to resume
esac

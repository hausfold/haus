#!/usr/bin/env bash
# wt — manage Claude Code agent worktrees, for ANY git repo.
#
# `claude --worktree` (the Super-c / ⌘C zellij bind) fires Claude Code's
# WorktreeCreate/WorktreeRemove hooks; this script is what they call. It keeps
# agent checkouts under ~/.cache/claude-worktrees/<repo>/<name> (out of the repo
# so trees stay clean) on branch worktree-<name>, and — crucially — makes
# closing a pane safe and reversible:
#
#   wt                list every parked/live agent worktree, across ALL repos
#                     (self-heals first: reaps parked branches whose PR has merged)
#   wt <name>         resume one: rebuild its checkout + reopen its Claude chat
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
PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/$(id -un 2>/dev/null)/bin:/usr/bin:/bin:${PATH:-}"

WT_BASE="${CLAUDE_WT_BASE:-$HOME/.cache/claude-worktrees}"
# The registry is `wt`'s source of truth for parked worktrees: one tab-separated
# line per worktree — "name<TAB>main-checkout<TAB>branch<TAB>checkout-path" —
# written at create time. It lets `wt` rebuild a parked worktree and find its
# main checkout across ANY repo, even after the checkout dir is gone. Merged-away
# worktrees are pruned; unmerged ones linger exactly as long as their branch.
WT_REGISTRY="$WT_BASE/registry.tsv"

say() { printf '\033[38;5;103m🌫  %s\033[0m\n' "$*" >&2; }
die() { printf '\033[38;5;167m✗  %s\033[0m\n' "$*" >&2; exit 1; }

fit() { # fit <string> <maxlen> — trim to width, appending … when it overflowed
  local s="$1" n="$2"
  [ "$n" -lt 1 ] && n=1
  if [ "${#s}" -gt "$n" ]; then printf '%s…' "${s:0:n-1}"; else printf '%s' "$s"; fi
}

reg_put() { # reg_put <name> <main> <branch> <wt_path> [parent] — upsert, keyed on wt_path
  # The optional 5th field is the cwd the worktree was spawned FROM (its parent
  # pane) — recorded at create so the statusline can show a session only the
  # worktrees IT spawned. When omitted (e.g. resume, which doesn't know the
  # original spawner), the existing parent is preserved, never blanked.
  mkdir -p "$WT_BASE"
  local parent="${5:-}"
  local tmp="$WT_REGISTRY.$$"
  if [ -f "$WT_REGISTRY" ]; then
    [ -z "$parent" ] && parent="$(awk -F'\t' -v p="$4" '$4==p{print $5; exit}' "$WT_REGISTRY")"
    awk -F'\t' -v p="$4" '$4 != p' "$WT_REGISTRY" >"$tmp"
  else
    : >"$tmp"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$parent" >>"$tmp"
  mv "$tmp" "$WT_REGISTRY"
}

reg_del() { # reg_del <wt_path> — drop the line for a worktree we've reaped
  [ -f "$WT_REGISTRY" ] || return 0
  local tmp="$WT_REGISTRY.$$"
  awk -F'\t' -v p="$1" '$4 != p' "$WT_REGISTRY" >"$tmp"
  mv "$tmp" "$WT_REGISTRY"
}

reg_prune() { # drop every row that can no longer resume anything, and its empty bucket dir
  # reg_del only fires when WE reap a branch. A branch that vanishes any other way
  # — merged and deleted on GitHub, `git branch -D` by hand, a main checkout moved
  # or removed — leaves its row behind forever, and the rows outlive the repos:
  # 54 of 56 rows here were dead. Harmless, but they're the fuel every path-resolution
  # bug feeds on, so the sweep that already self-heals branches heals the registry too.
  [ -f "$WT_REGISTRY" ] || return 0
  local tmp="$WT_REGISTRY.$$" name main branch wt parent
  while IFS=$'\t' read -r name main branch wt parent; do
    [ -n "$branch" ] || continue
    git -C "$main" show-ref -q --verify "refs/heads/$branch" 2>/dev/null || continue
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$main" "$branch" "$wt" "$parent"
  done <"$WT_REGISTRY" >"$tmp"
  mv "$tmp" "$WT_REGISTRY"
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

wt_projdir() { # wt_projdir <abs-cwd> — Claude Code's transcript dir for that cwd
  # Claude encodes the project by its cwd, replacing every '/' and '.' with '-'.
  printf '%s/.claude/projects/%s' "$HOME" "$(printf '%s' "$1" | sed 's/[/.]/-/g')"
}

chat_home() { # chat_home <wt_path> — echo the cwd whose Claude chat this worktree resumes
  # Claude keys a transcript to the cwd it ran in — and EVERY local client (the CLI, the
  # desktop app) mirrors it to the same ~/.claude/projects/<cwd>/ store, so this is
  # client-agnostic. A spawned worktree (`wt child`, or a nested worktree) never hosts its
  # OWN chat: the conversation lives in the pane that spawned it — the 5th registry field.
  # So when this worktree has no transcript of its own but the parent does, the chat you
  # want is the parent's, not an empty picker here. Falls back to the worktree's own cwd.
  local w="$1" row main parent
  [ -d "$(wt_projdir "$w")" ] && { printf '%s' "$w"; return; }
  [ -f "$WT_REGISTRY" ] || { printf '%s' "$w"; return; }
  row="$(awk -F'\t' -v p="$w" '$4==p{print; exit}' "$WT_REGISTRY" 2>/dev/null)"
  main="$(printf '%s' "$row" | cut -f2)"
  parent="$(printf '%s' "$row" | cut -f5)"
  [ -n "$parent" ] && [ -d "$(wt_projdir "$parent")" ] || { printf '%s' "$w"; return; }
  # Inherit the parent's chat only when the parent is a DIFFERENT context than this
  # worktree's own repo — a genuine spawned child. Two signatures:
  #   1. parent is itself an agent worktree (under WT_BASE) — a nested spawn.
  #   2. parent is a checkout of a DIFFERENT repo — a `wt child` (e.g. a workshop pane
  #      that spawned this sub-repo worktree). The chat is one session in that pane's pile.
  # A plain same-repo worktree's parent is its OWN main checkout, whose transcripts are the
  # user's unrelated on-main work — never hijack resume to that, so it falls through.
  case "$parent" in "$WT_BASE"/*) printf '%s' "$parent"; return ;; esac
  # Cross-repo? Compare the two checkouts' git-common-dirs — both resolved by git, so
  # symlink-consistent (a raw string compare vs the stored path breaks on /var → /private).
  local pcommon mcommon
  pcommon="$(git -C "$parent" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || pcommon=""
  mcommon="$(git -C "$main" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || mcommon=""
  [ -n "$pcommon" ] && [ "$pcommon" != "$mcommon" ] && { printf '%s' "$parent"; return; }
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

branch_landed() { # branch_landed <main> <branch> -> 0 if it has ALREADY landed; read-only
  local main="$1" b="$2" base slug state head tip
  # Ancestry-merged (fast-forward / merge-commit / rebase that kept the commits):
  # offline, always-safe. This is the same test `git branch -d` gates on.
  base="$(git -C "$main" symbolic-ref --short HEAD 2>/dev/null || echo main)"
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
  # Offline ancestry-merge: -d refuses anything not fully in the base, so it is
  # always safe and needs no network.
  git -C "$main" branch -d "$b" >/dev/null 2>&1 && return 0
  # Otherwise force-delete only when branch_landed confirms a squash/rebase merge.
  branch_landed "$main" "$b" || return 1
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

wt_for_branch() { # wt_for_branch <main> <branch> — where git says the branch is checked out
  # resume_rows can hand us a SYNTHESIZED path for a branch it only learned about
  # from `git branch --list worktree-*` (an orphan worktree made by a raw
  # `git worktree add`, or a `wt child` bucket keyed by owner-repo slug). That path
  # usually doesn't exist, so the sweep files a very-much-live worktree as "parked"
  # and reaps its branch under the running pane. git itself knows the truth.
  git -C "$1" worktree list --porcelain 2>/dev/null |
    awk -v b="refs/heads/$2" '/^worktree /{p=substr($0,10)} $0=="branch "b{print p; exit}'
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
  local mode="${1:-parked}" main branch wt selftop real
  REAPED=""
  SKIPPED_LIVE=""
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
    # Prefer the checkout git actually has for this branch over resume_rows' guess,
    # so a real live worktree is never filed as parked (see wt_for_branch).
    real="$(wt_for_branch "$main" "$branch")"
    [ -n "$real" ] && wt="$real"
    if [ -e "$wt/.git" ]; then
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
  reg_put "$name" "$(git_main "$base")" "worktree-$name" "$dir" "$base" || true
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
  local tmain
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
  reg_put "$name" "$tmain" "worktree-$name" "$dir" "$PWD" || true
  say "created $(basename "$tmain") worktree '$name' → $dir"
  echo "$dir"   # ONLY the path on stdout, so callers can: cd "$(wt child …)"
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
  local porcelain
  porcelain="$(git -C "$dir" status --porcelain 2>/dev/null || true)"
  if [ -n "$porcelain" ]; then
    if printf '%s\n' "$porcelain" | grep -qv '^??' \
       || [ -z "$branch" ] || ! branch_landed "$main" "$branch"; then
      wip_commit "$dir" "wip: auto-saved on pane close ($(date '+%Y-%m-%d %H:%M'))" || true
    fi
  fi
  git -C "$main" worktree remove "$dir" 2>/dev/null \
    || git -C "$main" worktree remove --force "$dir"
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
  local rows="" raw="" real="" d m b mdir ob
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
  while IFS= read -r mdir; do
    [ -n "$mdir" ] || continue
    for ob in $(git -C "$mdir" branch --list 'worktree-*' --format='%(refname:short)' 2>/dev/null); do
      rows+="$mdir"$'\t'"$ob"$'\t'"$WT_BASE/$(basename "$mdir")/${ob#worktree-}"$'\n'
    done
  done <<<"$(printf '%s' "$real" | awk 'NF && !s[$0]++')"
  printf '%s' "$rows" | awk -F'\t' 'NF>=3 && !seen[$1 FS $2]++'
}

cmd_list() {
  # Self-heal: reap parked branches whose PR has since merged. Parked-only, so it
  # never disturbs a live checkout that may still have an open pane; the risky live
  # sweep is opt-in via `wt reap`. Best-effort — a network hiccup must not break the
  # listing.
  reap_sweep parked || true
  [ -n "${REAPED:-}" ] && say "swept $(printf '%s' "$REAPED" | grep -c .) merged worktree(s)"
  say "agent worktrees you can resume (wt <name>, or <repo>/<name>)"

  # Gather every row FIRST, so columns can be sized to their real content and the
  # commit message trimmed to whatever width the terminal actually has. The old
  # layout hardcoded 12/26-wide repo/name columns and a 56-char commit slice —
  # ~110 columns total — which wrapped into a mess in a narrow pane. Now repo/name
  # size to content (capped), and the commit fills the remaining width, so the
  # listing stays on one line per worktree however narrow the pane.
  local main branch wt
  local -a r_repo=() r_nm=() r_state=() r_chat=() r_last=()
  while IFS=$'\t' read -r main branch wt; do
    [ -n "$branch" ] || continue
    git -C "$main" show-ref -q --verify "refs/heads/$branch" 2>/dev/null || continue
    r_repo+=("$(basename "$main")")
    r_nm+=("${branch#worktree-}")
    if [ -e "$wt/.git" ]; then r_state+=("live"); else r_state+=("parked"); fi
    if [ -d "$(wt_projdir "$wt")" ]; then r_chat+=("yes")
    elif [ "$(chat_home "$wt")" != "$wt" ]; then r_chat+=("par")   # inherited from its wt-child parent
    else r_chat+=("·"); fi
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

  # Drop the (narrow, low-signal) chat column first when space is tight, then let
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
    printf "$hdr" "repo" "name" "state" "chat" "last commit"
    for i in "${!r_repo[@]}"; do
      printf "$hdr" "$(fit "${r_repo[$i]}" "$rw")" "$(fit "${r_nm[$i]}" "$nw")" \
        "${r_state[$i]}" "${r_chat[$i]}" "$(fit "${r_last[$i]}" "$lastw")"
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
  local rrepo="" rname="$want" sel="" matches=0 main branch wt
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
  if [ -e "$wt/.git" ]; then
    say "'$branch' is still live at $wt"
  else
    say "rebuilding checkout for $branch → $wt"
    mkdir -p "$(dirname "$wt")"
    git -C "$main" worktree add "$wt" "$branch" >&2
    reg_put "${branch#worktree-}" "$main" "$branch" "$wt" || true
  fi
  # A spawned worktree (`wt child`, nested) has no chat of its own — resume the parent
  # session that spawned it (see chat_home). The checkout above is still rebuilt so the
  # branch's files are on disk; we just cd to where the transcript lives to reopen it.
  local chat; chat="$(chat_home "$wt")"
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
  if [ -t 1 ] && command -v claude >/dev/null 2>&1; then
    say "reopening the chat …"
    cd "$chat" && exec claude --resume
  else
    say "checkout ready. Reopen the chat with:"
    printf '    cd %q && claude --resume\n' "$chat"
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
}

case "${1:-}" in
create) cmd_create ;;
remove) cmd_remove ;;
child) cmd_child "${2:-}" "${3:-}" ;;
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

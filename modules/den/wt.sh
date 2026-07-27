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
#                     merged live checkouts (dirty/unmerged/your-own-pane are kept).
#                     The idempotent backstop for when a pane ends WITHOUT firing
#                     the remove hook (a manual pane close, a reboot, a crash) or
#                     for `wt child` checkouts, which the hook never reaps.
#   wt child <repo>   make a worktree of ANOTHER repo as a child of THIS pane —
#                     for cross-repo work (a workshop pane editing a sub-repo).
#                     Registers it so its PR shows in the statusline; prints the
#                     new checkout path, so: cd "$(wt child ~/code/…/rice)"
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

git_main() { # git_main <dir> — the MAIN checkout backing any worktree of a repo
  dirname "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
}

wt_projdir() { # wt_projdir <abs-cwd> — Claude Code's transcript dir for that cwd
  # Claude encodes the project by its cwd, replacing every '/' and '.' with '-'.
  printf '%s/.claude/projects/%s' "$HOME" "$(printf '%s' "$1" | sed 's/[/.]/-/g')"
}

chat_home() { # chat_home <wt_path> — echo the cwd whose Claude chat this worktree resumes
  # Claude keys a transcript to the cwd it ran in. A `wt child` worktree is spawned FROM
  # another pane and never hosts its OWN chat — the conversation lives in that parent
  # pane's cwd (the 5th registry field). So when this worktree has no transcript of its
  # own but the parent does, the chat you actually want is the parent's, not an empty
  # picker here. Falls back to the worktree's own cwd.
  local w="$1" parent
  [ -d "$(wt_projdir "$w")" ] && { printf '%s' "$w"; return; }
  [ -f "$WT_REGISTRY" ] || { printf '%s' "$w"; return; }
  parent="$(awk -F'\t' -v p="$w" '$4==p{print $5; exit}' "$WT_REGISTRY" 2>/dev/null)"
  # Only inherit a chat from a parent that is ITSELF an agent worktree (under WT_BASE):
  # that's the `wt child` / nested-spawn signature. A normal worktree's parent is a MAIN
  # checkout, whose transcript is the user's unrelated work on main — never hijack to it.
  case "$parent" in
    "$WT_BASE"/*) [ -d "$(wt_projdir "$parent")" ] && { printf '%s' "$parent"; return; } ;;
  esac
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

# reap_sweep <parked|all> — the idempotent counterpart to the WorktreeRemove hook.
# The hook only fires on Claude's own graceful worktree teardown; anything else
# that ends a pane (a manual `zellij close-pane`, a reboot, a crash, ⌘C churn) or
# a `wt child` cross-repo checkout bypasses it, so merged worktrees pile up. This
# sweep reaps them independent of pane lifecycle. Sets REAPED to a newline list of
# "<name> (<repo>)" for what it dropped.
#   parked  — reap ONLY branches whose checkout is already gone (zero risk); the
#             self-heal that runs on every `wt` list.
#   all     — also reap LIVE checkouts, but only when clean AND landed AND not the
#             pane we're standing in; dirty/unmerged live work is always left.
reap_sweep() {
  local mode="${1:-parked}" main branch wt selftop
  REAPED=""
  selftop="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
  while IFS=$'\t' read -r main branch wt; do
    [ -n "$branch" ] || continue
    git -C "$main" show-ref -q --verify "refs/heads/$branch" 2>/dev/null || continue
    if [ -e "$wt/.git" ]; then
      # A live checkout. Parked-only mode leaves every live checkout untouched.
      [ "$mode" = "all" ] || continue
      [ "$wt" = "$selftop" ] && continue                                   # never our own pane
      [ -z "$(git -C "$wt" status --porcelain 2>/dev/null)" ] || continue  # dirty → leave for a human
      branch_landed "$main" "$branch" || continue                          # unmerged live work → leave
      git -C "$main" worktree remove "$wt" 2>/dev/null || continue         # free the branch, then reap it
    fi
    if reap_branch "$main" "$branch"; then
      reg_del "$wt"
      REAPED+="${branch#worktree-} ($(basename "$main"))"$'\n'
    fi
  done <<<"$(resume_rows)"
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

cmd_remove() { # [WorktreeRemove hook] JSON on stdin — retire without losing work
  local json dir main branch
  json="$(cat)"
  dir="$(hook_field "$json" worktree_path path)"
  main="$(git_main "$dir")"
  branch="$(git -C "$dir" branch --show-current 2>/dev/null || true)"
  # A --force remove would silently discard UNCOMMITTED edits. Committed work
  # always survives on the branch; park the dirty remainder there too, as a WIP
  # commit, so closing a pane can never cost you work. gpgsign off: this hook is
  # non-interactive, and a signing prompt here would hang the whole teardown.
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
      git -C "$dir" add -A >/dev/null 2>&1 || true
      git -C "$dir" -c commit.gpgsign=false \
        commit -q -m "wip: auto-saved on pane close ($(date '+%Y-%m-%d %H:%M'))" \
        >/dev/null 2>&1 || true
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
  # A `wt child` worktree has no chat of its own — resume the parent session that
  # spawned it (see chat_home). The checkout above is still rebuilt so the branch's
  # files are on disk; we just cd to where the transcript lives to reopen it.
  local chat; chat="$(chat_home "$wt")"
  if [ "$chat" != "$wt" ]; then
    say "no chat here — this worktree was spawned via 'wt child'; its conversation lives in $chat"
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
  say "reaping landed worktrees (parked, plus clean & merged live checkouts) …"
  reap_sweep all
  if [ -n "${REAPED:-}" ]; then
    printf '%s' "$REAPED" | while IFS= read -r r; do
      [ -n "$r" ] && printf '\033[38;5;103m  ✓ reaped %s\033[0m\n' "$r" >&2
    done
  else
    say "nothing to reap — every worktree is unmerged, dirty, or your own pane."
  fi
}

case "${1:-}" in
create) cmd_create ;;
remove) cmd_remove ;;
child) cmd_child "${2:-}" "${3:-}" ;;
resume) cmd_resume "${2:-}" ;;
reap | gc) cmd_reap ;;
list | ls) cmd_list ;;
"" | -h | --help | help) [ "${1:-}" = "" ] && cmd_list || sed -n '2,28p' "$0" | sed '/^#!/d; s/^# \{0,1\}//' ;;
*) cmd_resume "$1" ;; # bare token → treat as a worktree name to resume
esac

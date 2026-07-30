#!/bin/bash
# pounce: name = Spawn Agent
# pounce: description = Start a Claude Code session on a named worktree of any repo
# pounce: icon = sparkles
# pounce: submenu = true
#
# The palette front door to `claude --worktree`. Pick a repo, type what you want
# done, and this creates a worktree named after the task and drops a Claude Code
# session into it, in the `main` zellij session's tab for that repo.
#
# Why it exists: the same thing by hand is caps→t to a terminal, find the repo's
# tab, cd, ⌘C for an agent pane, then type the prompt — and the worktree ends up
# with whatever name Claude generated (`luminous-twirling-codd`), which is the
# name you then have to recognise in `wt`, in the statusline, and on the branch.
# Naming it from the prompt is the whole point; the palette is just the shortest
# path to doing it.
#
# The worktree is made by `wt spawn`, NOT by `claude --worktree`: a palette
# command has no pane, so it must not be recorded as anybody's child session (see
# wt.sh's cmd_spawn). Claude is then started in that checkout like any other
# directory — no hook fires, nothing else to keep in sync.
#
# Repos come from $NEBELHAUS_REPO_ROOTS (colon-separated, default ~/code and the
# usual siblings), scanned one and two levels deep for a main checkout — two so a
# workshop-style parent dir full of repos resolves to its children — plus every
# repo `wt` already knows, so a repo outside those roots that you have agent'd
# before stays reachable.

# A launchd GUI agent's PATH is bare; resolve our tools (wt, zellij, claude, git,
# open, osascript, pounce) explicitly — the same prelude add-app.sh uses.
export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOTS="${NEBELHAUS_REPO_ROOTS:-$HOME/code:$HOME/src:$HOME/Developer:$HOME/Projects}"
WT_REGISTRY="${CLAUDE_WT_BASE:-$HOME/.cache/claude-worktrees}/registry.tsv"
SESSION="${NEBELHAUS_ZELLIJ_SESSION:-main}"

field() { printf '%s' "$1" | cut -f"$2"; }
notice() {
  printf '%s\t%s\t%s\n' "$1" "$2" "${3:-exclamationmark.triangle}" \
    | pounce -p "Spawn Agent" -i "sparkles" >/dev/null
}

for tool in wt zellij claude; do
  command -v "$tool" >/dev/null 2>&1 && continue
  notice "$tool is unavailable" "Rebuild nebelhaus, then try again"
  exit 1
done

# ── which repo ────────────────────────────────────────────────────────────
# One line per candidate: "<mtime>\t<main checkout path>". Sorting on the .git
# mtime puts whatever you touched last on top, which is nearly always the one
# you meant. The depth is 3 because a root's repos sit at depth 2 (~/code/foo/.git)
# and a parent dir full of repos puts its children at depth 3
# (~/code/workshop/pounce/.git). Only a .git DIRECTORY is a main checkout — a
# .git *file* means a linked worktree, which must never be the base of another.
candidates="$(mktemp)" || exit 1
trap 'rm -f "$candidates"' EXIT

IFS=':' read -r -a roots <<<"$ROOTS"
for root in "${roots[@]}"; do
  [ -d "$root" ] || continue
  find "$root" -mindepth 1 -maxdepth 3 -type d -name .git -prune 2>/dev/null
done | sed 's|/\.git$||' >>"$candidates"

# Repos wt already knows (registry field 2 is each worktree's main checkout).
[ -f "$WT_REGISTRY" ] && cut -f2 "$WT_REGISTRY" 2>/dev/null >>"$candidates"

list="$(
  sort -u "$candidates" | while IFS= read -r repo; do
    [ -d "$repo/.git" ] || continue
    stamp="$(stat -f '%m' "$repo/.git" 2>/dev/null)" || continue
    branch="$(git -C "$repo" branch --show-current 2>/dev/null)"
    open="$(awk -F'\t' -v m="$repo" '$2 == m' "$WT_REGISTRY" 2>/dev/null | wc -l | tr -d ' ')"
    # Prefix REMOVAL, not `${repo/#$HOME/~}`: the anchored-replacement spelling
    # silently returns the string unchanged on bash 5.3 (it still works on the
    # 3.2 at /bin/bash), so every row would show an absolute path on one and a
    # tilde on the other depending on which bash ran the command.
    desc="~${repo#$HOME}"
    [ -n "$branch" ] && desc="$desc · on $branch"
    [ "${open:-0}" -gt 0 ] && desc="$desc · $open worktree(s) open"
    printf '%s\t%s\t%s\t%s\t\tRepositories\t%s\n' \
      "$stamp" "$(basename "$repo")" "$desc" "folder.badge.gearshape" "$repo"
  done | sort -rn | cut -f2-
)"

if [ -z "$list" ]; then
  notice "No repositories found" "Set NEBELHAUS_REPO_ROOTS, or clone something under ~/code"
  exit 0
fi

repo_sel="$(printf '%s\n' "$list" | pounce -p "Spawn Agent — which repo?" -i "sparkles")"
[ -z "$repo_sel" ] && exit 0
repo_name="$(field "$repo_sel" 2)"
repo="$(field "$repo_sel" 7)"
# Free text that matched no row has an empty payload — there is nothing sensible
# to spawn on, so treat it as a miss rather than guessing a repo.
[ -n "$repo" ] && [ -d "$repo/.git" ] || exit 0

# ── what should it do ─────────────────────────────────────────────────────
# --chain: Enter here starts a git worktree add and a session spawn, so pounce
# holds the window with its loading skeleton instead of fading out and back in.
prompt_sel="$(printf '' | pounce --chain -p "What should the agent do in $repo_name?" -i "sparkles")"
[ -z "$prompt_sel" ] && exit 0
prompt="$(field "$prompt_sel" 2)"

# The palette's field is one line, and so is a TSV row — but a paste can still
# carry newlines and tabs, which would split the prompt across fields and lose
# everything after the first. Fold every run of whitespace into one space so a
# pasted paragraph, a stack trace, or a diff arrives whole and on one line.
prompt="$(printf '%s' "$prompt" | tr '\n\r\t' '   ' | sed 's/  */ /g; s/^ //; s/ $//')"
[ -z "$prompt" ] && exit 0

# ── name the worktree after the task ──────────────────────────────────────
# The naming win: a branch called `fix-notch-clipping` instead of Claude's
# generated `luminous-twirling-codd`. First few words, slugged; `wt spawn` takes
# the next free suffix if that name is already in use.
slug="$(printf '%s' "$prompt" \
  | tr '[:upper:]' '[:lower:]' \
  | sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//')"
# Trim to whole words, and only when it actually overflowed — cutting
# unconditionally would turn a two-word prompt into one word.
if [ "${#slug}" -gt 32 ]; then
  slug="$(printf '%s' "$slug" | cut -c1-32 | sed 's/-[^-]*$//; s/-$//')"
fi
[ -n "$slug" ] || slug="agent"

# ── make sure there is somewhere to put it ────────────────────────────────
# Ghostty autostarts the `main` session; wait for it exactly like
# hearth/zellij/pounce-terminal.sh does, and only create the worktree once we
# know we have a session to spawn into — a worktree with no pane is litter.
if ! pgrep -x "Ghostty" >/dev/null; then
  open -a "Ghostty"
  sleep 2.0
fi
if ! zellij list-sessions 2>/dev/null | grep -q "$SESSION"; then
  for _ in $(seq 1 10); do
    sleep 0.5
    zellij list-sessions 2>/dev/null | grep -q "$SESSION" && break
  done
fi
if ! zellij list-sessions 2>/dev/null | grep -q "$SESSION"; then
  notice "No '$SESSION' zellij session" "Open Ghostty and let it start, then spawn again"
  exit 1
fi

dir="$(wt spawn "$repo" "$slug" 2>/dev/null)"
if [ -z "$dir" ] || [ ! -d "$dir" ]; then
  notice "Could not create the worktree" "Check that $repo_name has a commit to branch from"
  exit 1
fi
name="$(basename "$dir")"

# ── land it in the repo's tab ─────────────────────────────────────────────
# A tab already named after the repo is where that repo's work lives, so join it
# rather than opening a second one. Otherwise make the tab, named for the REPO —
# zellij would otherwise title a new tab after its cwd or its running command,
# and `luminous-twirling-codd` or `claude` is not a tab you can find later.
osascript -e 'tell application "Ghostty" to activate' >/dev/null 2>&1
if zellij -s "$SESSION" action query-tab-names 2>/dev/null | grep -qxF "$repo_name"; then
  zellij -s "$SESSION" action go-to-tab-name "$repo_name" >/dev/null 2>&1
  spawned=$(zellij -s "$SESSION" action new-pane --cwd "$dir" --name "$name" -- claude "$prompt")
else
  spawned=$(zellij -s "$SESSION" action new-tab --name "$repo_name" --cwd "$dir" -- claude "$prompt")
fi

if [ -z "$spawned" ]; then
  # Nothing is holding the checkout, so take it back rather than leave a worktree
  # nobody asked for. The branch goes with it — there is no work in it yet.
  git -C "$repo" worktree remove --force "$dir" >/dev/null 2>&1
  git -C "$repo" branch -D "worktree-$name" >/dev/null 2>&1
  notice "Could not open a pane" "The worktree was removed; nothing changed"
  exit 1
fi

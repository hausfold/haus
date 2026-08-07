#!/bin/bash
# pounce: name = Spawn Agent
# pounce: description = Start your default coding agent on a named worktree of any repo
# pounce: icon = sparkles
# pounce: submenu = true
#
# The palette front door to a named agent worktree. Pick a repo, type what you
# want done, and this creates a worktree named after the task and drops the
# configured default (Claude Code, Codex, or OpenCode) into it, in the `main`
# zellij session's tab for that repo.
#
# Why it exists: the same thing by hand is caps→t to a terminal, find the repo's
# tab, cd, ⌘A for an agent pane, then type the prompt — and the worktree ends up
# with whatever name Claude generated (`luminous-twirling-codd`), which is the
# name you then have to recognise in `holt`, in the statusline, and on the branch.
# Naming it from the prompt is the whole point; the palette is just the shortest
# path to doing it.
#
# The worktree is made by `holt spawn`, NOT by a client-native worktree command: a
# palette command has no pane, so it must not be recorded as anybody's child
# session (see holt's Spawn). Claude is then started in that checkout like any
# other directory — no hook fires, nothing else to keep in sync.
#
# Repos come from $NEBELHAUS_REPO_ROOTS (colon-separated, default ~/code and the
# usual siblings), scanned one and two levels deep for a main checkout — two so a
# workshop-style parent dir full of repos resolves to its children — plus every
# repo `holt` already knows, so a repo outside those roots that you have agent'd
# before stays reachable.
#
# ── the prompt step's four Returns ────────────────────────────────────────────
#
#   ↵    spawn on what you typed
#   ⇧↵   newline — the task is often a list, not a sentence
#   ⌘↵   capture a screenshot first, then spawn (this used to be a whole second
#        palette entry, "Spawn Agent with Screenshot")
#   ⌥↵   your drafts
#
# ⌘↵ and ⌥↵ fire on an EMPTY box too, which is the point of both: opening your
# drafts is what you do INSTEAD of typing, and a screenshot is often the subject
# you are about to describe, so pointing at it first is the natural order. ⌘↵
# with nothing typed captures and hands the box back with the shot attached;
# only plain ↵ on an empty box means "never mind" and dismisses.
#
# ⌘↵ replaces the separate screenshot command. That command's own comment gave
# the right reason it had to be separate: an "Attach screenshot" ROW in the
# free-text picker is fuzzy-matched, so a task merely CONTAINING the word
# "screenshot" selected it on Return. An action-bar binding is not a row and
# cannot be matched — so the two entries collapse into one, and you write the
# task first and point at the thing second, which is the more natural order.
#
# Drafts are ⌥↵ for exactly the same reason, and not rows in this step.
#
# Why drafts exist at all: the palette dismisses on any click into another app,
# and this is the one step in the whole rice that asks you to type a paragraph.
# Losing it to a stray click is unrecoverable — the text existed nowhere else.
# `--draft` files it on every dismissal; ⌥↵ hands it back through `--query`, in
# the box, editable, rather than just re-running it.

# A launchd GUI agent's PATH is bare; resolve our tools (holt, zellij, git,
# open, osascript, pounce) explicitly — the same prelude add-app.sh uses.
export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOTS="${NEBELHAUS_REPO_ROOTS:-$HOME/code:$HOME/src:$HOME/Developer:$HOME/Projects}"
WT_REGISTRY="${CLAUDE_WT_BASE:-$HOME/.cache/claude-worktrees}/registry.tsv"
SESSION="${NEBELHAUS_ZELLIJ_SESSION:-main}"
# One drafts store for the command, not one per repo: you often start typing
# before you have decided which repo it belongs to.
DRAFT_KEY="spawn-agent"
SHOTS="$HOME/.cache/nebelhaus-agent-screenshots"

field() { printf '%s' "$1" | cut -f"$2"; }
# A free-text commit is "<action>\t<text>" where the TEXT may now contain
# newlines (⇧↵) — so the action is field 1 of the FIRST line, and the payload is
# everything after that first tab, newlines and all. `field 2` would keep working
# by accident here and break the moment a prompt's later line contained a tab.
action_of() { printf '%s' "$1" | /usr/bin/head -n1 | cut -f1; }
payload_of() { printf '%s' "$1" | /usr/bin/sed $'1s/^[^\t]*\t//'; }
notice() {
  printf '%s\t%s\t%s\n' "$1" "$2" "${3:-exclamationmark.triangle}" \
    | pounce -p "Spawn Agent" -i "sparkles" >/dev/null
}

for tool in holt zellij; do
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

# Repos holt already knows (registry field 2 is each worktree's main checkout).
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

agent="$(holt agent default 2>/dev/null)"
[ -n "$agent" ] || agent="claude"
# Belt to the assertion's braces. `nebelhaus.agents.clients` makes the default
# client present at BUILD time, but this script runs long after that — the
# client can still be missing on a machine driving `holt` without the rice, or
# with a hand-managed install that moved. Checking here, before anything is
# created, is the difference between a toast and the old failure: `holt spawn`
# succeeds, the pane opens, and only `holt agent start` inside it finds nothing —
# leaving a dead pane and a worktree nobody asked for.
if ! command -v "$agent" >/dev/null 2>&1; then
  notice "$agent is not installed" "Add it to nebelhaus.agents.clients, or change agents.default"
  exit 1
fi

repo_sel="$(printf '%s\n' "$list" | pounce -p "Spawn Agent — which repo?" -i "sparkles")"
[ -z "$repo_sel" ] && exit 0
repo_name="$(field "$repo_sel" 2)"
repo="$(field "$repo_sel" 7)"
# Free text that matched no row has an empty payload — there is nothing sensible
# to spawn on, so treat it as a miss rather than guessing a repo.
[ -n "$repo" ] && [ -d "$repo/.git" ] || exit 0

# ── what should it do ─────────────────────────────────────────────────────
#
# --chain enter,opt: BOTH of those Returns are answered by another `pounce`
# (the spawn's own loading window, or the drafts list), so the window holds its
# skeleton instead of fading out and back in. ⌘↵ is deliberately NOT chained:
# its next act is `screencapture -i`, which needs the palette off the screen —
# a crosshair over a loading spinner is not a UI.
#
# --draft: every dismissal that isn't a commit keeps the text. This is the whole
# insurance policy against the click-away.
ask() {
  # $1: text the box opens with (a draft coming back for editing, or empty).
  printf '' | pounce --chain enter,opt \
    --draft "$DRAFT_KEY" \
    --actions "Spawn|shift:New line|cmd:With a screenshot|opt:Drafts" \
    --query "$1" \
    -p "What should the agent do in $repo_name?" -i "sparkles"
}

# ── drafts ────────────────────────────────────────────────────────────────
# Rows built from `pounce drafts … list`, which is one line per draft by
# construction (previews are whitespace-folded there, not here) — so this stays
# an honest `while read`. Field 6 carries the index back; `get` then hands over
# the real multi-line text.
draft_picker() {
  local rows sel idx
  rows="$(pounce drafts "$DRAFT_KEY" list 2>/dev/null | while IFS=$'\t' read -r i preview age; do
    printf '%s\t%s\t%s\tUse|cmd:Delete|opt:Clear all\t\t%s\n' \
      "$preview" "$age" "text.quote" "$i"
  done)"
  if [ -z "$rows" ]; then
    notice "No drafts yet" "Text you type here is kept if you dismiss the box" "tray"
    return 1
  fi
  sel="$(printf '%s\n' "$rows" | pounce -p "Drafts — $DRAFT_KEY" -i "tray.full")"
  [ -z "$sel" ] && return 1
  # A row commits as "<action>\t<the whole row>", so every column is shifted by
  # one: field 1 is the action and the index written as the row's 6th field
  # arrives as the 7th. Free text typed here matches no row and carries no
  # index — treat that as a miss rather than acting on draft 0.
  idx="$(field "$sel" 7)"
  case "$idx" in ''|*[!0-9]*) return 1 ;; esac
  case "$(field "$sel" 1)" in
    cmd) pounce drafts "$DRAFT_KEY" rm "$idx" >/dev/null 2>&1; return 1 ;;
    opt) pounce drafts "$DRAFT_KEY" clear >/dev/null 2>&1; return 1 ;;
  esac
  pounce drafts "$DRAFT_KEY" get "$idx"
}

# ⌥↵ leaves the box for the drafts list and comes back to it, so this loops
# rather than falling through: deleting a draft, or clearing them all, has to
# return you to what you were typing instead of ending the spawn.
image=""
seed=""
while :; do
  prompt_sel="$(ask "$seed")"
  # Dismissed. A screenshot captured on the way here belongs to a spawn that
  # never happened — drop it rather than let the cache collect orphans.
  if [ -z "$prompt_sel" ]; then
    [ -n "$image" ] && rm -f "$image"
    exit 0
  fi
  action="$(action_of "$prompt_sel")"
  prompt="$(payload_of "$prompt_sel")"

  case "$action" in
    opt)
      # Leaving the box deliberately is a COMMIT, not a dismissal, so the daemon
      # files nothing — keep it by hand or ⌥↵ would be the one way to lose a
      # prompt now that every other exit preserves it.
      printf '%s' "$prompt" | pounce drafts "$DRAFT_KEY" save >/dev/null 2>&1
      if picked="$(draft_picker)"; then
        seed="$picked"
      else
        seed="$prompt"
      fi
      continue
      ;;
    cmd)
      # macOS's own interactive area capture — no second implementation of the
      # crosshair to keep in sync with the OS. Cancelling it is not cancelling
      # the spawn: you get the box back, text intact.
      mkdir -p "$SHOTS"
      shot="$SHOTS/screenshot-$(date +%Y%m%d-%H%M%S).png"
      if ! /usr/sbin/screencapture -i "$shot" || [ ! -s "$shot" ]; then
        rm -f "$shot"; seed="$prompt"; continue
      fi
      # A second capture supersedes the first — only one image is ever attached,
      # so the one it replaces has no way back and no reason to survive.
      [ -n "$image" ] && rm -f "$image"
      image="$shot"
      # ⌘↵ on an EMPTY box is "point at the thing FIRST, then say what to do with
      # it" — the natural order when the screenshot is the subject. Go back to
      # the box holding the capture instead of spawning on an empty prompt.
      if [ -z "$(printf '%s' "$prompt" | tr -d '[:space:]')" ]; then
        seed="$prompt"; continue
      fi
      ;;
  esac
  break
done

# Only \r and stray leading/trailing space go; newlines and tabs are the user's
# now that ⇧↵ can produce them, and `holt agent start` receives the prompt as a
# single argv element, so a list survives as a list all the way into the client.
prompt="$(printf '%s' "$prompt" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
if [ -z "$prompt" ]; then
  [ -n "$image" ] && rm -f "$image"
  exit 0
fi

# ── name the worktree after the task ──────────────────────────────────────
# The naming win: a branch called `bar-pill-flickers` instead of Claude's
# generated `luminous-twirling-codd`. `holt spawn` takes the next free suffix if
# that name is already in use.
#
# The FIRST few words are not the name — "can you look into why the bar pill
# flickers" would name itself `can-you-look-into`, which says nothing. Dropping
# the words that carry no identity and keeping the next four, in order, is what
# turns a prefix into a name.
#
# Deliberately not asking a model for one. `claude -p --model haiku` gives a
# better name (`bar-pill-flicker-fix`), but it measured 9.4s cold even with
# slash-commands and MCP disabled — nine seconds of frozen palette between Enter
# and the pane, every single spawn, to improve a string you can rename later.
STOPWORDS=" a about all also an and any are as at be been being but by can could did do does doing done for from get give go going had has have how i if in into is it its just let make me my need needs no not now of on once only or our out over please put should so some still such take than that the their them then there these they this those to too try up us use want was way we were what when where which while who why will with would you your "

slug=""
kept=0
for word in $(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' ' '); do
  [ "${#word}" -ge 2 ] || continue
  case "$STOPWORDS" in *" $word "*) continue ;; esac
  slug="${slug:+$slug-}$word"
  kept=$((kept + 1))
  [ "$kept" -ge 4 ] && break
done
# Every word was a stopword ("can you have a look at this") — a name made of the
# raw words beats no name at all.
if [ -z "$slug" ]; then
  slug="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' \
    | sed 's/--*/-/g; s/^-//; s/-$//')"
fi
# Trim to whole words, and only when it actually overflowed — cutting
# unconditionally would turn a two-word name into one word.
if [ "${#slug}" -gt 40 ]; then
  slug="$(printf '%s' "$slug" | cut -c1-40 | sed 's/-[^-]*$//; s/-$//')"
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

dir="$(holt spawn "$repo" "$slug" "$agent" 2>/dev/null)"
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
agent_args=(agent start "$agent")
# NEBELHAUS_AGENT_IMAGE is still honoured so an external caller can pre-attach a
# file; ⌘↵ above is the in-palette way to the same argument.
[ -n "${image:-}" ] || image="${NEBELHAUS_AGENT_IMAGE:-}"
[ -n "$image" ] && agent_args+=(--image "$image")
# The prompt is ONE argv element even when it spans lines — holt joins argv with
# spaces, so splitting it here is what would flatten a list back into a sentence.
agent_args+=(-- "$prompt")
if zellij -s "$SESSION" action query-tab-names 2>/dev/null | grep -qxF "$repo_name"; then
  zellij -s "$SESSION" action go-to-tab-name "$repo_name" >/dev/null 2>&1
  spawned=$(zellij -s "$SESSION" action new-pane --cwd "$dir" --name "$name" -- holt "${agent_args[@]}")
else
  spawned=$(zellij -s "$SESSION" action new-tab --name "$repo_name" --cwd "$dir" -- holt "${agent_args[@]}")
fi

if [ -z "$spawned" ]; then
  # Nothing is holding the checkout, so take it back rather than leave a worktree
  # nobody asked for. The branch goes with it — there is no work in it yet.
  git -C "$repo" worktree remove --force "$dir" >/dev/null 2>&1
  git -C "$repo" branch -D "worktree-$name" >/dev/null 2>&1
  notice "Could not open a pane" "The worktree was removed; nothing changed"
  exit 1
fi

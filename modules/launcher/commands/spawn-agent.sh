#!/bin/bash
# pounce: name = Spawn Agent
# pounce: description = Start your default coding agent on a named worktree of any repo
# pounce: icon = sparkles
# pounce: submenu = true
#
# The palette front door to a named agent worktree. Pick a repo, type what you
# want done, and this creates a worktree named after the task and drops the
# configured default (Claude Code, Codex or OpenCode) into it, as a LANE: a zmx
# session, and — the moment anything is looking at it — a Ghostty window forced
# to its name, tiled on that repo's own T/<repo> page.
#
# Return files it and gets out of your way: the box closes at once, the lane
# comes up with NO window anywhere, and a banner says so when it is actually
# running. ⌃↵ is the one that opens the window and brings it to you.
#
# Why it exists: the same thing by hand is caps→t to a terminal, cd to the repo,
# ⌃⌘A for a lane, then type the prompt — and the worktree ends up
# with whatever name Claude generated (`luminous-twirling-codd`), which is the
# name you then have to recognise in `scruff`, in the statusline, and on the branch.
# Naming it from the prompt is the whole point; the palette is just the shortest
# path to doing it.
#
# The worktree is made by `scruff spawn`, NOT by a client-native worktree command: a
# palette command has no pane, so it must not be recorded as anybody's child
# session (see scruff's Spawn). Claude is then started in that checkout like any
# other directory — no hook fires, nothing else to keep in sync.
#
# $HAUS_LANE_NAMER is the same shape and arrives the same way (`haus.ai.namer`,
# through the daemon's launchd environment) and decides WHO names the lane, far
# below. It has no hand-run fallback on purpose: reading it out of scruff's own
# config.toml would be scruff's contract reimplemented in a palette command, which
# is the drift this script's spawn block was rewritten to stop. So a hand-run of
# this file names the lane the old way, from the slug. It is also only as fresh
# as the daemon: the plist environment is re-read on agent reload, so for one
# generation after `haus.ai.namer` changes the two can disagree.
#
# Repos come from $HAUS_REPO_ROOTS — colon-separated, written into the pounce
# daemon's launchd environment from `haus.ai.repoRoots`, which is the only way
# it can arrive: a GUI agent inherits nothing from your shell, so the list below
# is a fallback for a hand-run rather than the thing you tune. Each entry is
# read one of two ways, decided by the path itself: an entry that IS a repo is
# offered as itself and never descended into (that is `~/.config/nix`, the
# config flake this Mac is built from, without scanning `~/.config`), and
# anything else is scanned one and two levels deep for a main checkout — two so
# a workshop-style parent dir full of repos resolves to its children. Plus every
# repo `scruff` already knows, so a repo outside those roots that you have agent'd
# before stays reachable.
#
# ── the prompt step's five Returns ────────────────────────────────────────────
#
#   ↵    spawn — in the BACKGROUND: nothing appears anywhere
#   ⇧↵   newline — the task is often a list, not a sentence
#   ⌘↵   capture a screenshot first, then spawn (this used to be a whole second
#        palette entry, "Spawn Agent with Screenshot")
#   ⌃↵   spawn and FOLLOW it: the lane window takes the screen, as it used to
#   ⌥↵   your drafts
#
# ⇧↵ is deliberately NOT in the action bar. `shift` there is hint-only in pounce
# (Items.swift: the field editor inserts the newline itself, whatever the spec
# says), so dropping it costs nothing but the pixels — and four chords across
# the bottom of the box was one more than it could show without crowding.
#
# ── which way round ↵ and ⌃↵ go, and why ──────────────────────────────────────
#
# Background is the DEFAULT, and ⌃↵ is the one that takes the screen. The two
# spawns are the same code path either way — one exported variable,
# HAUS_LANE_BACKGROUND, read by ~/.config/haus/lanes/lane-open.sh — so this is
# purely which one you get for free. The worktree, the branch and the zmx
# session are made exactly as usual in both, and the client starts on the prompt
# in both. The WINDOW is the difference: ⌃↵ opens it now, tiled on T/<repo>, and
# ↵ opens none at all until something goes looking for the lane.
#
# Backgrounding is the right default because of what a spawn IS: you describe a
# task in a sentence and hand it to somebody else. Almost none of those are the
# thing you are about to sit and watch — you keep doing what you were doing and
# visit the lane when it has something to show (⌃⇥, the Lanes palette, the bar's
# agents pill). Making the common case the plain Return means the palette can
# get out of the way completely: box → gone → banner when the lane is up.
#
# Nothing else moves while that happens, and the reason is that a backgrounded
# lane opens NO WINDOW: it is a detached zmx session with the client on its
# prompt, and the window is born the first time you go to it (the banner, the
# agents pill, the Lanes palette — all three end at a properly tiled lane
# window). So there is nothing to flash and nothing to hand focus back to. Two
# earlier attempts to keep a real window and make its birth quiet — `open -g`,
# then a direct exec at a clamped off-screen position — are written up where the
# silence lives, ~/.config/haus/lanes/lane-open.sh; this script only ever set the
# variable. The one thing to know here: a background lane is NOT on T/<repo>
# until you have opened it once.
#
# ⌃↵ is for the spawn you ARE about to work in: the lane window comes to you and
# stays, and there is no notification because you are looking at it.
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

# A launchd GUI agent's PATH is bare; resolve our tools (scruff, zmx, git,
# open, osascript, pounce) explicitly — the same prelude add-app.sh uses.
export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOTS="${HAUS_REPO_ROOTS:-$HOME/code:$HOME/src:$HOME/Developer:$HOME/Projects:$HOME/.config/nix}"
WT_REGISTRY="${CLAUDE_WT_BASE:-$HOME/.cache/claude-worktrees}/registry.tsv"
# One drafts store for the command, not one per repo: you often start typing
# before you have decided which repo it belongs to.
DRAFT_KEY="spawn-agent"
SHOTS="$HOME/.cache/haus-agent-screenshots"

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

# The lane opener is scruff's own `open` seam, installed by the terminal room.
# Checked HERE, before anything is created, for the reason the client check
# below gives: a worktree with nothing to open it is litter.
# NOTE: $OPENER is a PRECONDITION PROBE here and is never executed by this
# script any more — `scruff spawn --prompt` drives the same seam itself, reading
# the path from ~/.config/scruff/config.toml. Checked anyway, and here rather than
# 250 lines down where it is used, because a lane with nothing to open it is
# litter and this is before anything is created.
OPENER="$HOME/.config/haus/lanes/lane-open.sh"
for tool in scruff zmx; do
  command -v "$tool" >/dev/null 2>&1 && continue
  notice "$tool is unavailable" "Rebuild haus, then try again"
  exit 1
done
if [ ! -x "$OPENER" ]; then
  notice "No lane opener" "Rebuild haus — ~/.config/haus/lanes/lane-open.sh is missing"
  exit 1
fi
# scruff has to be new enough to open a lane on a prompt. The lock bump and this
# script move together, but a machine caught mid-ripple — or anyone with an
# older scruff earlier on PATH — would otherwise get "could not create the
# worktree", which points at their repo instead of at the version skew. `--help`
# prints to stderr, hence the redirect.
if ! scruff --help 2>&1 | grep -q -- '--prompt-file'; then
  notice "scruff is too old for Spawn Agent" "Rebuild haus — it needs scruff with --prompt-file"
  exit 1
fi

# Where the spawn path's evidence goes. A launchd GUI agent has no stderr a
# person will ever read, and the toasts below are one line each — so without
# this, scruff's errors, the open seam's refusal reasons and lane-open.sh's own
# output all vanish and every failure looks identical.
LOG="${XDG_CACHE_HOME:-$HOME/.cache}/haus/spawn-agent.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || LOG=/dev/null

# ── which repo ────────────────────────────────────────────────────────────
# One line per candidate: "<mtime>\t<main checkout path>". Sorting on the .git
# mtime puts whatever you touched last on top, which is nearly always the one
# you meant. The depth is 3 because a root's repos sit at depth 2 (~/code/foo/.git)
# and a parent dir full of repos puts its children at depth 3
# (~/code/workshop/pounce/.git). Only a .git DIRECTORY is a main checkout — a
# .git *file* means a linked worktree, which must never be the base of another.
#
# A root that is ITSELF a repo is offered as itself and NOT scanned. That is
# what lets `~/.config/nix` — one repo inside a directory full of things that
# are not repos — be named directly, and it is also the right answer for a root
# that happens to be a checkout: descending would offer its submodules and
# vendored trees as spawn targets, which are not repos you work in.
candidates="$(mktemp)" || exit 1
trap 'rm -f "$candidates"' EXIT

IFS=':' read -r -a roots <<<"$ROOTS"
for root in "${roots[@]}"; do
  # `haus.ai.repoRoots` is written by a person, so `~/code` is the natural
  # spelling — and nothing between the option and here expands it: the value
  # crosses a launchd plist and arrives as a literal. Prefix removal in a
  # `case`, which also answers a bare `~` and needs no tilde on either side of
  # a substitution (see the desc= line below for what that costs).
  case "$root" in
    '~') root="$HOME" ;;
    '~/'*) root="$HOME/${root#\~/}" ;;
  esac
  [ -d "$root" ] || continue
  if [ -d "$root/.git" ]; then
    printf '%s\n' "${root%/}"
    continue
  fi
  find "$root" -mindepth 1 -maxdepth 3 -type d -name .git -prune 2>/dev/null \
    | sed 's|/\.git$||'
done >>"$candidates"

# Repos scruff already knows (registry field 2 is each worktree's main checkout).
[ -f "$WT_REGISTRY" ] && cut -f2 "$WT_REGISTRY" 2>/dev/null >>"$candidates"

list="$(
  sort -u "$candidates" | while IFS= read -r repo; do
    [ -d "$repo/.git" ] || continue
    stamp="$(stat -f '%m' "$repo/.git" 2>/dev/null)" || continue
    branch="$(git -C "$repo" branch --show-current 2>/dev/null)"
    open="$(awk -F'\t' -v m="$repo" '$2 == m' "$WT_REGISTRY" 2>/dev/null | wc -l | tr -d ' ')"
    # Prefix REMOVAL, not `${repo/#$HOME/~}`: the REPLACEMENT half of an
    # anchored substitution is itself tilde-expanded on bash 5.3, so that
    # spelling puts $HOME back where it just took it out and every row shows an
    # absolute path — while the 3.2 at /bin/bash leaves the `~` alone and shows
    # a tilde. Escaping it (`\~`) only swaps which one is wrong: 5.3 gets the
    # tilde, 3.2 gets a literal backslash. Measured on 3.2.57 and 5.3.15.
    desc="~${repo#$HOME}"
    [ -n "$branch" ] && desc="$desc · on $branch"
    [ "${open:-0}" -gt 0 ] && desc="$desc · $open worktree(s) open"
    printf '%s\t%s\t%s\t%s\t\tRepositories\t%s\n' \
      "$stamp" "$(basename "$repo")" "$desc" "folder.badge.gearshape" "$repo"
  done | sort -rn | cut -f2-
)"

if [ -z "$list" ]; then
  notice "No repositories found" "Add a path to haus.ai.repoRoots, or clone something under ~/code"
  exit 0
fi

agent="$(scruff agent default 2>/dev/null)"
[ -n "$agent" ] || agent="claude"
# Belt to the assertion's braces. `haus.ai.clients` makes the default
# client present at BUILD time, but this script runs long after that — the
# client can still be missing on a machine driving `scruff` without the rice, or
# with a hand-managed install that moved. Checking here, before anything is
# created, is the difference between a toast and the old failure: `scruff spawn`
# succeeds, the pane opens, and only `scruff agent start` inside it finds nothing —
# leaving a dead pane and a worktree nobody asked for.
if ! command -v "$agent" >/dev/null 2>&1; then
  notice "$agent is not installed" "Add it to haus.ai.clients, or change haus.ai.default"
  exit 1
fi

repo_sel="$(printf '%s\n' "$list" | pounce -p "Spawn Agent — which repo?" -i "sparkles")"
[ -z "$repo_sel" ] && exit 0
repo_name="$(field "$repo_sel" 2)"
repo="$(field "$repo_sel" 7)"
# Free text that matched no row commits as "<action>\t<what you typed>" and
# carries no path in field 7 — there is nothing sensible to spawn on. Say which
# text missed rather than vanishing: a step that closes with no window, no lane
# and no message is indistinguishable from the palette having dropped the
# keystroke, which is exactly how this read from the outside.
if [ -z "$repo" ]; then
  typed="$(payload_of "$repo_sel" | tr '\n\t' '  ')"
  notice "No repo matches “${typed}”" \
    "Add its parent to haus.ai.repoRoots, or spawn there once from a terminal" \
    "folder.badge.questionmark"
  exit 0
fi
# A row WAS picked and its checkout is gone — a repo moved or deleted since the
# list was built, or a stale scruff registry row. Different miss, different words:
# `payload_of` here would hand back the whole tab-joined row.
if [ ! -d "$repo/.git" ]; then
  notice "$repo_name is not there any more" "Nothing at $repo — moved, or removed" \
    "folder.badge.questionmark"
  exit 0
fi

# ── what should it do ─────────────────────────────────────────────────────
#
# --chain opt, and ONLY opt. ⌥↵ is answered by another `pounce` (the drafts
# list) within milliseconds, so the window holds its skeleton instead of fading
# out and straight back in.
#
# Every other Return is unchained, each for its own reason:
#
#   ⌘↵  its next act is `screencapture -i`, which needs the palette off the
#       screen — a crosshair over a loading spinner is not a UI.
#   ↵   the spawn it starts is a BACKGROUND lane: it is gone off to T/<repo>
#       within the second and there is deliberately nothing to look at here.
#       Chaining it parked a skeleton over your work until the 8-second
#       fallback fade — and a skeleton is a lie twice over, because the window
#       is never resized when loading begins, so a tall multi-line prompt left
#       a one-line header with a screenful of half-drawn rows under it. The
#       palette lingers out at once instead, and `haus-notify` says the lane is
#       up when it actually is.
#   ⌃↵  its next act IS a window, so this is the one Return a chain could
#       honestly bridge — `--chain ctrl,opt` would do it. Left unchained on
#       purpose: the skeleton's header is one line tall however tall the box
#       was, so a multi-line prompt hands back a screenful of half-drawn rows,
#       and one behaviour for every Return ("the box goes, then the lane
#       arrives") is worth more than covering a second of dead air. Revisit if
#       a namer adapter ever makes that second into five.
#
# --draft: every dismissal that isn't a commit keeps the text. This is the whole
# insurance policy against the click-away.
ask() {
  # $1: text the box opens with (a draft coming back for editing, or empty).
  printf '' | pounce --chain opt \
    --draft "$DRAFT_KEY" \
    --actions "Spawn|cmd:With a screenshot|ctrl:Spawn and follow|opt:Drafts" \
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
# Background unless ⌃↵ says otherwise — see "which way round ↵ and ⌃↵ go" at the
# top. Set BEFORE the loop and only ever cleared, so a trip out to the drafts
# list and back can't quietly rearm it.
background=1
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
    ctrl)
      # "I'm going to work in this one." Same spawn, one exported variable
      # cleared — so foreground and background are never two code paths that
      # can rot apart.
      background=""
      ;;
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
# now that ⇧↵ can produce them, and the prompt reaches scruff on stdin, so a list
# survives as a list all the way into the client.
prompt="$(printf '%s' "$prompt" | tr -d '\r' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
if [ -z "$prompt" ]; then
  [ -n "$image" ] && rm -f "$image"
  exit 0
fi

# ── name the worktree after the task ──────────────────────────────────────
# The naming win: a branch called `bar-pill-flickers` instead of Claude's
# generated `luminous-twirling-codd`. `scruff spawn` takes the next free suffix if
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

# ── create the lane, and open it ──────────────────────────────────────────
# ONE call. `scruff spawn --prompt` creates the checkout, the branch and the
# registry row, then drives scruff's own `open` seam with the client invocation
# it resolved — which on this machine is the very same
# ~/.config/haus/lanes/lane-open.sh the terminal room writes into
# ~/.config/scruff/config.toml.
#
# It used to be this script's job to build that invocation and export five
# SCRUFF_* variables by hand. That was scruff's contract reimplemented outside
# scruff, and it drifted the moment either side moved: the argv shape (`--` for
# a positional prompt, `--prompt=` for opencode's yargs) and the shell-quoting
# of the command string both lived here, in a palette command, for the one
# caller that happened to need them.
#
# Going through the seam rather than opening a window here is still the whole
# point: one name — holt.<repo>.<lane> — becomes the zmx session, and the Ghostty
# window title AND the tile on T/<repo> whenever a window exists, which is the
# join every other surface (the bar's go-to, Lanes, resort-windows.sh) reads.
#
# The prompt goes in on STDIN, not in argv. A task typed with ⇧↵ spans lines
# and routinely holds quotes and `$`; `--prompt-file -` means it never crosses
# a command line at all, so there is nothing left to quote wrong.
#
# HAUS_AGENT_IMAGE is still honoured so an external caller can pre-attach a
# file; ⌘↵ above is the in-palette way to the same argument.
[ -n "${image:-}" ] || image="${HAUS_AGENT_IMAGE:-}"

# WHO names the lane. A name given to `scruff spawn` always wins — the namer is
# only ever asked for a lane that has none — so passing "$slug" unconditionally
# is the same as saying "never ask", which is what this command meant for as
# long as asking cost nine seconds (see the slug's own comment above).
#
# An ADAPTER namer changes that trade. `haus.ai.namer = "api"` measured 0.7-1.1s
# for the whole spawn on the machine this was written on, and the answer is a
# name the stopword slug cannot reach: `agents-pill-wedge` out of "the agents
# pill stops updating after the popup is closed twice in a row", where the slug
# gives `agents-pill-stops-updating`. So hand scruff no name and let the brief
# name the lane.
#
# scruff's BUILT-IN namer is excluded, and the exclusion is the load-bearing half:
#
#   - It costs 8-12s (scruff's own namer.go says so), and it is asked BEFORE the
#     worktree exists, so the whole wait lands between Return and the lane.
#     That was nine seconds of frozen palette back when the prompt step was
#     `--chain enter`, and it is the exact reason the slug exists at all. The
#     chain is gone now and the argument is if anything stronger: the box
#     closes at once, so those nine seconds are nine seconds in which NOTHING
#     is on screen and the only sign the spawn took is a banner that hasn't
#     arrived yet.
#   - Its argv is fixed and reads no environment, so it cannot honour the floor
#     below. An offline spawn would drop to scruff's random word pair, which is
#     strictly WORSE than the slug this command has always had.
#
# The slug is not wasted for an adapter namer, it is DEMOTED: SCRUFF_NAMER_FALLBACK
# travels down to it (scruff hands a seam os.Environ() and never sets cmd.Env, so
# the adapter inherits it) and is what the adapter prints when its model can't
# answer. That is a contract between THIS command and a host-written adapter,
# not a scruff feature — scruff neither sets nor reads the variable, it only passes
# the environment through, and an adapter that ignores it degrades to the random
# pair. `haus.ai.namer`'s description states the contract; the built-in is
# excluded here because it provably cannot meet it.
#
# Exported unconditionally — empty unless this spawn set it — for the same
# reason HAUS_LANE_BACKGROUND below is written on every path: nothing stale in
# the launchd environment may become a floor for a spawn that never asked for
# one.
#
# ⚠️ BOTH spellings go out, and this is the one place in the room where that is
# not belt-and-braces. The reader is a hand-written adapter in the operator's
# own ~/.config — a file haus does not ship, cannot see and cannot rewrite — so
# the usual "flip both ends together" does not apply: an adapter written against
# HOLT_NAMER_FALLBACK would simply stop seeing a floor, and the only symptom is
# an offline spawn quietly landing on a random word pair instead of the slug.
# The old spelling comes out once the adapters on this machine have moved (the
# tool's own docs/rename.md §8.1).
case "${HAUS_LANE_NAMER:-}" in
  "" | claude) laneNamer="" ;;
  *) laneNamer="$HAUS_LANE_NAMER" ;;
esac
export SCRUFF_NAMER_FALLBACK="" HOLT_NAMER_FALLBACK=""
set -- spawn "$repo"
if [ -n "$laneNamer" ]; then
  export SCRUFF_NAMER_FALLBACK="$slug" HOLT_NAMER_FALLBACK="$slug"
else
  set -- "$@" "$slug"
fi
set -- "$@" --agent "$agent" --prompt-file -
[ -n "$image" ] && set -- "$@" --image "$image"

# The default, cleared by ⌃↵. Not a scruff flag and not an argument: "don't take
# the screen" is a fact about whether THIS machine opens a window at all, which
# is lane-open.sh's business and nobody else's — scruff only has to carry it, and it
# does, because it hands a seam os.Environ(). Exported even when empty, so
# nothing stale in the launchd environment can silence a ⌃↵ spawn that asked to
# be followed.
export HAUS_LANE_BACKGROUND="${background:-}"

# scruff prints the lane's path on stdout BEFORE it drives the seam, so this
# captures it whether the seam got as far as a session or not — which is what
# the cleanup below needs.
dir="$(printf '%s' "$prompt" | scruff "$@" 2>>"$LOG")"
rc=$?
if [ -z "$dir" ] || [ ! -d "$dir" ]; then
  notice "Could not create the worktree" "Why, in $LOG"
  exit 1
fi
name="$(basename "$dir")"

# rc 0 is a lane that started; anything else means the lane exists with nothing
# on it. 3 is scruff saying no `open` seam is configured — impossible here, since
# the OPENER check up top already refused that case, but it is not this script's
# job to be the only thing standing between a rebuild gap and silent litter.
#
# This covers the seam REFUSING, not the lane failing later. A ⌃↵ spawn's last
# act is `open -na`, which returns the moment LaunchServices accepts it; a
# background spawn's is `zmx run -d`, which returns as soon as the session is up.
# Either way nothing after that — the launcher script, `zmx attach`, the client
# itself — can reach this exit status. Those failures are caught where they
# happen instead: lane-open.sh's hold keeps a non-zero client exit on screen (or,
# for a background lane, in the session's scrollback) rather than letting it
# flash shut, which is the evidence you would otherwise want this branch to
# preserve.
if [ "$rc" -ne 0 ]; then
  # `scruff drop`, not `git worktree remove`: the raw remove takes the checkout
  # and the branch but leaves scruff's REGISTRY ROW, so the lane goes on being
  # listed by `scruff`, `bench status` and the agents pill as a checkout that
  # isn't there. drop is scruff's own verb for "this will never land" — it takes
  # the branch with it and records the reason in `scruff reaped`, so nothing
  # vanishes unrecorded. It refuses (exit 2) if something is genuinely standing
  # in the checkout, and that refusal is the right answer rather than something
  # to force past: this is the one path where the lane might not be empty.
  if scruff drop "$name" >>"$LOG" 2>&1; then
    notice "Could not open the lane" "The lane was dropped; nothing changed"
  else
    notice "Could not open the lane" "Lane '$name' is still here — run scruff"
  fi
  exit 1
fi

# ── say so, when there is nothing to see ──────────────────────────────────
# The default spawn puts nothing on any screen — no window, no tile, nothing to
# glance at — and the palette is already gone by the time scruff finishes, so
# without this, Return on a paragraph you just typed produces nothing you can see
# at all and you are left wondering whether it took. This banner IS the receipt,
# and it fires when the lane genuinely exists rather than when the box closed.
#
# It is a RECEIPT and nothing more — `haus-notify`'s actions are URL-only, so
# there is nothing to click here. The clickable door is scruff's own fin, which
# trill parks when the lane blocks or finishes (`scruff hook notify`, wired in
# terminal/default.nix): that click runs `scruff focus`, which finds no window,
# defers, and comes back through lane-open.sh's foreground path with one tiled on
# T/<repo>. Until the lane says something, the doors are the bar's agents pill
# and the Lanes palette.
#
# ⌃↵ gets none: the lane window is what you are looking at when it lands, and a
# banner about the thing on your screen is noise.
#
# A notification rather than a `notice` toast: `notice` is another pounce
# window, which is a thing appearing in front of you and waiting to be answered
# — the outcome a background spawn is paying to avoid.
if [ -n "${background:-}" ]; then
  # Through haus-notify, so trill draws it when it can and `rules.json` can
  # route it — this is the one banner here that is news rather than a failure,
  # so it is a `pulse` and it threads on the lane name.
  /run/current-system/sw/bin/haus-notify --source haus.lane --kind pulse --symbol play.circle \
    --thread "$name" --title "haus · agent lane" \
    --body "$repo_name — $name is working" >/dev/null 2>&1
fi
# Explicitly, so the spawn's exit status is the spawn's and not a notification's.
exit 0

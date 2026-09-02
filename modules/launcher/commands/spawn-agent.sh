#!/bin/bash
# pounce: name = Spawn Agent
# pounce: description = Start a coding agent on a worktree named after the task
# pounce: icon = sparkles
# pounce: submenu = true
#
# The palette front door to a named agent worktree. Pick a repo, type what you
# want done, and this creates a worktree named after the task and drops the
# configured default (Claude Code, Codex or OpenCode) into it, as a LANE: a zmx
# session, and — the moment anything is looking at it — a Ghostty window forced
# to its name, tiled on that repo's own T/<repo> page.
#
# Return files it and gets out of your way: the box closes at once, the lane's
# window is born off-screen and walked to T/<repo> without ever reaching you,
# and a banner says so when it is actually running — click it and you are taken
# to that page. ⌃↵ is the one that brings you there in the first place.
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
# ── the prompt step's five Returns, and the chip beside them ─────────────────
#
#   ↵    spawn — in the BACKGROUND: the lane's window opens on T/<repo>
#        without ever reaching your screen
#   ⇧↵   newline — the task is often a list, not a sentence
#   ⌘↵   capture a screenshot first, then spawn (this used to be a whole second
#        palette entry, "Spawn Agent with Screenshot")
#   ⌃↵   spawn and FOLLOW it: the lane window takes the screen, as it used to
#   ⌥↵   your drafts
#   ⇥    which client this ONE lane opens in (⇧⇥ backwards)
#
# ⇧↵ is deliberately NOT in the action bar. `shift` there is hint-only in pounce
# (Items.swift: the field editor inserts the newline itself, whatever the spec
# says), so dropping it costs nothing but the pixels — and four chords across
# the bottom of the box was one more than it could show without crowding.
#
# ⇥ is a `--dial`, which is a different kind of thing from the four Returns: not
# a verb but a value the step carries, cycled in place at the leading edge of the
# same action bar. "Which client, this once" is exactly the question dials exist
# for — too small to deserve a picker step of its own, too real to be settled
# only by `haus.ai.default`, and answered without leaving the paragraph you are
# typing. It offers the clients that are actually on PATH, `haus.ai.default`
# first, and opens on whichever one you last spawned with; a Mac with one client
# installed gets no chip at all. The lane records the client it was made with,
# so a `pi` lane spawned from here still reopens in pi however the chip sits
# next time.
#
# ── which way round ↵ and ⌃↵ go, and why ──────────────────────────────────────
#
# Background is the DEFAULT, and ⌃↵ is the one that takes the screen. The two
# spawns are the same code path either way — one exported variable,
# HAUS_LANE_BACKGROUND, read by ~/.config/haus/lanes/lane-open.sh — so this is
# purely which one you get for free. The worktree, the branch and the zmx
# session are made exactly as usual in both, and the client starts on the prompt
# in both, and BOTH open a window, tiled on T/<repo>. What differs is whether
# that window reaches you: ⌃↵ brings you to it, ↵ leaves you exactly where you
# were standing.
#
# Backgrounding is the right default because of what a spawn IS: you describe a
# task in a sentence and hand it to somebody else. Almost none of those are the
# thing you are about to sit and watch — you keep doing what you were doing and
# visit the lane when it has something to show (the banner's own click, ⌃⇥, the
# Lanes palette, the bar's agents pill). Making the common case the plain Return
# means the palette can get out of the way completely: box → gone → banner when
# the lane is up, and that banner is a door rather than a receipt.
#
# Nothing else moves while that happens: the lane's Ghostty is exec'd from the
# app bundle directly, so LaunchServices never activates anything, and the
# window is asked for at a position macOS clamps into a corner until the
# self-tile moves it to T/<repo>. How that is done, what `open -g` cost when it
# was tried, and the one release when a background lane had no window at all,
# are all written up where the silence lives —
# ~/.config/haus/lanes/lane-open.sh. This script only ever sets the variable.
# The thing to know here: a background lane IS on T/<repo> from the moment it
# spawns, so ⌃⇥ finds it without your having opened it first.
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
# and this is the one step in the whole of haus that asks you to type a paragraph.
# Losing it to a stray click is unrecoverable — the text existed nowhere else.
# `--draft` files it on every dismissal; ⌥↵ hands it back through `--query`, in
# the box, editable, rather than just re-running it.

# A launchd GUI agent's PATH is bare; resolve our tools (scruff, zmx, git,
# open, osascript, pounce) explicitly — the same prelude add-app.sh uses.
export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOTS="${HAUS_REPO_ROOTS:-$HOME/code:$HOME/src:$HOME/Developer:$HOME/Projects:$HOME/.config/nix}"
# The registry, resolved the way scruff's own baseDir() does (scruff's
# docs/rename.md §8.2): the scruff-named base while it holds the registry, the
# legacy path while THAT is the one holding it, else the scruff default a
# fresh install will create. Probe-based, so a rebuild that lands ahead of the
# base move — or after it, whichever order the operator runs them in — reads a
# registry that exists either way.
if [ -f "$HOME/.cache/scruff/registry.tsv" ]; then
  WT_REGISTRY="$HOME/.cache/scruff/registry.tsv"
elif [ -f "$HOME/.cache/claude-worktrees/registry.tsv" ]; then
  WT_REGISTRY="$HOME/.cache/claude-worktrees/registry.tsv"
else
  WT_REGISTRY="${CLAUDE_WT_BASE:-$HOME/.cache/scruff}/registry.tsv"
fi
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
# A `--dial` step's commit grows one MIDDLE field —
# "<action>\t<name=value;…>\t<line-or-text>" — so the step that passed the flag
# strips TWO fields where every other step here strips one. Both halves are
# below; this one answers "was there a dial field at all", and answers no
# whenever it cannot be sure, because a false yes eats the first line of
# somebody's task.
#
# Three things have to hold, and each rules out a different way of being wrong:
# a resident DAEMON older than the flag ignores it and answers in the two-field
# shape (caught by the field count — an old CLI is a different story and
# refuses the flag outright with exit 64, which reads here as a dismissal; the
# CLI ships in the same closure as this script, so the two cannot skew),
# a prompt beginning "agent=" is ordinary text
# (caught by the count too, unless it also contains a tab), and a value that
# is not one we offered is not ours to act on (caught by the membership test,
# which is also what stops a stale chip naming a client that has since gone).
dial_agent() {
  [ -n "$agent_dial" ] || return 1
  local line value
  line="$(printf '%s' "$1" | /usr/bin/head -n1)"
  [ "$(printf '%s' "$line" | awk -F'\t' '{print NF}')" -ge 3 ] || return 1
  value="$(printf '%s' "$line" | cut -f2)"
  case "$value" in agent=*) value="${value#agent=}" ;; *) return 1 ;; esac
  case " $AGENTS " in *" $value "*) printf '%s' "$value" ;; *) return 1 ;; esac
}
# The other half: everything after the SECOND tab of the first line, newlines
# and tabs in the task itself untouched.
dial_payload() { printf '%s' "$1" | /usr/bin/sed $'1s/^[^\t]*\t[^\t]*\t//'; }
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

# ── which client ──────────────────────────────────────────────────────────
# The machine's default, and the ones actually on PATH beside it. Two answers
# from one walk, because they are the same question asked twice:
#
#   $agent   what a spawn uses when nothing says otherwise.
#   $AGENTS  everything the ⇥ dial may offer, default first so it is the
#            value the chip opens on the very first time.
#
# Belt to the assertion's braces. `haus.ai.clients` makes the default client
# present at BUILD time, but this script runs long after that — the client can
# still be missing on a machine driving `scruff` without haus, or with a
# hand-managed install that moved. Checking here, before anything is created, is
# the difference between a toast and the old failure: `scruff spawn` succeeds,
# the pane opens, and only `scruff agent start` inside it finds nothing — leaving
# a dead pane and a worktree nobody asked for.
#
# Building the dial from `command -v` rather than from `haus.ai.clients` is what
# makes every option on the chip a client that will actually start. The four ids
# are scruff's own (`internal/registry`'s validAgent) and this is the one place
# the list is written out — `scruff spawn --agent` refuses anything else, so a
# fifth client is a scruff change first and a line here second.
# One function so it is testable: it reads only PATH and `scruff agent default`,
# and everything it decides lands in the three globals named above.
resolve_agents() {
  agent="$(scruff agent default 2>/dev/null)"
  [ -n "$agent" ] || agent="claude"
  AGENTS=""
  local client
  for client in "$agent" claude codex opencode pi; do
    case " $AGENTS " in *" $client "*) continue ;; esac
    command -v "$client" >/dev/null 2>&1 || continue
    AGENTS="${AGENTS:+$AGENTS }$client"
  done
  [ -n "$AGENTS" ] || return 1
  # The default itself can be the missing one — a host that names `codex` on a
  # Mac that never installed it. Fall to the first that IS here rather than
  # refusing, because the alternative is a palette command that does nothing at
  # all on a machine with three working clients and one stale option.
  #
  # But say so. The chip shows the substitution only where there IS a chip, and
  # the case that actually needs telling is the other one — one client
  # installed, the wrong one named, no chip, and every lane from now on quietly
  # opening in a client the host file does not mention. A banner rather than a
  # `notice`, because a `notice` is a second window in front of somebody who
  # asked for a spawn; this is news about their config, threads on itself, and
  # `rules.json` can silence it by source like anything else haus draws.
  #
  # The function only RECORDS it, in $agent_missing; the banner is the caller's,
  # two reasons deep. resolve_agents reads PATH and one command and writes three
  # globals — keeping it that way is what lets a test run it for real instead of
  # against a copy, and a function that draws on the screen is a function no test
  # can call twice. (haus-notify resolves at an absolute path this script's own
  # PATH prelude cannot shadow, so there is nothing to stub either.)
  agent_missing=""
  case " $AGENTS " in
    *" $agent "*) ;;
    *) agent_missing="$agent"; agent="${AGENTS%% *}" ;;
  esac
  # `--dial "agent=a|b"` needs two options to be a dial at all — `Dial.parse`
  # drops a segment with fewer than two and the step opens without a chip, which
  # is exactly right for a machine with one client installed. Spelling the guard
  # out anyway, so the empty string is a decision rather than a side effect.
  agent_dial=""
  case "$AGENTS" in *" "*) agent_dial="agent=$(printf '%s' "$AGENTS" | tr ' ' '|')" ;; esac
}
if ! resolve_agents; then
  notice "no coding agent is installed" \
    "Add one to haus.ai.clients, then rebuild — claude, codex, opencode or pi"
  exit 1
fi
if [ -n "$agent_missing" ]; then
  /run/current-system/sw/bin/haus-notify --source haus.lane --kind pulse \
    --symbol exclamationmark.triangle --thread "ai-default-$agent_missing" \
    --title "haus · $agent_missing is not installed" \
    --body "Spawning with $agent instead — fix haus.ai.default or haus.ai.clients" \
    >/dev/null 2>&1
fi

# Cards, not rows. A repo IS a thing rather than a name — it has an icon, a
# path, a branch and a worktree count — and `--grid` is pounce's shape for
# exactly that. Groups order the cards but draw no headers, so the single
# "Repositories" group costs nothing; the rows are unchanged, because `--grid`
# is purely a shape and the commit string is identical either way.
repo_sel="$(printf '%s\n' "$list" | pounce --grid -p "Spawn Agent — which repo?" -i "sparkles")"
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
  #
  # The dial is passed as ONE argument that is either the whole flag pair or
  # nothing, unquoted on purpose: a machine with a single client installed has
  # no second option to cycle to, and $agent_dial is empty there, so word
  # splitting is what makes the flag disappear entirely rather than arrive as
  # `--dial ""` for pounce to parse and discard.
  local dial=""
  [ -n "$agent_dial" ] && dial="--dial $agent_dial"
  # shellcheck disable=SC2086
  printf '' | pounce --chain opt \
    --draft "$DRAFT_KEY" \
    $dial \
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
  # Every commit carries the chip's CURRENT value, so this is re-read on each
  # trip round the loop rather than once: cycling to another client and then
  # going out to the drafts list must not put the first client back. pounce
  # remembers the value per option-set and only on a commit, so the box reopens
  # on what you last spawned with and an Esc changes nothing.
  if picked_agent="$(dial_agent "$prompt_sel")"; then
    agent="$picked_agent"
    prompt="$(dial_payload "$prompt_sel")"
  else
    prompt="$(payload_of "$prompt_sel")"
  fi

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
# point: one name — scruff.<repo>.<lane> — becomes the zmx session, and the Ghostty
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
# The reader is a hand-written adapter in the operator's own ~/.config — a file
# haus does not ship, cannot see and cannot rewrite — so an adapter written
# against the old name must have been updated in the same rebuild that stopped
# exporting it (scruff 1.1.0; docs/rename.md §8.1). This machine's was.
case "${HAUS_LANE_NAMER:-}" in
  "" | claude) laneNamer="" ;;
  *) laneNamer="$HAUS_LANE_NAMER" ;;
esac
export SCRUFF_NAMER_FALLBACK=""
set -- spawn "$repo"
if [ -n "$laneNamer" ]; then
  export SCRUFF_NAMER_FALLBACK="$slug"
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

# trill's lane whitelist, halved: each side of a lane id is a basename, so
# neither may carry a slash of its own even though the joined target does.
# Prints the qualified target and succeeds, or prints nothing and fails — a
# function rather than an inline `case` so the test runs the real one.
lane_target() {
  case "$1" in "" | *[!A-Za-z0-9._-]*) return 1 ;; esac
  case "$2" in "" | *[!A-Za-z0-9._-]*) return 1 ;; esac
  printf '%s/%s\n' "$1" "$2"
}

# ── say so, when there is nothing to see ──────────────────────────────────
# The default spawn puts nothing on any screen — no window, no tile, nothing to
# glance at — and the palette is already gone by the time scruff finishes, so
# without this, Return on a paragraph you just typed produces nothing you can see
# at all and you are left wondering whether it took. This banner IS the receipt,
# and it fires when the lane genuinely exists rather than when the box closed.
#
# It is also the DOOR to the lane it announces. `--action "…=lane:<repo>/<name>"`
# is trill's `focus_lane`, and trill's own rule is that the first action is what
# clicking the banner BODY does — so the whole card is the target, not just the
# pill. The click runs `scruff focus <repo>/<name>`, which goes through
# lane-focus.sh: the background spawn already has a window tiled on T/<repo>, so
# the common answer is a plain raise onto that page, and the one case where the
# window was closed with ⌘W defers back into lane-open.sh and opens a fresh one
# there. Exactly the path scruff's own fin takes when the lane later blocks or
# finishes (`scruff hook notify`) — this just stops the FIRST banner being the
# one that can't take you anywhere.
#
# Qualified by repo, and spelled the way scruff spells it everywhere else
# (`laneID`: the main checkout's basename, then the lane name) — `scruff child`
# puts one lane name in two repos, and an unqualified name is the ambiguity
# `scruff focus` refuses to guess at. `$repo_name` IS that basename: the repo
# list builds it with `basename "$repo"` and `$repo` is what `scruff spawn` was
# handed, so the two cannot drift.
#
# And it is OFFERED rather than assumed, which is the one thing this block has
# to get right. trill whitelists a lane target ([A-Za-z0-9._-/]) and refuses the
# WHOLE send when it fails — not just the action — so a repo directory with a
# space or a `+` in its name would cost this banner its trill rendering
# altogether: haus-notify catches the refusal and falls through to Apple's, and
# the spawn receipt quietly loses its threading, its symbol and its `rules.json`
# routing over a character in a folder name. So the action goes in only when it
# would be accepted, and an oddly-named repo keeps exactly the banner it had
# before and loses only the click.
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
  banner=(--source haus.lane --kind pulse --symbol play.circle
          --thread "$name" --title "haus · agent lane"
          --body "$repo_name — $name is working")
  target="$(lane_target "$repo_name" "$name")" \
    && banner+=(--action "Go to lane=lane:$target")
  /run/current-system/sw/bin/haus-notify "${banner[@]}" >/dev/null 2>&1
fi
# Explicitly, so the spawn's exit status is the spawn's and not a notification's.
exit 0

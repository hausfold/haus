#!/bin/bash
# pounce: name = Spawn Agent
# pounce: description = Start your default coding agent on a named worktree of any repo
# pounce: icon = sparkles
# pounce: submenu = true
#
# The palette front door to a named agent worktree. Pick a repo, type what you
# want done, and this creates a worktree named after the task and drops the
# configured default (Claude Code, Codex or OpenCode) into it, as a LANE:
# a zmx session, a Ghostty window forced to its name, tiled on that repo's own
# T/<repo> page.
#
# Why it exists: the same thing by hand is caps→t to a terminal, cd to the repo,
# ⌃⌘A for a lane, then type the prompt — and the worktree ends up
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
# Repos come from $HAUS_REPO_ROOTS — colon-separated, written into the pounce
# daemon's launchd environment from `haus.ai.repoRoots`, which is the only way
# it can arrive: a GUI agent inherits nothing from your shell, so the list below
# is a fallback for a hand-run rather than the thing you tune. Each entry is
# read one of two ways, decided by the path itself: an entry that IS a repo is
# offered as itself and never descended into (that is `~/.config/nix`, the
# config flake this Mac is built from, without scanning `~/.config`), and
# anything else is scanned one and two levels deep for a main checkout — two so
# a workshop-style parent dir full of repos resolves to its children. Plus every
# repo `holt` already knows, so a repo outside those roots that you have agent'd
# before stays reachable.
#
# ── the prompt step's five Returns ────────────────────────────────────────────
#
#   ↵    spawn on what you typed
#   ⇧↵   newline — the task is often a list, not a sentence
#   ⌘↵   capture a screenshot first, then spawn (this used to be a whole second
#        palette entry, "Spawn Agent with Screenshot")
#   ⌃↵   spawn in the background — everything happens, nothing takes the screen
#   ⌥↵   your drafts
#
# ⌃↵ is the same spawn as ↵ with HAUS_LANE_BACKGROUND=1 exported: the worktree,
# the branch, the zmx session, the Ghostty window and the tile on T/<repo> are
# all made exactly as usual, and the client starts on the prompt — but the
# window is opened with `open -g` and AeroSpace is not told to follow it, so you
# stay in whatever you were doing and visit the lane when you are ready (⌃⇥, the
# Lanes palette, the bar's agents pill). The whole silence lives in
# ~/.config/haus/lanes/lane-open.sh; this script only sets the variable. It is
# what you want for "start this and I'll read it later", which is most spawns
# that aren't the thing you are about to work on.
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

# A launchd GUI agent's PATH is bare; resolve our tools (holt, zmx, git,
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

# The lane opener is holt's own `open` seam, installed by the terminal room.
# Checked HERE, before anything is created, for the reason the client check
# below gives: a worktree with nothing to open it is litter.
# NOTE: $OPENER is a PRECONDITION PROBE here and is never executed by this
# script any more — `holt spawn --prompt` drives the same seam itself, reading
# the path from ~/.config/holt/config.toml. Checked anyway, and here rather than
# 250 lines down where it is used, because a lane with nothing to open it is
# litter and this is before anything is created.
OPENER="$HOME/.config/haus/lanes/lane-open.sh"
for tool in holt zmx; do
  command -v "$tool" >/dev/null 2>&1 && continue
  notice "$tool is unavailable" "Rebuild haus, then try again"
  exit 1
done
if [ ! -x "$OPENER" ]; then
  notice "No lane opener" "Rebuild haus — ~/.config/haus/lanes/lane-open.sh is missing"
  exit 1
fi
# holt has to be new enough to open a lane on a prompt. The lock bump and this
# script move together, but a machine caught mid-ripple — or anyone with an
# older holt earlier on PATH — would otherwise get "could not create the
# worktree", which points at their repo instead of at the version skew. `--help`
# prints to stderr, hence the redirect.
if ! holt --help 2>&1 | grep -q -- '--prompt-file'; then
  notice "holt is too old for Spawn Agent" "Rebuild haus — it needs holt with --prompt-file"
  exit 1
fi

# Where the spawn path's evidence goes. A launchd GUI agent has no stderr a
# person will ever read, and the toasts below are one line each — so without
# this, holt's errors, the open seam's refusal reasons and lane-open.sh's own
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

# Repos holt already knows (registry field 2 is each worktree's main checkout).
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

agent="$(holt agent default 2>/dev/null)"
[ -n "$agent" ] || agent="claude"
# Belt to the assertion's braces. `haus.ai.clients` makes the default
# client present at BUILD time, but this script runs long after that — the
# client can still be missing on a machine driving `holt` without the rice, or
# with a hand-managed install that moved. Checking here, before anything is
# created, is the difference between a toast and the old failure: `holt spawn`
# succeeds, the pane opens, and only `holt agent start` inside it finds nothing —
# leaving a dead pane and a worktree nobody asked for.
if ! command -v "$agent" >/dev/null 2>&1; then
  notice "$agent is not installed" "Add it to haus.ai.clients, or change haus.ai.default"
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
# ⌃↵ is not chained either, for the opposite reason: a chained action holds the
# palette up and KEY until the next step presents, and its only way out is an
# 8-second fallback fade. Plain ↵ never notices, because the lane window it
# opens takes the screen a moment later — but a background spawn opens nothing
# you can see, so chaining it would park a spinner over your work for eight
# seconds to announce a lane that is deliberately elsewhere. Unchained, the
# palette lingers out normally and hands focus back to the app it stole it from,
# which is exactly the promise ⌃↵ is making.
#
# --draft: every dismissal that isn't a commit keeps the text. This is the whole
# insurance policy against the click-away.
ask() {
  # $1: text the box opens with (a draft coming back for editing, or empty).
  printf '' | pounce --chain enter,opt \
    --draft "$DRAFT_KEY" \
    --actions "Spawn|shift:New line|cmd:With a screenshot|ctrl:Background|opt:Drafts" \
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
background=""
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
      # Same spawn, one exported variable. Nothing else about the path changes,
      # so a background lane is never a second code path that can rot.
      background=1
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
# now that ⇧↵ can produce them, and the prompt reaches holt on stdin, so a list
# survives as a list all the way into the client.
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

# ── create the lane, and open it ──────────────────────────────────────────
# ONE call. `holt spawn --prompt` creates the checkout, the branch and the
# registry row, then drives holt's own `open` seam with the client invocation
# it resolved — which on this machine is the very same
# ~/.config/haus/lanes/lane-open.sh the terminal room writes into
# ~/.config/holt/config.toml.
#
# It used to be this script's job to build that invocation and export five
# HOLT_* variables by hand. That was holt's contract reimplemented outside
# holt, and it drifted the moment either side moved: the argv shape (`--` for
# a positional prompt, `--prompt=` for opencode's yargs) and the shell-quoting
# of the command string both lived here, in a palette command, for the one
# caller that happened to need them.
#
# Going through the seam rather than opening a window here is still the whole
# point: one name — holt.<repo>.<lane> — becomes the zmx session, the Ghostty
# window title AND the tile on T/<repo>, which is the join every other surface
# (the bar's go-to, Lanes, resort-windows.sh) reads.
#
# The prompt goes in on STDIN, not in argv. A task typed with ⇧↵ spans lines
# and routinely holds quotes and `$`; `--prompt-file -` means it never crosses
# a command line at all, so there is nothing left to quote wrong.
#
# HAUS_AGENT_IMAGE is still honoured so an external caller can pre-attach a
# file; ⌘↵ above is the in-palette way to the same argument.
[ -n "${image:-}" ] || image="${HAUS_AGENT_IMAGE:-}"
set -- spawn "$repo" "$slug" --agent "$agent" --prompt-file -
[ -n "$image" ] && set -- "$@" --image "$image"

# ⌃↵. Not a holt flag and not an argument: "don't take the screen" is a fact
# about how THIS machine opens a window, which is lane-open.sh's business and
# nobody else's — holt only has to carry it, and it does, because it hands a
# seam os.Environ(). Exported unconditionally-empty otherwise so nothing stale
# in the launchd environment can turn an ordinary spawn silent.
export HAUS_LANE_BACKGROUND="${background:-}"

# holt prints the lane's path on stdout BEFORE it drives the seam, so this
# captures it whether the window opened or not — which is what the cleanup
# below needs.
dir="$(printf '%s' "$prompt" | holt "$@" 2>>"$LOG")"
rc=$?
if [ -z "$dir" ] || [ ! -d "$dir" ]; then
  notice "Could not create the worktree" "Why, in $LOG"
  exit 1
fi
name="$(basename "$dir")"

# rc 0 is the window; anything else means the lane exists with nothing on it.
# 3 is holt saying no `open` seam is configured — impossible here, since the
# OPENER check up top already refused that case, but it is not this script's
# job to be the only thing standing between a rebuild gap and silent litter.
#
# This covers the seam REFUSING, not the lane failing later: the opener's last
# act is `open -na`, which returns the moment LaunchServices accepts it, so
# nothing after that — the launcher script, `zmx attach`, the client itself —
# can reach this exit status. Those failures are caught where they happen
# instead: lane-open.sh holds the window open on a non-zero client exit rather
# than letting it flash shut, which is the evidence you would otherwise want
# this branch to preserve.
if [ "$rc" -ne 0 ]; then
  # `holt drop`, not `git worktree remove`: the raw remove takes the checkout
  # and the branch but leaves holt's REGISTRY ROW, so the lane goes on being
  # listed by `holt`, `bench status` and the agents pill as a checkout that
  # isn't there. drop is holt's own verb for "this will never land" — it takes
  # the branch with it and records the reason in `holt reaped`, so nothing
  # vanishes unrecorded. It refuses (exit 2) if something is genuinely standing
  # in the checkout, and that refusal is the right answer rather than something
  # to force past: this is the one path where the lane might not be empty.
  if holt drop "$name" >>"$LOG" 2>&1; then
    notice "Could not open the lane" "The lane was dropped; nothing changed"
  else
    notice "Could not open the lane" "Lane '$name' is still here — run holt"
  fi
  exit 1
fi

# ── say so, when there is nothing to see ──────────────────────────────────
# An ordinary spawn announces itself by taking the screen. A background one
# announces itself by definition NOT taking the screen, so without this the
# palette simply fades and you are left wondering whether ⌃↵ did anything at
# all. A notification rather than a `notice` toast: `notice` is another pounce
# window, which is a thing appearing in front of you — the one outcome ⌃↵ is
# paying to avoid.
if [ -n "${background:-}" ]; then
  /usr/bin/osascript -e "display notification \"$repo_name — $name is working\" with title \"haus · agent lane\"" >/dev/null 2>&1
fi
# Explicitly, so the spawn's exit status is the spawn's and not a notification's.
exit 0

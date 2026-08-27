#!/usr/bin/env bash
# statusline.sh — haus agent-worktree statusline for Claude Code.
#
# Row 1  : THIS session's git-status token as the leading glyph (⏏/N^/+A-D, or a
#          muted ● when clean) + its own PR number (left of the name, colored by
#          PR state, same as the children) + worktree name, then flush right:
#          the child-PR cluster (bare clickable numbers for every worktree this
#          session spawned — there so they survive the row-2+ list being capped
#          or clipped in a short pane) ·
#          rice-nag (⇡N — commits your pinned haus is behind, `haus update`)
#          · ctx% (green <100k tokens, yellow <200k, red beyond — banded on
#          absolute tokens, not the percentage) · cost · permission-mode icon
#          (blank auto, ⏵ default, ⏵⏵ accept,
#          ⏵⏵⏵ bypass, ⏸ plan, ⊘ dontAsk) · model tier chip (O5 / S5 / H45 / F5).
# Tint   : on Fable/Mythos only, every row gets a dark magenta background painted
#          edge-to-edge, so the special model is legible from across a wall of
#          panes without reading anything. Per-pane, hence safe — see TINT_FABLE.
# Row 2+ : the worktrees THIS session spawned (its direct children via ⌘A /
#          `claude --worktree`), across whatever repos they live in — each with
#          the same status-as-bullet as row 1, then repo, PR number (colored by
#          PR state), and name. Active rows lead; reapable ⏏ rows come last so
#          Claude Code clipping never hides work that still needs attention.
#
# Lineage: `scruff hook create` records each worktree's parent (the cwd it was spawned
# from) in its registry; the refresher carries that into panel.tsv, and a
# session lists only the rows whose parent == its own cwd.
#
# The status token is a single mutually-exclusive slot:
#     ⏏  (orange)   branch is merged/landed → `scruff` reaps it on pane close
#     N^ (orange)   the PR merged and N commits landed on the branch SINCE: work
#                   no PR covers and nothing pushed (GitHub deleted the remote
#                   branch at merge). `scruff reship` opens the follow-up.
#     N^ (blue)     N commits on the branch, not yet merged
#     +A -D         uncommitted line changes (green/red), when no commits yet
#     (empty)       nothing differs from main → show nothing (no "clean")
#
# Cheap local git runs inline every render; the cross-repo + gh enumeration is
# done DETACHED by statusline-refresh.sh and cached (stale-while-revalidate).
# Pair with: "statusLine":{"command":"…/statusline.sh","refreshInterval":12}
PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/$(id -un 2>/dev/null)/bin:/opt/homebrew/bin:/usr/bin:/bin:${PATH:-}"

CACHE_DIR="${CLAUDE_STATUSLINE_CACHE:-$HOME/.cache/claude-statusline}"
PANEL="$CACHE_DIR/panel.tsv"
# Refresher: the rice ships it on PATH as `claude-statusline-refresh`; fall back
# to the sibling script when running straight out of ~/.claude (pre-rebuild).
#
# `CLAUDE_STATUSLINE_REFRESHER` overrides both, and exists for the same reason
# `CLAUDE_STATUSLINE_CACHE` does: a test needs to observe the STALENESS DECISION
# without the real refresher's network calls. PATH cannot stand in for it — the
# line above prepends the system profile, so a stub in a temp dir can never
# shadow an installed `claude-statusline-refresh`, and test/statusline.bats was
# firing the real one against its temp cache while its header claimed otherwise.
REFRESHER="${CLAUDE_STATUSLINE_REFRESHER:-$(command -v claude-statusline-refresh 2>/dev/null || echo "$HOME/.claude/statusline-refresh.sh")}"
TTL=15          # seconds before the sister-repo panel is considered stale
MAX_ROWS=8      # cap child rows; extras collapse into a "+N more" line
PANEL_COVERED="$CACHE_DIR/.panel-covered"   # written by the refresher; see below

# ---- the GitHub bridge, where there is one ----------------------------------
# The panel's cost is one `gh pr list` per sister repo, which is why its TTL is
# 15 seconds rather than 5. With haus.github's webhook bridge on this machine
# that question has a push answer, so the TTL stretches to the bridge's backstop
# and drops to zero the instant a delivery lands — faster to notice a merge AND
# a fraction of the API traffic.
#
# Sourced, never forked: this is the render path, and it runs on every prompt.
# The refresher writes `.panel-covered` because it is the half that knows which
# repositories the panel is about. No bridge, and every function says no — which
# leaves the TTL exactly what it has always been.
if [ -r "$HOME/.config/haus/github/signal.sh" ]; then
  # shellcheck source=/dev/null
  . "$HOME/.config/haus/github/signal.sh"
else
  haus_gh_fresh_since() { return 1; }
fi
HAUS_GH_BACKSTOP="${HAUS_GH_BACKSTOP:-0}"

# 256-colour palette — muted, rice-consistent (cf. `scruff`: 103 gray, 167 red).
c() { printf '\033[38;5;%sm' "$1"; }
DOT=$(c 108); DIM=$(c 244); NAME=$'\033[1m'
AHEAD=$(c 75); ADD=$(c 71); DEL=$(c 167); PURGE=$(c 173); WARN=$(c 179)
PR_OPEN=$(c 71); PR_MERGED=$(c 139); PR_CLOSED=$(c 167)
R0=$'\033[0m'   # true reset — ends a line, drops any row tint
R="$R0"         # in-row reset; re-armed to keep the tint when one is set (below)

# Row tint for Fable/Mythos: a 24-bit background painted edge-to-edge behind
# every row, so the whole block reads as "this pane is on the special model" at
# a glance across a wall of panes. #382713 is the terminal background (nebelung
# ghostty: 202020) warmed toward amber — dark enough that the dimmest foreground
# in the bar — the 244 gray of cost, and of ctx% on a Claude Code too old to
# send token counts — keeps a 3.6:1 contrast ratio, which is what it has against the bare
# background anyway; a brighter amber costs real
# legibility fast, because yellows carry far more luminance per unit of colour
# than the plum this started as. Truecolor rather than a 256 index because the
# cube has nothing simultaneously this dark and this saturated; every terminal
# this rice targets does 24-bit. Tune it here, it's the one knob.
#
# It does collide semantically with the bar's own warm slots — orange (173) is
# "this branch needs you" on ⏏/N^, yellow (179) is the stale-rice nag and the
# ctx% 100–200k band. Those
# stay legible (5:1 and 6.8:1), but they pop a little less against a warm band
# than they did against a cool one. Accepted: the tint is a per-pane constant
# you stop seeing, while those two are events you're looking for.
TINT_FABLE=$'\033[48;2;56;39;19m'

# render_status <ahead> <files> <ins> <del> <prstate> <purge>
# Emits the single status token. purge=1 => branch would be reaped (row-1 only).
# prstate feeds the merged→⏏ and merged+K→K^ checks; the PR number itself is
# rendered by render_pr as its own segment, left of the worktree name.
render_status() {
  local ahead=${1:-0} files=${2:-0} ins=${3:-0} del=${4:-0} pr="$5" purge=${6:-0}
  local st="" state="${pr##* }" relanded=""
  # merged+K (see the refresher): the PR merged, then K more commits landed on the
  # branch. ⏏ — "nothing left here, scruff reaps it on pane close" — is a LIE about
  # that pane: those K commits have no PR, no remote branch (GitHub deleted it at
  # merge), and `scruff` correctly refuses to reap them. The bar said done while the
  # work sat there, which is how un-shipped commits went unnoticed. Show the count
  # instead, in the same orange: it is the same "this branch needs you" hue.
  case "$state" in merged+*) relanded="${state#merged+}" ;; esac
  # purge outranks it: purge=1 means the tip really IS an ancestor of the default
  # branch — those K commits landed too, by some later merge, so ⏏ is the truth.
  local done=0; { [ "$purge" = 1 ] || [ "$state" = merged ]; } && done=1
  [ "$purge" = 1 ] && relanded=""
  if [ -n "$relanded" ]; then
    st="${PURGE}${relanded}^${R}"
  elif [ "$done" = 1 ]; then
    st="${PURGE}⏏${R}"
  elif [ "$ahead" -gt 0 ] 2>/dev/null; then
    st="${AHEAD}${ahead}^${R}"
  elif [ "$files" -gt 0 ] 2>/dev/null; then
    [ "${ins:-0}" -gt 0 ] && st="${ADD}+${ins}${R}"
    [ "${del:-0}" -gt 0 ] && st="${st:+$st }${DEL}-${del}${R}"
  fi
  printf '%s' "$st"
}

# render_pr <prstate> [url] — "#N" colored by PR state, or nothing when there's
# no PR. When a url is given, the "#N" becomes an OSC 8 terminal hyperlink —
# SGR color survives inside the link. The hyperlink adds ZERO visible width;
# callers must size the segment from the plain "#N" text, not from this output
# (plain() strips SGR, not OSC 8). A "#N" is clickable ONLY when its caller
# passes a url — every caller here does (row 1's own pill, the row-1 sister
# cluster, and the row-2 children). CC forwards OSC 8 to the terminal, so in a
# hyperlink-aware terminal ⌘-click opens the PR — no shift, even though this
# pill is drawn inside an agent TUI that is tracking the mouse. Ghostty consumes
# a cmd-click as a link click before it forwards any mouse report, so the
# tracking never gets a say. (This comment claimed ⌘⇧ until 2026-08-20, arguing
# from the SGR mouse report's missing super bit — real, but it describes what
# the PROGRAM could see, not whether the terminal acts first. ⇧ is for ghostty's
# SELECTION over a mouse grab, which is what `mouse-shift-capture = never` in
# its config buys, and it was never part of the link gesture.) Terminals that
# swallow OSC 8 (some tmux
# builds — anthropics/claude-code#21586, #27047) just show the colored "#N" with
# no link, which is a harmless graceful downgrade.
render_pr() {
  local pr="$1" url="${2:-}" state="${1##* }" col="$DIM" num="${1%% *}"
  [ -n "$pr" ] || return 0
  # merged* covers merged+K too — the PR itself really did merge, so the pill keeps
  # the merged color; it's the STATUS token beside it that says work has piled up
  # since (render_status). Without the glob a merged+K pill fell through to $DIM.
  case "$state" in open) col="$PR_OPEN";; merged*) col="$PR_MERGED";; closed) col="$PR_CLOSED";; esac
  if [ -n "$url" ]; then
    # OSC 8: ESC ]8;;URL ST  <text>  ESC ]8;; ST   (ST = ESC \, real bytes here —
    # the child-row printf uses %s so these bytes pass through un-reinterpreted).
    printf '\033]8;;%s\033\\%s%s%s\033]8;;\033\\' "$url" "$col" "$num" "$R"
  else
    printf '%s' "${col}${num}${R}"
  fi
}
# strip ANSI SGR *and* OSC 8 hyperlinks so vlen counts only visible columns.
# (This sed doesn't grok \x1b inside a bracket class, so the URL is matched as
# "non-backslash" — URLs never contain '\', and the ST terminator's '\' stops it.)
plain() { printf '%s' "$1" | sed 's/\x1b]8;;[^\\]*\x1b\\//g; s/\x1b\[[0-9;]*m//g'; }

mtime() { # mtime <file> — modification time in epoch seconds, 0 when unknown
  # The same helper the refresher carries, and for the same reason: `stat -f %m`
  # is BSD/macOS, which is where this runs — but the test suite runs on a GNU
  # box in CI, where -f means --file-system and %m is the MOUNT POINT, so it
  # prints "/" and exits 0. The fallback cannot be selected by exit status
  # alone. Accept the BSD result only when it is numeric, then try GNU stat,
  # then insist on digits so the caller's arithmetic can't blow up.
  local m
  m=$(stat -f %m "$1" 2>/dev/null || true)
  case "$m" in '' | *[!0-9]*) m=$(stat -c %Y "$1" 2>/dev/null || echo 0) ;; esac
  case "$m" in '' | *[!0-9]*) m=0 ;; esac
  printf '%s' "$m"
}

in=$(cat)
j() { printf '%s' "$in" | jq -r "$1 // empty"; }
cwd=$(j '.workspace.current_dir // .cwd'); [ -z "$cwd" ] && cwd="$PWD"
# The $HOME pane is the catch-all: it alone also surfaces "orphan" worktrees
# (ones with no recorded parent — e.g. a raw `git worktree add` that skipped
# `scruff child`), so a stray worktree is never fully invisible, while every other
# session stays quiet and shows only the worktrees it actually spawned.
is_home=0; [ "$cwd" = "$HOME" ] && is_home=1
wt_name=$(j '.worktree.name // .workspace.git_worktree')
ctx=$(j '.context_window.used_percentage')
# Absolute tokens in the window, for the ctx% chip's colour (see CTX below).
# Sum of input+output, which is what `exceeds_200k_tokens` counts too; input
# already includes cache reads and writes.
ctx_tok=$(j '.context_window
             | select(.total_input_tokens != null or .total_output_tokens != null)
             | (.total_input_tokens // 0) + (.total_output_tokens // 0) | floor')
cost=$(j '.cost.total_cost_usd')
transcript=$(j '.transcript_path')
COLS=${COLUMNS:-120}

# Session → transcript map, consumed by pounce's Links command
# (modules/launcher/commands/links.sh) and by ⌘F find
# (modules/terminal/scripts/find.sh). This render is the one process that knows
# BOTH which zmx session it lives in ($ZMX_SESSION, inherited through Claude
# Code) and which conversation transcript that session is showing (stdin) — so
# it maintains the join. Upsert keyed by session name, write only on change: a
# `term.<n>` name recycled onto a new conversation is corrected by that window's
# next render, and a lost race between two concurrent renders heals the same
# way. Tiny file; no pruning.
#
# The file is still called pane-transcripts.tsv. A window IS the pane now, both
# readers spell the path, and renaming it would strand every live row for a
# word.
if [ -n "${ZMX_SESSION:-}" ] && [ -n "$transcript" ]; then
  map="$CACHE_DIR/pane-transcripts.tsv"
  if [ "$(awk -F'\t' -v id="$ZMX_SESSION" '$1==id{v=$2} END{print v}' "$map" 2>/dev/null)" != "$transcript" ]; then
    [ -d "$CACHE_DIR" ] || mkdir -p "$CACHE_DIR"
    {
      awk -F'\t' -v id="$ZMX_SESSION" '$1!=id' "$map" 2>/dev/null
      printf '%s\t%s\n' "$ZMX_SESSION" "$transcript"
    } >"$map.$$" && mv -f "$map.$$" "$map"
  fi
fi

# Usage limits → the bar `claudeUsage` pill (modules/bar/sketchybar/plugins/
# claude_usage.sh). Claude Code hands every render the account-wide 5-hour and
# weekly rate-limit percentages, so this is by far the cheapest place to harvest
# them: no keychain read, no /api/oauth/usage call, no polling daemon on a timer.
#
# Account-global numbers arriving through a per-SESSION channel is fine here —
# unlike the model-reactive theme we tried and reverted (PRs #47/#51), where
# last-writer-wins lied in a mixed-model fleet, every pane reports the SAME
# percentages, so whichever writes last is right.
#
# Always rewrite the stash (the reader greys the pill out from that timestamp),
# but only nudge the bar when a percentage actually moved: renders fire on every
# assistant message while these numbers crawl by whole points.
lim5=$(j '.rate_limits.five_hour.used_percentage')
if [ -n "$lim5" ]; then
  limw=$(j '.rate_limits.seven_day.used_percentage')
  usage="$CACHE_DIR/usage.tsv"
  usage_claude="$CACHE_DIR/usage-claude.tsv"
  # Truncate rather than round: 99.6% must not render as a scary 100%.
  now5=${lim5%%.*}; noww=${limw%%.*}
  rst5=$(j '.rate_limits.five_hour.resets_at'); rstw=$(j '.rate_limits.seven_day.resets_at')
  was=$(cut -f1,2 "$usage" 2>/dev/null)
  [ -d "$CACHE_DIR" ] || mkdir -p "$CACHE_DIR"
  # Column 9 is when quota was last BURNED here, and the bar's `latest` provider
  # is chosen on it (see the header of ai_usage.sh). A render is not by itself
  # use: the statusline re-runs every refreshInterval seconds for as long as a
  # pane is merely OPEN, so stamping it `now` would pin the pill to whichever
  # client you left sitting idle. A percentage that went UP is use, and it is
  # the one signal every feed here can produce, pushed or pulled alike.
  stamp_now=$(date +%s)
  p5=0; pw=0; p_used=0
  # A file test rather than `<file 2>/dev/null`: redirections are applied left to
  # right, so a missing file has already printed to the REAL stderr by the time
  # the suppression takes effect — straight into the pane, under the prompt.
  [ -s "$usage_claude" ] && IFS=$'\t' read -r p5 pw _ _ _ _ _ _ p_used <"$usage_claude"
  case "${p5:-}"     in '' | *[!0-9]*) p5=0 ;; esac
  case "${pw:-}"     in '' | *[!0-9]*) pw=0 ;; esac
  case "${p_used:-}" in '' | *[!0-9]*) p_used=0 ;; esac
  used=$p_used
  { [ "$p_used" = 0 ] || [ "${now5:-0}" -gt "$p5" ] || [ "${noww:-0}" -gt "$pw" ]; } && used=$stamp_now
  # Columns 7 and 8 (model, provider id) are FILLED rather than left empty, even
  # though provider_style's `claude` arm reads neither. Tab is IFS whitespace, so
  # `read` collapses a run of empty middle fields into one delimiter and every
  # later column shifts left — the used stamp would land in `model` and the pill
  # would order on a string. Same reason panel.tsv writes `-` for "no PR".
  printf '%s\t%s\t%s\t%s\t%s\tclaude\tclaude\tanthropic\t%s\n' \
    "${now5:-0}" "${noww:-0}" "${rst5:-0}" "${rstw:-0}" "$stamp_now" "$used" \
    >"$usage.$$" && mv "$usage.$$" "$usage_claude" && cp "$usage_claude" "$usage"
  pill="$HOME/.config/sketchybar/plugins/ai_usage.sh"
  if [ "$was" != "$(printf '%s\t%s' "${now5:-0}" "${noww:-0}")" ] && [ -x "$pill" ]; then
    # Detached: a render must never block on sketchybar's socket.
    (SENDER=refresh NAME=ai_usage "$pill" >/dev/null 2>&1 &)
  fi
fi

# Permission mode, from stdin when the payload carries it, else the transcript.
#
# `.permission_mode` is NOT in stock Claude Code's statusline payload (see the
# schema at code.claude.com/docs/en/statusline — cwd/model/cost/context_window/
# fast_mode/effort/vim/pr/worktree, no mode), and no hook fires on a flip either
# (ConfigChange is settings-FILE changes only; PreToolUse & friends carry
# `permission_mode` but only fire inside a turn). A host CAN add it: the payload
# builder already receives the live mode as a parameter, so a byte-length-
# preserving patch of the bun-embedded JS emits it — which is what this machine
# does (hosts/mbp/statusline-permission-mode.py in the nix config, alongside the
# footer-collapsing patch that makes this chip the only mode signal in the pane).
# On a patched build the chip tracks shift+tab live, because Claude Code already
# re-runs this script on every flip: the mode is a dependency of the effect that
# fires the statusline command, inside a 300ms debounce.
#
# THE FALLBACK'S LIMITATION, because it looks like a bug otherwise: Claude Code
# writes the {"type":"permission-mode","permissionMode":"…"} record at TURN
# BOUNDARIES, not on every flip. Cycling shift+tab between turns writes nothing —
# so on a stock build the icon shows the mode as of your LAST SUBMITTED TURN and
# sits still while you cycle. (Verified: a session that shift+tab'd into plan
# mode and back logged 10 consecutive "auto" records ~35KB apart, one per turn,
# and no "plan" at all.) Even then it does the job this chip exists for —
# catching a mode that CHANGED UNDER YOU (switching to a model with no auto mode
# drops you to `default`), which persists across turns and lights up on the very
# next one. Don't "fix" the fallback with a hook; there isn't one. 64KB of tail
# keeps it O(1); `permissionMode` is stamped on user records too, so the window
# almost always holds one.
mode=$(j '.permission_mode')
[ -z "$mode" ] && [ -n "$transcript" ] && [ -f "$transcript" ] &&
  mode=$(tail -c 65536 "$transcript" 2>/dev/null |
    grep -o '"permissionMode": *"[a-zA-Z]*"' | tail -1 | grep -o '[a-zA-Z]*"$')
mode=${mode%\"}

# Model tier chip: a 2–3 char family+version tag for EVERY model — O5, S5, H45,
# F5 — not the old ✦-only-for-Fable flag. The flag was blank at the baseline like
# the mode icon, which was exactly wrong here: the common way to lose auto mode
# is switching to a model that has none, and a blank chip couldn't tell you a
# switch had happened. The mode icon says WHAT changed; this says WHY.
#
# Letter carries the meaning, never colour alone — dim for the everyday tiers,
# magenta for Fable/Mythos so the special model still announces itself. Magenta
# is ANSI slot 5, not a fixed 256 index, so it renders through the terminal theme
# (nebelung maps it to pink #f2c4e5).
#
# The version is the digit run right after the family, plus one more `-N` group
# if present: opus-5 → O5, haiku-4-5-20251001 → H45 (the date suffix is not a
# third group, so it's dropped). A `[1m]` context-variant suffix is ignored — the
# ctx% chip beside it already shows how much room is left. An id that puts the
# version BEFORE the family (old claude-3-5-sonnet-… form) yields the bare
# letter, which is still more than the old flag gave.
#
# Rides the RIGHT-edge tail group (ctx% · cost · mode), NOT the row-1 bullet:
# model is per-SESSION (each ⌘A pane is its own session; --model / mid-session
# /model switches), a per-pane constant that pairs naturally with the other
# per-pane chips — and it frees the bullet to carry the worktree's git status.
# Per-pane by design: any global surface (a rewritten custom-theme file) would
# lie in a mixed-model fleet. Tried, reverted.
#
# Fable/Mythos ALSO tints the whole block's background (see TINT_FABLE). That is
# a second, redundant channel for the same fact, not a replacement: the F/M
# letter still carries it, so a tint that a terminal drops costs nothing. It's
# the one signal that survives not reading the bar — you see which pane is on
# the expensive model from across the screen. Read the "tried and reverted"
# warning below before assuming this is the same mistake: it isn't. That was a
# GLOBAL surface (a rewritten theme file) driven by a per-session fact, so the
# last pane to render decided the colour for every pane. This paints only the
# rows THIS render emits, so a mixed-model fleet shows a mixed set of panes —
# which is the entire point of it.
MODEL=""
model_id="$(j '.model.id')"
BG=""
case "$model_id" in
  *fable*)  mletter=F; mcolor=$'\033[35m'; BG="$TINT_FABLE";;
  *mythos*) mletter=M; mcolor=$'\033[35m'; BG="$TINT_FABLE";;
  *opus*)   mletter=O; mcolor="$DIM";;
  *sonnet*) mletter=S; mcolor="$DIM";;
  *haiku*)  mletter=H; mcolor="$DIM";;
  *)        mletter="";  mcolor="$DIM";;
esac
# Every segment ends in $R, and a bare reset would punch a hole in the tint at
# each one. Re-arm the background right after the reset so $R means "back to row
# context" rather than "back to nothing"; $R0 stays the real reset, used once at
# end of line so the tint can't bleed into whatever the terminal draws next.
[ -n "$BG" ] && R="${R0}${BG}"
if [ -n "$mletter" ]; then
  mver=""
  # {1,2} + the trailing non-digit/end anchor is what stops a DATE suffix being
  # read as a version: `claude-3-5-sonnet-20241022` has no 1–2 digit run after
  # the family that ends cleanly, so it matches nothing and the chip stays "S".
  # Without the anchor it rendered "S20241022" and blew the tail-group budget.
  [[ "$model_id" =~ (fable|mythos|opus|sonnet|haiku)-([0-9]{1,2})(-([0-9]{1,2}))?([^0-9]|$) ]] &&
    mver="${BASH_REMATCH[2]}${BASH_REMATCH[4]}"
  MODEL="${mcolor}${mletter}${mver}${R}"
fi

g() { git -C "$cwd" --no-optional-locks "$@" 2>/dev/null; }
branch=$(g branch --show-current)
is_wt=0
[ -n "$wt_name" ] && is_wt=1
[ "$is_wt" = 0 ] && case "$branch" in worktree-*) is_wt=1; wt_name="${branch#worktree-}";; esac

def=$(g symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
[ -z "$def" ] && { for b in main master; do g show-ref -q --verify "refs/heads/$b" && def=$b && break; done; }
[ -z "$def" ] && def=main

files=$(g status --porcelain | grep -c .)
ahead=$(g rev-list --count "$def..HEAD" 2>/dev/null || echo 0)
ins=0; del=0
if [ "${files:-0}" -gt 0 ]; then
  read -r ins del < <(g diff HEAD --shortstat | awk '{i=0;d=0;for(k=1;k<=NF;k++){if($k~/insertion/)i=$(k-1);if($k~/deletion/)d=$(k-1)}print i" "d}')
  ins=${ins:-0}; del=${del:-0}
fi
purge=0
if [ "$is_wt" = 1 ] && [ "${files:-0}" -eq 0 ] && g merge-base --is-ancestor HEAD "$def" 2>/dev/null; then
  purge=1
  # …unless the branch has never DIVERGED — no commit of its own, and no
  # `commit…` entry in its reflog to say it ever had one. Ancestry can't tell
  # work that landed from work that never existed, so a lane spawned five
  # seconds ago is an ancestor of the default branch too, and row 1 opened with
  # ⏏ — which reads as "merged", and is meant to mean "scruff reaps this on pane
  # close". Both are the wrong thing to say about an empty branch: the honest
  # token for it is no token at all (the muted ● below).
  #
  # Same two facts scruff's `landed.verdict: fresh` is built from (SPEC.md §3.5),
  # deliberately duplicated rather than shelled out to: this runs on every
  # render of every prompt, and `scruff --json` walks every lane on the machine.
  # The reflog is the half that does the work — a branch that merged by
  # fast-forward has no commits of its own left to count either, and only its
  # reflog remembers that it ever did anything. An EMPTY reflog (gc'd entries,
  # or core.logAllRefUpdates off) proves nothing, so it keeps the ⏏.
  #
  # The test is INVERTED on purpose: nothing but `branch: Created from …` may
  # appear, rather than a list of what "something happened" looks like. That
  # list is a trap — `commit:` covers `git commit` and `--amend` and nothing
  # else, while cherry-pick writes `cherry-pick:`, revert `revert:`, rebase
  # `rebase (finish):`, `reset --hard` `reset: moving to`, and `branch -f`
  # `branch: Reset to` (which is why the match keeps its trailing space).
  # Hunting for prefixes calls every one of those empty — this same bug
  # pointing the other way, a lane whose work landed losing its ⏏.
  if [ "${ahead:-0}" -eq 0 ] && [ -n "$branch" ]; then
    reflog=$(g reflog show --format=%gs "$branch" 2>/dev/null)
    [ -n "$reflog" ] && ! printf '%s\n' "$reflog" | grep -qv '^branch: Created from ' && purge=0
  fi
fi

# Row 1's own PR, from two sources that cover different halves of a PR's life.
#
# The panel (cached by the detached refresher) is primary: it is the only source
# that knows a PR MERGED or CLOSED, which is what lights the ⏏ and the post-merge
# N^. purge catches an ancestor-merged branch locally, but a squash/rebase merge
# lands the work under a NEW commit that's never an ancestor, so for those the
# panel's merged state is the only signal there is.
#
# stdin `.pr` is Claude Code's own tracking of the current branch's PR — it polls
# `gh pr view` itself and re-runs this script when the result changes (prStatus
# rides the same effect the mode chip does). It is immediate where the panel has
# a 15s TTL and a detached refresh behind it, and its url is the REAL one rather
# than one reconstructed from a parsed remote — so it is right on GitHub
# Enterprise and on any remote our slug parse would mangle. What it will never
# report is a merged or closed PR: Claude Code drops the field for those.
#
# So: panel first (it can say merged), stdin to fill the gap it leaves — a PR
# opened seconds ago, or a cold/stale refresher — and stdin's url preferred
# whenever the two agree on the number.
own_pr=""; slug=""
cc_prnum=$(j '.pr.number'); cc_prurl=$(j '.pr.url')
if [ "$is_wt" = 1 ] && [ -f "$PANEL" ]; then
  # Match our own panel row by (slug, name). slug is the remote-derived owner/name
  # (same parse the refresher uses) — NOT the local dir name, which can differ
  # (e.g. dir "org-profile" but slug "hausfold/.github").
  slug=$(g remote get-url origin 2>/dev/null)
  slug=${slug%.git}; slug=${slug#*://}; slug=${slug#*@}; slug=${slug#*[:/]}
  if [ -n "$slug" ]; then
    own_pr=$(awk -F'\t' -v n="$wt_name" -v s="$slug" \
      '$1==s && $2==n { print $7; exit }' "$PANEL")
    [ "$own_pr" = "-" ] && own_pr=""
  fi
fi
# Only "open" is expressible from stdin — see above, that's the only state it has.
[ "$is_wt" = 1 ] && [ -z "$own_pr" ] && [ -n "$cc_prnum" ] && own_pr="#$cc_prnum open"

# --- ROW 1 : status-as-bullet + PR pill + name (no repo name, no "clean") -------
# The git-status token IS the leading glyph: ⏏ landed / N^ ahead / +A -D dirty,
# colored by state. A lane that has done nothing yet has NO token — see the
# never-diverged arm of purge above, which is what stopped a five-second-old
# worktree opening with ⏏ — so fall back to a muted ● (clean / at-main). The
# model glyph used to sit here — it moved to the tail (per-pane, next to
# ctx%/cost/mode). The PR "#N" pill follows the lead, left of the name, same as
# the children.
st=$(render_status "$ahead" "$files" "$ins" "$del" "$own_pr" "$purge")
lead="$st"; [ -z "$lead" ] && lead="${DOT}●${R}"
# Hyperlink the own pill to its PR (OSC 8), same as the sister/child rows — this
# is what makes a worktree pane's OWN "#N" ⌘-clickable; before, only the sister
# cluster and row-2 children got urls, so an in-worktree pane's own pill was dead.
# Take Claude Code's url when it's talking about the same PR (real url, any host);
# otherwise rebuild it from the slug + number already in hand (no extra gh call),
# which is also the only option once the PR merges and stdin stops reporting it.
prnum="${own_pr%% *}"          # "#104"
ownurl=""
if [ -n "$own_pr" ]; then
  if [ -n "$cc_prurl" ] && [ "$cc_prnum" = "${prnum#\#}" ]; then
    ownurl="$cc_prurl"
  elif [ -n "$slug" ]; then
    ownurl="https://github.com/${slug}/pull/${prnum#\#}"
  fi
fi
prseg=$(render_pr "$own_pr" "$ownurl")   # "#N" left of the name, mirroring the children
if [ "$is_wt" = 1 ]; then
  row1="${lead} ${prseg:+$prseg }${NAME}${wt_name}${R}"
elif [ -n "$branch" ]; then
  row1="${lead} ${NAME}${branch}${R}"
else
  row1="${lead} ${DIM}$(basename "$cwd")${R}"
fi

# PR-link cluster: bare PR numbers (no '#') for every worktree THIS session
# spawned, space-separated. Each is an OSC 8 hyperlink to its PR, colored by
# state. It rides the RIGHT-flushed tail group (leading it, so it sits just left
# of ⇡nag/ctx%/cost/mode/model) rather than the far left of row 1, where it used
# to push this pane's OWN lead glyph, PR pill and worktree name rightwards — the
# identity of the pane you're looking at is what must never move. Leading the
# group also means the cluster is the only thing that shifts as children come and
# go: it's the widest-varying segment, so everything after it stays put relative
# to the right edge. Row 1 is the last line a growing input composer clips, so
# these links stay reachable even when the per-worktree rows below scroll away.
prcluster=""
if [ -f "$PANEL" ]; then
  while IFS=$'\t' read -r cslug cname _c3 _c4 _c5 _c6 cpr cparent; do
    [ -n "$cname" ] || continue
    [ "$cparent" = "$cwd" ] || continue          # only PRs this session spawned
    [ -n "$cpr" ] && [ "$cpr" != "-" ] || continue
    cnum="${cpr%% *}"; cnum="${cnum#\#}"          # bare number, no '#'
    case "${cpr##* }" in open) ccol="$PR_OPEN";; merged*) ccol="$PR_MERGED";; closed) ccol="$PR_CLOSED";; *) ccol="$DIM";; esac
    clink=$(printf '\033]8;;https://github.com/%s/pull/%s\033\\%s%s%s\033]8;;\033\\' \
              "$cslug" "$cnum" "$ccol" "$cnum" "$R")
    prcluster="${prcluster:+$prcluster }$clink"
  done <"$PANEL"
fi

# Mode icon: Claude Code's own glyph language (⏸ plan, ⏵ armed), our palette.
# AUTO is the blank one — it's the rice's `permissions.defaultMode` (terminal sets
# it) and where you live, so no news is good news and the slot stays quiet all
# day. Everything else is a positive mark, and each is told apart by GLYPH COUNT,
# not colour: one ⏵ gated, two armed, three ungated. Colour only reinforces.
# `default` used to render blank too, which made "you silently fell out of auto"
# and "everything is normal" the same picture — the whole reason this chip
# exists. It now shows a dim ⏵.
#
# Blank still doubles as unknown (no transcript / no stamp in the 64KB window).
# That's the cost of auto-is-blank and it's the right trade: a mis-read reads as
# the mode you're in 95% of the time, rather than crying wolf.
#
# Worth knowing: this line is the ONLY mode signal in the pane. The stock
# "⏵⏵ auto mode on (shift+tab to cycle)" footer row is patched out — NOT by this
# rice, which ships stock `pkgs.claude-code` (terminal/default.nix), but by a host
# that overlays a patched build (mbp does, via declutter-claude-footer.py). A
# host running the unpatched client keeps both.
mseg=""
case "$mode" in
  auto|"")           mseg="";;                 # blank  — the baseline, and unknown
  default)           mseg="${DIM}⏵${R}";;      # dim    — gated, asks every tool
  acceptEdits)       mseg="${ADD}⏵⏵${R}";;     # green  — edits sail through
  plan)              mseg="${AHEAD}⏸${R}";;    # blue   — paused to plan
  dontAsk)           mseg="${DEL}⊘${R}";;      # red    — deny-if-not-allowed
  bypassPermissions) mseg="${DEL}⏵⏵⏵${R}";;    # red    — no gates at all
esac

# Stale-rice nag: "⇡6" = your pinned haus is 6 commits behind upstream, i.e.
# what `haus update` would bring in. Nix has no "latest" — an input is whatever
# flake.lock pinned — so this chip is the only place the drift is visible without
# running a command. The count is computed DETACHED by the refresher (one cached
# GitHub compare call, 30-min TTL); the render path just reads a 1-line file, so
# this costs no network and no nix. Nothing renders when you're up to date.
#
# Yellow at first (haus's own `warn` colour), red once the PIN itself is older
# than NAG_ALERT_DAYS — being a few commits behind for an afternoon is normal;
# running a rice nobody has rebuilt in a fortnight is the thing worth seeing.
# ⌘-click opens the GitHub compare of exactly the commits you haven't taken.
NAG_ALERT_DAYS=14
nagseg=""
if [ -s "$CACHE_DIR/lock-nag.tsv" ]; then
  IFS=$'\t' read -r nbehind nlockdate nagurl <"$CACHE_DIR/lock-nag.tsv"
  case "${nbehind:-}" in ''|*[!0-9]*) nbehind=0;; esac
  case "${nlockdate:-}" in ''|*[!0-9]*) nlockdate=0;; esac
  if [ "$nbehind" -gt 0 ]; then
    ncol="$WARN"
    [ "$nlockdate" -gt 0 ] &&
      [ $(( ( $(date +%s) - nlockdate ) / 86400 )) -ge "$NAG_ALERT_DAYS" ] && ncol="$DEL"
    if [ -n "${nagurl:-}" ]; then
      nagseg=$(printf '\033]8;;%s\033\\%s⇡%s%s\033]8;;\033\\' "$nagurl" "$ncol" "$nbehind" "$R")
    else
      nagseg="${ncol}⇡${nbehind}${R}"
    fi
  fi
fi

# Tail group (child-PR cluster · rice-nag · ctx% · cost · mode icon · model) sits
# flush RIGHT, next to Claude Code's own right-edge chips (/rc); RESERVE leaves
# them room. Narrow pane → fall back to the old inline append. wc -m under a
# UTF-8 locale counts the wide glyphs as characters (≈ columns), not bytes. The
# model chip is last — nearest /rc — and unlike the others it's always present.
# Order is by how much each segment MOVES: the PR cluster leads because it's the
# widest-varying (children come and go), then the nag, which is machine-global
# (same in every pane), then the per-session chips — so the things you read most
# stay put instead of shuffling every time a child opens a PR.
vlen() { plain "$1" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' '; }
RESERVE=8

# emit <row> — print one row, tinted edge-to-edge when $BG is armed.
#
# A background only shows where a character is, so an untinted row has to be
# padded out to the block's width or the tint is a ragged blob the shape of the
# text. The width is COLS - RESERVE, the same budget row 1's tail group already
# flushes to, so all rows end on one clean edge and Claude Code's own right-edge
# chips keep their untinted gutter.
#
# %s, not %b: rows carry OSC 8 links whose ST is a literal backslash that %b
# would eat. The padding sits BEFORE $R0, so the string never ends in
# whitespace — nothing downstream can trim the tint off the end of the line.
emit() {
  if [ -z "$BG" ]; then printf '%s\n' "$1"; return; fi
  local pad=$(( COLS - RESERVE - $(vlen "$1") ))
  [ "$pad" -lt 0 ] && pad=0
  printf '%s%s%*s%s\n' "$BG" "$1" "$pad" '' "$R0"
}
# ctx% colour: green under 100k tokens, yellow to 200k, red past it — banded on
# the ABSOLUTE token count, never on the percentage. The percentage is relative
# to `context_window_size`, which is 200k on most models and 1M on the extended
# ones, so the same 40% is 80k tokens in one pane and 400k in the next; a colour
# keyed to it would mean two different things side by side in a mixed fleet.
# Tokens are the thing that actually costs money, slows a turn down and decides
# when a compaction lands, so that is what the band tracks. Consequence worth
# knowing: on a 200k model red is unreachable (compaction fires first) and
# yellow starts at 50%, while on a 1M model yellow lands at 10% — that asymmetry
# is the point, not a bug.
#
# The number stays the number, so colour is a second channel over a value that
# already reads on its own (the same rule the model chip follows) — a terminal
# that drops the SGR loses nothing. Missing token counts fall back to the old dim
# gray rather than guessing a band from the percentage — that path is for a
# Claude Code too old to send the two fields, and ONLY that: a fresh pane sends
# a real 0/0 (the payload builder defaults them, it never omits them), so it
# renders a green 0%, which is what it should.
#
# The bands share their colours with the chips either side — the ⇡ rice-nag is
# yellow at the same 179 and red at the same 167, and the child-PR cluster's open
# PRs are green at the same 71 — so at ≥200k a stale-rice pane shows two red
# numbers side by side meaning unrelated things. Accepted: each chip carries its
# own glyph (⇡, %, $) and the tail-group order is fixed, so the position tells
# you which is which before the colour does. Same trade the tint paragraph makes
# above.
CTX="$DIM"
if [ -n "$ctx_tok" ]; then
  if   [ "$ctx_tok" -ge 200000 ]; then CTX="$DEL"
  elif [ "$ctx_tok" -ge 100000 ]; then CTX="$WARN"
  else                                 CTX="$ADD"
  fi
fi
tailseg=""
[ -n "$nagseg" ] && tailseg="$nagseg"
[ -n "$ctx" ]  && tailseg="${tailseg:+$tailseg }${CTX}${ctx}%${R}"
[ -n "$cost" ] && [ "$cost" != "0" ] && tailseg="${tailseg:+$tailseg }${DIM}\$$(printf '%.2f' "$cost" 2>/dev/null)${R}"
[ -n "$mseg" ] && tailseg="${tailseg:+$tailseg }$mseg"
[ -n "$MODEL" ] && tailseg="${tailseg:+$tailseg }$MODEL"
# The child-PR cluster leads the group, held off the chips by two spaces so a run
# of bare numbers can't be misread as part of "⇡3 42% $1.23 O5".
[ -n "$prcluster" ] && tailseg="$prcluster${tailseg:+  $tailseg}"
if [ -n "$tailseg" ]; then
  pad=$(( COLS - RESERVE - $(vlen "$row1") - $(vlen "$tailseg") ))
  if [ "$pad" -ge 3 ]; then
    row1="$row1$(printf '%*s' "$pad" '')$tailseg"
  else
    row1="$row1   $tailseg"
  fi
fi
emit "$row1"

# --- refresh the (shared) panel cache if stale, detached --------------------
stale=1
if [ -f "$PANEL" ]; then
  age=$(( $(date +%s) - $(mtime "$PANEL") ))
  ttl=$TTL
  [ -f "$PANEL_COVERED" ] && [ "$HAUS_GH_BACKSTOP" -gt "$ttl" ] && ttl=$HAUS_GH_BACKSTOP
  # Back to $TTL, never below it. A delivery cancels the STRETCH; it does not
  # buy a faster poll than an un-bridged machine gets, or an org hook's
  # workflow_run storm would turn every prompt into a `gh pr list` per repo.
  haus_gh_fresh_since "$PANEL" && ttl=$TTL
  [ "$age" -lt "$ttl" ] && stale=0
fi
[ "$stale" = 1 ] && [ -x "$REFRESHER" ] && { nohup "$REFRESHER" >/dev/null 2>&1 & disown 2>/dev/null || true; }

# --- ROW 2+ : the worktrees THIS session spawned (panel parent == cwd), plus, in
# the $HOME pane only, orphan worktrees (no recorded parent) so nothing hides ----
[ -f "$PANEL" ] || exit 0
# panel.tsv is stable in registry order. Preserve that order within each group,
# but move the exact state render_status turns into ⏏ behind every active row
# BEFORE applying MAX_ROWS. Otherwise eight landed children can consume the cap
# and make a ninth, unmerged child disappear into "+N more".
ordered_panel() {
  awk -F'\t' '
    $7 ~ / merged$/ { reapable = reapable $0 ORS; next }
    { print }
    END { printf "%s", reapable }
  ' "$PANEL"
}
shown=0; extra=0
while IFS=$'\t' read -r pslug pname pahead pfiles pins pdel ppr pparent; do
  [ -n "$pname" ] || continue
  [ "$ppr" = "-" ] && ppr=""                    # decode empty-prstate sentinel
  orphan=0
  if [ "$pparent" = "$cwd" ]; then
    :                                           # a worktree I spawned
  elif [ "$is_home" = 1 ] && [ -z "$pparent" ]; then
    orphan=1                                    # unattributed — surfaced only at $HOME
  else
    continue
  fi
  if [ "$shown" -ge "$MAX_ROWS" ]; then extra=$((extra+1)); continue; fi
  pst=$(render_status "$pahead" "$pfiles" "$pins" "$pdel" "$ppr" 0)
  # Hyperlink the PR number to its GitHub page (OSC 8). The URL is reconstructed
  # from the slug + number the refresher already cached — no extra gh call.
  prnum="${ppr%% *}"                            # "#40" (empty when no PR)
  prurl=""; [ -n "$ppr" ] && prurl="https://github.com/${pslug}/pull/${prnum#\#}"
  prseg=$(render_pr "$ppr" "$prurl")
  repo="${pslug##*/}"
  # width-aware truncation: only clip the name if the row would exceed COLS.
  # Size the PR segment from its VISIBLE text ("#40"), since the OSC 8 hyperlink
  # in prseg carries the URL as zero-width bytes that plain() can't strip.
  bullet="$pst"; [ -z "$bullet" ] && bullet="${DOT}●${R}"
  bulletplain=$(plain "$bullet"); bulletlen=${#bulletplain}
  # An orphan has no recorded parent — a raw `git worktree add` that skipped
  # `scruff child`, so nothing in the registry knows who owns it. It rides in
  # front of the repo name because the bullet slot is the STATUS token now
  # (rice#…, "Prioritize active Claude statusline rows"), which is what took
  # the old leading ◇ away and left orphans rendering identically to real
  # children — invisible, in the one pane that surfaces them at all.
  mark=""; [ "$orphan" = 1 ] && mark="${PURGE}◇${R}"
  marklen=0; [ -n "$mark" ] && marklen=1
  prlen=${#prnum}; [ "$prlen" -gt 0 ] && prlen=$((prlen+1))   # +1 for trailing space
  budget=$(( COLS - 4 - bulletlen - marklen - ${#repo} - prlen ))
  [ "$budget" -lt 8 ] && budget=8
  disp="$pname"
  [ ${#disp} -gt "$budget" ] && disp="${disp:0:budget-1}…"
  emit "  ${bullet} ${mark}${DIM}${repo}${R} ${prseg:+$prseg }${disp}"
  shown=$((shown+1))
done < <(ordered_panel)
[ "$extra" -gt 0 ] && emit "  ${DIM}+${extra} more${R}"
exit 0

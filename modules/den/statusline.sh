#!/usr/bin/env bash
# statusline.sh — nebelhaus agent-worktree statusline for Claude Code.
#
# Row 1  : THIS session's git-status token as the leading glyph (⏏/N^/+A-D, or a
#          muted ● when clean) + its own PR number (left of the name, colored by
#          PR state, same as the children) + worktree name, then flush right:
#          rice-nag (⇡N — commits your pinned nebelhaus is behind, `haus update`)
#          · ctx% · cost · permission-mode icon (blank auto, ⏵ default, ⏵⏵ accept,
#          ⏵⏵⏵ bypass, ⏸ plan, ⊘ dontAsk) · model tier chip (O5 / S5 / H45 / F5).
# Row 2+ : the worktrees THIS session spawned (its direct children via ⌘A /
#          `claude --worktree`), across whatever repos they live in — each as
#          repo, PR number (left of the name, colored by PR state), name, and
#          the same status token as row 1.
#
# Lineage: `wt create` records each worktree's parent (the cwd it was spawned
# from) in its registry; the refresher carries that into panel.tsv, and a
# session lists only the rows whose parent == its own cwd.
#
# The status token is a single mutually-exclusive slot:
#     ⏏  (orange)   branch is merged/landed → `wt` reaps it on pane close
#     N^ (orange)   the PR merged and N commits landed on the branch SINCE: work
#                   no PR covers and nothing pushed (GitHub deleted the remote
#                   branch at merge). `wt reship` opens the follow-up.
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
REFRESHER="$(command -v claude-statusline-refresh 2>/dev/null || echo "$HOME/.claude/statusline-refresh.sh")"
TTL=15          # seconds before the sister-repo panel is considered stale
MAX_ROWS=8      # cap child rows; extras collapse into a "+N more" line

# 256-colour palette — muted, rice-consistent (cf. `wt`: 103 gray, 167 red).
c() { printf '\033[38;5;%sm' "$1"; }
DOT=$(c 108); DIM=$(c 244); GRAY=$(c 103); NAME=$'\033[1m'
AHEAD=$(c 75); ADD=$(c 71); DEL=$(c 167); PURGE=$(c 173)
PR_OPEN=$(c 71); PR_MERGED=$(c 139); PR_CLOSED=$(c 167)
R=$'\033[0m'

# render_status <ahead> <files> <ins> <del> <prstate> <purge>
# Emits the single status token. purge=1 => branch would be reaped (row-1 only).
# prstate feeds the merged→⏏ and merged+K→K^ checks; the PR number itself is
# rendered by render_pr as its own segment, left of the worktree name.
render_status() {
  local ahead=${1:-0} files=${2:-0} ins=${3:-0} del=${4:-0} pr="$5" purge=${6:-0}
  local st="" state="${pr##* }" relanded=""
  # merged+K (see the refresher): the PR merged, then K more commits landed on the
  # branch. ⏏ — "nothing left here, wt reaps it on pane close" — is a LIE about
  # that pane: those K commits have no PR, no remote branch (GitHub deleted it at
  # merge), and `wt` correctly refuses to reap them. The bar said done while the
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
# hyperlink-aware terminal (Ghostty) ⌘-click opens the PR; terminals/multiplexers
# that swallow OSC 8 (some tmux builds — anthropics/claude-code#21586, #27047)
# just show the colored "#N" with no link, which is a harmless graceful downgrade.
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

in=$(cat)
j() { printf '%s' "$in" | jq -r "$1 // empty"; }
cwd=$(j '.workspace.current_dir // .cwd'); [ -z "$cwd" ] && cwd="$PWD"
# The $HOME pane is the catch-all: it alone also surfaces "orphan" worktrees
# (ones with no recorded parent — e.g. a raw `git worktree add` that skipped
# `wt child`), so a stray worktree is never fully invisible, while every other
# session stays quiet and shows only the worktrees it actually spawned.
is_home=0; [ "$cwd" = "$HOME" ] && is_home=1
wt_name=$(j '.worktree.name // .workspace.git_worktree')
ctx=$(j '.context_window.used_percentage')
cost=$(j '.cost.total_cost_usd')
transcript=$(j '.transcript_path')
COLS=${COLUMNS:-120}

# Pane → transcript map, consumed by pounce's Links command (modules/pounce/
# commands/links.sh). This render is the one process that knows BOTH which
# zellij pane it lives in ($ZELLIJ_PANE_ID, inherited through Claude Code) and
# which session transcript that pane is showing (stdin) — so it maintains the
# join. Upsert keyed by pane id, write only on change: a pane id reused after a
# session restart is corrected by that pane's next render, and a lost race
# between two concurrent renders heals the same way. Tiny file; no pruning.
if [ -n "${ZELLIJ_PANE_ID:-}" ] && [ -n "$transcript" ]; then
  map="$CACHE_DIR/pane-transcripts.tsv"
  if [ "$(awk -F'\t' -v id="$ZELLIJ_PANE_ID" '$1==id{v=$2} END{print v}' "$map" 2>/dev/null)" != "$transcript" ]; then
    [ -d "$CACHE_DIR" ] || mkdir -p "$CACHE_DIR"
    {
      awk -F'\t' -v id="$ZELLIJ_PANE_ID" '$1!=id' "$map" 2>/dev/null
      printf '%s\t%s\n' "$ZELLIJ_PANE_ID" "$transcript"
    } >"$map.$$" && mv -f "$map.$$" "$map"
  fi

  # zreload needs a collision-proof mapping across zellij server restarts.
  # Pane ids are reused, so launch.sh gives each new server a generation token.
  # Store one atomic file per pane instead of another shared TSV: concurrent
  # statusline renders can never overwrite a sibling pane's identity.
  generation="${NEBELHAUS_ZELLIJ_GENERATION:-}"
  session="${ZELLIJ_SESSION_NAME:-}"
  if [ -n "$generation" ] && [ -n "$session" ]; then
    case "$generation/$session/$ZELLIJ_PANE_ID" in
      *[!A-Za-z0-9_.\/-]*) ;;
      *"/../"*|*"/.."|../*) ;;
      *)
        generation_dir="$CACHE_DIR/pane-transcripts-v2/$generation/$session"
        [ -d "$generation_dir" ] || mkdir -p "$generation_dir"
        printf '%s\n' "$transcript" >"$generation_dir/$ZELLIJ_PANE_ID.$$"
        mv -f "$generation_dir/$ZELLIJ_PANE_ID.$$" "$generation_dir/$ZELLIJ_PANE_ID"
        ;;
    esac
  fi
fi

# Usage limits → the sill `claudeUsage` pill (modules/sill/sketchybar/plugins/
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
  printf '%s\t%s\t%s\t%s\t%s\tclaude\n' \
    "${now5:-0}" "${noww:-0}" "${rst5:-0}" "${rstw:-0}" "$(date +%s)" \
    >"$usage.$$" && mv "$usage.$$" "$usage_claude" && cp "$usage_claude" "$usage"
  pill="$HOME/.config/sketchybar/plugins/ai_usage.sh"
  if [ "$was" != "$(printf '%s\t%s' "${now5:-0}" "${noww:-0}")" ] && [ -x "$pill" ]; then
    # Detached: a render must never block on sketchybar's socket.
    (SENDER=refresh NAME=ai_usage "$pill" >/dev/null 2>&1 &)
  fi
fi

# Permission mode. Read from the transcript tail because there is NO other
# source: it is absent from the statusline stdin payload (see the schema at
# code.claude.com/docs/en/statusline — cwd/model/cost/context_window/fast_mode/
# effort/vim/pr/worktree, no permission mode), and NO hook event fires on a mode
# flip either (ConfigChange is settings-FILE changes only; PreToolUse & friends
# carry `permission_mode` but only fire inside a turn).
#
# THE LIMITATION, because it looks like a bug otherwise: Claude Code writes the
# {"type":"permission-mode","permissionMode":"…"} record at TURN BOUNDARIES, not
# on every flip. Cycling shift+tab between turns writes nothing — so the icon
# shows the mode as of your LAST SUBMITTED TURN and will sit still while you
# cycle. (Verified: a session that shift+tab'd into plan mode and back logged 10
# consecutive "auto" records ~35KB apart, one per turn, and no "plan" at all.)
# Claude Code does re-run this script on a mode change; the input is what's
# stale, so no amount of re-running fixes it. That's fine for what this chip is
# actually for — catching a mode that CHANGED UNDER YOU (switching to a model
# with no auto mode drops you to `default`), which persists across turns and so
# lights up on the very next one. Don't "fix" it by adding a hook; there isn't
# one. 64KB of tail keeps this O(1); `permissionMode` is stamped on user records
# too, so the window almost always holds one.
mode=""
[ -n "$transcript" ] && [ -f "$transcript" ] &&
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
MODEL=""
model_id="$(j '.model.id')"
case "$model_id" in
  *fable*)  mletter=F; mcolor=$'\033[35m';;
  *mythos*) mletter=M; mcolor=$'\033[35m';;
  *opus*)   mletter=O; mcolor="$DIM";;
  *sonnet*) mletter=S; mcolor="$DIM";;
  *haiku*)  mletter=H; mcolor="$DIM";;
  *)        mletter="";  mcolor="$DIM";;
esac
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
fi

# Row 1's own PR: the detached refresher already cached this branch's PR state in
# the panel, so read our own row (gh-free in the render path) and render it just
# like the children — a "#N" pill left of the name, colored by PR state. It also
# lights the ⏏: purge catches an ancestor-merged branch locally, but a
# squash/rebase merge lands the work under a NEW commit that's never an ancestor,
# so the panel's merged state is the only signal for those.
own_pr=""
if [ "$is_wt" = 1 ] && [ -f "$PANEL" ]; then
  # Match our own panel row by (slug, name). slug is the remote-derived owner/name
  # (same parse the refresher uses) — NOT the local dir name, which can differ
  # (e.g. dir "nebelhaus" but slug "nebelhaus/workshop").
  slug=$(g remote get-url origin 2>/dev/null)
  slug=${slug%.git}; slug=${slug#*://}; slug=${slug#*@}; slug=${slug#*[:/]}
  if [ -n "$slug" ]; then
    own_pr=$(awk -F'\t' -v n="$wt_name" -v s="$slug" \
      '$1==s && $2==n { print $7; exit }' "$PANEL")
    [ "$own_pr" = "-" ] && own_pr=""
  fi
fi

# --- ROW 1 : status-as-bullet + PR pill + name (no repo name, no "clean") -------
# The git-status token IS the leading glyph: ⏏ landed / N^ ahead / +A -D dirty,
# colored by state. A worktree almost always has one (a fresh checkout at main
# is already ⏏); when nothing differs the token is empty, so fall back to a
# muted ● (clean / at-main). The model glyph used to sit here — it moved to the
# tail (per-pane, next to ctx%/cost/mode). The PR "#N" pill follows the lead,
# left of the name, same as the children.
st=$(render_status "$ahead" "$files" "$ins" "$del" "$own_pr" "$purge")
lead="$st"; [ -z "$lead" ] && lead="${DOT}●${R}"
# Hyperlink the own pill to its PR (OSC 8), same as the sister/child rows — the
# url is rebuilt from the slug + number already in hand (no extra gh call). This
# is what makes a worktree pane's OWN "#N" ⌘-clickable; before, only the sister
# cluster and row-2 children got urls, so an in-worktree pane's own pill was dead.
prnum="${own_pr%% *}"          # "#104"
ownurl=""; [ -n "$own_pr" ] && ownurl="https://github.com/${slug}/pull/${prnum#\#}"
prseg=$(render_pr "$own_pr" "$ownurl")   # "#N" left of the name, mirroring the children
if [ "$is_wt" = 1 ]; then
  row1="${lead} ${prseg:+$prseg }${NAME}${wt_name}${R}"
elif [ -n "$branch" ]; then
  row1="${lead} ${NAME}${branch}${R}"
else
  row1="${lead} ${DIM}$(basename "$cwd")${R}"
fi

# PR-link cluster: bare PR numbers (no '#') for every worktree THIS session
# spawned, space-separated and pinned to the far LEFT of row 1 — before the lead
# glyph/name. Each is an OSC 8 hyperlink to its PR, colored by state. Row 1 is
# the last line a growing input composer clips, so these links stay reachable
# even when the per-worktree rows below scroll out of view.
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
  [ -n "$prcluster" ] && row1="$prcluster $row1"
fi

# Mode icon: Claude Code's own glyph language (⏸ plan, ⏵ armed), our palette.
# AUTO is the blank one — it's the rice's `permissions.defaultMode` (hearth sets
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
# rice, which ships stock `pkgs.claude-code` (hearth/default.nix), but by a host
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

# Stale-rice nag: "⇡6" = your pinned nebelhaus is 6 commits behind upstream, i.e.
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
    ncol=$(c 179)
    [ "$nlockdate" -gt 0 ] &&
      [ $(( ( $(date +%s) - nlockdate ) / 86400 )) -ge "$NAG_ALERT_DAYS" ] && ncol="$DEL"
    if [ -n "${nagurl:-}" ]; then
      nagseg=$(printf '\033]8;;%s\033\\%s⇡%s%s\033]8;;\033\\' "$nagurl" "$ncol" "$nbehind" "$R")
    else
      nagseg="${ncol}⇡${nbehind}${R}"
    fi
  fi
fi

# Tail group (rice-nag · ctx% · cost · mode icon · model) sits flush RIGHT, next
# to Claude Code's own right-edge chips (/rc); RESERVE leaves them room. Narrow
# pane → fall back to the old inline append. wc -m under a UTF-8 locale counts
# the wide glyphs as characters (≈ columns), not bytes. The model chip is last —
# nearest /rc — and unlike the others it's always present. The nag leads the group:
# it's machine-global (same in every pane) while everything after it is
# per-session, so it stays put instead of shuffling with ctx%/cost.
vlen() { plain "$1" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' '; }
RESERVE=8
tailseg=""
[ -n "$nagseg" ] && tailseg="$nagseg"
[ -n "$ctx" ]  && tailseg="${tailseg:+$tailseg }${DIM}${ctx}%${R}"
[ -n "$cost" ] && [ "$cost" != "0" ] && tailseg="${tailseg:+$tailseg }${DIM}\$$(printf '%.2f' "$cost" 2>/dev/null)${R}"
[ -n "$mseg" ] && tailseg="${tailseg:+$tailseg }$mseg"
[ -n "$MODEL" ] && tailseg="${tailseg:+$tailseg }$MODEL"
if [ -n "$tailseg" ]; then
  pad=$(( COLS - RESERVE - $(vlen "$row1") - $(vlen "$tailseg") ))
  if [ "$pad" -ge 3 ]; then
    row1="$row1$(printf '%*s' "$pad" '')$tailseg"
  else
    row1="$row1   $tailseg"
  fi
fi
printf '%s\n' "$row1"   # %s: row 1 may carry OSC 8 links whose ST '\' %b would eat

# --- refresh the (shared) panel cache if stale, detached --------------------
stale=1
if [ -f "$PANEL" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$PANEL" 2>/dev/null || echo 0) ))
  [ "$age" -lt "$TTL" ] && stale=0
fi
[ "$stale" = 1 ] && [ -x "$REFRESHER" ] && { nohup "$REFRESHER" >/dev/null 2>&1 & disown 2>/dev/null || true; }

# --- ROW 2+ : the worktrees THIS session spawned (panel parent == cwd), plus, in
# the $HOME pane only, orphan worktrees (no recorded parent) so nothing hides ----
[ -f "$PANEL" ] || exit 0
shown=0; extra=0
while IFS=$'\t' read -r pslug pname pahead pfiles pins pdel ppr pparent; do
  [ -n "$pname" ] || continue
  [ "$ppr" = "-" ] && ppr=""                    # decode empty-prstate sentinel
  orphan=0
  if [ "$pparent" = "$cwd" ]; then
    :                                           # a worktree I spawned
  elif [ "$is_home" = 1 ] && [ -z "$pparent" ]; then
    orphan=1                                     # unattributed — surfaced only at $HOME
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
  stplain=$(plain "$pst"); stlen=${#stplain}
  prlen=${#prnum}; [ "$prlen" -gt 0 ] && prlen=$((prlen+1))   # +1 for trailing space
  budget=$(( COLS - 4 - ${#repo} - 1 - prlen - stlen - 4 ))
  [ "$budget" -lt 8 ] && budget=8
  disp="$pname"
  [ ${#disp} -gt "$budget" ] && disp="${disp:0:budget-1}…"
  # Orphans get an orange ◇ (vs the children's gray ○) — a "no parent, adopt or
  # reap me" flag, only ever seen in the $HOME pane.
  bullet="${GRAY}○${R}"; [ "$orphan" = 1 ] && bullet="${PURGE}◇${R}"
  # %s (not %b): prseg's OSC 8 bytes include a literal ST backslash that %b would
  # eat; every color code here is already a materialized ESC byte, so %s is exact.
  printf '%s\n' "  ${bullet} ${DIM}${repo}${R} ${prseg:+$prseg }${disp}${pst:+  $pst}"
  shown=$((shown+1))
done <"$PANEL"
[ "$extra" -gt 0 ] && printf '%b\n' "  ${DIM}+${extra} more${R}"
exit 0

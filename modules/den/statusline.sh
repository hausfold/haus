#!/usr/bin/env bash
# statusline.sh — nebelhaus agent-worktree statusline for Claude Code.
#
# Row 1  : THIS session's git-status token as the leading glyph (⏏/N^/+A-D, or a
#          muted ● when clean) + its own PR number (left of the name, colored by
#          PR state, same as the children) + worktree name, then flush right:
#          rice-nag (⇡N — commits your pinned nebelhaus is behind, `haus update`)
#          · ctx% · cost · permission-mode icon (⏸ plan, ⏵⏵ auto/accept/bypass, ⊘
#          dontAsk) · model glyph (✦ Fable/Mythos) — read from the transcript tail.
# Row 2+ : the worktrees THIS session spawned (its direct children via ⌘C /
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
# prstate only feeds the merged→⏏ check; the PR number itself is rendered by
# render_pr as its own segment, left of the worktree name.
render_status() {
  local ahead=${1:-0} files=${2:-0} ins=${3:-0} del=${4:-0} pr="$5" purge=${6:-0}
  local st="" state="${pr##* }"
  local done=0; { [ "$purge" = 1 ] || [ "$state" = merged ]; } && done=1
  if [ "$done" = 1 ]; then
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
  case "$state" in open) col="$PR_OPEN";; merged) col="$PR_MERGED";; closed) col="$PR_CLOSED";; esac
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

# Permission mode: NOT in the statusline stdin, but Claude Code appends a
# {"type":"permission-mode","permissionMode":"…"} record to the transcript on
# every mode change (and stamps user records too), and re-runs the statusline
# when the mode flips — so the last occurrence in the transcript tail IS the
# live mode, no hook or stash file needed. 64KB of tail keeps this O(1).
mode=""
[ -n "$transcript" ] && [ -f "$transcript" ] &&
  mode=$(tail -c 65536 "$transcript" 2>/dev/null |
    grep -o '"permissionMode": *"[a-zA-Z]*"' | tail -1 | grep -o '[a-zA-Z]*"$')
mode=${mode%\"}

# Model tier indicator: a ✦ ONLY when the session runs a Mythos-class model
# (fable/mythos in model.id), nothing otherwise — a pure "special model" flag,
# blank at the baseline like the mode icon. ANSI magenta — slot 5, not a fixed
# 256 index — so it renders through the terminal theme (nebelung maps it to pink
# #f2c4e5). It rides the RIGHT-edge tail group (ctx% · cost · mode), NOT the
# row-1 bullet: model is per-SESSION (each ⌘C pane is its own session; --model /
# mid-session /model switches), a per-pane constant that pairs naturally with
# the other per-pane chips — and it frees the bullet to carry the worktree's git
# status. Per-pane by design: any global surface (a rewritten custom-theme file)
# would lie in a mixed-model fleet. Tried, reverted.
MODEL=""
case "$(j '.model.id')" in
  *fable*|*mythos*) MODEL=$'\033[35m'"✦${R}";;
esac

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
    case "${cpr##* }" in open) ccol="$PR_OPEN";; merged) ccol="$PR_MERGED";; closed) ccol="$PR_CLOSED";; *) ccol="$DIM";; esac
    clink=$(printf '\033]8;;https://github.com/%s/pull/%s\033\\%s%s%s\033]8;;\033\\' \
              "$cslug" "$cnum" "$ccol" "$cnum" "$R")
    prcluster="${prcluster:+$prcluster }$clink"
  done <"$PANEL"
  [ -n "$prcluster" ] && row1="$prcluster $row1"
fi

# Mode icon: Claude Code's own glyph language (⏸ plan, ⏵⏵ armed), our palette.
# default/unknown stays blank — quiet is the baseline, the icon marks the
# armed/special modes. Pairs with the rice's de-footered claude build (the
# stock "⏵⏵ auto mode on (shift+tab to cycle)" row is patched out).
mseg=""
case "$mode" in
  auto)              mseg="$(c 179)⏵⏵${R}";;   # yellow — asks via classifier
  acceptEdits)       mseg="${ADD}⏵⏵${R}";;     # green  — edits sail through
  plan)              mseg="${AHEAD}⏸${R}";;    # blue   — paused to plan
  dontAsk)           mseg="${DEL}⊘${R}";;      # red    — deny-if-not-allowed
  bypassPermissions) mseg="${DEL}⏵⏵${R}";;     # red    — no gates at all
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
# the wide glyphs as characters (≈ columns), not bytes. The model glyph, when
# present (Fable/Mythos only), is last — nearest /rc. The nag leads the group:
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

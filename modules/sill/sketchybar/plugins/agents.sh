#!/bin/bash
# agents.sh — the reader half of the `agents` bar item (opt-in via
# haus.sill.items.agents). Surfaces the state of your agent worktree panes in the
# menu bar so you never have to cycle zellij tabs hunting for the one that's
# blocked on you. Client-agnostic: Claude Code, Codex and Opencode panes all
# land here, and each popup row is marked with the client sitting in it.
#
# State is written by agents-hook.sh from each client's own lifecycle hooks
# (authoritative — no screen-scraping), one file per pane under
# /tmp/nebelhaus-agents/*.state, each:
#     <state>\t<session>\t<pane-id>\t<label>\t<epoch>\t<client>
# <client> is the newest field: a file written before it existed reads as empty,
# which provider_style draws as the generic mark rather than lying about a client.
# A `.cwd` sibling (same base name) carries the pane's checkout path, which the
# popup joins against `holt --json`'s lane `.path` to pull in repo/branch/PR
# context — see "the holt join" below.
#
# Four entry paths:
#   • agent_update / system_woke / periodic  → recount, repaint icon+label
#   • mouse.clicked                          → (re)build + toggle the popup list
#   • `agents.sh row <sess> <pane>`          → popup-row click: go-to (left) or
#                                              peek (⌥/right), per $BUTTON/$MODIFIER
#
# ── the pill: waiting always wins ─────────────────────────────────────────────
# The pill can only show one number, so it can't average across states — it has
# to pick the one worth interrupting you for. A permission prompt sitting idle
# is more urgent than five agents quietly working, so `waiting` (renamed "ready"
# in the UI — an agent blocked on a prompt is ready for YOUR turn) outranks
# `working`, which outranks `idle` ("done"). The label carries the word, not
# just the count: a bare "3" makes you open the popup to learn what kind of 3.
#
# ── the popup: same grammar as ai_usage.sh's dropdown ─────────────────────────
# Borrowed wholesale from the aiUsage pill (see its header comment for the full
# rationale) rather than reinvented: a brand-coloured mark identifies WHO, a
# ladder-coloured value says WHAT STATE, dim descriptors on the left never
# carry colour themselves, and italic footnotes are for staleness/hints, never
# data. One thing this popup adds that aiUsage's doesn't need: every row in an
# agent's block shares one click target (go-to/peek), not just one — a header a
# few pixels tall is a bad target for "this is the pane I meant".
#
# ── the holt join ──────────────────────────────────────────────────────────────
# `agents-hook.sh` only ever knew state + a checkout basename, which is NOT
# unique — `holt child` names a child lane after its parent pane's own lane, so
# a single agent that spawned an out-of-repo worktree reports the same basename
# for two different repos (see AGENTS.md's "workshop worktree can't see child
# repos" section). The `.cwd` sibling breaks the tie: it's the one thing that
# maps 1:1 to a `holt --json` lane's `.path`. That command can spend seconds on
# landed-verdict network checks, so the update path refreshes a TTL cache in the
# background and the click path only reads the last valid result. When the cache
# is still empty, or a pane's cwd isn't a holt lane at all, the block just skips
# the repo/PR rows — degrading to what the pill showed before this existed, not
# an error or a blocked popup.
set -u
# Work whether we're run by the bar (rich env) or invoked from a bare env (an
# agent's hook, or a popup click needing zellij/aerospace): guarantee the nix
# profile + Homebrew on PATH, and $USER (sketchybar-msg resolves its socket via
# it). Set USER before PATH since PATH interpolates it.
export USER="${USER:-$(id -un)}"
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"
source "$HOME/.config/sketchybar/colors.sh"
# $SB — which bar this pill lives on (haus.sill.bottom.items can move it to
# the bottom bar, a separate SketchyBar instance addressed by its own
# binary). SILL_ITEM is the fallback bar.sh needs on the HOOK path: invoked
# from outside SketchyBar there is no $BAR_NAME to route on, and not every
# caller sets $NAME either.
SILL_ITEM=agents
source "$HOME/.config/sketchybar/bar.sh"

source "$HOME/.config/sketchybar/sizes.sh"
# provider_style() — the same client icon table the aiUsage pill draws from, so
# a Codex pane wears the same mark in both pills.
# shellcheck source=./ai-provider.sh
source "$HOME/.config/sketchybar/plugins/ai-provider.sh"

DIR=/tmp/nebelhaus-agents
PLUGINS="$HOME/.config/sketchybar/plugins"
PAW=$(printf '\xEF\x86\xB0')   # nf-fa-paw (U+F1B0) — on-theme for the cat rice
HOLT_CACHE_DIR="${CLAUDE_STATUSLINE_CACHE:-$HOME/.cache/claude-statusline}"
HOLT_CACHE="$HOLT_CACHE_DIR/holt.json"
HOLT_KICK="$HOLT_CACHE_DIR/.holt-kick"
HOLT_LOCK="$HOLT_CACHE_DIR/.holt-refresh.lock"
HOLT_TTL=120                    # lane/PR state does not need sub-minute freshness
HOLT_MAX_AGE=900                # persistent failure eventually drops stale PR rows
HOLT_TIMEOUT=60                 # bound a wedged git/gh call before lock recovery
HOLT_LOCK_STALE=90              # recover a refresher killed before releasing its lock

release_holt_lock() {
  local token="$1"
  if [ "$(cat "$HOLT_LOCK/owner" 2>/dev/null)" = "$token" ]; then
    rm -f "$HOLT_LOCK/owner"
    rmdir "$HOLT_LOCK" 2>/dev/null || true
  fi
}

refresh_holt_cache() {
  local token="$1" tmp
  tmp=$(mktemp "$HOLT_CACHE_DIR/.holt-json.XXXXXX") || {
    release_holt_lock "$token"
    return 0
  }
  if /usr/bin/perl -e 'alarm shift; exec @ARGV' "$HOLT_TIMEOUT" holt --json \
    >"$tmp" 2>/dev/null \
    && jq -e '(.lanes // []) | type == "array"' "$tmp" >/dev/null 2>&1; then
    mv -f "$tmp" "$HOLT_CACHE"
  else
    rm -f "$tmp"
  fi
  # A stale owner may have been replaced while this slow process was alive.
  # Only the process that still owns the lock may remove it.
  release_holt_lock "$token"
}

# state → colour + human tag. waiting (a permission prompt) is the urgent one,
# and is worded "ready" throughout the UI — it means "ready for your turn",
# which is the reading that actually matters when you glance at the bar.
state_style() {
  case "$1" in
    waiting) COL=$PEACH; TAG="ready"   ;;
    working) COL=$SKY;   TAG="working" ;;
    idle)    COL=$GREEN; TAG="done"    ;;
    *)       COL=$TEXT;  TAG="$1"      ;;
  esac
}

# ── popup-row click: go to the agent (left) or peek it (⌥/right) ──────────────
if [ "${1:-}" = "row" ]; then
  sess="$2"; pane="$3"
  # A plain click sends MODIFIER=none (not empty), so test against "none" — any
  # real modifier (alt/cmd/shift/ctrl) or a right-click means "peek instead".
  if [ "${BUTTON:-left}" = "right" ] || [ "${MODIFIER:-none}" != "none" ]; then
    # peek: live-tail the pane in a throwaway Ghostty, without stealing focus.
    # float-term centers it on the current screen (this window used to spawn
    # wherever AppKit last left one) and floats it via the shared helper.
    "$HOME/.config/zellij/float-term.sh" spawn --title "peek" \
      --w 900 --h 560 --pin \
      --command "/bin/bash $PLUGINS/agents-peek.sh $sess $pane" >/dev/null
  else
    # go-to: focus the pane (zellij jumps to its tab), then raise the terminal
    # window showing that session. Match the Ghostty window whose title carries
    # the session name (zellij titles the terminal with it); fall back to just
    # activating Ghostty. Only works for an attached session — a detached one
    # (0 clients) isn't in any window, so nothing to raise.
    zellij --session "$sess" action focus-pane-id "$pane" 2>/dev/null
    win=$(aerospace list-windows --all --format '%{window-id} %{app-name} %{window-title}' 2>/dev/null \
          | grep -w Ghostty | grep -F "$sess" | head -1 | awk '{print $1}')
    if [ -n "$win" ]; then aerospace focus --window-id "$win" 2>/dev/null; else open -a Ghostty; fi
  fi
  "$SB" --set agents popup.drawing=off
  exit 0
fi

# ── drop rows whose pane is gone ─────────────────────────────────────────────
# The state files are self-reported, so a client that never says goodbye leaves
# its last row on the bar forever. Claude Code has SessionEnd and Opencode has
# dispose; CODEX HAS NEITHER — its hook events end at Stop — so without this a
# finished Codex pane would sit there as a green paw until the 12h sweep below.
#
# zellij knows, and answers from outside a session (the bar is not in one):
# `action list-panes` prints one `terminal_<id>` per line, the exact key these
# filenames carry. Two answers are actionable and everything else is left
# alone — a transient zellij failure must never wipe live agents:
#   • a real list (has the PANE_ID header) → drop the panes not in it
#   • "Session 'x' not found"              → drop every row of that session
# One call per session with rows, on a 10s while-visible tick. Cheap.
prune_dead_panes() {
  [ -d "$DIR" ] || return 0
  command -v zellij >/dev/null 2>&1 || return 0
  local f base sess pane panes
  for sess in $(
    for f in "$DIR"/*.state; do
      [ -e "$f" ] || continue
      base="${f##*/}"; printf '%s\n' "${base%%__*}"
    done | sort -u
  ); do
    panes="$(zellij --session "$sess" action list-panes 2>&1)"
    case "$panes" in
      *PANE_ID*) ;;                       # a real list — fall through and diff it
      *"not found"*) rm -f "$DIR/${sess}__"*.state; continue ;;
      *) continue ;;                      # anything else: leave the rows alone
    esac
    for f in "$DIR/${sess}__"*.state; do
      [ -e "$f" ] || continue
      base="${f##*/}"; pane="${base##*__}"; pane="${pane%.state}"
      printf '%s\n' "$panes" | grep -q "^${pane}[[:space:]]" || rm -f "$f"
    done
  done
}
prune_dead_panes

# Backstop cleanup for what that can't see (a whole zellij server gone, a client
# that wrote a row from a pane id zellij never knew): reap state files untouched
# for >12h. Live agents re-stamp their epoch on every hook.
[ -d "$DIR" ] && find "$DIR" -name '*.state' -mmin +720 -delete 2>/dev/null

# Iterate the glob with a -e guard rather than an array: macOS bash 3.2 under
# `set -u` throws on "${arr[@]}" when the array is empty, and "no agents" is the
# common case. The literal-pattern-when-no-match is caught by [ -e ].

ago() { # ago <seconds> — "4m" / "1h 12m" / "2d", how long an agent has sat in
  # its current state. Identical to ai_usage.sh's helper of the same name —
  # duplicated rather than shared, since neither popup is a stable library the
  # other should import from yet (see modules/sill's other *_lib.sh files for
  # where that line actually gets drawn, e.g. vitals_lib.sh between cpu/memory).
  awk -v s="${1:-0}" 'BEGIN {
    m = int(s / 60); h = int(m / 60); d = int(h / 24)
    if      (d >= 1) printf "%dd %dh", d, h % 24
    else if (h >= 1) printf "%dh %dm", h, m % 60
    else             printf "%dm", m
  }'
}

# ── the column grid — identical math to ai_usage.sh, see its comment for why
# a label can't be indented with leading spaces (sketchybar trims on size and
# draws untrimmed, so a leading run of spaces buys a clipped row, not a margin).
ROW_INDENT=22                    # left margin of a value row, under its header
DESC_COLS=4                      # widest descriptor: `repo` (the state row's own
                                  # descriptor is empty — its value is the state
                                  # word itself, so it just gets the full margin)
DESC_GAP=12                      # descriptor → value gutter
ADV_M=$(awk -v s="${FS_SMALL:-13}" 'BEGIN { printf "%.0f", s * 602 }')
px() { printf '%s' $((($1 + 500) / 1000)); }
desc_pad() { # desc_pad <descriptor> [extra columns]
  px $(((DESC_COLS - ${#1} + ${2:-0}) * ADV_M + DESC_GAP * 1000))
}
LEAD=0
UNPADDED=""
unpad() { # unpad <value> → sets UNPADDED (blanks stripped) and LEAD (how many)
  UNPADDED="${1#"${1%%[! ]*}"}"
  LEAD=$(( ${#1} - ${#UNPADDED} ))
}

H_HEADER=32
H_ROW=25
H_META=20

# Every agent's block gets one click target across ALL its rows (header, state,
# repo, PR) — a taller hit area than aiUsage needs, since aiUsage's rows all
# close the popup while these route to go-to/peek. pop_add's default falls
# back to closing, for the summary header and the footer hint, which belong to
# no single agent.
ROW_CLICK=""
pop_add() { # pop_add <property=value…>
  ARGS+=(--add item "agents.popup.$i" popup.agents
    --set "agents.popup.$i"
      icon="" icon.padding_left=0 icon.padding_right=0
      label="" label.padding_left=0 label.padding_right=14
      background.drawing=off background.height="$H_ROW"
      click_script="${ROW_CLICK:-$SB --set agents popup.drawing=off}"
    "$@")
  i=$((i + 1))
}

header() { # header <icon> <font> <color> <name> [name-color]
  pop_add icon="$1" icon.font="$2" icon.color="$3" \
    icon.padding_left=10 icon.padding_right=8 \
    label="$4" label.color="${5:-$TEXT}" label.font="${BAR_FONT}:Bold:${FS_LABEL}" \
    background.height="$H_HEADER"
}

row() { # row <descriptor> <value> <color> [weight]
  unpad "$2"
  pop_add icon="$1" icon.color="$OVERLAY1" \
    icon.font="${BAR_FONT}:Regular:${FS_SMALL}" \
    icon.padding_left="$ROW_INDENT" icon.padding_right="$(desc_pad "$1" "$LEAD")" \
    label="$UNPADDED" label.color="$3" label.font="${BAR_FONT}:${4:-Bold}:${FS_SMALL}"
}

meta() { # meta <text> — a footnote. Smallest, dimmest, shortest row there is.
  pop_add label="$1" label.color="$OVERLAY0" \
    label.font="${BAR_FONT}:Italic:${FS_TINY}" \
    label.padding_left="$ROW_INDENT" background.height="$H_META"
}

# ── click: rebuild the popup as one block per agent, then toggle it ───────────
if [ "${SENDER:-}" = "mouse.clicked" ]; then
  # Closing is just hiding: a click while the popup is UP must not rebuild it
  # first (see ai_usage.sh's identical guard — this pill had the same
  # rebuild-then-toggle flash before this).
  if [ "$("$SB" --query agents 2>/dev/null | jq -r '.popup.drawing')" = "on" ]; then
    "$SB" --set agents popup.drawing=off
    exit 0
  fi

  "$SB" --remove '/agents.popup\..*/' 2>/dev/null
  ARGS=()
  i=0

  # Build the sort key up front: priority (waiting=0 … idle=2), then epoch
  # ascending — within a tier, the one that's been sitting longest is the one
  # that most needs a glance.
  files=()
  for f in "$DIR"/*.state; do
    [ -e "$f" ] || continue
    IFS=$'\t' read -r st _ _ _ epoch _ < "$f"
    case "$st" in waiting) pr=0 ;; working) pr=1 ;; idle) pr=2 ;; *) pr=3 ;; esac
    files+=("$pr"$'\t'"${epoch:-0}"$'\t'"$f")
  done

  if [ ${#files[@]} -eq 0 ]; then
    "$SB" --add item agents.popup.0 popup.agents 2>/dev/null \
      --set agents.popup.0 icon.drawing=off label="no active agents" label.color="$SUBTEXT0"
  else
    # Never run `holt --json` here: landed-verdict checks can block on the
    # network for seconds. The update path below keeps this cache warm; a first
    # click before it lands deliberately gets the existing no-lane fallback.
    lanes_json=""
    cache_at=$(stat -f %m "$HOLT_CACHE" 2>/dev/null || echo 0)
    case "$cache_at" in '' | *[!0-9]*) cache_at=0 ;; esac
    if [ $(( $(date +%s) - cache_at )) -lt "$HOLT_MAX_AGE" ] && [ -s "$HOLT_CACHE" ]; then
      lanes_json="$(cat "$HOLT_CACHE" 2>/dev/null)"
    fi
    [ -n "$lanes_json" ] || lanes_json="{}"

    waiting=0 working=0 idle=0
    for entry in "${files[@]}"; do
      case "${entry%%$'\t'*}" in 0) waiting=$((waiting+1)) ;; 1) working=$((working+1)) ;; 2) idle=$((idle+1)) ;; esac
    done

    # Summary block, only when there's more than one agent to summarise — the
    # same "no total for a total of one" rule ai_usage's ∑ row follows.
    if [ ${#files[@]} -gt 1 ]; then
      ROW_CLICK=""
      header "$PAW" "${BAR_FONT}:Bold:${FS_ICON:-$FS_LABEL}" "$TEXT" "Agents"
      parts=()
      [ "$waiting" -gt 0 ] && parts+=("$waiting ready")
      [ "$working" -gt 0 ] && parts+=("$working working")
      [ "$idle" -gt 0 ]    && parts+=("$idle done")
      # Never index parts[0] directly — waiting+working+idle can fall short of
      # the file count (a state file carrying something other than the three
      # words agents-hook.sh writes), and under `set -u` indexing an empty
      # array is a hard error, not an empty string.
      summary=""
      for p in "${parts[@]:-}"; do
        [ -n "$p" ] || continue
        summary="${summary:+$summary  ·  }$p"
      done
      [ -n "$summary" ] && row "" "$summary" "$TEXT" Regular
    fi

    now=$(date +%s)
    while IFS=$'\t' read -r _pr _epoch f; do
      [ -n "$f" ] || continue
      IFS=$'\t' read -r st sess pane label epoch client < "$f"
      state_style "$st"

      cwd=""
      cf="${f%.state}.cwd"
      [ -s "$cf" ] && cwd="$(cat "$cf")"

      lane="{}"
      if [ -n "$cwd" ] && [ "$lanes_json" != "{}" ]; then
        lane="$(printf '%s' "$lanes_json" | jq -c --arg p "$cwd" \
          '(.lanes // [])[] | select(.path == $p)' 2>/dev/null | head -1)"
        [ -n "$lane" ] || lane="{}"
      fi

      provider_style "${client:-}" "" "$FS_LABEL"
      ROW_CLICK="$PLUGINS/agents.sh row $sess $pane"

      header "$P_ICON" "$P_FONT" "$P_COLOR" "$label"
      row "" "$TAG  ·  $(ago $((now - ${epoch:-now})))" "$COL" Bold

      if [ "$lane" != "{}" ]; then
        repo="$(printf '%s' "$lane" | jq -r '.repo // ""')"
        row "repo" "${repo##*/}" "$OVERLAY1" Regular

        verdict="$(printf '%s' "$lane" | jq -r '.landed.verdict // "no"')"
        ahead="$(printf '%s' "$lane" | jq -r '.post_merge_ahead.commits // 0')"
        case "$ahead" in ''|*[!0-9]*) ahead=0 ;; esac
        case "$verdict" in
          yes)
            if [ "$ahead" -gt 0 ]; then
              # Exactly the state `holt reship` exists to fix: the PR merged,
              # but commits landed after it, so nothing carries them forward
              # on its own.
              row "PR" "+$ahead unshipped" "$PEACH" Bold
            else
              row "PR" "merged" "$GREEN" Regular
            fi
            ;;
          contained)
            # holt's own "advisory only" verdict (merge-tree-empty): the tree
            # matches main, but that can't tell a squash-merge from a branch
            # that never diverged, so `holt reap` itself won't act on it
            # without --contained. Worded to match that uncertainty rather
            # than asserting either "merged" or "no PR yet".
            row "PR" "maybe merged" "$OVERLAY1" Regular
            ;;
          *)
            row "PR" "no PR yet" "$OVERLAY1" Regular
            ;;
        esac

        dirty="$(printf '%s' "$lane" | jq -r '.dirty // false')"
        [ "$dirty" = "true" ] && meta "uncommitted changes"
      fi
    done < <(printf '%s\n' "${files[@]}" | sort -t $'\t' -k1,1n -k2,2n)

    ROW_CLICK=""
    meta "click: go to  ·  ⌥/right-click: peek"
  fi

  # One message: every row, then reveal — not `toggle`, the state was already
  # settled above (see the early-exit guard), so toggling here would flip a
  # popup we just rebuilt right back off on a stray double-fire.
  [ ${#ARGS[@]} -gt 0 ] && "$SB" "${ARGS[@]}" 2>/dev/null
  "$SB" --set agents popup.drawing=on
  # SKETCHYBAR_BIN is what sillpop resolves its own client from: unset, it
  # queries the TOP bar, finds no such item on a pill that moved to the
  # bottom one, and exits before it ever arms — leaving a dropdown nothing
  # closes but a second click on the pill.
  SKETCHYBAR_BIN="$SB" /run/current-system/sw/bin/sillpop arm agents 2>/dev/null &
  exit 0
fi

# ── update: count states, paint the pill by the most-urgent one present ───────
working=0 waiting=0 idle=0
for f in "$DIR"/*.state; do
  [ -e "$f" ] || continue
  IFS=$'\t' read -r st _ < "$f"
  case "$st" in
    working) working=$((working + 1)) ;;
    waiting) waiting=$((waiting + 1)) ;;
    idle)    idle=$((idle + 1)) ;;
  esac
done

if [ $((working + waiting + idle)) -eq 0 ]; then
  "$SB" --set agents drawing=off   # nothing running → no clutter
  exit 0
fi

# `holt --json` computes landed verdicts live and can spend seconds in git/gh.
# Kick it from the normal update path (push events plus the 10s visible tick),
# never from mouse.clicked. The TTL limits ordinary starts; an atomic lock also
# elects one winner when simultaneous hook/tick invocations see the same stale
# kick. The cache is replaced only after jq accepts the complete result, so a
# failed refresh leaves the previous lane/PR state intact until HOLT_MAX_AGE.
now=$(date +%s)
kick_at=$(stat -f %m "$HOLT_KICK" 2>/dev/null || echo 0)
case "$kick_at" in '' | *[!0-9]*) kick_at=0 ;; esac
if [ $((now - kick_at)) -ge "$HOLT_TTL" ] && command -v holt >/dev/null 2>&1; then
  mkdir -p "$HOLT_CACHE_DIR"
  if [ -d "$HOLT_LOCK" ]; then
    lock_at=$(stat -f %m "$HOLT_LOCK" 2>/dev/null || echo 0)
    case "$lock_at" in '' | *[!0-9]*) lock_at=0 ;; esac
    if [ $((now - lock_at)) -ge "$HOLT_LOCK_STALE" ]; then
      # Rename the stale lock out of the election atomically. Two reclaimers
      # may race here, but only one can move this exact directory; neither can
      # delete the fresh lock the winner (or another tick) creates afterward.
      stale_lock="$HOLT_LOCK.stale.$$.$RANDOM"
      if mv "$HOLT_LOCK" "$stale_lock" 2>/dev/null; then
        rm -f "$stale_lock/owner"
        rmdir "$stale_lock" 2>/dev/null || true
      fi
    fi
  fi
  if mkdir "$HOLT_LOCK" 2>/dev/null; then
    lock_token="$now.$$.$RANDOM"
    printf '%s\n' "$lock_token" >"$HOLT_LOCK/owner"
    touch "$HOLT_KICK"
    # The inner `&` belongs inside a short-lived subshell, matching ai_usage's
    # kick: the refresher is reparented before this plugin invocation exits, so
    # SketchyBar cannot reap the slow work with its script process.
    (refresh_holt_cache "$lock_token" >/dev/null 2>&1 &)
  fi
fi

if   [ "$waiting" -gt 0 ]; then state_style waiting; n=$waiting
elif [ "$working" -gt 0 ]; then state_style working; n=$working
else                           state_style idle;    n=$idle
fi
"$SB" --set agents drawing=on icon="$PAW" icon.color="$COL" \
  label="$n $TAG" label.color="$COL"

#!/bin/bash
# widget: interval = 10
# widget: popup = true
# widget: mark = violet
# widget: segments = ready, working, done
#
# agents.sh — the reader half of the `agents` bar item (opt-in via
# haus.bar.items.agents). Surfaces the state of your agent windows in the menu
# bar so you never have to hunt the workspaces for the one that's blocked on
# you. Client-agnostic: Claude Code, Codex and Opencode all land here, and each
# popup row is marked with the client sitting in it.
#
# State is written by agents-hook.sh from each client's own lifecycle hooks
# (authoritative — no screen-scraping) into one of TWO stores, depending on
# where the agent sits. Both are normalised into one record by zmx_records /
# desktop_records below, and nothing after that point knows the difference.
#
#   • a zmx session → labels on the session itself. No file, and so no pruning:
#     labels are in-memory and die with the session. A LANE's scruff join is by
#     NAME (`scruff.<repo>.<lane>`, forced by terminal/lanes/lane-open.sh); a
#     plain window's is by the `cwd` zmx reports for it.
#   • a desktop-app session → one file per conversation under
#     /tmp/haus-agents/*.desk: <state>\t<session>\t<key>\t<label>\t<epoch>\t<client>,
#     with a `.desk.cwd` sibling for the same join.
#
# A THIRD store used to sit in front of both: `.state` files keyed by (zellij
# session, pane id), with a `prune_dead_panes` reaper asking zellij which panes
# still existed and a 12h backstop behind it. Both went with the multiplexer,
# and the reason is worth keeping: a file outlives what it describes, so it
# needs a reaper; a label cannot, so it doesn't.
#
# Four entry paths:
#   • agent_update / system_woke / periodic  → recount, repaint icon+label
#   • mouse.clicked                          → (re)build + toggle the popup list
#   • `agents.sh row <sess> <pane>`          → popup-row click: go-to (left) or
#                                              peek (⌥/right), per $BUTTON/$MODIFIER
#
# ── the pill: every state, in urgency order ───────────────────────────────────
# The pill draws ONE SEGMENT PER STATE that has agents in it — a mark and a
# count each — always in the same order: ready, working, done. It used to show
# a single winning count ("2 ready", picked because a permission prompt beats
# five agents quietly working), and the reason that had to go is that the
# ranking hid the rest: "2 ready" and "2 ready, 9 working, 4 done" drew
# identically, so the pill could not answer "is anything else going on" without
# a click. Urgency still decides the ORDER (and which state colours the bot),
# not what gets to exist.
#
# Words became marks for the same reason: "2 ready · 9 working · 4 done" is
# most of a sentence in a bar that has a notch to stay clear of, and this is a
# glanceable pill, not prose. The three marks are declared as a set beside
# $BOT below; the popup still spells the words out.
#
# Positions are FIXED — a state with a count of 0 draws nothing, but the ones
# that remain never reorder — so "is the red one there" is answerable by shape
# and position without reading a number.
#
# SketchyBar can colour a label exactly once, so three colours means three
# items: `agents` (the bot) plus agents.ready / .working / .done, with a
# `bracket` — `agents.pill` — drawing the one pill background behind whichever
# are visible AND carrying the dropdown. The framework emits all five off the
# `segments =` header; none of these ids is spelled in this file. That is why the segments carry no background of their own and no
# background padding — the bracket owns both, and a segment that kept its own
# would draw a second pill inside the first and space the marks like separate
# items. They ARE clickable: each one's click_script is this script, so the
# popup opens from anywhere on the pill.
#
# ── the popup ────────────────────────────────────────────────────────────────
# A brand-coloured MARK identifies WHO and a ladder-coloured value says WHAT
# STATE — the same two axes the aiUsage pill draws on, said through the same
# vocabulary (modules/bar/marks.nix, modules/bar/tones.nix) now that both
# pills are framework widgets. The shared table under them is ai-provider.sh,
# whose `P_COLOR` half existed only for as long as one of its two readers
# could not resolve a mark; this pill was that reader.
#
# Every row in an agent's block shares ONE click target (go-to/peek), which is
# what `popup_heading --run` is for: a heading a few pixels tall is a bad
# target for "this is the pane I meant", so the name line and the detail line
# are given the same command and the block becomes one hit area.
#
# TWO of aiUsage's rules this popup drops, because an agent block is two rows
# and aiUsage's is many. Its "dim descriptors never carry colour" assumes a
# descriptor column; there is none here — the detail line is two ANSWERS side
# by side, this lane's state and its PR's, so the left half carries the state
# tone (`popup_row --name-tone`, which exists for exactly this row) rather
# than the dim a descriptor would get. And its "footnotes are for staleness,
# never data" yields to the overflow count, which is the one number that has
# to be legible as an aside rather than as another agent.
#
# ── the scruff join ──────────────────────────────────────────────────────────────
# `agents-hook.sh` only ever knew state + a checkout basename, which is NOT
# unique — `scruff child` names a child lane after its parent pane's own lane, so
# a single agent that spawned an out-of-repo worktree reports the same basename
# for two different repos (see AGENTS.md's "workshop worktree can't see child
# repos" section). The `.cwd` sibling breaks the tie: it's the one thing that
# maps 1:1 to a `scruff --json` lane's `.path`. That command can spend seconds on
# landed-verdict network checks, so the update path refreshes a TTL cache in the
# background and the click path only reads the last valid result. When the cache
# is still empty, or a pane's cwd isn't a scruff lane at all, the block just draws
# no repo and no PR verdict — degrading to what the pill showed before this
# existed, not an error or a blocked popup.
set -u
# Work whether we're run by the bar (rich env) or invoked from a bare env (an
# agent's hook, or a popup click needing zmx/aerospace): guarantee the nix
# profile + Homebrew on PATH, and $USER (sketchybar-msg resolves its socket via
# it). Set USER before PATH since PATH interpolates it.
export USER="${USER:-$(id -un)}"
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"
# BAR_ITEM is the fallback bar.sh and barlib need on the HOOK path: agents-hook.sh
# invokes this file directly (`SENDER=refresh NAME=agents`) from outside
# SketchyBar, where there is no $BAR_NAME to route on, and the `row` modes below
# run from a popup click. The pill is movable via haus.bar.bottom.items, so a
# bare `sketchybar` would keep talking to a top-bar item that is no longer there.
BAR_ITEM=agents
source "$HOME/.config/sketchybar/barlib.sh"
# provider_style() — the same client icon table the aiUsage pill draws from, so
# a Codex pane wears the same mark in both pills.
# shellcheck source=./ai-provider.sh
source "$HOME/.config/sketchybar/plugins/ai-provider.sh"

DIR=/tmp/haus-agents
PLUGINS="$HOME/.config/sketchybar/plugins"
# Which item owns the dropdown is the RUNTIME's answer, not this file's: a
# `segments =` header makes the pill a bracket, and barlib puts the popup on
# it (see modules/bar/manifest.nix for why the bot cannot carry it — a popup
# aligns to the item holding it, and the bot is a third of this pill's width).
# So there is no $POPUP here any more; `popup_toggle` and the row builders
# already know.
# The pill's identity mark: a robot head, drawn as raw UTF-8 bytes because
# /bin/bash is 3.2 and its printf has no \u. It is the one part of the pill
# that is not a count — it says "this pill is about agents" and, by taking
# the most urgent live state's colour (see the bottom of this file), answers
# "is anything asking for me" before you have read a single digit.
BOT=$(printf '\xF3\xB0\x9A\xA9')  # nf-md-robot (U+F06A9)

# ── the three state marks ─────────────────────────────────────────────────────
# One glyph per state, so the pill can say ALL of them at once (see the pill
# section below) instead of only the most urgent. They are picked as a set, and
# the thing that makes them a set is WEIGHT: a solid disc for the state that is
# asking you something, an open ring for the ones still going, a bare stroke
# for the ones that finished. Read down the pill and the ink thins exactly as
# the urgency does — which is the part that still works in the corner of your
# eye, where the colours are too small to separate.
#
# Semantics, not decoration: `?` is literally the question a permission prompt
# is asking you; the ring is the codicon called `session_in_progress`; the tick
# is a tick. A hammer was the obvious first pick for `working` and is NOT used
# — at 17pt nf-md-hammer renders as a bare diagonal stroke, and its legible
# cousin (nf-md-hammer_wrench) is the heaviest mark of the three, which puts
# the loudest ink on the calmest state. Swap the one line if you disagree.
MARK_WAITING=$(printf '\xEF\x81\x99')  # nf-fa-question_circle (U+F059)
MARK_WORKING=$(printf '\xEE\xB1\xB7')  # nf-cod-session_in_progress (U+EC77)
MARK_IDLE=$(printf '\xEF\x80\x8C')     # nf-fa-check (U+F00C)
# The warm `scruff --json` copy, and its whole protocol — the TTL, the one-winner
# lock and the "only a complete result replaces the cache" rule — belong to
# `scruff-cache` (modules/ai/scruff-cache.sh), which the AI room puts on PATH. This
# block was where all of it was written; the Lanes palette then needed exactly
# the same cache under a much harder deadline, and a second copy of a lock
# protocol is a drift bug waiting to be found the hard way.
SCRUFF_TTL=20                     # scruff itself keeps forge answers cached for 120s
SCRUFF_MAX_AGE=900                # persistent failure eventually drops stale PR rows
SCRUFF_TIMEOUT=60                 # bound a wedged git/gh call before lock recovery

# state → tone + human tag. waiting (a permission prompt) is the urgent one,
# and is worded "ready" throughout the UI — it means "ready for your turn",
# which is the reading that actually matters when you glance at the bar.
#
# These are the LADDER's rungs, named (modules/bar/tones.nix), and they say
# what they say everywhere else in the bar. The three hexes they replace were
# picked here and mapped one to one: `bad` is red, `busy` is sky, `ok` is
# green — so nothing about this pill changed colour on the way through.
state_style() {
  case "$1" in
    # `bad`, not `warn`. This is the one state on the whole bar that is asking
    # you to stop what you are doing, and peach was reading as a warning about
    # the agent rather than a request from it.
    waiting) TONE=bad;  TAG="ready";   MARK=$MARK_WAITING ;;
    working) TONE=busy; TAG="working"; MARK=$MARK_WORKING ;;
    idle)    TONE=ok;   TAG="done";    MARK=$MARK_IDLE    ;;
    *)       TONE=text; TAG="$1";      MARK=""            ;;
  esac
}

# ── the two sources, in one shape ────────────────────────────────────────────
# Both emit the same 8-field record so everything downstream — the sort, the
# counts, the popup — reads one format and never asks where a row came from:
#
#   <priority> <since> <kind> <state> <target> <label> <client> <cwd>
#
# `kind` is `zmx` or `desktop`, and `target` is what that kind's row-click
# handler needs to find the agent again: the session name for zmx, the
# conversation key for desktop. It stays the LAST positional in the `row`
# sub-command, which is a shape inherited from when one kind's target was two
# words (a zellij session plus a pane id) and is kept because it costs nothing.
#
# zmx_records — every terminal agent. Their state lives as labels on the
# session (agents-hook.sh), which zmx holds in memory for the session's
# lifetime. So there is no reaper here and none is needed: a session that dies
# takes its labels with it, and a session that never reported (a plain `term.<n>`
# window, or an `zmx attach` you opened yourself) has no `state` label and is
# skipped.
#
# Read through ~/.config/haus/term/zmx-rows.sh — the one reader of the `zmx
# ls` wire format, reached at the same cross-room address this file already
# reaches raise-session.sh and float-term.sh. `dir` is its derived directory
# (start_dir in zmx 0.7.0, the older file:// cwd stripped of its host — the
# scruff join below wants the plain path either way; it is a field zmx keeps
# itself, which is why the hook does not have to). Filtered HERE and not with
# `zmx ls --where state=…`: in zmx 0.7.0 `--where` does not filter — it
# returns every session, labelled or not — so doing it here is the honest
# version rather than a missed optimisation. A machine without the terminal
# room has no reader — and no lanes — so the pill counts desktop agents alone.
zmx_records() {
  [ -x "$HOME/.config/haus/term/zmx-rows.sh" ] || return 0
  "$HOME/.config/haus/term/zmx-rows.sh" name,state,client,label,since,created,dir |
    awk -F'\t' '
    $1 == "" || $2 == "" { next }
    {
      pr = 3
      if      ($2 == "waiting") pr = 0
      else if ($2 == "working") pr = 1
      else if ($2 == "idle")    pr = 2
      since = ($5 == "" ? $6 : $5)
      printf "%s\t%s\tzmx\t%s\t%s\t%s\t%s\t%s\n",
        pr, (since == "" ? 0 : since), $2, $1,
        ($4 == "" ? $1 : $4), $3, $7
    }'
}

# desktop_records — the `.desk` files a desktop-client session writes. Six
# columns, normalised into the same shape zmx_records emits, so everything
# downstream is unchanged. See agents-hook.sh's desktop branch for the reasoning.
desktop_records() {
  local f st sess key label epoch client pr cwd cf
  # ── the liveness answer prune_dead_panes can't give ────────────────────────
  # A desktop row's only reaper is the client's own SessionEnd, which never
  # fires on a force-quit, a crash, a logout or an app update — and the pill's
  # LABEL is the most urgent state it can find, so one stuck row makes the bar
  # read "1 working" with nothing running, for the twelve hours until the
  # backstop sweep. A zmx row cannot accrete this way — its labels die with the
  # session — so this is the one store that still needs an outside answer.
  #
  # The app not running is that answer, and it is total: every desktop session
  # lives in the one process, so no app means no session, whatever the files
  # say. Asked through LaunchServices by BUNDLE ID rather than pgrep'ing a
  # process name — `Claude` matches haus's own `claude` CLI and anything
  # else named for it, and the bundle id is the same string the row's click
  # handler raises. Bundle-id-specific because the hook's desktop branch is
  # too: Claude Code is the only client with a desktop front end today, and a
  # reaper that guessed wider would reap rows it cannot vouch for.
  #
  # No lsappinfo, no reap: a missing tool must never wipe live agents.
  if command -v /usr/bin/lsappinfo >/dev/null 2>&1; then
    if [ -z "$(/usr/bin/lsappinfo find bundleid=com.anthropic.claudefordesktop 2>/dev/null)" ]; then
      rm -f "$DIR"/*.desk "$DIR"/*.desk.cwd 2>/dev/null
    fi
  fi
  # A `.cwd` orphaned by the 12h sweep (which only deletes the row itself)
  # would otherwise never go: a `.desk` key is a fresh uuid per conversation,
  # so unlike the pane keys these never get reused and the directory would
  # accrete one file per conversation until reboot. Keyed on its own row being
  # gone rather than on age — a live session's `.cwd` is written once and can
  # be arbitrarily older than the state beside it.
  for cf in "$DIR"/*.desk.cwd; do
    [ -e "$cf" ] || continue
    [ -e "${cf%.cwd}" ] || rm -f "$cf"
  done
  for f in "$DIR"/*.desk; do
    [ -e "$f" ] || continue
    IFS=$'\t' read -r st sess key label epoch client < "$f"
    case "$st" in waiting) pr=0 ;; working) pr=1 ;; idle) pr=2 ;; *) pr=3 ;; esac
    cwd=""
    cf="${f}.cwd"
    [ -s "$cf" ] && cwd="$(cat "$cf")"
    printf '%s\t%s\tdesktop\t%s\t%s\t%s\t%s\t%s\n' \
      "$pr" "${epoch:-0}" "$st" "$key" "$label" "$client" "$cwd"
  done
}

# ── popup-row click: go to the agent (left) or peek it (⌥/right) ──────────────
# `agents.sh row <kind> <target…>` — see the record contract above for why the
# target is last.
if [ "${1:-}" = "row" ] && [ "${2:-}" = "desktop" ]; then
  # Raise the desktop client, and that is the whole action — there is no
  # per-conversation window to focus (every session is a tab of one window) and
  # no peek either: a desktop session's transcript is not tailable from outside
  # the app the way `zmx tail` follows a lane. So a modifier click does the
  # same thing rather than silently doing nothing, which is the failure mode
  # that teaches you the row is broken.
  #
  # `aerospace focus` rather than `open -b`: the window usually lives on its
  # own workspace (the roster puts the client on one), and focusing by window
  # id switches to that workspace, where `open` would only activate the app
  # under whatever is in front of it. Falls back to `open -b` when AeroSpace
  # can't see a window — the app may be closed to its dock icon.
  win=$(aerospace list-windows --all --format '%{window-id}|%{app-bundle-id}' 2>/dev/null \
        | awk -F'|' '$2 == "com.anthropic.claudefordesktop" { print $1; exit }')
  if [ -n "$win" ]; then
    aerospace focus --window-id "$win" 2>/dev/null
  else
    open -b com.anthropic.claudefordesktop 2>/dev/null
  fi
  exit 0
fi

if [ "${1:-}" = "row" ] && [ "${2:-}" = "zmx" ]; then
  zsess="$3"
  if [ "${BUTTON:-left}" = "right" ] || [ "${MODIFIER:-none}" != "none" ]; then
    # peek: `zmx tail` FOLLOWS the session's output, so this is a LIVE view
    # rather than the one-shot dump the zellij path used to take, and it needs
    # no attach — it can never steal the session's keyboard or count as a client
    # on it. (agents-peek.sh, which wrapped `zellij … subscribe --pane-id`, is
    # deleted: one `zmx tail` replaces the whole script.)
    # `quick-terminal-agent-peek`, not `peek`: the prefix is what tells windows'
    # re-sort to leave a float-term popup where it was put (float-term.sh's
    # header states the rule), and the suffix keeps it apart from ⌘Y's yazi
    # panel — float-term finds a window it just spawned by exact title, so two
    # popups sharing one would race for each other's window.
    "$HOME/.config/haus/term/float-term.sh" spawn --title "quick-terminal-agent-peek" \
      --w 900 --h 560 --pin \
      --command "zmx tail $zsess" >/dev/null
  else
    # go-to: raise the window. terminal/scripts/raise-session.sh owns the joins
    # — an exact window-title match for a lane, the window-id label
    # scripts/launch.sh stamps for a plain `term.<n>` window that happens to
    # hold an agent, and whether either is spelled AeroSpace or Ghostty on this
    # machine. ⌘F's ⏎ calls the same script; this pair used to be two copies of
    # it, both AeroSpace-only.
    #
    # A session with no window is detached and still running — the whole point
    # of zmx — so a row always opens one rather than pretending nothing is
    # there. WHICH window depends on what the session is, and for a lane it is
    # never `--or-open`: a lane whose window was closed with ⌘W, or one still
    # being tiled, would be answered with a BARE window — born on whatever
    # page you are standing on, floated by windows' on-window-detected rule and
    # never tiled onto T/<repo> (raise-session.sh's own `open_window`). So ask
    # scruff for a lane instead: that drives the resume seam, which is
    # lane-open.sh's foreground path, and the window lands titled and tiled on
    # the repo's page. Everything that is not a lane keeps `--or-open`, which is
    # exactly right for a `term.<n>` window someone closed.
    #
    # The session name → <repo>/<lane> join is the REGISTRY, read the way
    # lanes/lane-seen.sh reads it and for the reason stated there: `<repo>` may
    # carry a dot (hausfold.co), so no split of `scruff.<repo>.<lane>` can tell
    # that dot from the separator. No registry, or no row for this session, and
    # this falls back to the bare window rather than doing nothing.
    if ! "$HOME/.config/haus/term/raise-session.sh" "$zsess" >/dev/null 2>&1; then
      pair=""
      # Same probe ladder as lanes/lane-seen.sh and scruff's own baseDir(): the
      # scruff-named base while it holds the registry, the legacy path while it
      # does (docs/rename.md §8.2).
      if [ -f "$HOME/.cache/scruff/registry.tsv" ]; then
        reg="$HOME/.cache/scruff/registry.tsv"
      else
        reg="${SCRUFF_BASE:-$HOME/.cache/claude-worktrees}/registry.tsv"
      fi
      [ -r "$reg" ] && pair="$(
        awk -F'\t' -v want="$zsess" '
          {
            n = split($2, p, "/")
            if (n == 0 || $1 == "") next
            # (No apostrophes — single-quoted awk.)
            if ("scruff." p[n] "." $1 == want) { print p[n] "/" $1; exit }
          }
        ' "$reg"
      )"
      # A plain redirect, never `$(…)`: a command substitution stays open until
      # every inherited descriptor is closed, so the window scruff leaves running
      # would hold this plugin open for the life of the lane (the same trap
      # launcher/commands/lanes.sh documents at its own `open_lane`).
      if [ -n "$pair" ]; then
        scruff "$pair" >/dev/null 2>&1
      else
        "$HOME/.config/haus/term/raise-session.sh" --or-open "$zsess" >/dev/null 2>&1
      fi
    fi
  fi
  exit 0
fi

# Iterate the glob with a -e guard rather than an array: macOS bash 3.2 under
# `set -u` throws on "${arr[@]}" when the array is empty, and "no agents" is the
# common case. The literal-pattern-when-no-match is caught by [ -e ].

ago() { # ago <seconds> — "4m" / "1h 12m" / "2d", how long an agent has sat in
  # its current state. Identical to ai_usage.sh's helper of the same name —
  # duplicated rather than shared, since neither popup is a stable library the
  # other should import from yet (see modules/bar's other *_lib.sh files for
  # where that line actually gets drawn, e.g. vitals_lib.sh between cpu/memory).
  awk -v s="${1:-0}" 'BEGIN {
    m = int(s / 60); h = int(m / 60); d = int(h / 24)
    if      (d >= 1) printf "%dd %dh", d, h % 24
    else if (h >= 1) printf "%dh %dm", h, m % 60
    else             printf "%dm", m
  }'
}


# ── the scruff join, in ONE jq ──────────────────────────────────────────────────
# This used to be five `jq` invocations per agent — lane lookup, repo, verdict,
# ahead, dirty. At ~7 ms a spawn against a 24 KB registry that is ~385 ms of
# the half-second it took an eleven-agent popup to open, all of it spent
# re-parsing the same JSON. Now: one pass, flattened to a TSV table, and the
# per-agent lookup is a pure-bash scan that spawns nothing at all.
#
# Two keys per lane, because there are two joins (see the render loop): the
# checkout `path` a plain window reports as its cwd, and `<repo>.<name>` for a
# lane's session, named `scruff.<repo>.<lane>`.
LANE_TABLE=""
lane_table() { # lane_table <lanes-json>
  LANE_TABLE="$(printf '%s' "$1" | jq -r '
    (.lanes // [])[] |
    [ (.path // ""),
      (((.main // "") | split("/") | last) + "." + (.name // "")),
      (.repo // ""),
      (.landed.verdict // "no"),
      (.post_merge_ahead.commits // 0),
      (.post_merge_ahead.pr // 0),
      (if .dirty == true then "dirty" else "" end)
    ] | @tsv' 2>/dev/null)"
}

L_REPO="" L_VERDICT="" L_AHEAD=0 L_PR=0 L_DIRTY=""
lane_scan() { # lane_scan <name|path> <key> → 0 and sets L_* on the first hit
  local lpath lname repo verdict ahead pr dirty
  while IFS=$'\t' read -r lpath lname repo verdict ahead pr dirty; do
    case "$1" in
      name) [ "$lname" = "$2" ] || continue ;;
      *) [ "$lpath" = "$2" ] || continue ;;
    esac
    L_REPO="$repo" L_VERDICT="$verdict" L_DIRTY="$dirty"
    case "$ahead" in '' | *[!0-9]*) L_AHEAD=0 ;; *) L_AHEAD="$ahead" ;; esac
    case "$pr" in '' | *[!0-9]*) L_PR=0 ;; *) L_PR="$pr" ;; esac
    return 0
  done <<<"$LANE_TABLE"
  return 1
}

lane_lookup() { # lane_lookup <path-key> <name-key> → 0 and sets L_* on a hit
  L_REPO="" L_VERDICT="" L_AHEAD=0 L_PR=0 L_DIRTY=""
  [ -n "$LANE_TABLE" ] || return 1
  # NAME FIRST, PATH SECOND, and the order is the whole correctness of the
  # join — testing both keys in one pass would hand the row to whichever lane
  # `scruff --json` happens to list first. For a `scruff child` zmx lane BOTH keys
  # match, and they match DIFFERENT lanes: the cwd is the PARENT's checkout
  # (lane-open.sh's SCRUFF_CHAT contract), while the session name is this lane's
  # own. Path-wins there draws a child under its parent's repo, PR verdict and
  # dirty flag — the exact confusion the name key exists to prevent.
  [ -n "$2" ] && lane_scan name "$2" && return 0
  [ -n "$1" ] && lane_scan path "$1" && return 0
  return 1
}

# ── what a lane's PR is doing, as a glyph and a word ──────────────────────────
# Sets PR_TEXT (empty = draw nothing) and PR_TONE. The ladder means here what
# it means everywhere else on the bar: `warn` is the one that wants you.
GIT_PR=$(printf '\xEF\x90\x87')     # nf-oct-git_pull_request
GIT_MERGE=$(printf '\xEF\x90\x99')  # nf-oct-git_merge
PR_TEXT="" PR_TONE=""
pr_style() {
  PR_TEXT="" PR_TONE=dim
  # `+N unshipped` is keyed on the AHEAD COUNT, not on the landed verdict, and
  # that is the whole point of the row. A lane that genuinely outran its merged
  # PR has diverged from main, so its verdict is "no" — the old `verdict == yes`
  # gate meant this case could never draw, and the single most actionable state
  # scruff knows about rendered as its exact opposite, "no PR yet".
  if [ "$L_AHEAD" -gt 0 ] && [ "$L_PR" -gt 0 ]; then
    PR_TEXT="$GIT_PR +$L_AHEAD unshipped"; PR_TONE=warn; return
  fi
  case "$L_VERDICT" in
    yes) PR_TEXT="$GIT_MERGE merged"; PR_TONE=ok ;;
    # scruff's own advisory verdict (merge-tree-empty): the tree matches main,
    # but that can't tell a squash-merge from a branch that never diverged.
    contained) PR_TEXT="$GIT_MERGE maybe merged"; PR_TONE=dim ;;
    # Nothing landed and nothing to ship. Drawing "no PR yet" on every fresh
    # lane was a row per agent that said only "this is a normal branch".
    #
    # scruff's `fresh` (via never-diverged — the lane has never committed) lands
    # here too, and deliberately: it is the state whose whole content is "nothing
    # has happened yet". It used to arrive as `yes`, because a branch cut from
    # main is trivially an ancestor of it, so every lane drew a green `merged`
    # row from the second it was spawned. Needs a scruff that reports it
    # (hausfold/scruff#48); an older one still says `yes`, and still draws
    # `merged` — the pill is the reader here, not the judge.
    *) PR_TEXT="" ;;
  esac
}

# ── the dropdown: one block per agent ────────────────────────────────────────
# Read again here rather than from the tick's state: popup_rows runs on a
# CLICK, where fetch never ran and the framework's emitted variables do not
# exist. One pass over both stores serves every row, so no two rows are
# describing different moments.
#
# ── the two-row block ─────────────────────────────────────────────────────────
# An agent is a NAME line and a DETAIL line, and nothing else. It used to be
# four rows (five when dirty), each repeating a `repo` or `PR` descriptor down
# the left margin — which put eleven agents well off the top of a screen and
# made it genuinely hard to see which detail belonged to which name. Now the
# descriptors are gone (a lane name and a state word don't need labelling), the
# PR verdict is the detail row's `--value` instead of owning a row, and a lane
# with nothing landed says NOTHING rather than "no PR yet".
#
# Both rows carry the same `--run`, which is what makes an agent's block one
# click target rather than two adjacent ones.

# Even at two rows an agent, a busy day runs off the screen edge — and a popup
# that overflows can't be scrolled, only truncated by the display. Show the
# most urgent MAX_BLOCKS (the sort is priority-then-longest-waiting) and SAY
# what was dropped: a silent cut reads as "that's everyone", which is the one
# thing this pill must never imply.
MAX_BLOCKS=8

popup_rows() {
  local rec entry lanes_json shown dropped now click left summary p
  local _pr epoch kind st target label client cwd namekey
  local waiting=0 working=0 idle=0

  # Panes and lanes land in one array, already in the shape the render loop
  # reads (see zmx_records above).
  files=()
  while IFS= read -r rec; do
    [ -n "$rec" ] && files+=("$rec")
  done < <(
    zmx_records
    desktop_records
  )

  if [ ${#files[@]} -eq 0 ]; then
    popup_row --label "no active agents" --tone dim
    return 0
  fi

  # Never run `scruff --json` here: landed-verdict checks can block on the
  # network for seconds. The tick keeps this cache warm; a first click before
  # it lands deliberately gets the existing no-lane fallback.
  lanes_json="$(scruff-cache read "$SCRUFF_MAX_AGE" 2>/dev/null)"
  [ -n "$lanes_json" ] || lanes_json="{}"

  for entry in "${files[@]}"; do
    case "${entry%%$'\t'*}" in
      0) waiting=$((waiting + 1)) ;;
      1) working=$((working + 1)) ;;
      2) idle=$((idle + 1)) ;;
    esac
  done

  # Summary block, only when there's more than one agent to summarise — the
  # same "no total for a total of one" rule ai_usage's ∑ row follows.
  if [ ${#files[@]} -gt 1 ]; then
    popup_heading --icon "$BOT" --label "Agents"
    parts=()
    [ "$waiting" -gt 0 ] && parts+=("$waiting ready")
    [ "$working" -gt 0 ] && parts+=("$working working")
    [ "$idle" -gt 0 ] && parts+=("$idle done")
    # Never index parts[0] directly — waiting+working+idle can fall short of
    # the file count (a record carrying something other than the three words
    # agents-hook.sh writes), and under `set -u` indexing an empty array is a
    # hard error, not an empty string.
    summary=""
    for p in "${parts[@]:-}"; do
      [ -n "$p" ] || continue
      summary="${summary:+$summary  ·  }$p"
    done
    # A continuation row: the name column is left blank and the value lands on
    # it, which is what puts the total under its own heading.
    [ -n "$summary" ] && popup_row --label "" --value "$summary" --tone text
  fi

  lane_table "$lanes_json"

  shown=0
  dropped=$((${#files[@]} - MAX_BLOCKS))
  [ "$dropped" -lt 0 ] && dropped=0

  now=$(date +%s)
  while IFS=$'\t' read -r _pr epoch kind st target label client cwd; do
    [ -n "$kind" ] || continue
    [ "$shown" -lt "$MAX_BLOCKS" ] || break
    # A hairline between blocks — and above the first one only when the
    # summary sits above it, so a one-agent panel is a heading and a line.
    if [ "$shown" -gt 0 ] || [ ${#files[@]} -gt 1 ]; then popup_separator; fi
    shown=$((shown + 1))
    state_style "$st"

    # Two joins, one table (see lane_lookup). A zmx session named
    # `scruff.<repo>.<lane>` (terminal/lanes/lane-open.sh) joins on that name
    # QUALIFIED BY REPO, which is why it carries the repo at all: `scruff
    # child` gives a child lane its parent's NAME, so two live lanes in
    # different repos share one and a cwd join would send a child to the
    # parent's row. Everything else joins on the checkout path.
    # `scruff.<repo>.<lane>` minus its prefix IS the table's name key
    # (`<repo>.<name>`, built the same way), so no splitting — and that is
    # not just brevity: splitting on the FIRST dot read `hausfold.co` as
    # `hausfold`, so every lane in this family's dotted repo missed the name
    # join entirely and silently fell through to the cwd one.
    namekey=""
    if [ "$kind" = zmx ]; then
      case "$target" in
        scruff.*.*) namekey="${target#scruff.}" ;;
      esac
    fi

    provider_style "${client:-}" "" "$FS_LABEL"
    click="$PLUGINS/agents.sh row $kind $target"

    popup_heading --icon "$P_ICON" --icon-font "$P_FONT" --label "$label" \
      --mark "$P_MARK" --run "$click"

    # The detail line: what this agent is doing, then where. The repo joins
    # the state word rather than owning a row — at one repo per lane it was
    # never worth a descriptor and a line of its own.
    left="$TAG  ·  $(ago $((now - ${epoch:-now})))"
    if lane_lookup "$cwd" "$namekey"; then
      [ -n "$L_REPO" ] && left="$left  ·  ${L_REPO##*/}"
      # A dot, not a footnote row. It sits with the state because that is
      # what it qualifies: this agent, right now, has uncommitted work.
      [ -n "$L_DIRTY" ] && left="$left  ●"
      pr_style
    else
      PR_TEXT="" PR_TONE=dim
    fi
    # --name-tone, because both halves are ANSWERS: the left is this lane's
    # state and the right is its PR's, and neither is labelling the other.
    popup_row --label "$left" --name-tone "$TONE" \
      --value "$PR_TEXT" --tone "$PR_TONE" --run "$click"
  done < <(printf '%s\n' "${files[@]}" | sort -t $'\t' -k1,1n -k2,2n)

  [ "$dropped" -gt 0 ] && popup_note --label "… $dropped more, quieter than these"
  popup_note --label "click: go to  ·  ⌥/right-click: peek"
  return 0
}

# One click anywhere on the pill lands here — the bot arrives through its
# mouse.clicked subscription and each segment through the click_script the
# emitter gives it, which sets SENDER to the same thing. The rebuild-then-
# toggle flash this pill used to have is `popup_toggle`'s guard now.
on_click() { popup_toggle; }

# ── the tick: count states, paint the pill by the most urgent one present ─────
# Same two sources as the popup, through the same records — a pill that counted
# only panes would read "2 working" while a third lane sat waiting on you.
fetch() {
  local st _pr _epoch _kind _rest
  local waiting=0 working=0 idle=0

  # The 12h backstop. Only `.desk` rows can go stale: a zmx row's labels die
  # with its session. A desktop row's only reaper is the client's own
  # SessionEnd, which never fires on a force-quit, a crash, a logout or an app
  # update — desktop_records' lsappinfo check catches the common case, and this
  # catches the rest. Live agents re-stamp their epoch on every hook.
  [ -d "$DIR" ] && find "$DIR" -name '*.desk' -mmin +720 -delete 2>/dev/null

  while IFS=$'\t' read -r _pr _epoch _kind st _rest; do
    case "$st" in
      working) working=$((working + 1)) ;;
      waiting) waiting=$((waiting + 1)) ;;
      idle) idle=$((idle + 1)) ;;
    esac
  done < <(
    zmx_records
    desktop_records
  )

  # `scruff --json` computes landed verdicts live and can spend seconds in
  # git/gh. Kick it from the tick, never from a click. `scruff-cache kick` owns
  # the throttle, the one-winner election and the reparenting that keeps
  # SketchyBar from reaping the slow work with its script process — this line
  # is the whole of the bar's half. Nothing running means nothing to look up.
  if [ $((working + waiting + idle)) -gt 0 ]; then
    scruff-cache kick "$SCRUFF_TTL" "$SCRUFF_TIMEOUT" >/dev/null 2>&1
  fi

  emit waiting="$waiting" working="$working" idle="$idle"
  return 0
}

# seg_draw <segment> <state> <count> — one segment of the pill, hidden at zero.
# Positions are FIXED: a state with a count of 0 draws nothing, but the ones
# that remain never reorder, so "is the red one there" is answerable by shape
# and position without reading a number.
seg_draw() {
  if [ "$3" -gt 0 ]; then
    state_style "$2"
    segment "$1" --icon "$MARK" --label "$3" --tone "$TONE"
  else
    segment "$1" --hide
  fi
}

render() {
  # Nothing running → no clutter. `pill --hide` takes the bracket down with the
  # bot (an all-hidden bracket still paints its own background), and pairs the
  # drawing=off with updates=on, so the pill keeps ticking while invisible and
  # can re-show itself — which is the door agents-hook.sh had to work around by
  # invoking this file directly. It still does, because a `.desk` write wants
  # the bar to say so NOW rather than within the interval.
  if [ $((waiting + working + idle)) -eq 0 ]; then
    pill --hide
    seg_draw ready waiting 0
    seg_draw working working 0
    seg_draw done idle 0
    return 0
  fi

  # The bot takes the most urgent state's tone — the same ranking the label
  # used to encode on its own, kept because it is the one thing that reads
  # without focusing on the pill at all.
  if [ "$waiting" -gt 0 ]; then
    state_style waiting
  elif [ "$working" -gt 0 ]; then
    state_style working
  else
    state_style idle
  fi
  pill --icon "$BOT" --tone "$TONE"

  seg_draw ready waiting "$waiting"
  seg_draw working working "$working"
  seg_draw done idle "$idle"
}

barlib_main "$@"

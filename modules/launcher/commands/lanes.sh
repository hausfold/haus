#!/bin/bash
# pounce: name = Lanes
# pounce: description = Jump to an agent lane, or search what the agents are saying
# pounce: icon = point.3.connected.trianglepath.dotted
# pounce: submenu = true

# The lane picker: every agent worktree scruff knows about, fuzzy-filtered by
# pounce, Enter focuses the lane's window. Three sources joined by the session
# name (scruff.<repo>.<lane>, the same join every zmx surface uses):
#
#   scruff-cache    a warm copy of `scruff --json` — repo, branch, live/parked,
#                 last commit. NEVER `scruff --json` on the open path; see below
#   zmx ls        the live sessions — and the agent's own state (working /
#                 waiting / done), which agents-hook.sh keeps as labels
#
# A lane with a window is focused through terminal/scripts/raise-session.sh,
# which knows how this machine finds a window (a forced title through AeroSpace,
# or a Ghostty window id where there is no tiler). A parked lane — no session,
# no window — is reopened with `scruff <repo>/<name>`, which spawns the window
# through the open seam.
#
# ── the 8-second cliff ───────────────────────────────────────────────────────
#
# A submenu command commits with pounce's `.loading` disposition: the window
# holds the skeleton until step 2 calls present(). If step 2 never comes,
# `Window.startLoading`'s fallback fades the window out after EIGHT SECONDS.
# So every exit from this script is a deadline, and there are only two ways to
# meet it — print rows, or print a row that SAYS what happened. A bare `exit 0`
# is neither: it leaves the palette pulsing at a skeleton for eight seconds and
# then vanishing, which is precisely what "Lanes does nothing" looked like on a
# machine with no lanes registered. Hence `bail`, and hence not one silent exit
# below.
#
# The same cliff is why `scruff --json` is not run here. It is an investigation,
# not a listing: `scruff list` self-heals on the way in (a parked reap sweep) and
# both that sweep and the JSON encoder dump `lsof -d cwd` machine-wide — twice
# per run, before any lane's landed/PR verdict spends its own time in git and
# `gh`. That is seconds with ZERO lanes registered, which is the answer to "is
# it slow because of the reap": near enough, and the constant half of it is
# the two lsof dumps rather than the sweep. `scruff-cache` (modules/ai) keeps one
# warm copy for the bar and for this picker; a cold cache is refreshed in the
# BACKGROUND and this open renders from what zmx already knows.
#
# The union is what makes that safe. A cached lane list can be up to $FRESH
# seconds behind, but the sessions are read live every time, so a lane spawned
# five seconds ago is on the list anyway — it just arrives with what zmx knows
# about it (state, directory) instead of a branch and a commit subject.
#
# ── searching what they're saying ────────────────────────────────────────────
#
# Type anything that matches no lane and Enter searches the TRANSCRIPTS instead
# — the term grepped across every live session's `zmx history`, matches back as
# rows, Enter focusing the session it came from. `--actions` labels that Return
# so the action bar says "Search transcripts" the moment the query stops
# matching any lane; it used to be an undocumented `/` prefix with nothing to
# suggest it existed, and a typo'd lane name fell through to `scruff <typo>/<typo>`,
# which does not search anything — it SPAWNS A LANE. A leading `/` is still
# accepted and stripped, because that is the spelling the old header taught.
# It is NOT a guaranteed escape hatch, and don't document it as one: pounce
# scores the subtitle as well as the title, and a subtitle here is a branch
# name or a directory, both full of slashes — so `/foo` can still match a row,
# and a row that matches is a row that commits. A term that collides with a
# lane belongs in ⌘⇧F, which searches every window and has no rows to lose to.
#
# One `zmx history` per session, run in PARALLEL and individually bounded —
# serial greps across a dozen sessions is the one shape guaranteed to walk off
# the same eight-second cliff the rows just cleared.
set -u

export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

PROMPT="Lanes"
ICON="point.3.connected.trianglepath.dotted"

FRESH=900       # serve the cached lane list up to this old — the same window
                # the bar's agents popup already trusts, and the zmx union
                # covers anything SPAWNED since, which is the half that moves.
                # Wide on purpose: the bar only warms this cache while an agent
                # is running (agents.sh returns before its kick when nothing
                # is), so on the very machine you open this picker to resume a
                # parked lane, every open past the window pays SYNC_BOUND
STALE=3600      # …and this is the last resort, when a bounded live refresh
                # didn't land either. Rows this old can name a lane that has
                # since been reaped — which is survivable only because opening
                # a dead row now REPORTS, rather than exiting into the void
KICK_AFTER=20   # warm it in the background past this, so the next open is
                # reading something recent. Matches the bar's own TTL
SYNC_BOUND=5    # a COLD cache is worth waiting for, but only inside the 8s
                # skeleton, and only once — a miss kicks a full-length refresh
HISTORY_BOUND=4 # per-session `zmx history` in the content search

# The one thing this script may do instead of printing rows: print ONE row that
# explains itself. See the 8-second cliff above.
bail() {
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "${2:-}" "${3:-exclamationmark.triangle}" \
    "${4:-Dismiss}" "Lanes" |
    pounce -p "$PROMPT" -i "$ICON" >/dev/null
  exit 0
}

command -v scruff >/dev/null 2>&1 ||
  bail "scruff isn't on PATH" "the lane picker has nothing to read" "questionmark.circle"
command -v jq >/dev/null 2>&1 ||
  bail "jq isn't on PATH" "the lane picker can't parse scruff's listing" "questionmark.circle"

# ── zmx: session name → "state<TAB>client<TAB>dir", the labels agents-hook.sh
# keeps, plus the directory zmx keeps itself ─────────────────────────────────
zmx_states() {
  command -v zmx >/dev/null 2>&1 || return 0
  zmx ls 2>/dev/null | awk -F'\t' '
    {
      name = ""; state = ""; client = ""; dir = ""; cwd = ""
      for (i = 1; i <= NF; i++) {
        p = index($i, "=")
        if (p == 0) { gsub(/^[ \t]+|[ \t]+$/, "", $i); if (name == "") name = $i; continue }
        k = substr($i, 1, p - 1); gsub(/^[ \t]+|[ \t]+$/, "", k)
        # The row you are attached to is marked in zmx s FIRST field
        # ("-> ** name=..."), gluing the marker onto that key; strip it or the
        # lane you are sitting in is the one row with no state.
        sub(/^[^A-Za-z_]*/, "", k)
        if (k == "name")      name   = substr($i, p + 1)
        if (k == "state")     state  = substr($i, p + 1)
        if (k == "client")    client = substr($i, p + 1)
        # `start_dir` in zmx 0.7.0, `cwd` (a file:// URL with the host in it)
        # before that — the same pair agents.sh reads, for the same reason.
        if (k == "start_dir") dir    = substr($i, p + 1)
        if (k == "cwd")       cwd    = substr($i, p + 1)
      }
      if (dir == "") dir = cwd
      sub(/^file:\/\/[^\/]*/, "", dir)
      if (name != "") printf "%s\t%s\t%s\t%s\n", name, state, client, dir
    }'
}

focus_session() {
  # terminal/scripts/raise-session.sh owns the joins, and owning them in one
  # place is the point: this was the THIRD copy of "find that session's window
  # and raise it" (the bar's agents popup and ⌘F's ⏎ were the other two), all
  # three matching a forced window title through AeroSpace — which answers
  # nothing on a machine with no tiler, so every row here fell through to a
  # scruff reopen and opened a SECOND window onto a session that already had one.
  #
  # A dead lane still has no window, still returns non-zero, and still falls
  # through to the caller's scruff reopen. No --or-open: that is the caller's
  # decision here, and `scruff` does more than attach (it can wake a parked lane).
  "$HOME/.config/haus/term/raise-session.sh" "$1" >/dev/null 2>&1
}

# Wake a parked lane, and SAY SO when it can't be woken.
#
# This was `exec scruff <repo>/<lane>` — which is right up to the moment the row
# was built from a cache that has since gone stale. A lane reaped in that
# window is gone from scruff's registry, `matchLane` answers "no lane named …"
# (scruff's drop.go) and exits non-zero, and that message goes to the pounce
# daemon's stderr, which nobody reads. A row commit is `.linger`, so the window
# has already faded by then: the palette closes and nothing happens — the exact
# failure `bail` exists to end, arriving through the one door that had no
# `bail` in it. scruff's own words go in the row, so a refusal for some OTHER
# reason (a dirty tree, a git error) doesn't get reported as "the lane is gone".
# scruff's stderr goes to a FILE rather than through `$(…)`: a command
# substitution stays open until every inherited descriptor is closed, so a
# window scruff spawns and leaves running would hold this script open forever.
# A plain redirect waits for scruff and nothing else — the lifetime `exec` had.
open_lane() {
  local log err rc
  log="$(mktemp "${TMPDIR:-/tmp}/haus-lane-open.XXXXXX" 2>/dev/null)" || log=""
  if [ -n "$log" ]; then
    scruff "$1/$2" >/dev/null 2>"$log"
    rc=$?
    err="$(tr '\n' ' ' <"$log" | cut -c1-160)"
    rm -f "$log"
  else
    scruff "$1/$2" >/dev/null 2>&1
    rc=$?
    err=""
  fi
  [ "$rc" -eq 0 ] && exit 0
  bail "Could not open $1 · $2" "${err:-scruff exited $rc}" "questionmark.circle"
}

# `scruff.<repo>.<lane>` → `<repo>/<lane>`, scruff's own address for the lane.
# The lane name is dot-free and a repo name is not (hausfold.co), so the split
# is at the LAST dot, never the first.
#
# Both prefixes: a session that predates scruff 1.2.0's rename of the join is
# still alive and still named `holt.…` until its pane closes. Drop the second
# strip at 1.3.0.
lane_address() {
  local rest="${1#scruff.}"; rest="${rest#holt.}"
  printf '%s/%s\n' "${rest%.*}" "${rest##*.}"
}

# ── step 1: the lane rows ────────────────────────────────────────────────────
states="$(zmx_states)"

# The warm copy, in the order that keeps the open fast (see the header). A
# cache inside $FRESH is served as-is; past it we pay for one bounded refresh,
# and a refresh that doesn't land inside the skeleton's budget falls back to
# whatever is on disk while a full-length one warms up behind us.
#
# LANES_FORCE_FRESH is ⌘↵'s doing (see the picker below): a person who can see
# the list is stale wants the LIVE answer, not the warm copy however young it
# is — so skip the $FRESH read entirely and sync in the foreground. Still
# bounded by $SYNC_BOUND, because a re-exec'd open presents back into the same
# 8-second skeleton every other open honours; a scruff too slow for that budget
# falls back to the last good answer rather than blanking the picker.
if [ -n "${LANES_FORCE_FRESH:-}" ]; then
  lanes_json="$(scruff-cache sync "$SYNC_BOUND" 2>/dev/null)"
  [ -n "$lanes_json" ] || lanes_json="$(scruff-cache read "$STALE" 2>/dev/null)"
else
  lanes_json="$(scruff-cache read "$FRESH" 2>/dev/null)"
  if [ -n "$lanes_json" ]; then
    [ "$(scruff-cache age 2>/dev/null || echo 0)" -ge "$KICK_AFTER" ] &&
      scruff-cache kick "$KICK_AFTER" >/dev/null 2>&1
  else
    lanes_json="$(scruff-cache sync "$SYNC_BOUND" 2>/dev/null)"
    if [ -z "$lanes_json" ]; then
      lanes_json="$(scruff-cache read "$STALE" 2>/dev/null)"
      scruff-cache kick 0 >/dev/null 2>&1
    fi
  fi
fi
# One probe before the real pass: a lane list jq refuses takes the whole picker
# down with it, INCLUDING the zmx-only rows that never needed scruff at all —
# and this is the pass whose stderr is discarded, so it would fail as an empty
# window rather than as an error. `scruff-cache` only ever installs a validated
# result, so this should be unreachable; it costs one spawn to keep it that way.
printf '%s' "$lanes_json" | jq -e '(.lanes // []) | type == "array"' >/dev/null 2>&1 ||
  lanes_json='{}'

# TSV per pounce's row protocol: title, subtitle, icon, actions, group. The
# title is exactly "repo · lane", so the session name needs no hidden field —
# it is reconstructed from the pick.
rows="$(
  printf '%s' "$lanes_json" | jq -r --arg states "$states" '
    (
      $states | split("\n") | map(select(length > 0) | split("\t"))
      | map({ (.[0]): { state: (.[1] // ""), client: (.[2] // ""), dir: (.[3] // "") } })
      | add // {}
    ) as $live
    # state precedence: the agent'"'"'s own label (working/waiting/done) beats
    # scruff'"'"'s registry state (live/parked) — the label is what the agents pill
    # shows, and the picker should agree with the bar.
    | (
        { waiting: 0, working: 1, done: 2, idle: 2,
          live: 3, stray: 4, parked: 5 }
      ) as $rank
    | (
        { working: "play.circle.fill",
          waiting: "hourglass.circle.fill",
          done:    "checkmark.circle.fill",
          idle:    "checkmark.circle.fill",
          live:    "circle.dashed",
          stray:   "exclamationmark.triangle",
          parked:  "zzz" }
      ) as $icons
    | [ .lanes[]?
        | (.main | split("/") | last) as $repo
        # The live table is the authority on which spelling this session
        # actually has: lanes opened before scruff 1.2.0 renamed the join are
        # still `holt.…` until their panes close. Prefer the new name, fall
        # back to the old one only when zmx is holding it. Drop at 1.3.0.
        | "scruff.\($repo).\(.name)" as $new
        | "holt.\($repo).\(.name)" as $old
        | (if ($live[$new] // null) == null and ($live[$old] // null) != null
           then $old else $new end) as $sess
        | (if ($live[$sess].state // "") != "" then $live[$sess].state else .state end) as $state
        # A lane with no chat of its own has no pane, no panel and no
        # transcript: `scruff child` made it so a pane could edit a second repo,
        # and its conversation lives in the pane that made it. Opening one here
        # starts a client in a checkout that never had one, which is a dud row
        # in a picker whose whole job is "take me to that agent". scruff answers
        # this with `chat` (--json, schema 2+): the lane'"'"'s own `path` when it has
        # a conversation, the parent'"'"'s path when it doesn'"'"'t.
        #
        # Filter on THAT, never on `parent`. A lane opened with ⌘↵ from inside
        # another lane'"'"'s pane is parented to that lane exactly as a `scruff
        # child` is, and it is a full lane with a window — `parent` cannot tell
        # the two apart, and hiding one of those would hide a running agent.
        #
        # Three escapes, all in the show-it direction: a live zmx session
        # outranks everything (if a window is holding it, it is openable
        # whatever scruff believes), and an absent `chat` or `path` means "not
        # determined" — an older scruff, or a client whose transcript store
        # scruff cannot probe.
        #
        # They stay listed where the accounting happens: `scruff` and `bench
        # status` still show every one, nested under its parent. A spawned lane
        # carries its own branch and its own PR, and closing the parent'"'"'s pane
        # does not reap it, so nothing may drop it everywhere at once.
        | select(($live[$sess] // null) != null
                 or (.chat // "") == "" or (.path // "") == ""
                 or .chat == .path)
        # No trailing "  —  " on a lane with no commits yet: a dangling em
        # dash reads as a truncated subject rather than as an empty one.
        | { sess: $sess, repo: $repo, lane: .name, state: $state,
            detail: (if (.last_commit // "") == "" then (.branch // "")
                     else "\(.branch)  —  \(.last_commit)" end) }
      ] as $known
    # A lane spawned since the cache was written is live in zmx and absent
    # here. Carry it anyway, with what zmx knows — a picker that omits the lane
    # you started ten seconds ago is worse than one showing a stale branch name.
    | ($known | map(.sess)) as $seen
    | [ $live | to_entries[]
        # `.key` has to be bound BEFORE the `$seen | index(…)` pipe: past that
        # bar `.` is $seen, an array, and `.key` on an array is an error jq
        # reports at runtime — which `2>/dev/null` turns into an empty picker.
        | .key as $sess
        | select((($sess | startswith("scruff.")) or ($sess | startswith("holt.")))
                 and (($seen | index($sess)) == null))
        | ($sess | ltrimstr("scruff.") | ltrimstr("holt.") | split(".")) as $p
        | { sess: $sess, repo: ($p[:-1] | join(".")), lane: ($p[-1]),
            state: (if .value.state != "" then .value.state else "live" end),
            detail: (.value.dir // "") }
      ] as $fresh
    | ($known + $fresh)
    # Most urgent first, then alphabetically — an empty query is the common
    # open, and "whatever order scruff walked the registry in" is not an answer.
    | sort_by([ ($rank[.state] // 9), .repo, .lane ])
    | .[]
    | [ "\(.repo) · \(.lane)",
        "\(.state)  \(.detail)",
        ($icons[.state] // "circle.dashed"),
        # A ROW carries its own action spec, and it is the only thing pounce
        # consults for a modifier held over a row: `--actions` labels the bar
        # only for a step with no selected row (State.swift'"'"'s `freeTextActions`),
        # and `buildCommit` FALLS BACK to the plain Return when the row declares
        # nothing for the key you pressed. So a `cmd:Refresh` that lives only in
        # `--actions` is invisible AND inert over a lane — ⌘↵ silently opens the
        # lane under the cursor. It has to be spelled here, per row, as well.
        "Open|cmd:Refresh",
        "Lanes" ]
    | @tsv
  ' 2>/dev/null
)"

if [ -z "$rows" ]; then
  # No lanes anywhere — the case that used to be a silent `exit 0`. Offer the
  # thing you actually wanted, rather than a dead row.
  spawn="$(dirname "$0")/spawn-agent.sh"
  if [ -x "$spawn" ]; then
    # Read the PICK, not the exit status: Esc and a commit differ in what comes
    # back on stdout, and only one of them means "yes, spawn one".
    choice="$(printf 'Spawn an agent lane…\t%s\tsparkles\tSpawn\tLanes\n' \
      "no lanes yet — scruff has nothing parked and nothing running" |
      pounce -p "$PROMPT" -i "$ICON")"
    [ -n "$choice" ] && exec "$spawn"
    exit 0
  fi
  bail "No lanes yet" "scruff has nothing parked and nothing running" "zzz"
fi

# --actions and the rows' own fourth field are TWO action bars, not one, and
# ⌘↵ has to be written into both to work everywhere in this picker:
#   * `--actions` is `freeTextActions`, and pounce draws it ONLY when the
#     VISIBLE list is empty (`ContentView.showFreeTextBar`) — which here means
#     a query matching no lane, and nothing else: a piped step is not
#     `isLauncher`, so its list never hides, and an empty filter shows every
#     row with one selected. (This script `bail`s before the picker when there
#     are no lanes at all, so there is no row-less open either.) That one state
#     is the transcript search's only chance to announce itself.
#   * a selected row draws its OWN spec (the fourth TSV field, "Open|cmd:Refresh"
#     above), and that spec is also what `buildCommit` consults for the modifier
#     you held — a key the row doesn't declare falls back to the plain Return.
#     So `cmd:Refresh` here alone left ⌘↵ over a lane both unlabelled and inert:
#     it just opened the lane, exactly like ↵.
# --chain enter,cmd: the TYPED-text commits — the transcript search, and a ⌘↵
# fired from that same no-match bar — re-invoke this picker, so the window
# holds its loading skeleton instead of fading out and popping back. It says
# nothing about a ROW pick: `chainActions` is read only in pounce's
# `commitText`, and `buildCommit`'s `.plain` case hard-codes `.linger` whatever
# this flag says. So a ⌘↵ refresh over a row — the common one — fades and
# re-opens, a beat slower and not worth a second commit path. The same fact
# is why `open_lane` reports a failure as a fresh row rather than into the old
# window.
selected="$(printf '%s\n' "$rows" |
  pounce -p "$PROMPT" -i "$ICON" --chain enter,cmd \
    --actions "Search transcripts|cmd:Refresh")" || exit 0
[ -n "$selected" ] || exit 0

# ⌘↵ anywhere means "the list is stale, read it live" — no matter what row was
# under the cursor. Re-exec so the whole picker rebuilds from a forced sync,
# rather than threading a fresh lane list back through the row/search branches
# below. The re-exec presents into the held skeleton this commit chained.
if [ "$(printf '%s' "$selected" | cut -f1)" = "cmd" ]; then
  exec env LANES_FORCE_FRESH=1 "$0"
fi

picked="$(printf '%s' "$selected" | cut -f2)"
[ -n "$picked" ] || exit 0

# ── a picked lane row ────────────────────────────────────────────────────────
# Row commits hand back the raw row, whose first field is the "repo · lane"
# title. Free text has no separator, and that is exactly what tells the two
# apart — a lane name you mistyped is a SEARCH, never a lane to conjure.
case "$picked" in
  *" · "*)
    repo="${picked%% · *}"
    lane="${picked##* · }"
    # Both spellings before giving up on a window: one born before scruff
    # 1.2.0 renamed the join wears the old FORCED title until it is closed, and
    # falling through to open_lane would spawn a second window for a live lane.
    sess="scruff.${repo}.${lane}"
    focus_session "$sess" && exit 0
    focus_session "holt.${repo}.${lane}" && exit 0
    # No window: parked (or the window was ⌘W'd). scruff's open seam spawns it back.
    open_lane "$repo" "$lane"
    ;;
esac

# ── free text: content search across the lanes' transcripts ──────────────────
term="${picked#/}"
[ -n "$term" ] || exit 0
command -v zmx >/dev/null 2>&1 ||
  bail "zmx isn't on PATH" "there are no transcripts to search" "questionmark.circle"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/haus-lane-search.XXXXXX")" ||
  bail "Couldn't open a scratch directory" "the transcript search has nowhere to collect hits"
trap 'rm -rf "$tmp"' EXIT

# Fan out: one grep per session, each bounded on its own, all at once. Serial
# was fine at the two sessions it was written against and walks off the
# skeleton's eight-second cliff at a dozen.
# 20 is a cap, not a target: this machine runs ~10 sessions, and a pathological
# registry should degrade to "the first 20" rather than to a fan-out nobody
# bounded. `n` is what the no-match row reports, so it counts what was SEARCHED
# — tested before the increment, or a run that stopped at the cap claims 21.
n=0
while IFS=$'\t' read -r sess _state _client _dir; do
  [ -n "$sess" ] || continue
  [ "$n" -ge 20 ] && break
  n=$((n + 1))
  # The braces + redirect catch bash's own "Alarm clock" line on a session
  # whose history doesn't come back in time — the timeout is the DESIGN here,
  # not a fault, and it has nothing to say to anyone.
  (
    { /usr/bin/perl -e 'alarm shift; exec @ARGV' "$HISTORY_BOUND" zmx history "$sess"; } 2>/dev/null |
      grep -iF -- "$term" | tail -1 | cut -c1-120 | tr '\t' ' ' >"$tmp/$n"
  ) &
done <<EOF
$states
EOF
wait

# Keyed by the loop INDEX, never by the session name. A lane name is its branch
# minus `worktree-` (scruff's Entry.Name), and a branch may hold a slash — which
# in `$tmp/$sess` is a directory that doesn't exist, so that one lane's redirect
# fails, its subshell writes nothing, and it silently never matches anything.
# The second pass walks the same list in the same order, so the index is a
# join key with no characters in it at all.
matches=""
i=0
while IFS=$'\t' read -r sess _state _client _dir; do
  [ -n "$sess" ] || continue
  [ "$i" -ge "$n" ] && break
  i=$((i + 1))
  hit="$(cat "$tmp/$i" 2>/dev/null)"
  [ -n "$hit" ] || continue
  case "$sess" in
    scruff.*|holt.*)
      rest="${sess#scruff.}"; rest="${rest#holt.}"
      title="${rest%.*} · ${rest##*.}"
      ;;
    *) title="$sess" ;;
  esac
  # A SIXTH field, past the five pounce renders: the session name, carried
  # through untouched so the row can be titled like a lane row instead of by
  # its session id. parsePlain reads parts[0…4] and hands the whole line back
  # as `raw`, so a hidden field is free — and it is the only way to keep the
  # join key when the title is no longer it.
  matches="$matches$title"$'\t'"$hit"$'\t'"text.magnifyingglass"$'\t'"Open"$'\t'"Matches"$'\t'"$sess"$'\n'
done <<EOF
$states
EOF

# The curly quotes are display text, not shell quoting — shellcheck reads every
# “ as a mistyped " and has no way to know the difference.
#
# Which is also why the braces below are not optional. In a UTF-8 locale bash
# reads the closing ” as part of the identifier, so `“$term”` looks up a
# variable named term” — unset, and this script runs under `set -u`, so the
# search dies on the line that was about to show its results. shellcheck's one
# warning near this class is the SC1111 disabled right here.
# shellcheck disable=SC1111
PROMPT="Matches for “${term}”"
ICON="text.magnifyingglass"
# shellcheck disable=SC1111
[ -n "$matches" ] ||
  bail "No transcript mentions “${term}”" \
    "searched $n live session(s) — ⌘⇧F searches every window's scrollback" \
    "text.magnifyingglass"

selected="$(printf '%s' "$matches" | pounce -p "$PROMPT" -i "$ICON")" || exit 0
# Reply is "<action>\t<raw row>", and the session is the row's hidden sixth
# field — so field 7 of the whole reply.
sess="$(printf '%s' "$selected" | cut -f7)"
[ -n "$sess" ] || exit 0
focus_session "$sess" && exit 0
# Session alive but its window ⌘W'd: same wake-up the lane rows get — and ONLY
# for a lane. A `term.<n>` shell is not a scruff address, and handing one to
# `scruff` spawns a lane in a repo named "term".
case "$sess" in
  scruff.*|holt.*)
    address="$(lane_address "$sess")"
    rm -rf "$tmp"
    trap - EXIT
    open_lane "${address%%/*}" "${address#*/}"
    ;;
esac
exit 0

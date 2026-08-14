#!/bin/bash
# github.sh — the `github` pill (opt-in via haus.sill.items.github). One pill
# over N typed SOURCES, each of which answers "how many of these are there, and
# is that bad?" — the org's open PRs, the repos whose default branch is red, or
# whatever a host's own command prints.
#
# ── why sources are typed and not one query string ────────────────────────────
# The obvious knob is a single GitHub search filter, and it is the wrong one:
# GitHub's search index carries no workflow runs at all, so "did main's last run
# pass" is unreachable through it — that answer only exists in GraphQL, as the
# statusCheckRollup of the default branch's head commit. Handing the OPTION a
# raw GraphQL query instead just moves the problem: a search result has a known
# shape (count + rows with a title, a repo and a URL) while a GraphQL document
# returns whatever tree it selected, so the pill would need paired jq paths for
# the count, the rows and the state — four coupled strings that fail at runtime,
# inside a bar plugin, where the only symptom is a pill that draws nothing.
#
# So each source names its KIND and the plugin owns the query for it:
#
#   search   a GitHub issue/PR search filter. count = total_count (which can
#            exceed the rows shown); rows are the first `limit` hits.
#   ci       the owner's repos, each one's default branch, that branch's head
#            commit's check rollup. count = how many are FAILURE/ERROR; rows are
#            those repos. This is the one search cannot do.
#   command  an arbitrary command printing `<state>\t<text>[\t<url>]` per line.
#            count = the number of lines. The escape hatch, and deliberately a
#            command rather than a query: it can do the fetching AND the shaping,
#            and you can run it in a terminal to see why it is wrong.
#
# ── how it stays off the bar's critical path ──────────────────────────────────
# Every other pill here reads something local. This one is the first that has to
# cross the network, and a SketchyBar plugin is synchronous: a 1-2s `gh` call on
# the update tick would stall the whole bar for as long as GitHub takes. So the
# tick NEVER fetches. It renders the cache under ~/.local/state/nebelhaus/github
# and, if that cache is older than SILL_GITHUB_REFRESH, detaches a `fetch` run
# that writes the cache and then --triggers github_update to repaint. Which
# means the pill is always drawing something it already had, and the network
# latency is only ever visible as a stale number for one tick.
#
# ── files ─────────────────────────────────────────────────────────────────────
#   src-<i>.tsv   one per configured source, index-keyed. Line 1 is
#                 `meta<US><state><US><count><US><title>`; every later line is
#                 `row<US><state><US><text><US><url>`, where <US> is ASCII 0x1f.
#                 NOT a tab: tab is an IFS *whitespace* character, so
#                 `IFS=$'\t' read` folds a run of them into one delimiter and an
#                 empty field simply vanishes — a source with no title would
#                 shift its severity into the title column and read fine. The
#                 unit separator is not whitespace, so every field survives.
#                 Indices past the end of the current list are swept at the top
#                 of each fetch — see do_fetch for why an orphan is not inert.
#   stamp         epoch of the last COMPLETED fetch (success or handled failure).
#   fetching      present while a fetch is in flight — the pill's "…" state, and
#                 what a second refresh click checks so it doesn't pile on.
#   lock/         mkdir-lock, so the update tick and a click can't fetch at once.
set -u
export USER="${USER:-$(id -un)}"
export PATH="/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"

source "$HOME/.config/sketchybar/colors.sh"
# $SB — which bar this pill lives on (haus.sill.bottom.items can move it to the
# bottom bar, which is a second SketchyBar instance addressed by its own
# binary). SILL_ITEM is the fallback bar.sh routes on when there is no
# $BAR_NAME, i.e. when this script is invoked by hand rather than by a bar.
SILL_ITEM=github
source "$HOME/.config/sketchybar/bar.sh"
source "$HOME/.config/sketchybar/sizes.sh"
source "$HOME/.config/sketchybar/github_config.sh"

# gh by absolute path, not off $PATH. This runs from launchd, where the PATH is
# whatever the agent's EnvironmentVariables said, and a `gh` that silently isn't
# there is indistinguishable from an empty org.
GH=/run/current-system/sw/bin/gh

STATE="$HOME/.local/state/nebelhaus/github"
STAMP="$STATE/stamp"
FETCHING="$STATE/fetching"
LOCK="$STATE/lock"

ITEM="${NAME:-github}"
now=$(date +%s)

# The rows a source may contribute to the dropdown, when it didn't say. Also the
# `per_page` a search asks GitHub for — there is no point paging in 100 hits to
# draw eight of them.
DEFAULT_LIMIT=8

# How long a fetch may claim to be running before the next caller assumes it
# died and takes over. Longer than any of these calls can take (a hung `gh` on a
# dead connection is the slow case, and it gives up well inside this), shorter
# than the shortest legal refresh, so a sweep can never race a live fetch or
# delay a healthy one.
STALE_INFLIGHT=300

# ── source table ──────────────────────────────────────────────────────────────
# SILL_GITHUB_SOURCES is one line per source, unit-separated (see the note on
# the cache format above for why not tabs):
#   <kind><US><payload><US><org><US><title><US><icon><US><severity><US><limit>
# Read into parallel arrays because bash 3.2 (what /bin/bash is on macOS) has no
# associative arrays and no nested ones.
S_KIND=(); S_PAYLOAD=(); S_ORG=(); S_TITLE=(); S_ICON=(); S_SEV=(); S_LIMIT=()
n_sources=0
if [ -n "${SILL_GITHUB_SOURCES:-}" ]; then
  while IFS=$'\037' read -r kind payload org title icon sev limit; do
    [ -n "$kind" ] || continue
    S_KIND[$n_sources]="$kind"
    S_PAYLOAD[$n_sources]="$payload"
    S_ORG[$n_sources]="$org"
    S_TITLE[$n_sources]="$title"
    S_ICON[$n_sources]="$icon"
    S_SEV[$n_sources]="${sev:-info}"
    S_LIMIT[$n_sources]="${limit:-$DEFAULT_LIMIT}"
    n_sources=$((n_sources + 1))
  done <<< "$SILL_GITHUB_SOURCES"
fi

# Nothing configured — a pill asked for with no sources has nothing it could
# ever say, so it draws nothing at all rather than a permanent zero. The Nix
# side asserts on this too; this is the belt for a hand-edited config file.
if [ "$n_sources" -eq 0 ]; then
  "$SB" --set "$ITEM" drawing=off
  exit 0
fi

# ── the tour ──────────────────────────────────────────────────────────────────
# The first-run tour hides the right-side pills for the length of its lap
# (tour.sh mute()). Our own paints have to honour that: a repaint landing after
# the tour's `drawing=off` would pop the pill back over the step labels. Read
# right before each --set, never cached, so a mute that lands mid-fetch wins.
tour_drawing() {
  local muted="$HOME/.local/state/nebelhaus/tour-muted"
  if [ -f "$muted" ] && grep -qxF github "$muted" 2>/dev/null; then
    echo off
  else
    echo on
  fi
}

# ── severity ──────────────────────────────────────────────────────────────────
# Three levels, ordered, so the pill can pick which source it is speaking for.
# `auth` and `error` are states rather than severities: they mean the number is
# unknown, which is a different thing from the number being zero.
sev_rank() {
  case "$1" in
    bad) echo 3 ;;
    warn) echo 2 ;;
    *) echo 1 ;;
  esac
}
sev_color() {
  case "$1" in
    bad) echo "$RED" ;;
    warn) echo "$PEACH" ;;
    *) echo "$TEXT" ;;
  esac
}

# ── fetch ─────────────────────────────────────────────────────────────────────
# Runs detached, never on the bar's tick. Each source writes its own cache file
# whole (tmp + mv), so a half-written file is never read and one source failing
# leaves the others' last-good numbers alone.
fetch_search() { # fetch_search <index> <query> <limit>
  local i="$1" q="$2" limit="$3" out err json
  out="$STATE/src-$i.tsv.tmp"
  err="$STATE/src-$i.err"
  # stderr to its own file rather than 2>&1 into the JSON: gh writes deprecation
  # notices and rate-limit warnings there on calls that SUCCEED, and folding
  # those into the body would leave jq parsing a message.
  #
  # advanced_search=true is not optional going forward: GitHub is retiring the
  # legacy issue-search behaviour behind this flag, and a query that works today
  # without it is one deprecation away from returning nothing.
  json=$("$GH" api --method GET search/issues \
    -f q="$q" -F per_page="$limit" -f advanced_search=true 2>"$err") || {
    classify_failure "$i" "$(cat "$err" 2>/dev/null)"
    return 0
  }
  local count
  count=$(printf '%s' "$json" | jq -r '.total_count // 0')
  {
    printf 'meta\037%s\037%s\037%s\n' "${S_SEV[$i]}" "$count" "$(source_title "$i")"
    # `repository_url` is the only place a search hit names its repo, and it is
    # an API URL — the last two path components are owner/name.
    printf '%s' "$json" | jq -r --arg sev "${S_SEV[$i]}" '
      .items[]? |
      "row\u001f" + $sev + "\u001f" +
      ((.repository_url | split("/") | .[-1]) + " #" + (.number|tostring) + "  " + .title) +
      "\u001f" + .html_url'
  } > "$out"
  mv -f "$out" "$STATE/src-$i.tsv"
  rm -f "$err"
}

fetch_ci() { # fetch_ci <index> <org> <limit>
  local i="$1" org="$2" limit="$3" out err json
  out="$STATE/src-$i.tsv.tmp"
  err="$STATE/src-$i.err"
  # repositoryOwner, not organization: GitHub's `organization(login:)` returns
  # null for a personal account, and haus.git.org is documented to accept either
  # ("GitHub's issue search treats org:<user> the same as user:<user>"). The
  # interface field works for both.
  #
  # statusCheckRollup on the default branch's HEAD COMMIT is the whole answer:
  # it is the same state GitHub paints beside a commit, folding every workflow
  # run and every legacy commit status into one. Asking for workflow runs
  # per-repo instead would be one REST call per repo, which is the rate limit
  # gone in one tick.
  json=$("$GH" api graphql -f org="$org" -F n=100 -f query='
    query($org:String!,$n:Int!){
      repositoryOwner(login:$org){
        repositories(first:$n, orderBy:{field:PUSHED_AT, direction:DESC}){
          nodes{
            name url isArchived
            defaultBranchRef{
              name
              target{ ... on Commit { statusCheckRollup{ state } } }
            }
          }
        }
      }
    }' 2>"$err") || {
    classify_failure "$i" "$(cat "$err" 2>/dev/null)"
    return 0
  }
  local rows count
  # FAILURE and ERROR are both "it went red"; PENDING is a run still going and
  # NONE is a repo with no checks at all, neither of which is a thing to report.
  rows=$(printf '%s' "$json" | jq -r '
    .data.repositoryOwner.repositories.nodes[]?
    | select(.isArchived | not)
    | select(.defaultBranchRef != null)
    | { name: .name, url: .url, br: .defaultBranchRef.name,
        st: (.defaultBranchRef.target.statusCheckRollup.state // "NONE") }
    | select(.st == "FAILURE" or .st == "ERROR")
    | "row\u001fbad\u001f" + .name + "  " + .br + "\u001f" + .url')
  count=$(printf '%s' "$rows" | grep -c '^row' 2>/dev/null || true)
  count=${count:-0}
  {
    printf 'meta\037bad\037%s\037%s\n' "$count" "$(source_title "$i")"
    [ "$count" -gt 0 ] && printf '%s\n' "$rows" | head -n "$limit"
  } > "$out"
  mv -f "$out" "$STATE/src-$i.tsv"
  rm -f "$err"
}

fetch_command() { # fetch_command <index> <command> <limit>
  local i="$1" cmd="$2" limit="$3" out rows count
  out="$STATE/src-$i.tsv.tmp"
  rows=$(bash -c "$cmd" 2>/dev/null) || {
    write_state "$i" error 0
    return 0
  }
  # The contract is `<state>\t<text>[\t<url>]`; anything else is dropped rather
  # than drawn as a mangled row, because a plugin that renders garbage teaches
  # you to distrust the pill instead of fixing the script.
  rows=$(printf '%s' "$rows" | awk -F'\t' -v US=$'\037' 'NF>=2 && ($1=="ok"||$1=="warn"||$1=="bad"){
    printf "row%s%s%s%s%s%s\n", US, $1, US, $2, US, (NF>=3 ? $3 : "") }')
  count=$(printf '%s' "$rows" | grep -c '^row' 2>/dev/null || true)
  count=${count:-0}
  {
    printf 'meta\037%s\037%s\037%s\n' "${S_SEV[$i]}" "$count" "$(source_title "$i")"
    [ "$count" -gt 0 ] && printf '%s\n' "$rows" | head -n "$limit"
  } > "$out"
  mv -f "$out" "$STATE/src-$i.tsv"
}

# What a source is called in the dropdown when it didn't say.
source_title() { # source_title <index>
  local i="$1"
  if [ -n "${S_TITLE[$i]}" ]; then
    printf '%s' "${S_TITLE[$i]}"
    return
  fi
  case "${S_KIND[$i]}" in
    ci) printf '%s' "${S_ORG[$i]} · default branches" ;;
    search) printf '%s' "${S_PAYLOAD[$i]}" ;;
    *) printf '%s' "command" ;;
  esac
}

write_state() { # write_state <index> <state> <count> — a source with no rows
  printf 'meta\037%s\037%s\037%s\n' "$2" "$3" "$(source_title "$1")" > "$STATE/src-$1.tsv"
}

# Which kind of failure, because only one of them is actionable and it is by far
# the most likely on a fresh machine: `gh` is installed by the Git pack but
# nothing logs you in, so the very first fetch on a new Mac is an auth failure.
# Telling that apart from "GitHub is down" is what lets the dropdown offer the
# one command that fixes it instead of a shrug.
classify_failure() { # classify_failure <index> <stderr>
  case "$2" in
    *"gh auth login"* | *"authentication"* | *"Bad credentials"* | *"HTTP 401"* | *"not logged"*)
      write_state "$1" auth 0 ;;
    *) write_state "$1" error 0 ;;
  esac
}

do_fetch() {
  mkdir -p "$STATE"
  # One fetch at a time. mkdir is the atomic test-and-set every POSIX shell has;
  # a stale lock from a killed run is swept after five minutes, which is longer
  # than any of these calls can take and shorter than the shortest refresh.
  if ! mkdir "$LOCK" 2>/dev/null; then
    if [ -d "$LOCK" ]; then
      local age
      age=$(( now - $(stat -f %m "$LOCK" 2>/dev/null || echo "$now") ))
      [ "$age" -lt "$STALE_INFLIGHT" ] && return 0
      rmdir "$LOCK" 2>/dev/null
      mkdir "$LOCK" 2>/dev/null || return 0
    fi
  fi
  touch "$FETCHING"

  # Drop the cache of every index past the end of the CURRENT list, before
  # writing the ones that are still there. Sources are index-keyed, so
  # shortening the list in Nix strands `src-<i>.tsv` for the entries that went
  # away, and nothing else ever collects them: this is the only writer.
  #
  # Swept rather than tolerated because an orphan is not inert. render() walks
  # the configured sources, so today it goes unread — but the moment the list
  # grows back past that index, the tick draws the stranded count as if it
  # belonged to the NEW source at that slot, for the one paint between the bar
  # restarting and the first fetch landing. First, not last, so that window is
  # closed for the whole fetch rather than only after it.
  local f idx
  for f in "$STATE"/src-*; do
    [ -e "$f" ] || continue          # no match: the glob stays literal
    idx=${f##*/src-}
    idx=${idx%%.*}                   # src-2.tsv, src-2.err, src-2.tsv.tmp → 2
    case "$idx" in
      '' | *[!0-9]*) continue ;;
    esac
    [ "$idx" -ge "$n_sources" ] && rm -f "$f"
  done

  local i
  for ((i = 0; i < n_sources; i++)); do
    if [ ! -x "$GH" ]; then
      write_state "$i" error 0
      continue
    fi
    case "${S_KIND[$i]}" in
      search) fetch_search "$i" "${S_PAYLOAD[$i]}" "${S_LIMIT[$i]}" ;;
      ci) fetch_ci "$i" "${S_ORG[$i]}" "${S_LIMIT[$i]}" ;;
      command) fetch_command "$i" "${S_PAYLOAD[$i]}" "${S_LIMIT[$i]}" ;;
    esac
  done

  date +%s > "$STAMP"
  rm -f "$FETCHING"
  rmdir "$LOCK" 2>/dev/null
  # Repaint whoever is drawing this pill. --trigger on the same instance the
  # caller belongs to, so a pill on the bottom bar isn't woken by an event sent
  # to the menu bar's mach service and nothing else.
  "$SB" --trigger github_update 2>/dev/null
}

# Detach a fetch. `setsid`-less on macOS, so a subshell with its own stdio is
# what keeps it alive past this script's exit — the same shape media_stream.sh
# and ai_usage.sh use for their background work.
#
# The in-flight flag is AGE-SWEPT, not merely tested. It is only removed by a
# do_fetch that ran to completion, so anything that kills one mid-flight — sleep,
# a reboot, `launchctl bootout`, a rebuild restarting the bar, a `gh` that hangs
# on a dead connection — leaves it behind, and a bare `[ -f ]` guard would then
# refuse every future fetch: the tick, the Refresh row and the right-click all
# come through here. The pill would sit on a frozen number (or, on a machine
# whose FIRST fetch was interrupted, on `…`) until someone deleted a file they
# have no reason to know about. Same deadline and same reasoning as the lock.
spawn_fetch() {
  if [ -f "$FETCHING" ]; then
    local age
    age=$(( now - $(stat -f %m "$FETCHING" 2>/dev/null || echo "$now") ))
    [ "$age" -lt "$STALE_INFLIGHT" ] && return 0
    rm -f "$FETCHING"
  fi
  ("$HOME/.config/sketchybar/plugins/github.sh" fetch >/dev/null 2>&1 &)
}

# ── read the cache ────────────────────────────────────────────────────────────
# Sets LEAD_* to the source the pill speaks for: the highest-severity one with a
# nonzero count, earliest in the configured order on a tie.
#
# The two failure states do NOT simply outrank a real count, and the asymmetry is
# deliberate.
#
#   auth  wins outright. It is a fact about the whole machine rather than about
#         one source — nothing that talks to GitHub is answering — so every count
#         beside it is stale by definition, and it is the one failure with a
#         command that fixes it.
#   error is a FALLBACK: it leads only when no source has a live count. One
#         source failing is not evidence about the others, and letting it win
#         would mean a `command` source ending in a `grep` that matched nothing
#         (exit 1, entirely normal) blanks a ci count that is sitting there
#         correct and red. A transient 502 on one call would do the same.
LEAD_STATE=ok
LEAD_COUNT=0
LEAD_SEV=info
read_cache() {
  local i rank best=0 kind sev count saw_error=0
  LEAD_STATE=ok; LEAD_COUNT=0; LEAD_SEV=info
  for ((i = 0; i < n_sources; i++)); do
    [ -f "$STATE/src-$i.tsv" ] || continue
    IFS=$'\037' read -r kind sev count _ < "$STATE/src-$i.tsv"
    [ "$kind" = meta ] || continue
    case "$sev" in
      auth)
        LEAD_STATE=auth; LEAD_COUNT=0
        return ;;
      error)
        saw_error=1
        continue ;;
    esac
    [ "${count:-0}" -gt 0 ] || continue
    rank=$(sev_rank "$sev")
    if [ "$rank" -gt "$best" ]; then
      best="$rank"; LEAD_SEV="$sev"; LEAD_COUNT="$count"
    fi
  done
  # Nothing to say AND something went wrong: say so, rather than drawing the
  # quiet nothing-to-report pill over a number nobody managed to fetch.
  [ "$best" -eq 0 ] && [ "$saw_error" -eq 1 ] && LEAD_STATE=error
  return 0
}

# ── paint the pill ────────────────────────────────────────────────────────────
render() {
  # Defaulted rather than named bare: the plugin directory and github_config.sh
  # are two separate home.file entries, so a rebuild that lands one before the
  # other leaves a window where this is unset — and under `set -u` that is not a
  # missing glyph, it is a pill that stops drawing until the next tick.
  local icon="${SILL_GITHUB_ICON:-}" color label ldraw=on
  if [ -f "$FETCHING" ] && [ "$(stamp_epoch)" -eq 0 ]; then
    # Only on the very first fetch, when there is genuinely nothing to show. A
    # refresh over a populated cache keeps drawing the old number instead of
    # blanking a pill you were reading.
    color="$OVERLAY0"; label="…"
  else
    read_cache
    case "$LEAD_STATE" in
      auth)
        color="$YELLOW"; label="auth" ;;
      error)
        color="$OVERLAY0"; label="—" ;;
      *)
        if [ "$LEAD_COUNT" -gt 0 ]; then
          color="$(sev_color "$LEAD_SEV")"; label="$LEAD_COUNT"
        else
          # Nothing to report: the pill goes quiet rather than drawing a zero.
          # A number you never act on is a number you stop seeing, and then so
          # is the one that matters.
          color="$OVERLAY0"; label=""; ldraw=off
        fi ;;
    esac
  fi
  "$SB" --set "$ITEM" drawing="$(tour_drawing)" \
    icon="$icon" icon.color="$color" \
    label="$label" label.color="$color" label.drawing="$ldraw"
}

# The last completed fetch, as an epoch, or 0. `cat` alone is not enough: a
# stamp that exists but is EMPTY — a fetch killed between the create and the
# write, a full disk — turns every `$((now - last))` below into an arithmetic
# syntax error, which under a bar plugin means the popup or the tick simply dies
# mid-run. Anything that isn't all digits reads as "never fetched".
stamp_epoch() {
  local v
  v=$(cat "$STAMP" 2>/dev/null)
  case "$v" in
    "" | *[!0-9]*) echo 0 ;;
    *) echo "$v" ;;
  esac
}

# ── the dropdown ──────────────────────────────────────────────────────────────
H_HEADER=32
H_ROW=25
H_META=20

open_popup() {
  read_cache
  "$SB" --remove "/${ITEM}\.popup\..*/" 2>/dev/null
  # Every row is accumulated and handed over in ONE call, so the popup appears
  # fully formed instead of growing a row at a time in front of you.
  local ARGS=() i=0 s line kind sev count title rows_drawn
  pop_add() {
    ARGS+=(--add item "${ITEM}.popup.$i" "popup.${ITEM}"
      --set "${ITEM}.popup.$i"
      icon="" icon.padding_left=10 icon.padding_right=8
      label="" label.padding_left=0 label.padding_right=14
      background.drawing=off background.height="$H_ROW"
      click_script="$SB --set ${ITEM} popup.drawing=off"
      "$@")
    i=$((i + 1))
  }

  if [ "$LEAD_STATE" = auth ]; then
    # The one actionable failure gets the one actionable row. Clicking it copies
    # the command rather than running it: `gh auth login` is interactive (it
    # wants a browser, a protocol choice and a paste-back code) and there is no
    # terminal behind a bar popup to answer any of that.
    pop_add icon="" icon.color="$YELLOW" \
      label="GitHub CLI is not logged in" label.color="$TEXT" \
      label.font="${BAR_FONT}:Bold:${FS_LABEL}" background.height="$H_HEADER"
    pop_add icon="" icon.color="$OVERLAY1" \
      label="gh auth login" label.color="$SUBTEXT0" \
      label.font="${BAR_FONT}:Bold:${FS_SMALL}" \
      click_script="printf 'gh auth login' | pbcopy; $SB --set ${ITEM} popup.drawing=off"
    pop_add icon="" label="copied to the clipboard when you click it" \
      label.color="$OVERLAY0" label.font="${BAR_FONT}:Italic:${FS_TINY}" \
      background.height="$H_META"
  else
    for ((s = 0; s < n_sources; s++)); do
      [ -f "$STATE/src-$s.tsv" ] || continue
      IFS=$'\037' read -r kind sev count title < "$STATE/src-$s.tsv"
      [ "$kind" = meta ] || continue
      # Kept aside because the row loop below reuses `sev` for each row's own
      # state — the section's verdict has to survive that.
      local msev="$sev"
      local hcolor="$OVERLAY1"
      [ "${count:-0}" -gt 0 ] && hcolor="$(sev_color "$sev")"
      pop_add icon="${S_ICON[$s]}" icon.color="$hcolor" \
        label="$title" label.color="$TEXT" \
        label.font="${BAR_FONT}:Bold:${FS_LABEL}" background.height="$H_HEADER"

      rows_drawn=0
      while IFS=$'\037' read -r kind sev text url; do
        [ "$kind" = row ] || continue
        rows_drawn=$((rows_drawn + 1))
        # A row with a URL opens it and closes the popup; one without just
        # closes, which is the pop_add default.
        if [ -n "$url" ]; then
          pop_add icon="" icon.color="$(sev_color "$sev")" \
            label="$text" label.color="$SUBTEXT0" \
            label.font="${BAR_FONT}:Regular:${FS_SMALL}" \
            click_script="/usr/bin/open '$url'; $SB --set ${ITEM} popup.drawing=off"
        else
          pop_add icon="" icon.color="$(sev_color "$sev")" \
            label="$text" label.color="$SUBTEXT0" \
            label.font="${BAR_FONT}:Regular:${FS_SMALL}"
        fi
      done < "$STATE/src-$s.tsv"

      if [ "$rows_drawn" -eq 0 ]; then
        # A source that FAILED and a source with genuinely nothing in it are the
        # same empty section otherwise, and only one of them is good news.
        local empty="nothing"
        [ "$msev" = error ] && empty="couldn't fetch this one"
        [ "$msev" = auth ] && empty="not logged in"
        pop_add icon="" label="$empty" label.color="$OVERLAY0" \
          label.font="${BAR_FONT}:Italic:${FS_TINY}" background.height="$H_META"
      elif [ "${count:-0}" -gt "$rows_drawn" ]; then
        # Never let a truncated list read as a complete one.
        pop_add icon="" label="+$((count - rows_drawn)) more" label.color="$OVERLAY0" \
          label.font="${BAR_FONT}:Italic:${FS_TINY}" background.height="$H_META"
      fi
    done
  fi

  # The refresh row, always last. Right-clicking the pill does the same thing —
  # two doors on the same action, because the pill is the obvious place to reach
  # for and the row is the discoverable one.
  local age="never" last secs
  last=$(stamp_epoch)
  if [ "$last" -gt 0 ]; then
    secs=$((now - last))
    if [ "$secs" -lt 60 ]; then age="${secs}s ago"
    elif [ "$secs" -lt 3600 ]; then age="$((secs / 60))m ago"
    else age="$((secs / 3600))h ago"; fi
  fi
  pop_add icon="" icon.color="$SKY" \
    label="Refresh · $age" label.color="$SUBTEXT0" \
    label.font="${BAR_FONT}:Bold:${FS_SMALL}" \
    click_script="$HOME/.config/sketchybar/plugins/github.sh refresh"

  [ ${#ARGS[@]} -gt 0 ] && "$SB" "${ARGS[@]}" 2>/dev/null
  "$SB" --set "$ITEM" popup.drawing=on
  # Hand it to sillpop so it also closes on the first click anywhere else — the
  # dismissal SketchyBar can't do, since it only hears clicks on its own items.
  # SKETCHYBAR_BIN is how sillpop is told which bar's popup it is guarding.
  SKETCHYBAR_BIN="$SB" /run/current-system/sw/bin/sillpop arm "$ITEM" 2>/dev/null &
}

# ── entry points ──────────────────────────────────────────────────────────────
mkdir -p "$STATE"

case "${1:-}" in
  fetch)
    do_fetch
    render
    exit 0 ;;
  refresh)
    # From the dropdown row or a right-click. Close first: the rows behind it
    # are about to be replaced, and a popup that silently swaps its contents
    # under the pointer is how you click the wrong PR.
    "$SB" --set "$ITEM" popup.drawing=off
    spawn_fetch
    render
    exit 0 ;;
  click)
    if [ "${BUTTON:-left}" = right ]; then
      "$SB" --set "$ITEM" popup.drawing=off
      spawn_fetch
      render
      exit 0
    fi
    # Closing is just hiding: a click while the popup is UP must not rebuild the
    # rows first, or closing it flashes through a re-layout on the way out.
    if [ "$("$SB" --query "$ITEM" 2>/dev/null | jq -r '.popup.drawing')" = "on" ]; then
      "$SB" --set "$ITEM" popup.drawing=off
      exit 0
    fi
    open_popup
    exit 0 ;;
esac

# The periodic tick, system_woke, and our own github_update event. Draw what we
# have, then top the cache up if it has gone stale — in that order, so the
# repaint never waits on a decision about the network.
render
last=$(stamp_epoch)
if [ "$last" -eq 0 ] || [ $((now - last)) -ge "${SILL_GITHUB_REFRESH:-300}" ]; then
  spawn_fetch
fi
exit 0

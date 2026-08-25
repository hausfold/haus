#!/bin/bash
# github.sh — the `github` pill (opt-in via haus.bar.items.github). One pill
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
#   search   a GitHub issue/PR search filter. count = the search's own hit
#            total (which can exceed the rows shown); rows are the first
#            `limit` hits, each carrying its own MERGE VERDICT — see below.
#   ci       the owner's repos, each one's default branch, that branch's head
#            commit's check rollup. count = how many are FAILURE/ERROR; rows are
#            those repos. This is the one search cannot do.
#   command  an arbitrary command printing `<state>\t<text>[\t<url>]` per line,
#            state being one rung of the colour ladder below.
#            count = the number of lines. The escape hatch, and deliberately a
#            command rather than a query: it can do the fetching AND the shaping,
#            and you can run it in a terminal to see why it is wrong.
#
# ── the merge verdict, and why the pill is two-tone ───────────────────────────
# A count of open PRs is a work queue; it says nothing about whether any of them
# is stuck. So a `search` row is not just a title: the same GraphQL call that
# counts the hits also asks each pull request whether it CONFLICTS, what its
# head commit's checks came back as, and what the review landed on, and folds
# those into one state — the same question GitHub's own merge box answers.
#
# ── the colour ladder ─────────────────────────────────────────────────────────
# Five states, one hue each, and this ladder is the whole colour system — rows,
# section headings and both halves of the pill all read off it:
#
#   mute   grey    no verdict. A draft, an issue rather than a PR, a
#                  mergeability GitHub has not computed yet. Tints nothing.
#   ok     green   green — and clear to merge, when it is also approved.
#   busy   sky     checks still running. The tone the agents pill already
#                  spends on "working": the machine has this one, not you.
#   warn   peach   wants a human on THIS pull request — it conflicts, its own
#                  checks came back red, or a reviewer asked for changes.
#   bad    red     the DEFAULT BRANCH is red.
#
# Red meaning exactly one thing is the point of the ladder. A pull request of
# yours with red checks is your branch's problem, not the repo on fire, so it
# reads peach on the rung below — a red that fires for every work-in-progress
# is a red you stop reading, and then the one that means "main is broken" has
# nothing left to say. Red reaches the rest of the pill only where a HOST put
# it there: a source declared `bad` (`severity`) paints its own count and its
# section heading red — that is a host saying "this question is on the same
# footing as a broken main" about a filter it wrote itself. A `command` source
# is the one that can also print a red ROW, because it is arbitrary code and
# its rows are its own claim rather than a verdict this plugin computed.
#
# That state colours the row's glyph, and the WORST state across every source
# colours the pill's octocat, while the number keeps the colour of the source it
# is counting. Two tones, because they are two different facts and collapsing
# them loses one of them: painting the number peach when one of five PRs
# conflicts says "five bad things" when there is one, and leaving it neutral
# says nothing is wrong at all. So the number is HOW MANY and the logo is HOW
# BAD — green included, which is not a resting state here: with nothing open
# there are no rows at all and the logo keeps the number's own grey, so a green
# octocat only ever means "there is a queue, and every row in it is fine".
#
# `mergeable` is computed lazily by GitHub: a PR nobody has asked about comes
# back UNKNOWN, and asking is what schedules the merge-commit test. That reads
# as the neutral "no verdict yet" state and resolves itself on the next refresh,
# which is why UNKNOWN is deliberately not drawn as a problem.
#
# ── how it stays off the bar's critical path ──────────────────────────────────
# Every other pill here reads something local. This one is the first that has to
# cross the network, and a SketchyBar plugin is synchronous: a 1-2s `gh` call on
# the update tick would stall the whole bar for as long as GitHub takes. So the
# tick NEVER fetches. It renders the cache under ~/.local/state/haus/github
# and, if that cache is older than BAR_GITHUB_REFRESH, detaches a `fetch` run
# that writes the cache and then --triggers github_update to repaint. Which
# means the pill is always drawing something it already had, and the network
# latency is only ever visible as a stale number for one tick.
#
# ── files ─────────────────────────────────────────────────────────────────────
#   src-<i>.tsv   one per configured source, index-keyed. Line 1 is
#                 `meta<US><state><US><count><US><title><US><worst>`; every
#                 later line is `row<US><state><US><text><US><url><US><glyph>`,
#                 where <US> is ASCII 0x1f. The two trailing fields are the
#                 merge verdict (see above) and are the newest additions, which
#                 is why they are LAST: a cache written by an older generation
#                 parses under the current reader with those fields empty, and
#                 empty is exactly the "no verdict" case both already handle.
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
# $SB — which bar this pill lives on (haus.bar.bottom.items can move it to the
# bottom bar, which is a second SketchyBar instance addressed by its own
# binary). BAR_ITEM is the fallback bar.sh routes on when there is no
# $BAR_NAME, i.e. when this script is invoked by hand rather than by a bar.
BAR_ITEM=github
source "$HOME/.config/sketchybar/bar.sh"
source "$HOME/.config/sketchybar/sizes.sh"
source "$HOME/.config/sketchybar/github_config.sh"

# gh by absolute path, not off $PATH. This runs from launchd, where the PATH is
# whatever the agent's EnvironmentVariables said, and a `gh` that silently isn't
# there is indistinguishable from an empty org.
GH=/run/current-system/sw/bin/gh

STATE="$HOME/.local/state/haus/github"
STAMP="$STATE/stamp"
FETCHING="$STATE/fetching"
LOCK="$STATE/lock"
COVERED="$STATE/pill-covered"

# ---- the GitHub bridge, where there is one ----------------------------------
# This pill is the one thing in the bar that crosses the network, which is why
# its refresh floor is 60s and its default 300. With haus.github's webhook
# bridge on this machine there is a push answer to "has anything changed", so
# the tick fetches the moment a delivery lands instead of waiting out the
# interval — and where the host has raised `haus.github.backstop` above that
# interval, the interval itself stretches to it.
#
# Sourced rather than forked: the tick is synchronous and runs every few
# seconds. Absent, both functions say no and this pill behaves exactly as it
# always has.
#
# Note the state directory is SHARED with the receiver, which is deliberate:
# both are "what this Mac knows about GitHub", and a person debugging a stale
# pill wants `last` and `stamp` in one `ls`.
if [ -r "$HOME/.config/haus/github/signal.sh" ]; then
  # shellcheck source=/dev/null
  . "$HOME/.config/haus/github/signal.sh"
else
  haus_gh_covers() { return 1; }
  haus_gh_fresh_since() { return 1; }
fi
HAUS_GH_BACKSTOP="${HAUS_GH_BACKSTOP:-0}"

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
# BAR_GITHUB_SOURCES is one line per source, unit-separated (see the note on
# the cache format above for why not tabs):
#   <kind><US><payload><US><org><US><title><US><icon><US><severity><US><limit>
# Read into parallel arrays because bash 3.2 (what /bin/bash is on macOS) has no
# associative arrays and no nested ones.
S_KIND=(); S_PAYLOAD=(); S_ORG=(); S_TITLE=(); S_ICON=(); S_SEV=(); S_LIMIT=()
n_sources=0
if [ -n "${BAR_GITHUB_SOURCES:-}" ]; then
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
  done <<< "$BAR_GITHUB_SOURCES"
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
  local muted="$HOME/.local/state/haus/tour-muted"
  if [ -f "$muted" ] && grep -qxF github "$muted" 2>/dev/null; then
    echo off
  else
    echo on
  fi
}

# ── severity ──────────────────────────────────────────────────────────────────
# One ordered scale for two related jobs: which SOURCE the pill speaks for
# (those are `info`/`warn`/`bad`, what a host writes in the option) and how bad
# a ROW is (those are `mute`/`ok`/`busy`/`warn`/`bad` — the colour ladder in the
# header, what the merge verdict resolves to, and the four a `command` source is
# allowed to print).
#
# The rungs are ordered by how much the row wants a HUMAN, which is not the same
# as how alarming it looks:
#
#   `mute` sits below `ok` on purpose. It is "no verdict" — a draft, an issue
#   rather than a PR, a mergeability GitHub has not computed yet — and a row with
#   nothing to say must never out-rank a row that came back green, or one draft
#   in the list would tint the pill for the whole queue.
#
#   `busy` sits ABOVE `ok`, because a queue with a run still going is not yet
#   the queue you can act on, and one below `warn`, because a run in flight is
#   the machine's turn and not yours.
#
#   `bad` is the top rung and it is reserved: a red default branch, or a source
#   a host declared `bad` itself. Nothing a single pull request can do reaches
#   it — see the header for why that reservation is the whole point.
#
# `info` is a SOURCE severity only, and it takes the rung BELOW `ok` rather than
# sharing it. The two are only ever compared in one place — the dropdown's
# section heading, which wears the worse of what the source is worth and what
# its rows found — and a tie there would leave an `info` queue of entirely green
# rows with a plain TEXT heading over a green octocat, i.e. the one corner of
# the new system that didn't read off the ladder.
#
# `auth` and `error` are states rather than severities: they mean the number is
# unknown, which is a different thing from the number being zero.
sev_rank() {
  case "$1" in
    bad) echo 5 ;;
    warn) echo 4 ;;
    busy) echo 3 ;;
    ok) echo 2 ;;
    mute | none | '') echo 0 ;;
    *) echo 1 ;;
  esac
}
sev_color() {
  case "$1" in
    bad) echo "$RED" ;;
    warn) echo "$PEACH" ;;
    busy) echo "$SKY" ;;
    ok) echo "$GREEN" ;;
    mute | none | '') echo "$OVERLAY0" ;;
    *) echo "$TEXT" ;;
  esac
}

# The glyph a row wears, by what the merge verdict found. Nerd Font MDI, the
# same family every other pill draws in.
G_CONFLICT="󰀩"  # md-alert_octagon — the merge itself is blocked
G_FAILED="󰅚"    # md-close_circle_outline — checks came back red
G_RUNNING="󰦖"   # md-progress_clock — checks still going
G_CHANGES="󰅾"   # md-comment_alert_outline — a reviewer wants changes
G_READY="󰄭"     # md-check_all — green AND approved: nothing left
G_GREEN="󰗡"     # md-check_circle_outline — green, review still open
G_DRAFT="󰲶"     # md-pencil_outline — a draft, deliberately not news
G_NONE="󰝦"      # md-circle_outline — no checks, or no verdict yet

# ASCII 0x1f, the field separator the cache is written in (see the header).
US=$'\037'

# The worst state among a block of already-formatted rows, as one word. Scanned
# rather than tracked per-row because every producer builds its rows in one shot
# — jq, a filter, a command's stdout — and re-walking a handful of lines is
# cheaper than threading a running maximum through three different pipelines.
rows_worst() { # rows_worst <rows>
  local s
  for s in bad warn busy ok; do
    printf '%s\n' "$1" | grep -q "^row${US}${s}${US}" && { echo "$s"; return; }
  done
  echo none
}

# ── fetch ─────────────────────────────────────────────────────────────────────
# Runs detached, never on the bar's tick. Each source writes its own cache file
# whole (tmp + mv), so a half-written file is never read and one source failing
# leaves the others' last-good numbers alone.
fetch_search() { # fetch_search <index> <query> <limit>
  local i="$1" q="$2" limit="$3" out err json
  out="$STATE/src-$i.tsv.tmp"
  err="$STATE/src-$i.err"
  # GraphQL rather than REST `search/issues`, and the merge verdict is the whole
  # reason. The count is the same index either way (`issueCount` IS
  # `total_count`), but a REST hit is an issue-shaped record: no mergeability,
  # no check rollup, no review state on it. Getting those over REST would be a
  # second call PER ROW, which is the rate limit gone in one tick. Here it is
  # one request for the count, the rows and every row's verdict — and GraphQL
  # charges by the nodes touched rather than per call, so a page of eight PRs
  # costs about what the plain search did.
  #
  # It also steps off the `advanced_search=true` treadmill: that flag exists
  # because GitHub is retiring REST's legacy issue-search behaviour, and the
  # GraphQL `search` connection was never on the old path to begin with.
  #
  # stderr to its own file rather than 2>&1 into the JSON: gh writes deprecation
  # notices and rate-limit warnings there on calls that SUCCEED, and folding
  # those into the body would leave jq parsing a message.
  json=$("$GH" api graphql -f q="$q" -F n="$limit" -f query='
    query($q:String!,$n:Int!){
      search(query:$q, type:ISSUE, first:$n){
        issueCount
        nodes{
          __typename
          ... on PullRequest {
            number title url isDraft mergeable reviewDecision
            repository{ name }
            commits(last:1){ nodes{ commit{ statusCheckRollup{ state } } } }
          }
          ... on Issue { number title url repository{ name } }
        }
      }
    }' 2>"$err") || {
    classify_failure "$i" "$(cat "$err" 2>/dev/null)"
    return 0
  }
  local rows count worst
  count=$(printf '%s' "$json" | jq -r '.data.search.issueCount // 0')
  # The verdict, in precedence order, and the order IS the design:
  #
  #   Draft first, above even a conflict. A draft is its author saying "not
  #   ready" out loud; red checks on one are expected, and letting them reach
  #   the pill would have it cry wolf for every work-in-progress on the machine.
  #   Then the two states that BLOCK a merge, worse first — a conflict (nothing
  #   about the PR can proceed) ahead of red checks (the code is the problem).
  #   Then the two that merely delay it: checks still running, then a reviewer
  #   asking for changes. Then UNKNOWN mergeability, which has to be tested
  #   HERE and not folded into the trailing else: GitHub computes it lazily, so
  #   a PR opened a moment ago comes back UNKNOWN with its checks already green
  #   — and without this arm that falls through to the `SUCCESS` case and draws
  #   an all-clear for a merge nobody has tried yet. Then the two good
  #   outcomes, of which green-and-approved gets its own glyph because it is
  #   the one row in the list that means "you can press the button".
  #   Everything else — an Issue rather than a PR, a repo with no checks — is
  #   `mute`: a row with no verdict, which must not tint the pill.
  #
  #   Note the ceiling: the WORST rung a pull request can reach here is `warn`.
  #   Conflicts and red checks used to be `bad`, which meant the pill's octocat
  #   went the same red for "one of my branches is failing CI" as for "main is
  #   broken" — and since the first is the normal state of a machine that opens
  #   PRs all day, it made the second unreadable. `bad` is the ci source's now
  #   (see the ladder in the header), and everything below it is a rung a PR
  #   can actually climb.
  #
  #   Each verdict also carries its NAME, appended to the row's text in the
  #   dropdown. Colour puts a row in a tier and the glyph says which member of
  #   it, but "conflicts" and "changes requested" are peach with a similar mark
  #   at 11pt — the word is what makes the row readable without a legend. Only
  #   the verdicts worth acting on carry one; a plain green PR reads as its
  #   title alone.
  rows=$(printf '%s' "$json" | jq -r \
    --arg conflict "$G_CONFLICT" --arg failed "$G_FAILED" --arg running "$G_RUNNING" \
    --arg changes "$G_CHANGES" --arg ready "$G_READY" --arg green "$G_GREEN" \
    --arg draft "$G_DRAFT" --arg none "$G_NONE" '
    .data.search.nodes[]?
    | select(.url != null)
    | . as $n
    | (.commits.nodes[0].commit.statusCheckRollup.state // "NONE") as $ci
    | (if $n.__typename != "PullRequest"                        then ["mute", $none,     ""]
       elif $n.isDraft                                          then ["mute", $draft,    "draft"]
       elif $n.mergeable == "CONFLICTING"                       then ["warn", $conflict, "conflicts"]
       elif $ci == "FAILURE" or $ci == "ERROR"                  then ["warn", $failed,   "checks red"]
       elif $ci == "PENDING" or $ci == "EXPECTED"               then ["busy", $running,  "checks running"]
       elif $n.reviewDecision == "CHANGES_REQUESTED"            then ["warn", $changes,  "changes requested"]
       elif $n.mergeable == "UNKNOWN"                           then ["mute", $none,     ""]
       elif $n.reviewDecision == "APPROVED" and $ci == "SUCCESS" then ["ok",  $ready,    "ready to merge"]
       elif $ci == "SUCCESS"                                    then ["ok",   $green,    ""]
       else ["mute", $none, ""] end) as [$state, $glyph, $note]
    | "row\u001f" + $state
      + "\u001f" + (.repository.name + " #" + (.number|tostring) + "  " + .title
                     + (if $note == "" then "" else "  · " + $note end))
      + "\u001f" + .url
      + "\u001f" + $glyph')
  worst=$(rows_worst "$rows")
  {
    printf 'meta\037%s\037%s\037%s\037%s\n' \
      "${S_SEV[$i]}" "$count" "$(source_title "$i")" "$worst"
    [ -n "$rows" ] && printf '%s\n' "$rows"
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
  # Every row this source draws is therefore red by construction, which is why
  # it takes the glyph as a constant rather than deciding one per row.
  rows=$(printf '%s' "$json" | jq -r --arg failed "$G_FAILED" '
    .data.repositoryOwner.repositories.nodes[]?
    | select(.isArchived | not)
    | select(.defaultBranchRef != null)
    | { name: .name, url: .url, br: .defaultBranchRef.name,
        st: (.defaultBranchRef.target.statusCheckRollup.state // "NONE") }
    | select(.st == "FAILURE" or .st == "ERROR")
    | "row\u001fbad\u001f" + .name + "  " + .br + "\u001f" + .url
      + "\u001f" + $failed')
  count=$(printf '%s' "$rows" | grep -c '^row' 2>/dev/null || true)
  count=${count:-0}
  {
    # `worst` is whatever the rows are, not a constant `bad`: a green board
    # has no rows at all, and a source with nothing in it must not tint the
    # pill's logo red for the whole time nothing is wrong.
    printf 'meta\037bad\037%s\037%s\037%s\n' \
      "$count" "$(source_title "$i")" "$(rows_worst "$rows")"
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
  #
  # The glyph comes from the state the script printed, so a `command` source
  # gets the same marks a search row wears without having to know they exist —
  # its contract is still the two or three fields it always was. `busy` is the
  # newest of the four and the only one that is not just a colour: it is how a
  # command says "this is in flight", which is the state the ladder added so
  # that red could stop meaning it. A script that only ever printed the old
  # three keeps working unchanged.
  rows=$(printf '%s' "$rows" | awk -F'\t' -v US=$'\037' \
    -v GB="$G_FAILED" -v GW="$G_CHANGES" -v GR="$G_RUNNING" -v GO="$G_GREEN" \
    'NF>=2 && ($1=="ok"||$1=="busy"||$1=="warn"||$1=="bad"){
      glyph = ($1=="bad" ? GB : ($1=="warn" ? GW : ($1=="busy" ? GR : GO)))
      printf "row%s%s%s%s%s%s%s%s\n", US, $1, US, $2, US, (NF>=3 ? $3 : ""), US, glyph }')
  count=$(printf '%s' "$rows" | grep -c '^row' 2>/dev/null || true)
  count=${count:-0}
  {
    printf 'meta\037%s\037%s\037%s\037%s\n' \
      "${S_SEV[$i]}" "$count" "$(source_title "$i")" "$(rows_worst "$rows")"
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

  note_coverage
  date +%s > "$STAMP"
  rm -f "$FETCHING"
  rmdir "$LOCK" 2>/dev/null
  # Repaint whoever is drawing this pill. --trigger on the same instance the
  # caller belongs to, so a pill on the bottom bar isn't woken by an event sent
  # to the menu bar's mach service and nothing else.
  "$SB" --trigger github_update 2>/dev/null
}

# May this pill stretch its interval? Only if every configured source names a
# scope the bridge covers — and the sources are typed, so that is answerable
# rather than guessed:
#
#   ci        carries its owner explicitly.
#   search    is a GitHub search filter, so the scope is whatever `org:`,
#             `user:` and `repo:` qualifiers it names. A filter that names NONE
#             is unbounded by construction and can never be covered.
#   command   is arbitrary code whose subject nothing here can know. Never
#             covered, and that is the honest answer rather than a limitation.
#
# Written as a flag by the fetch path for the same reason every other consumer
# does it there: the tick reads a `stat`, not a parse.
note_coverage() {
  local i tok found scopes=()
  for ((i = 0; i < n_sources; i++)); do
    case "${S_KIND[$i]}" in
      ci)
        [ -n "${S_ORG[$i]}" ] || { rm -f "$COVERED"; return; }
        scopes+=("${S_ORG[$i]}")
        ;;
      search)
        found=0
        for tok in ${S_PAYLOAD[$i]}; do
          case "$tok" in
            org:?* | user:?*) scopes+=("${tok#*:}"); found=1 ;;
            repo:?*) scopes+=("${tok#repo:}"); found=1 ;;
          esac
        done
        [ "$found" = 1 ] || { rm -f "$COVERED"; return; }
        ;;
      *) rm -f "$COVERED"; return ;;
    esac
  done
  if [ "${#scopes[@]}" -gt 0 ] && haus_gh_covers "${scopes[@]}"; then
    : >"$COVERED"
  else
    rm -f "$COVERED"
  fi
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
#
# LEAD_WORST is the other half of the two-tone pill (see the header): the worst
# ROW state anywhere, across every source rather than only the leading one. It
# is deliberately not tied to which source leads — a conflict in the open-PR
# list is worth the same peach whether or not that list happens to be the
# source the number came from.
LEAD_STATE=ok
LEAD_COUNT=0
LEAD_SEV=info
LEAD_WORST=none
read_cache() {
  local i rank best=0 wrank wbest=0 kind sev count title worst saw_error=0
  LEAD_STATE=ok; LEAD_COUNT=0; LEAD_SEV=info; LEAD_WORST=none
  for ((i = 0; i < n_sources; i++)); do
    [ -f "$STATE/src-$i.tsv" ] || continue
    # `worst` named rather than swallowed by a trailing `_`: with five fields
    # and four variables, `read` folds the last two together and the title
    # arrives with the verdict stuck to it.
    IFS=$'\037' read -r kind sev count title worst < "$STATE/src-$i.tsv"
    [ "$kind" = meta ] || continue
    case "$sev" in
      auth)
        # LEAD_WORST too, not just the count. Nothing is answering, so an
        # earlier source's rows are not evidence about anything — and since the
        # logo now paints on `ok`, leaving it behind would draw a green octocat
        # beside the word `auth`.
        LEAD_STATE=auth; LEAD_COUNT=0; LEAD_WORST=none
        return ;;
      error)
        saw_error=1
        continue ;;
    esac
    wrank=$(sev_rank "${worst:-none}")
    if [ "$wrank" -gt "$wbest" ]; then
      wbest="$wrank"; LEAD_WORST="${worst:-none}"
    fi
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
  local icon="${BAR_GITHUB_ICON:-}" color label ldraw=on icolor
  if [ -f "$FETCHING" ] && [ "$(stamp_epoch)" -eq 0 ]; then
    # Only on the very first fetch, when there is genuinely nothing to show. A
    # refresh over a populated cache keeps drawing the old number instead of
    # blanking a pill you were reading.
    color="$OVERLAY0"; label="…"; LEAD_WORST=none
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

  # The logo's own tone: the worst row anywhere, on the ladder in the header.
  # Every rung paints it except `mute`, which is the one that means "nothing has
  # a verdict" and so has no tone to lend.
  #
  # That includes `ok`, which it used to withhold on the grounds that an
  # all-clear true almost all the time is a colour you stop reading. It isn't
  # true almost all the time — a source with nothing in it contributes no rows
  # at all, so an empty queue leaves the logo the number's own grey. Green here
  # means "there IS a queue and every row in it is fine", which is a different
  # sentence from silence and worth a colour; and now that the ladder reserves
  # red, the octocat reads as a four-step gauge rather than an alarm that is
  # either on or off.
  icolor="$color"
  case "$LEAD_WORST" in
    bad | warn | busy | ok) icolor="$(sev_color "$LEAD_WORST")" ;;
  esac

  # An icon-only pill has to be padded symmetrically. The bar's defaults are
  # 8 left / 4 right on the icon and 4 / 8 on the label, which reads centred
  # while both are drawn and visibly left-heavy the moment the label goes away
  # — which for this pill is its RESTING state, i.e. most of the time. Set with
  # every paint rather than once at --add, because the label appears and
  # disappears with the count.
  local ipl=8 ipr=4
  [ "$ldraw" = off ] && { ipl=10; ipr=10; }

  "$SB" --set "$ITEM" drawing="$(tour_drawing)" \
    icon="$icon" icon.color="$icolor" \
    icon.padding_left="$ipl" icon.padding_right="$ipr" \
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
  local ARGS=() i=0 s line kind sev count title worst glyph rows_drawn
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
      IFS=$'\037' read -r kind sev count title worst < "$STATE/src-$s.tsv"
      [ "$kind" = meta ] || continue
      # Kept aside because the row loop below reuses `sev` and `glyph` for each
      # row's own state — the section's verdict has to survive that.
      local msev="$sev" mworst="${worst:-none}"
      # The heading takes the WORSE of what the source is worth and what its
      # rows actually found, so an `info` queue holding one conflict reads peach
      # at the section level too rather than only on the one row.
      local hsev="$msev"
      [ "$(sev_rank "$mworst")" -gt "$(sev_rank "$msev")" ] && hsev="$mworst"
      local hcolor="$OVERLAY1"
      [ "${count:-0}" -gt 0 ] && hcolor="$(sev_color "$hsev")"
      # The count in the heading, not just on the pill. A section that says
      # "open PRs" over eight rows leaves you counting them to find out whether
      # eight is all of them; "open PRs · 12" answers it before the `+4 more`.
      local htitle="$title"
      [ "${count:-0}" -gt 0 ] && htitle="$title · $count"
      pop_add icon="${S_ICON[$s]}" icon.color="$hcolor" \
        label="$htitle" label.color="$TEXT" \
        label.font="${BAR_FONT}:Bold:${FS_LABEL}" background.height="$H_HEADER"

      rows_drawn=0
      while IFS=$'\037' read -r kind sev text url glyph; do
        [ "$kind" = row ] || continue
        rows_drawn=$((rows_drawn + 1))
        # A `mute` row — a draft, an issue, a verdict GitHub hasn't computed —
        # loses its text a shade too, not just its glyph colour. Otherwise a
        # list of eight reads as eight equal claims on you when two of them are
        # their author saying "not yet".
        local lcolor="$SUBTEXT0"
        [ "$sev" = mute ] && lcolor="$OVERLAY0"
        # A row with a URL opens it and closes the popup; one without just
        # closes, which is the pop_add default. The glyph is the merge verdict
        # (empty from a cache an older generation wrote, which draws as the
        # blank the rows used to have).
        if [ -n "$url" ]; then
          pop_add icon="$glyph" icon.color="$(sev_color "$sev")" \
            label="$text" label.color="$lcolor" \
            label.font="${BAR_FONT}:Regular:${FS_SMALL}" \
            click_script="/usr/bin/open '$url'; $SB --set ${ITEM} popup.drawing=off"
        else
          pop_add icon="$glyph" icon.color="$(sev_color "$sev")" \
            label="$text" label.color="$lcolor" \
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
  pop_add icon="" icon.color="$SAPPHIRE" \
    label="Refresh · $age" label.color="$SUBTEXT0" \
    label.font="${BAR_FONT}:Bold:${FS_SMALL}" \
    click_script="$HOME/.config/sketchybar/plugins/github.sh refresh"

  [ ${#ARGS[@]} -gt 0 ] && "$SB" "${ARGS[@]}" 2>/dev/null
  "$SB" --set "$ITEM" popup.drawing=on
  # Hand it to barpop so it also closes on the first click anywhere else — the
  # dismissal SketchyBar can't do, since it only hears clicks on its own items.
  # SKETCHYBAR_BIN is how barpop is told which bar's popup it is guarding.
  SKETCHYBAR_BIN="$SB" /run/current-system/sw/bin/barpop arm "$ITEM" 2>/dev/null &
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
# Push shortens a poll, it never removes one: `haus_gh_fresh_since` is the
# "something actually happened" door, the interval underneath it is the
# backstop, and with no bridge both fall back to what they always were.
#
# PUSH_FLOOR is why the door has a sill. This pill's option carries a 60s floor
# enforced by its very type, because a fetch is a full `gh` pass over every
# configured source and GitHub's authed budget is shared with every other `gh`
# on the machine. A bare `|| haus_gh_fresh_since` hands that floor to whoever is
# pushing: an org hook subscribed to `workflow_run` turns one push into roughly
# two deliveries per workflow, each waking this pill, and the only remaining
# bound would be how long a fetch takes. So the delivery cancels the WAIT, not
# the floor — worst case one fetch a minute, which is what the option promised.
PUSH_FLOOR=60
refresh="${BAR_GITHUB_REFRESH:-300}"
[ -f "$COVERED" ] && [ "$HAUS_GH_BACKSTOP" -gt "$refresh" ] && refresh="$HAUS_GH_BACKSTOP"
if [ "$last" -eq 0 ] || [ $((now - last)) -ge "$refresh" ] ||
  { [ $((now - last)) -ge "$PUSH_FLOOR" ] && haus_gh_fresh_since "$STAMP"; }; then
  spawn_fetch
fi
exit 0

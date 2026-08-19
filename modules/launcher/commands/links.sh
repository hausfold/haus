#!/bin/bash
# pounce: name = Links
# pounce: description = Open a URL from the focused window's Claude transcript
# pounce: icon = link
# pounce: submenu = true

# Links: every URL the focused window has ever seen, newest first, in a pounce
# picker — ⏎ opens the pick in the browser.
#
# Where the URLs come from, in preference order:
#   1. The window's Claude Code session TRANSCRIPT (the whole session, including
#      URLs inside collapsed tool outputs and things that scrolled away hours
#      ago). The session → transcript join is maintained by the statusline
#      (modules/core/statusline.sh writes pane-transcripts.tsv on every render —
#      it's the one process that knows both $ZMX_SESSION and the transcript
#      path), so this map only exists for windows running Claude Code.
#   2. Fallback for any other window: `zmx history` — its whole scrollback.
#
# GitHub PR/issue links get real details (title, open/closed/merged) via
# `gh api` — fetched in parallel, capped at ~2s total and cached by gh for an
# hour, so a slow network degrades to plain links instead of a hung palette.
#
# Gotchas encoded here:
#   - The pounce daemon spawns commands on launchd's bare PATH → resolve
#     zmx/gh/jq explicitly (same prelude as reload-bar.sh).
#   - WHICH window did the user mean? The palette is an NSPanel, so it never
#     takes focus away from the terminal — the focused window at this instant is
#     the one the chord was pressed in. scripts/focused-session.sh turns that
#     into a session name; see its header for the two joins.
#   - A window with no session (a browser was frontmost, or zmx isn't running)
#     is a real case, not an error state: say so in the picker rather than
#     showing an empty list, which reads as "this file has no links".

export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

CACHE_DIR="${CLAUDE_STATUSLINE_CACHE:-$HOME/.cache/claude-statusline}"
MAP="$CACHE_DIR/pane-transcripts.tsv"
MAX_LINKS=40
GH_WAIT_TICKS=20 # ×0.1s — cap on the parallel GitHub detail fetches

# Noise nobody ever wants to open: endpoints Claude Code itself talks to, and
# the per-session Co-Authored-By link stamped into every commit message.
DENY='^https?://(api\.anthropic\.com|statsig\.anthropic\.com|[^/]*sentry\.io)|^https://claude\.ai/code/session_'

# NB: the `]` is FIRST in the negated class on purpose — BSD grep (which this
# PATH resolves) is POSIX-strict: a `\]` later in the class would end the class
# at the backslash and silently match nothing. GNU grep forgives it; don't let
# a GNU-tested pattern regress this.
extract_urls() {
  grep -oE 'https?://[^][:space:]<>"'\''`)]+' | sed -E 's/[.,;:!?]+$//'
}

sess=$("$HOME/.config/haus/term/focused-session.sh" 2>/dev/null)
if [ -z "$sess" ]; then
  printf 'No terminal window focused\t(nothing to scan)\txmark.circle\n' | pounce
  exit 0
fi

transcript=""
[ -f "$MAP" ] && transcript=$(awk -F'\t' -v id="$sess" '$1==id{t=$2} END{print t}' "$MAP")

urls=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  # Transcript JSONL → every string in user/assistant records (covers message
  # text AND tool_result content nested inside user records). fromjson? keeps a
  # torn mid-write last line from aborting the whole stream.
  urls=$(jq -Rr 'fromjson? | select(.type=="user" or .type=="assistant") | .message.content | .. | strings' \
    "$transcript" 2>/dev/null | extract_urls)
fi

# Scrollback fallback: no map entry (not a Claude window), a stale entry
# pointing at a transcript that's since been removed, or a transcript that
# simply has no URLs in it. Cheaper to just try than to prove which case we're
# in. `zmx history` is the whole scrollback, not one screenful — which is more
# than `dump-screen --full` ever gave, and free.
if [ -z "$urls" ]; then
  urls=$(zmx history "$sess" 2>/dev/null | extract_urls)
fi

# Newest first, dedupe on first (= most recent) occurrence, drop noise, cap.
urls=$(tail -r <<<"$urls" | awk '!seen[$0]++' | grep -vE "$DENY" | head -"$MAX_LINKS")

if [ -z "$urls" ]; then
  printf 'No links found\t(transcript and scrollback are URL-free)\txmark.circle\n' | pounce
  exit 0
fi

# Kick off GitHub PR/issue detail fetches in parallel, one tmp file per index.
# The issues endpoint serves both kinds: .pull_request.merged_at distinguishes
# a merged PR from a merely-closed one.
tmp=$(mktemp -d -t pounce-links)
trap 'rm -rf "$tmp"' EXIT
i=0
while IFS= read -r u; do
  if [[ "$u" =~ ^https://github\.com/([^/]+)/([^/]+)/(pull|issues)/([0-9]+) ]]; then
    # Success-only write: on a 404 (dead or example link) gh emits the error
    # body on stdout, which must never end up as a row title.
    (
      out=$(gh api "repos/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}/issues/${BASH_REMATCH[4]}" \
        --cache 1h -q '[.title, .state, (.pull_request.merged_at // "")] | @tsv' 2>/dev/null) &&
        [ -n "$out" ] && printf '%s\n' "$out" >"$tmp/$i"
    ) &
  fi
  i=$((i + 1))
done <<<"$urls"
for _ in $(seq "$GH_WAIT_TICKS"); do
  [ -z "$(jobs -pr)" ] && break
  sleep 0.1
done
kill $(jobs -pr) 2>/dev/null

# Build picker rows: title = the most human thing we know, subtitle = context
# + the URL itself (the URL doubles as the selection payload — see below).
items=""
i=0
while IFS= read -r u; do
  title="" sub="" icon="link"
  if [[ "$u" =~ ^https://github\.com/([^/]+)/([^/]+)/(pull|issues)/([0-9]+) ]]; then
    ref="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}#${BASH_REMATCH[4]}"
    kind="issue" icon="dot.circle"
    [ "${BASH_REMATCH[3]}" = "pull" ] && kind="PR" icon="arrow.triangle.pull"
    state=""
    if [ -s "$tmp/$i" ]; then
      title=$(cut -f1 "$tmp/$i" | tr '\t' ' ')
      state=$(cut -f2 "$tmp/$i")
      [ -n "$(cut -f3 "$tmp/$i")" ] && state="merged"
    fi
    [ -z "$title" ] && title="$ref"
    sub="$ref · $kind${state:+ · $state} — $u"
  elif [[ "$u" =~ ^https://github\.com/([^/]+)/([^/]+)/commit/([0-9a-f]{7,40}) ]]; then
    title="${BASH_REMATCH[1]}/${BASH_REMATCH[2]} @ ${BASH_REMATCH[3]:0:7}"
    icon="number" sub="commit — $u"
  elif [[ "$u" =~ ^https://github\.com/([^/]+)/([^/]+)/?([?#]|$) ]]; then
    title="${BASH_REMATCH[1]}/${BASH_REMATCH[2]%.git}"
    icon="shippingbox" sub="repo — $u"
  elif [[ "$u" == https://github.com/* ]]; then
    # Deeper paths (tree/blob/pull/new/releases/…): the path IS the description.
    title="${u#https://github.com/}" icon="shippingbox" sub="$u"
  else
    title="${u#http://}" title="${title#https://}" title="${title#www.}"
    sub="$u"
  fi
  items="$items$title	$sub	$icon"$'\n'
  i=$((i + 1))
done <<<"$urls"

# ⏎ opens the pick. pounce echoes the whole selected row; the subtitle always
# carries the full URL, so grep it back out rather than trusting field order.
selected=$(printf '%s' "$items" | pounce -p "Links" -i "link")
[ -z "$selected" ] && exit 0
url=$(grep -oE 'https?://[^[:space:]]+' <<<"$selected" | tail -1)
[ -n "$url" ] && open "$url"

#!/bin/bash
# pounce: name = Links
# pounce: description = Open a URL from the focused pane's Claude transcript
# pounce: icon = link
# pounce: submenu = true

# Links: every URL the focused zellij pane has ever seen, newest first, in a
# pounce picker — ⏎ opens the pick in the browser.
#
# Where the URLs come from, in preference order:
#   1. The pane's Claude Code session TRANSCRIPT (the whole session, including
#      URLs inside collapsed tool outputs and things that scrolled away hours
#      ago). The pane → transcript join is maintained by the statusline
#      (modules/den/statusline.sh writes pane-transcripts.tsv on every render —
#      it's the one process that knows both $ZELLIJ_PANE_ID and the transcript
#      path), so this map only exists for panes running Claude Code.
#   2. Fallback for any other pane: `zellij action dump-screen --full` — the
#      pane's full scrollback.
#
# GitHub PR/issue links get real details (title, open/closed/merged) via
# `gh api` — fetched in parallel, capped at ~2s total and cached by gh for an
# hour, so a slow network degrades to plain links instead of a hung palette.
#
# Gotchas encoded here:
#   - The pounce daemon spawns commands on launchd's bare PATH → resolve
#     zellij/gh/jq explicitly (same prelude as reload-bar.sh).
#   - `zellij action` from outside a session needs -s and must NOT see a
#     $ZELLIJ from a testing shell, hence `env -u ZELLIJ`.
#   - list-clients prints pane ids as "terminal_88"; $ZELLIJ_PANE_ID inside the
#     pane is bare "88" — strip the prefix to join against the map.
#   - list-clients' RUNNING_COMMAND is the pane's *deepest foreground* process,
#     NOT what you launched: a Claude Code pane routinely reports sourcekit-lsp,
#     node, bash or rg. Never gate the transcript lookup on it matching
#     "claude" — presence in the map is the only reliable "this is a Claude
#     pane" signal, and a stale entry is covered by the fallback below.
#   - dump-screen dumps the FOCUSED pane, which is exactly the one we want:
#     the palette is an NSPanel, it never steals zellij focus. Pass -p anyway so
#     the dump can't drift to another pane between the two zellij calls.
#   - dump-screen takes `--path FILE` (or prints to STDOUT); it has NO positional
#     file argument — passing one makes zellij 0.44 exit with a usage error and
#     leaves an empty dump, i.e. a silent "No links found".

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

sess=$(env -u ZELLIJ zellij list-sessions -n 2>/dev/null | grep -v EXITED | head -1 | awk '{print $1}')
if [ -z "$sess" ]; then
  printf 'No zellij session\t(nothing to scan)\txmark.circle\n' | pounce
  exit 0
fi

# Focused pane: one attached client → one data row. $2 is the pane id.
pane=$(env -u ZELLIJ zellij -s "$sess" action list-clients 2>/dev/null | awk 'NR==2{print $2}')
pane=${pane#terminal_}

transcript=""
[ -f "$MAP" ] && transcript=$(awk -F'\t' -v id="$pane" '$1==id{t=$2} END{print t}' "$MAP")

urls=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  # Transcript JSONL → every string in user/assistant records (covers message
  # text AND tool_result content nested inside user records). fromjson? keeps a
  # torn mid-write last line from aborting the whole stream.
  urls=$(jq -Rr 'fromjson? | select(.type=="user" or .type=="assistant") | .message.content | .. | strings' \
    "$transcript" 2>/dev/null | extract_urls)
fi

# Scrollback fallback: no map entry (not a Claude pane), a stale entry pointing
# at a transcript that's since been removed, or a transcript that simply has no
# URLs in it. Cheaper to just try than to prove which case we're in.
if [ -z "$urls" ]; then
  urls=$(env -u ZELLIJ zellij -s "$sess" action dump-screen --full ${pane:+-p "$pane"} 2>/dev/null | extract_urls)
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

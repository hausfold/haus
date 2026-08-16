#!/bin/bash
# pounce: name = Lanes
# pounce: description = Jump to an agent lane, or /search what they're saying
# pounce: icon = point.3.connected.trianglepath.dotted
# pounce: submenu = true

# The lane picker: every agent worktree holt knows about, fuzzy-filtered by
# pounce, Enter focuses the lane's window. Two sources joined by the session
# name (holt.<repo>.<lane>, the same join every zmx surface uses):
#
#   holt --json   the registry — repo, branch, live/parked, last commit
#   zmx ls        the live sessions — and the agent's own state (working /
#                 waiting / done), which agents-hook.sh keeps as labels
#
# A lane with a window is focused via `aerospace focus --window-id` (found by
# its title). A parked lane — no session, no window — is reopened with
# `holt <repo>/<name>`, which spawns the window through the open seam.
#
# Type `/` + a term + Enter to switch to CONTENT search instead: the term is
# grepped across every live session's `zmx history` — what the agents are
# actually saying — and the matches come back as rows, one per lane, Enter
# focusing the lane it came from. One `zmx history` subprocess per lane, which
# is fine at the ~10 lanes this machine actually runs; cap it at 20 so a
# pathological registry degrades to "the 20 most recent" instead of a hang.
set -u

export PATH="/etc/profiles/per-user/${USER:-$(id -un)}/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

command -v holt >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

# ── zmx: session name → "state<TAB>client", the labels agents-hook.sh keeps ──
zmx_states() {
  command -v zmx >/dev/null 2>&1 || return 0
  zmx ls 2>/dev/null | awk -F'\t' '
    {
      name = ""; state = ""; client = ""
      for (i = 1; i <= NF; i++) {
        p = index($i, "=")
        if (p == 0) { gsub(/^[ \t]+|[ \t]+$/, "", $i); if (name == "") name = $i; continue }
        k = substr($i, 1, p - 1); gsub(/^[ \t]+|[ \t]+$/, "", k)
        if (k == "name")   name   = substr($i, p + 1)
        if (k == "state")  state  = substr($i, p + 1)
        if (k == "client") client = substr($i, p + 1)
      }
      if (name != "") printf "%s\t%s\t%s\n", name, state, client
    }'
}

focus_session() {
  # The window is found by its forced title; a dead lane has no window and
  # falls through to a holt reopen by the caller.
  local sess="$1" wid
  wid="$(aerospace list-windows --all --format '%{window-id}|%{window-title}' 2>/dev/null |
    awk -F'|' -v want="$sess" '$2 == want { print $1; exit }')"
  [ -n "$wid" ] || return 1
  aerospace focus --window-id "$wid" >/dev/null 2>&1
}

# ── step 1: the lane rows ────────────────────────────────────────────────────
# TSV per pounce's row protocol: title, subtitle, icon, actions, group. The
# title is exactly "repo · lane", so the session name needs no hidden field —
# it is reconstructed from the pick.
states="$(zmx_states)"

# Bounded, never bare: agents.sh warns in as many words that `holt --json`'s
# landed-verdict checks can block on the network for seconds, and this runs on
# the palette's interactive path. Ten seconds is generous next to the bar's 60
# because a human is waiting; past it the picker simply comes up empty.
rows="$(
  /usr/bin/perl -e 'alarm shift; exec @ARGV' 10 holt --json 2>/dev/null |
    jq -r --arg states "$states" '
    # state precedence: the agent'\''s own label (working/waiting/done) beats
    # holt'\''s registry state (live/parked) — the label is what the paw pill
    # shows, and the picker should agree with the bar.
    (
      $states | split("\n") | map(select(length > 0) | split("\t"))
      | map({ (.[0]): { state: (.[1] // ""), client: (.[2] // "") } })
      | add // {}
    ) as $live
    | .lanes[]?
    | (.main | split("/") | last) as $repo
    | "holt.\($repo).\(.name)" as $sess
    | ($live[$sess].state // "") as $lstate
    | (if $lstate != "" then $lstate else .state end) as $state
    | (
        { working: "play.circle.fill",
          waiting: "hourglass.circle.fill",
          done:    "checkmark.circle.fill",
          live:    "circle.dashed",
          parked:  "zzz" }[$state] // "circle.dashed"
      ) as $icon
    | [ "\($repo) · \(.name)",
        "\($state)  \(.branch)  —  \(.last_commit // "")",
        $icon,
        "Open",
        "Lanes" ]
    | @tsv
  '
)"

[ -n "$rows" ] || exit 0

# --chain enter: a commit here is never the end — either we focus a window (a
# fast next act) or the typed /term re-invokes the picker with content rows —
# so the window holds its skeleton instead of fading out and popping back.
selected="$(printf '%s\n' "$rows" | pounce -p "Lanes" -i "point.3.connected.trianglepath.dotted" --chain enter)" || exit 0
picked="$(printf '%s' "$selected" | cut -f2)"

# ── the / switch: content search across the lanes' transcripts ───────────────
case "$picked" in
  /*)
    term="${picked#/}"
    [ -n "$term" ] || exit 0
    matches=""
    n=0
    while IFS=$'\t' read -r sess _state _client; do
      [ -n "$sess" ] || continue
      n=$((n + 1)); [ "$n" -gt 20 ] && break
      hit="$(zmx history "$sess" 2>/dev/null | grep -iF -- "$term" | tail -1 |
        cut -c1-120 | tr '\t' ' ')"
      [ -n "$hit" ] || continue
      matches="$matches$sess"$'\t'"$hit"$'\t'"text.magnifyingglass"$'\t'"Open"$'\t'"Matches"$'\n'
    done <<EOF
$states
EOF
    [ -n "$matches" ] || exit 0
    selected="$(printf '%s' "$matches" | pounce -p "Lanes /$term" -i "text.magnifyingglass")" || exit 0
    # Reply is "<action>\t<raw row>", and the row's own first field is the
    # session name — so field 2 of the whole reply.
    sess="$(printf '%s' "$selected" | cut -f2)"
    [ -n "$sess" ] || exit 0
    focus_session "$sess" && exit 0
    # Session alive but its window ⌘W'd: same wake-up the lane rows get. The
    # session name is holt.<repo>.<lane> with a dot-free lane, so repo is
    # everything between the first and last dot.
    rest="${sess#holt.}"
    exec holt "${rest%.*}/${rest##*.}"
    ;;
esac

# ── a picked lane row: focus its window, or wake the parked lane ─────────────
title="$picked"
repo="${title%% · *}"
lane="${title##* · }"
[ -n "$repo" ] && [ -n "$lane" ] || exit 0
sess="holt.${repo}.${lane}"

focus_session "$sess" && exit 0
# No window: parked (or the window was ⌘W'd). holt's open seam spawns it back.
exec holt "${repo}/${lane}"

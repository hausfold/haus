#!/bin/bash
# holt-cache — one warm copy of `holt --json`, shared by everything that reads it.
#
# WHY THIS EXISTS
#
# `holt --json` is not a listing, it is an INVESTIGATION. `holt list` self-heals
# on the way in (a parked reap sweep), and both that sweep and the JSON encoder
# ask `occupancy.Collect(LSOF(), …)` — a machine-wide `lsof -d cwd`, twice per
# run — before the per-lane landed/PR verdicts spend their own time in git and
# `gh`. On this machine that is seconds, floor, with ZERO lanes registered:
# the constant cost is the two lsof dumps, not the lane count.
#
# Nothing that reads it can afford that inline:
#
#   the bar's agents popup   redraws on a 10s tick and on every hook event
#   the Lanes palette        opens under pounce's loading skeleton, which
#                            fades the window out after 8 SECONDS (pounce's
#                            Window.startLoading) — a picker that takes longer
#                            than that doesn't just feel slow, it vanishes
#
# So both read this cache and neither runs holt on its own hot path. It was
# agents.sh's private block until the palette needed the same thing; the lock
# protocol below is subtle enough that a second copy of it was the wrong answer.
#
# THE CACHE IS REPLACED ONLY BY A COMPLETE, PARSEABLE RESULT (jq has to accept
# `.lanes` as an array), so a failed or half-written refresh leaves the previous
# answer intact rather than blanking every consumer at once. Readers pass their
# own max age and decide what a miss means.
#
# usage:
#   holt-cache path             the cache file's path
#   holt-cache age              seconds since it was last written (huge if none)
#   holt-cache read [max-age]   print it if younger than max-age (default 900),
#                               else exit 1
#   holt-cache kick [ttl] [timeout]
#                               refresh in the BACKGROUND if the last kick is
#                               older than ttl (default 20s). One winner among
#                               concurrent callers; returns immediately
#   holt-cache sync [timeout]   refresh in the FOREGROUND, bounded by timeout
#                               (default 6s — deliberately UNDER the 8s the
#                               skeleton fades at, since a default equal to the
#                               deadline is a default that always misses it),
#                               and print the result. Exit 1 if
#                               holt was too slow or answered with nonsense —
#                               the caller then decides between a stale read
#                               and saying so out loud
set -u

export USER="${USER:-$(id -un)}"
export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin${PATH:+:$PATH}"

DIR="${CLAUDE_STATUSLINE_CACHE:-$HOME/.cache/claude-statusline}"
CACHE="$DIR/holt.json"
KICK="$DIR/.holt-kick"
LOCK="$DIR/.holt-refresh.lock"
LOCK_STALE=90                   # recover a refresher killed before it released
COVERED="$DIR/.holt-covered"    # every lane's repo is behind the GitHub bridge

# ---- the GitHub bridge, where there is one ----------------------------------
# `holt --json` asks GitHub about every lane's pull request, which is most of
# what makes it expensive. With a webhook bridge on this machine (haus.github)
# that question has a push answer, so the kick throttle stretches from seconds
# to `HAUS_GH_BACKSTOP` and collapses to zero the moment a delivery lands.
#
# Absent, every function below is defined to say "no" and the throttle is
# exactly what it always was. That is the only acceptable failure direction
# here: a bridge that cannot be confirmed must never be assumed.
if [ -r "$HOME/.config/haus/github/signal.sh" ]; then
  # shellcheck source=/dev/null
  . "$HOME/.config/haus/github/signal.sh"
else
  haus_gh_covers() { return 1; }
  haus_gh_fresh_since() { return 1; }
fi
HAUS_GH_BACKSTOP="${HAUS_GH_BACKSTOP:-0}"

now() { date +%s; }

# mtime, or 0 for anything we can't read a number out of.
mtime() {
  local m
  m=$(stat -f %m "$1" 2>/dev/null || echo 0)
  case "$m" in '' | *[!0-9]*) m=0 ;; esac
  printf '%s\n' "$m"
}

release_lock() {
  # A stale owner may have been replaced while this slow process was alive.
  # Only the process that still owns the lock may remove it.
  if [ "$(cat "$LOCK/owner" 2>/dev/null)" = "$1" ]; then
    rm -f "$LOCK/owner"
    rmdir "$LOCK" 2>/dev/null || true
  fi
}

# Does the bridge cover EVERY lane's repo? Answered here, in the fetch path,
# because this is the one place that knows which repositories the answer is
# about — and answered as a flag file so the callers, which run on a 10s bar
# tick and inside pounce's loading skeleton, spend a `stat` rather than a `jq`.
#
# All of them, not any: one lane in a repo GitHub will never tell us about is
# enough to make a stretched interval a lie about that lane's PR.
note_coverage() {
  local slugs
  # shellcheck disable=SC2207
  slugs=($(jq -r '(.lanes // [])[] | .repo // empty' "$CACHE" 2>/dev/null | sort -u))
  if [ "${#slugs[@]}" -gt 0 ] && haus_gh_covers "${slugs[@]}"; then
    : >"$COVERED"
  else
    rm -f "$COVERED"
  fi
}

# Run holt, bounded, and install the result only if it parses. Prints nothing.
refresh() {
  local token="$1" timeout="$2" tmp
  mkdir -p "$DIR"
  tmp=$(mktemp "$DIR/.holt-json.XXXXXX") || { release_lock "$token"; return 1; }
  # The braces + redirect are not decoration: when the alarm fires, bash itself
  # reports the signal ("Alarm clock: 14") on ITS stderr, not the command's, so
  # a `2>/dev/null` on the perl call alone leaves a timeout printing noise into
  # whatever ran this.
  if { /usr/bin/perl -e 'alarm shift; exec @ARGV' "$timeout" holt --json >"$tmp"; } 2>/dev/null &&
    jq -e '(.lanes // []) | type == "array"' "$tmp" >/dev/null 2>&1; then
    mv -f "$tmp" "$CACHE"
    note_coverage
    release_lock "$token"
    return 0
  fi
  rm -f "$tmp"
  release_lock "$token"
  return 1
}

# Elect one refresher. Prints the winning token, or nothing when somebody else
# already holds the lock.
claim() {
  local n="$1" lock_at stale
  mkdir -p "$DIR"
  if [ -d "$LOCK" ]; then
    lock_at=$(mtime "$LOCK")
    if [ $((n - lock_at)) -ge "$LOCK_STALE" ]; then
      # Rename the stale lock out of the election atomically. Two reclaimers may
      # race here, but only one can move this exact directory; neither can
      # delete the fresh lock the winner (or another caller) creates afterward.
      stale="$LOCK.stale.$$.$RANDOM"
      if mv "$LOCK" "$stale" 2>/dev/null; then
        rm -f "$stale/owner"
        rmdir "$stale" 2>/dev/null || true
      fi
    fi
  fi
  mkdir "$LOCK" 2>/dev/null || return 1
  local token="$n.$$.$RANDOM"
  printf '%s\n' "$token" >"$LOCK/owner"
  printf '%s\n' "$token"
}

case "${1:-read}" in
  path) printf '%s\n' "$CACHE" ;;

  age)
    at=$(mtime "$CACHE")
    if [ "$at" -eq 0 ] || [ ! -s "$CACHE" ]; then printf '%s\n' 999999
    else printf '%s\n' $(( $(now) - at )); fi
    ;;

  read)
    max="${2:-900}"
    at=$(mtime "$CACHE")
    [ -s "$CACHE" ] && [ "$at" -gt 0 ] && [ $(( $(now) - at )) -lt "$max" ] || exit 1
    cat "$CACHE"
    ;;

  kick)
    ttl="${2:-20}"
    timeout="${3:-60}"
    command -v holt >/dev/null 2>&1 || exit 0
    # Push shortens a poll, it never removes one: covered, the throttle becomes
    # the bridge's backstop rather than the caller's seconds, and a delivery
    # that landed after the cache was written puts it back to the caller's —
    # never below it. `holt --json` dumps `lsof -d cwd` machine-wide twice per
    # run, so a delivery must cancel the stretch rather than buy a faster
    # refresh than an un-bridged machine gets.
    if [ -f "$COVERED" ] && [ "$HAUS_GH_BACKSTOP" -gt "$ttl" ]; then
      haus_gh_fresh_since "$CACHE" || ttl="$HAUS_GH_BACKSTOP"
    fi
    n=$(now)
    [ $((n - $(mtime "$KICK"))) -ge "$ttl" ] || exit 0
    token=$(claim "$n") || exit 0
    mkdir -p "$DIR"
    touch "$KICK"
    # The inner `&` belongs inside a short-lived subshell: the refresher is
    # reparented before this process exits, so a caller that reaps its children
    # (SketchyBar does, with its script process) cannot take the slow work with
    # it.
    ( refresh "$token" "$timeout" >/dev/null 2>&1 & )
    exit 0
    ;;

  sync)
    timeout="${2:-6}"
    command -v holt >/dev/null 2>&1 || exit 1
    n=$(now)
    # No lock, no refresh — somebody else is already paying this cost, and
    # `holt --json` is not a cheap thing to run twice at once. The caller falls
    # back to a stale read, which is what the other run is about to replace.
    token=$(claim "$n") || exit 1
    touch "$KICK"
    refresh "$token" "$timeout" || exit 1
    cat "$CACHE"
    ;;

  *) exit 2 ;;
esac

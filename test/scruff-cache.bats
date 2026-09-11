#!/usr/bin/env bats
# Hermetic tests for modules/ai/scruff-cache.sh — the one warm copy of
# `scruff --json` that the agents pill and the Lanes palette both read.
#
# Why a suite. Everything in that script is an age: `read` serves the cache only
# if it is younger than the caller's max, `kick` refreshes only if the last one
# is older than a throttle, and `claim` reclaims the refresher's lock only once
# it is older than LOCK_STALE. All three are `now - mtime`, so a file stamped
# AHEAD of now — a clock stepped backward by NTP, a VM resumed from a snapshot,
# a cache restored from another machine — makes the subtraction NEGATIVE, and a
# negative age is below every threshold at once. Nothing errors. The cache reads
# fresh forever, the throttle never expires, the lock never goes stale, and both
# consumers go on serving lane rows nothing is refreshing. Observed on
# 2026-09-11: two markers in ~/.cache/claude-statusline stamped 3h40m ahead of
# `date +%s` on a machine whose clock matched network time.
#
# What is NOT here, and why. `kick` and `claim` are deliberately untested. The
# script PREPENDS the system bin directories to $PATH before it looks for
# `scruff`, so a shim cannot win that race on a real machine — the suite would
# spawn the actual `scruff --json`, which is two machine-wide `lsof -d cwd`
# dumps — while on the Linux runner there is no `scruff` at all and `kick`
# returns at its first guard. Neither half can be asserted on. Both verbs read
# their stamps through the same `mtime` every case below drives, and
# test/statusline-refresh.bats covers a future-stamped lock end to end on the
# refresher's identical breaker.
#
# `touch -t 209901010000` rather than `date -v+…`: -t's CCYYMMDDhhmm is the one
# spelling BSD and GNU touch agree on, and this suite runs on both.

bats_require_minimum_version 1.5.0

setup() {
  CACHE_SH="$BATS_TEST_DIRNAME/../modules/ai/scruff-cache.sh"
  TMP="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"

  export HOME="$TMP/home"
  export CLAUDE_STATUSLINE_CACHE="$TMP/cache"
  mkdir -p "$HOME" "$CLAUDE_STATUSLINE_CACHE"
  CACHE="$CLAUDE_STATUSLINE_CACHE/scruff.json"
}

run_cache() { run bash "$CACHE_SH" "$@"; }

future() { touch -t 209901010000 "$@"; }

fail() { printf '%s\n' "$*" >&2; return 1; }

# ---- path -------------------------------------------------------------------

@test "path answers where the cache lives, cache or no cache" {
  run_cache path
  [ "$output" = "$CACHE" ]
}

# ---- age --------------------------------------------------------------------

@test "no cache at all is the ancient sentinel, not a negative number" {
  run_cache age
  [ "$output" = 999999 ]
}

@test "a cache written just now is a small age" {
  printf '{"lanes":[]}' >"$CACHE"
  run_cache age
  [ "$output" -lt 5 ] || fail "a fresh cache read as $output seconds old"
}

@test "a cache stamped in the FUTURE is ancient, not fresh" {
  printf '{"lanes":[]}' >"$CACHE"
  future "$CACHE"
  run_cache age
  [ "$output" = 999999 ] || fail "a future stamp read as $output, not the sentinel"
}

@test "an EMPTY cache is ancient however new its stamp" {
  # A refresh killed between the create and the write. `age` is what the bar
  # prints beside the lane rows, and "0s" over nothing is the worst of both.
  : >"$CACHE"
  run_cache age
  [ "$output" = 999999 ]
}

# ---- read -------------------------------------------------------------------

@test "a cache inside the max age is served" {
  printf '{"lanes":[1]}' >"$CACHE"
  run_cache read 900
  [ "$status" -eq 0 ]
  [ "$output" = '{"lanes":[1]}' ]
}

@test "a cache older than the caller's max is refused" {
  printf '{"lanes":[1]}' >"$CACHE"
  touch -t 202001010000 "$CACHE"
  run_cache read 900
  [ "$status" -eq 1 ]
  [ -z "$output" ] || fail "refused and printed anyway: $output"
}

@test "a cache stamped in the FUTURE is refused, so the caller refetches" {
  # The freezing one. `read` is what the Lanes palette and the agents pill call,
  # and a yes here is a picker full of lanes nobody is checking any more —
  # confidently drawn, indefinitely, with nothing on the machine saying so.
  printf '{"lanes":[1]}' >"$CACHE"
  future "$CACHE"
  run_cache read 900
  [ "$status" -eq 1 ] || fail "served a cache from the future as if it were fresh"
  [ -z "$output" ] || fail "refused and printed anyway: $output"
}

@test "no cache at all is a refusal, not an empty success" {
  run_cache read 900
  [ "$status" -eq 1 ]
}

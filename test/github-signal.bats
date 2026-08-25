#!/usr/bin/env bats
# Hermetic tests for the GitHub bridge's consumer contract
# (modules/github/signal.sh, and the gate it feeds in modules/ai/statusline.sh).
#
# Why a suite. Everything in this seam fails SILENTLY and in the expensive
# direction: a `haus_gh_covers` that says yes when it shouldn't turns a 15-second
# readout into a 30-minute one, and nothing on screen says so — the pill just
# quietly starts lying about a merge that already happened. There is no error
# path to notice, so the only thing standing between "covered" and "wrong" is
# the exact set of cases below.
#
# The rule every one of them is checking: **coverage must fail closed.** No
# scopes file, an empty one, a stale one, one repo out of two, an unparsable
# mtime — every single one has to come back "not covered", because the fallback
# is the polling that already worked.
#
# Nothing here touches the network, a real hook, or the real state directory:
# HOME is substituted, and `scopes` is written by hand precisely because the
# thing under test is what the consumers do with it, not how it got there.

bats_require_minimum_version 1.5.0

setup() {
  SIGNAL="$BATS_TEST_DIRNAME/../modules/github/signal.sh"
  SL="$BATS_TEST_DIRNAME/../modules/ai/statusline.sh"
  TMP="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"

  export HOME="$TMP/home"
  export CLAUDE_STATUSLINE_CACHE="$TMP/cache"
  export STATE="$HOME/.local/state/haus/github"
  export CONFIG="$HOME/.config/haus/github"
  mkdir -p "$STATE" "$CONFIG" "$CLAUDE_STATUSLINE_CACHE"

  # What the room generates. Written here rather than imported so the suite
  # states the contract it depends on instead of inheriting it.
  cat >"$CONFIG/config.sh" <<EOF
HAUS_GH_STATE="$STATE"
HAUS_GH_CONFIG="$CONFIG"
HAUS_GH_BACKSTOP="1800"
HAUS_GH_COVERAGE_REFRESH="3600"
HAUS_GH_HOSTNAME="hooks.example.com"
HAUS_GH_PORT="42786"
EOF
  cp "$SIGNAL" "$CONFIG/signal.sh"
}

# covers <slug>... — the sourced contract, in a subshell so each case is clean.
covers() {
  bash -c '. "$1"; shift; haus_gh_covers "$@"' _ "$CONFIG/signal.sh" "$@"
}

fresh_since() {
  bash -c '. "$1"; shift; haus_gh_fresh_since "$1"' _ "$CONFIG/signal.sh" "$@"
}

# ---- coverage ---------------------------------------------------------------

@test "an org hook covers a repository inside it" {
  printf 'hausfold\n' >"$STATE/scopes"
  covers hausfold/haus
}

@test "an org hook covers the org asked about by bare name" {
  printf 'hausfold\n' >"$STATE/scopes"
  covers hausfold
}

@test "a repo hook covers that repository and no other in the org" {
  printf 'hausfold/haus\n' >"$STATE/scopes"
  covers hausfold/haus
  ! covers hausfold/pounce
}

@test "every slug must be covered, not merely one of them" {
  printf 'hausfold\n' >"$STATE/scopes"
  ! covers hausfold/haus acme/widget
}

@test "asking about nothing is not coverage" {
  printf 'hausfold\n' >"$STATE/scopes"
  # The case that matters: a consumer whose repo list came back empty must not
  # read "no counter-examples" as "the bridge has this".
  ! covers
}

@test "an empty scopes file is not coverage" {
  : >"$STATE/scopes"
  ! covers hausfold/haus
}

@test "a missing scopes file is not coverage" {
  ! covers hausfold/haus
}

@test "coverage expires once it can no longer be confirmed" {
  printf 'hausfold\n' >"$STATE/scopes"
  covers hausfold/haus
  # Older than three refresh intervals: the machine has stopped being able to
  # ask GitHub, so it goes back to polling rather than trusting a stale yes.
  touch -t 202001010000 "$STATE/scopes"
  ! covers hausfold/haus
}

@test "a prefix of a covered owner is not a covered owner" {
  printf 'haus\n' >"$STATE/scopes"
  # `grep -qxF` and not `grep -qF`: `haus` must not match `hausfold/haus`.
  ! covers hausfold/haus
}

# ---- what sourcing must NOT do ----------------------------------------------

@test "sourcing does not change the caller's shell options" {
  # The bug this exists for: `set -u` at signal.sh's file scope applies to the
  # SOURCING script. statusline.sh deliberately runs without it — its render
  # path reads many optional JSON fields — so a leaked `-u` turns the first
  # absent field into a dead statusline on every prompt, from a file
  # statusline.sh never mentions.
  run bash -c 'set +u; . "$1"; case "$-" in *u*) echo leaked;; *) echo clean;; esac' _ "$CONFIG/signal.sh"
  [ "$output" = clean ]
}

@test "sourcing leaves an unset variable readable, not fatal" {
  run bash -c 'set +u; . "$1"; printf "[%s]" "${NOT_SET_ANYWHERE}"' _ "$CONFIG/signal.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "sourcing defines only the two contract functions and HAUS_GH_ names" {
  # A library sourced into hot paths must not shadow a caller's helper. Both
  # holt-cache.sh and statusline.sh already have their own `mtime`, which is
  # why this file's is `haus_gh_mtime`.
  run bash -c '
    before=$(declare -F | awk "{print \$3}" | sort)
    . "$1"
    after=$(declare -F | awk "{print \$3}" | sort)
    comm -13 <(printf "%s\n" "$before") <(printf "%s\n" "$after")
  ' _ "$CONFIG/signal.sh"
  [ "$output" = "haus_gh_covers
haus_gh_fresh_since
haus_gh_mtime" ]
}

# ---- the delivery signal ----------------------------------------------------

@test "a delivery after the cache was written is a reason to refetch" {
  : >"$STATE/cache"
  sleep 1
  : >"$STATE/last"
  fresh_since "$STATE/cache"
}

@test "a delivery older than the cache is not" {
  : >"$STATE/last"
  sleep 1
  : >"$STATE/cache"
  ! fresh_since "$STATE/cache"
}

@test "no delivery has ever arrived is not a reason to refetch" {
  : >"$STATE/cache"
  ! fresh_since "$STATE/cache"
}

@test "a missing cache is the caller's business, not this signal's" {
  : >"$STATE/last"
  ! fresh_since "$STATE/nonexistent"
}

# ---- `github-signal check`, which is what haus doctor asks -------------------
#
# The deck's rule is that a card never draws a tick nothing earned, and this is
# the whole of what earns it. Written by hand rather than by a refresh: the point
# is what the verdict column MEANS, not how it got there, and the check must
# never reach the network.

signal_check() {
  HAUS_GH_STATE="$STATE" HAUS_GH_CONFIG="$CONFIG" bash "$CONFIG/signal.sh" check
}

@test "check: every hook confirmed healthy is the only thing that passes" {
  printf 'org:hausfold\tok\t\n' >"$STATE/coverage.tsv"
  signal_check
}

@test "check: a scope GitHub could not be asked about does not pass" {
  # `unreadable` — gh logged out, offline, or rate-limited. It carries no fix
  # command, which is exactly why testing `drift`'s stdout used to tick green.
  printf 'org:hausfold\tunreadable\t\n' >"$STATE/coverage.tsv"
  ! signal_check
}

@test "check: a malformed scope does not pass" {
  printf 'hausfold\tbad-scope\t\n' >"$STATE/coverage.tsv"
  ! signal_check
}

@test "check: one bad hook among several does not pass" {
  printf 'org:hausfold\tok\t\nrepo:acme/widget\tabsent\tgh api …\n' >"$STATE/coverage.tsv"
  ! signal_check
}

@test "check: never confirmed is not the same as confirmed fine" {
  ! signal_check
}

@test "check: a report too old to trust does not pass" {
  printf 'org:hausfold\tok\t\n' >"$STATE/coverage.tsv"
  signal_check
  touch -t 202001010000 "$STATE/coverage.tsv"
  ! signal_check
}

@test "check: reads only — it must not call out or rewrite coverage" {
  printf 'org:hausfold\tok\t\n' >"$STATE/coverage.tsv"
  printf 'hausfold\n' >"$STATE/scopes"
  before=$(stat -f %m "$STATE/scopes")
  sleep 1
  # No `gh` on PATH at all: a check that reached the network would fail here.
  PATH=/usr/bin:/bin signal_check
  [ "$(stat -f %m "$STATE/scopes")" = "$before" ]
}

# ---- the statusline's gate --------------------------------------------------
#
# The render path's decision is "is the panel stale", and the bridge only ever
# moves it in two directions: later when covered, immediately on a delivery.
# Asserted by whether the DETACHED REFRESHER got spawned, because that is the
# thing the decision actually controls — a stub on PATH under the name the
# script resolves (`claude-statusline-refresh`) records the fact and returns.

# render — run the statusline over a panel of a given age and report whether it
# decided to refresh. `age` in seconds; the stub leaves a breadcrumb.
render_with_panel_age() {
  local age="$1"
  mkdir -p "$TMP/bin"
  cat >"$TMP/bin/claude-statusline-refresh" <<EOF
#!/bin/bash
: >"$TMP/refreshed"
EOF
  chmod +x "$TMP/bin/claude-statusline-refresh"
  rm -f "$TMP/refreshed"
  # Named explicitly rather than found on PATH: statusline.sh prepends the
  # system profile, where a REAL claude-statusline-refresh lives on any machine
  # running this rice, so a stub could never win the lookup.
  export CLAUDE_STATUSLINE_REFRESHER="$TMP/bin/claude-statusline-refresh"

  printf 'hausfold/haus\tx\t1\t0\t0\t0\t#1 open\t%s\n' "$TMP" \
    >"$CLAUDE_STATUSLINE_CACHE/panel.tsv"
  touch -t "$(date -v-"$age"S +%Y%m%d%H%M.%S)" "$CLAUDE_STATUSLINE_CACHE/panel.tsv"

  bash -c \
    'printf "{\"model\":{\"id\":\"claude-opus-5\"},\"workspace\":{\"current_dir\":\"$2\"}}" | bash "$1"' \
    _ "$SL" "$TMP" >/dev/null 2>&1
  # A short grace: the refresher is spawned with nohup and disowned.
  sleep 1
  [ -f "$TMP/refreshed" ]
}

@test "statusline: with no bridge at all a 20s panel is stale, exactly as before" {
  rm -f "$CONFIG/signal.sh"
  # The fallback definitions are also what keep an un-bridged machine from
  # crashing on an unbound variable in the render path.
  render_with_panel_age 20
}

@test "statusline: a bridge present but nothing covered leaves the TTL alone" {
  render_with_panel_age 20
}

@test "statusline: a covered panel rides the bridge's backstop instead" {
  printf 'hausfold\n' >"$STATE/scopes"
  : >"$CLAUDE_STATUSLINE_CACHE/.panel-covered"
  ! render_with_panel_age 20
}

@test "statusline: a delivery collapses the backstop to the un-bridged TTL" {
  printf 'hausfold\n' >"$STATE/scopes"
  : >"$CLAUDE_STATUSLINE_CACHE/.panel-covered"
  : >"$STATE/last"
  # `last` is newer than a panel written 20 seconds ago, which is the whole
  # point of the bridge: something happened, go and look now.
  render_with_panel_age 20
}

@test "statusline: a delivery does not buy a faster poll than no bridge at all" {
  printf 'hausfold\n' >"$STATE/scopes"
  : >"$CLAUDE_STATUSLINE_CACHE/.panel-covered"
  : >"$STATE/last"
  # Five seconds old is fresh under the un-bridged TTL of 15, and a delivery
  # must not change that — an org hook subscribed to workflow_run turns one CI
  # run into a burst of deliveries, and `gh pr list` per sister repo on every
  # prompt is the traffic this whole change exists to remove.
  ! render_with_panel_age 5
}

@test "statusline: a covered panel past the backstop is stale again" {
  printf 'hausfold\n' >"$STATE/scopes"
  : >"$CLAUDE_STATUSLINE_CACHE/.panel-covered"
  # Push shortens a poll, it never removes one.
  render_with_panel_age 2000
}

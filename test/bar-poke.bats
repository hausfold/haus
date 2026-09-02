#!/usr/bin/env bats
# Hermetic tests for modules/core/haus-bar-poke.sh — the both-bars trigger.
#
# Why a suite. "Anything that pokes a bar pokes both" (AGENTS.md) used to be a
# rule four producers each wrote out, and each of those copies was checked, if
# at all, by the producer's own suite. Now it is one binary, so the rule has one
# place to be tested — and the failure it guards is the quietest one this repo
# has: SketchyBar keys its lock file and its mach service on `basename(argv[0])`,
# so a `--trigger` reaches exactly ONE instance. Poking the top bar alone is
# valid syntax, exits 0, logs nothing, and leaves a pill that `haus.bar.bottom.
# items` moved downward frozen on stale data until its own tick comes round.
#
# The harness stands a recorder at each bar path and asserts on the TRAFFIC:
# which binaries were called, and exactly what rode each call.

bats_require_minimum_version 1.5.0

setup() {
  TMP="$BATS_TEST_TMPDIR"
  mkdir -p "$TMP/bin"
  export POKE_LOG="$TMP/poke.log"

  # Two recorders, distinguishable by name, standing where the two SketchyBar
  # instances would be. `$0`'s basename is what the real bar keys itself on, so
  # it is what a line of this log is named after too.
  for bar in sketchybar bar-bottom; do
    cat >"$TMP/bin/$bar" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$POKE_LOG"
EOF
    chmod +x "$TMP/bin/$bar"
  done

  # The derivation's one build-time step, by hand: modules/core/default.nix
  # substitutes `@sketchybar@` with haus.roster.sketchybar.binPath. Doing it
  # here means the suite runs what nix installs rather than a shape only bats
  # has seen — and the top bar arrives through that hole while the bottom one is
  # a literal profile path, which is the asymmetry every case below rests on.
  build_subject "$TMP/bin/sketchybar"

  # The bottom bar has no hole of its own — on a real machine it is always
  # /run/current-system/sw/bin/bar-bottom — so the env override is how a test
  # (and a producer's suite) stands anything else there.
  export HAUS_BAR_POKE_BOTTOM_BIN="$TMP/bin/bar-bottom"
}

build_subject() { # build_subject <what @sketchybar@ becomes>
  SUBJECT="$TMP/haus-bar-poke"
  sed -e "s|@sketchybar@|$1|" \
    "$BATS_TEST_DIRNAME/../modules/core/haus-bar-poke.sh" >"$SUBJECT"
  chmod +x "$SUBJECT"
}

log_lines() { # the recorder's log, or nothing when it was never written
  cat "$POKE_LOG" 2>/dev/null || true
}

@test "a poke reaches BOTH instances" {
  run "$SUBJECT" focus_change
  [ "$status" -eq 0 ]
  [ "$(log_lines)" = "sketchybar --trigger focus_change
bar-bottom --trigger focus_change" ]
}

@test "key=value arguments ride through to both, in order" {
  run "$SUBJECT" haus.agents.change client=claude state=waiting
  [ "$status" -eq 0 ]
  [ "$(log_lines)" = "sketchybar --trigger haus.agents.change client=claude state=waiting
bar-bottom --trigger haus.agents.change client=claude state=waiting" ]
}

# The one that makes this a binary rather than a comment: a machine with the bar
# room on and haus.bar.bottom.enable off has no second binary at all, and every
# producer calls this unconditionally. It must not be an error there.
@test "a missing bottom bar is a no-op, not a failure" {
  export HAUS_BAR_POKE_BOTTOM_BIN="$TMP/bin/does-not-exist"
  run "$SUBJECT" caffeinate_change
  [ "$status" -eq 0 ]
  [ "$(log_lines)" = "sketchybar --trigger caffeinate_change" ]
}

# The reverse, and the reason it is BUILT rather than exported: on a machine
# with no `sketchybar` roster entry, `@sketchybar@` is substituted with the
# EMPTY STRING, and the env override cannot reproduce that — `${VAR:-default}`
# treats an empty value as unset and falls straight back to the substituted
# path. So the empty case is the one that has to come through the derivation's
# own hole, which is also the only way this asserts what nix installs.
@test "an empty top-bar path skips it and still pokes the bottom" {
  build_subject ""
  run "$SUBJECT" focus_change
  [ "$status" -eq 0 ]
  [ "$(log_lines)" = "bar-bottom --trigger focus_change" ]
}

# A machine with no bar at all — `blank`, or any host that never turned the room
# on. Three rooms call this on their success paths (focus toggles, `awake 1h`,
# an agent taking a lid hold), and a repaint that could not happen must never be
# why one of those reports failure.
@test "no bars anywhere still exits 0 and touches nothing" {
  build_subject ""
  export HAUS_BAR_POKE_BOTTOM_BIN="$TMP/bin/does-not-exist"
  run "$SUBJECT" focus_change
  [ "$status" -eq 0 ]
  [ "$(log_lines)" = "" ]
}

# A bar that IS there and fails — a SketchyBar mid-reload, whose mach service
# cannot answer. Same contract: the caller's own work already succeeded.
@test "a bar that exits non-zero does not fail the poke" {
  cat >"$TMP/bin/sketchybar" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$POKE_LOG"
exit 3
EOF
  run "$SUBJECT" focus_change
  [ "$status" -eq 0 ]
  [ "$(log_lines)" = "sketchybar --trigger focus_change
bar-bottom --trigger focus_change" ]
}

# The one thing it DOES refuse. Every call site spells a literal event name, so
# an empty argv is a producer bug at build time rather than a runtime condition
# — and silently triggering nothing would leave that bug to be found by a pill
# that never repaints.
@test "no event name is a usage error, and pokes nothing" {
  run "$SUBJECT"
  [ "$status" -eq 64 ]
  [[ "$output" == *"usage: haus-bar-poke <event>"* ]]
  [ "$(log_lines)" = "" ]
}

#!/usr/bin/env bats
# Where a lane's WINDOW PROCESS stands, pinned as an invariant of
# modules/terminal/lanes/lane-open.sh.
#
# ── the failure this exists for ──────────────────────────────────────────────
# A lane spawned by an agent running `HAUS_LANE_BACKGROUND=1 scruff spawn` from
# its own shell — the spelling modules/ai/default.nix hands every agent here,
# and what `/handoff spawn` drives — used to leave its Ghostty process standing
# in the SPAWNING lane's checkout. The direct exec inherits the hook's cwd, the
# hook inherits its caller's, and a GUI process keeps the cwd it was born with
# for as long as the window is open.
#
# The palette takes the same code path and never leaked one, because pounce is a
# launchd agent standing in `/`. ⌘↵ cannot reach it at all: lanes/lane-spawn.sh
# sets no HAUS_LANE_BACKGROUND, so the subject leaves $ghostty_bin empty and the
# spawn goes through `open -na`, whose LaunchServices launch carries no cwd.
#
# scruff decides occupancy with `lsof -d cwd`, so that inherited cwd reads as a
# live occupant of a lane whose branch has landed and whose session is long
# gone: `scruff reap` refuses to sweep it and names a ghostty pid as the holder.
# Killing that pid closes the window of the OTHER lane — the one the refusal was
# never about — which is how the bug was found.
#
# MEASURED 2026-09-11, the hook run by hand from a lane checkout:
#
#   15953 ghostty /Users/julienmartel/.cache/scruff/workshop/spawn-lane-cleanup
#
# against `/` for all five lanes the palette had spawned on the same machine.
# The palette never showed it because pounce is a launchd agent and its cwd is
# already `/`; only a spawn from inside a checkout can leak one.
#
# ── what is pinned, and what is RUN ──────────────────────────────────────────
# The subject cannot be driven here — it wants Ghostty, AeroSpace, a live zmx
# and a display (see lane-no-display.bats for the same wall). But the launch
# itself is four lines of bash, so they are LIFTED OUT of the subject and run
# against a stub binary that records its own cwd: the fix is exercised rather
# than described, and the control case below runs the same lines with the `cd`
# removed to prove the assertion can fail.
#
# Needs bash + bats. No Nix, no Mac, no display, no Ghostty.

bats_require_minimum_version 1.5.0

SUBJECT() { printf '%s' "$BATS_TEST_DIRNAME/../modules/terminal/lanes/lane-open.sh"; }

# The launch, as the subject spells it today: from the `cd` through the
# backgrounded exec. Extracted rather than retyped — a copy would go on passing
# after the original drifted, which is the one thing this file exists to stop.
launch_lines() {
  awk '/^[[:space:]]*cd \/([[:space:]]|$)/ { on = 1 }
       on                                      { print }
       on && /&$/                              { exit }' "$(SUBJECT)"
}

# Run a launch chunk with a stub in place of Ghostty, from a known directory,
# and answer with the cwd the stub was born in.
born_in() { # born_in <chunk> <start dir>
  local chunk="$1" here="$2" stub="$BATS_TEST_TMPDIR/stub" out="$BATS_TEST_TMPDIR/cwd"
  rm -f "$out"
  cat > "$stub" <<'STUB'
#!/usr/bin/env bash
pwd > "$OUT"
STUB
  chmod +x "$stub"
  (
    cd "$here" || exit 1
    export OUT="$out"
    # The names the lifted lines reference. A lane's real ones are a session
    # name and a launcher path; neither is read by the stub.
    # shellcheck disable=SC2034
    local ghostty_bin="$stub" sess=probe launcher=/dev/null
    eval "$chunk"
  )
  local _
  for _ in $(seq 1 40); do
    [ -s "$out" ] && break
    sleep 0.05
  done
  cat "$out" 2>/dev/null
}

@test "the launch chunk is still where this file thinks it is" {
  # Every case below rests on the extraction. If the subject is reshaped so the
  # awk finds nothing, an empty chunk would eval to nothing and both arms would
  # agree — green, against a script that no longer contains the fix.
  local chunk
  chunk="$(launch_lines)"
  [ -n "$chunk" ]
  printf '%s\n' "$chunk" | grep -q 'nohup "\$ghostty_bin"'
  printf '%s\n' "$chunk" | grep -q -- '--initial-command="\$launcher"'
}

@test "the window process is born in /, not in the checkout it was spawned from" {
  # The fix, run. `/` is where the `open -na` fallback's window already lands
  # (LaunchServices launches carry no cwd), so both paths leave a window process
  # standing in no checkout at all — the only answer that cannot pin the wrong
  # one.
  [ "$(born_in "$(launch_lines)" "$BATS_TEST_TMPDIR")" = / ]
}

@test "and the cd is the reason — the same lines without it inherit the spawner" {
  # The control. Without this arm the case above would pass just as happily on
  # a machine where something ELSE had already put the process in `/`, and a
  # pin nobody has watched fail is a pin nobody has tested.
  # `|| true` so a chunk the extraction could not find fails THIS case on its
  # own assertion rather than on grep's exit status — the guard above is where
  # a moved anchor is meant to be reported.
  local without
  without="$(launch_lines | grep -v '^[[:space:]]*cd /' || true)"
  [ "$(born_in "$without" "$BATS_TEST_TMPDIR")" = "$BATS_TEST_TMPDIR" ]
}

@test "the lane's OWN directory still comes from the launcher, not from the process" {
  # What makes `/` safe. The window's shell is put in the checkout by the
  # launcher's own cd, one line before it execs zmx — so the lane opens where it
  # always did, and the process cwd is free to be neutral. Lose this line and
  # every lane would open in `/`.
  grep -qE "printf 'cd %q \|\| exit 1" "$(SUBJECT)"
  grep -qE "printf 'exec zmx attach %q bash -lc %q" "$(SUBJECT)"
}

@test "nothing between the cd and the exec walks back into a checkout" {
  # A later edit that put a `cd` of its own in the launch chunk would undo this
  # silently — the window would open, the lane would work, and the leak would be
  # back with no symptom until the next reap refused.
  local chunk
  chunk="$(launch_lines | grep -vE '^[[:space:]]*#' || true)"
  [ "$(printf '%s\n' "$chunk" | grep -cE '^[[:space:]]*cd ')" = 1 ]
}

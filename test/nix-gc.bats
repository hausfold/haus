#!/usr/bin/env bats
# Hermetic tests for modules/core/nix-gc.sh — the weekly store cleanup's
# survival of a store path macOS will not let go of.
#
# Why a suite. Every failure mode here is silent by construction. The bug it
# was written for produced ONE line in a log nobody reads and then a store that
# quietly grew for months; the wrapper's own failure modes are worse, because a
# loop whose exit condition is "nix stopped complaining" either spins forever
# or pins the wrong thing, and both look like a clean weekly run from outside.
# A feel-test cannot reach any of it: the real trigger needs a launched app
# bundle, root, and a week.
#
# So the subject is faked at exactly two seams — the collector and `xattr` —
# and every case is about the wrapper's decisions, never nix's. `$BATS_TEST_TMPDIR`
# stands in for /nix/var/nix/gcroots, so no case can touch a real store.

bats_require_minimum_version 1.5.0

setup() {
  GC_SH="${NIX_GC_UNDER_TEST:-$BATS_TEST_DIRNAME/../modules/core/nix-gc.sh}"
  ROOTS="$BATS_TEST_TMPDIR/gcroots"
  PLAN="$BATS_TEST_TMPDIR/plan"
  export FAKE_GC_N="$BATS_TEST_TMPDIR/n"
  export FAKE_GC_PLAN="$PLAN"

  # A collector that reads its answers off $PLAN, one per invocation, `<exit
  # code>|<output>`; the last line repeats forever so a case can say "this
  # never resolves" in one line.
  cat >"$BATS_TEST_TMPDIR/gc" <<'FAKE'
#!/usr/bin/env bash
n=$(cat "$FAKE_GC_N" 2>/dev/null || echo 0)
n=$((n + 1))
printf '%s' "$n" >"$FAKE_GC_N"
line=$(sed -n "${n}p" "$FAKE_GC_PLAN")
[ -n "$line" ] || line=$(tail -n 1 "$FAKE_GC_PLAN")
[ -n "${line#*|}" ] && printf '%s\n' "${line#*|}"
printf '%s store paths deleted, 0.0 KiB freed\n' "$n"
exit "${line%%|*}"
FAKE
  chmod +x "$BATS_TEST_TMPDIR/gc"
  export HAUS_NIX_GC_BIN="$BATS_TEST_TMPDIR/gc"
  export HAUS_NIX_GC_ROOTS="$ROOTS"
  # Default: an `xattr` that refuses, which is the interesting half. A case
  # that wants the strip to work overrides it.
  xattr_stub 1
}

# xattr_stub <exit code> — a recording `xattr` that answers with that code.
xattr_stub() {
  cat >"$BATS_TEST_TMPDIR/xattr" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$BATS_TEST_TMPDIR/xattr-calls"
exit $1
FAKE
  chmod +x "$BATS_TEST_TMPDIR/xattr"
  export HAUS_NIX_GC_XATTR="$BATS_TEST_TMPDIR/xattr"
}

# The real shape of the refusal, quoted the way nix quotes it. One line, because
# the plan file is one answer per line.
refusal() {
  printf 'error: chmod "%s/Applications/OrbStack.app": Operation not permitted' "$1"
}

STUCK=/nix/store/lzi45pjgh5960z2zwxsnzp9q93d1zj44-orbstack-2.2.1-20628
STUCK2=/nix/store/dipvm59ak1x26a55bys8nj8mbsrw28zb-orbstack-2.2.1-20628

@test "a store that collects cleanly runs once and pins nothing" {
  printf '0|\n' >"$PLAN"
  run "$GC_SH" 30d
  [ "$status" -eq 0 ]
  [[ "$output" == *"attempt 1:"* ]]
  [[ "$output" != *"attempt 2:"* ]]
  [[ "$output" != *"pinned as un-collectable"* ]]
  [ -z "$(ls -A "$ROOTS")" ]
}

@test "a path macOS will not release is pinned, and the collection finishes" {
  {
    printf '1|%s\n' "$(refusal "$STUCK")"
    printf '0|\n'
  } >"$PLAN"

  run "$GC_SH" 30d
  [ "$status" -eq 0 ]
  [ -L "$ROOTS/lzi45pjgh5960z2zwxsnzp9q93d1zj44-orbstack-2.2.1-20628" ]
  [ "$(readlink "$ROOTS/lzi45pjgh5960z2zwxsnzp9q93d1zj44-orbstack-2.2.1-20628")" = "$STUCK" ]
  [[ "$output" == *"pinned as un-collectable"* ]]
  [[ "$output" == *"$STUCK"* ]]
}

@test "it pins the store path, not the app bundle nix named" {
  {
    printf '1|%s\n' "$(refusal "$STUCK")"
    printf '0|\n'
  } >"$PLAN"

  run "$GC_SH" 30d
  [ "$status" -eq 0 ]
  # The error line named .../Applications/OrbStack.app. A root pointing at that
  # is not a store path, so nix would refuse it and the loop would never end.
  [ -z "$(find "$ROOTS" -name '*OrbStack.app*')" ]
  [ "$(find "$ROOTS" -type l | wc -l)" -eq 1 ]
}

@test "stripping the attributes is tried first, and skips the pin when it works" {
  xattr_stub 0
  {
    printf '1|%s\n' "$(refusal "$STUCK")"
    printf '0|\n'
  } >"$PLAN"

  run "$GC_SH" 30d
  [ "$status" -eq 0 ]
  [[ "$output" == *"tried clearing the extended attributes"* ]]
  [[ "$output" != *"pinned as un-collectable"* ]]
  [ -z "$(ls -A "$ROOTS")" ]
  grep -q -- "-c -r $STUCK" "$BATS_TEST_TMPDIR/xattr-calls"
}

@test "the strip is tried once per path, then the path is pinned" {
  xattr_stub 0
  {
    printf '1|%s\n' "$(refusal "$STUCK")"
    printf '1|%s\n' "$(refusal "$STUCK")"
    printf '0|\n'
  } >"$PLAN"

  run "$GC_SH" 30d
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$BATS_TEST_TMPDIR/xattr-calls")" -eq 1 ]
  [ -L "$ROOTS/lzi45pjgh5960z2zwxsnzp9q93d1zj44-orbstack-2.2.1-20628" ]
}

@test "several stuck paths are pinned one after another" {
  {
    printf '1|%s\n' "$(refusal "$STUCK")"
    printf '1|%s\n' "$(refusal "$STUCK2")"
    printf '0|\n'
  } >"$PLAN"

  run "$GC_SH" 30d
  [ "$status" -eq 0 ]
  [ "$(find "$ROOTS" -type l | wc -l)" -eq 2 ]
}

@test "last week's pins are cleared before this week's collection" {
  mkdir -p "$ROOTS"
  ln -s "$STUCK" "$ROOTS/lzi45pjgh5960z2zwxsnzp9q93d1zj44-orbstack-2.2.1-20628"
  printf '0|\n' >"$PLAN"

  run "$GC_SH" 30d
  [ "$status" -eq 0 ]
  [[ "$output" == *"cleared 1 pin(s)"* ]]
  [ -z "$(ls -A "$ROOTS")" ]
}

@test "a refusal inside nix's own trash directory is never pinned" {
  # /nix/store/trash is nix's staging area, not a store path. Pinning it would
  # be a root nix cannot resolve — a broken store in place of a survivable
  # failure — so this has to fall through to the unhandled-error path.
  {
    printf '1|%s\n' "$(refusal /nix/store/trash/lzi45pjgh5960z2zwxsnzp9q93d1zj44-orbstack)"
    printf '0|\n'
  } >"$PLAN"

  run "$GC_SH" 30d
  [ "$status" -ne 0 ]
  [ -z "$(ls -A "$ROOTS")" ]
  [[ "$output" == *"does not handle"* ]]
}

@test "a failure that is not a permission refusal is reported, not retried" {
  {
    printf '1|error: out of disk space\n'
    printf '0|\n'
  } >"$PLAN"

  run "$GC_SH" 30d
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not handle"* ]]
  [[ "$output" == *"out of disk space"* ]]
  [[ "$output" != *"attempt 2:"* ]]
  [ -z "$(ls -A "$ROOTS")" ]
}

@test "a store that never settles gives up instead of looping forever" {
  # The same path refuses even after being pinned — nix reporting a refusal the
  # pin does not resolve. Without the cap this is a weekly root daemon spinning
  # on a collection that can never end.
  export HAUS_NIX_GC_MAX_ATTEMPTS=3
  printf '1|%s\n' "$(refusal "$STUCK")" >"$PLAN"

  run "$GC_SH" 30d
  [ "$status" -ne 0 ]
  [[ "$output" == *"gave up after 3 attempts"* ]]
  [[ "$output" == *"attempt 3:"* ]]
  [[ "$output" != *"attempt 4:"* ]]
  # Pinned on every pass round, but it is one stuck path, and the summary has
  # to say so — a count that grows with the retries is a lie about the store.
  [ "$(printf '%s\n' "$output" | grep -c "^  $STUCK$")" -eq 1 ]
}

@test "the age argument reaches the collector" {
  cat >"$BATS_TEST_TMPDIR/gc" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$*" >"$BATS_TEST_TMPDIR/gc-args"
echo "0 store paths deleted, 0.0 KiB freed"
FAKE
  chmod +x "$BATS_TEST_TMPDIR/gc"

  run "$GC_SH" 14d
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/gc-args")" = "--delete-older-than 14d" ]
}

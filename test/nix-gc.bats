#!/usr/bin/env bats
# Hermetic tests for modules/core/nix-gc.sh — the weekly store cleanup's
# survival of a store path macOS will not let go of.
#
# Why a suite. Every failure mode here is silent by construction. The bug it
# was written for produced one line in a log nobody reads and then a store that
# quietly stopped being collected; the wrapper's own failure modes are worse,
# because a loop whose exit condition is "nix stopped complaining" either spins
# forever or pins the wrong thing, and both look like a clean weekly run from
# outside. A feel-test cannot reach any of it: the real trigger needs a
# launched app bundle, root, and a week.
#
# The case that matters most is `pins go in BEFORE the collection`. The obvious
# design pins reactively and appears to work — it logs a pin, it exits 0 — while
# rooting nothing at all, because nix invalidates a path's database entry before
# the delete that then fails, and a root pointing at an invalid path is skipped.
# That bug reached a real machine and was found by reading `nix-store --query
# --roots`, not by any output the wrapper produced.
#
# So the subject is faked at three seams — the collector, `xattr`, and
# `nix-store`'s validity check — over a store directory built per case under
# `$BATS_TEST_TMPDIR`. No case can touch a real store.

bats_require_minimum_version 1.5.0

TART=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-tart-2.36.0
ORB=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-orbstack-2.2.1-20628
IINA=cccccccccccccccccccccccccccccccc-iina-1.4.4

setup() {
  GC_SH="${NIX_GC_UNDER_TEST:-$BATS_TEST_DIRNAME/../modules/core/nix-gc.sh}"
  STORE="$BATS_TEST_TMPDIR/store"
  ROOTS="$BATS_TEST_TMPDIR/gcroots"
  ORPHANS="$BATS_TEST_TMPDIR/orphans"
  PLAN="$BATS_TEST_TMPDIR/plan"
  mkdir -p "$STORE"
  export FAKE_GC_N="$BATS_TEST_TMPDIR/n"
  export FAKE_GC_PLAN="$PLAN"
  export HAUS_NIX_GC_ROOTS="$ROOTS"
  export HAUS_NIX_GC_ORPHANS="$ORPHANS"
  export HAUS_NIX_STORE_DIR="$STORE"
  printf '0|\n' >"$PLAN"

  # A collector that reads its answers off $PLAN, one per invocation, as
  # `<exit code>|<output>`; the last line repeats forever, so a case can say
  # "this never resolves" in one line.
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

  # `nix-store --query --hash <path>`: valid iff the store path carries a
  # .valid marker. That is the check a GC root has to pass.
  cat >"$BATS_TEST_TMPDIR/nix-store" <<'FAKE'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in /*) p=$a ;; esac; done
[ -e "$p/.valid" ]
FAKE
  chmod +x "$BATS_TEST_TMPDIR/nix-store"
  export HAUS_NIX_STORE_BIN="$BATS_TEST_TMPDIR/nix-store"

  xattr_stub 1
}

# xattr_stub <strip exit code> — lists com.apple.macl for a bundle carrying a
# .stamped marker, and answers `-c -r` with that code (default: refuses, which
# is what macOS actually does).
xattr_stub() {
  cat >"$BATS_TEST_TMPDIR/xattr" <<FAKE
#!/usr/bin/env bash
if [ "\$1" = "-c" ]; then
  printf '%s\n' "\$*" >>"$BATS_TEST_TMPDIR/xattr-calls"
  exit $1
fi
[ -e "\$1/.stamped" ] && echo com.apple.macl
echo com.apple.provenance
FAKE
  chmod +x "$BATS_TEST_TMPDIR/xattr"
  export HAUS_NIX_GC_XATTR="$BATS_TEST_TMPDIR/xattr"
}

# mkapp <store path name> [stamped] [invalid] — a store path with an app bundle
# in it. Stamped means macOS has marked it; invalid means nix has already
# forgotten it, which is the state a failed delete leaves behind.
mkapp() {
  local dir="$STORE/$1" app
  app="$dir/Applications/${1#*-}.app"
  mkdir -p "$app"
  case " $* " in *" stamped "*) : >"$app/.stamped" ;; esac
  case " $* " in *" invalid "*) ;; *) : >"$dir/.valid" ;; esac
}

# The real shape of the refusal, quoted the way nix quotes it. One line,
# because the plan file is one answer per line.
refusal() {
  printf 'error: chmod "%s/%s/Applications/x.app": Operation not permitted' "$STORE" "$1"
}

pins() { find "$ROOTS" -type l 2>/dev/null | wc -l | tr -d ' '; }

@test "a store with nothing stamped collects in one pass and pins nothing" {
  mkapp "$IINA"
  run "$GC_SH" 30d
  [ "$status" -eq 0 ]
  [[ "$output" == *"attempt 1:"* ]]
  [[ "$output" != *"attempt 2:"* ]]
  [ "$(pins)" -eq 0 ]
}

@test "a stamped bundle is pinned BEFORE the collection runs" {
  # The whole design. Pinned reactively — after nix has invalidated the path —
  # a root is skipped as invalid and roots nothing, so the pin has to be in
  # place before the collector is ever asked to delete it.
  mkapp "$TART" stamped
  run "$GC_SH" 30d
  [ "$status" -eq 0 ]
  [[ "$output" == *"pinned 1 stamped app bundle(s) before collecting"* ]]
  [ -L "$ROOTS/$TART" ]
  [ "$(readlink "$ROOTS/$TART")" = "$STORE/$TART" ]
  [[ "$output" != *"attempt 2:"* ]]
}

@test "the pre-pin scan pins the store path, not the app bundle inside it" {
  mkapp "$TART" stamped
  run "$GC_SH" 30d
  [ "$status" -eq 0 ]
  [ -z "$(find "$ROOTS" -name '*.app*')" ]
  [ "$(pins)" -eq 1 ]
}

@test "an unstamped bundle is left alone, so ordinary apps still get collected" {
  mkapp "$TART" stamped
  mkapp "$IINA"
  run "$GC_SH" 30d
  [ "$status" -eq 0 ]
  [ "$(pins)" -eq 1 ]
  [ -L "$ROOTS/$TART" ]
  [ ! -e "$ROOTS/$IINA" ]
}

@test "a stamped bundle nix has already forgotten is not pinned" {
  # nix skips a root that points at an invalid path, so pinning one is a lie
  # the log would tell every week.
  mkapp "$ORB" stamped invalid
  run "$GC_SH" 30d
  [ "$status" -eq 0 ]
  [ "$(pins)" -eq 0 ]
  [[ "$output" != *"before collecting"* ]]
}

@test "a valid path the scan missed is pinned reactively and the run finishes" {
  mkapp "$TART"
  {
    printf '1|%s\n' "$(refusal "$TART")"
    printf '0|\n'
  } >"$PLAN"

  run "$GC_SH" 30d
  [ "$status" -eq 0 ]
  [ -L "$ROOTS/$TART" ]
  [[ "$output" == *"pinned as un-collectable"* ]]
}

@test "stripping the attributes is tried first, and skips the pin when it works" {
  xattr_stub 0
  mkapp "$TART"
  {
    printf '1|%s\n' "$(refusal "$TART")"
    printf '0|\n'
  } >"$PLAN"

  run "$GC_SH" 30d
  [ "$status" -eq 0 ]
  [[ "$output" == *"tried clearing the extended attributes"* ]]
  [ "$(pins)" -eq 0 ]
  grep -q -- "-c -r $STORE/$TART" "$BATS_TEST_TMPDIR/xattr-calls"
}

@test "the strip is tried once per path, then the path is pinned" {
  xattr_stub 0
  mkapp "$TART"
  {
    printf '1|%s\n' "$(refusal "$TART")"
    printf '1|%s\n' "$(refusal "$TART")"
    printf '0|\n'
  } >"$PLAN"

  run "$GC_SH" 30d
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$BATS_TEST_TMPDIR/xattr-calls")" -eq 1 ]
  [ -L "$ROOTS/$TART" ]
}

@test "an orphan is moved out of the store, because nothing can root it" {
  # The state a pre-wrapper run leaves: on disk, invalid, and reconsidered by
  # every future collection. A pin is skipped as invalid, so the only way past
  # it is out of the store directory.
  mkapp "$ORB" invalid
  {
    printf '1|%s\n' "$(refusal "$ORB")"
    printf '0|\n'
  } >"$PLAN"

  run "$GC_SH" 30d
  [ "$status" -eq 0 ]
  [ ! -e "$STORE/$ORB" ]
  [ -d "$ORPHANS/$ORB" ]
  [ "$(pins)" -eq 0 ]
  [[ "$output" == *"moved out of the store"* ]]
}

@test "an orphan that cannot be moved is reported with the one command that clears it" {
  mkapp "$ORB" invalid
  printf '1|%s\n' "$(refusal "$ORB")" >"$PLAN"
  # A file where the orphan directory should be is the stand-in for a rename
  # macOS refuses: mkdir -p fails, so the move cannot even be attempted.
  : >"$ORPHANS"

  run "$GC_SH" 30d
  [ "$status" -ne 0 ]
  [ -e "$STORE/$ORB" ]
  [[ "$output" == *"could not be moved aside"* ]]
  [[ "$output" == *"sudo rm -rf $STORE/$ORB"* ]]
  [[ "$output" != *"attempt 3:"* ]]
}

@test "last week's pins are cleared before this week's are derived" {
  mkdir -p "$ROOTS"
  ln -s "$STORE/$IINA" "$ROOTS/$IINA"
  run "$GC_SH" 30d
  [ "$status" -eq 0 ]
  [[ "$output" == *"cleared 1 pin(s)"* ]]
  [ "$(pins)" -eq 0 ]
}

@test "a refusal inside nix's own trash directory is never pinned" {
  # /nix/store/trash is nix's staging area, not a store path. Pinning it would
  # be a root nix cannot resolve, so this has to fall through to the
  # unhandled-error path.
  printf '1|error: chmod "%s/trash/xyz": Operation not permitted\n' "$STORE" >"$PLAN"

  run "$GC_SH" 30d
  [ "$status" -ne 0 ]
  [ "$(pins)" -eq 0 ]
  [[ "$output" == *"does not handle"* ]]
}

@test "a failure that is not a permission refusal is reported, not retried" {
  printf '1|error: out of disk space\n' >"$PLAN"

  run "$GC_SH" 30d
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not handle"* ]]
  [[ "$output" == *"out of disk space"* ]]
  [[ "$output" != *"attempt 2:"* ]]
}

@test "a store that never settles gives up instead of looping forever" {
  # The same valid path refuses even after being pinned. Without the cap this
  # is a weekly root daemon spinning on a collection that can never end.
  export HAUS_NIX_GC_MAX_ATTEMPTS=3
  mkapp "$TART"
  printf '1|%s\n' "$(refusal "$TART")" >"$PLAN"

  run "$GC_SH" 30d
  [ "$status" -ne 0 ]
  [[ "$output" == *"gave up after 3 attempts"* ]]
  [[ "$output" == *"attempt 3:"* ]]
  [[ "$output" != *"attempt 4:"* ]]
  # Pinned on every pass round, but it is one stuck path and the summary has to
  # say so — a count that grows with the retries is a lie about the store.
  [ "$(printf '%s\n' "$output" | grep -c "^  $STORE/$TART$")" -eq 1 ]
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

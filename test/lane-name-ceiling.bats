#!/usr/bin/env bats
# The zmx session-name ceiling, as modules/terminal/lanes/lane-open.sh meets it.
#
# ── the failure this exists for ──────────────────────────────────────────────
# MEASURED 2026-09-09: `scruff spawn ~/code/workshop/hausfold.co
# docs-displays-expansion-slim` created the lane, and its window died on
# Ghostty's own launch error:
#
#   error: session name is too long (47 bytes, max 46 for socket directory
#   "/var/folders/nc/…/T/zmx-501")
#
# zmx names a unix socket after the session, a sockaddr_un holds 104 bytes with
# the NUL, and the path is <dir>/<name> — so the ceiling is 102 - len(dir), 46
# on a Mac with a three-digit uid. `scruff.hausfold.co.docs-displays-expansion-slim`
# is 47. The lane existed with a branch and a checkout and no way in, and the
# only diagnosis was in a window that closed.
#
# The fix is upstream, at the moment the name can still change: scruff's
# `name_max` (SPEC.md §5.7), written by modules/terminal/default.nix. What is
# pinned here is the backstop — the case a build-time constant cannot see.
#
# ── why nothing here runs the subject ────────────────────────────────────────
# Same rule as lane-no-display.bats and ghostty-prewarm.bats one file over, and
# this suite learned it the hard way: an end-to-end case DID run lane-open.sh
# against the live machine, the ceiling check did not fire (under bats $TMPDIR
# is a short run directory, so zmx's ceiling is roughly 74 and the 47-byte name
# this file exists for sails through), and the run walked into the launcher and
# put a Ghostty window on the screen of the person at the Mac. The guard meant
# to stop that sat one line BELOW the check it was guarding, so every path that
# skipped the check skipped the guard too.
#
# There is no safe version of that test. The subject's whole tail is "open a
# window", it exports its own PATH — system directories first, because scruff
# may exec it from launchd — so no stub `zmx` a test puts on PATH can win, and
# the one knob that does move the ceiling (ZMX_DIR) leaves every other way of
# reaching the launcher open. So the arithmetic and the message are lifted out
# and run here, and the decisions around them are pinned as text.
#
# Needs bash + bats. No Nix, no Mac, no zmx, no display — and it opens nothing.

bats_require_minimum_version 1.5.0

SUBJECT() { printf '%s' "$BATS_TEST_DIRNAME/../modules/terminal/lanes/lane-open.sh"; }

# CHECK runs the subject's ceiling block against a socket directory and a
# session name of the test's choosing — the two inputs the real thing has.
CHECK() { # CHECK <socket dir> <lane name> <repo>
    local sock_dir="$1" name="$2" repo="$3" sess budget
    sess="scruff.$repo.$name"
    budget=$((102 - ${#sock_dir}))
    [ "${#sess}" -gt "$budget" ] || return 0
    printf '▲ %s is too long a lane name for this machine: the zmx session %s is %s bytes and %s holds %s.\n' \
        "$name" "$sess" "${#sess}" "$sock_dir" "$budget"
    printf '  scruff drop %s/%s, then spawn it again with a name of %s characters or fewer.\n' \
        "$repo" "$name" "$((budget - ${#sess} + ${#name}))"
    return 3
}

@test "the ceiling is 102 minus the socket directory, and the subject computes it that way" {
    # 104 bytes of sockaddr_un, minus the NUL, minus the separating slash. Get
    # this wrong by one and the backstop passes a name zmx will refuse.
    grep -q 'budget=\$((102 - \${#sock_dir}))' "$(SUBJECT)"
    grep -q '\[ "\${#sess}" -gt \$((102 - \${#sock_dir})) \]' "$(SUBJECT)"
}

@test "the socket directory is measured, never assumed" {
    # zmx takes it from ZMX_DIR, then XDG_RUNTIME_DIR, then TMPDIR, and prints
    # the winner. A constant here would be wrong on any machine that overrides
    # one of the three — which is the only case this backstop exists for.
    grep -q 'zmx version' "$(SUBJECT)"
    grep -q 'socket_dir' "$(SUBJECT)"
}

@test "a zmx that cannot be asked leaves the lane alone" {
    # An empty answer must not become a refusal: this is a backstop and has no
    # business being the thing that stops a lane opening.
    grep -q '\[ -n "\$sock_dir" \] &&' "$(SUBJECT)"
}

@test "it defers rather than attaching, so the lane survives to be renamed" {
    # Exit 3 is the seam's "no opinion": scruff prints how to open the lane and
    # the checkout and branch are untouched. Exec'ing the attach anyway would
    # put the reason back in a window that closes.
    run bash -c "sed -n '/a name zmx cannot hold/,/^fi$/p' \"$(SUBJECT)\" | grep -c 'exit 3'"
    [ "$output" = 1 ]
}

@test "the refusal names both numbers and the budget that is left" {
    run CHECK /var/folders/nc/wwv8hwvn3sn2wvz8nnc4nhk40000gn/T/zmx-501 docs-displays-expansion-slim hausfold.co
    [ "$status" -eq 3 ]
    [[ "$output" == *"47 bytes"* ]]            # what the session would have cost
    [[ "$output" == *"holds 46"* ]]            # what this machine carries
    [[ "$output" == *"zmx-501"* ]]             # where that ceiling comes from
    # `scruff.hausfold.co.` spends 19 of the 46, so a lane here gets 27. A
    # message that stops at "too long" makes the reader do this arithmetic.
    [[ "$output" == *"27 characters or fewer"* ]]
    [[ "$output" == *"scruff drop hausfold.co/docs-displays-expansion-slim"* ]]
}

@test "a name that fits says nothing at all" {
    # The one that actually shipped, 37 bytes against 46. Every lane runs this
    # block, so a false positive here is every lane.
    run CHECK /var/folders/nc/wwv8hwvn3sn2wvz8nnc4nhk40000gn/T/zmx-501 docs-displays-slim hausfold.co
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "a name at the ceiling exactly is a name that fits" {
    # 46 bytes. zmx 0.7.0 takes this one and refuses the next, measured.
    run CHECK /var/folders/nc/wwv8hwvn3sn2wvz8nnc4nhk40000gn/T/zmx-501 docs-displays-expansion-sli hausfold.co
    [ "$status" -eq 0 ]
}

@test "a roomier socket directory carries a longer name" {
    # The reason this is measured rather than constant: ZMX_DIR=/tmp/zmx-501
    # makes the same name comfortable.
    run CHECK /tmp/zmx-501 docs-displays-expansion-slim hausfold.co
    [ "$status" -eq 0 ]
}

@test "the repo is half of the budget, so the same name differs by repo" {
    # `scruff.nix.` spends 11 where `scruff.hausfold.co.` spends 19.
    run CHECK /var/folders/nc/wwv8hwvn3sn2wvz8nnc4nhk40000gn/T/zmx-501 docs-displays-expansion-slim nix
    [ "$status" -eq 0 ]
}

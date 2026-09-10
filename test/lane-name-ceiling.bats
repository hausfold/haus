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
# ── the subject's own function, not a copy of it ─────────────────────────────
# `name_fits` is lifted out of lane-open.sh and run, the way new-window-title.bats
# lifts its one function: sed the real text, define a `zmx` in front of it, call
# it. A copy of the arithmetic here would pass while the shipped one rotted, and
# the recovery number (`budget - ${#sess} + ${#SCRUFF_NAME}`) is the trickiest
# thing in the change.
#
# Nothing runs the SCRIPT. Its whole tail is "open a window", it exports its own
# PATH so no stub can win, and a case that fails to refuse walks straight into
# the launcher — which is not hypothetical: an end-to-end test written for this
# file did exactly that and put a Ghostty window on the screen of the person at
# the Mac. lane-no-display.bats and ghostty-prewarm.bats are text-only for the
# same subject and say so too.
#
# Needs bash + bats. No Nix, no Mac, no zmx, no display — and it opens nothing.

bats_require_minimum_version 1.5.0

SUBJECT() { printf '%s' "$BATS_TEST_DIRNAME/../modules/terminal/lanes/lane-open.sh"; }

# FITS runs the SHIPPED name_fits against a socket directory, a lane name and a
# repo of the test's choosing, with `zmx version` answered by a shell function.
# `cfg` is a scruff config.toml body, so the clamp can be exercised too.
FITS() { # FITS <socket dir> <lane name> <repo> [config.toml body]
    local fn; fn="$(sed -n '/^name_fits() {/,/^}$/p' "$(SUBJECT)")"
    [ -n "$fn" ] || { echo "name_fits is no longer a function in the subject" >&2; return 99; }
    mkdir -p "$BATS_TEST_TMPDIR/cfg/scruff"
    printf '%s\n' "${4-}" >"$BATS_TEST_TMPDIR/cfg/scruff/config.toml"
    SOCK="$1" NAME="$2" REPO="$3" CFG="$BATS_TEST_TMPDIR/cfg" bash -c '
        zmx() { printf "zmx\t\t0.7.0\nsocket_dir\t%s\nlog_dir\t\t/x\n" "$SOCK"; }
        XDG_CONFIG_HOME="$CFG"
        SCRUFF_NAME="$NAME"; repo="$REPO"; sess="scruff.$REPO.$NAME"
        '"$fn"'
        name_fits
    ' 2>&1
}

@test "the ceiling is 102 minus the socket directory" {
    # 104 bytes of sockaddr_un, minus the NUL, minus the separating slash. Get
    # this wrong by one and the backstop passes a name zmx will refuse.
    grep -q 'budget=\$((102 - \${#sock_dir}))' "$(SUBJECT)"
}

@test "the socket directory is measured, never assumed" {
    # zmx takes it from ZMX_DIR, then XDG_RUNTIME_DIR, then TMPDIR, and prints
    # the winner. A constant here would be wrong on any machine that overrides
    # one of the three — which is the only case this backstop exists for.
    grep -q 'zmx version' "$(SUBJECT)"
    grep -q 'socket_dir' "$(SUBJECT)"
}

@test "the length is counted in bytes, not characters" {
    # ${#…} is characters under a UTF-8 locale and the ceiling is bytes, so one
    # accented character in a repo directory would let a refused name through.
    grep -q 'local LC_ALL=C' "$(SUBJECT)"
}

@test "it defers rather than attaching, so nothing half-opens" {
    # Exit 3 is the seam's "no opinion". Exec'ing the attach anyway would put
    # the reason back in a window that closes.
    grep -q '^name_fits || exit 3$' "$(SUBJECT)"
}

@test "the refusal names both numbers, the directory, and what is left" {
    run FITS /var/folders/nc/wwv8hwvn3sn2wvz8nnc4nhk40000gn/T/zmx-501 docs-displays-expansion-slim hausfold.co
    [ "$status" -eq 3 ]
    [[ "$output" == *"too long a lane name"* ]]  # the sentence a reader meets first
    [[ "$output" == *"47 bytes"* ]]            # what the session would have cost
    [[ "$output" == *"holds 46"* ]]            # what this machine carries
    [[ "$output" == *"zmx-501"* ]]             # where that ceiling comes from
    # `scruff.hausfold.co.` spends 19 of the 46, so a lane here gets 27. A
    # message that stops at "too long" makes the reader do this arithmetic.
    [[ "$output" == *"27 bytes or fewer"* ]]
    [[ "$output" == *"scruff drop hausfold.co/docs-displays-expansion-slim"* ]]
}

@test "the advice never promises the lane is still there" {
    # It usually is not: `scruff spawn` treats a defer as "nothing opened it",
    # and the palette drops the lane itself before anyone reads this.
    run FITS /var/folders/nc/wwv8hwvn3sn2wvz8nnc4nhk40000gn/T/zmx-501 docs-displays-expansion-slim hausfold.co
    [[ "$output" == *"if the lane is still listed"* ]]
}

@test "a name that fits says nothing at all" {
    # The one that actually shipped, 37 bytes against 46. Every lane runs this,
    # so a false positive here is every lane.
    run FITS /var/folders/nc/wwv8hwvn3sn2wvz8nnc4nhk40000gn/T/zmx-501 docs-displays-slim hausfold.co
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "a name at the ceiling exactly is a name that fits" {
    # 46 bytes. zmx 0.7.0 takes this one and refuses the next, measured.
    run FITS /var/folders/nc/wwv8hwvn3sn2wvz8nnc4nhk40000gn/T/zmx-501 docs-displays-expansion-sli hausfold.co
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "a roomier socket directory carries a longer name" {
    # The reason this is measured rather than constant: ZMX_DIR=/tmp/zmx-501
    # makes the same name comfortable.
    run FITS /tmp/zmx-501 docs-displays-expansion-slim hausfold.co
    [ "$status" -eq 0 ]
}

@test "the repo is half of the budget, so the same name differs by repo" {
    # `scruff.nix.` spends 11 where `scruff.hausfold.co.` spends 19.
    run FITS /var/folders/nc/wwv8hwvn3sn2wvz8nnc4nhk40000gn/T/zmx-501 docs-displays-expansion-slim nix
    [ "$status" -eq 0 ]
}

@test "an unreadable zmx is never a refusal" {
    # An empty answer must not stop a lane opening: this is a backstop, not a
    # gate. `zmx version` printing nothing parseable takes this path.
    run FITS "" docs-displays-expansion-slim hausfold.co
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "the padding in zmx's own output cannot make the check a no-op" {
    # `zmx version` is tab-ALIGNED, not TSV — short keys carry two tabs. A
    # fixed field index reads the padding, yields nothing, and silently turns
    # the whole backstop off. The stub in FITS reproduces that alignment, so
    # the refusal above only passes if the parse survives it.
    grep -q 'for (i = NF; i > 1; i--)' "$(SUBJECT)"
}

@test "the budget is clamped to name_max, so both halves quote one number" {
    # scruff refuses against `name_max`, a build-time FLOOR; the measurement
    # here is this Mac's real ceiling and is usually roomier. Quoting the
    # roomier one sends the reader back for a second refusal with different
    # arithmetic — the recovery flow this whole change exists for.
    run FITS /var/folders/nc/wwv8hwvn3sn2wvz8nnc4nhk40000gn/T/zmx-501 docs-displays-expansion-sli hausfold.co 'name_max = "44"'
    [ "$status" -eq 3 ] || fail "44 leaves 25 for a lane in hausfold.co; a 26-byte name must not pass: $output"
    [[ "$output" == *"holds 44"* ]]
    [[ "$output" == *"25 bytes or fewer"* ]]
}

@test "a config with no name_max leaves the measurement alone" {
    run FITS /var/folders/nc/wwv8hwvn3sn2wvz8nnc4nhk40000gn/T/zmx-501 docs-displays-expansion-sli hausfold.co 'agent = "claude"'
    [ "$status" -eq 0 ]
}

# The config.toml this reads may be hand-written, and scruff strips the comment
# and the surrounding space before it parses — SPEC.md §5.7's example line
# carries one. A miss is not a refusal but a DISAGREEMENT: this half would quote
# the roomier measured ceiling (46 here) while scruff refuses against 44, which
# is the second-refusal loop the clamp exists to close. Same pattern as
# commands/spawn-agent.sh's `slug_budget`.
@test "the clamp reads a name_max written the way the spec writes it" {
    run FITS /var/folders/nc/wwv8hwvn3sn2wvz8nnc4nhk40000gn/T/zmx-501 docs-displays-expansion-sli hausfold.co \
        '  name_max = "44"   # the longest key this machine can hold'
    [ "$status" -eq 3 ] || fail "a commented name_max is still 44: $output"
    [[ "$output" == *"holds 44"* ]]
    [[ "$output" == *"25 bytes or fewer"* ]]
}

@test "a name_max roomier than the machine does not raise the ceiling" {
    # The clamp is a floor, not an override: a config that claims more than the
    # socket directory allows must not talk this machine into a name zmx will
    # refuse.
    run FITS /var/folders/nc/wwv8hwvn3sn2wvz8nnc4nhk40000gn/T/zmx-501 docs-displays-expansion-slim hausfold.co 'name_max = "90"'
    [ "$status" -eq 3 ]
    [[ "$output" == *"holds 46"* ]]
}

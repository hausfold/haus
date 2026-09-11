#!/usr/bin/env bats
# The GUI-agent launch wait — modules/lib/gui-wait.nix — pinned as an invariant.
#
# This script is the first thing that runs in every GUI agent's launchd job: the
# bar (twice, top and bottom), AeroSpace and pounce. Nothing reports on it. A
# mistake here is a bar that is late, a tiler whose hotkeys never registered, or
# a palette that does not answer ⌘Space, all with a live pid and an empty log,
# and all of it noticed days later.
#
# ── what went wrong once, and must not come back ─────────────────────────────
# The second loop used to be an Apple event:
#
#     osascript -e 'tell application "System Events" to count processes'
#
# Two failures, one cause. macOS files the request under /bin/bash — the
# script's own interpreter, because a launchd job's responsible-process chain
# never resolves to an app bundle — so a fresh machine's first impression was a
# modal reading "'bash' wants access to control 'System Events.app'" with
# nothing drawn behind it. And refusing it was the expensive half: a denied
# Apple event does not fail fast, it sits out the Apple Event Manager's
# two-minute timeout, and it does that in the `until` CONDITION, which the
# deadline check in the loop body only runs between. Instrumented on a cold boot
# of a guest with the grant denied, AeroSpace exec'd 125 s in, not 65; with the
# Apple event gone, 4.3 s.
#
# So the case below is narrow on purpose, and so is what it claims: an Apple
# event was the one call in this file with a multi-minute manager timeout behind
# it, and it may not come back. It is NOT a proof that any future probe is safe
# in that position — a probe that blocks still outlives the deadline, whatever
# blocks it.
#
# ── and the three things the fix leans on ────────────────────────────────────
#   * the deadline is read inside every loop, once per loop;
#   * the probe tests for a NAME, not for bytes. `lsappinfo info -only name`
#     answers the null ASN with `"LSDisplayName"=[ NULL ]`, which is non-empty
#     and satisfies a bare `-n` on the first iteration — in exactly the window
#     the loop exists for. The sed peel is what makes the test real;
#   * the settle after the wait is LOAD-BEARING, and lives in the SHARED script
#     so that pounce gets it too. Across instrumented cold boots the probe first
#     answered 0.08 / 0.54 / 0.31 s before a real RegisterEventHotKey — the
#     Carbon call AeroSpace's hotkeys are — first succeeded in a freshly spawned
#     process. Five seconds covers that; zero would not, and zero is what
#     `.script`'s only consumer had while the settle sat in the wrappers.

bats_require_minimum_version 1.5.0

FILE() { printf '%s' "$BATS_TEST_DIRNAME/../modules/lib/gui-wait.nix"; }

# The bash between `script = ''` and its closing `'';` — the part that actually
# runs on every login, with the Nix around it dropped.
script_body() {
    awk -v q="'" '
        $0 == "  script = " q q { inside = 1; next }
        inside && $0 == "  " q q ";" { inside = 0 }
        inside
    ' "$(FILE)"
}

# The whole file minus its comments: the two wrappers included, since an Apple
# event added THERE would never appear in script_body.
code_body() {
    grep -v '^[[:space:]]*#' "$(FILE)"
}

@test "no wait in the file carries an Apple event" {
    body="$(code_body)"
    [ -n "$body" ]
    refute_match() {
        if printf '%s' "$body" | grep -qi -- "$1"; then
            printf 'gui-wait.nix runs %s — see this file'\''s header.\n' "$2" >&2
            return 1
        fi
    }
    refute_match 'osascript'        'osascript'
    refute_match 'tell application'  'an AppleScript `tell application`'
    refute_match 'System Events'     'a System Events request'
    refute_match 'open -a'           '`open -a`, which launches an app'
}

@test "every probe is an absolute boot-volume path" {
    body="$(script_body)"
    [ -n "$body" ]
    # /nix is not mounted yet when this runs — problem 1 in the header. That
    # includes the launchd PATH, which starts with /run/current-system/sw/bin,
    # so nothing here may be spelled as a bare command name either.
    ! printf '%s' "$body" | grep -q '/nix/'
    while read -r path; do
        case "$path" in
        /bin/* | /usr/bin/* | /dev/null) ;;
        *)
            printf 'gui-wait.nix names %s, which is not on the boot volume\n' "$path" >&2
            return 1
            ;;
        esac
    done < <(printf '%s' "$body" |
        grep -oE '(^|[[:space:]>|])/[A-Za-z0-9_/.-]+' |
        sed 's/^[^/]*//' | sort -u)
    # …and the three verbs it calls are called by path, not by name.
    for verb in date pgrep sleep lsappinfo sed; do
        if printf '%s' "$body" | grep -qE "(^|[^/[:alnum:]])$verb "; then
            printf 'gui-wait.nix calls bare `%s`, which resolves through PATH\n' "$verb" >&2
            return 1
        fi
    done
}

@test "one shared deadline, read once inside every loop" {
    body="$(script_body)"
    [ "$(printf '%s\n' "$body" | grep -c 'deadline=\$((')" -eq 1 ]
    [ "$(printf '%s\n' "$body" | grep -c '+ 60 ))')" -eq 1 ]
    loops=$(printf '%s\n' "$body" | grep -c '^\s*until ')
    checks=$(printf '%s\n' "$body" | grep -c -- '-ge "\$deadline" \] && break')
    [ "$loops" -ge 2 ]
    [ "$loops" -eq "$checks" ]
}

@test "the LaunchServices probe waits for a name, not for bytes" {
    # The regression this case exists for: `lsappinfo info -only name` answers
    # the null ASN with a line that is non-empty and is not a name. Run the
    # file's own sed over both, rather than restating it here.
    peel=$(script_body | grep -o "/usr/bin/sed -n '[^']*'")
    [ -n "$peel" ]
    run bash -c "printf '%s' '\"LSDisplayName\"=[ NULL ] ' | $peel"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run bash -c "printf '%s' '\"LSDisplayName\"=\"Finder\" ' | $peel"
    [ "$status" -eq 0 ]
    [ "$output" = "Finder" ]
}

@test "the script parses under the bash launchd runs it with" {
    # The plist names /bin/bash, which is 3.2 on macOS. A Linux runner's
    # /bin/bash is 5.x, so this case is a syntax check there and a 3.2 syntax
    # check on a Mac; it is not a claim that 3.2 ran it in CI.
    script_body > "$BATS_TEST_TMPDIR/wait.sh"
    run /bin/bash -n "$BATS_TEST_TMPDIR/wait.sh"
    [ "$status" -eq 0 ]
}

@test "the settle is in the shared script, so pounce gets it too" {
    # It was in the two wrappers, which meant .script — pounce's form, and the
    # one agent whose failure is a dead ⌘Space — had none. See the header.
    [ "$(grep -c 'sleep 5$' "$(FILE)")" -eq 1 ]
    [ "$(script_body | tail -1 | sed 's/^[[:space:]]*//')" = "/bin/sleep 5" ]
    run grep -A1 -- '${script}' "$(FILE)"
    [ "$status" -eq 0 ]
    [[ "$output" == *'exec "$0"'* ]]
    [[ "$output" == *'exec "$0" "$@"'* ]]
}

@test "the target stays argv[0] — SketchyBar names its instance after it" {
    # bar draws its second bar by exec'ing the same binary as `bar-bottom`, and
    # SketchyBar keys its lock file and mach service on basename(argv[0]). Fold
    # the target into the -c string and both bars become one.
    grep -q 'exec "\$0" "\$@"' "$(FILE)"
    grep -q 'exec "\$0"$' "$(FILE)"
    ! grep -q 'exec \${target}' "$(FILE)"
}

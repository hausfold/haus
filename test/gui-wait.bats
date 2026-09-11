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
# two-minute timeout INSIDE the loop body, where the file's one shared 60 s
# deadline never gets read. Instrumented on a cold boot of a guest with the
# grant denied, AeroSpace exec'd 125 s in, not 65; with the Apple event gone,
# 4.3 s. Every login, for every agent, until the probe changed.
#
# So the invariant is not "call lsappinfo" — it is that NO WAIT IN THIS FILE MAY
# BLOCK ON SOMETHING TCC CAN REFUSE, because that is what silently unbinds the
# deadline the rest of the header is about. A future probe is free to be
# something else entirely; it is not free to be an Apple event.
#
# ── and the two things the fix leans on ──────────────────────────────────────
#   * the deadline is read inside every loop, once per loop;
#   * the 5 s settle after the wait is LOAD-BEARING now, not decoration. Across
#     instrumented cold boots the LaunchServices probe first answered 0.1-0.5 s
#     before a real RegisterEventHotKey — the Carbon call AeroSpace's hotkeys
#     are — first succeeded in a freshly spawned process. Five seconds covers
#     that by an order of magnitude; zero would not.

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

@test "the wait carries no Apple event" {
    body="$(script_body)"
    [ -n "$body" ]
    refute_match() {
        if printf '%s' "$body" | grep -qi -- "$1"; then
            printf 'gui-wait.nix runs %s — see this file'\''s header.\n' "$2" >&2
            return 1
        fi
    }
    refute_match 'osascript'       'osascript'
    refute_match 'tell application' 'an AppleScript `tell application`'
    refute_match 'System Events'   'a System Events request'
    refute_match 'open -a'         '`open -a`, which launches an app'
}

@test "every probe is an absolute boot-volume path" {
    body="$(script_body)"
    # /nix is not mounted yet when this runs — problem 1 in the header.
    ! printf '%s' "$body" | grep -q '/nix/'
    # Everything the script names by path lives in /bin or /usr/bin.
    while read -r path; do
        case "$path" in
        /bin/* | /usr/bin/* | /dev/null) ;;
        *)
            printf 'gui-wait.nix names %s, which is not on the boot volume\n' "$path" >&2
            return 1
            ;;
        esac
    done < <(printf '%s' "$body" | grep -o '/[A-Za-z0-9_/.-]*' | sort -u)
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

@test "the script parses under the bash launchd runs it with" {
    # /bin/bash is 3.2 and is what the plist names; on a runner that hasn't got
    # it, whatever bash is here still catches a syntax error.
    sh=/bin/bash
    [ -x "$sh" ] || sh=bash
    script_body > "$BATS_TEST_TMPDIR/wait.sh"
    run "$sh" -n "$BATS_TEST_TMPDIR/wait.sh"
    [ "$status" -eq 0 ]
}

@test "both wrappers keep the 5 s settle between the wait and the exec" {
    # The probe answers a little before the Carbon event path does; this is the
    # margin. See the header.
    [ "$(grep -c '^ *sleep 5$' "$(FILE)")" -eq 2 ]
    run grep -A1 'sleep 5' "$(FILE)"
    [ "$status" -eq 0 ]
    [[ "$output" == *'exec "$0"'* ]]
}

@test "the target stays argv[0] — SketchyBar names its instance after it" {
    # bar draws its second bar by exec'ing the same binary as `bar-bottom`, and
    # SketchyBar keys its lock file and mach service on basename(argv[0]). Fold
    # the target into the -c string and both bars become one.
    grep -q 'exec "\$0" "\$@"' "$(FILE)"
    grep -q 'exec "\$0"$' "$(FILE)"
    ! grep -q 'exec \${target}' "$(FILE)"
}

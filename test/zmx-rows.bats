#!/usr/bin/env bats
# Hermetic tests for modules/terminal/scripts/zmx-rows.sh — the one reader for
# the `zmx ls` wire format, which ~10 awk/sed programs in 8 files across three
# rooms each re-derived by hand until it existed.
#
# Why a suite. Every trap here has already fired in production, silently:
# the attached-row marker glued to the first key cost exactly the session the
# chord was pressed in; the 0.7.0 `start_dir` rename broke ⌘↵ with nothing on
# any stream (the old spelling was a file:// URL needing host-stripping, so
# reading one spelling is wrong in each direction); and `zmx get` flipped from
# tab- to space-separated at 0.7.0, which left both hand parses of it
# answering EMPTY for every key — raise-session's exact lane join fell through
# to its title scan for months and nobody saw. The fixtures below are verbatim
# the shapes a live zmx 0.7.0 emits (od-verified 2026-09-02), because a stub
# that paraphrases its subject is how a suite starts passing for the wrong
# reason.
#
# Hermetic: zmx is a stub behind HAUS_ZMX_BIN — the subject's own PATH prelude
# puts the system profile first, so on a dev Mac a PATH stub could never beat
# the real zmx (the same reason awake.sh takes AWAKE_DATE_BIN). Needs only
# bash + bats + awk.

bats_require_minimum_version 1.5.0

setup() {
  SUBJECT="$BATS_TEST_DIRNAME/../modules/terminal/scripts/zmx-rows.sh"
  STUB="$BATS_TEST_TMPDIR/zmx"

  # The desk the fixtures describe, shaped byte-for-byte like zmx 0.7.0:
  #   · unattached rows carry two spaces GLUED to the first key ("  name=…")
  #   · the attached row carries "→ " glued the same way
  #   · term.2 is an OLDER zmx row: no start_dir, a file:// cwd with a host
  #   · term.3 has a label value carrying "=" and one carrying a backslash
  #     escape, which must both survive byte-for-byte
  {
    printf '  name=scruff.haus.a\tpid=11\tclients=1\tcreated=100\tstart_dir=/Users/me/.cache/scruff/haus/a\tcmd=bash -lc...\tclient=claude\tlabel=a\tlwindow=201\tsince=110\tstate=working\n'
    printf '\342\206\222 name=term.1\tpid=22\tclients=1\tcreated=90\tstart_dir=/Users/me\twindow=333\n'
    printf '  name=term.2\tpid=33\tclients=0\tcreated=80\tcwd=file://Mac/Users/me/proj\n'
    printf '  name=term.3\tpid=44\tclients=1\tcreated=70\tstart_dir=/Users/me\tlabel=a=b\tnote=a\\nb\n'
  } >"$BATS_TEST_TMPDIR/ls"

  # `zmx get` in 0.7.0: labels alone, SPACE-separated, one line, no trailing
  # newline. `old` is the pre-0.7.0 era: tab-separated, keys space-padded.
  printf 'client=claude label=x lwindow=114151 state=working' >"$BATS_TEST_TMPDIR/get.term.9"
  printf ' window=42\tconvo=abc\n' >"$BATS_TEST_TMPDIR/get.old"

  cat >"$STUB" <<EOF
#!/usr/bin/env bash
case "\$1" in
  ls)  cat "$BATS_TEST_TMPDIR/ls" ;;
  get) cat "$BATS_TEST_TMPDIR/get.\$2" 2>/dev/null ;;
esac
EOF
  chmod +x "$STUB"
}

rows() { HAUS_ZMX_BIN="$STUB" "$SUBJECT" "$@"; }

@test "columns come back in the order asked, one TSV row per session" {
  run rows state,name
  [ "${lines[0]}" = "$(printf 'working\tscruff.haus.a')" ]
  [ "${#lines[@]}" -eq 4 ]
}

@test "the attached-row marker glued to the first key does not lose the row" {
  # The session you are sitting in is exactly the one a naive parse loses.
  run rows name,window name=term.1
  [ "$output" = "$(printf 'term.1\t333')" ]
}

@test "a missing key is an empty column, so the column count is stable" {
  run rows name,state,window name=term.2
  [ "$output" = "$(printf 'term.2\t\t')" ]
}

@test "dir: start_dir wins where it exists" {
  run rows dir name=scruff.haus.a
  [ "$output" = "/Users/me/.cache/scruff/haus/a" ]
}

@test "dir: an older row falls back to cwd and strips the file:// host" {
  run rows dir name=term.2
  [ "$output" = "/Users/me/proj" ]
}

@test "a value carrying = survives whole: the key ends at the FIRST =" {
  run rows label name=term.3
  [ "$output" = "a=b" ]
}

@test "ENVIRON, not -v: a backslash escape in a value passes byte-for-byte" {
  # -v rewrites \n into a newline; ENVIRON must not.
  run rows note name=term.3
  [ "$output" = 'a\nb' ]
  # And on the FILTER channel, where a -v rewrite would make the comparison
  # silently false — this is the arm a -v implementation actually fails.
  run rows name 'note=a\nb'
  [ "$output" = "term.3" ]
}

@test "filters are ANDed, and k= matches rows where the key is absent" {
  run rows name state=working client=claude
  [ "$output" = "scruff.haus.a" ]
  run rows name state= clients=1
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = 2 ]  # term.1, term.3
}

@test "no match answers empty with exit 0" {
  run rows name name=nosuch
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no zmx at all answers empty with exit 0 — the degrade direction" {
  run env HAUS_ZMX_BIN=/nonexistent-zmx "$SUBJECT" name
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a malformed call is a caller bug: exit 1, nothing printed" {
  run rows
  [ "$status" -eq 1 ]
  run rows name not-a-filter
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "--get reads 0.7.0's space-separated single line, missing keys empty" {
  # This is the shape that left both hand parses of `zmx get` answering
  # empty for every key: they split on tabs that stopped existing at 0.7.0.
  run rows --get term.9 lwindow,state,gwindow
  [ "$output" = "$(printf '114151\tworking\t')" ]
}

@test "--get still reads the older tab-separated, space-padded era" {
  run rows --get old window,convo
  [ "$output" = "$(printf '42\tabc')" ]
}

@test "--get of a session zmx does not know answers empty with exit 0" {
  run rows --get nosuch window
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

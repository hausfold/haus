#!/usr/bin/env bats
# Hermetic tests for the lane→window join in
# modules/terminal/scripts/raise-session.sh — the AeroSpace branch that answers
# "which window is this lane in?".
#
# Why a suite. The bug this closes was invisible for months and only ever fired
# on a busy desk. The join skips IMPOSTORS — plain shell windows born inside a
# lane's Ghostty instance, which wear that lane's forced title — by way of the
# `window=` labels launch.sh stamps, and that list was handed to awk through
# `-v c="$claimed"`, NEWLINE-separated. But `-v` is not a variable assignment,
# it is a piece of awk SOURCE: macOS's one-true-awk (`awk version 20200816`,
# /usr/bin/awk, the only awk a GUI-spawned script finds) refuses a literal
# newline inside a string literal and dies with `awk: newline in string`, exit
# 2, nothing on stdout. With zero or one plain window labelled the list had no
# newline and everything worked; the SECOND one broke the join for every lane at
# once, silently. Downstream, `scruff focus` read the empty answer as "no window
# holds this session" and opened a SECOND window beside the one it was asked to
# raise — which is how it reached a person: clicking a lane's trill banner
# spawned a new lane window instead of going to the open one. ⌘F's ⏎ and the
# bar's agent rows did their own version of the same. Measured 2026-08-26.
#
# The subject is a join over two text listings, so it needs no Mac, no window
# and no tiler: `zmx` and `aerospace` are stubbed. `awk` is stubbed too, and
# that stub is the point of the suite — it reproduces one-true-awk's rule on any
# platform, so the case that matters FAILS on Linux CI, where the runner's
# mawk/gawk would happily accept the newline and pass the old code.
#
# ⚠️ The subject is extracted by `sed`, because raise-session.sh cannot be
# sourced — it is a top-to-bottom script that raises a window. So the two lines
# must keep a `^    claimed=` opening and an awk body whose last line matches
# `^        \$2 == "Ghostty"`. If either moves the eval yields nothing and every
# case fails with an empty result, which is the loud failure and the reason this
# is acceptable.

bats_require_minimum_version 1.5.0

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB"

  # The real awk, resolved BEFORE the stub shadows it and exported, so the stub
  # can delegate without recursing.
  REAL_AWK="$(command -v awk)"
  export REAL_AWK

  # one-true-awk's rule, on any platform: a `-v` assignment whose value carries
  # a literal newline is a parse error, not an assignment. Everything else is
  # handed to the platform's real awk unchanged. Quoted heredoc — the stub is
  # bash source and nothing in it is for this shell to expand.
  cat >"$STUB/awk" <<'AWKSTUB'
#!/usr/bin/env bash
LF=$'\n'
prev=""
for arg in "$@"; do
  if [ "$prev" = "-v" ]; then
    case "$arg" in
      *"$LF"*)
        printf 'awk: newline in string %s... at source line 1\n' "${arg%%"$LF"*}" >&2
        exit 2
        ;;
    esac
  fi
  prev="$arg"
done
exec "$REAL_AWK" "$@"
AWKSTUB
  chmod +x "$STUB/awk"
}

# Load the join alone, against a given desk. WINDOWS is aerospace's listing,
# SESSIONS is zmx's — both verbatim in the format the real tools emit, because a
# stub that paraphrases its subject is how a suite starts passing for the wrong
# reason (zmx's rows are TAB-separated and its first field carries a leading
# marker, which is exactly why the real `sed` has to match `^window=` per field).
join() { # SESS WINDOWS SESSIONS
  set -u
  local sess="$1"
  printf '%s' "$2" >"$BATS_TEST_TMPDIR/windows"
  printf '%s' "$3" >"$BATS_TEST_TMPDIR/sessions"
  cat >"$STUB/aerospace" <<EOF
#!/usr/bin/env bash
cat "$BATS_TEST_TMPDIR/windows"
EOF
  cat >"$STUB/zmx" <<EOF
#!/usr/bin/env bash
cat "$BATS_TEST_TMPDIR/sessions"
EOF
  chmod +x "$STUB/aerospace" "$STUB/zmx"
  PATH="$STUB:$PATH" eval "$(sed -n '/^    claimed=/,/^        \$2 == "Ghostty"/p' \
    "$BATS_TEST_DIRNAME/../modules/terminal/scripts/raise-session.sh")"
  printf '%s\n' "$win"
}

# One lane's Ghostty instance holding three windows, all wearing its forced
# title: the lane itself (58716) and two plain shells that claimed `term.1` and
# `term.2` and were labelled by launch.sh. This is the real desk the bug was
# found on.
CROWDED_WINDOWS='58703|Ghostty|holt.haus.trill-skill-install
58831|Ghostty|holt.workshop.progress-banner-wireup
58836|Ghostty|holt.workshop.progress-banner-wireup
58716|Ghostty|holt.workshop.progress-banner-wireup
44630|Things|hausfold'

crowded_sessions() { # how many plain windows carry a label
  printf '  name=holt.workshop.progress-banner-wireup\tpid=58618\tclients=1\n'
  [ "$1" -ge 1 ] && printf '  name=term.1\tpid=19011\tclients=1\tstart_dir=/Users/me\twindow=58831\n'
  [ "$1" -ge 2 ] && printf '→ name=term.2\tpid=20028\tclients=1\tstart_dir=/Users/me\twindow=58836\n'
  return 0
}

@test "two labelled plain windows: the lane still resolves, impostors skipped" {
  run join holt.workshop.progress-banner-wireup "$CROWDED_WINDOWS" "$(crowded_sessions 2)"
  [ "$output" = 58716 ]
}

@test "one labelled plain window: the remaining impostor is skipped" {
  run join holt.workshop.progress-banner-wireup "$CROWDED_WINDOWS" "$(crowded_sessions 1)"
  # 58836 is unlabelled here, so it is indistinguishable from a lane and wins on
  # listing order. That is the join's known ceiling, not a regression — what
  # matters is that awk RAN and the labelled impostor was skipped.
  [ "$output" = 58836 ]
}

@test "no labelled plain windows: an empty claim list is not a parse error" {
  run join holt.workshop.progress-banner-wireup "$CROWDED_WINDOWS" "$(crowded_sessions 0)"
  [ "$output" = 58831 ]
}

@test "a lane with no window at all resolves to nothing" {
  run join holt.trill.gone "$CROWDED_WINDOWS" "$(crowded_sessions 2)"
  [ -z "$output" ]
}

@test "the title must match a Ghostty window, not any app's" {
  run join hausfold "$CROWDED_WINDOWS" "$(crowded_sessions 2)"
  [ -z "$output" ]
}

@test "the awk stub reproduces one-true-awk: a newlined -v is a parse error" {
  # Guards the guard. If this passes trivially the suite above proves nothing,
  # because every case would run on an awk that tolerates the old code.
  run env PATH="$STUB:$PATH" awk -v c="$(printf '58831\n58836')" 'BEGIN { print "ran" }'
  [ "$status" -eq 2 ]
  [[ "$output" == *"newline in string"* ]]
}

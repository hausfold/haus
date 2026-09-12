#!/usr/bin/env bats
# Hermetic tests for modules/bar/sketchybar/plugins/page.sh — the fraction on
# the page pill, and the three states it draws.
#
# ── what is actually hard here ───────────────────────────────────────────────
# The pill counts PLACES, and the rule is one line — a place counts when there
# is a window on it — but the two sides of it come from one `aerospace` call
# that treats them differently. A page (`T/<repo>`) is never persistent, so it
# is listed only while it is live; the base (`T`) always is, so it is listed
# whether or not anything is on it. `--empty no` is the whole of what makes
# those comparable, and dropping it is invisible on a machine with a busy `T`:
# every number is right until the day you page every window away.
#
# Each rule below fails silently on a real bar — a pill drawing a plausible
# number nobody can check against anything, or a pill that is simply not there:
#
#   * an empty base must not be counted, or a lone lane reads `1/2` and the
#     workspace you have nothing on claims a place.
#   * an occupied base MUST be, which is what this change was: `perch 2/3` on a
#     `T` holding four windows was counting three of the four places there are.
#   * a workspace whose only live place is itself draws NOTHING, and a base with
#     a page under it always draws — including when the base is empty, which is
#     exactly when the pages are invisible and the pill is the only notice that
#     they exist. That state is why the pill has a middle state at all, and the
#     `> 0` guarding it is on the PAGE count for that reason and not on the
#     total.
#   * the base prefix carries its slash, so `TT/x` is not a page of `T`.
#
# ⚠️ The subject is COPIED with its PATH prelude rewritten, the anchored sed
# test/new-window-title.bats documents: the plugin puts `/opt/homebrew/bin`
# ahead of anything a test can prepend, which on a real Mac is the machine's own
# `aerospace` answering with the workspaces you happen to have open. The grep
# after it is the guard — a prelude that stops starting the way it does turns
# every case below into a reading of this desktop.
#
# On macOS the subject runs under `/bin/bash`, which is 3.2 — the one shell that
# scans a `$( )` for its closing paren BEFORE parsing the shell inside it, so an
# unbalanced one from a `case` pattern (`*/*)`) written in there takes the whole
# file down at load with `unexpected EOF`. `bash -n` under any bash 4+ passes it
# happily. These cases run the file, so they are the local guard against it.

bats_require_minimum_version 1.5.0

SUBJECT() { printf '%s' "$BATS_TEST_DIRNAME/../modules/bar/sketchybar/plugins/page.sh"; }

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  STUB="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$HOME/.config/sketchybar" "$STUB"

  # The two files the plugin sources. colors.sh carries only the four names it
  # reads; bar.sh points $SB at a recorder, exactly as the generated router
  # points it at one of the two bars.
  cat >"$HOME/.config/sketchybar/colors.sh" <<'EOF'
export TEXT=0xff000001
export SUBTEXT0=0xff000002
export TEAL=0xff000003
export OVERLAY1=0xff000004
EOF
  printf 'SB=%s/sb\n' "$STUB" >"$HOME/.config/sketchybar/bar.sh"

  cat >"$STUB/sb" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*"
EOF
  chmod +x "$STUB/sb"

  # aerospace, as the two questions the plugin asks it: which workspace is
  # focused, and which ones have a window on them. $FOCUSED and $NONEMPTY are
  # the fixture; the call itself is logged so a case can assert that `--empty
  # no` was the question — the flag being the whole difference between counting
  # places and counting workspaces.
  cat >"$STUB/aerospace" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$BATS_TEST_TMPDIR/aerospace.log"
case "\$*" in
  *--focused*) printf '%s\n' "\$FOCUSED" ;;
  *list-workspaces*) printf '%s\n' \$NONEMPTY ;;
esac
EOF
  chmod +x "$STUB/aerospace"

  COPY="$BATS_TEST_TMPDIR/page.sh"
  sed 's|^export PATH=.*|export PATH="$PATH"|' "$(SUBJECT)" >"$COPY"
  grep -q '^export PATH="\$PATH"$' "$COPY"
  chmod +x "$COPY"
}

# draw FOCUSED NONEMPTY… → the label the pill set, or `off`.
draw() {
  local focused="$1"
  shift
  local out
  out="$(FOCUSED="$focused" NONEMPTY="$*" PATH="$STUB:$PATH" "$COPY")"
  case "$out" in
    *"drawing=off"*) printf 'off\n' ;;
    *) printf '%s\n' "${out#*label=}" | sed 's/ label.color=.*//' ;;
  esac
}

# ── the base counts, when there is something on it ───────────────────────────

@test "on a page: the base is the first place counted" {
  # The reported bug, in the shape it was reported in: four windows on `T` and
  # three lanes paged off it read `perch 2/3` — the base was not one of the
  # places, so both halves of the fraction were short by one.
  run -0 draw T/perch 1 B N R T T/haus T/perch T/workshop
  [ "$output" = "perch  3/4" ]
}

@test "on a page: the count asks for non-empty workspaces" {
  draw T/perch T T/perch >/dev/null
  grep -q -- '--empty no' "$BATS_TEST_TMPDIR/aerospace.log"
}

@test "on the only page, with the base occupied: 2/2" {
  run -0 draw T/perch T T/perch
  [ "$output" = "perch  2/2" ]
}

@test "on the only page, with the base emptied: the name alone" {
  # One place is not a fraction. `T` is listed by a plain `--monitor all`
  # whether or not anything is on it, so this is the case a missing
  # `--empty no` turns into `perch  1/2`.
  run -0 draw T/perch 1 B N R T/perch
  [ "$output" = "perch" ]
}

@test "a focused page counts itself before it holds a window" {
  # Switch to a page and it is live-but-empty until something lands on it —
  # the one empty place that has to count, or the pill loses its own index.
  run -0 draw T/new T T/haus
  [ "$output" = "new  3/3" ]
}

@test "the base prefix carries its slash" {
  # `T` must not match `TT/x`: a base whose name is a prefix of another base is
  # the one way the count can silently inflate.
  run -0 draw T/haus T TT/x T/haus
  [ "$output" = "haus  2/2" ]
}

@test "pages of another base are counted for that base" {
  run -0 draw R/site R R/site R/docs T T/haus
  [ "$output" = "site  2/3" ]
}

# ── the middle state, and the hidden one ─────────────────────────────────────

@test "on the base with a page under it: the count alone" {
  run -0 draw T T T/haus
  [ "$output" = "2" ]
}

@test "on an emptied base the count reads the same from either side" {
  # `3` standing on an emptied `T`, then `2/3` once you are on one of its
  # pages. The base is not appended to the set just because it is focused,
  # which is what keeps those two numbers the same number.
  run -0 draw T T/haus T/perch T/workshop
  [ "$output" = "3" ]
  run -0 draw T/perch T/haus T/perch T/workshop
  [ "$output" = "perch  2/3" ]
}

@test "an emptied base with one page still draws: it is the only notice" {
  # The middle state exists for exactly this — every window paged away, so
  # nothing else on screen says the page is there. Guarding it on the TOTAL
  # rather than the page count would hide it here, since the total is 1.
  run -0 draw T T/haus
  [ "$output" = "1" ]
}

@test "on the base with no page under it: nothing at all" {
  run -0 draw T 1 B N R T
  [ "$output" = "off" ]
}

@test "an empty base with no page under it: nothing at all" {
  run -0 draw T 1 B N R
  [ "$output" = "off" ]
}

@test "no aerospace, no pill" {
  run -0 draw "" ""
  [ "$output" = "off" ]
}

#!/usr/bin/env bats
# THANKS.md's *Standing on* list, diffed against the tree that is supposed to
# use each project.
#
# What it is FOR. A credit list is the one document in this repo with no
# consumer: nothing imports it, nothing renders it, no build fails when it is
# wrong. So it rots in the one direction that embarrasses us — thanking a
# project we deleted. That is not hypothetical. The first draft of THANKS.md
# credited zellij for holding your sessions, three weeks after
# `modules/moved.nix` recorded it gone, in the same sentence as the zmx that
# replaced it. Nothing would ever have caught that except a reader who knew.
#
# The check is deliberately dumb. Every project named in *Standing on* must
# have a row in the table below, and that row's token must still appear where
# the row says. It catches the two failures that matter — a credit outliving
# its dependency, and a credit added with nothing tying it to the code — and it
# makes no attempt to judge whether the SENTENCE about a project is still true.
# That half is a reader's job, and the file is short enough to reread.
#
# Adding a credit means adding a row. That is the point: the row is the evidence
# the project is really used, written down at the moment you know it.

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  THANKS="$ROOT/THANKS.md"
  TABLE="$BATS_TEST_DIRNAME/thanks-drift.tsv"
}

# Every markdown link text under "## Standing on", one per line.
credited() {
  awk '/^## Standing on/{on = 1} on' "$THANKS" |
    grep -o '\[[^][]*\]([^()]*)' |
    sed 's/^\[//; s/\](.*$//' |
    sort -u
}

rows() { grep -v '^#' "$TABLE" | grep -v '^$'; }

@test "THANKS.md exists and still has a Standing on section" {
  [ -f "$THANKS" ]
  grep -q '^## Standing on' "$THANKS"
  [ "$(credited | wc -l)" -gt 10 ]
}

@test "every project credited in Standing on has a row in the table" {
  local missing=()
  while IFS= read -r name; do
    rows | cut -f1 | grep -qxF "$name" || missing+=("$name")
  done < <(credited)
  if [ ${#missing[@]} -gt 0 ]; then
    printf 'credited with no row in %s:\n' "$TABLE" >&2
    printf '  %s\n' "${missing[@]}" >&2
    printf 'Add a row naming where that project is still used, or drop the credit.\n' >&2
    return 1
  fi
}

@test "every row in the table still points at something in the tree" {
  local gone=()
  while IFS=$'\t' read -r name where token; do
    [ "$where" = "-" ] && continue
    if [ -d "$ROOT/$where" ]; then
      grep -rqi -- "$token" "$ROOT/$where" || gone+=("$name ($token not in $where/)")
    else
      grep -qi -- "$token" "$ROOT/$where" || gone+=("$name ($token not in $where)")
    fi
  done < <(rows)
  if [ ${#gone[@]} -gt 0 ]; then
    printf 'THANKS.md credits projects the tree no longer uses:\n' >&2
    printf '  %s\n' "${gone[@]}" >&2
    printf 'Drop the credit, or fix the row if the project just moved.\n' >&2
    return 1
  fi
}

@test "no row is stale — everything in the table is still credited" {
  local orphan=()
  while IFS=$'\t' read -r name where token; do
    credited | grep -qxF "$name" || orphan+=("$name")
  done < <(rows)
  if [ ${#orphan[@]} -gt 0 ]; then
    printf 'rows in %s naming projects THANKS.md no longer credits:\n' "$TABLE" >&2
    printf '  %s\n' "${orphan[@]}" >&2
    return 1
  fi
}

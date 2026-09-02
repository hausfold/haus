#!/usr/bin/env bats
# modules/launcher/commands/lib/menu-commit.sh — the ONE parse of a pounce
# stdin-menu answer, over fixture commit strings shaped exactly like pounce's
# (State.swift, buildCommit's .plain case: "<action>\t<raw-row>", free text in
# the same shape, multi-line under ⇧↵).
#
# The bug class this file pins shut is silent by construction: a `case` on
# field 1 of the ANSWER compares every row against the literal "enter", falls
# through the `*)` arm, and the menu does nothing at all — no error, no log.
# Seven scripts each carried a private copy of the fix before the helper; the
# last test holds them to the shared one, so an eighth private parse cannot
# land quietly.

bats_require_minimum_version 1.5.0

setup() {
  LIB="$BATS_TEST_DIRNAME/../modules/launcher/commands/lib/menu-commit.sh"
  [ -f "$LIB" ] || {
    echo "subject missing: $LIB" >&2
    return 1
  }
  # shellcheck disable=SC1090
  . "$LIB"
}

@test "row commit: the verb comes off and the row keeps its own field numbers" {
  # A five-field row plus a hidden sixth — the lanes/pages/drafts shape.
  menu_commit "$(printf 'enter\tTitle\tsubtitle\ticon\tOpen\tGroup\thidden6')"
  [ "$MENU_ACTION" = "enter" ]
  [ "$(menu_field "$MENU_ROW" 1)" = "Title" ]
  [ "$(menu_field "$MENU_ROW" 6)" = "hidden6" ]
}

@test "row commit: a case on the row's first field no longer sees 'enter'" {
  # The regression itself: before the helper, matching on the ANSWER's first
  # field compared "enter" against every row name.
  menu_commit "$(printf 'enter\tSwitch to light mode\tdesc\tsun.max.fill')"
  [ "$(menu_field "$MENU_ROW" 1)" != "enter" ]
  [ "$(menu_field "$MENU_ROW" 1)" = "Switch to light mode" ]
}

@test "modifier commits carry their own verb" {
  menu_commit "$(printf 'cmd\trow\tsub')"
  [ "$MENU_ACTION" = "cmd" ]
  menu_commit "$(printf 'opt\trow\tsub')"
  [ "$MENU_ACTION" = "opt" ]
  menu_commit "$(printf 'ctrl\trow\tsub')"
  [ "$MENU_ACTION" = "ctrl" ]
}

@test "free text: the typed words arrive whole" {
  menu_commit "$(printf 'enter\tfix the bar pill flicker')"
  [ "$MENU_ACTION" = "enter" ]
  [ "$MENU_ROW" = "fix the bar pill flicker" ]
}

@test "multi-line free text: the verb is read from line one only" {
  # ⇧↵ makes the text span lines, and a later line may hold a tab of its own —
  # the action must come from the first line, and the text must survive
  # verbatim, newlines and tabs alike.
  local commit expected
  commit="$(printf 'ctrl\t- one\n- two\twith a tab\n- three')"
  menu_commit "$commit"
  [ "$MENU_ACTION" = "ctrl" ]
  expected="$(printf -- '- one\n- two\twith a tab\n- three')"
  [ "$MENU_ROW" = "$expected" ]
}

@test "a dismissal is empty on both sides" {
  menu_commit ""
  [ -z "$MENU_ACTION" ]
  [ -z "$MENU_ROW" ]
}

@test "a first line with no tab is all row, no action" {
  # Nothing pounce sends looks like this, but the wrong reading — the whole
  # string as MENU_ACTION — would turn garbage into a verb.
  menu_commit "just some text"
  [ -z "$MENU_ACTION" ]
  [ "$MENU_ROW" = "just some text" ]
}

@test "the globals are overwritten by the next commit" {
  menu_commit "$(printf 'cmd\tfirst row')"
  menu_commit "$(printf 'enter\tsecond row')"
  [ "$MENU_ACTION" = "enter" ]
  [ "$MENU_ROW" = "second row" ]
}

@test "menu_field on a tab-free row answers field 1 whole and nothing past it" {
  # The free-text/row-pick discriminator every consumer leans on: typed text
  # has field 1 and NOTHING else. Raw cut would hand the whole line back for
  # any field number, so "T/newthing" typed at the Pages picker would arrive
  # wearing the hidden page field's number — see menu_field's own comment.
  [ "$(menu_field "typed words" 1)" = "typed words" ]
  [ -z "$(menu_field "typed words" 2)" ]
  [ -z "$(menu_field "typed words" 6)" ]
}

@test "every stdin-menu consumer parses through the helper" {
  # The seven scripts the helper replaced private parses in. A revert to a
  # local strip, or a new consumer with its own, should have to argue with
  # this list.
  local f
  for f in \
    "$BATS_TEST_DIRNAME/../modules/launcher/commands/settings.sh" \
    "$BATS_TEST_DIRNAME/../modules/launcher/commands/add-app.sh" \
    "$BATS_TEST_DIRNAME/../modules/launcher/commands/spawn-agent.sh" \
    "$BATS_TEST_DIRNAME/../modules/launcher/commands/lanes.sh" \
    "$BATS_TEST_DIRNAME/../modules/launcher/commands/links.sh" \
    "$BATS_TEST_DIRNAME/../modules/launcher/commands/pages.sh" \
    "$BATS_TEST_DIRNAME/../modules/bar/sketchybar/plugins/haus_menu.sh"; do
    grep -q 'menu-commit\.sh' "$f" || {
      echo "$f no longer sources menu-commit.sh" >&2
      return 1
    }
    grep -q '^\s*menu_commit ' "$f" || {
      echo "$f no longer calls menu_commit" >&2
      return 1
    }
  done
}

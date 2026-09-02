#!/bin/bash
# The ONE parse of a pounce stdin-menu answer. Sourced, never run — it lives
# under lib/ so pounce's top-level command discovery cannot offer it as a row.
#
# A generic stdin picker's commit is "<action>\t<raw-row>", never the raw row
# alone (pounce's State.swift, buildCommit's .plain case — free text commits
# in the same shape). <action> is enter/cmd/opt/ctrl, whichever key committed.
# The failure mode this file exists to end is silent: a `case` on field 1 of
# the ANSWER compares every row against the literal "enter", falls through the
# `*)` arm, and the menu does nothing at all — no error, no log. Seven scripts
# each carried their own copy of that fact before this one.
#
# menu_commit <answer> — split the verb off, into two globals:
#
#   MENU_ACTION  the committing key ("enter", "cmd", "opt", "ctrl"), read from
#                the FIRST line only: a ⇧↵ free-text answer spans lines, and
#                only line one carries the verb. A later line's tab must never
#                move it.
#   MENU_ROW     everything after the first tab — the raw row for a row pick,
#                the typed text for a free-text commit — newlines and tabs in
#                a multi-line answer untouched. Index it with the SAME field
#                numbers the script printed the row with; the whole
#                "field 6 arrives as the 7th" comment class is what this
#                helper deletes.
#
#   An answer whose first line has no tab (a dismissal is the empty string;
#   nothing pounce sends looks otherwise) is all row and no action, so an
#   emptiness check on either global keeps meaning what it did.
#
#   Globals, deliberately: every caller runs under macOS's /bin/bash 3.2,
#   where two out-parameters cost either a fork or a nameref 3.2 doesn't have.
#   They are OVERWRITTEN by the next menu_commit — capture what you need
#   before opening another picker.
#
# menu_field <row> <n> — field <n> of a row's FIRST line, tab-cut. Hand it
#   $MENU_ROW, not the raw answer. On a free-text MENU_ROW (tab-free) field 1
#   is the text and every later field is EMPTY — which is what lets a caller
#   test a hidden payload field for emptiness to tell a row pick from typed
#   text. cut alone would break that twice over: it passes a delimiter-less
#   line through WHOLE whatever -f asks for, and it does so per line, so a ⇧↵
#   multi-line answer would hand its first line back wearing a hidden field's
#   number. Taking line one and appending a tab closes both — rows are
#   single-line by pounce's own protocol, and the trailing empty field is one
#   nothing reads. A multi-line free text's BODY is $MENU_ROW itself, never a
#   menu_field read.
#
# A --dial step's answer grows a MIDDLE field ("<action>\t<name=value>\t<text>")
# which MENU_ROW then still carries in front of the text. Stripping it is the
# dial-passing caller's business, not this file's: only that caller knows
# whether a dial was offered at all, and believing an unoffered one eats the
# first line of somebody's task. spawn-agent.sh's dial_agent/dial_payload are
# the one reader, and test/spawn-agent.bats holds them to it.

# The two globals ARE the API — they are only ever read by the script that
# sourced this file, which shellcheck cannot see from here.
# shellcheck disable=SC2034
menu_commit() {
  local answer="${1-}"
  case "${answer%%$'\n'*}" in
    *$'\t'*)
      MENU_ACTION="${answer%%$'\t'*}"
      MENU_ROW="${answer#*$'\t'}"
      ;;
    *)
      MENU_ACTION=""
      MENU_ROW="$answer"
      ;;
  esac
}

menu_field() { printf '%s\t' "${1%%$'\n'*}" | cut -f"$2"; }

#!/usr/bin/env bats
# The mail watcher's decisions — modules/notifications/mail-announce.py.
#
# The IMAP half is somebody else's tested code (goimapnotify holds the IDLE
# connection; imaplib speaks the protocol). What is OURS is five small
# functions, and each of them fails in a way nobody notices until it is
# embarrassing:
#
#   * `to_announce` is the flood guard. A mailbox this Mac has never watched
#     must announce NOTHING — goimapnotify runs the hook once at startup and
#     launchd starts the agent at every login, so the wrong answer here is a
#     card per unread message, every morning. The same for a mailbox the server
#     has renumbered: UIDs are only monotonic inside one UIDVALIDITY, and a
#     watermark compared across a change replays the whole mailbox at once.
#   * `watermark_after` is that same fact one fire later, and it fails the
#     OTHER way: a renumbered mailbox that keeps its old, higher watermark puts
#     every message the server then issues below the line. No flood, no error,
#     no cards ever again.
#   * `decoded` is the difference between a subject and `=?UTF-8?B?…?=`. Most
#     non-ASCII mail arrives encoded, so this is not an edge case; it is most
#     of the mail anyone outside an English-speaking inbox gets.
#   * `card` decides the fold. trill folds everything on one `--thread` into a
#     single card with a count, so the thread has to be the MAILBOX — per
#     sender, five people at once is five cards and the fold never fires.
#   * `slug` turns a mailbox name into the filename its watermark lives in, and
#     Gmail's are `[Gmail]/All Mail`. A slash there writes the watermark into a
#     directory that does not exist, which reads as "never watched" forever —
#     the flood guard, disarmed by a filename.
#
# Hermetic and hostless: none of the five opens a socket, which is why they are
# the five that were split out. test/mail-imap.bats is the other side of that
# line: the same subject, driven end to end against a real one.

bats_require_minimum_version 1.5.0

setup() {
  SUBJECT="$BATS_TEST_DIRNAME/../modules/notifications/mail-announce.py"
}

# The subject is a hook script rather than an importable module — it lives at a
# store path with a name python cannot import — so it is loaded by path, the
# same way a person debugging it would.
py() {
  {
    echo 'import importlib.util'
    echo "spec = importlib.util.spec_from_file_location('ann', '$SUBJECT')"
    echo 'ann = importlib.util.module_from_spec(spec)'
    echo 'spec.loader.exec_module(ann)'
    cat
  } | python3 -
}

# ---- to_announce: the flood guard ------------------------------------------

@test "a mailbox nobody has watched announces nothing" {
  run py <<'PY'
print(ann.to_announce([41, 42, 43], None, "9", None))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "a renumbered mailbox announces nothing, whatever the watermark says" {
  run py <<'PY'
print(ann.to_announce([41, 42, 43], 40, "10", "9"))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "only the unseen mail above the watermark" {
  run py <<'PY'
print(ann.to_announce([40, 41, 42], 40, "9", "9"))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "[41, 42]" ]
}

@test "nothing unseen is nothing to draw" {
  run py <<'PY'
print(ann.to_announce([], 40, "9", "9"))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

# ---- watermark_after: where the line goes next -----------------------------

@test "a renumbered mailbox takes the new top, never the old number" {
  # The bug this pins: keeping 49 across a renumber puts every message the
  # server then issues BELOW the line, so the mailbox goes quiet for good.
  run py <<'PY'
print(ann.watermark_after(11, 49, "999", "111"))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "11" ]
}

@test "an unwatched mailbox takes the current top" {
  run py <<'PY'
print(ann.watermark_after(42, None, "9", None))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "42" ]
}

@test "the line never moves backwards on a mailbox that is still itself" {
  # `top` is 0 for an empty mailbox and for a fetch that came back without a
  # UID; taking it at face value would replay everything still in there.
  run py <<'PY'
print(ann.watermark_after(0, 49, "9", "9"))
print(ann.watermark_after(50, 49, "9", "9"))
PY
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "49" ]
  [ "${lines[1]}" = "50" ]
}

# ---- decoded: what the card actually reads ----------------------------------

@test "an encoded subject reaches the card as text" {
  run py <<'PY'
print(ann.decoded("=?UTF-8?B?SGVsbG8gd29ybGQ=?="))
print(ann.decoded("=?iso-8859-1?q?Caf=E9_meeting?="))
PY
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Hello world" ]
  [ "${lines[1]}" = "Café meeting" ]
}

@test "a folded header becomes one line" {
  run py <<'PY'
print(repr(ann.decoded("re:  the\r\n  quarterly thing")))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "'re: the quarterly thing'" ]
}

@test "a header python cannot decode still draws, as itself" {
  # A card missing is worse than a card with an ugly title: the user wanted to
  # know that mail arrived.
  run py <<'PY'
print(ann.decoded("=?nonsense-charset?B?%%%?="))
PY
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "no header at all is empty rather than an exception" {
  run py <<'PY'
print(repr(ann.decoded(None)))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "''" ]
}

# ---- sender: the title ------------------------------------------------------

@test "the display name wins, decoded, and the bare address stands in" {
  run py <<'PY'
print(ann.sender('"Foo Bar" <foo@bar.com>'))
print(ann.sender('foo@bar.com'))
print(ann.sender('=?UTF-8?B?SsO2cmc=?= <j@x.de>'))
print(ann.sender(None))
PY
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "Foo Bar" ]
  [ "${lines[1]}" = "foo@bar.com" ]
  [ "${lines[2]}" = "Jörg" ]
  [ "${lines[3]}" = "Unknown sender" ]
}

# ---- card: the fold, and the pill ------------------------------------------

@test "the thread is the mailbox, so a burst folds into one card" {
  run py <<'PY'
first = ann.card('"A" <a@b.c>', "one", "INBOX")
second = ann.card('"B" <b@b.c>', "two", "INBOX")
print(first[2])
print(first[2] == second[2])
PY
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "haus.mail.INBOX" ]
  [ "${lines[1]}" = "True" ]
}

@test "Gmail's thread id becomes an Open pill, in hex, on this account" {
  run py <<'PY'
print(ann.card('a@b.c', "hi", "INBOX", 0x1234abcd, "you@gmail.com")[3])
PY
  [ "$status" -eq 0 ]
  [ "$output" = "Open=https://mail.google.com/mail/u/you@gmail.com/#all/1234abcd" ]
}

@test "no thread id means no pill rather than a link to the wrong thing" {
  run py <<'PY'
print(ann.card('a@b.c', "hi", "INBOX", None, "you@gmail.com")[3])
PY
  [ "$status" -eq 0 ]
  [ "$output" = "None" ]
}

@test "a message with no subject still says something" {
  run py <<'PY'
print(ann.card('a@b.c', None, "INBOX")[1])
PY
  [ "$status" -eq 0 ]
  [ "$output" = "(no subject)" ]
}

# ---- slug: where the watermark lives ---------------------------------------

@test "a Gmail mailbox name is a filename, with no path left in it" {
  run py <<'PY'
name = ann.slug("[Gmail]/All Mail")
print(name)
print("/" in name)
PY
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "_Gmail__All_Mail" ]
  [ "${lines[1]}" = "False" ]
}

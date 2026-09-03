#!/usr/bin/env bats
# The mail watcher's other half — the conversation itself.
#
# test/mail-announce.bats pins the four decisions in isolation. This one drives
# the whole of modules/notifications/mail-announce.py against a real socket, a
# real TLS handshake and a real imaplib, because everything between those
# decisions and the card is a response SHAPE nothing else exercises: EXAMINE's
# UIDVALIDITY, the untagged `SEARCH` list, `FETCH *`'s sequence-numbered UID,
# and a header fetch whose literal arrives with X-GM-THRID glued to the front.
# Get one of those wrong and there is no error anywhere — just a Mac that
# stopped mentioning mail.
#
# The regression it was written for is the last case. A mailbox the server
# RENUMBERS (UIDVALIDITY moves, UIDs start again from 1) used to keep its old
# watermark, so every message after it was below the line: silent, permanently,
# on a mailbox that looked perfectly healthy from every other angle.
#
# Hostless: ./fake-imap.py is the server, the certificate is generated per run,
# and `haus-notify` is a recorder. Needs bash + bats + python3 + openssl.

bats_require_minimum_version 1.5.0

setup_file() {
  # One certificate for every case. Both SANs, so the client can use the
  # ADDRESS and DNS never enters the test: `localhost` resolving to ::1 first
  # on some runner is exactly the kind of failure that reads as a bug in the
  # subject.
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
    -keyout "$BATS_FILE_TMPDIR/key.pem" -out "$BATS_FILE_TMPDIR/cert.pem" \
    -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" \
    >/dev/null 2>&1
}

setup() {
  SUBJECT="$BATS_TEST_DIRNAME/../modules/notifications/mail-announce.py"
  FAKE="$BATS_TEST_DIRNAME/fake-imap.py"
  STATE="$BATS_TEST_TMPDIR/state"
  CARDS="$BATS_TEST_TMPDIR/cards"
  NOTIFY="$BATS_TEST_TMPDIR/notify"
  mkdir -p "$STATE"
  : >"$CARDS"
  cat >"$NOTIFY" <<'RECORDER'
#!/bin/sh
printf '%s\n' "$*" >>"$NOTIFY_LOG"
RECORDER
  chmod +x "$NOTIFY"
}

teardown() {
  [ -n "${SERVER_PID:-}" ] && kill "$SERVER_PID" 2>/dev/null
  return 0
}

# start_server <connections> <uidvalidity> <message>...
#   message: uid:unseen:thrid:from:subject
start_server() {
  local connections=$1 uidvalidity=$2
  shift 2
  local ready="$BATS_TEST_TMPDIR/ready.$RANDOM"
  local messages=()
  local spec
  for spec in "$@"; do messages+=(--message "$spec"); done
  python3 "$FAKE" --cert "$BATS_FILE_TMPDIR/cert.pem" --key "$BATS_FILE_TMPDIR/key.pem" \
    --uidvalidity "$uidvalidity" --serve "$connections" --ready-file "$ready" \
    "${messages[@]}" &
  SERVER_PID=$!
  local waited=0
  while [ ! -s "$ready" ]; do
    sleep 0.05
    waited=$((waited + 1))
    [ "$waited" -gt 200 ] && return 1
  done
  PORT="$(cat "$ready")"
}

announce() {
  NOTIFY_LOG="$CARDS" SSL_CERT_FILE="$BATS_FILE_TMPDIR/cert.pem" \
    python3 "$SUBJECT" --mailbox INBOX --host 127.0.0.1 --port "$PORT" \
    --address you@gmail.com --password-command "echo hunter2" \
    --notify "$NOTIFY" --state-dir "$STATE" "$@"
}

cards() { cat "$CARDS"; }
watermark() { python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['uid'])" "$STATE/uid-INBOX.json"; }

@test "a mailbox this Mac has never watched records the top and draws nothing" {
  start_server 1 111 "41:1:1000:a@b.c:one" "42:1:2000:b@b.c:two"
  run announce
  [ "$status" -eq 0 ]
  [ -z "$(cards)" ]
  [ "$(watermark)" = "42" ]
}

@test "one new unseen message draws one card, decoded, with the Gmail pill" {
  printf '{"uidvalidity": "111", "uid": 42}' >"$STATE/uid-INBOX.json"
  start_server 1 111 "41:0:1:a@b.c:read already" "42:0:1:b@b.c:also read" \
    "43:1:305419896:=?UTF-8?B?SsO2cmc=?= <j@x.de>:=?UTF-8?B?Q2Fmw6kgbWVldGluZw==?="
  run announce
  [ "$status" -eq 0 ]
  [ "$(cards)" = "--title Jörg --body Café meeting --source haus.mail --kind chat --thread haus.mail.INBOX --action Open=https://mail.google.com/mail/u/you@gmail.com/#all/12345678" ]
  [ "$(watermark)" = "43" ]
}

@test "mail read on another device draws nothing, and the line still moves" {
  # The phone case, and the reason the search asks for UNSEEN as well as for
  # everything above the watermark. Without it, opening the laptop announces
  # what you read on the train.
  printf '{"uidvalidity": "111", "uid": 42}' >"$STATE/uid-INBOX.json"
  start_server 1 111 "43:0:1:a@b.c:read on the phone"
  run announce
  [ "$status" -eq 0 ]
  [ -z "$(cards)" ]
  [ "$(watermark)" = "43" ]
}

@test "a burst past the cap is one card saying how many" {
  printf '{"uidvalidity": "111", "uid": 43}' >"$STATE/uid-INBOX.json"
  start_server 1 111 "44:1:1:a@b.c:s1" "45:1:1:b@b.c:s2" "46:1:1:c@b.c:s3" \
    "47:1:1:d@b.c:s4" "48:1:1:e@b.c:s5" "49:1:1:f@b.c:s6"
  run announce
  [ "$status" -eq 0 ]
  [ "$(cards)" = "--title 6 new messages --body INBOX --source haus.mail --kind chat --thread haus.mail.INBOX" ]
}

@test "--test draws the newest message and leaves the watermark where it was" {
  printf '{"uidvalidity": "111", "uid": 43}' >"$STATE/uid-INBOX.json"
  start_server 1 111 "43:0:4095:a@b.c:nothing new, and it still proves the chain"
  run announce --test
  [ "$status" -eq 0 ]
  [[ "$(cards)" == *"--title a@b.c"* ]]
  [ "$(watermark)" = "43" ]
}

@test "a renumbered mailbox resets the line instead of swallowing what follows" {
  printf '{"uidvalidity": "111", "uid": 49}' >"$STATE/uid-INBOX.json"
  start_server 1 999 "10:1:1:a@b.c:first after the renumber" "11:1:1:b@b.c:second"
  run announce
  [ "$status" -eq 0 ]
  [ -z "$(cards)" ]
  # 11, never 49: keeping the old number is what makes every later message
  # invisible until the server happens to reach 50.
  [ "$(watermark)" = "11" ]

  # And the next message on that mailbox announces normally.
  start_server 1 999 "10:0:1:a@b.c:read" "11:0:1:b@b.c:read" "12:1:2748:c@b.c:the new one"
  run announce
  [ "$status" -eq 0 ]
  [[ "$(cards)" == *"--body the new one"* ]]
  [ "$(watermark)" = "12" ]
}

@test "no password is a refusal with a code, not a card" {
  start_server 1 111 "41:1:1:a@b.c:one"
  run announce --password-command "true"
  # EX_CONFIG. There is no version of this that logs in without a password.
  [ "$status" -eq 78 ]
  [ -z "$(cards)" ]
}

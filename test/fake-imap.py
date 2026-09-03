#!/usr/bin/env python3
# A fake IMAP server, for test/mail-imap.bats.
#
# It exists because the alternative was shipping the announcer's half of an IMAP
# conversation without ever having had one. Everything ../modules/notifications/
# mail-announce.py does to a server is a response SHAPE it has to parse —
# EXAMINE's UIDVALIDITY, `SEARCH`'s untagged list, `FETCH *`'s sequence-numbered
# UID, and a literal-carrying header fetch with X-GM-THRID glued to the front
# of it. Four parses, none of them exercised by anything hermetic, each of them
# a silent no-card if it is wrong.
#
# ⚠️ TLS, not plaintext, and that is the point of the certificate the suite
# generates: imaplib's IMAP4_SSL verifies the chain and the hostname, so a fake
# that skipped it would have needed a plaintext seam in the production code —
# a flag whose only caller is a test and whose failure mode is a mailbox
# password crossing a network in the clear.
#
# It speaks the smallest dialect that gets one client through: no AUTHENTICATE,
# no STARTTLS, no partial fetches, no flag writes. A test that needed more
# would be a test of imaplib.

import argparse
import re
import socket
import ssl
import sys

CAPABILITIES = "IMAP4rev1 UIDPLUS X-GM-EXT-1"


class Mailbox:
    def __init__(self, uidvalidity, messages):
        # messages: list of (uid, unseen, thrid, from, subject)
        self.uidvalidity = uidvalidity
        self.messages = messages

    def uids(self):
        return [message[0] for message in self.messages]

    def unseen(self):
        return [message[0] for message in self.messages if message[1]]

    def by_uid(self, uid):
        for index, message in enumerate(self.messages, start=1):
            if message[0] == uid:
                return index, message
        return None, None


def headers_for(message):
    return f"From: {message[3]}\r\nSubject: {message[4]}\r\n\r\n".encode()


def search(mailbox, criteria):
    """`UNSEEN`, or `UID <low>:* UNSEEN` — the two the announcer sends."""
    unseen = mailbox.unseen()
    found = re.match(r"UID (\d+):\* UNSEEN", criteria.strip(), re.IGNORECASE)
    if found:
        low = int(found.group(1))
        return [uid for uid in unseen if uid >= low]
    return unseen


def serve(conn, mailbox):
    stream = conn.makefile("rwb")

    def send(line):
        stream.write(line.encode() + b"\r\n")
        stream.flush()

    def send_bytes(raw):
        stream.write(raw)
        stream.flush()

    send(f"* OK [CAPABILITY {CAPABILITIES}] fake-imap ready")

    while True:
        line = stream.readline()
        if not line:
            return
        text = line.decode(errors="replace").strip()
        tag, _, rest = text.partition(" ")
        command, _, args = rest.partition(" ")
        command = command.upper()

        if command == "CAPABILITY":
            send(f"* CAPABILITY {CAPABILITIES}")
            send(f"{tag} OK CAPABILITY completed")
        elif command == "LOGIN":
            send(f"{tag} OK LOGIN completed")
        elif command in ("SELECT", "EXAMINE"):
            send(f"* {len(mailbox.messages)} EXISTS")
            send(f"* OK [UIDVALIDITY {mailbox.uidvalidity}] UIDs valid")
            send(f"{tag} OK [READ-ONLY] {command} completed")
        elif command == "UID":
            verb, _, verb_args = args.partition(" ")
            verb = verb.upper()
            if verb == "SEARCH":
                hits = search(mailbox, verb_args)
                send("* SEARCH " + " ".join(str(uid) for uid in hits))
                send(f"{tag} OK UID SEARCH completed")
            elif verb == "FETCH":
                uid_text, _, items = verb_args.partition(" ")
                index, message = mailbox.by_uid(int(uid_text))
                if message is None:
                    send(f"{tag} OK UID FETCH completed")
                    continue
                raw = headers_for(message)
                prefix = f"* {index} FETCH ("
                if "X-GM-THRID" in items.upper():
                    prefix += f"X-GM-THRID {message[2]} "
                prefix += f"UID {message[0]} BODY[HEADER.FIELDS (FROM SUBJECT)] "
                send_bytes(prefix.encode() + b"{%d}\r\n" % len(raw) + raw + b")\r\n")
                send(f"{tag} OK UID FETCH completed")
            else:
                send(f"{tag} BAD unsupported UID verb")
        elif command == "FETCH":
            # `FETCH * (UID)` — the cheap "what is the top of this mailbox".
            if not mailbox.messages:
                send(f"{tag} OK FETCH completed")
                continue
            send(f"* {len(mailbox.messages)} FETCH (UID {mailbox.uids()[-1]})")
            send(f"{tag} OK FETCH completed")
        elif command == "LOGOUT":
            send("* BYE fake-imap closing")
            send(f"{tag} OK LOGOUT completed")
            return
        elif command == "NOOP":
            send(f"{tag} OK NOOP completed")
        else:
            send(f"{tag} BAD unknown command {command}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--port",
        type=int,
        default=0,
        help="0 (the default) binds a free one and writes it to --ready-file, "
        "which is what keeps two cases in the same suite from racing for a "
        "number",
    )
    parser.add_argument("--cert", required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--uidvalidity", default="1")
    parser.add_argument(
        "--message",
        action="append",
        default=[],
        help="uid:unseen:thrid:from:subject — repeatable, in mailbox order",
    )
    parser.add_argument("--serve", type=int, default=1, help="connections to accept")
    parser.add_argument(
        "--ready-file", help="the bound port, written once the socket is listening"
    )
    args = parser.parse_args()

    messages = []
    for spec in args.message:
        uid, unseen, thrid, sender, subject = spec.split(":", 4)
        messages.append(
            (int(uid), unseen == "1", int(thrid), sender, subject)
        )
    mailbox = Mailbox(args.uidvalidity, messages)

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(args.cert, args.key)

    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", args.port))
    listener.listen(5)
    if args.ready_file:
        # Written last and in one go: the caller waits on this file's existence,
        # so anything written before the socket is listening is a race that
        # fails as a connection refused in whichever case ran first.
        with open(args.ready_file, "w") as handle:
            handle.write(f"{listener.getsockname()[1]}\n")

    for _ in range(args.serve):
        raw, _ = listener.accept()
        try:
            with context.wrap_socket(raw, server_side=True) as conn:
                serve(conn, mailbox)
        except (ssl.SSLError, OSError) as error:
            print(f"fake-imap: {error}", file=sys.stderr)
    listener.close()


if __name__ == "__main__":
    main()

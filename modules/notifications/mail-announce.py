#!/usr/bin/env python3
# haus-mail-announce — turn "something changed in <mailbox>" into one card per
# message that is actually new to this Mac.
#
# Called by goimapnotify's onNewMail hook (see ./mail.nix). goimapnotify holds
# the IDLE connection and knows only which mailbox moved; this reopens that
# mailbox read-only, works out which messages this machine has never announced,
# and hands each one to `haus-notify`.
#
# ── why this is a second process at all ──────────────────────────────────────
# The IDLE half is the fiddly one: re-issuing IDLE inside the window RFC 2177
# allows, noticing a TCP connection that died silently across a sleep, backing
# off when the server says no. goimapnotify does all of that — with a dial
# retry budget and a switch for the servers that need an ID command — and more
# than one machine tests it. Its failure mode is the worst thing this repo can
# ship: a notification that silently stops arriving.
#
# imaplib's own `idle()` would make one process possible, and it is still not
# the trade to take. The loop AROUND idle is the part that fails, and that verb
# is new enough (python 3.14) that a room resting on it refuses to work for any
# consumer whose pkgs is a little behind this repo's — for a room whose whole
# job is to be running six months from now, unnoticed.
#
# So the split is: somebody else's tested loop decides WHEN, and this decides
# WHAT — which is all header parsing and arithmetic, and is what the tests pin.
#
# ── the watermark, and why a new mailbox announces nothing ───────────────────
# goimapnotify runs onNewMail once at startup before any event, and launchd
# starts the agent again at every login. Without a watermark that is a card per
# unread message in the inbox, every morning. So the highest UID this Mac has
# announced is written down per mailbox, and a mailbox nobody has watched before
# records its current top and announces nothing: joining late starts from the
# present, exactly as trill's own System Mirror does when you tick an app.
#
# UIDs are only monotonic within one UIDVALIDITY, so that value is stored beside
# the watermark and a change resets the mailbox to "never seen". Skipping that
# replays a mailbox the server has renumbered — every message in it, at once.
#
# ── read-only, always ────────────────────────────────────────────────────────
# The mailbox is SELECTed read-only and every header comes from BODY.PEEK, so
# nothing here marks mail as read. A notifier that changes what it looked at is
# a bug you find out about from someone else's phone.
#
# ── what goes in the log ─────────────────────────────────────────────────────
# UIDs, counts and mailbox names. Never a subject, a sender or an address: the
# log is a file with none of a card's shyness about who is looking at the
# screen, and trill holds itself to the same line. `--dry-run` is the exception
# and prints the card, because a person asked it to, on their terminal.

import argparse
import email
import email.utils
import fcntl
import imaplib
import json
import os
import re
import subprocess
import sys
from email.header import decode_header, make_header

SOURCE = "haus.mail"
# Gmail's own thread view. `u/<address>` rather than `u/0`: the numbered form
# means "whichever account signed in first", which is the wrong mailbox on any
# Mac signed into two of them.
GMAIL_THREAD_URL = "https://mail.google.com/mail/u/{address}/#all/{thrid:x}"


# ---- the pure half: everything the tests can reach without a server ---------


def decoded(raw):
    """An RFC 2047 header down to one line of text.

    Most non-ASCII subjects arrive as `=?UTF-8?B?…?=`, and a card showing that
    is worse than a card showing nothing. Anything that fails to decode falls
    through as itself rather than raising: a header this machine cannot parse
    is still a message the user wants to hear about.
    """
    if not raw:
        return ""
    try:
        text = str(make_header(decode_header(raw)))
    except Exception:
        text = raw
    return " ".join(text.split())


def sender(from_header):
    """Who it is from, in the form a person recognises.

    The display name when there is one, the bare address when there is not —
    and never both, because the card's title is one line and the address is
    what the Open pill is for.
    """
    display, address = email.utils.parseaddr(from_header or "")
    name = decoded(display)
    return name or address or "Unknown sender"


def card(from_header, subject_header, mailbox, thrid=None, address=None):
    """The card for one message: (title, body, thread, action-or-None).

    Threaded per MAILBOX, not per sender. trill folds everything on one thread
    into a single card with a count and opens it into the list on hover, so a
    burst of five becomes one card you can still read — which is the whole
    reason to hand it a thread at all. Per sender, five people at once is five
    cards and the fold never fires.
    """
    title = sender(from_header)
    body = decoded(subject_header) or "(no subject)"
    thread = f"{SOURCE}.{mailbox}"
    action = None
    if thrid is not None and address:
        action = "Open=" + GMAIL_THREAD_URL.format(address=address, thrid=thrid)
    return title, body, thread, action


def restarting(watermark, uidvalidity, known_uidvalidity):
    """Is the line this Mac wrote down still worth anything?

    Two ways it is not, and they are the same answer: nothing written down at
    all (a mailbox never watched), or a UIDVALIDITY that moved — the server
    renumbered the mailbox, so the old number now points at some other
    message, or at nothing.

    One definition, two callers below, because getting it right in one of them
    and not the other is how a mailbox ends up either flooding or going silent.
    """
    return watermark is None or known_uidvalidity != uidvalidity


def to_announce(unseen_uids, watermark, uidvalidity, known_uidvalidity):
    """Which UIDs are new to this Mac, given what it wrote down last time.

    A mailbox with no usable line starts from the present and announces
    nothing. Everything else is the unseen mail above the line.
    """
    if restarting(watermark, uidvalidity, known_uidvalidity):
        return []
    return sorted(uid for uid in unseen_uids if uid > watermark)


def watermark_after(top, watermark, uidvalidity, known_uidvalidity):
    """Where the line goes after this fire.

    A mailbox with no usable line takes the current top, and must NOT keep the
    old number: UIDs start again from 1 after a renumber, so a mailbox that
    kept a watermark of 49 would swallow every message the server then issued
    until it happened to reach 50. Silently, and for as long as the mailbox
    exists.

    Otherwise the line never moves backwards. `top` is 0 for an empty mailbox
    and for a fetch that came back without a UID, and treating either as "the
    mailbox is empty now" would replay everything still in it.
    """
    if restarting(watermark, uidvalidity, known_uidvalidity):
        return top
    return max(top, watermark)


def slug(mailbox):
    """A mailbox name as a filename. Gmail's are `[Gmail]/All Mail`."""
    return re.sub(r"[^A-Za-z0-9._-]", "_", mailbox) or "mailbox"


# ---- the half that talks to a server ---------------------------------------


def log(message):
    print(f"haus-mail-announce: {message}", flush=True)


def read_state(path):
    try:
        with open(path) as handle:
            state = json.load(handle)
        return state.get("uidvalidity"), int(state["uid"])
    except (OSError, ValueError, KeyError, TypeError):
        return None, None


def write_state(path, uidvalidity, uid):
    # Atomic, and 600: a UID is not a secret but the file sits in a state
    # directory this room keeps at 700 anyway, and a half-written watermark
    # would replay or swallow a mailbox on the next fire.
    tmp = f"{path}.new"
    with open(tmp, "w") as handle:
        json.dump({"uidvalidity": uidvalidity, "uid": uid}, handle)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def password(command):
    """The account password, from the command the room was given.

    Through a shell because that is what the option promises (`haus-secret …`,
    `op read …`, anything). Never cached to disk: both halves of this room can
    ask for it when they need it, so there is no reason for a copy to exist.
    """
    done = subprocess.run(
        command, shell=True, capture_output=True, text=True, check=False
    )
    return done.stdout.strip()


def highest_uid(imap):
    """The top of the mailbox, without listing it.

    `FETCH *` is the last message by sequence number, so this is one round trip
    whatever the mailbox holds. `SEARCH ALL` would hand back every UID in it —
    a hundred thousand of them for `[Gmail]/All Mail`, to learn one number.
    """
    typ, data = imap.fetch("*", "(UID)")
    if typ != "OK" or not data or data[0] is None:
        return 0
    found = re.search(rb"UID (\d+)", data[0] if isinstance(data[0], bytes) else data[0][0])
    return int(found.group(1)) if found else 0


def unseen(imap, watermark):
    """The unseen UIDs above the watermark, asked of the server that way.

    Both halves matter. UNSEEN alone re-announces anything you left unread;
    above-the-watermark alone announces mail you already read on your phone
    thirty seconds ago, which is the single most annoying thing a mail notifier
    does.
    """
    criteria = "UNSEEN" if watermark is None else f"UID {watermark + 1}:* UNSEEN"
    typ, data = imap.uid("SEARCH", criteria)
    if typ != "OK" or not data or not data[0]:
        return []
    return sorted(int(part) for part in data[0].split())


def headers(imap, uid, want_thrid):
    """FROM, SUBJECT and (on Gmail) the thread id, for one UID.

    BODY.PEEK, so the message stays unread. X-GM-THRID only where the server
    said it speaks Gmail's dialect: asking for an unknown data item is a BAD
    response and takes the whole fetch down with it.
    """
    items = "BODY.PEEK[HEADER.FIELDS (FROM SUBJECT)]"
    if want_thrid:
        items = f"X-GM-THRID {items}"
    typ, data = imap.uid("FETCH", str(uid), f"({items})")
    if typ != "OK":
        return None, None, None
    thrid = None
    message = None
    for part in data:
        if not isinstance(part, tuple):
            continue
        found = re.search(rb"X-GM-THRID (\d+)", part[0])
        if found:
            thrid = int(found.group(1))
        message = email.message_from_bytes(part[1])
    if message is None:
        # Deleted between the search and the fetch. Not an error: the message
        # the user would have been told about is gone.
        return None, None, None
    return message.get("From"), message.get("Subject"), thrid


def send(notify, title, body, thread, action, dry_run):
    argv = [
        notify,
        "--title",
        title,
        "--body",
        body,
        "--source",
        SOURCE,
        "--kind",
        "chat",
        "--thread",
        thread,
    ]
    if action:
        argv += ["--action", action]
    if dry_run:
        print(" ".join(repr(part) for part in argv[1:]))
        return
    subprocess.run(argv, check=False)


def main():
    parser = argparse.ArgumentParser(
        description="Draw a trill card for each new message in an IMAP mailbox."
    )
    parser.add_argument("--mailbox", required=True)
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", type=int, default=993)
    parser.add_argument("--address", required=True)
    parser.add_argument("--password-command", required=True)
    parser.add_argument("--notify", default="haus-notify")
    parser.add_argument("--state-dir", required=True)
    parser.add_argument(
        "--max-cards",
        type=int,
        default=5,
        help="above this, one card saying how many rather than a screenful",
    )
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print the cards instead of drawing them, and leave the watermark alone",
    )
    parser.add_argument(
        "--test",
        action="store_true",
        help="draw a card for the newest message whatever the watermark says, "
        "and leave the watermark alone — the one-command proof that the whole "
        "chain works without waiting for mail",
    )
    args = parser.parse_args()

    os.makedirs(args.state_dir, mode=0o700, exist_ok=True)
    name = slug(args.mailbox)
    state_path = os.path.join(args.state_dir, f"uid-{name}.json")

    # One fire at a time per mailbox. Two EXISTS a second apart would otherwise
    # both read the old watermark and both announce the same message. Blocking
    # rather than "give up if busy": the second fire may be the one that knows
    # about a message the first has not seen.
    lock_path = os.path.join(args.state_dir, f"lock-{name}")
    lock = open(lock_path, "w")
    fcntl.flock(lock, fcntl.LOCK_EX)

    secret = password(args.password_command)
    if not secret:
        # EX_CONFIG, the same answer the github room's receiver gives: there is
        # no reduced-function version of this that logs in without a password.
        log(f"{args.mailbox} — no password from the configured command")
        return 78

    # imaplib refuses a line over 10 kB by default, and a real mail header goes
    # past that — a long References chain, or forty Received hops. The refusal
    # takes down the whole fetch, so the one message with a big header would be
    # the one that never draws a card.
    imaplib._MAXLINE = max(imaplib._MAXLINE, 1_000_000)
    try:
        imap = imaplib.IMAP4_SSL(args.host, args.port, timeout=args.timeout)
    except Exception as error:
        log(f"{args.mailbox} — cannot reach {args.host}:{args.port}: {error}")
        return 1

    try:
        imap.login(args.address, secret)
        typ, _ = imap.select(f'"{args.mailbox}"', readonly=True)
        if typ != "OK":
            log(f"{args.mailbox} — no such mailbox on this account")
            return 1

        uidvalidity_raw = imap.response("UIDVALIDITY")[1]
        uidvalidity = (
            uidvalidity_raw[0].decode() if uidvalidity_raw and uidvalidity_raw[0] else None
        )
        known_uidvalidity, watermark = read_state(state_path)
        top = highest_uid(imap)
        want_thrid = "X-GM-EXT-1" in imap.capabilities

        if args.test:
            uids = [top] if top else []
        else:
            uids = to_announce(
                unseen(imap, watermark), watermark, uidvalidity, known_uidvalidity
            )

        if len(uids) > args.max_cards:
            # A screenful of cards is not more information than one line saying
            # how many. This is the login case: mail that arrived while the Mac
            # was shut is a count, not a morning of banners.
            send(
                args.notify,
                f"{len(uids)} new messages",
                args.mailbox,
                f"{SOURCE}.{args.mailbox}",
                None,
                args.dry_run,
            )
        else:
            for uid in uids:
                from_header, subject_header, thrid = headers(imap, uid, want_thrid)
                if from_header is None and subject_header is None:
                    continue
                title, body, thread, action = card(
                    from_header, subject_header, args.mailbox, thrid, args.address
                )
                send(args.notify, title, body, thread, action, args.dry_run)

        moved = watermark_after(top, watermark, uidvalidity, known_uidvalidity)
        held = args.dry_run or args.test
        if not held:
            write_state(state_path, uidvalidity, moved)
        was = "(new mailbox)" if watermark is None else watermark
        if known_uidvalidity != uidvalidity and watermark is not None:
            was = f"{watermark} (mailbox renumbered)"
        log(
            f"{args.mailbox} — {len(uids)} to draw, watermark {was} "
            f"{'unchanged' if held else f'→ {moved}'}"
        )
    except Exception as error:
        log(f"{args.mailbox} — {type(error).__name__}: {error}")
        return 1
    finally:
        try:
            imap.logout()
        except Exception:
            pass

    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""`haus-json` — the JSON reading `haus` does, as named jobs instead of filters.

Every caller is a shell script that had a jq filter inline. The filters were
short, but they were also the only place the shape of `flake.lock`, the options
catalogue and `nix eval --json` output was written down, spread across forty
call sites in two files.

Each subcommand here does ONE of those jobs and is named for it. Where a jq
filter took a path, so does this; where it encoded a whole record, there is a
subcommand for that record rather than a general expression language. That is
deliberate: a general one would just be jq with a different name.

PATHS are dotted, with `[n]` for a list index: `nodes.haus.locked.rev`,
`sets[0].path`. A segment of `@` stands for `--key` and is taken whole, which
is how a key containing dots is reached — `@.type --key haus.theme.accent`.

Reading: `--file F` or stdin. Output follows `jq -r` — a string prints raw, and
anything else prints as JSON, so `true`, `null` and numbers read back the way
the shell already expects. A missing path prints the `--default` if one was
given, `null` otherwise, and exits 0; only malformed JSON is an error.
"""

import argparse
import json
import re
import sys

MISSING = object()


def load(args):
    try:
        with (open(args.file) if args.file else sys.stdin) as handle:
            return json.load(handle)
    except (OSError, ValueError) as err:
        print(f"haus-json: {err}", file=sys.stderr)
        sys.exit(2)


def walk(doc, path, key=None):
    """Follow a dotted path. Returns MISSING rather than raising.

    A path segment of `@` stands for `--key`, taken literally rather than split
    — which is how a key that itself contains dots is reached. That is most of
    them: an options-catalogue lookup is `@.type` with `--key haus.theme.accent`,
    and a flake.lock one is `nodes.@.locked.rev` with the input's name.
    """
    if not path:
        return doc if key is None else (doc.get(key, MISSING) if isinstance(doc, dict) else MISSING)
    node = doc
    for segment in re.findall(r"[^.\[\]]+|\[\d+\]", path):
        if segment == "@":
            segment = key
        if isinstance(segment, str) and segment.startswith("[") and segment.endswith("]"):
            index = int(segment[1:-1])
            if not isinstance(node, list) or index >= len(node):
                return MISSING
            node = node[index]
        elif isinstance(node, dict) and segment in node:
            node = node[segment]
        else:
            return MISSING
    return node


def raw(value):
    """`jq -r`: strings bare, everything else as JSON."""
    return value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)


# ---- generic readers --------------------------------------------------------


def cmd_get(args):
    value = walk(load(args), args.path, args.key)
    if value is MISSING or value is None:
        if args.default is not None:
            print(args.default)
            return 0
        value = None
    print(raw(value))
    return 0


def cmd_has(args):
    """`jq -e '<path> != null'` — the exit code is the answer."""
    value = walk(load(args), args.path, args.key)
    return 0 if value is not MISSING and value is not None else 1


def cmd_compact(args):
    """The subtree as compact JSON. A missing path prints nothing, like `empty`."""
    value = walk(load(args), args.path, args.key)
    if value is MISSING or value is None:
        return 0
    print(json.dumps(value, separators=(",", ":"), ensure_ascii=False))
    return 0


def cmd_lines(args):
    """Every element of a list, one per line.

    `--strip-prefix` is jq's `ltrimstr`: a checker's failures are absolute
    paths, and the reader has already said which file it is reading.
    """
    value = walk(load(args), args.path, args.key)
    if value is MISSING or value is None:
        return 0
    for item in selected(value, args.where) if args.where else value:
        text = raw(item)
        if args.strip_prefix and text.startswith(args.strip_prefix):
            text = text[len(args.strip_prefix):]
        print(text)
    return 0


def cmd_length(args):
    """How many, optionally of the ones `--where` keeps."""
    value = walk(load(args), args.path, args.key)
    if value is MISSING or value is None:
        print(0)
    elif args.where:
        print(len(selected(value, args.where)))
    else:
        print(len(value))
    return 0


def selected(items, where):
    """`select(.k == v)`. A `where` of `k=null` matches an absent or null field."""
    if not where:
        return list(items)
    key, _, want = where.partition("=")
    if want == "null":
        return [i for i in items if i.get(key) is None]
    return [i for i in items if i.get(key) is not None and str(i.get(key)) == want]


def cmd_rows(args):
    """Tab-separated fields from every element of a list.

    A field is `name` or `name=fallback`, and the fallback is what renders when
    the field is absent or null — the jq `// "—"` at each call site, per field
    rather than per row. Every renderer here reads its rows back with
    `IFS=$'\\t' read`, where TAB is an IFS *whitespace* character: bash collapses
    a run of them, so an empty field silently shifts every later one left. Give
    each field a non-empty fallback and that cannot happen.

    `--where k=v` keeps only the elements whose field `k` equals `v`.
    """
    value = walk(load(args), args.path, args.key)
    if value is MISSING or value is None:
        return 0
    for item in selected(value, args.where):
        cells = []
        for field in args.fields:
            name, _, fallback = field.partition("=")
            cell = item.get(name)
            cells.append(fallback or args.null_as if cell is None else raw(cell))
        print("\t".join(cells))
    return 0


def cmd_pluck(args):
    """One field from every element, as a JSON array — jq's `[.sets[].path]`."""
    value = walk(load(args), args.path, args.key) or []
    field = args.fields[0] if args.fields else None
    picked = [i.get(field) for i in selected(value, args.where)] if field else list(value)
    print(json.dumps(picked, separators=(",", ":"), ensure_ascii=False))
    return 0


def cmd_join(args):
    """One field from every element, joined — jq's `[.silent[].title] | join(…)`."""
    value = walk(load(args), args.path, args.key) or []
    field = args.fields[0] if args.fields else None
    picked = [i.get(field) for i in selected(value, args.where)] if field else list(value)
    print(args.sep.join("" if i is None else raw(i) for i in picked))
    return 0


# ---- writing ----------------------------------------------------------------


def cmd_encode_string(args):
    """stdin as a JSON string — `jq -Rn --arg v … '$v'`, for embedding in Nix."""
    print(json.dumps(sys.stdin.read(), ensure_ascii=False))
    return 0


def cmd_parse(args):
    """Compact stdin if it is JSON at all. Exit 1 if it isn't — the caller's test."""
    try:
        doc = json.loads(sys.stdin.read())
    except ValueError:
        return 1
    print(json.dumps(doc, separators=(",", ":"), ensure_ascii=False))
    return 0


def cmd_str_or_json(args):
    """A `nix eval --json` result as a person should see it.

    A string is its own best rendering; everything else is JSON. Same rule the
    settings printer had inline.
    """
    doc = load(args)
    print(doc if isinstance(doc, str) else json.dumps(doc, separators=(",", ":"), ensure_ascii=False))
    return 0


# ---- one-job readers, named for the job -------------------------------------


def cmd_catalogue_rows(args):
    """Every settable path with its one-line summary, for `haus set`'s picker.

    The `haus.` prefix is dropped because the picker's rows are already inside
    that namespace and 38 columns is the budget. `--sep` because the picker
    wants a tab to `awk` on and zsh's completion wants the `path:description`
    its `_describe` reads.
    """
    for key, entry in load(args).items():
        print(f"{key[5:]}{args.sep}{entry.get('summary', '')}")
    return 0


def cmd_commit_subjects(args):
    """The first line of each commit message in a GitHub compare response."""
    for commit in load(args).get("commits") or []:
        print(commit.get("commit", {}).get("message", "").split("\n")[0])
    return 0


def cmd_defaults_block(args):
    """A `defaults export` domain as Nix assignments.

    Nested values are called out rather than emitted: JSON's `[a, b]` is not
    valid Nix list syntax (`[ a b ]`), and silently emitting it would produce a
    file that doesn't evaluate.
    """
    for key, value in load(args).items():
        if isinstance(value, (list, dict)):
            print(f"    # {key} — nested value, add it by hand if you need it")
        else:
            print(
                f"    {json.dumps(key, ensure_ascii=False)} = "
                f"{json.dumps(value, separators=(',', ':'), ensure_ascii=False)};"
            )
    return 0


def cmd_perm_deck(args):
    """The permissions deck, one card per record.

    US (\\x1f) between fields and RS (\\x1e) between steps, NOT tab: tab is an
    IFS *whitespace* character, so bash collapses runs of them and strips the
    leading and trailing ones — a card with no `applies` shifted every field
    after it left, and the wizard ran its pane URL as a shell check. Prose is
    flattened to one line; code keeps its newlines as VT (\\x0b), which
    `_perm_code` puts back before anything is evaluated.
    """

    def flat(text):
        return re.sub(r"\s+", " ", text or "").strip(" ")

    def code(text):
        return (text or "").replace("\n", "\x0b")

    cards = load(args)
    for card in sorted(cards, key=lambda c: (c.get("order", 0), c.get("key", ""))):
        fields = [
            card.get("key", ""),
            flat(card.get("title")),
            flat(card.get("why")),
            flat(card.get("cost")),
            code(card.get("applies")),
            code(card.get("check")),
            code(card.get("prompt")),
            flat(card.get("promptLabel")),
            card.get("pane") or "",
            "\x1e".join(flat(step) for step in (card.get("steps") or [])),
            code(card.get("detail")),
        ]
        sys.stdout.write("\x1f".join(fields) + "\n")
    return 0


# ---- `haus show`'s three records --------------------------------------------
# The reader builds JSON as well as reading it, and these are the three places
# it does. They are subcommands rather than a filter because each one IS a
# documented shape: `origin` and the `--json` envelope are read by other
# people's CI, so the shape belongs somewhere a person can find it by name.


def cmd_show_origin(args):
    """Where a fetched source came from, and how old that is.

    `file` is null for a source that had no pick — a `file` shape IS the file.
    """
    fetched = load(args)
    print(
        json.dumps(
            {
                "typed": args.typed,
                "shape": args.shape,
                "file": args.pick or None,
                "tree": fetched.get("tree"),
                "rev": fetched.get("rev"),
                "lastModified": fetched.get("lastModified"),
                "narHash": fetched.get("narHash"),
                "fetchedAt": int(args.at),
            },
            separators=(",", ":"),
            ensure_ascii=False,
        )
    )
    return 0


def cmd_show_verdicts(args):
    """What each leaf the file sets would actually do on THIS machine.

      overridden  something here outranks a desktop, so the file's value does
                  not land — the single most useful line in the report
      unranked    a leaf under a recursive container, which has no option node,
                  so the values compare but the winner cannot be named
      unknown     this machine's haus has no such option: the file was written
                  against a different one than you have pinned
      unchanged   it already says that
      changes     it moves
    """
    machine = json.loads(args.machine)
    report = json.loads(args.report)
    have = {leaf["path"]: leaf for leaf in machine.get("leaves") or []}

    def verdict(want, leaf):
        if leaf is None or (not leaf.get("ranked") and leaf.get("inside") is None):
            return "unknown"
        if leaf.get("ranked") and leaf.get("prio", 0) < 900:
            return "overridden"
        if leaf.get("value") == want:
            return "unchanged"
        if not leaf.get("ranked"):
            return "unranked"
        return "changes"

    leaves = []
    for item in report.get("sets") or []:
        leaf = have.get(item["path"])
        leaves.append(
            {
                "path": item["path"],
                "proposed": item["value"],
                "current": (leaf or {}).get("value"),
                "prio": (leaf or {}).get("prio"),
                "type": (leaf or {}).get("type"),
                "inside": (leaf or {}).get("inside"),
                "verdict": verdict(item["value"], leaf),
            }
        )
    print(
        json.dumps(
            {
                "host": machine.get("host"),
                "desktop": machine.get("desktop"),
                "leaves": leaves,
                "drops": [
                    {"path": path, "current": have.get(path, {}).get("value")}
                    for path in machine.get("dropped") or []
                ],
            },
            separators=(",", ":"),
            ensure_ascii=False,
        )
    )
    return 0


def cmd_show_envelope(args):
    """haus's first `--json` verb, and the envelope the rest of the sweep copies.

    `ok` is NULL when nothing was checked, never `true`. A room and an
    unreadable file are both "not a failed desktop", and a consumer reading
    `.ok` alone must not be told they passed — `.ok == true` has to mean the
    checker said so. `failures` still carries the reason an unreadable file had
    no reading, because throwing that away leaves the caller with an exit code
    and no sentence.
    """
    report = json.loads(args.report) if args.report else None
    desktop = args.klass == "desktop"
    failures = []
    if args.klass != "room":
        failures = list((report or {}).get("failures") or [])
        if args.reason:
            failures.append(args.reason)
    envelope = {
        "schemaVersion": 1,
        "file": (report or {}).get("file") or args.file_,
        "origin": json.loads(args.origin),
        "class": args.klass,
        "checked": desktop,
        "ok": (report or {}).get("ok") if desktop else None,
        "failures": failures,
        "sets": (report or {}).get("sets") if desktop else [],
        "rooms": (report or {}).get("rooms") if desktop else [],
        "silent": (report or {}).get("silent") if desktop else [],
        "machine": json.loads(args.machine),
    }
    print(json.dumps(envelope, indent=2, ensure_ascii=False))
    return 0


COMMANDS = {
    "get": cmd_get,
    "has": cmd_has,
    "compact": cmd_compact,
    "lines": cmd_lines,
    "length": cmd_length,
    "rows": cmd_rows,
    "pluck": cmd_pluck,
    "join": cmd_join,
    "encode-string": cmd_encode_string,
    "parse": cmd_parse,
    "str-or-json": cmd_str_or_json,
    "catalogue-rows": cmd_catalogue_rows,
    "commit-subjects": cmd_commit_subjects,
    "defaults-block": cmd_defaults_block,
    "perm-deck": cmd_perm_deck,
    "show-origin": cmd_show_origin,
    "show-verdicts": cmd_show_verdicts,
    "show-envelope": cmd_show_envelope,
}


def main():
    ap = argparse.ArgumentParser(prog="haus-json")
    ap.add_argument("command", choices=sorted(COMMANDS))
    ap.add_argument("path", nargs="?", default="")
    ap.add_argument("fields", nargs="*")
    ap.add_argument("--file", "-f")
    ap.add_argument("--key", help="what `@` stands for in the path, taken literally")
    ap.add_argument("--default", help="printed when the path is absent or null")
    ap.add_argument("--where", help="rows: keep elements whose field=value")
    ap.add_argument("--null-as", default="", help="rows: how an absent field renders")
    ap.add_argument("--sep", default="\t", help="catalogue-rows/join: separator")
    ap.add_argument("--strip-prefix", help="lines: drop this prefix from each line")
    ap.add_argument("--typed", help="show-origin: the source as the user typed it")
    ap.add_argument("--pick", default="", help="show-origin: the file picked out of the tree")
    ap.add_argument("--shape", help="show-origin: file | tree | repo")
    ap.add_argument("--at", default="0", help="show-origin: the fetch timestamp")
    ap.add_argument("--machine", default="null", help="show-*: the machine's leaves, as JSON")
    ap.add_argument("--report", default="", help="show-*: the checker's report, as JSON")
    ap.add_argument("--origin", default="null", help="show-envelope: the origin record")
    ap.add_argument("--class", dest="klass", help="show-envelope: desktop | room")
    ap.add_argument("--file-", dest="file_", default="", help="show-envelope: the file read")
    ap.add_argument("--reason", default="", help="show-envelope: why it could not be read")
    args = ap.parse_args()
    return COMMANDS[args.command](args)


if __name__ == "__main__":
    sys.exit(main())

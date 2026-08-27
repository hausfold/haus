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
    """Every element of a list, one per line."""
    value = walk(load(args), args.path, args.key)
    if value is MISSING or value is None:
        return 0
    for item in value:
        print(raw(item))
    return 0


def cmd_length(args):
    value = walk(load(args), args.path, args.key)
    print(0 if value is MISSING or value is None else len(value))
    return 0


def cmd_rows(args):
    """Tab-separated fields from every element of a list.

    `--where k=v` keeps only the elements whose field `k` equals `v`; a field
    that is absent or null renders as `--null-as` (default the empty string),
    which is what the jq `// "—"` fallbacks did at each call site.
    """
    value = walk(load(args), args.path, args.key)
    if value is MISSING or value is None:
        return 0
    key, _, want = (args.where or "").partition("=")
    for item in value:
        if args.where and str(item.get(key)) != want:
            continue
        cells = []
        for field in args.fields:
            cell = item.get(field)
            cells.append(args.null_as if cell is None else raw(cell))
        print("\t".join(cells))
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


COMMANDS = {
    "get": cmd_get,
    "has": cmd_has,
    "compact": cmd_compact,
    "lines": cmd_lines,
    "length": cmd_length,
    "rows": cmd_rows,
    "encode-string": cmd_encode_string,
    "parse": cmd_parse,
    "str-or-json": cmd_str_or_json,
    "catalogue-rows": cmd_catalogue_rows,
    "commit-subjects": cmd_commit_subjects,
    "defaults-block": cmd_defaults_block,
    "perm-deck": cmd_perm_deck,
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
    ap.add_argument("--sep", default="\t", help="catalogue-rows: field separator")
    args = ap.parse_args()
    return COMMANDS[args.command](args)


if __name__ == "__main__":
    sys.exit(main())

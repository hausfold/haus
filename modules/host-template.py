#!/usr/bin/env python3
"""Render the ANNOTATED HOST FILE and the OFFLINE OPTIONS CATALOGUE.

Both come out of nixosOptionsDoc's `options.json`, and both used to be jq
programs (`host-template.jq`, `options-catalogue.jq`). They live together
because they are the same query asked twice: every settable `haus.*` path, once
as prose you edit and once as data a picker reads.

WHY NOT NIX, when the agent skill's reference next door is rendered in Nix.
Everything here is width-aware text: greedy word wrap at four different
columns, a summary cut on a word boundary at 78, comment blocks aligned under
their classification. Nix strings are BYTES — `builtins.stringLength "—"` is 3
— so every wrap in a description containing an em-dash or a `⌘` would break at
a different column than the jq it replaces, and there is no codepoint-aware
length in the Nix builtins to fix it with. Python counts characters, which is
what the old renderer counted, so this port is byte-for-byte.

  host file   share/haus/host-options.nix
  catalogue   share/haus/options.json

The self-checks that used to be four more jq calls in the derivation are at the
bottom of this file, against the data rather than against the rendered text.
"""

import argparse
import json
import re
import sys

# ---- shared: how a default or example is written out ------------------------


def lit(value):
    """A default as the reference should write it.

    literalExpression carries the author's own text; anything else is JSON, so
    a string default renders quoted and reads as a value rather than as prose.
    """
    if isinstance(value, dict) and "_type" in value:
        return value.get("text") or json.dumps(
            value.get("value"), separators=(",", ":"), ensure_ascii=False
        )
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False)


def pasteable(raw, rendered):
    """Can `rendered` go on the right-hand side of an assignment in a host file?

    Two ways it can't, and the host file and the catalogue agree on both:
    a `literalMD` default is a SENTENCE describing the value ("19, scaled by
    haus.ui.scale"), and one that reads `config.` is a real expression with no
    `config` in scope where a value gets typed. Both are still worth SHOWING;
    neither may be prefilled as if the user had typed it.
    """
    if rendered is None:
        return False
    if isinstance(raw, dict) and raw.get("_type", "literalExpression") != "literalExpression":
        return False
    return re.search(r"\bconfig\.", rendered) is None


# ---- shared: text shaping ---------------------------------------------------


def wrap(width, text):
    """Greedy word wrap, as a list of lines.

    Descriptions arrive already hard-wrapped by hand in the .nix sources and are
    passed through untouched; this is for the machine-generated strings (a
    `one of "a", "b", …` type runs past 200 characters and would otherwise be
    one unreadable line).
    """
    lines = []
    for word in re.split(r"[ \t\n]+", text):
        if not word:
            continue
        if not lines:
            lines.append(word)
        elif len(lines[-1]) + 1 + len(word) <= width:
            lines[-1] = lines[-1] + " " + word
        else:
            lines.append(word)
    return lines or [""]


def softwrap(width, text):
    """Re-wrap only prose that needs it.

    Most descriptions are hand-wrapped in their .nix source at a sensible width
    and some lay out lists or tables a blind re-wrap would destroy; a few (the
    bar pills) are authored as one 800-character line. So: leave a paragraph
    alone unless it has a line that is actually too long, and only then reflow.
    """
    longest = max((len(line) for line in text.split("\n")), default=0)
    return "\n".join(wrap(width, text)) if longest > width else text


def commented(indent, text):
    """Comment a block of text at a given indent.

    Blank lines become a bare "#" so a stanza reads as one comment block rather
    than as fragments separated by voids.
    """
    return [
        indent + "#" if re.match(r"^[ \t]*$", line) else indent + "# " + line
        for line in text.split("\n")
    ]


def rtrim_newline(text):
    """jq's `rtrimstr("\\n")`: one trailing newline, not all of them."""
    return text[:-1] if text.endswith("\n") else text


# ---- the annotated host file ------------------------------------------------

# The docs site slugifies `### `haus.theme.accent`` by lowercasing and dropping
# everything that isn't alphanumeric — so the dots and the backticks vanish.
# Held across the Starlight → Fumadocs move; verified against the links on the
# live page (hausfold.co/docs/haus/reference/options/#hauspouncewindowswitcher).
def slug(key):
    return re.sub(r"[^a-z0-9]", "", key.lower())


def demarkdown(text):
    """Room blurbs are markdown, because the docs page renders them as-is.

    A Nix comment can't click a link, so `[your host file](/internals/…)`
    becomes `your host file` — the sentence survives, the URL noise doesn't.
    """
    return re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)


def explain(text):
    """The sentence under a `desktop data:` line.

    Wrapped and aligned under the classification it explains rather than at the
    `type:` continuation, so a wrapped type and a rule never read as one line.
    Blank in, nothing out: a registry that carries a name and no sentence
    renders no line at all rather than an indented empty comment.
    """
    text = text or ""
    if re.match(r"^[ \t]*$", text):
        return ""
    return "\n".join("  #               " + line for line in wrap(56, text)) + "\n"


def uninformative(rendered):
    """A default that teaches nothing about the option's shape.

    For those — and only those — the example is worth the extra lines, because
    `haus.apps = { }` on its own tells you nothing about what goes inside.
    """
    t = rendered[1:] if rendered.startswith(" ") else rendered
    t = t[:-1] if t.endswith(" ") else t
    return t in ("{ }", "[ ]", "null", '""', "{}", "[]")


HEADER = """\
# Every haus.* option this machine has, at its default.
#
# GENERATED at install time from haus {version}'s own module system, so it
# describes the options that exist at the revision you pinned — not upstream's
# latest. Regenerate it after `haus update` with:  haus options
#
# HOW TO USE IT. Everything below is commented out and the file does nothing as
# shipped. Uncomment a line to change that option; delete every line you never
# touched and you are left with a minimal host config that says only what you
# meant. Apply with `haus rebuild`; undo with `haus rollback`.
#
# WHY COMMENTED OUT rather than spelled out like AeroSpace's default config: a
# file that stated every default explicitly would silently override your whole
# desktop and freeze every default. A line here outranks the desktop you
# selected — uncomment `ui.scale` and `haus.appearance.largePrint = true` stops
# reaching it. And a plain value outranks the ROOMS' own `lib.mkDefault`s for
# good, so a later haus that retunes that default could never reach you.
#
# Overriding your desktop is a PLAIN assignment, no `lib.mkForce` needed —
# that is what the priority ladder is for. Uncomment the one line you mean.
#
# Your identity, apps and secrets live NEXT DOOR in default.nix, which imports
# this file. Both are yours to edit; only this one is safe to regenerate.
#
# Full reference: https://hausfold.co/docs/haus/reference/options/
{{ ... }}:

{{
"""


def nixish(value):
    """jq's string interpolation of a maybe-missing registry field."""
    return "null" if value is None else str(value)


def stanza(key, opt, safety, validators, reasons):
    raw = opt.get("default")
    rendered = None if raw is None else lit(raw)
    can_paste = pasteable(raw, rendered)

    # Descriptions run to several paragraphs; the first says what the option IS
    # and the rest is caveat that belongs on the docs page. Carrying all of it
    # would turn 84 options into a 2000-line file nobody scrolls to the bottom of.
    desc = softwrap(74, rtrim_newline(opt.get("description", "").split("\n\n")[0]))

    out = ""
    if desc != "":
        out += "\n".join(commented("  ", desc)) + "\n"
    out += "  #\n"
    out += (
        "\n".join(
            ("  # type: " if i == 0 else "  #       ") + line
            for i, line in enumerate(wrap(66, opt["type"]))
        )
        + "\n"
    )
    out += f"  # docs: https://hausfold.co/docs/haus/reference/options/#{slug(key)}\n"
    out += "  # desktop data: "

    safety = safety or {}
    if safety.get("desktopSafe") is True:
        out += "safe\n"
    elif safety.get("desktopSafe") is False:
        out += "host-only\n"
        out += explain(reasons.get(safety.get("reason") or "", {}).get("why"))
    else:
        validator = safety.get("validator")
        out += f"recursive ({nixish(validator)})\n"
        out += explain(validators.get(validator or "", {}).get("rule"))

    if "example" in opt and rendered is not None and uninformative(rendered):
        body = f"{key} = " + rtrim_newline(lit(opt["example"])) + ";"
        out += "  #\n  # example:\n"
        out += "\n".join("  #   " + line for line in body.split("\n")) + "\n"
        out += "  #\n"

    if rendered is None:
        out += f"  # {key} = …;   # REQUIRED — this option has no default\n"
    elif not can_paste:
        note = "default (not a literal you can paste): " + rtrim_newline(rendered)
        out += "\n".join(commented("  ", softwrap(72, note))) + "\n"
        out += f"  # {key} = …;\n"
    else:
        out += "\n".join(commented("  ", f"{key} = " + rtrim_newline(rendered) + ";")) + "\n"
    return out


def render_template(opts, groups, version):
    namespaces = groups.get("namespaces") or {}
    validators = groups.get("validators") or {}
    reasons = groups.get("hostOnlyReasons") or {}

    # Every namespace is registry-backed; `room-registry` rejects an
    # unclassified option before this renderer runs.
    rooms = {}
    for key in opts:
        rooms.setdefault(key.split(".")[1], []).append(key)
    ordered = sorted(rooms, key=lambda r: (namespaces.get(r, {}).get("order", 0), r))

    out = HEADER.format(version=version)
    for room in ordered:
        meta = namespaces.get(room, {})
        # 64 = 78 columns minus the "  # ═══ haus." + " " that precedes it.
        rule = "═" * max(64 - len(room), 3)
        out += f"\n  # ═══ haus.{room} {rule}\n"
        blurb = meta.get("blurb") or ""
        if blurb != "":
            out += "\n".join(commented("  ", "\n".join(wrap(74, demarkdown(blurb))))) + "\n"
        out += "\n"
        out += "\n".join(
            stanza(key, opts[key], (meta.get("options") or {}).get(key), validators, reasons)
            for key in rooms[room]
        )
    # The trailing newline `jq -r` used to add after the closing brace. Kept so
    # a machine that regenerates its host file sees no diff but its own edits.
    return out + "}\n\n"


# ---- the offline options catalogue ------------------------------------------


def summary(description):
    """One SHORT line, because this ends up in a menu row next to the path.

    A row that wraps stops being a row. The first paragraph is what the host
    file keeps; the first line is less than that, and even that is not always
    short — several descriptions (the bar pills) are authored as one
    800-character line, so the hard cut is doing the real work here, not the
    split. Cut on a word boundary at 78, which leaves a 38-column path and a
    row inside 120.
    """
    text = re.sub(r"^[ \t\n\r\f\v]+|[ \t\n\r\f\v]+$", "", (description or "").split("\n")[0])
    if len(text) > 78:
        return re.sub(r" [^ ]*$", "", text[:78]) + "…"
    return text


def render_catalogue(opts):
    out = {}
    for key, opt in opts.items():
        raw = opt.get("default")
        rendered = None if raw is None else lit(raw)
        out[key] = {
            "type": opt["type"],
            "default": rendered,
            "literal": pasteable(raw, rendered),
            "summary": summary(opt.get("description")),
        }
    return out


# ---- entry point ------------------------------------------------------------


def settable(options):
    """`haus.*` only, and no submodule children.

    `haus.apps.<name>.key` documents what goes INSIDE an attrset option — you
    cannot name it on a `haus set` command line, and you cannot uncomment it in
    a host file either. The parent is in the list with an example that shows
    the whole shape.
    """
    return {
        key: value
        for key, value in sorted(options.items())
        if key.startswith("haus.") and not re.search(r"<|\*", key)
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--options", required=True)
    ap.add_argument("--groups", required=True)
    ap.add_argument("--version", required=True)
    ap.add_argument("--template", required=True)
    ap.add_argument("--catalogue", required=True)
    args = ap.parse_args()

    with open(args.options) as handle:
        opts = settable(json.load(handle))
    with open(args.groups) as handle:
        groups = json.load(handle)

    # A template that rendered empty would be worse than none: someone would
    # conclude haus has no options rather than that the render broke. Checked
    # here, against the data, rather than by grepping the output afterwards.
    if not opts:
        print("host template: no settable haus.* options — the render is broken", file=sys.stderr)
        return 1

    catalogue = render_catalogue(opts)

    # Every entry must carry the facts a picker prompts from, WITH THE RIGHT
    # SHAPE. Presence is not the check to make: an entry of four nulls would
    # pass it while the value prompt silently degraded to a free-text box for an
    # enum — the exact failure this is for, and it looks like it worked until
    # the rebuild rejects the value. `default` is the one that legitimately may
    # be null (an option with no default at all).
    for key, entry in catalogue.items():
        if not (
            isinstance(entry["type"], str)
            and isinstance(entry["summary"], str)
            and isinstance(entry["literal"], bool)
            and "default" in entry
        ):
            print(f"options catalogue: {key} has a missing or mistyped field", file=sys.stderr)
            return 1

    with open(args.template, "w") as handle:
        handle.write(render_template(opts, groups, args.version))
    with open(args.catalogue, "w") as handle:
        json.dump(catalogue, handle, indent=2, ensure_ascii=False)
        handle.write("\n")

    # The count the derivation's remaining guards compare against, so the
    # expected number comes from the same pass that rendered the files rather
    # than from a second query that could drift out of step with it.
    print(len(opts))
    return 0


if __name__ == "__main__":
    sys.exit(main())

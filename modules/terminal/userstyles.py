#!/usr/bin/env python3
"""Turn selected Nebelung userstyles into plain LESS files, ready for lessc.

The half of the Stylus story that never needed Stylus. nebelung's bundle is
134 usercss styles and NOTHING ELSE — measured, not assumed: every entry
carries `sourceCode` and zero compiled `sections`, because Stylus compiles the
LESS itself at import time. That is the whole reason the accent could only
reach the web through a click. Compile the same source here and the click goes
away; the output is `@-moz-document` blocks, which is exactly what a Gecko
`userContent.css` is made of.

Two things this has to do that Stylus does in the browser:

  * **supply every declared var.** A style's `@var` block is not decoration —
    `less` fails hard on the first undefined variable (YouTube's `@sponsorBlock`
    is how this was found). So every var in `usercssData.vars` is emitted, at
    its own default, and only the three theme axes are overridden.
  * **resolve the standard library.** Every style opens with
    `@import "https://userstyles.catppuccin.com/lib/lib.less"`, and a Nix build
    has no network. The caller vendors that file and passes its path; the import
    is rewritten to point at it.

The palette itself is NOT the vendored lib's. Each style redefines `@catppuccin`
inline with nebelung's own greys after the import, and LESS takes the last
definition — which is why the compiled output carries #202020 and not #1e1e2e.
The lib supplies the mixins those definitions are fed through.
"""

import json
import os
import sys

# The remote import every style opens with. Matched literally rather than by
# regex: if nebelung ever changes the line, the check at the bottom fires and
# says so, which beats a silent half-rewrite.
REMOTE_LIB = '@import "https://userstyles.catppuccin.com/lib/lib.less";'


def var_value(var):
    """One var as LESS sees it: the user's value if the bundle carries one,
    otherwise the style's own default. `range` is the only type that isn't
    already a bare literal — its units live in a separate field."""
    value = var["value"] if var.get("value") is not None else var.get("default")
    if var.get("type") == "range":
        return f"{value}{var.get('units') or ''}"
    return str(value)


def stamp(var, wanted):
    """A theme axis, but only where the style actually offers it.

    Same guard as the Stylus bundle's (modules/terminal/zen.nix): a select var
    whose options don't list our accent keeps its own default rather than being
    handed a name that resolves to nothing. Styles do drop accents.
    """
    options = var.get("options") or []
    if var.get("type") == "select" and any(o.get("name") == wanted for o in options):
        return wanted
    return var_value(var)


def main():
    bundle_path, lib_path, outdir, accent, flavor = sys.argv[1:6]
    wanted = sorted(set(sys.argv[6:]))

    with open(bundle_path) as f:
        bundle = json.load(f)

    # The bundle is a list carrying Stylus's own `settings` object alongside
    # the styles (entry 0 today) — key off `sourceCode` rather than position,
    # which is also what keeps this honest if the export order ever changes.
    styles = {}
    for entry in bundle:
        if not isinstance(entry, dict) or not entry.get("sourceCode"):
            continue
        # The slug is the last segment of the style's namespace
        # (github.com/catppuccin/userstyles/styles/<slug>) — unique across all
        # 134, and the only stable name in the file. `name` is a title
        # ("GitHub Nebelung") and would make an ugly option value.
        slug = entry["usercssData"]["namespace"].rstrip("/").rsplit("/", 1)[-1]
        styles[slug] = entry

    unknown = [s for s in wanted if s not in styles]
    if unknown:
        sys.exit(
            f"haus.zen.userStyles: no such style: {', '.join(unknown)}\n"
            f"  nebelung ships {len(styles)}: {', '.join(sorted(styles))}"
        )

    overrides = {"accentColor": accent, "lightFlavor": flavor, "darkFlavor": flavor}

    os.makedirs(outdir, exist_ok=True)
    for slug in wanted:
        entry = styles[slug]
        data = entry["usercssData"]
        header = "".join(
            f"@{name}: {stamp(var, overrides[name]) if name in overrides else var_value(var)};\n"
            for name, var in (data.get("vars") or {}).items()
        )

        source = entry["sourceCode"]
        if REMOTE_LIB not in source:
            sys.exit(
                f"haus.zen.userStyles: {slug} no longer opens with the catppuccin "
                f"standard library import haus vendors.\n"
                f"  expected: {REMOTE_LIB}\n"
                f"  Re-check what nebelung's bundle imports before bumping the pin."
            )
        source = source.replace(REMOTE_LIB, f'@import "{lib_path}";')

        # 29 of the 134 pull remote CSS for code highlighting (prismjs,
        # pygments, highlight.js) — mdn, wikipedia and the nix docs among them.
        # lessc leaves `@import url(...)` alone and userstyles-inline.py
        # replaces it with the vendored file's contents AFTER lessc, so nothing
        # to do here: an @import is invalid inside `@-moz-document` wherever it
        # points, which is why this is an inline rather than a rewrite.
        with open(os.path.join(outdir, f"{slug}.less"), "w") as f:
            f.write(header + source)

    # One slug per line, and an EMPTY file for an empty selection — not a blank
    # line, which the caller's `while read` would hand to lessc as `less/.less`.
    # Unreachable through the option (terminal/default.nix skips this whole
    # derivation for an empty list), so this is for the second caller.
    with open(os.path.join(outdir, "order"), "w") as f:
        f.writelines(f"{slug}\n" for slug in wanted)


if __name__ == "__main__":
    main()

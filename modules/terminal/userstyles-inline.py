#!/usr/bin/env python3
"""Replace each `@import url(...)` in a compiled style with the CSS it names.

---- the rule this is working around ---------------------------------------

`@import` is only valid at the TOP of a stylesheet. Every one of these sits
inside an `@-moz-document` block, where it is invalid CSS and Firefox drops it
— so the 29 styles that theme their code blocks this way (mdn, wikipedia, the
nix docs, stack-overflow) landed with the code blocks alone unthemed.

VENDORING THE URL DOES NOT FIX THAT. The problem is the position of the rule,
not the distance to the file: an `@import` pointing at /nix/store inside an
`@-moz-document` is dropped for exactly the same reason. The only thing that
works is putting the CSS itself where the `@import` was, which is what this
does — after lessc rather than before it, so LESS never parses text it didn't
author. That matters concretely: two of the four files use `rgb(from … r g b)`
relative colour syntax, which LESS would try to evaluate as its own `rgb()`.

The files are `fetchurl`s pinned by hash in package-userstyles.nix — a Nix
build has no network, and the URLs are version-pinned upstream anyway.

---- why an unknown URL is fatal --------------------------------------------

Silently leaving one behind would put back exactly the failure this removes,
and invisibly: the style would compile, install, and render its code blocks
stock. So a URL with no vendored file stops the build and says which attribute
to add. The cost of that is a build break when upstream adds a fifth URL, which
is the direction you want the failure to point.
"""

import json
import re
import sys

# `@import url("…");` as lessc leaves it — quotes optional, and it never
# rewrites or reflows these, which is what makes a plain regex honest here.
IMPORT = re.compile(r"""@import\s+url\(\s*(['"]?)(?P<url>[^'")]+)\1\s*\)\s*;""")


def inline(css, vendored):
    missing = []

    def one(match):
        url = match.group("url").strip()
        path = vendored.get(url)
        if path is None:
            missing.append(url)
            return match.group(0)
        with open(path) as f:
            body = f.read().strip()
        # Labelled, because the next person to open a profile's userContent.css
        # and find highlight.js selectors in the middle of a wikipedia block
        # deserves to know they were not written there.
        return f"/* inlined from {url} */\n{body}"

    out = IMPORT.sub(one, css)
    if missing:
        sys.exit(
            "haus.zen.userStyles: no vendored copy of "
            + ", ".join(sorted(set(missing)))
            + "\n  An @import inside @-moz-document is invalid CSS, so this has to be\n"
            "  inlined rather than pointed at. Add the URL to `vendoredImports` in\n"
            "  modules/terminal/package-userstyles.nix:\n"
            "    nix store prefetch-file --json <url>"
        )
    return out


if __name__ == "__main__":
    with open(sys.argv[1]) as f:
        vendored = json.load(f)
    sys.stdout.write(inline(sys.stdin.read(), vendored))

#!/usr/bin/env python3
"""Raise every declaration in the compiled userstyles to `!important`.

---- why this pass exists, which is a cascade fact rather than a Gecko one ----

`userContent.css` is a USER stylesheet, and in the cascade a user sheet's
NORMAL declarations sit BELOW the page's own:

    ua normal  <  user normal  <  author normal  <  author !important
                                                 <  user !important

So a user sheet loses every property the site also sets — which, for a theme,
is all of them. Stylus never hits this because it injects a `<style>` element
INTO the document: its rules are author origin and compete on specificity.
That asymmetry is invisible in the compiled CSS, which is why it survived two
releases of `haus.zen.userStyles` looking correct and rendering nothing.

Measured in Zen itself, one page, two divs, one user sheet overriding both:
the normal declaration lost to the site's colour, the `!important` one won.

Most Catppuccin styles theme by redefining the SITE's own custom properties
(`--primary-color`, `--content-bg`) rather than by restyling elements, and
they do it without `!important` — regex101 is 2 out of 287 declarations — so
without this pass those styles are inert from a user sheet. Upstream ships a
`.important.css` build of its highlight.js variables for the same reason.

---- what is deliberately NOT stamped -------------------------------------

`!important` is invalid in three places, and a declaration carrying it there is
DROPPED rather than demoted — so stamping blindly would delete styling instead
of strengthening it:

  * inside `@keyframes` — an important declaration in a keyframe is ignored
  * in descriptor blocks (`@font-face`, `@counter-style`, `@property`, …),
    which take descriptors and not properties at all
  * on at-STATEMENTS like `@import url(...);`, which aren't declarations

Anything whose block this can't positively identify as a style rule is left
alone, which is the safe direction: an unstamped declaration renders as it did
before this pass, a wrongly-stamped one disappears.
"""

import re
import sys

# Conditional group rules hold RULES, not declarations — descend and keep
# looking. `-moz-document` is the one every compiled style opens with.
GROUP_AT_RULES = {
    "media",
    "supports",
    "document",
    "-moz-document",
    "layer",
    "container",
    "scope",
}

# Their children are keyframe blocks, which look exactly like style rules and
# must NOT be stamped — see the docstring.
KEYFRAME_AT_RULES = {"keyframes", "-webkit-keyframes", "-moz-keyframes"}

# What a block of declarations is called when it may be stamped, may not, and
# when it holds rules rather than declarations.
STYLE, DESCRIPTOR, GROUP, KEYFRAMES = "style", "descriptor", "group", "keyframes"

AT_RULE_NAME = re.compile(r"@(-?[A-Za-z][\w-]*)")


def block_kind(prelude, parent):
    """Which of the four a `{` opens, from the text in front of it."""
    prelude = prelude.strip()
    if parent == KEYFRAMES:
        # `0%`, `from`, `to` — a style rule's shape, none of its cascade.
        return DESCRIPTOR
    if not prelude.startswith("@"):
        return STYLE
    name = AT_RULE_NAME.match(prelude)
    name = name.group(1).lower() if name else ""
    if name in GROUP_AT_RULES:
        return GROUP
    if name in KEYFRAME_AT_RULES:
        return KEYFRAMES
    # @font-face, @property, @page, and anything this doesn't know.
    return DESCRIPTOR


def stamp(decl):
    """One declaration's text, raised — or handed back untouched when it is
    already important, is empty, or isn't a declaration at all."""
    if not decl.strip() or "!important" in decl.lower():
        return decl
    if decl.lstrip().startswith("@"):
        return decl
    if ":" not in decl:
        return decl
    # Before the trailing whitespace, so the output still line-breaks where
    # lessc put the break.
    body = decl.rstrip()
    return body + " !important" + decl[len(body) :]


def raise_declarations(css):
    out = []
    stack = [GROUP]  # the top level of a stylesheet holds rules
    decl = []  # text accumulated since the last `{`, `}` or `;`
    i, n = 0, len(css)
    while i < n:
        c = css[i]

        # Comments and strings are copied through verbatim: a `;` or a brace
        # inside either is text, not structure.
        if c == "/" and css.startswith("/*", i):
            end = css.find("*/", i + 2)
            end = n if end == -1 else end + 2
            decl.append(css[i:end])
            i = end
            continue
        if c in "\"'":
            j = i + 1
            while j < n:
                if css[j] == "\\":
                    j += 2
                    continue
                if css[j] == c:
                    j += 1
                    break
                j += 1
            decl.append(css[i:j])
            i = j
            continue

        # An UNQUOTED url() is one token to the parser, so its contents are
        # not structure either. A quoted one already went through the string
        # branch above.
        if (c in "uU") and css[i : i + 4].lower() == "url(":
            end = css.find(")", i)
            end = n if end == -1 else end + 1
            decl.append(css[i:end])
            i = end
            continue

        if c == "{":
            kind = block_kind("".join(decl), stack[-1])
            stack.append(kind)
            out.append("".join(decl))
            out.append("{")
            decl = []
            i += 1
            continue

        if c == "}":
            # A block's last declaration may have no `;` of its own.
            text = "".join(decl)
            out.append(stamp(text) if stack[-1] == STYLE else text)
            if len(stack) > 1:
                stack.pop()
            out.append("}")
            decl = []
            i += 1
            continue

        if c == ";":
            text = "".join(decl)
            out.append(stamp(text) if stack[-1] == STYLE else text)
            out.append(";")
            decl = []
            i += 1
            continue

        decl.append(c)
        i += 1

    out.append("".join(decl))
    return "".join(out)


if __name__ == "__main__":
    sys.stdout.write(raise_declarations(sys.stdin.read()))

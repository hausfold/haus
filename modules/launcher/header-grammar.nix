# The `# pounce: key = value` command-header grammar, mirrored on our side of
# the repo boundary — the sibling of ./item-grammar.nix, one layer over.
#
# pounce parses these headers twice itself (an awk in `pounce-palette`, and
# `CommandRegistry.swift` for the daemon, which is the path ⌘Space actually
# takes). This is the third copy, and it cannot be collapsed into the other two:
# we read headers at Nix EVAL time, where calling a pounce binary would be
# import-from-derivation on every rebuild. A regex is the price of not doing
# that.
#
# What makes the third copy dangerous is WHICH keys it is the only reader of.
# `name`/`description` are pounce's too, so a miss there is loud — the module
# asserts on a null name. But `cheat` and `cheatWhen` are ours alone: pounce
# ignores header keys it does not know, so nothing else in either repo would
# notice. A miss just drops a word from the cheatsheet's key box, or a clause
# from a caption explaining why a row is absent — the surface whose entire job
# is explaining an absence, failing silently.
#
# It has drifted twice already, both found by hand and never by a check:
#   * haus#451 — only this copy rejected `key  = value` (two spaces).
#   * haus#459 / pounce#95 — only the Swift copy accepted an INDENTED header
#     line, and no copy accepted a stray second space after `#`.
# So the grammar is pinned to a table now: `expectedHeaderGrammarTable` in
# ../../flake.nix, checked by `nix flake check`'s `pounce-header-grammar`.
# pounce holds the same cases under the same names over real fixture scripts
# (pkgs/pounce/tests/fixtures/header-grammar/), and once the lock moves past
# pounce#95 this check can read ITS copy directly, the way `pounce-item-grammar`
# already reads `ItemSettings.swift`.
#
# ⚠️ TOLERANCE HERE IS NOT A LICENCE TO USE IT. We are the PRODUCER of the
# headers in ./commands and pounce is the consumer, so anything this file
# accepts that the LOCKED pounce does not is a header we write and the daemon
# drops — falling the row back to its filename, losing the description, and
# never reading `whenFile`, which would list a gated row unconditionally. The
# tolerance exists for headers a USER hand-types in their own command dir,
# where forgiveness beats a silent no-op. Our own stay canonical, and
# `pounce-command-headers` in the flake enforces that separately.
#
# Data + pure `builtins` only — no `lib`, no `config` — so both the module and
# the flake's check can import it without a fixed point (same rule as
# ./item-grammar.nix).
rec {
  # The keys only WE read. pounce ignores them, which is what makes them both
  # possible and unguarded; `pounce-command-keys` allows them by name for the
  # same reason.
  hausOwnKeys = [
    "cheat"
    "cheatWhen"
  ];

  # `# pounce: <field> = <value>` → value, or null.
  #
  # Tolerant in three places, each because a header is hand-typed:
  #   `[ \t]*` before `#`      — an indented header line
  #   `[ \t]+` after `#`       — a stray second space; REQUIRED, so `#pounce:`
  #                              stays an ordinary comment (the `tight-hash`
  #                              fixture pins that, and all three parsers agree)
  #   `[ \t]*` around `=`      — `k  = v`, `k= v`, `k=v`
  #
  # The value is trimmed at BOTH ends. Leading is the regex's job; trailing is
  # `trimEnd`'s, and it is not decorative — pounce's two parsers both finish
  # with a trim (`.trimmingCharacters`, `sub(/[ \t]+$/,…)`), so without it one
  # trailing space in a comment put a stray space inside a rendered caption here
  # and nowhere else.
  matchField =
    field: line:
    let
      m = builtins.match "[ \t]*#[ \t]+pounce:[ \t]*${field}[ \t]*=[ \t]*(.*)" line;
    in
    if m == null then null else trimEnd (builtins.head m);

  # Trailing spaces/tabs off a single line. `builtins.match` is anchored at both
  # ends, so the greedy `.*` backtracks until the last kept character is not
  # whitespace; an all-whitespace value matches nothing and is empty.
  trimEnd =
    s:
    let
      m = builtins.match "(.*[^ \t])[ \t]*" s;
    in
    if m == null then "" else builtins.head m;

  # How many leading lines carry a header. Both of pounce's parsers stop here
  # (`NR > 30 { exit }` in the awk, `if seen > 30 { break }` in Swift), on the
  # grounds that headers live at the top and whole scripts should not be read.
  # Scanning further would make us read a `# pounce:` line inside a heredoc or a
  # long comment block that the daemon never sees — us right, the palette wrong,
  # and no way to tell from either.
  headerLines = 30;

  # First value of `field` in `text`, or null. First wins, like both of pounce's
  # parsers (`&& n == ""` in the awk, `header.name.isEmpty` in Swift).
  fieldOf =
    text: field:
    let
      lines = builtins.filter builtins.isString (builtins.split "\n" text);
      scanned = if builtins.length lines > headerLines then lib_take headerLines lines else lines;
      hits = builtins.filter (v: v != null) (map (matchField field) scanned);
    in
    if hits == [ ] then null else builtins.head hits;

  # `lib.take`, hand-rolled: this file takes no `lib` on purpose (see the header),
  # so both the module and the flake's check can import it without a fixed point.
  lib_take =
    n: xs:
    let
      len = builtins.length xs;
    in
    builtins.genList (builtins.elemAt xs) (if n < len then n else len);
}

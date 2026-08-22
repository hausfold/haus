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
# So the grammar is pinned to a table now: ./header-grammar-table.txt, checked
# by `nix flake check`'s `pounce-header-grammar`. pounce holds the same table
# over the same fixture names (pkgs/pounce/tests/fixtures/), and once the lock
# moves past pounce#95 this check can read ITS copy directly, the way
# `pounce-item-grammar` already reads `ItemSettings.swift` — see the note at the
# bottom of that check.
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

  # First value of `field` in `text`, or null. First wins, like both of pounce's
  # parsers (`&& n == ""` there, `header.name.isEmpty` there).
  fieldOf =
    text: field:
    let
      lines = builtins.filter builtins.isString (builtins.split "\n" text);
      hits = builtins.filter (v: v != null) (map (matchField field) lines);
    in
    if hits == [ ] then null else builtins.head hits;
}

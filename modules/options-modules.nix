# The per-room options files, as a plain list of paths.
#
# These are the ONLY modules that declare `haus.*`, and they are pure
# `{ lib, ... }` modules — no config, no pkgs, no darwin system. That purity is
# what lets the option surface be evaluated on its own, on any platform, which
# in turn is what lets it be RENDERED rather than hand-documented:
#
#   flake.nix  →  .#options-json   → the site's options reference (Linux CI)
#   flake.nix  →  .#agent-skill    → the agent skill installed on every machine
#
# Two consumers, one list — three now that modules/default.nix imports this file
# rather than writing the same paths out again. It lived inline in flake.nix
# while there was one; the second would have been a copy that silently stops
# covering a new room the day someone adds one — the exact drift the whole
# rendered-docs approach exists to prevent. Add a room's options.nix here and
# every surface picks it up.
[
  # The `nebelhaus.*` -> `haus.*` aliases. In this list rather than only in
  # modules/default.nix because the pure-lib evals above are ALSO consumers of
  # the old names: flake.nix's pack and preset checks feed rice files written
  # against `nebelhaus.*` into a bare evalModules of exactly this list.
  ./renamed.nix
  # Options that moved room WITHIN `haus.*` (today: the `claude` room folding
  # into `agents`). Listed here for the same reason renamed.nix is — the evals
  # above are fed rice files written against the old address too.
  ./moved.nix
  ./options.nix
  ./apps/options.nix
  ./den/options.nix
  ./displays/options.nix
  ./theme/options.nix
  ./wallpaper/options.nix
  ./hearth/options.nix
  ./prowl/options.nix
  ./sill/options.nix
  ./collar/options.nix
  ./pounce/options.nix
  ./perch/options.nix
  ./hush/options.nix
  ./secrets/options.nix
  ./snippets/options.nix
]

# The per-room options files, as a plain list of paths.
#
# These are the ONLY modules that declare `nebelhaus.*`, and they are pure
# `{ lib, ... }` modules — no config, no pkgs, no darwin system. That purity is
# what lets the option surface be evaluated on its own, on any platform, which
# in turn is what lets it be RENDERED rather than hand-documented:
#
#   flake.nix  →  .#options-json   → nebelhaus.com's options reference (Linux CI)
#   flake.nix  →  .#claude-skill   → the agent skill installed on every machine
#
# Two consumers, one list. It lived inline in flake.nix while there was one;
# the second would have been a copy that silently stops covering a new room the
# day someone adds one — the exact drift the whole rendered-docs approach exists
# to prevent. Add a room's options.nix here and both surfaces pick it up.
[
  ./options.nix
  ./apps/options.nix
  ./den/options.nix
  ./displays/options.nix
  ./theme/options.nix
  ./hearth/options.nix
  ./prowl/options.nix
  ./sill/options.nix
  ./collar/options.nix
  ./pounce/options.nix
  ./trill/options.nix
  ./perch/options.nix
  ./hush/options.nix
  ./secrets/options.nix
  ./snippets/options.nix
]

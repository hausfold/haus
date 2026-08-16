# The numbered workspaces, from a count.
#
# One line of arithmetic, in modules/lib because it has two callers that cannot
# share a `let`: modules/workspaces resolves it for a real machine, and
# flake.nix's `launch-keys-json` resolves it for the DEFAULT count, purely, on
# Linux CI, with no darwin config anywhere in reach.
#
# The whole subtlety is id vs key, and it appears once, at ten. A workspace is
# named by its number, but the leader reaches it by pressing a DIGIT and there
# is no ten key — so the tenth is id "10" reached by `0`, the wrap a browser's
# tab shortcuts use. Below ten they are the same string, which is why nothing
# needed this distinction until the count stopped being four.
#
# Order is natural, never sorted: sill draws the bar pills in it, and a string
# sort files "10" between "1" and "2".
{ lib }:

count:
lib.genList (
  i:
  let
    id = toString (i + 1);
  in
  {
    inherit id;
    key = if i == 9 then "0" else id;
  }
) count

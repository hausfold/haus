# The desktop seam. A person chooses EXACTLY ONE desktop, and this is where
# that "exactly one" is a rule rather than a sentence in a note.
#
# The selection itself happens in flake.nix (`lib.desktop`, and `mkNebelhaus`'s
# `desktop` argument): a desktop file is validated, its leaves are carried in at
# the desktop priority, and its filename is appended to `haus._desktop.sources`.
# All this module does is read that list back and refuse a second entry — which
# has to happen HERE, in the evaluated system, because two desktops can arrive
# from two different places (the builder's argument and an `extraModules` line)
# and neither seam can see the other.
#
# Zero is allowed, deliberately. A standalone `darwinModules.<room>` import is
# the bare foundation plus one room, and it acquires no desktop's opinions —
# that is what those exports have always meant, and the desktop seam does not
# get to make them stop evaluating.
{ config, lib, ... }:
let
  # Sorted, because the order two definitions of one option arrive in is the
  # module system's business and not a fact worth reporting: the builder's
  # desktop and an `extraModules` one land either way round, and a message that
  # changes with it reads as if it knew something it doesn't.
  sources = builtins.sort (a: b: a < b) config.haus._desktop.sources;
  distinctSources = lib.unique sources;
  repeatedOne = builtins.length sources > 1 && builtins.length distinctSources == 1;
in
{
  assertions = [
    {
      assertion = builtins.length sources <= 1;
      message =
        if repeatedOne then
          "This machine selected the same desktop more than once:\n"
          + "  ${builtins.head distinctSources}\n"
          + "Import it once. Repeating a desktop can duplicate list-valued settings even "
          + "when its scalar values are identical."
        else
          "This machine selected ${toString (builtins.length sources)} desktops:\n"
          + "  ${builtins.concatStringsSep "\n  " sources}\n"
          + "A host runs exactly one. Whole desktops do not stack — pick the one that "
          + "answers what this Mac should feel like, and say the rest in your host file, "
          + "which wins over the desktop by plain assignment. To select one through "
          + "`extraModules` instead of the builder's own `desktop` argument, pass "
          + "`desktop = null` alongside it.";
    }
  ];
}

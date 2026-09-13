# The desktop seam. A person chooses EXACTLY ONE desktop, and this is where
# that "exactly one" is a rule rather than a sentence in a note.
#
# The selection itself happens in flake.nix (`lib.desktop`, and `mkHaus`'s
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

  # The retired desktops (compat/desktops/, bound as `haus.desktops.<name>` in
  # flake.nix) still build the machine they always did, for one release, and
  # say so on every rebuild — the same shape as compat/presets.nix, for the
  # same reason: a consumer scaffolded from hausfold.co/everyday.sh carries
  # `desktop = haus.desktops.everyday;`, and `haus update` moves the lock
  # before it rebuilds, so a throw would leave that machine unable to rebuild
  # until a hand edit. A warning names the edit, and the verb that makes it.
  retiredReplacement = {
    "blank.nix" =
      "select no desktop: `haus desktop none` writes `desktop = null;`, which is exactly what blank was.";
    "minimal.nix" =
      "select no desktop (`haus desktop none`) and set `haus.developer.enable = true;` in your host file (and `haus.security.touchId.enable = true;` for Touch ID sudo).";
    "everyday.nix" =
      "select no desktop (`haus desktop none`) and turn its rooms on in your host file: haus.bar.enable, haus.launcher.enable, haus.shelf.enable, haus.focus.enable and haus.security.touchId.enable, each `= true;`, plus `haus.keys.palette = \"cmd-space\";` and `haus.wallpaper.style = \"minimal\";`.";
  };
  retiredSelected = builtins.filter (
    s: lib.hasInfix "/compat/desktops/" (toString s)
  ) distinctSources;
in
{
  warnings = map (
    s:
    let
      file = baseNameOf (toString s);
    in
    "haus.desktops.${lib.removeSuffix ".nix" file} is retired and will be removed: "
    + (retiredReplacement.${file} or "select no desktop (`haus desktop none`).")
    + " See https://hausfold.co/docs/haus/desktops/choosing/#retired-names. This alias keeps your current machine building."
  ) retiredSelected;

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

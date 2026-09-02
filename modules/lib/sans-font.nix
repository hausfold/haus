# Resolve haus.fonts.sans into the package that provides the family — or null,
# because unlike mono, "nothing to install" is the normal answer here.
#
#   sansPackage = import ../lib/sans-font.nix {
#     inherit lib pkgs;
#     fonts = config.haus.fonts;
#   };
#
# THE SHAPE IS mono-font.nix's, AND THE DEFAULT IS NOT. `package` is a package
# (code), `packageName` is an attribute path into nixpkgs (data, so a data-only
# desktop can change the family too) — same two arms, same "set one or the
# other". What differs is the third case: mono falls back to haus's own
# JetBrains Mono Nerd Font, because the terminal has to be SOME Nerd Font or
# starship, lsd and yazi render tofu. `sans` falls back to null, because its
# default family is `.AppleSystemUIFont` — macOS's own, on every Mac, and
# nothing haus could install if it wanted to.
#
# So the caller installs `lib.optional (sansPackage != null) sansPackage`, and a
# desktop that never names a family installs no proportional font at all, which
# is what it did before this option existed.
{
  lib,
  pkgs,
  fonts,
}:

if fonts.sans.package != null then
  fonts.sans.package
else if fonts.sans.packageName != null then
  import ./pkg-by-name.nix {
    inherit lib pkgs;
    option = "haus.fonts.sans.packageName";
    name = fonts.sans.packageName;
  }
else
  null

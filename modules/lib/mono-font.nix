# Resolve haus.fonts.mono into the package that actually provides the family.
# Imported the same way as bar.nix / gaps.nix — a plain function, no module
# system.
#
#   monoPackage = import ../lib/mono-font.nix {
#     inherit lib pkgs;
#     fonts = config.haus.fonts;
#   };
#
# THREE ways to say it and one answer, which is why this isn't a let-binding in
# den any more: `package` is a package (code), `packageName` is an attribute path
# into nixpkgs (data, so a data-only desktop can change the family too), and
# neither set means the rice's own JetBrains Mono Nerd Font. den INSTALLS the
# result; wallpaper reads the font FILE out of it to set the debug band in.
# Getting a different answer in the two rooms would put the desktop in one
# typeface and the terminal in front of it in another.
{
  lib,
  pkgs,
  fonts,
}:

if fonts.mono.package != null then
  fonts.mono.package
else if fonts.mono.packageName != null then
  import ./pkg-by-name.nix {
    inherit lib pkgs;
    option = "haus.fonts.mono.packageName";
    name = fonts.mono.packageName;
  }
else
  pkgs.nerd-fonts.jetbrains-mono

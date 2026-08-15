# Resolve a package NAMED as a string into the package itself.
#
#   pkgByName { inherit lib pkgs; option = "haus.fonts.mono.packageName";
#               name = "nerd-fonts.fira-code"; }
#
# Why a string at all, when `types.package` exists and is more precise: a
# shared desktop or app pack is DATA (an attrset, no arguments, so
# `haus.lib.checkDesktop`/`checkRice` can read it at a glance), and a data file cannot
# reach `pkgs`. So every `types.package` option in the surface is invisible to
# the format the whole rice-sharing story is built on: a shared rice could make
# the terminal font bigger but not change its family, and a pack could install
# from Homebrew and the App Store but never from Nixpkgs. Naming the attribute
# is the one move that stays data.
#
# WHAT THIS DOES AND DOESN'T GUARANTEE. It walks `pkgs` by attribute path and
# nothing else — no `import`, no `builtins.eval`, no string that becomes code.
# That's the property that matters: reading a rice still tells you everything it
# can do. It is NOT a claim that the software is safe; a data-only rice could
# already install anything Homebrew ships via `cask`, and naming a nixpkgs
# attribute is the same kind of trust, not a new one.
#
# Dotted paths are supported because that's how nixpkgs is shaped
# ("nerd-fonts.fira-code", "python3Packages.black") and a flat-only lookup would
# send exactly the fonts case — the motivating one — back to `types.package`.
{
  lib,
  pkgs,
  # The option path, for the error message. A throw from deep inside a resolve
  # helper is otherwise unattributable: the reader sees a package name they
  # never typed and no clue which of their lines produced it.
  option,
  name,
}:

let
  path = lib.splitString "." name;

  # tryEval, because an intermediate that isn't an attrset ("hello.foo") makes
  # hasAttrByPath itself throw nix's own message rather than returning false.
  probe = builtins.tryEval (lib.hasAttrByPath path pkgs);
  found = probe.success && probe.value;

  drv = lib.getAttrFromPath path pkgs;
in
if !found then
  throw ''
    haus: ${option} = "${name}" names no package.

    It is read as an attribute path into nixpkgs, so "fira-code" means
    pkgs.fira-code and "nerd-fonts.fira-code" means pkgs.nerd-fonts.fira-code.
    Search for the right spelling with `nix search nixpkgs ${lib.last path}`.
  ''
else if !(lib.isDerivation drv) then
  throw ''
    haus: ${option} = "${name}" exists in nixpkgs but is not a package.

    It resolves to ${builtins.typeOf drv} — usually a set of packages rather
    than one of them (pkgs.nerd-fonts is the set, pkgs.nerd-fonts.fira-code is
    the font). Name the leaf.
  ''
else
  drv

# Resolve nebelhaus.theme.{flavor,contrast} into the handful of things every
# module that reads the `nebelung` input needs. Imported the same way as
# gui-wait.nix — a plain function, no module system involved.
#
#   nb = import ../lib/nebelung.nix { inherit lib nebelung; theme = osConfig.nebelhaus.theme; };
#   nb.root      # themes-package path to source rendered ports from
#   nb.palette   # name -> "#hex" for the selected variant
#   nb.flavor    # the catppuccin flavor whiskers rendered it as ("mocha" | "latte")
#   nb.title     # that flavor, capitalised — some ports title-case it in a path
#
# This exists because three modules (hearth, sill, theme) each read the palette
# and each source rendered files, so the selection was duplicated three times the
# moment `contrast` landed. Adding the `flavor` axis would have made that six
# near-identical blocks, and flavor is the axis where getting it subtly wrong is
# invisible — a mocha path under a latte root silently resolves to nothing.
#
# `flavor` is load-bearing beyond picking colours: whiskers names its output after
# the flavor it rendered (catppuccin-latte.conf, "Catppuccin Latte.tmTheme",
# zen/themes/Latte/), and templates branch on `flavor.dark`. So callers must build
# paths from nb.flavor rather than writing "mocha" — see modules/hearth.
{
  lib,
  nebelung,
  theme,
}:

let
  # Variant naming MIRRORS nebelung's own, deliberately rather than by reading its
  # `variants` output: keeping it derivable here means the DEFAULT selection still
  # evaluates against an older nebelung lock, so a flavor change and its lock bump
  # don't have to land in the same commit. The rule is
  # nebelung/scripts/generate-palette.mjs's `variantDir` — the default variant is
  # plain "nebelung" and owns the themes-package root; every other one is
  # "nebelung-<parts>" and renders into "<parts>/" beneath it.
  parts =
    lib.optional (theme.flavor != "mocha") theme.flavor
    ++ lib.optional (theme.contrast == "high") "high-contrast";
  subdir = lib.concatStringsSep "-" parts;
  variant = lib.concatStringsSep "-" ([ "nebelung" ] ++ parts);

  capitalise = s: lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (lib.stringLength s) s;
in
{
  # "normal"/"mocha" is the EMPTY subdir, i.e. byte-for-byte the paths that were
  # here before any variant existed.
  root = "${nebelung.themes}" + lib.optionalString (subdir != "") "/${subdir}";

  palette =
    nebelung.palettes.${variant} or (throw ''
      nebelhaus: the pinned `nebelung` input renders no "${variant}" palette.
      nebelhaus.theme.flavor = "${theme.flavor}" with contrast = "${theme.contrast}"
      needs a newer nebelung — run `nix flake update nebelung` (or `bench ship`,
      which ripples it) and rebuild.
    '');

  flavor = theme.flavor;
  title = capitalise theme.flavor;
  inherit variant;
}

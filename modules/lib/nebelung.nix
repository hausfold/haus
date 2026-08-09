# Resolve haus.theme.{flavor,contrast} into the handful of things every
# module that reads the `nebelung` input needs. Imported the same way as
# gui-wait.nix — a plain function, no module system involved.
#
#   nb = import ../lib/nebelung.nix { inherit lib nebelung; theme = osConfig.haus.theme; };
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
  contrastParts = lib.optional (theme.contrast == "high") "high-contrast";
  parts = lib.optional (theme.flavor != "mocha") theme.flavor ++ contrastParts;
  subdir = lib.concatStringsSep "-" parts;
  variant = lib.concatStringsSep "-" ([ "nebelung" ] ++ parts);

  # The same rule with the flavor axis forced to each pole, for the consumers
  # that can follow macOS Light/Dark instead of pinning one polarity (pounce's
  # theme/themeLight pair). Contrast still tracks theme.contrast — only the
  # flavor is taken out of the machine's hands.
  darkVariant = lib.concatStringsSep "-" ([ "nebelung" ] ++ contrastParts);
  lightVariant = lib.concatStringsSep "-" (
    [
      "nebelung"
      "latte"
    ]
    ++ contrastParts
  );

  capitalise = s: lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (lib.stringLength s) s;

  root = "${nebelung.themes}" + lib.optionalString (subdir != "") "/${subdir}";

  # nebelung's ports.meta.json records each port's path for the DEFAULT (mocha)
  # variant. Every other variant renders the same port under its own flavor name
  # — catppuccin-latte.conf, "Catppuccin Latte.tmTheme", zen/themes/Latte/ — so
  # a metadata path has to be re-spelled for the selected flavor before it means
  # anything. This is the same substitution the hand-written wiring in
  # modules/hearth does inline (`catppuccin-${nbFlavor}.conf`); doing it here
  # means a port's path comes FROM nebelung instead of being retyped next to it.
  resolveFlavor =
    p: builtins.replaceStrings [ "mocha" "Mocha" ] [ theme.flavor (capitalise theme.flavor) ] p;
in
{
  # "normal"/"mocha" is the EMPTY subdir, i.e. byte-for-byte the paths that were
  # here before any variant existed.
  inherit root;

  # Per-port install metadata, narrowed to the ports whose TOOL runs on macOS
  # (nebelung ships Linux-only ones too — foot, Xresources, zathura, tty) and
  # with `path` resolved to both the selected flavor and an absolute location in
  # the themes tree. `{ }` on an older nebelung lock that predates the output;
  # every consumer below treats "no metadata" as "nothing to offer", never as an
  # error, so being pinned behind it costs the report, not the build.
  # The flavor lives in the human-facing strings too, not just the path: a port's
  # `howto`, its `setting.value` and its `requires` commands all name the theme
  # ("set theme = catppuccin-mocha", "fish_config theme choose catppuccin-mocha").
  # Resolving the path but not those is the worst outcome — a correct file next
  # to instructions that name a theme this machine doesn't have.
  ports = lib.mapAttrs (
    _: p:
    p
    // {
      path = resolveFlavor p.path;
      file = "${root}/${resolveFlavor p.path}";
      howto = resolveFlavor p.howto;
    }
    // lib.optionalAttrs (p ? setting && p.setting ? value) {
      setting = p.setting // {
        value = resolveFlavor p.setting.value;
      };
    }
    // lib.optionalAttrs (p ? requires) { requires = map resolveFlavor p.requires; }
  ) (lib.filterAttrs (_: p: builtins.elem "darwin" p.platform) (nebelung.ports or { }));

  palette =
    nebelung.palettes.${variant} or (throw ''
      nebelhaus: the pinned `nebelung` input renders no "${variant}" palette.
      haus.theme.flavor = "${theme.flavor}" with contrast = "${theme.contrast}"
      needs a newer nebelung — run `nix flake update nebelung` (or `bench ship`,
      which ripples it) and rebuild.
    '');

  flavor = theme.flavor;
  title = capitalise theme.flavor;
  inherit variant darkVariant lightVariant;
}

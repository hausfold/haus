# Resolve haus.wallpaper.* — plus the four other rooms it reads — into the
# picture itself. A plain function, no module system, so it has TWO callers:
#
#   ./default.nix                    the real desktop, from a real machine's config
#   flake.nix `packages.<sys>.wallpaper`   the same look at the shipped defaults,
#                                    so `nix build .#wallpaper` shows you what
#                                    `minimal` IS without rebuilding a Mac — and
#                                    so the `wallpaper` flake check has something
#                                    to actually render.
#
# The split is what makes that second caller free of duplication: everything
# below — the depth ladder, the six-accent ring, the gap-derived inset, the lock
# edges — would otherwise have to be written twice and agree by hand.
{
  pkgs,
  lib,
  nebelung,
  inputs,
  theme, # haus.theme
  cfg, # haus.wallpaper
  ui, # haus.ui
  bar, # haus.bar
  fonts, # haus.fonts
}:

let
  # haus.theme.{flavor,contrast} select which rendered variant this reads —
  # ../lib/nebelung.nix owns that resolution for terminal, bar and wallpaper
  # alike. Only the palette is needed here.
  #
  # It reaches `minimal` and `bold` and stops there: the three hand-made PNGs
  # have the DARK palette in their pixels and do not follow the flavour. The
  # option says so.
  palette =
    (import ../lib/nebelung.nix {
      inherit lib nebelung theme;
    }).palette;

  # The background ladder, ordered from the pole inwards, so `depth = 0` means
  # "as far out as this palette goes" in either polarity. In mocha that's crust
  # at the black end; in latte the light end is `base`, which is why the first
  # three entries swap rather than the list reversing. options.nix prints the
  # whole table.
  ladder =
    if theme.flavor == "latte" then
      [
        "base"
        "mantle"
        "crust"
        "surface0"
        "surface1"
        "surface2"
      ]
    else
      [
        "crust"
        "mantle"
        "base"
        "surface0"
        "surface1"
        "surface2"
      ];
  background =
    if cfg.background != null then cfg.background else palette.${builtins.elemAt ladder cfg.depth};

  # The six product accents, in the order hausfold.co sweeps them. By palette
  # NAME rather than by hex so `spectrum` follows the flavour: the Nebelung
  # pastels read on a dark field, and latte's saturated counterparts read on a
  # light one — the same swap the site makes.
  family = map (n: palette.${n}) [
    "mauve" # nebelung
    "teal" # scruff
    "green" # perch
    "yellow" # trill
    "peach" # pounce
    "pink" # hacker
  ];

  size = builtins.match "([0-9]+)x([0-9]+)" cfg.size;
  width = lib.toInt (builtins.elemAt size 0);
  height = lib.toInt (builtins.elemAt size 1);

  # The inset a tiled window's bottom-left corner lands on. ../lib/gaps.nix is
  # the same arithmetic windows writes into aerospace.toml, so the band can't
  # drift out from under the windows when a gap is retuned. `outermost` is the
  # widest reservation any attached display could be using — inset by the
  # built-in's narrower gap instead and the band peeks out from under an
  # external's wider one.
  gaps = import ../lib/gaps.nix {
    inherit lib bar;
    scale = ui.scale;
  };
  # Gaps are points; a picture is pixels. Two per point on every Retina display,
  # which is every display haus targets — haus.wallpaper.debug.inset is the
  # way out for one that isn't.
  retina = 2;

  # A lock edge, the way `bench status` means it: the revision this system was
  # actually built from. `shortRev` is absent on a local override — which is
  # exactly what `bench try` does — so a dirty tree says so rather than failing
  # the build.
  edge =
    name:
    let
      src = if name == "self" then inputs.self or null else inputs.${name} or null;
    in
    if src == null then
      null
    else
      {
        key = if name == "self" then "haus" else name;
        value = src.shortRev or src.dirtyShortRev or "local";
      };
  rows = lib.filter (r: r != null) (map edge cfg.debug.inputs);

  minimal = pkgs.callPackage ./package.nix { } {
    name = "haus-wallpaper-${theme.flavor}-${theme.accent}-${toString cfg.depth}-${cfg.mark.color}.png";
    inherit width height background;
    grain = cfg.grain;
    glow =
      if cfg.glow.enable then
        {
          color = if cfg.glow.color != null then cfg.glow.color else palette.${theme.accent};
          inherit (cfg.glow) strength spread;
        }
      else
        null;
    mark =
      if cfg.mark.enable then
        {
          inherit (cfg.mark)
            size
            weight
            rise
            opacity
            ;
          paint =
            {
              muted = {
                kind = "solid";
                color = palette.overlay1;
              };
              ink = {
                kind = "solid";
                color = palette.text;
              };
              accent = {
                kind = "solid";
                color = palette.${theme.accent};
              };
              spectrum = {
                kind = "spectrum";
                colors = family;
              };
            }
            .${cfg.mark.color};
        }
      else
        null;
    debug =
      if cfg.debug.enable then
        {
          inherit rows;
          inherit (cfg.debug) size;
          insetX = if cfg.debug.inset != null then cfg.debug.inset else gaps.outermost.left * retina;
          insetY = if cfg.debug.inset != null then cfg.debug.inset else gaps.outermost.bottom * retina;
          # The rev is the content, the repo name is the label, so the name takes
          # the dimmer of the two. surface2 is the stronger tone against the
          # field in BOTH flavours (mocha's ladder runs up from black, latte's
          # down from white), so the emphasis doesn't invert when haus goes
          # light.
          keyColor = palette.surface1;
          valueColor = palette.surface2;
          # core's resolution, not the raw option: `package` is null on a desktop
          # that named its font as `packageName` or left the default.
          fontPackage = import ../lib/mono-font.nix { inherit lib pkgs fonts; };
        }
      else
        null;
  };

  # `bold` predates `minimal` and is kept as it was: a diagonal accent→crust
  # sweep, saturation pushed 150% so the grey-tinted Nebelung pastels read bold
  # rather than washed. It goes through ImageMagick alone because it has no
  # vector layer to place.
  bold =
    pkgs.runCommand "nebelung-bold-${theme.accent}.png" { nativeBuildInputs = [ pkgs.imagemagick ]; }
      ''
        magick -size 6048x3928 \
          gradient:'${palette.${theme.accent}}'-'${palette.crust}' \
          -rotate -30 -gravity center -extent 3024x1964 \
          -modulate 100,150 "$out"
      '';
in
if cfg.style == "minimal" then
  minimal
else if cfg.style == "bold" then
  bold
else
  ./looks/${cfg.style}.png

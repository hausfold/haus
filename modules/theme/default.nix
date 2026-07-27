# Theme — the desktop wallpaper. The accent (nebelhaus.theme.accent) lives in
# options.nix and is consumed per-tool by hearth/sill/pounce; this room owns the
# one whole-desktop surface those don't touch: the wallpaper behind everything.
#
# Four Nebelung looks (nebelhaus.theme.wallpaper):
#   orbits · constellation · flow  — hand-made PNGs, the palette baked in
#   bold                           — GENERATED from theme.accent, so it follows
#                                    the accent (a bold pink at accent = "pink")
#   none (default)                 — leave whatever wallpaper you already have
#
# Set via osascript at each home-manager activation. Changing the desktop is a
# visible, personal thing, so the default is `none`: nothing moves unless a host
# (or the bootstrap interview) opts in.
{
  config,
  lib,
  username,
  ...
}:

let
  choice = config.nebelhaus.theme.wallpaper;
  accent = config.nebelhaus.theme.accent;
in
{
  config = lib.mkIf (choice != "none") {
    home-manager.users.${username} =
      {
        lib,
        pkgs,
        osConfig,
        nebelung,
        ...
      }:
      let
        # nebelhaus.theme.contrast selects which rendered variant everything below
        # reads. Two derived bindings rather than threading the option through each
        # call site: the variant renders into a SUBDIRECTORY of the same package, so
        # the only difference is a path prefix — and "normal" is the empty prefix,
        # i.e. byte-for-byte the paths that were here before.
        nebelungRoot =
          "${nebelung.themes}"
          + lib.optionalString (osConfig.nebelhaus.theme.contrast == "high") "/high-contrast";
        nebelungPalette =
          if osConfig.nebelhaus.theme.contrast == "high" then
            nebelung.palettes.nebelung-high-contrast
          else
            nebelung.palette;
        # `bold` is rendered in a pure derivation from the accent hex, so it
        # recolours with theme.accent like the per-tool accents do. A diagonal
        # accent→crust sweep, saturation pushed 150% so the grey-tinted Nebelung
        # pastels read bold rather than washed. The three hand-made wallpapers
        # are shipped PNGs, already palette-correct.
        boldWallpaper =
          pkgs.runCommand "nebelung-bold-${accent}.png" { nativeBuildInputs = [ pkgs.imagemagick ]; }
            ''
              magick -size 6048x3928 \
                gradient:'${nebelungPalette.${accent}}'-'${nebelungPalette.crust}' \
                -rotate -30 -gravity center -extent 3024x1964 \
                -modulate 100,150 "$out"
            '';

        # enum guarantees choice ∈ { orbits, constellation, flow, bold } here.
        wallpaper = if choice == "bold" then boldWallpaper else ./wallpapers/${choice}.png;
      in
      {
        # Re-applied on every switch. osascript sets the picture for every
        # desktop on the current Space; a wallpaper set must never be able to
        # fail the whole activation, so it's guarded.
        home.activation.nebelhausWallpaper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run /usr/bin/osascript -e \
            'tell application "System Events" to tell every desktop to set picture to "${wallpaper}"' \
            || run true
        '';
      };
  };
}

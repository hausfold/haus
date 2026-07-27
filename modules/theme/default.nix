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
        # nebelhaus.theme.{flavor,contrast} select which rendered variant everything
        # below reads — ../lib/nebelung.nix owns that resolution for hearth, sill and
        # theme alike, so the flavor axis was added in one place rather than three.
        # Only the palette is needed here (the generated wordmark reads two hexes);
        # the three shipped wallpapers have the DARK palette baked into their pixels
        # and do not follow theme.flavor — see the option's honest-scope note.
        nebelungPalette =
          (import ../lib/nebelung.nix {
            inherit lib nebelung;
            theme = osConfig.nebelhaus.theme;
          }).palette;
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

# wallpaper — the desktop behind everything.
#
# Six looks under haus.wallpaper.style (options.nix has the table). Five of them
# are a file: `orbits`, `constellation` and `flow` are hand-made PNGs with the
# dark palette baked into their pixels, `bold` is a diagonal accent→crust sweep
# generated from haus.theme.accent, and `none` leaves whatever desktop you
# already have alone.
#
# `minimal` is the haus-themed one, the default, and the reason this stopped
# being a value on the theme and became a room. It is generated from this machine: the palette and
# flavour pick the field, the accent lights it, prowl's gaps place the debug
# band, and the flake's own lock edges are what that band says. ./render.nix
# resolves all five rooms into the picture's arguments and ./package.nix renders
# it — this file is only the option gate and the osascript that hangs it.
#
# Set via osascript at each home-manager activation, for the same reason the
# system appearance is (see ../theme): a desktop belongs to a logged-in GUI
# session, and there is no `defaults` key that moves it.
{
  config,
  lib,
  username,
  ...
}:

{
  config = lib.mkIf (config.haus.wallpaper.style != "none") {
    home-manager.users.${username} =
      {
        lib,
        pkgs,
        osConfig,
        nebelung,
        inputs,
        ...
      }:
      let
        wallpaper = import ./render.nix {
          inherit
            pkgs
            lib
            nebelung
            inputs
            ;
          inherit (osConfig.haus)
            theme
            ui
            sill
            fonts
            ;
          cfg = osConfig.haus.wallpaper;
        };
      in
      {
        # Re-applied on every switch. osascript sets the picture for every
        # desktop on the current Space; a wallpaper set must never be able to
        # fail the whole activation, so it's guarded.
        home.activation.hausWallpaper = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run /usr/bin/osascript -e \
            'tell application "System Events" to tell every desktop to set picture to "${wallpaper}"' \
            || run true
        '';
      };
  };
}

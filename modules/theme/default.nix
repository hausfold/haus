# Theme — the two whole-desktop surfaces the per-tool palette wiring doesn't
# touch. The accent (nebelhaus.theme.accent) lives in options.nix and is
# consumed per-tool by hearth/sill/pounce; this room owns the wallpaper behind
# everything, and macOS's own Light/Dark appearance.
#
# Four Nebelung looks (nebelhaus.theme.wallpaper):
#   orbits · constellation · flow  — hand-made PNGs, the palette baked in
#   bold                           — GENERATED from theme.accent, so it follows
#                                    the accent (a bold pink at accent = "pink")
#   none (default)                 — leave whatever wallpaper you already have
#
# Set via osascript at each home-manager activation. Changing the desktop is a
# visible, personal thing, so the default is `none`: nothing moves unless a host
# (or the bootstrap interview) opts in. nebelhaus.theme.systemAppearance is the
# same deal — default "unmanaged", and osascript for the same reason the
# wallpaper uses it, only more so: see the block that applies it.
{
  config,
  lib,
  username,
  ...
}:

let
  choice = config.nebelhaus.theme.wallpaper;
  accent = config.nebelhaus.theme.accent;

  # ---- macOS Light/Dark (nebelhaus.theme.systemAppearance) ------------------
  appearanceChoice = config.nebelhaus.theme.systemAppearance;
  # "flavor" resolves here rather than in the activation script so the built
  # system carries the ANSWER, not the rule — one less thing to be wrong at 3am
  # in a shell fragment.
  appearanceWanted =
    if appearanceChoice == "flavor" then
      (if config.nebelhaus.theme.flavor == "latte" then "light" else "dark")
    else
      appearanceChoice;
in
{
  config = lib.mkMerge [
    (lib.mkIf (appearanceChoice != "unmanaged") {
      home-manager.users.${username} =
        { lib, pkgs, ... }:
        let
          # Same derivation den installs system-wide; asking for it again is
          # free (identical inputs → identical store path) and keeps this room
          # from depending on den's let-block.
          hausax = pkgs.callPackage ../den/package-hausax.nix { };
        in
        {
          # macOS appearance is NOT a `defaults` key you can write, however much
          # it looks like one. Measured on macOS 26.6, 2026-08-08:
          # `defaults write -g AppleInterfaceStyle Dark` from a light session and
          # `defaults delete -g AppleInterfaceStyle` from a dark one BOTH change
          # nothing — before or after `activateSettings -u`, and not even for a
          # process launched fresh afterwards, with no
          # AppleInterfaceThemeChangedNotification posted either time. The key is
          # a mirror the appearance system writes on its way past, not a lever.
          # That is why this is an activation script and not a
          # `system.defaults.NSGlobalDomain` entry — and why
          # modules/lib/restart-map.nix has no restart to offer for it: there is
          # no write to make live. (`haus diff` warns if a host declares that key
          # by hand, the same way it warns about com.apple.Accessibility.)
          #
          # System Events flips it live in ~0.3s and posts the notification, so
          # running apps repaint. Two guards:
          #
          #   - Read hausax FIRST and skip when it already matches. Without this
          #     every rebuild re-posts the appearance-changed notification and
          #     every running app repaints for nothing.
          #   - Driving System Events needs an Automation grant for whichever app
          #     runs the rebuild. Refusal must degrade to "the appearance didn't
          #     move", never abort activation and take every launchd service with
          #     it — the same failure shape den's FDA-guarded accessibility block
          #     exists to avoid.
          home.activation.nebelhausSystemAppearance = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            appearanceHave="$(${hausax}/bin/hausax 2>/dev/null | ${pkgs.jq}/bin/jq -r '.appearance // empty' || true)"
            if [ "$appearanceHave" = "${appearanceWanted}" ]; then
              verboseEcho "system appearance: already ${appearanceWanted}"
            elif run /usr/bin/osascript -e \
                 'tell application "System Events" to tell appearance preferences to set dark mode to ${
                   lib.boolToString (appearanceWanted == "dark")
                 }'; then
              echo "system appearance: ${appearanceWanted}" >&2
            else
              echo "warning: could not set macOS appearance to ${appearanceWanted} — System Events needs an Automation grant for the app running this rebuild (System Settings ▸ Privacy & Security ▸ Automation). Appearance left as-is; nothing else was affected." >&2
            fi
          '';
        };
    })

    (lib.mkIf (choice != "none") {
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
    })
  ];
}

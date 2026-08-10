# Theme — the whole-desktop surface the per-tool palette wiring doesn't touch.
# The accent (haus.theme.accent) lives in options.nix and is consumed per-tool
# by hearth/sill/pounce; this room owns macOS's own Light/Dark appearance.
#
# The desktop picture used to live here too, as `haus.theme.wallpaper`. It moved
# to a room of its own (../wallpaper) when the generated `minimal` look landed:
# that desktop reads the palette, the accent, the tiling gaps and the flake's own
# lock edges, which is more than one enum on the theme can carry.
# ../renamed.nix keeps the old name working.
#
# haus.theme.systemAppearance defaults to "unmanaged" — nothing moves unless a
# host (or the bootstrap interview) opts in — and is applied with osascript for
# the reason spelled out in the block that applies it.
{
  config,
  lib,
  username,
  ...
}:

let
  # ---- macOS Light/Dark (haus.theme.systemAppearance) ------------------
  appearanceChoice = config.haus.theme.systemAppearance;
  # "flavor" resolves here rather than in the activation script so the built
  # system carries the ANSWER, not the rule — one less thing to be wrong at 3am
  # in a shell fragment.
  appearanceWanted =
    if appearanceChoice == "flavor" then
      (if config.haus.theme.flavor == "latte" then "light" else "dark")
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
  ];
}

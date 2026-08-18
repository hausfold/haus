# The behavioural projection for the rooms plan's desktop carve-out.
#
# Step 4 moves hacker's choices from option defaults into a data-only
# desktop. A derivation-path comparison is useful, but too opaque to explain a
# mismatch and unsafe to paste for a real consumer. This projection names the
# complete public surface whose effective values the move is allowed to affect.
# It contains no identity, secrets, hardware selectors or host paths.
#
# Keep `paths` explicit. Adding a field here is a reviewable schema change; a
# recursive walk over config.haus would silently start serialising future
# host-only options.
{
  lib,
  pkgs,
}:

let
  version = 1;

  paths = [
    [
      "ai"
      "enable"
    ]
    [
      "ai"
      "clients"
    ]
    [
      "ai"
      "default"
    ]
    [
      "apps"
      "videoPlayer"
      "enable"
    ]
    [
      "apps"
      "videoPlayer"
      "claimFileTypes"
    ]
    [
      "security"
      "touchId"
      "enable"
    ]
    [
      "security"
      "touchId"
      "passwordlessRebuild"
    ]
    [
      "developer"
      "enable"
    ]
    [
      "developer"
      "languages"
    ]
    [
      "fonts"
      "mono"
      "name"
    ]
    [
      "fonts"
      "mono"
      "size"
    ]
    # The proportional half, for the same reason the editor pair is here in
    # full: it is desktop-safe, so a desktop can move it, and a projection that
    # names one family and not the other reports "no difference" for a machine
    # whose clock changed face.
    [
      "fonts"
      "sans"
      "name"
    ]
    [
      "terminal"
      "floatBorder"
    ]
    [
      "terminal"
      "editor"
    ]
    # Both halves of the editor pair, deliberately. `editor` alone would go
    # blind exactly where it matters: a host that pins the command while a
    # desktop moves the NAME still changes which editor is installed, and the
    # projection would report no difference at all.
    [
      "terminal"
      "editorName"
    ]
    [
      "terminal"
      "rightClickFullscreen"
    ]
    [
      "terminal"
      "zellijStartLocked"
    ]
    [
      "focus"
      "enable"
    ]
    [
      "keys"
      "leader"
    ]
    [
      "keys"
      "palette"
    ]
    [
      "keys"
      "windowNav"
    ]
    [
      "shelf"
      "enable"
    ]
    [
      "launcher"
      "enable"
    ]
    [
      "launcher"
      "windowMode"
    ]
    [
      "windows"
      "enable"
    ]
    [
      "windows"
      "mouseFullscreen"
    ]
    [
      "bar"
      "enable"
    ]
    [
      "bar"
      "position"
    ]
    [
      "bar"
      "clock"
      "mode"
    ]
    [
      "bar"
      "items"
      "battery"
    ]
    [
      "bar"
      "items"
      "clock"
    ]
    [
      "bar"
      "items"
      "media"
    ]
    [
      "bar"
      "items"
      "weather"
    ]
    [
      "bar"
      "items"
      "wifi"
    ]
    [
      "bar"
      "logo"
      "gestures"
    ]
    [
      "bar"
      "logo"
      "icon"
    ]
    [
      "bar"
      "logo"
      "size"
    ]
    [
      "bar"
      "logo"
      "status"
    ]
    [
      "bar"
      "logo"
      "sweep"
    ]
    [
      "theme"
      "accent"
    ]
    [
      "theme"
      "contrast"
    ]
    [
      "theme"
      "flavor"
    ]
    [
      "theme"
      "ports"
      "enable"
    ]
    [
      "tour"
      "enable"
    ]
    [
      "wallpaper"
      "style"
    ]
    [
      "wallpaper"
      "size"
    ]
    [
      "wallpaper"
      "depth"
    ]
    [
      "wallpaper"
      "grain"
    ]
    [
      "wallpaper"
      "glow"
      "enable"
    ]
    [
      "wallpaper"
      "glow"
      "spread"
    ]
    [
      "wallpaper"
      "glow"
      "strength"
    ]
    [
      "wallpaper"
      "mark"
      "enable"
    ]
    [
      "wallpaper"
      "mark"
      "color"
    ]
    [
      "wallpaper"
      "mark"
      "opacity"
    ]
    [
      "wallpaper"
      "mark"
      "rise"
    ]
    [
      "wallpaper"
      "mark"
      "size"
    ]
    [
      "wallpaper"
      "mark"
      "weight"
    ]
  ];

  key = path: "haus.${lib.concatStringsSep "." path}";
in
{
  inherit version paths;

  project = config: {
    schema = version;
    values = lib.listToAttrs (
      map (path: {
        name = key path;
        value = lib.attrByPath path (throw "desktop projection is missing ${key path}") config.haus;
      }) paths
    );

    # The font FAMILY can be named three ways (`package`, `packageName`, or
    # neither) and all three are allowed to change spelling as long as the
    # installed package does not. So project what actually gets installed
    # rather than which form selected it — the raw leaves above cannot see
    # that difference, and it is exactly the kind of "same value, different
    # package" regression this comparison exists to catch.
    effective.monoFontPackage =
      let
        package = import ../modules/lib/mono-font.nix {
          inherit lib pkgs;
          fonts = config.haus.fonts;
        };
      in
      package.pname or package.name;
  };
}

# displays — the size of everything, from macOS's side.
#
# `nebelhaus.ui.scale` and `nebelhaus.fonts` make the RICE bigger: the terminal,
# the bar, the Dock, the gaps. They can't touch Mail, Safari, or an app nobody
# here has heard of. macOS's own text-size settings can, in theory — but the sweep
# in the workshop's notes/macos-settings-matrix.md found every one of them either
# locked to a preference domain that refuses writes during activation, or writing a
# value that lands in the plist and is never re-read (System Settings then renders
# a desynced view of its own rows, which is worse than not shipping the option).
#
# Display scaling is what's left, and it works: public CoreGraphics, no Homebrew
# dependency, effective for every app on the machine because it changes what a
# point means. That makes this room the missing half of `presets/large-print.nix`
# — the preset could describe how the rice looks, but not how big the Mac is.
#
# Two deliberate choices:
#
#   * `hausdisp` is installed even when no display is configured. It's read-only
#     until you ask it to apply something, and you need `hausdisp list` to find a
#     monitor's UUID *before* you can write the option that uses it — gating the
#     binary on the option would make the option undiscoverable.
#
#   * The apply runs as a home-manager activation, not a system one. A display
#     configuration belongs to a logged-in GUI session; the system activation runs
#     as root outside it, where a mode change either fails or lands on the wrong
#     session. Same reason the wallpaper is set from home-manager (theme/).
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  hausdisp = pkgs.callPackage ./package.nix { };

  displays = config.nebelhaus.displays;

  # Only entries that actually ask for something. `displays.foo = { }` declares a
  # display without an opinion about it, which is a no-op rather than an error —
  # there'll be more per-display settings than uiScale eventually.
  configured = lib.filterAttrs (_: d: d.uiScale != null) displays;

  # A selector is `internal`, `main`, or a display UUID. Caught at eval because
  # the failure mode otherwise is invisible: hausdisp would report "no attached
  # display matches 'external'" once per rebuild, which reads exactly like an
  # unplugged monitor, and the typo would live in the host file for months.
  isUUID = name: builtins.match "[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}" name != null;
  validSelector = name: name == "internal" || name == "main" || isUUID name;
  badSelectors = lib.filter (name: !validSelector name) (lib.attrNames displays);
in
{
  assertions = [
    {
      assertion = badSelectors == [ ];
      message =
        "nebelhaus.displays: ${lib.concatStringsSep ", " (map (n: "\"${n}\"") badSelectors)} "
        + "is not a display selector. Use \"internal\", \"main\", or a persistent "
        + "display UUID (run `hausdisp list` to print the UUIDs of the displays "
        + "attached right now).";
    }
  ];

  environment.systemPackages = [ hausdisp ];

  # Takes home-manager's own `lib` (the outer one has no `lib.hm.dag`), like the
  # wallpaper activation in theme/ does.
  home-manager.users.${username} =
    { lib, ... }:
    {
      home.activation = lib.mapAttrs' (
        selector: display:
        lib.nameValuePair "nebelhausDisplay-${lib.replaceStrings [ ":" ] [ "-" ] selector}" (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            # Exit 2 means "that display isn't attached", which is not a problem
            # worth failing a rebuild over; hausdisp has already said so on stderr.
            run ${hausdisp}/bin/hausdisp apply ${lib.escapeShellArg selector} ${lib.escapeShellArg display.uiScale} || run true
          ''
        )
      ) configured;
    };
}

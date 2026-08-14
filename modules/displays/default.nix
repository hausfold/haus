# displays — the size of everything, from macOS's side.
#
# `haus.ui.scale` and `haus.fonts` make the RICE bigger: the terminal,
# the bar, the Dock, the gaps. They can't touch Mail, Safari, or an app nobody
# here has heard of. macOS's own text-size setting writes a value that running
# apps never re-read (System Settings then renders a desynced view of its own
# rows, which is worse than not shipping the option). The accessibility scalars
# that do work are FDA-gated and affect contrast or motion, not system-wide size.
#
# Display scaling is what's left, and it works: public CoreGraphics, no Homebrew
# dependency, effective for every app on the machine because it changes what a
# point means. That makes this room the missing half of
# `haus.appearance.largePrint` — the rest of that profile says how the rice
# looks, and only this line says how big the Mac is.
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
#     session. Same reason the wallpaper is set from home-manager (wallpaper/).
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  hausdisp = pkgs.callPackage ./package.nix { };

  displays = config.haus.displays;

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

  activationName = selector: "nebelhausDisplay-${lib.replaceStrings [ ":" ] [ "-" ] selector}";

  # Broad selectors run before specific ones. `large-print` sets `main`, while a
  # host may add `internal` or a UUID for the panel it actually owns; without DAG
  # edges both entries can resolve to the same display and whichever happens to
  # run last wins. UUID is the most specific selector, then internal, then main.
  predecessors =
    selector:
    [ "writeBoundary" ]
    ++ lib.optional (selector != "main" && configured ? main) (activationName "main")
    ++ lib.optional (isUUID selector && configured ? internal) (activationName "internal");
in
{
  assertions = [
    {
      assertion = badSelectors == [ ];
      message =
        "haus.displays: ${lib.concatStringsSep ", " (map (n: "\"${n}\"") badSelectors)} "
        + "is not a display selector. Use \"internal\", \"main\", or a persistent "
        + "display UUID (run `hausdisp list` to print the UUIDs of the displays "
        + "attached right now).";
    }
  ];

  environment.systemPackages = [ hausdisp ];

  # Takes home-manager's own `lib` (the outer one has no `lib.hm.dag`), like the
  # wallpaper activation in wallpaper/ does.
  home-manager.users.${username} =
    { lib, ... }:
    {
      home.activation = lib.mapAttrs' (
        selector: display:
        lib.nameValuePair (activationName selector) (
          lib.hm.dag.entryAfter (predecessors selector) ''
            # Exit 2 means "that display isn't attached", which is not a problem
            # worth failing a rebuild over; hausdisp has already said so on stderr.
            # Every other failure is real and must fail activation rather than
            # leave the display unchanged while the rebuild reports success.
            if run ${hausdisp}/bin/hausdisp apply ${lib.escapeShellArg selector} ${lib.escapeShellArg display.uiScale}; then
              :
            else
              hausdisp_status=$?
              if [ "$hausdisp_status" -ne 2 ]; then
                exit "$hausdisp_status"
              fi
            fi
          ''
        )
      ) configured;
    };
}

# displays — the size of everything, from macOS's side.
#
# `haus.ui.scale` and `haus.fonts` make HAUS bigger: the terminal,
# the bar, the Dock, the gaps. They can't touch Mail, Safari, or an app nobody
# here has heard of. macOS's own text-size setting writes a value that running
# apps never re-read (System Settings then renders a desynced view of its own
# rows, which is worse than not shipping the option). The accessibility scalars
# that do work are FDA-gated and affect contrast or motion, not system-wide size.
#
# Display scaling is what's left, and it works: public CoreGraphics, no Homebrew
# dependency, effective for every app on the machine because it changes what a
# point means. That makes this room the missing half of
# `haus.appearance.largePrint` — the rest of that profile says how haus
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
  swiftBin = pkgs.callPackage ../lib/swift-bin.nix { };

  # haus's display-mode helper. See hausdisp.swift for what it does and why the
  # mode ladder is derived rather than tabulated.
  hausdisp = swiftBin {
    name = "hausdisp";
    src = ./hausdisp.swift;
    description = "Set a display's scaled resolution by intent (haus.displays)";
  };

  displays = config.haus.displays;

  # Only entries that actually ask for something. `displays.foo = { }` declares a
  # display without an opinion about it, which is a no-op rather than an error —
  # there'll be more per-display settings than uiScale eventually.
  configured = lib.filterAttrs (_: d: d.uiScale != null) displays;

  # The entries that ask WHERE a display sits relative to another.
  arranged = lib.filterAttrs (_: d: d.arrangement != null) displays;
  isHorizontalSide =
    side:
    builtins.elem side [
      "right-of"
      "left-of"
    ];
  alignsFor =
    side:
    if isHorizontalSide side then
      [
        "top"
        "center"
        "bottom"
      ]
    else
      [
        "left"
        "center"
        "right"
      ];

  # null align resolves to the shared edge — top for a horizontal side, left
  # for a vertical one — in Nix, so hausdisp takes one resolved word.
  arrangementAlign =
    selector:
    let
      a = arranged.${selector}.arrangement;
    in
    if a.align != null then
      a.align
    else if isHorizontalSide a.side then
      "top"
    else
      "left";

  # Follow `of` from one arranged entry to the next. The relations form a chain
  # (the desk is built beside its neighbour), so a cycle is a desk that cannot
  # be placed in any order — caught at eval rather than wedging the DAG.
  arrangementCycleFrom =
    name: seen:
    let
      next = arranged.${name}.arrangement.of;
    in
    if !arranged ? ${next} then
      null
    else if builtins.elem next seen then
      next
    else
      arrangementCycleFrom next (seen ++ [ next ]);

  # Every per-entry arrangement refusal, as assertion messages.
  arrangementProblems = lib.mapAttrsToList (
    selector: display:
    let
      a = display.arrangement;
      badOf = a.of == selector;
      badOfGrammar = !validSelector a.of;
      badAlign = a.align != null && !builtins.elem a.align (alignsFor a.side);
      # A self-reference already refused above needs no second sentence.
      cycle = if badOf then null else arrangementCycleFrom selector [ selector ];
    in
    (
      if badOf then
        [
          "haus.displays.\"${selector}\".arrangement.of names the display itself — a relation needs two panels"
        ]
      else
        [ ]
    )
    ++ (
      if badOfGrammar then
        [
          (
            "haus.displays.\"${selector}\".arrangement.of = \"${a.of}\" is not a display selector. "
            + "Use \"internal\", \"main\", or a persistent display UUID (run `hausdisp list`)"
          )
        ]
      else
        [ ]
    )
    ++ (
      if badAlign then
        [
          (
            "haus.displays.\"${selector}\".arrangement.align = \"${a.align}\" does not fit side \"${a.side}\". "
            + "Want: ${lib.concatStringsSep " | " (alignsFor a.side)}"
          )
        ]
      else
        [ ]
    )
    ++ (
      if cycle != null then
        [
          (
            "haus.displays.\"${selector}\".arrangement is part of a cycle through \"${cycle}\" — "
            + "displays cannot be built beside each other in a circle"
          )
        ]
      else
        [ ]
    )
  ) arranged;

  # A selector is `internal`, `main`, or a display UUID. Caught at eval because
  # the failure mode otherwise is invisible: hausdisp would report "no attached
  # display matches 'external'" once per rebuild, which reads exactly like an
  # unplugged monitor, and the typo would live in the host file for months.
  isUUID = name: builtins.match "[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}" name != null;
  validSelector = name: name == "internal" || name == "main" || isUUID name;
  badSelectors = lib.filter (name: !validSelector name) (lib.attrNames displays);

  activationName = selector: "hausDisplay-${lib.replaceStrings [ ":" ] [ "-" ] selector}";

  # A display with BOTH a uiScale and an arrangement gets two activations, so
  # the two can't share a name: the scale one is `hausDisplay-…`, this one is
  # `hausDisplayArrangement-…`, and the arrangement's edges name the scale
  # entries through `activationName`.
  arrangementActivationName =
    selector: "hausDisplayArrangement-${lib.replaceStrings [ ":" ] [ "-" ] selector}";

  # Broad selectors run before specific ones. `large-print` sets `main`, while a
  # host may add `internal` or a UUID for the panel it actually owns; without DAG
  # edges both entries can resolve to the same display and whichever happens to
  # run last wins. UUID is the most specific selector, then internal, then main.
  predecessors =
    selector:
    [ "writeBoundary" ]
    ++ lib.optional (selector != "main" && configured ? main) (activationName "main")
    ++ lib.optional (isUUID selector && configured ? internal) (activationName "internal");

  # Arrangement runs after EVERY uiScale entry: origins are in points, and a
  # scale change moves every origin, so the arithmetic must see final sizes.
  # One arrangement also follows another when its `of` names a display that is
  # itself placed — a desk built in relations, edge by edge.
  arrangementPredecessors =
    selector:
    [ "writeBoundary" ]
    ++ map activationName (lib.attrNames configured)
    ++ lib.optional (arranged ? ${arranged.${selector}.arrangement.of}) (
      arrangementActivationName (arranged.${selector}.arrangement.of)
    );

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
  ]
  ++ map (message: {
    assertion = false;
    inherit message;
  }) (lib.flatten arrangementProblems);

  environment.systemPackages = [ hausdisp ];

  # Takes home-manager's own `lib` (the outer one has no `lib.hm.dag`), like the
  # wallpaper activation in wallpaper/ does.
  home-manager.users.${username} =
    { lib, ... }:
    {
      home.activation =
        (lib.mapAttrs' (
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
        ) configured)
        // (lib.mapAttrs' (
          selector: display:
          lib.nameValuePair (arrangementActivationName selector) (
            let
              a = display.arrangement;
            in
            lib.hm.dag.entryAfter (arrangementPredecessors selector) ''
              # Exit 2 means "one of the two displays isn't attached" — an undocked
              # desk has no such arrangement, and macOS remembers its own until the
              # next activation after the dock returns. Every other failure is real.
              if run ${hausdisp}/bin/hausdisp arrange ${lib.escapeShellArg selector} ${lib.escapeShellArg a.side} ${lib.escapeShellArg a.of} ${lib.escapeShellArg (arrangementAlign selector)}; then
                :
              else
                hausdisp_status=$?
                if [ "$hausdisp_status" -ne 2 ]; then
                  exit "$hausdisp_status"
                fi
              fi
            ''
          )
        ) arranged);
    };
}

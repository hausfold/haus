# Which macOS settings a desktop actually WRITES, and who asked for it.
#
# The ten curated settings groups (roadmap §5.6) share one policy, stated once
# for all of them: every leaf defaults to "write nothing" — `null`, or
# `"system"` for `haus.animations` — because a `defaults` write is ONE-WAY.
# Setting a leaf back to its default stops writing; it cannot restore, since
# macOS keeps no memory of the value it overwrote. So a group that ships on by
# default doesn't express an opinion, it destroys one, on every machine already
# running.
#
# That policy is written about DECLARATIONS and read as a promise about
# MACHINES, and on 2026-08-22 the two came apart: `haus.shelf.watchScreenshots`
# sets `haus.screenshots.thumbnail = mkDefault false` from inside the shelf
# room, so the leaf still declares `null`, the generated reference still prints
# `null`, and two of the four shipping desktops write the key anyway. Every
# surface was honest and none of them holds the PRODUCT of the two.
#
# This is that product. For each shipping desktop it resolves all 66 leaves and
# reports every one that comes out non-quiet, naming the file that supplied the
# value — because the failure is only legible as a pair, and whoever trips it
# will be standing in a room that has never heard of §5.6.
#
# A row here is not automatically a bug. A desktop naming a leaf in its own
# file is the whole point of a desktop. What the table exists to catch is the
# other author: a ROOM, reached by some unrelated `enable`, quietly deciding a
# macOS setting on a machine that asked it nothing. Those rows are marked
# `room:` and each one in the expected table had to be argued for.
{
  lib,
  root,
}:

let
  # Explicit, like test/desktop-projection.nix's `paths`, and for the same
  # reason: a recursive walk would silently start covering leaves nobody
  # decided this policy applies to. The inventory is the ten groups of §5.6 —
  # `modules/options-groups.nix`'s `optionPaths` for the eight whole
  # namespaces, and the settings subtrees only for the two namespaces that
  # also hold room behaviour (`security` keeps `touchId`, `windows` keeps
  # AeroSpace).
  #
  # `quiet` is the value that means "write nothing". It is `null` for 65 of
  # the 66; `haus.animations` spells the same thing `"system"`, and it is the
  # namespace option itself rather than a leaf under one, so its path is [ ].
  group =
    quiet: prefix: leaves:
    map (l: {
      path = prefix ++ l;
      inherit quiet;
    }) leaves;

  nullGroup = group null;

  leaves =
    nullGroup
      [ "hotCorners" ]
      [
        [ "bottomLeft" ]
        [ "bottomRight" ]
        [ "topLeft" ]
        [ "topRight" ]
      ]
    ++
      nullGroup
        [ "screenshots" ]
        [
          [ "format" ]
          [ "includeDate" ]
          [ "location" ]
          [ "shadow" ]
          [ "thumbnail" ]
        ]
    ++
      nullGroup
        [ "lock" ]
        [
          [
            "login"
            "hideRestart"
          ]
          [
            "login"
            "hideShutDown"
          ]
          [
            "login"
            "hideSleep"
          ]
          [
            "login"
            "message"
          ]
          [
            "login"
            "showNameField"
          ]
          [ "requirePassword" ]
          [ "requirePasswordDelay" ]
        ]
    ++
      nullGroup
        [ "menuBar" ]
        [
          [
            "clock"
            "analog"
          ]
          [
            "clock"
            "format"
          ]
          [
            "clock"
            "showDate"
          ]
          [
            "clock"
            "showDayOfWeek"
          ]
          [
            "clock"
            "showSeconds"
          ]
          [
            "controlCenter"
            "airdrop"
          ]
          [
            "controlCenter"
            "batteryPercentage"
          ]
          [
            "controlCenter"
            "bluetooth"
          ]
          [
            "controlCenter"
            "displayBrightness"
          ]
          [
            "controlCenter"
            "focus"
          ]
          [
            "controlCenter"
            "nowPlaying"
          ]
          [
            "controlCenter"
            "sound"
          ]
        ]
    ++
      nullGroup
        [ "sound" ]
        [
          [ "alertSound" ]
          [ "alertVolume" ]
          [ "startupChime" ]
          [ "uiSounds" ]
          [ "volumeFeedback" ]
        ]
    ++
      nullGroup
        [ "locale" ]
        [
          [ "hourFormat" ]
          [ "inputSources" ]
          [ "language" ]
          [ "metric" ]
          [ "region" ]
          [ "temperature" ]
        ]
    ++
      nullGroup
        [ "power" ]
        [
          [
            "computerSleep"
            "battery"
          ]
          [
            "computerSleep"
            "charger"
          ]
          [
            "diskSleep"
            "battery"
          ]
          [
            "diskSleep"
            "charger"
          ]
          [
            "displaySleep"
            "battery"
          ]
          [
            "displaySleep"
            "charger"
          ]
          [
            "lowPowerMode"
            "battery"
          ]
          [
            "lowPowerMode"
            "charger"
          ]
        ]
    # `security` also holds `touchId`, which is a room's behaviour and not a
    # curated macOS setting — the firewall half and the guest account are.
    ++
      nullGroup
        [ "security" ]
        [
          [
            "firewall"
            "allowSigned"
          ]
          [
            "firewall"
            "allowSignedApp"
          ]
          [
            "firewall"
            "blockAllIncoming"
          ]
          [
            "firewall"
            "enable"
          ]
          [
            "firewall"
            "stealthMode"
          ]
          [ "guestAccount" ]
        ]
    # `windows` is the one settings group that lives in a room, so only its
    # three `com.apple.WindowManager` subtrees are in scope; the tiler's own
    # leaves (gravity, defaultLayout, numberedWorkspaces, …) are not.
    ++
      nullGroup
        [ "windows" ]
        [
          [
            "desktop"
            "clickToReveal"
          ]
          [
            "desktop"
            "hideIcons"
          ]
          [
            "desktop"
            "hideWidgets"
          ]
          [
            "nativeTiling"
            "edgeDrag"
          ]
          [
            "nativeTiling"
            "margins"
          ]
          [
            "nativeTiling"
            "optionAccelerator"
          ]
          [
            "nativeTiling"
            "topEdgeFullscreen"
          ]
          [
            "stageManager"
            "autoHideStrip"
          ]
          [
            "stageManager"
            "enable"
          ]
          [
            "stageManager"
            "groupWindows"
          ]
          [
            "stageManager"
            "hideDesktopIcons"
          ]
          [
            "stageManager"
            "hideWidgets"
          ]
        ]
    ++ group "system" [ ] [ [ "animations" ] ];

  # Under `nix flake check` every declaration path is a /nix/store path that
  # moves with each commit. Root-relative keeps the part that decides the
  # verdict — WHICH file — and keeps the table stable. Same trick, same
  # reason, as `desktopHere` in flake.nix.
  here = builtins.replaceStrings [ "${toString root}/" ] [ "" ];

  render =
    v:
    if v == null then
      "null"
    else if builtins.isBool v then
      (if v then "true" else "false")
    else if builtins.isList v then
      "[" + builtins.concatStringsSep "," (map render v) + "]"
    else
      builtins.toString v;

in
{
  inherit leaves;

  # One line per (desktop, leaf) whose resolved value is not the quiet one:
  #
  #   <desktop> <leaf> = <value> <origin>:<file>
  #
  # `origin` is `desktop` when the desktop file itself names the leaf — the
  # ordinary case, and the reason a desktop exists — and `room:` when some
  # other module in the tree supplied it, which is the case §5.6's policy
  # never addressed and the one worth arguing about.
  rows =
    {
      name,
      config,
      options,
    }:
    let
      row =
        leaf:
        let
          value = lib.getAttrFromPath ([ "haus" ] ++ leaf.path) config;
          opt = lib.getAttrFromPath ([ "haus" ] ++ leaf.path) options;
          files = lib.unique (map (d: here (toString d.file)) opt.definitionsWithLocations);
          desktopFile = "desktops/${name}.nix";
          origin = if builtins.elem desktopFile files then "desktop" else "room";
          others = builtins.filter (f: f != desktopFile) files;
          shown = if origin == "desktop" then [ desktopFile ] else others;
        in
        lib.optional (value != leaf.quiet) (
          "${name} haus.${builtins.concatStringsSep "." leaf.path} = ${render value}"
          + " ${origin}:${builtins.concatStringsSep "+" shown}"
        );
    in
    builtins.concatMap row leaves;
}

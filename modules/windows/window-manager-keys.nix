# The `com.apple.WindowManager` half of the windows room, as one table: the plist
# key macOS stores, and the `haus.windows.*` path that sets it.
#
# Two files read it and neither may restate it — the same shape hot-corners.nix
# already has, and for the same reason: an enum and a lookup written twice can
# disagree, and here the disagreement would be silent in both directions.
#
#   ./options.nix    declares the options, and `mkWindowManagerOption` refuses a
#                    plist key this table doesn't carry — so an option can't be
#                    written for a key nothing will ever write.
#   ./default.nix    walks this table to build the `system.defaults.WindowManager`
#                    block, reading each option by its path here — so a table
#                    entry with no option fails at eval rather than quietly
#                    writing nothing.
#
# Keys are macOS's own spelling (nix-darwin's `system.defaults.WindowManager.*`
# uses the same), values are the path under `haus.windows`. The option names are
# deliberately NOT the plist names: `GloballyEnabled` says nothing about Stage
# Manager, and `HideDesktop` vs `StandardHideDesktopIcons` is a pair no one can
# tell apart from the key alone (the first is Stage-Manager-only, the second is
# always) — which is exactly the kind of thing a curated group exists to fix.
{
  # ---- Stage Manager -------------------------------------------------------
  GloballyEnabled = [
    "stageManager"
    "enable"
  ];
  AutoHide = [
    "stageManager"
    "autoHideStrip"
  ];
  AppWindowGroupingBehavior = [
    "stageManager"
    "groupWindows"
  ];
  # macOS's confusing pair, disambiguated by the option name rather than by a
  # comment nobody reads at the call site: HideDesktop is the Stage-Manager-only
  # one, StandardHideDesktopIcons is the always one.
  HideDesktop = [
    "stageManager"
    "hideDesktopIcons"
  ];
  StageManagerHideWidgets = [
    "stageManager"
    "hideWidgets"
  ];

  # ---- macOS's own tiling --------------------------------------------------
  EnableTilingByEdgeDrag = [
    "nativeTiling"
    "edgeDrag"
  ];
  EnableTopTilingByEdgeDrag = [
    "nativeTiling"
    "topEdgeFullscreen"
  ];
  EnableTilingOptionAccelerator = [
    "nativeTiling"
    "optionAccelerator"
  ];
  EnableTiledWindowMargins = [
    "nativeTiling"
    "margins"
  ];

  # ---- the desktop itself --------------------------------------------------
  EnableStandardClickToShowDesktop = [
    "desktop"
    "clickToReveal"
  ];
  StandardHideDesktopIcons = [
    "desktop"
    "hideIcons"
  ];
  StandardHideWidgets = [
    "desktop"
    "hideWidgets"
  ];
}

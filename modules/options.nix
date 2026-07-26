# Host-provided identity. These are the values that are personal to YOU rather
# than part of the rice — a host file (see hosts/example) sets them.
{ lib, ... }:

let
  appType = lib.types.submodule {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether this app participates in the shared launcher roster.";
      };
      order = lib.mkOption {
        type = lib.types.int;
        default = 1000;
        description = "Roster order; lower values appear first. Ties are sorted by app id.";
      };
      key = lib.mkOption {
        type = lib.types.str;
        example = "s";
        description = ''
          The leader letter for this app: tap Caps Lock then this key to
          launch/focus it. Must be unique across the roster.
        '';
      };
      name = lib.mkOption {
        type = lib.types.str;
        example = "Slack";
        description = "macOS application name, as passed to `open -a`.";
      };
      workspace = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "S";
        description = ''
          The AeroSpace workspace this app owns — its window auto-moves
          here, it gets a SketchyBar pill, and ⌥⇧<key> throws a window to
          it. null makes the app "launcher-only": the leader still opens
          it in the current workspace, but it claims no workspace, pill,
          or auto-assign rule (e.g. Passwords).
        '';
      };
      appId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "com.tinyspeck.slackmacgap";
        description = ''
          Bundle id, used for the AeroSpace `on-window-detected`
          auto-assign rule and the wake-time re-sort. null skips
          auto-assignment (the app still launches, it just isn't herded
          to its workspace). Find one with `osascript -e 'id of app "…"'`.
        '';
      };
      barIcon = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = ":slack:";
        description = ''
          The SketchyBar workspace-pill glyph. A sketchybar-app-font
          ligature like ":slack:" renders the app's logo; any other
          string is drawn in the bar's Nerd Font. null falls back to the
          workspace letter. Ignored when workspace is null.
        '';
      };
      label = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "Slack";
        description = "Cheatsheet caption for the leader key. null uses name.";
      };
      cask = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "slack";
        description = ''
          Homebrew cask that installs this app. When set, it's appended to
          homebrew.casks so declaring the app also installs it. null means
          "already present / installed some other way" (e.g. Safari, Music).
        '';
      };
    };
  };
in
{
  options.nebelhaus = {
    apps = lib.mkOption {
      type = lib.types.attrsOf appType;
      default = { };
      example = lib.literalExpression ''
        {
          slack = {
            key = "s";
            name = "Slack";
            workspace = "S";
            appId = "com.tinyspeck.slackmacgap";
            barIcon = ":slack:";
            cask = "slack";
          };
        }
      '';
      description = ''
        The shared app roster, keyed by a stable app id. This is the canonical,
        composable source for AeroSpace launcher keys and workspaces,
        SketchyBar pills, the pounce cheatsheet, and optional Homebrew casks.

        Attribute-set entries merge across Nix modules, so a host, an imported
        file, and pounce's "Install App" command can each contribute one app
        without parsing or replacing a monolithic list. Set an entry's enable
        field to false to remove it, or override individual fields by app id.
      '';
    };

    # Normalized by modules/prowl. Kept internal so every room consumes the same
    # ordered list while the public API stays keyed and composable.
    _apps = lib.mkOption {
      type = lib.types.listOf appType;
      internal = true;
      readOnly = true;
      description = "Resolved, enabled app roster used internally by nebelhaus modules.";
    };
  };
}

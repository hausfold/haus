# Host-provided identity. These are the values that are personal to YOU rather
# than part of the rice — a host file (see hosts/example) sets them.
{ lib, config, ... }:

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

    # ---- the developer pack ----
    # Lives here rather than in a room because it cuts across two: den's CLI
    # tools and hearth's shell programs.
    #
    # Until this existed, "minimal" was a lie — turning off prowl, sill and
    # pounce still installed bun, fnm, nixfmt, opencode, lazygit, delta, gh and
    # the agent-worktree tooling, because den and hearth are imported
    # unconditionally. A Mac for someone who doesn't write code could not be
    # expressed at all.
    developer = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = false;
        description = ''
          The developer pack: the CLI toolbelt, Git tooling, coding-agent
          tooling, and language runtimes. On (the default) is the rice as it
          has always been.

          `false` is what makes a non-developer nebelhaus possible — it strips
          those tools rather than merely hiding them. What remains is the
          product: `haus`, `awake`, the theme, the terminal, the bar, the tiler
          and the palette.

          The sub-options below each default to THIS value, so turning it off
          turns everything off and you can then re-enable one piece:

            nebelhaus.developer.enable = false;
            nebelhaus.developer.git.enable = true;  # …but keep git
        '';
      };

      git.enable = lib.mkOption {
        type = lib.types.bool;
        default = config.nebelhaus.developer.enable;
        defaultText = lib.literalExpression "config.nebelhaus.developer.enable";
        description = ''
          Git and its surroundings: the shell alias vocabulary, the themed git
          config, delta (diff pager), lazygit, `gh`, and gnupg for commit
          signing. Off drops all of them, and `nebelhaus.git.*` then has
          nothing to configure.
        '';
      };

      toolbelt.enable = lib.mkOption {
        type = lib.types.bool;
        default = config.nebelhaus.developer.enable;
        defaultText = lib.literalExpression "config.nebelhaus.developer.enable";
        description = ''
          The terminal toolbelt: bat, fzf, fd, yazi, zoxide, lsd, glow, jq,
          tree, chafa, ttyd and fastfetch — the themed replacements for cat,
          find, ls and friends that the rice's shell is built around.

          Off leaves a plain shell. The prompt (starship) and the colour scheme
          stay: these are the *tools*, not the appearance.
        '';
      };

      agents.enable = lib.mkOption {
        type = lib.types.bool;
        default = config.nebelhaus.developer.enable;
        defaultText = lib.literalExpression "config.nebelhaus.developer.enable";
        description = ''
          Coding-agent tooling: `wt` (Claude Code agent worktrees), `zscratch`,
          the agent-worktree statusline, opencode, and the Claude Code settings
          and hooks hearth writes.

          Off is right for any machine not running coding agents — it's a large
          surface a non-developer never sees.
        '';
      };

      languages = lib.mkOption {
        type = lib.types.listOf (lib.types.enum [ "node" ]);
        default = lib.optionals config.nebelhaus.developer.enable [ "node" ];
        defaultText = lib.literalExpression ''[ "node" ] when developer.enable is true, else [ ]'';
        example = [ ];
        description = ''
          Language runtimes to install. Currently only "node" (bun + fnm, with
          fnm's `--use-on-cd` shell hook).

          Deliberately a list rather than one bool per language, so adding
          "rust" or "python" later doesn't change this option's shape.
        '';
      };
    };
  };
}

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
          here, it gets a SketchyBar pill, and the leader then ⇧<key>
          throws a window to it. null makes the app "launcher-only": the
          leader still opens it in the current workspace, but it claims no
          workspace, pill, or auto-assign rule (e.g. Passwords).
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

    # ---- ui: one scale, fanned out ----
    # The missing abstraction. Before this, making the rice bigger meant finding
    # and tuning every size by hand in a different file each time.
    #
    # Honest scope, and it is narrower than "everything": this scales the things
    # nebelhaus itself controls and macOS lets it control — the terminal font,
    # the Dock, and the tiling gaps. It does NOT resize the menu bar (see the
    # note on ui.scale) and it cannot resize third-party apps; macOS has no
    # system-wide UI scale, so the OS-level lever is display resolution
    # (nebelhaus.displays, not built yet).
    ui.scale = lib.mkOption {
      type = lib.types.numbers.between 0.5 3.0;
      default = 1.0;
      example = 1.35;
      description = ''
        One number for "make the interface bigger". 1.0 is the rice as tuned;
        1.35 is a comfortable large-print setting; below 1.0 tightens things up.

        It sets the DEFAULT of the sizes it drives, so anything you pin by hand
        still wins:

          nebelhaus.ui.scale = 1.5;          # everything grows
          nebelhaus.fonts.mono.size = 18;    # …except the terminal, pinned here

        What it currently moves:

          - the terminal font size (nebelhaus.fonts.mono.size)
          - the Dock icon size (system.defaults.dock.tilesize)
          - prowl's window gaps

        What it deliberately does NOT move:

          - Sill's menu bar. Its height is tuned to sit inside the macOS
            menu-bar band so the hover-reveal covers it exactly; scaling that
            linearly breaks the alignment rather than making it bigger. The bar
            needs its own sizing pass, not a multiplier.
          - anything outside nebelhaus. macOS has no system-wide UI scale, so
            third-party apps follow only a display-resolution change.
      '';
    };

    # ---- keys: the keymap, opened up ----
    # Cross-cutting because the keymap is: `leader` and `windowNav` are prowl's
    # (AeroSpace chords + the Caps Lock remap), `palette` is pounce's (an
    # in-process hotkey), and the cheatsheet + the first-run tour describe all
    # three. Resolved once in modules/lib/keys.nix so a chord and the caption
    # documenting it come from the same row.
    #
    # Until this existed the keymap was closed: Caps Lock, ⌥, and ⌘Space were
    # baked in. That made three whole categories of rice unexpressible — mouse-
    # first (no leader at all), one-handed, and any NON-US KEYBOARD LAYOUT, where
    # ⌥+letter is how you type accented characters and so cannot belong to a
    # window manager.
    keys = {
      leader = lib.mkOption {
        type = lib.types.enum [
          "caps"
          "alt-space"
          "none"
        ];
        default = "caps";
        example = "none";
        description = ''
          What enters the launcher/leader mode — tap it, then a letter opens an
          app, a digit focuses a workspace, ⇧+either throws the focused window
          to that workspace, an arrow navigates, `-`/`=` resizes.

            - "caps" (default): Caps Lock. AeroSpace can't bind Caps Lock itself,
              so the rice remaps it to F18 with hidutil and binds that.
            - "alt-space": the leader without giving up Caps Lock. No remap at all.
            - "none": no leader. Caps Lock stays Caps Lock, launch mode is
              unreachable, and nothing is remapped — the setting for a mouse-first
              rice, or for a Mac you are handing to someone else. What the leader
              fronted is still reachable: apps through the palette, window moves
              through service mode's join-with and the palette's own commands.
              Workspace focus and the workspace throws go away with it — they
              live only in launch mode.

          The remap is re-applied at every activation and does not survive a
          reboot, so moving off "caps" ends it — at the latest, at next boot.

          Only meaningful with nebelhaus.prowl.enable (AeroSpace owns the modes).
        '';
      };

      palette = lib.mkOption {
        type = lib.types.enum [
          "cmd-space"
          "alt-space"
          "ctrl-space"
          "none"
        ];
        default = "cmd-space";
        example = "none";
        description = ''
          What opens the pounce command palette. Registered in-process by the
          daemon, so it's near-instant and doesn't go through AeroSpace.

          "cmd-space" (default) is the one value that also DISABLES Spotlight's
          own ⌘Space, because the two can't share it. Every other value leaves
          Spotlight alone — including "none", which hands the palette's job back
          to Spotlight entirely. That's a fix as much as an option: the rice used
          to take Spotlight's ⌘Space away unconditionally, even where nothing
          claimed it.

          Only meaningful with nebelhaus.pounce.enable.
        '';
      };

      windowNav = lib.mkOption {
        type = lib.types.enum [
          "alt"
          "ctrl-alt"
          "cmd-alt"
          "none"
        ];
        default = "alt";
        example = "ctrl-alt";
        description = ''
          The modifier vocabulary for prowl's window chords — one setting rather
          than a bind-per-action, because what people need to move is the
          modifier, not the letters. It drives focus (`<mod>` + hjkl), layouts
          (`<mod>` + `/` `,`), fullscreen, workspace back-and-forth, moving a
          workspace to the next monitor (`<mod>⇧⇥`), and entering service mode
          (`<mod>⇧;`). Anything that names a workspace — focusing one, or
          throwing the focused window there — hangs off `leader` instead, not
          this option.

          "alt" (default) is ⌥. The alternatives are for **non-US keyboard
          layouts**, where ⌥+letter types accented characters — a rice that owns
          ⌥+letter is unusable on those, which is the concrete reason this option
          exists.

          Whatever you pick, AeroSpace claims those chords **globally**, so they
          stop reaching whatever owned them inside a terminal. The surface is
          small now that the workspace throws moved to the leader: only hjkl,
          `/` `,`, `f`, `⇥`, `⇧⇥` and `⇧;`, none of which a roster letter can
          land on. (Under "ctrl-alt" that used to bite — the throws were `⌃⌥⇧` +
          an app's roster letter, so an app on `c` silently ate hearth's zellij
          `Ctrl Alt Shift c` in-place-agent bind. That collision is gone.)
          Nothing on a stock macOS collides either: the only ⌃⌥ system hotkeys
          are input-source switching (⌃⌥Space, off by default) and hyper-F13.

          "none" drops the modifier chords entirely: no focus/layout chords, no
          service mode. Combined with `leader = "none"` that's a rice where the
          tiler tiles and the keyboard is left alone — mouse-first. The cheatsheet
          follows, so it never advertises a key that does nothing.

          Only meaningful with nebelhaus.prowl.enable.
        '';
      };

      # The seam for leader actions that AREN'T "launch an app". The app roster
      # (nebelhaus.apps) already fronts a letter → open an app; this fronts a key
      # → run a command (a script, an AppleScript, a `things:///` open). Rendered
      # into AeroSpace's [mode.launch.binding] AND the pounce cheatsheet from this
      # one list, so a binding and its caption can't drift — the same guarantee the
      # roster gives. Kept a flat list rather than nested under an app entry on
      # purpose: a leader action is not an attribute of any one app (the target may
      # be no app at all), and launch-mode keys must be globally unique — an
      # assertion in modules/prowl catches a key that collides with a roster letter
      # or a built-in launch key.
      leaderExtras = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            key = lib.mkOption {
              type = lib.types.str;
              example = "enter";
              description = ''
                The AeroSpace key name pressed after the leader (e.g. "enter",
                "space", "period", or a letter). Must not collide with a roster
                app's key or a built-in launch-mode key (the digits 1-4, the
                arrows, `-`/`=`, `v`/`e`/`z`, `,`, `` ` ``, `/`, esc) — an
                assertion in modules/prowl catches a clash rather than letting one
                binding silently shadow another.
              '';
            };
            command = lib.mkOption {
              type = lib.types.str;
              example = "osascript -e 'tell application \"Things3\" to show quick entry panel'";
              description = ''
                The shell command run when the leader is followed by `key`; launch
                mode exits afterward. It's written verbatim into a small `/bin/sh`
                script that AeroSpace execs, so ordinary shell rules apply — `$HOME`
                resolves, and single quotes (an `osascript -e '…'`, say) are safe,
                which they would not be inlined into AeroSpace's own config.
              '';
            };
            caption = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "Things Quick Entry";
              description = ''
                The Launch Mode cheatsheet caption for this action. null falls back
                to the raw command, which is rarely what you want — set it.
              '';
            };
          };
        });
        default = [ ];
        example = lib.literalExpression ''
          [
            {
              key = "enter";
              command = "osascript -e 'tell application \"Things3\" to show quick entry panel'";
              caption = "Things Quick Entry";
            }
          ]
        '';
        description = ''
          Extra launch-mode (leader) bindings beyond the app roster: tap the leader,
          then `key`, to run `command`. Use it for leader actions that aren't
          "launch an app" — a script, an AppleScript, opening a URL.

          Only meaningful with nebelhaus.prowl.enable and keys.leader != "none"
          (with no leader there is no launch mode to bind into).
        '';
      };
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

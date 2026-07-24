# Host-provided identity. These are the values that are personal to YOU rather
# than part of the rice — a host file (see hosts/example) sets them.
{ lib, ... }:

{
  options.nebelhaus = {
    git = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "Ada Lovelace";
        description = "Git user.name for commits (hearth wires it into home-manager).";
      };
      email = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "ada@example.com";
        description = "Git user.email for commits.";
      };
      signingKey = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "6F7BD6F43A7C1420";
        description = ''
          GPG key id for signing commits/tags. Empty disables commit signing.
          Key material + any YubiKey/smartcard setup live outside Nix
          (gpg-agent + pinentry-mac).
        '';
      };
      shellAliases = lib.mkOption {
        type = lib.types.attrsOf (lib.types.nullOr lib.types.str);
        default = { };
        example = lib.literalExpression ''
          {
            gst = "git status --short --branch"; # replace a built-in
            gsync = "git pull --rebase --autostash"; # add one
            gco = null; # remove one
          }
        '';
        description = ''
          Per-host additions and overrides for Hearth's built-in Git shell
          aliases. Values are shell command strings; null removes a built-in.
          Hearth deliberately owns a compact, framework-independent default
          set, so this changes only Git shortcuts and does not require a shell
          plugin manager.
        '';
      };
    };

    hearth.editor = lib.mkOption {
      type = lib.types.str;
      default = "hx";
      example = "nvim";
      description = ''
        The ONE editor the rice uses everywhere. It's the shell command for
        $EDITOR / $VISUAL (git, etc.) AND what every "open in an editor" action
        launches — the "Nix Config" palette command, the bar's nix-open item,
        and the file-association hijack. Those open the target in a new zellij
        tab running this command, so a terminal editor (hx, nvim, vim, nano) is
        the natural fit for the rice; a GUI editor's CLI works too (e.g. "code"
        or "code -w" to block).
      '';
    };

    hearth.hijackFileAssociations = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        When true, build a small opener app and make it the default handler
        for ~80 text/code extensions (json, md, ts, nix, rs, go, kdl, …), so
        opening or clicking those files opens them in nebelhaus.hearth.editor in
        a terminal tab. The app declares the types itself (not just `duti`) so
        extensions nothing else on the machine declares still bind. Off by
        default: silently rewriting your file associations is a jarring,
        hard-to-undo change, so it's strictly opt-in. (Extensionless executables
        like `bench` are NOT covered — macOS gates the public.unix-executable
        handler behind an interactive dialog; set it by hand once if wanted:
        `duti -s org.nebelhaus.editoropen public.unix-executable all`.)
      '';
    };

    hearth.obsidianVaults = lib.mkOption {
      type = lib.types.listOf (
        lib.types.addCheck lib.types.str (
          path:
          path != ""
          && !(lib.hasPrefix "/" path)
          && !(lib.any (component: component == "..") (lib.splitString "/" path))
        )
      );
      default = [ ];
      apply = lib.unique;
      example = [
        "Library/Mobile Documents/iCloud~md~obsidian/Documents/notes"
      ];
      description = ''
        Home-relative paths to existing Obsidian vaults that should use the
        Nebelung theme. On each activation, Hearth copies the rendered
        theme.css + manifest.json into each vault's .obsidian/themes/Nebelung/
        directory, selects Nebelung's dark appearance in appearance.json, and
        removes the obsolete "nebelung" CSS snippet from the enabled list.

        Empty (the default) leaves every vault untouched. Paths must be
        relative to the user's home, may not contain "..", and are skipped
        with a warning unless their .obsidian directory already exists.
      '';
    };

    hearth.zellijStartLocked = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        When true (the default), zellij boots into Locked input mode instead of
        Normal — its single-key submode leaders (pane, tab, resize, …) stay
        inert until you unlock with Ctrl-g, so a stray keystroke can't jump you
        into a submode. The `Super`-prefixed launchers (claude / pane / tab /
        yazi-peek / fullscreen) are bound in `shared` and keep working while
        locked; the bar's bottom-right quick-hint block only shows in Locked
        mode. Set false to start in Normal mode (zellij's own default).
      '';
    };

    claude.globalMd = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = ''
        # CLAUDE.md — global
        How I like to work across every repo…
      '';
      description = ''
        Contents of Claude Code's global memory file, written to
        ~/.claude/CLAUDE.md (hearth wires it into home-manager). This is your
        personal, cross-project operating context. When set, the rice prepends
        one short section of its own — the `wt child` worktree rule, since the
        rice ships `wt` and that rule is what keeps it working — then your text.
        Leave it empty to manage ~/.claude/CLAUDE.md fully by hand (nothing is
        written, so the rice never clobbers a by-hand file).
      '';
    };

    snippets = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Text expansion via espanso: type a short trigger (say "@@") and it's
          replaced inline with a longer string (your email), in any app —
          browsers, Messages, and the terminal. espanso injects keystrokes, so
          it works where macOS's own text replacement doesn't (terminals,
          many Electron apps).

          Off by default: it installs the Espanso.app cask and needs a one-time
          macOS Accessibility grant (System Settings → Privacy & Security →
          Accessibility → enable Espanso) the first time it runs. The rice runs
          the SIGNED app bundle rather than a nix-store binary on purpose, so
          that grant is keyed to a stable identity and survives reboots and
          nixpkgs bumps — you grant it once, not on every rebuild (and so the
          espanso troubleshooting window stops popping up at login, since that
          window only ever meant "the grant went missing").
        '';
      };
      matches = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              trigger = lib.mkOption {
                type = lib.types.str;
                example = "@@";
                description = "What you type.";
              };
              replace = lib.mkOption {
                type = lib.types.str;
                example = "ada@example.com";
                description = "What it expands to.";
              };
            };
          }
        );
        default = [ ];
        example = lib.literalExpression ''
          [
            { trigger = "@@"; replace = "ada@example.com"; }
            { trigger = "##"; replace = "+1 555 0100"; }
          ]
        '';
        description = ''
          The expansion table — one { trigger; replace; } per snippet, written
          to ~/.config/espanso/match/default.yml. Only espanso's plain
          trigger→replace form is exposed here; for dynamic matches (dates,
          shell output, forms) drop a hand-written .yml alongside it in
          ~/.config/espanso/match/ — espanso loads every file in that dir.
        '';
      };
    };

    secrets.provider = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "keyring";
      example = "gcsm";
      description = ''
        The secretspec provider that supplies secret VALUES on this machine.
        The secrets room writes it to ~/.config/secretspec/config.toml as the
        default provider, so `secretspec run / check / set` work without
        flags. Any provider string secretspec accepts, URIs included:
        "keyring" (macOS login keychain — local, no accounts), "onepassword",
        "bws" (Bitwarden Secrets Manager), "gcsm" (Google Cloud Secret
        Manager), "awssm" (AWS Secrets Manager), "vault", "pass",
        "protonpass", "lastpass", "dotenv", "env", or a scoped URI like
        "onepassword://account@vault".

        WHICH secrets exist is not declared here — that's each project's
        committed secretspec.toml. Cloud providers authenticate with their own
        credentials, configured outside Nix (e.g. `gcloud auth
        application-default login` for gcsm); that login is the one manual
        step on a new Mac. null skips writing the config file entirely — run
        `secretspec config init` yourself.
      '';
    };

    theme.accent = lib.mkOption {
      type = lib.types.enum [
        "rosewater"
        "flamingo"
        "pink"
        "mauve"
        "red"
        "maroon"
        "peach"
        "yellow"
        "green"
        "teal"
        "sky"
        "sapphire"
        "blue"
        "lavender"
      ];
      default = "mauve";
      example = "sapphire";
      description = ''
        The accent colour, a Catppuccin Mocha name (the Nebelung palette is a
        grey-tinted Mocha). It recolours the tools nebelhaus injects colours
        into — lazygit, fzf, yazi, and the Zen browser — via the matching
        Nebelung per-accent ports.

        Honest scope: this moves the accent on those tools, NOT literally
        everything. Single-file dotfiles that bake the palette at their own
        theme slot (ghostty, starship, tmux, bat, zellij, …) keep their built-in
        colour and don't follow this option. The base palette stays the same
        Nebelung grey either way — only the accent hue changes.
      '';
    };

    theme.wallpaper = lib.mkOption {
      type = lib.types.enum [
        "none"
        "orbits"
        "constellation"
        "flow"
        "bold"
      ];
      default = "none";
      example = "orbits";
      description = ''
        The desktop wallpaper, set at each home-manager activation (osascript,
        every desktop on the current Space). Four Nebelung looks:

          orbits · constellation · flow  hand-made, the palette baked in
          bold                           generated from theme.accent, so it
                                         follows the accent (a bold pink at
                                         accent = "pink")

        Default "none" leaves your current wallpaper alone — changing the
        desktop is visible and personal, so nothing moves unless you ask (the
        bootstrap interview offers the choice on a fresh install).
      '';
    };

    prowl.apps = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
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
        }
      );
      default = [
        {
          key = "t";
          name = "Ghostty";
          workspace = "T";
          appId = "com.mitchellh.ghostty";
          barIcon = ":ghostty:";
          label = "Ghostty (Terminal)";
        }
        {
          key = "b";
          name = "Zen";
          workspace = "B";
          appId = "app.zen-browser.zen";
          barIcon = ":zen_browser:";
          label = "Zen (Browser)";
          cask = "zen";
        }
      ];
      description = ''
        The app roster — ONE source of truth for the tiling launcher. Each entry
        wires an app into AeroSpace (leader key, workspace + window
        auto-assign), SketchyBar (a workspace pill), and the pounce cheatsheet,
        so those three configs never drift. Set your own roster in your host
        file; the default is a neutral terminal + browser so a fresh install
        boots to something that works. See modules/prowl for the generation.
      '';
    };

    prowl.rosterFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression "./roster.json";
      description = ''
        Optional JSON file of extra roster entries, appended to
        nebelhaus.prowl.apps at build time (same per-app schema, as an array).
        This is what makes the roster machine-editable: the pounce "Install App"
        command appends structured entries here and rebuilds, so apps gain a
        workspace + leader key without hand-editing the Nix list. null disables
        it. The file must be tracked by the flake's git repo to be read.
      '';
    };

    # ---- optional rooms ----
    # den + hearth + collar are always on (system, shell, Touch ID). These three
    # are the choosable rooms — turning one off drops its packages, agents, and
    # config entirely (the "minimal vs developer" difference is just these flags).
    prowl.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "AeroSpace tiling window management + the Caps-Lock leader launcher.";
    };
    sill.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        The SketchyBar menu bar. When off, the native macOS menu bar is kept
        (nebelhaus stops hiding it) and no bar is drawn.
      '';
    };
    pounce.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "The pounce command palette daemon (⌘Space) + its rice commands.";
    };

    trill.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "The trill Messages client, installed via the trill flake (copied to /Applications).";
    };

    tour.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        The haus tour — a first-run tutor that walks the four moves (launch /
        navigate / resize / palette) as ONE quiet pill in the bar, advancing
        live as each move is detected. It never opens a window or steals
        focus: a fresh machine just shows a dormant "new here?" hint, clicking
        it (or `haus tour`, or ⌘Space → tour) starts the lap, right-click
        hides it forever. Detection reuses signals the rice already fires (the
        leader-mode scripts) — no key logging, no Accessibility.

        Needs prowl + sill (it silently stays out of the bar without them);
        the ⌘Space step is dropped when pounce is off. Progress lives in
        ~/.local/state/nebelhaus — `haus tour reset` re-arms a finished tour.
      '';
    };

    # Per-pill on/off for the whole right side of the bar. One bool per item in a
    # submodule (not attrsOf) so unknown keys are rejected and each item carries
    # its own default: the core pills default true, the extras default false. The
    # descriptions here are the single source for the options reference.
    sill.items =
      let
        core = {
          clock = "The clock pill, pinned to the far right.";
          weather = "The weather pill and its click-to-open forecast popover.";
          media = "The now-playing track (scrolls; auto-hides when nothing plays).";
          battery = "The battery pill.";
          wifi = "The Wi-Fi status pill.";
        };
        extra = {
          cpu = "Total CPU load, as a percentage pill.";
          memory = "Memory-pressure percentage pill.";
          volume = "Output volume / mute state.";
          calendar = "Your next timed event, with a click-popup of the next five. Pulls in `ical-buddy` automatically and reads Calendar, so macOS prompts for Calendar access on first run.";
          caffeinate = "A coffee pill that prevents idle system sleep for 1/2/4/8 hours, a custom whole-hour duration, or indefinitely. The display may still turn off; closing a MacBook lid still sleeps it. Uses macOS's built-in `caffeinate`, so there is no extra package.";
          agents = "A paw pill tracking your `claude --worktree` agent panes — amber when one is blocked on you, click for the per-agent list; left-click a row to jump to that pane, ⌥/right-click for a live `zellij subscribe` peek. Fed by Claude Code hooks (point them at ~/.config/sketchybar/plugins/agents-hook.sh); dormant until they fire.";
          elgato = "Toggles an Elgato Key Light on the local network.";
          harvest = "A Harvest time-tracking pill; needs a ~/.config/sketchybar/harvest_secrets.sh you provide.";
        };
        mkItem = default: desc: lib.mkOption {
          type = lib.types.bool;
          inherit default;
          description = desc;
        };
      in
      lib.mkOption {
        type = lib.types.submodule {
          options = lib.mapAttrs (_: mkItem true) core // lib.mapAttrs (_: mkItem false) extra;
        };
        default = { };
        example = {
          weather = false;
          cpu = true;
        };
        description = ''
          Which SketchyBar pills to draw, one bool each. The core pills —
          `clock`, `weather`, `media`, `battery`, `wifi` — default true; the extras
          — the readouts `cpu`, `memory`, `volume`, `calendar`, `caffeinate`
          and the personal `agents`, `elgato`, `harvest` — default false. Set
          only what you want to change:

            nebelhaus.sill.items = {
              weather = false;   # drop a default-on core pill
              cpu = true;        # add an off-by-default readout
              caffeinate = true; # add the keep-awake controller
            };

          A pill set false is never created (its update script doesn't run either).
          The hush (Do-Not-Disturb) pill is separate — it rides
          nebelhaus.hush.enable, not this set.
        '';
      };

    homebrew = {
      cleanup = lib.mkOption {
        type = lib.types.enum [
          "none"
          "uninstall"
          "zap"
        ];
        default = "none";
        description = ''
          How `darwin-rebuild switch` treats Homebrew casks/brews that are
          installed but NOT declared anywhere in your config.

          - "none" (default, safe): leave undeclared formulae/casks alone. The
            rice never deletes apps you installed yourself.
          - "uninstall": remove undeclared formulae/casks (keeps their data).
          - "zap": remove undeclared formulae/casks AND their app data. Fully
            declarative, but a stray cask you forgot to list is deleted — with
            no backup — on the very next rebuild. Only choose this once every
            app you keep is declared (bootstrap can adopt your current casks).
        '';
      };
      autoUpdate = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Run `brew update` before activating the Homebrew step on every
          rebuild. Off by default — reproducible rebuilds shouldn't silently
          pull newer formulae. Turn on if you want brew to track upstream.
        '';
      };
      upgrade = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Upgrade outdated Homebrew packages on every rebuild. Off by default
          for the same reproducibility reason as autoUpdate.
        '';
      };
      installsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = lib.literalExpression "./installs.json";
        description = ''
          Optional JSON file — { "casks": [ … ], "brews": [ … ],
          "nixpkgs": [ … ] } — of extra packages. Casks and formulae merge into
          homebrew.casks / homebrew.brews; Nixpkgs attribute paths merge into
          environment.systemPackages. The counterpart to prowl.rosterFile for
          packages that don't belong on the tiling roster: the pounce "Install
          App" command's "just install" lane appends here and rebuilds. null
          disables it. The file must be tracked by the flake's git repo to be
          read.
        '';
      };
    };

    # ---- hush ----
    hush.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        The hush room: one quiet switch — bar pill, palette command, and a
        `hush` CLI — that turns macOS Do Not Disturb on/off (via the
        declaratively-bound symbolic hotkey 175, pressed synthetically),
        optionally sets your Slack status, and runs your hooks.

        Honest scope: hush flips the built-in Do Not Disturb, not named Focus
        modes, and it doesn't manage which apps break through — curate that
        once in System Settings. The keypress needs an Accessibility grant on
        whatever app invokes hush (palette runs inherit pounce's; grant
        sketchybar once for the pill). `hush doctor` walks the one-time steps.
      '';
    };

    hush.slack = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Also set a Slack status and snooze Slack notifications (all devices,
          phone included) while hushed. Off by default: it needs a personal
          Slack user token (scopes users.profile:write + dnd:write) provided
          via tokenCommand. The previous status is saved and restored on
          unhush.
        '';
      };
      tokenCommand = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "security find-generic-password -s hush-slack -w";
        description = ''
          Shell command that prints the Slack user token (xoxp-…) to stdout.
          Keychain-first so no secret ever lands in the store or a dotfile:
            security add-generic-password -s hush-slack -a $USER -w 'xoxp-…'
        '';
      };
      statusText = lib.mkOption {
        type = lib.types.str;
        default = "heads down";
        description = "Slack status text while hushed.";
      };
      statusEmoji = lib.mkOption {
        type = lib.types.str;
        default = ":no_bell:";
        description = "Slack status emoji while hushed.";
      };
      snooze = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Also pause Slack's own notifications (dnd.setSnooze) while hushed —
          this is what silences the phone. Ended on unhush; capped at 24h as
          a failsafe if you forget.
        '';
      };
    };

    hush.hooks = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.path lib.types.str);
      default = [ ];
      example = lib.literalExpression ''[ ./onair-light.sh "/Users/ada/bin/pause-music" ]'';
      description = ''
        Extra scripts run on every hush/unhush, each called with a single
        argument "on" or "off". Paths are copied into the store; strings are
        run as-is (so $HOME paths work). Failures are logged, never fatal —
        a broken hook can't wedge the toggle.
      '';
    };

    pounce.windowSwitcher = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Replace the stock ⌘Tab app switcher with pounce's MRU *window* switcher:
        tap ⌘⇥ to toggle to the last window (across workspaces), hold ⌘ and keep
        tapping ⇥ to walk older ones, type while holding to fuzzy-filter
        (frecency-ranked). Rows carry the window's AeroSpace workspace, and
        focusing goes through `aerospace focus --window-id` so a window parked
        on another workspace surfaces correctly.

        Needs the daemon to hold an Accessibility grant — in practice, set
        nebelhaus.pounce.signingIdentity so the grant survives rebuilds. Without
        the grant the event tap can't install and stock ⌘Tab keeps working, so
        this default is safe on a fresh, not-yet-granted install. false leaves
        ⌘Tab native even when the grant is there.
      '';
    };

    pounce.signingIdentity = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "Developer ID Application: Jane Doe (ABCDE12345)";
      description = ''
        A code-signing identity in your login keychain — either its SHA-1 or
        (preferred) its full common name. The pounce daemon is re-signed with
        it so a macOS Accessibility (TCC) grant survives rebuilds. List yours:
          security find-identity -v -p codesigning

        Prefer a "Developer ID Application" identity passed BY NAME (e.g.
        "Developer ID Application: Jane Doe (TEAMID)"): its designated
        requirement anchors on the stable team OU, so the grant survives even
        a certificate renewal (the renewed cert keeps the same name/team but
        gets a new SHA — a hardcoded SHA would silently fall back to unsigned).
        This is also the identity the Homebrew build is signed with, so both
        install paths share one identity. An "Apple Development" cert works too
        but expires yearly and pins the specific cert, so it's less durable.

        Changing this once invalidates the existing grant (the requirement
        changes) — re-approve pounce in Accessibility a single time after.

        Leave empty to run pounce unsigned (the palette works, but auto-paste
        and other Accessibility-gated features stay off).
      '';
    };
  };
}

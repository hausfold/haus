# Host-provided identity. These are the values that are personal to YOU rather
# than part of the rice — a host file (see hosts/example) sets them.
{ lib, config, ... }:

let
  # Every coding-agent client the rice knows how to install, spawn and resume —
  # read by agents.clients, agents.default, and sill's aiUsage.provider, so none
  # of the three can drift apart. modules/lib/agents.nix says why it lives there
  # rather than here, and names the one copy that can't be folded in.
  agentClients = import ./lib/agents.nix;

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
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "s";
        description = ''
          The leader letter for this app: tap Caps Lock then this key to
          launch/focus it. Must be unique across the roster.

          null (the default) means the entry is INSTALL-ONLY: it still
          brings its cask/formula/package, but claims no leader key, no
          cheatsheet row, and no launch-mode bubble. That is what lets one
          roster hold both the apps you reach for by keyboard and the ones
          you just want on the machine (and fonts, and CLI tools).
        '';
      };
      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "Slack";
        description = ''
          macOS application name, as passed to `open -a`. Required when
          `key` is set (the launcher has nothing to open otherwise);
          null is right for an install-only entry — a font, a CLI tool, or
          an app you launch some other way.
        '';
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
      # ---- where it comes from -------------------------------------------
      # Four sources, one per package manager, all optional. Set the one that
      # applies and declaring the app is what installs it; set none and the
      # entry is pure metadata for something already on the machine (Safari,
      # Music, an app you drag in by hand).
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
      brew = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "ical-buddy";
        description = ''
          Homebrew FORMULA that installs this entry, appended to
          homebrew.brews. For the command-line half of the roster — a tool
          with no .app bundle, which usually means `key`, `name` and
          `workspace` are all null.
        '';
      };
      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        example = lib.literalExpression "pkgs.orbstack";
        description = ''
          Nixpkgs package that installs this entry. Where it lands is
          `scope`'s call.

          A shared rice or app pack can't set this one — it needs `pkgs`, and a
          data-only rice has no arguments. Use `packageName` there.
        '';
      };
      packageName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "orbstack";
        description = ''
          The same source as `package`, NAMED rather than evaluated: an
          attribute path into nixpkgs, so "orbstack" means `pkgs.orbstack` and
          "python3Packages.black" means what it says. `scope` applies to it
          identically.

          This is the source a shared app pack can use (packs/README.md).
          Without it a pack could install from Homebrew and the App Store but
          never from Nixpkgs, because reaching `pkgs` is exactly what the
          data-only format forbids — the one gap in the four sources.

          Set this or `package`, never both; and it counts as a source like any
          other, so pairing it with `cask` is the same mistake as pairing
          `cask` with `brew`.
        '';
      };
      scope = lib.mkOption {
        type = lib.types.enum [
          "user"
          "system"
        ];
        default = "user";
        description = ''
          Which profile `package` installs into.

          - "user" (default): home-manager's `home.packages`. Right for
            anything you run as yourself — apps, editors, CLI tools.
          - "system": nix-darwin's `environment.systemPackages`. Installed
            once for the whole machine, so it's on PATH for root, for
            non-login shells, and for launchd jobs — which is what a tool
            invoked by a daemon, a `sudo` workflow, or an activation script
            actually needs. (It is about REACH, not about the package
            needing elevated privileges to install: `darwin-rebuild` runs
            under sudo either way.)

          Ignored when `package` is null — Homebrew has no such split.
        '';
      };
      appStoreId = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        example = 497799835;
        description = ''
          Mac App Store numeric app id (the digits in its store URL), so an
          App Store app is declared in the same roster as everything else
          rather than in a comment.

          Recording it is always safe; INSTALLING from it is opt-in via
          `nebelhaus.appStore.install`, because the App Store is the one
          source that can't be fully automated: `mas` has no sign-in
          command, and it cannot buy a paid app for the first time. Free
          apps it can fetch; paid ones you purchase once in App Store.app
          and every machine afterwards can install them.
        '';
      };
      installedBy = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "nebelhaus.perch";
        description = ''
          The nebelhaus module that puts this app on disk, when none of the
          four sources above describes it: pounce and perch copy a
          notarized bundle into /Applications from their own activation
          step, which is neither a cask nor a package you can list.

          Set BY the rice, not by you. It exists so the roster can still
          answer "who installed this?" for those apps — without it, a host
          adding a leader key for Perch had to KNOW the rice already ships
          it, leave every source field null, and leave a comment explaining
          the hole. This is that comment, as data.
        '';
      };
    };
  };
in
{
  options.nebelhaus = {
    roster = lib.mkOption {
      type = lib.types.attrsOf appType;
      default = { };
      example = lib.literalExpression ''
        {
          # Launcher app: leader s, owns workspace S, installs itself.
          slack = {
            key = "s";
            name = "Slack";
            workspace = "S";
            appId = "com.tinyspeck.slackmacgap";
            barIcon = ":slack:";
            cask = "slack";
          };

          # Install-only: no key, so no leader binding and no pill.
          framer = { cask = "framer"; };
          orbstack = { package = pkgs.orbstack; };
          biome = { package = pkgs.biome; scope = "system"; };
          ical-buddy = { brew = "ical-buddy"; };
          xcode = { name = "Xcode"; appStoreId = 497799835; };
        }
      '';
      description = ''
        The one list of things this machine has, keyed by a stable id. It is
        the canonical, composable source for AeroSpace launcher keys and
        workspaces, SketchyBar pills, the pounce cheatsheet, Nebelung theme
        ports — and for the install itself, from any of four sources
        (`cask`, `brew`, `package`, `appStoreId`).

        Every field except the id is optional, and WHICH fields you set is
        what the entry means. Set `key` and it joins the launcher; set
        `workspace` and it claims one, with a pill; set none of those and
        it's install-only — which is how a font or a command-line tool
        lives in the same list as Slack instead of in a second one beside
        it. The rice's own `homebrew.casks` / `home.packages` still work and
        still merge; you just shouldn't need them for an app.

        Attribute-set entries merge across Nix modules, so a host, an imported
        file, and pounce's "Install App" command can each contribute one app
        without parsing or replacing a monolithic list. Set an entry's enable
        field to false to remove it, or override individual fields by app id.
      '';
    };

    # Normalized by modules/roster. Kept internal so every room consumes the same
    # ordered list while the public API stays keyed and composable.
    _roster = lib.mkOption {
      type = lib.types.listOf appType;
      internal = true;
      readOnly = true;
      description = "Resolved, enabled app roster used internally by nebelhaus modules.";
    };

    # The launcher subset: entries that claim a leader key. Its own list rather
    # than a `key != null` filter repeated in prowl, sill and pounce — every one
    # of those renders `a.key` into a string, so a missed filter isn't a wrong
    # binding, it's the literal word "null" in a keymap.
    _launchers = lib.mkOption {
      type = lib.types.listOf appType;
      internal = true;
      readOnly = true;
      description = "Resolved roster entries that have a leader key, in roster order.";
    };

    appStore = {
      install = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Install roster entries that set `appStoreId` from the Mac App
          Store during activation, skipping any already installed.

          Off by default: this reaches the network and acts on your Apple
          ID, which shouldn't happen as a side effect of turning on a
          window manager. It also can't be complete — `mas` cannot sign in
          (do that once in App Store.app) and cannot make a first-time
          PURCHASE, so a paid app you don't already own is reported and
          skipped rather than installed.

          Deliberately NOT nix-darwin's `homebrew.masApps`: that runs
          `mas install` through `brew bundle` as your user, and since
          macOS 13 the App Store install path requires root — so it stops
          for a password prompt that a rebuild has no terminal to show,
          and the rebuild hangs. The activation step this option enables
          is already running as root, so it neither prompts nor wedges.
        '';
      };
    };

    # ---- ui: one scale, fanned out ----
    # The missing abstraction. Before this, making the rice bigger meant finding
    # and tuning every size by hand in a different file each time.
    #
    # Honest scope, and it is narrower than "everything": this scales the things
    # nebelhaus itself controls and macOS lets it control — the terminal font,
    # the command palette, the Dock, Finder's sidebar rows, the bar's type, and
    # the tiling gaps (the full list, with what it does NOT reach, is in the
    # option's own description below, and pinned by `scale-reach`). The one
    # thing it cannot do proportionally is the menu bar's HEIGHT, which belongs to
    # macOS's own band (see the note on ui.scale); nor can it resize third-party
    # apps, since macOS has no system-wide UI scale — the OS-level lever there is
    # display resolution (`nebelhaus.displays`).
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
          - the command palette, whole (nebelhaus.pounce.scale) — its rows,
            text and icons, and the emoji / clipboard / screenshots / camera /
            Find Files / cheatsheet panels behind it
          - the type in Sill's menu bar — pill labels, icons and popup rows —
            up to a ceiling; see below
          - the Dock icon size (system.defaults.dock.tilesize)
          - Finder's sidebar rows (NSTableViewDefaultSizeMode) — a threshold
            rather than a multiplier, and it is set at every scale: at or below
            1.0 the rice picks SMALL rows (more fits in a tiled window), above
            1.0 it picks Apple's large ones
          - prowl's window gaps

        That list is pinned by `nix flake check`'s `scale-reach`, which
        fingerprints every surface it names at four scales — so a wire dropped
        in a refactor fails a check instead of quietly ceasing to arrive.

        Where it stops, and why it isn't a gap waiting to be filled:

          - Sill's bar HEIGHT. The bar is 36pt with 28pt pills so the pills sit
            inside the 32pt menu-bar band that macOS's own hover-reveal covers;
            taller pills poke out below it. That band is macOS's, fixed, and has
            no setting behind it — measured, not assumed. So the bar's type
            follows this option up to the largest that still fits a pill
            (1.25x) and then stops, silently: past that a rice simply gets the
            ceiling. The only way to make the whole bar bigger is to change what
            a point MEANS — the display's scaled resolution, below.
          - perch, the notch shelf. It sizes itself from the SCREEN — a fraction
            of the display's width, clamped — which is the right answer for a
            thing hanging off the notch, and it means NEITHER lever moves it: a
            scaled display shrinks the shelf's width in points by the same
            factor that makes a point bigger, so it stays the same physical
            size while everything around it grows. A large-print rice gets a
            normal-sized shelf, and there is no option here that changes that.
          - anything outside nebelhaus. macOS has no system-wide UI scale, so
            third-party apps follow only a display-resolution change.

        Worth knowing if you set both: this and
        `nebelhaus.displays.<name>.uiScale` MULTIPLY. A larger-text display mode
        leaves a smaller desktop in points, and this asks for bigger points
        inside it — so 1.4 on an already-scaled display is a bigger jump than
        1.4 on the panel's default.
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
          to that workspace and follows it there, an arrow navigates, `-`/`=`
          resizes.

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
          (`<mod>` + `/` `,`), fullscreen, moving a workspace to the next
          monitor (`<mod>⇧⇥`), and entering service mode
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
          `/` `,`, `f`, `⇧⇥` and `⇧;`, none of which a roster letter can land
          on — and `<mod>⇥` is free again, since workspace back-and-forth
          retired in favour of pounce's cross-workspace ⌘⇥ switcher. (Under
          "ctrl-alt" that used to bite — the throws were `⌃⌥⇧` + an app's roster
          letter, so an app on `a` silently ate hearth's zellij
          `Ctrl Alt Shift a` in-place-agent bind. That collision is gone.)
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
      # (nebelhaus.roster) already fronts a letter → open an app; this fronts a key
      # → run a command (a script, an AppleScript, a `things:///` open). Rendered
      # into AeroSpace's [mode.launch.binding] AND the pounce cheatsheet from this
      # one list, so a binding and its caption can't drift — the same guarantee the
      # roster gives. Kept a flat list rather than nested under an app entry on
      # purpose: a leader action is not an attribute of any one app (the target may
      # be no app at all), and launch-mode keys must be globally unique — an
      # assertion in modules/prowl catches a key that collides with a roster letter
      # or a built-in launch key.
      leaderExtras = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              key = lib.mkOption {
                type = lib.types.str;
                example = "enter";
                description = ''
                  The AeroSpace key name pressed after the leader (e.g. "enter",
                  "space", "period", or a letter). Must not collide with a roster
                  app's key or a built-in launch-mode key (the digits 1-4, the
                  arrows, `-`/`=`, `v`/`e`/`z`, `,`, `` ` ``, `/`, esc) — nor with
                  the workspace throws, which are ⇧ + any of those digits or a
                  roster letter ("shift-1", "shift-b", …). An assertion in
                  modules/prowl catches a clash rather than letting one binding
                  silently shadow another.
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
          }
        );
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
          The terminal toolbelt: bat, fzf, fd, ripgrep, yazi, zoxide, lsd,
          glow, jq, tree, chafa, ttyd and fastfetch — the themed replacements
          for cat, find, grep, ls and friends that the rice's shell is built
          around.

          Off leaves a plain shell. The prompt (starship) and the colour scheme
          stay: these are the *tools*, not the appearance.
        '';
      };

      agents.enable = lib.mkOption {
        type = lib.types.bool;
        default = config.nebelhaus.developer.enable;
        defaultText = lib.literalExpression "config.nebelhaus.developer.enable";
        description = ''
          Coding-agent *tooling*: `holt` (agent worktrees), `agent-state` (the
          pane-status writer behind the `agents` bar pill and the zellij tab
          badge), `zscratch`, the agent-worktree statusline, and the client
          config hearth writes (Claude Code's settings.json keys, opencode's
          agent-state plugin). Which clients get installed is `agents.clients`.

          Off is right for any machine not running coding agents — it's a large
          surface a non-developer never sees. It also empties `agents.clients`,
          since a client with no `holt` to park it is not the deal on offer.
        '';
      };

      languages = lib.mkOption {
        type = lib.types.listOf (lib.types.enum [ "node" ]);
        default = lib.optionals config.nebelhaus.developer.enable [ "node" ];
        # literalMD, not literalExpression: this SENTENCE describes the default,
        # it isn't Nix you could paste anywhere. The distinction is load-bearing
        # now — host-template.jq copies a literalExpression straight into the
        # generated host file as the option's value, and would have emitted
        # `nebelhaus.developer.languages = [ "node" ] when developer.enable …;`,
        # a syntax error the moment someone uncommented it. Prose ⇒ literalMD.
        defaultText = lib.literalMD ''[ "node" ] when developer.enable is true, else [ ]'';
        example = [ ];
        description = ''
          Language runtimes to install. Currently only "node" (bun + fnm, with
          fnm's `--use-on-cd` shell hook).

          Deliberately a list rather than one bool per language, so adding
          "rust" or "python" later doesn't change this option's shape.
        '';
      };
    };

    agents.clients = lib.mkOption {
      type = lib.types.listOf (lib.types.enum agentClients);
      default = lib.optionals config.nebelhaus.developer.agents.enable [
        "claude"
        "opencode"
      ];
      # Prose, so literalMD — see developer.languages above for why that matters.
      defaultText = lib.literalMD ''[ "claude" "opencode" ] when developer.agents.enable is true, else [ ]'';
      example = [
        "claude"
        "codex"
      ];
      description = ''
        Which coding-agent clients to install. `claude` is Claude Code, `codex`
        is OpenAI Codex, `opencode` is OpenCode. The ⌘A terminal binding starts
        whichever one `agents.default` names — Claude Code through its own
        `--worktree` hook, the others through `holt new`.

        A list rather than one bool per client, matching `developer.languages`
        — a fourth client later doesn't change this option's shape.

        This is the option that makes `agents.default` honest. Naming a client
        you have not installed used to fail *at spawn time*, inside the pane,
        after the worktree already existed: a flash of
        `codex is unavailable`, and litter to reap. `agents.default` must now
        be a member of this list, so the same mistake fails the rebuild
        instead, with both values named.

        Override the package for a client the usual Nix way — an overlay on
        `claude-code`, `codex` or `opencode` — rather than dropping the client
        here and installing your own copy alongside; two derivations shipping
        the same `bin/` name collide in one profile.
      '';
    };

    agents.default = lib.mkOption {
      type = lib.types.enum agentClients;
      default = "claude";
      example = "codex";
      description = ''
        The coding agent started by Pounce's **Spawn Agent** command, by the
        ⌘A / Super-a zellij binds and the `c` shell alias, and used to reopen
        worktrees with no client recorded yet. Each spawned worktree records its
        own client, so changing this affects new work but never reopens an
        existing Codex or OpenCode task in Claude.

        Must be one of `agents.clients` — see there.

        Only `claude` can make its own worktree (its native `--worktree` flag,
        which fires `holt hook create`); for `codex` and `opencode` ⌘A runs
        `holt new` instead, producing the same checkout, branch and registry
        entry from the outside. Resuming follows the client too: `codex` reopens
        its cwd-filtered `codex resume` picker, `opencode` continues its latest
        session for that cwd. All three share one `holt` branch/parking/reap
        lifecycle, and all three light up the `agents` bar pill and the zellij
        tab-bar badge — the opencode plugin and the codex hooks are written for
        you; only Claude Code's stay yours to wire, because Claude owns its own
        settings.json (see `nebelhaus.sill.items.agents`).
      '';
    };
  };
}

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
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "s";
        description = ''
          The leader letter for this app: tap Caps Lock then this key to
          launch/focus it. Must be unique across the roster, and not one of
          launch mode's own: `v` `e` `z` `,` `` ` `` `-` `=` `/` `1`-`4` `esc`
          and the arrows are taken, and a rebuild refuses them.

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
      appId = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "com.tinyspeck.slackmacgap";
        description = ''
          Bundle id, used for the AeroSpace `on-window-detected` auto-assign
          rule (when this app is a member of a `haus.workspaces` entry),
          the `float` rule below, and the wake-time re-sort. null skips both
          — the app still launches, it just isn't herded anywhere or floated.
          Find one with `osascript -e 'id of app "…"'`.
        '';
      };
      float = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Always float this app's windows instead of tiling them — an
          AeroSpace `on-window-detected` rule generated from `appId`
          (`run = 'layout floating'`). Right for a picker/dialog/status
          window that would otherwise reflow the whole workspace every time
          it opens (FaceTime, Trill's Settings/Inbox), not for something you
          work inside. Requires `appId`; ignored (with a warning) without it.
        '';
      };
      titleRegex = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "^Picture in Picture$";
        description = ''
          Scope `float` to windows of this app whose title matches this
          regex (AeroSpace's `window-title-regex-substring`), instead of
          every window the app opens. null (default) floats all of them.

          Some apps' windows report their title only AFTER AeroSpace has
          already detected and tiled them once (a race, not a bug this
          option can fix) — Ghostty is the known case, which is why
          haus's own Ghostty float rule is hand-written in aerospace.toml
          rather than generated from the roster. If a title rule flaps,
          that race is almost certainly why. Ignored when `float` is false.
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

          A shared desktop or app pack can't set this one — it needs `pkgs`, and
          a data-only desktop has no arguments. Use `packageName` there.
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

          This is the source a shared app pack can use — see
          `haus.apps.packs`, and `modules/apps/packs/writing.nix` for one.
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
          `haus.appStore.install`, because the App Store is the one
          source that can't be fully automated: `mas` has no sign-in
          command, and it cannot buy a paid app for the first time. Free
          apps it can fetch; paid ones you purchase once in App Store.app
          and every machine afterwards can install them.
        '';
      };
      installedBy = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "haus.perch";
        description = ''
          The haus module that puts this app on disk, when none of the
          four sources above describes it: pounce and perch copy a
          notarized bundle into /Applications from their own activation
          step, which is neither a cask nor a package you can list.

          Set BY haus, not by you. It exists so the roster can still
          answer "who installed this?" for those apps — without it, a host
          adding a leader key for Perch had to KNOW haus already ships
          it, leave every source field null, and leave a comment explaining
          the hole. This is that comment, as data.
        '';
      };
      id = lib.mkOption {
        type = lib.types.str;
        default = "";
        internal = true;
        description = ''
          The roster key this entry was declared under. Set BY ../roster
          from the attribute name — the same "set by haus, not by you"
          pattern as `installedBy` — so a resolved entry can be looked up
          in a `haus.workspaces` entry's `apps` membership list
          without roster and workspaces having to re-derive each other's
          keys.
        '';
      };
    };
  };

  workspaceType = lib.types.submodule {
    options = {
      key = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "c";
        description = ''
          Leader then ⇧<key> throws the focused window to this workspace
          and follows it there (AeroSpace's `move-node-to-workspace
          --focus-follows-window`). There is no bare <key> binding for a
          workspace — that namespace belongs to `haus.roster` app
          launch keys, one of which can double as this workspace's "open
          something here" action by being one of its `apps`. null means the
          workspace is reachable only by launching an app that belongs to
          it (or not by keyboard at all). Must be unique across workspaces,
          and ⇧<key> must not collide with a built-in launch-mode binding
          (⇧1-4 are taken).
        '';
      };
      icon = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = ":slack:";
        description = ''
          The SketchyBar workspace-pill glyph. A sketchybar-app-font
          ligature like ":slack:" renders a logo; any other string is
          drawn in the bar's Nerd Font. null falls back to the workspace's
          own id.
        '';
      };
      apps = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "slack"
          "mail"
          "messages"
        ];
        description = ''
          `haus.roster` app ids that live on this workspace: each
          one's window auto-moves here (via its `appId`), opening any of
          them from the leader lands you here, and this workspace's `key`
          throw (above) sends the focused window here regardless of which
          member app owns it. An app id may belong to at most one
          workspace.

          A plain list, not wrapped in `lib.mkDefault` even where haus
          itself contributes to it (ghostty → workspace `T`, say) — list
          options MERGE across modules at equal priority but a `mkDefault`
          list is dropped whole rather than merged the moment anything else
          defines the same option, so a host adding a second app to `T`
          would silently lose ghostty's membership if haus's own
          contribution used `mkDefault` here. Override a single membership
          by dropping the app's id from your own list instead.
        '';
      };
      id = lib.mkOption {
        type = lib.types.str;
        default = "";
        internal = true;
        description = ''
          The haus.workspaces attribute name. Set BY ../workspaces
          from the attribute name, the same pattern as appType's own `id` —
          not meant to be set by hand.
        '';
      };
    };
  };
in
{
  options.haus = {
    roster = lib.mkOption {
      type = lib.types.attrsOf appType;
      default = { };
      example = lib.literalExpression ''
        {
          # Launcher app: leader s. Own workspace + pill come from putting
          # "slack" in a haus.workspaces entry's `apps` (see below).
          slack = {
            key = "s";
            name = "Slack";
            appId = "com.tinyspeck.slackmacgap";
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
        the canonical, composable source for AeroSpace launcher keys, the
        SketchyBar pills, the pounce cheatsheet, Nebelung theme ports — and
        for the install itself, from any of four sources (`cask`, `brew`,
        `package`, `appStoreId`).

        Every field except the id is optional, and WHICH fields you set is
        what the entry means. Set `key` and it joins the launcher; set none
        of the launcher/workspace/install fields and it's install-only —
        which is how a font or a command-line tool lives in the same list as
        Slack instead of in a second one beside it. haus's own
        `homebrew.casks` / `home.packages` still work and still merge; you
        just shouldn't need them for an app.

        Which WORKSPACE an app owns is not a field here — it's
        `haus.workspaces.<id>.apps` naming this entry's id, so one
        workspace can hold several apps (a "comms" workspace with Slack,
        Mail and Messages) instead of baking "one app, one workspace" into
        this schema. See that option.

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
      description = "Resolved, enabled app roster used internally by haus modules.";
    };

    workspaces = lib.mkOption {
      type = lib.types.attrsOf workspaceType;
      default = { };
      example = lib.literalExpression ''
        {
          # Role workspace: three apps, one pill, one throw key.
          comms = {
            key = "c";
            icon = ":slack:";
            apps = [ "slack" "mail" "messages" ];
          };

          # Single-app workspace: the common case, one entry each.
          T = { key = "t"; icon = ":ghostty:"; apps = [ "ghostty" ]; };
        }
      '';
      description = ''
        AeroSpace workspaces this machine names on purpose, keyed by the
        workspace id AeroSpace itself will use (any string it accepts as a
        workspace name — a single letter like `T`, or a word like `comms`).
        First-class rather than a field on an app: an app can only ever own
        one workspace if the field lives on the app, which makes a role
        workspace ("communication" = Mail + Slack + Messages) or a project
        workspace literally unrepresentable. Here, a workspace lists its own
        members instead.

        The four fixed numbered workspaces (1-4, leader/⇧+digit) are not
        part of this option — they always exist, independent of what any
        app claims. This option is for the NAMED workspaces app windows get
        herded onto.

        An entry with no `key` and no `apps` does nothing (a warning says
        so); one with `apps` but no `key` still gets a persistent workspace,
        a pill (with `icon`) and auto-herds its member windows, it just has
        no dedicated leader throw.
      '';
    };

    # Normalized by modules/workspaces. Same shape as _roster/_launchers: one
    # resolution (sorted list + the reverse app→workspace lookup) so prowl,
    # sill and the doc generator can't compute it three different ways and
    # disagree.
    _workspaces = lib.mkOption {
      type = lib.types.listOf workspaceType;
      internal = true;
      readOnly = true;
      description = "Resolved, sorted haus.workspaces entries, each carrying its id.";
    };
    _appWorkspace = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      internal = true;
      readOnly = true;
      description = ''
        Reverse lookup, roster app id -> the workspace id it belongs to
        (from haus.workspaces.*.apps). An id absent here belongs to no
        workspace.
      '';
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
    # haus itself controls and macOS lets it control — the terminal font,
    # the command palette, the Dock, Finder's sidebar rows, the bar's type, and
    # the tiling gaps (the full list, with what it does NOT reach, is in the
    # option's own description below, and pinned by `scale-reach`). The one
    # thing it cannot do proportionally is the menu bar's HEIGHT, which belongs to
    # macOS's own band (see the note on ui.scale); nor can it resize third-party
    # apps, since macOS has no system-wide UI scale — the OS-level lever there is
    # display resolution (`haus.displays`).
    ui.scale = lib.mkOption {
      type = lib.types.numbers.between 0.5 3.0;
      default = 1.0;
      example = 1.35;
      description = ''
        One number for "make the interface bigger". 1.0 is haus as tuned;
        1.35 is a comfortable large-print setting; below 1.0 tightens things up.

        It sets the DEFAULT of the sizes it drives, so anything you pin by hand
        still wins:

          haus.ui.scale = 1.5;          # everything grows
          haus.fonts.mono.size = 18;    # …except the terminal, pinned here

        What it currently moves:

          - the terminal font size (haus.fonts.mono.size)
          - the command palette, whole (haus.pounce.scale) — its rows,
            text and icons, and the emoji / clipboard / screenshots / camera /
            Find Files / cheatsheet panels behind it
          - the type in Sill's menu bar — pill labels, icons and popup rows —
            up to a ceiling; see below
          - the Dock icon size (system.defaults.dock.tilesize)
          - Finder's sidebar rows (NSTableViewDefaultSizeMode) — a threshold
            rather than a multiplier, and it is set at every scale: at or below
            1.0 haus picks SMALL rows (more fits in a tiled window), above
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
            (1.25x) and then stops, silently: past that a machine simply gets the
            ceiling. The only way to make the whole bar bigger is to change what
            a point MEANS — the display's scaled resolution, below.
          - perch, the notch shelf. It sizes itself from the SCREEN — a fraction
            of the display's width, clamped — which is the right answer for a
            thing hanging off the notch, and it means NEITHER lever moves it: a
            scaled display shrinks the shelf's width in points by the same
            factor that makes a point bigger, so it stays the same physical
            size while everything around it grows. A large-print machine gets a
            normal-sized shelf, and there is no option here that changes that.
          - anything outside haus. macOS has no system-wide UI scale, so
            third-party apps follow only a display-resolution change.

        Worth knowing if you set both: this and
        `haus.displays.<name>.uiScale` MULTIPLY. A larger-text display mode
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
        default = "none";
        example = "none";
        description = ''
          What enters the launcher/leader mode — tap it, then a letter opens an
          app, a digit focuses a workspace, ⇧+either throws the focused window
          to that workspace and follows it there, an arrow navigates, `-`/`=`
          resizes.

            - "caps" (default): Caps Lock. AeroSpace can't bind Caps Lock itself,
              so haus remaps it to F18 with hidutil and binds that.
            - "alt-space": the leader without giving up Caps Lock. No remap at all.
            - "none": no leader. Caps Lock stays Caps Lock, launch mode is
              unreachable, and nothing is remapped — the setting for a mouse-first
              machine, or for a Mac you are handing to someone else. What the leader
              fronted is still reachable: apps through the palette, window moves
              through service mode's join-with and the palette's own commands.
              Workspace focus and the workspace throws go away with it — they
              live only in launch mode.

          The remap is re-applied at every activation and does not survive a
          reboot, so moving off "caps" ends it — at the latest, at next boot.

          Only meaningful with haus.prowl.enable (AeroSpace owns the modes).
        '';
      };

      palette = lib.mkOption {
        type = lib.types.enum [
          "cmd-space"
          "alt-space"
          "ctrl-space"
          "none"
        ];
        default = "none";
        example = "none";
        description = ''
          What opens the pounce command palette. Registered in-process by the
          daemon, so it's near-instant and doesn't go through AeroSpace.

          "cmd-space" (default) is the one value that also DISABLES Spotlight's
          own ⌘Space, because the two can't share it. Every other value leaves
          Spotlight alone — including "none", which hands the palette's job back
          to Spotlight entirely. That's a fix as much as an option: haus used
          to take Spotlight's ⌘Space away unconditionally, even where nothing
          claimed it.

          Only meaningful with haus.pounce.enable.
        '';
      };

      windowNav = lib.mkOption {
        type = lib.types.enum [
          "alt"
          "ctrl-alt"
          "cmd-alt"
          "none"
        ];
        default = "none";
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
          layouts**, where ⌥+letter types accented characters — a machine that owns
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
          service mode. Combined with `leader = "none"` that's a machine where the
          tiler tiles and the keyboard is left alone — mouse-first. The cheatsheet
          follows, so it never advertises a key that does nothing.

          Only meaningful with haus.prowl.enable.
        '';
      };

      # The seam for leader actions that AREN'T "launch an app". The app roster
      # (haus.roster) already fronts a letter → open an app; this fronts a key
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

          Only meaningful with haus.prowl.enable and keys.leader != "none"
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
        default = false;
        example = true;
        description = ''
          The Development room: the CLI toolbelt, Git tooling and language
          runtimes. The neutral catalogue leaves it off; hacker selects it
          in its desktop.

          Coding agents left this pack on 2026-08-13 and are their own room
          now (`haus.ai.*`). The two rooms are independent: a desktop or host
          selects each one explicitly.

          `false` is what makes a non-developer haus possible — it strips
          those tools rather than merely hiding them. What remains is the
          product: `haus`, `awake`, the theme, the terminal, the bar, the tiler
          and the palette.

          The Git and toolbelt sub-options below default to this value, so a
          host can turn the room on and then remove one piece:

            haus.developer.enable = true;
            haus.developer.git.enable = false;  # …but leave Git tooling out
        '';
      };

      git.enable = lib.mkOption {
        type = lib.types.bool;
        default = config.haus.developer.enable;
        defaultText = lib.literalExpression "config.haus.developer.enable";
        description = ''
          Git and its surroundings: the shell alias vocabulary, the themed git
          config, delta (diff pager), lazygit, `gh`, and gnupg for commit
          signing. Off drops all of them, and `haus.git.*` then has
          nothing to configure.
        '';
      };

      toolbelt.enable = lib.mkOption {
        type = lib.types.bool;
        default = config.haus.developer.enable;
        defaultText = lib.literalExpression "config.haus.developer.enable";
        description = ''
          The terminal toolbelt: bat, fzf, fd, ripgrep, yazi, zoxide, lsd,
          glow, jq, tree, chafa, ttyd and fastfetch — the themed replacements
          for cat, find, grep, ls and friends that haus's shell is built
          around.

          Off leaves a plain shell. The prompt (starship) and the colour scheme
          stay: these are the *tools*, not the appearance.
        '';
      };

      # `ai.enable` was here until 2026-08-13. The AI capability is its own
      # room now (modules/ai) and its switch went with it, to `haus.ai.enable`
      # beside the rest of that room's namespace; modules/moved.nix keeps this
      # address working with a warning. Nothing about the developer pack changed:
      # the new option still defaults to `developer.enable`.

      languages = lib.mkOption {
        type = lib.types.listOf (lib.types.enum [ "node" ]);
        default = [ ];
        defaultText = lib.literalExpression "[ ]";
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

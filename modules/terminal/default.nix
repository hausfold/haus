# Terminal — the room you actually live in. The terminal experience: zsh, a
# Nebelung-tinted starship prompt, git, and a themed CLI toolbelt (bat, delta,
# lazygit, lsd, yazi, zoxide, fzf), plus the ghostty / zmx / yazi dotfiles.
#
# Identity is NOT baked in: git name/email/signing come from `haus.git.*`
# (set in your host), and secrets stay out of the store — they live in the
# secrets room's provider (secretspec; see modules/secrets), not in a dotfile
# this module reads.
{
  config,
  lib,
  pkgs,
  username,
  ...
}@args:

let
  # Same reason modules/ai reads it this way (see there): `hostname` is a
  # specialArg of the full builders and NOT of a bare `darwinModules.terminal`
  # import, where the consumer writes their own darwinSystem call. Naming it in
  # the argument set above made it mandatory, so this export refused to evaluate
  # for anyone who didn't happen to pass it — for one interpolation into a
  # script that opens a host file. The `standalone-modules` check now evaluates
  # every export without it.
  hostname =
    args.hostname or (
      if (config.networking.hostName or null) != null then config.networking.hostName else "this Mac"
    );

  gitCfg = config.haus.git;
  terminalCfg = config.haus.terminal;
  ghDashCfg = terminalCfg.ghDash;
  agentsCfg = config.haus.ai;
  accent = config.haus.theme.accent; # a Catppuccin accent name, e.g. "mauve"
  devCfg = config.haus.developer;

  # The chosen editor's row: what to install, whether Nebelung themes it, and
  # the command it answers to (which is `terminal.editor`'s default, so anything
  # that OPENS a file keeps reading `terminalCfg.editor` and never this).
  # modules/lib/editors.nix carries the table and the reasoning.
  editor = (import ../lib/editors.nix).${terminalCfg.editorName};

  # What the AI room contributes to the terminal, through the extension point
  # this room declares (modules/terminal/options.nix, modules/lib/contrib.nix).
  # The chords, the `c` alias and the cheatsheet rows read THIS, never
  # `haus.ai.*`: the AI room decides whether it has an agent to spawn, the
  # terminal decides how a chord for one is spelled.
  #
  # Its client PAYLOAD used to be read directly below — the packages, the
  # instructions/skill files and the per-client hook wiring — hosted here on the
  # theory that a home profile is where they can be written. That turned out to
  # be a habit rather than a constraint: modules/ai writes into the same
  # `home-manager.users.<name>` now and home-manager merges the two. What is
  # left here is the terminal's own business — the client packages a pane needs
  # on PATH, and the dotfiles this room themes. See modules/ai.
  agentContrib = config.haus._contrib.development.agents;
  agentDefault = agentContrib.default;
  agentNamer = agentContrib.namer;

  # One client id → one package, from the one table (modules/lib/agent-packages.nix):
  # the AI room asserts each named client is buildable here, and this is where a
  # home profile installs it.
  agentPackages = import ../lib/agent-packages.nix pkgs;
  agentClients = config.haus._ai.clients;

  fontsCfg = config.haus.fonts; # terminal font family/size (core installs the package)

  # ---- the terminal's hotkeys ------------------------------------------------
  #
  # ./term-bindings.nix is the one table of terminal chords + captions; pounce
  # renders the Terminal cards on the cheatsheet from it.
  #
  # It used to be cross-checked against zellij's config.kdl in both directions —
  # every bind taught, every taught chord bound — and that assertion is gone with
  # the kdl. There is nothing left for it to read: the chords it described are
  # now pounce appHotkeys entries (modules/launcher) — all but ⌘⇧R, which
  # ghostty/config binds natively — and a Nix assertion cannot see into another
  # room's generated JSON. The table and the appHotkeys list are
  # kept honest by living one screen apart and by the chord glyphs being derived
  # rather than typed.
  termBindings = import ./term-bindings.nix {
    inherit lib agentDefault;
    agentsEnabled = agentContrib.enable;
    ghDashEnabled = ghDashCfg.enable;
    benchLaneEnabled = devCfg.enable;
  };
  ghDashGhosttyBind = lib.optionalString ghDashCfg.enable ''
    # ⌘G — consumed by pounce (cmd:gh-dash): GitHub's review queue as a
    # near-fullscreen floating window. Ghostty owns this chord as search-next by
    # default, so it must be released explicitly or the tap is the only thing
    # standing between the chord and a find-again nobody asked for.
    keybind = cmd+g=unbind
  '';
  benchLaneGhosttyBind = lib.optionalString devCfg.enable ''
    # ⌘B — consumed by pounce (cmd:bench-lane): build+activate this window's scruff
    # LANE — this worktree plus every `scruff child` worktree spawned from it — in
    # one rebuild (`bench try lane switch`; "b" for bench, since ⌘L is Links).
    # Ghostty has no default binding on this chord; unbound defensively, same
    # reasoning as cmd+enter above, so a future default can't steal it.
    keybind = cmd+b=unbind
  '';
  ghosttyConfigTemplate =
    builtins.replaceStrings
      [
        "@GH_DASH_GHOSTTY_BIND@"
        "@BENCH_LANE_GHOSTTY_BIND@"
      ]
      [
        ghDashGhosttyBind
        benchLaneGhosttyBind
      ]
      (builtins.readFile ./ghostty/config);

  # System Settings deep links, spelled once (modules/lib/settings-panes.nix) —
  # a wrong x-apple.systempreferences: URL lands on the front page with no error.
  panes = import ../lib/settings-panes.nix;
in
{
  # ---- what this room contributes to other rooms ------------------------------
  # One thing: the script AeroSpace runs after focus changes. A lane blocked on
  # you parks a trill fin, and lanes/lane-seen.sh takes it down once you are
  # looking at that lane's window — which only the tiler can report, because two
  # lanes are two windows of one app. Presentation only, in the contract's
  # sense: with no windows room the fin still clears when the session moves
  # (scruff's own hooks), just later.
  #
  # This room used to hand windows the agent-spawn chord's script as well
  # (`_contrib.windows.agents`, when the chord was the global ⌃⌘A); ⌘↵ is a
  # Ghostty-scoped pounce hotkey now, and pounce reaches the same script through
  # its own `cmd:lane-here` command rather than through an option. The file this
  # room installs at ~/.config/haus/lanes/lane-spawn.sh is still the one thing
  # the chord runs.
  haus._contrib.windows.laneSeen = {
    enable = agentsCfg.enable;
    script = "/Users/${username}/.config/haus/lanes/lane-seen.sh";
  };

  # haus.terminal.floatOnTop asks a popup's own Ghostty process to raise that
  # window's level, and an Apple event to another application is Automation.
  # WHO is asking is the SUMMONER — the responsible process macOS books the
  # request against — so the grant is never this room's, even though this room
  # is what wants it. There are two summoners and they are granted separately:
  # pounce (the palette commands and the ⌘-chords its tap owns) and sketchybar
  # (the agents pill's peek, which calls float-term.sh itself). A user who
  # grants only the first still has an unpinned agent peek and no idea why,
  # which is the whole reason both are named in `steps`.
  #
  # Listed whenever the option is on rather than gated on pounce existing: a
  # bar-without-launcher machine has exactly one of the two summoners, and it is
  # the one whose grant does NOT survive a version bump (sketchybar is an
  # adhoc-signed store path; pounce is re-signed with a stable identity), so
  # that is the machine that needs the card most.
  #
  # No `check`, for the deck's first rule: every API that reports an Automation
  # grant asks for it first, and a permission dialog fired by `haus doctor` is
  # how people learn to stop running `haus doctor`. macOS asks by itself on the
  # first summon; the card is for the machine where that dialog was dismissed,
  # because the degraded state is otherwise indistinguishable from the option
  # being off.
  haus._contrib.permissions.terminal-float-on-top = lib.mkIf terminalCfg.floatOnTop {
    order = 32;
    title = "Automation — Ghostty, for whatever summons a popup";
    why = ''
      Keeping the ⌘Y peek panel, ⌘G's gh-dash, the bar's agent peek and the
      palette's own windows above the tiling means asking each popup's Ghostty
      process to raise its window level, and macOS books that request against
      whichever app summoned it rather than against haus.
    '';
    cost = "popups still open in front, then sink behind the first tiled window you click";
    pane = panes.automation;
    steps = [
      "Turn Ghostty on underneath Pounce — that covers ⌘Y, ⌘G and every palette window"
      "Turn Ghostty on underneath SketchyBar too, if you use the bar's agent peek — it summons its own popup and needs its own grant"
      "A popup already on screen keeps its old behaviour — summon a fresh one to check"
    ];
  };

  # The agent assertions that used to sit here — default-not-in-clients, clients
  # without the tooling, a client nixpkgs can't build — are the AI room's own
  # invariants and moved to modules/ai with its switch. They named only
  # `haus.ai.*`, and they have to fail the rebuild on a machine with no
  # terminal room at all.
  # Agent lanes used to ASSERT haus.windows.enable here, and that was one room
  # deciding another room's business. What actually needed the tiler was never
  # the lane — the zmx session that outlives its window, the hold-on-error, the
  # bar row, scruff's registry are all tiler-free — it was PLACEMENT (which has no
  # meaning without pages) and the window→session JOIN, which was spelled
  # AeroSpace in three scripts because AeroSpace was always there. Since
  # 2026-08-19 the join has a second spelling in Ghostty's own scripting API
  # (lanes/lane-open.sh has the two backends and the measurement that keeps them
  # apart), so a machine with no tiler gets working lanes in ordinary macOS
  # windows, and this is a warning about what it is missing rather than a
  # refusal to build.
  warnings = lib.optional (agentContrib.enable && !config.haus.windows.enable) (
    "haus.ai is on with haus.windows off: agent lanes will open as ordinary macOS windows. "
    + "Everything else works — ⌘↵ spawns, ⌘W detaches, the bar's agents pill goes to a lane and "
    + "peeks it — but nothing places them, so there are no per-repo T/<repo> pages and no page "
    + "walk (⌃⇥) to tile five agents across three repos. Turn haus.windows.enable on for those."
  );

  assertions = [
    {
      assertion = !ghDashCfg.enable || devCfg.git.enable;
      message =
        "haus.terminal.ghDash.enable is on but haus.developer.git.enable is off. gh-dash has no "
        + "login of its own — it reads the token `gh auth login` wrote — and the Git pack is what "
        + "installs `gh`, so the dashboard would open on a machine with nothing to authenticate "
        + "it, and every tab would be an error. Turn the Git pack on, or the dashboard off.";
    }
  ];

  # The six `zellij-unwrapped` patches that used to sit here are gone with the
  # multiplexer, and the record of what they bought is worth keeping in one
  # line each, because four of the six describe behaviour Ghostty now has to
  # provide (or doesn't) rather than behaviour we chose:
  #
  #   selection-autoscroll     drag past a pane edge scrolls at a rate set by
  #                            the distance. Ghostty autoscrolls a drag natively.
  #   no-ctrl-scroll-resize    stop ⌃scroll resizing panes so it reaches the
  #                            program (⌃scroll is zoom in an agent TUI).
  #                            Moot: no panes to resize.
  #   ctrl-click-fullscreen    ⌃click zooms a pane. Moot: a window is the pane,
  #                            and windows/AeroSpace has fullscreen on its own
  #                            chord.
  #   right-click-fullscreen   the same, on right-click, behind
  #                            haus.terminal.rightClickFullscreen. Retired with
  #                            the option (see modules/moved.nix).
  #   unstick-mouse-selection  a selection left "stuck" after the mouse left the
  #                            pane. A zellij-server bug, gone with the server.
  #   naked-click-links        open the OSC 8 / regex link under a BARE click.
  #                            NOT replaced: inside a mouse-tracking program the
  #                            click belongs to the program, and ghostty's own
  #                            opener is ⌘+click — no shift (see ghostty/config's
  #                            macos-option-as-alt block; ghostty consumes the
  #                            cmd-click itself rather than forwarding it).
  #
  # `copy-clean.pl` went the same way and is the one outright loss: it was a
  # zellij `copy_command` filter that stripped the padding zellij adds to
  # wrapped lines on copy, and Ghostty has no copy hook to hang it on.

  # The one thing terminal installs that isn't shell config: the tool the
  # file-association hijack drives. In the roster because that's where
  # everything this machine HAS lives — visible in `this-machine.md`,
  # overridable by app id from a host, and (see the note by home.packages) able
  # to collide loudly with a cask of the same name instead of silently.
  #
  # It is the only app this room installs. A media player used to sit here too,
  # purely because this room's hijack code was next door; an editorial pick is
  # not shell config, and modules/apps is the room whose whole job it is.
  haus.roster = {
    duti = {
      package = lib.mkDefault pkgs.duti;
    };
  };

  # The nebelung ports this room wires itself, so the roster pass in
  # modules/theme/ports.nix leaves them alone instead of dropping a second,
  # blunter copy beside the integration below. Most are sourced from the
  # rendered theme tree; starship, fzf and lazygit take the palette as Nix
  # values instead (they want colours inline in a config this room already
  # owns, not a file to point at) — either way the tool is handled here.
  # An assertion in theme/ports.nix checks every name is still a real port.
  #
  # gh-dash is the one conditional entry: unlike the rest, its integration is
  # opt-in (haus.terminal.ghDash.enable), and claiming a port this room only
  # sometimes wires would tell the roster pass "handled" on a machine where
  # nothing wires it — so a host that installed gh-dash itself would get no
  # theme AND no manual-step nudge from `haus doctor`.
  #
  # The chosen editor's port is the second one, for the same reason: on a
  # neovim machine this room installs no helix, so claiming helix here would
  # promise a theme for a tool that is not there. `editor.port` is null for
  # every editor Nebelung has no port for, which is all of them but helix.
  haus.theme.ports.handled = [
    "bat"
    "delta"
    "ghostty"
    "glow"
    "lsd"
    "obsidian"
    "opencode"
    "yazi"
    "zen"
    "zsh-syntax-highlighting"
    "starship"
    "fzf"
    "lazygit"
  ]
  ++ lib.optional (editor.port != null) editor.port
  ++ lib.optional ghDashCfg.enable "gh-dash"
  # nebelung's `stylus` port is `manual` because the userstyles are LESS that
  # only Stylus could compile — the import was the activation. Naming a slug in
  # haus.zen.userStyles compiles them here instead, which IS wiring that port,
  # so claim it and the roster pass stops nudging you toward an import dialog
  # for a file haus no longer writes.
  ++ lib.optional (config.haus.zen.userStyles != [ ]) "stylus";

  home-manager.users.${username} =
    {
      config,
      lib,
      pkgs,
      osConfig,
      nebelung,
      ...
    }:
    let
      swiftBin = pkgs.callPackage ../lib/swift-bin.nix { };

      # haus.theme.{flavor,contrast} select which rendered variant everything
      # below reads — see ../lib/nebelung.nix, which owns that resolution for
      # terminal, bar and theme alike (it was duplicated in all three the moment
      # `contrast` landed; the `flavor` axis would have made that six blocks).
      #
      # nbFlavor is not decoration. whiskers names its output after the flavor it
      # rendered, so every path below that used to say "mocha" is now built from
      # nbFlavor and a latte desktop resolves to catppuccin-latte.conf under the latte
      # root. Getting one wrong is invisible: the path just doesn't exist.
      nb = import ../lib/nebelung.nix {
        inherit lib nebelung;
        theme = osConfig.haus.theme;
      };
      nebelungRoot = nb.root;
      nebelungPalette = nb.palette;

      # The outline around the floating Ghostty popups (haus.terminal.floatBorder),
      # baked into float-term.sh below. Three words plus any Nebelung accent name
      # (the `or` branch): "grey" is surface0 — the same step off the background
      # the bar's dropdowns take — and "off" renders an empty colour, which is the
      # one thing float-term.sh's ring() checks, so the binary is never launched
      # (nor built — the store path is dropped from the script too, below).
      floatring = swiftBin {
        name = "floatring";
        src = ./floatring.swift;
        description = "Rounded accent/grey outline around another process's window, for the floating Ghostty popups";
      };

      # The pin that keeps those same popups above the tiled window you click
      # next (haus.terminal.floatOnTop), baked into float-term.sh below the same
      # way. A separate binary rather than a floatring verb: the ring is a
      # long-lived overlay process and the pin is one bounded round trip, and the
      # two options are independent — a machine with floatBorder = "off" still
      # wants its peek panel to stay put. Dropped from the script (and so from
      # the closure) when the option is off, exactly like floatring.
      floatpin = swiftBin {
        name = "floatpin";
        src = ./floatpin.swift;
        description = "Keep a Ghostty float-term popup above every tiled window, by window level";
      };
      floatBorderColor =
        {
          accent = nebelungPalette.${osConfig.haus.theme.accent};
          grey = nebelungPalette.surface0;
          off = "";
        }
        .${terminalCfg.floatBorder} or nebelungPalette.${terminalCfg.floatBorder};

      # AeroSpace's OUTER gaps, baked into float-term.sh's `geom --tiled` (⌘G,
      # ⌘⇧F, and ⌘F once ^s widens it — the popups whose scope IS the whole
      # desktop; ⌘Y stopped being one 2026-08-21, it covers its summoner). A
      # near-fullscreen popup wants the rectangle the tiled windows occupy,
      # not everything macOS leaves free: those differ by exactly these
      # gaps, and a popup sized to the latter overhangs every window it covers.
      # ../lib/gaps.nix is the same import modules/windows uses to write
      # aerospace.toml's [gaps] block — one arithmetic, three consumers (windows,
      # wallpaper, here), so a retuned gap moves the popup with the layout.
      floatGaps = import ../lib/gaps.nix {
        inherit lib;
        scale = osConfig.haus.ui.scale;
        bar = osConfig.haus.bar;
      };
      # Asserting a path spelled INTO a store output — here, the nebelung
      # glamour port baked into the yazi plugin below. ../lib/checked-ref.nix.
      checkedRef = import ../lib/checked-ref.nix { inherit lib pkgs; };
      nbFlavor = nb.flavor; # "mocha" | "latte"
      # The bat theme's name AND its filename, which whiskers title-cases:
      # "Catppuccin Mocha" / "Catppuccin Mocha.tmTheme". Named once because three
      # places reference it — bat's own config, delta's syntax-theme (inside the
      # rendered gitconfig) and yazi's syntect_theme — and they must agree exactly.
      batTheme = "Catppuccin ${nb.title}";
      # Yazi preview: pipe code/text through bat (via piper) so previews match
      # the catppuccin-themed `cat` alias — colours + line numbers.
      batPreviewer = ''piper -- bat --color=always --paging=never --style=numbers --tabs=2 --terminal-width=$w "$1"'';

      # Nebelung glamour port (markdown styling for glow), selected from the
      # same flavor + accent matrix as yazi itself. glow ignores
      # $GLAMOUR_STYLE in its default "auto" mode (glow 2.x), so the style must
      # be passed explicitly with `-s`: baked into the yazi previewer plugin
      # (@glowStyle@ placeholder) and the `glow -p` opener below.
      glowStyle = "${nebelungRoot}/glow/themes/${nbFlavor}/catppuccin-${nbFlavor}-${accent}.json";
      # The `guard` half of ../lib/checked-ref.nix rather than its `collect`:
      # what gets installed is the PLUGIN, and the glamour style is baked into
      # its text by substitution rather than copied. Why the check has to be
      # here and cannot be a reach check: `accent-reach` fingerprints this
      # plugin's TEXT, and the accent varies only INSIDE the path, so a missing
      # referent would still read `moves`. This is the one place the build can
      # see the file. `-f`, because a directory there would be as wrong as
      # nothing.
      glowPlugin = pkgs.runCommand "glow.yazi" { } (
        checkedRef.guard [
          {
            path = glowStyle;
            test = "-f";
            problem = [
              "terminal: the pinned nebelung renders no glamour port at"
              "  ${glowStyle}"
              "  (haus.theme.flavor/accent moved past what it ships)"
            ];
            remedies = [
              "haus.theme.accent — pick one the pinned nebelung renders"
              "haus.theme.flavor — the port matrix is rendered per flavor"
              "(haus authors) nix flake update nebelung"
            ];
          }
        ]
        + ''
          cp -r ${./yazi/plugins/glow.yazi} $out
          chmod -R +w $out
          substituteInPlace $out/main.lua --subst-var-by glowStyle ${glowStyle}
        ''
      );

      # A deliberately finite Git vocabulary, using the names that recur most
      # often in Oh My Zsh and other common alias sets. Avoid the notoriously
      # ambiguous one- and two-letter collisions (`gl` is pull or log, `gr` is
      # remote or rebase, `gs` is status or stash depending on the framework).
      # Hosts can add/replace entries — or set one to null — through
      # haus.git.shellAliases, without loading a shell framework.
      defaultGitShellAliases = {
        g = "git";

        ga = "git add";
        gaa = "git add --all";
        gapa = "git add --patch";

        gb = "git branch";
        gba = "git branch --all";
        gbd = "git branch --delete";
        gbD = "git branch --delete --force";
        gbm = "git branch --move";

        gco = "git checkout";
        gcb = "git checkout -b";
        gcl = "git clone";
        gsw = "git switch";
        gswc = "git switch -c";

        # `switch` and `restore` are the two halves git 2.23 split `checkout`
        # into, and this set had only the branch half — undoing a file was the
        # one everyday move it still sent you back to `git checkout -- <path>`
        # for, the spelling whose whole problem is that it means two things.
        # They sit here rather than beside `grb` for that reason.
        grs = "git restore";
        grss = "git restore --source";
        grst = "git restore --staged";

        gc = "git commit --verbose";
        gca = "git commit --verbose --all";
        gcam = "git commit --all --message";
        gcp = "git cherry-pick";
        gcpa = "git cherry-pick --abort";
        gcpc = "git cherry-pick --continue";
        gcmsg = "git commit --message";
        gcn = "git commit --verbose --no-edit";

        gd = "git diff";
        gds = "git diff --staged";
        gdw = "git diff --word-diff";

        gf = "git fetch";
        gfa = "git fetch --all --tags --prune";
        gfo = "git fetch origin";

        glo = "git log --oneline --decorate";
        glog = "git log --oneline --decorate --graph";
        gloga = "git log --oneline --decorate --graph --all";

        gm = "git merge";
        gma = "git merge --abort";
        gmc = "git merge --continue";
        gmff = "git merge --ff-only";

        gpl = "git pull";
        gpr = "git pull --rebase";
        gp = "git push";
        gpf = "git push --force-with-lease";
        gpsup = "git push --set-upstream origin HEAD";

        grb = "git rebase";
        grba = "git rebase --abort";
        grbc = "git rebase --continue";
        grbi = "git rebase --interactive";
        grbs = "git rebase --skip";
        grt = "cd \"$(git rev-parse --show-toplevel)\"";
        grv = "git remote --verbose";

        gst = "git status";
        gss = "git status --short";
        gsb = "git status --short --branch";

        gsta = "git stash push";
        gstl = "git stash list";
        gstp = "git stash pop";
        gsts = "git stash show --patch";

        gt = "git tag";

        gwt = "git worktree";
        gwta = "git worktree add";
        gwtl = "git worktree list";
        gwtr = "git worktree remove";
      };
      gitShellAliases = lib.filterAttrs (_name: command: command != null) (
        defaultGitShellAliases // gitCfg.shellAliases
      );

      # The accent colour (haus.theme.accent, default mauve) as the hex the
      # tools haus injects colours into use for their accent.
      accentColor = nebelungPalette.${accent};
      # Zen browser accent. The nebelung zen port renders every accent under
      # themes/<Flavor>/<Accent>/ (both capitalised); yazi uses lowercase for both.
      zenAccent =
        lib.toUpper (lib.substring 0 1 accent) + lib.substring 1 (lib.stringLength accent) accent;
      zenTheme = "${nebelungRoot}/zen/themes/${nb.title}/${zenAccent}";

      # The sites half of Zen's user sheet (haus.zen.userStyles). nebelung's
      # userContent.css covers `about:` pages and nothing else; this is the
      # compiled Nebelung userstyles for the sites you named, appended to it, so
      # one file goes into the profile either way and the activation below stays
      # a single symlink.
      #
      # Appended rather than installed beside it because Firefox reads exactly
      # one userContent.css per profile — there is no `.d` directory and no
      # @import that would survive (see package-userstyles.nix). Order is
      # deliberate: nebelung's `about:` rules first, the sites after, which is
      # also the order they'd have been written in by hand.
      # Sorted and deduped HERE rather than in the script: the list reaches the
      # derivation through its environment verbatim, so `[ "github" "youtube" ]`
      # and `[ "youtube" "github" ]` would otherwise be two store paths with
      # byte-identical contents — a rebuild for a reordering, measured.
      zenUserStyleSlugs = lib.unique (lib.sort (a: b: a < b) osConfig.haus.zen.userStyles);
      zenUserStyles = pkgs.callPackage ./package-userstyles.nix {
        bundle = "${nebelungRoot}/stylus/nebelung-stylus.json";
        styles = zenUserStyleSlugs;
        inherit (osConfig.haus.theme) accent;
        flavor = nbFlavor;
      };
      zenUserContent =
        if osConfig.haus.zen.userStyles == [ ] then
          "${zenTheme}/userContent.css"
        else
          pkgs.runCommand "zen-userContent-${nbFlavor}-${accent}.css" { } ''
            cat ${zenTheme}/userContent.css ${zenUserStyles} > "$out"
          '';
      obsidianTheme = "${nebelungRoot}/obsidian/Nebelung";
      ghDashTheme = "${nebelungRoot}/gh-dash/themes/${nbFlavor}/catppuccin-${nbFlavor}-${accent}.yml";

      # The house queue, in two halves, because only one of them needs an owner.
      #
      # A gh-dash section is a GitHub search filter, and the PR tabs below are
      # scoped by `org:` — so haus.git.org is what makes them shippable at all,
      # and with no owner set Terminal writes none of them rather than guessing.
      # The self tabs (`@me`, `is:unread`) name no owner, so gating them on one
      # would only take four good tabs away from the machine that reads several
      # owners at once — exactly the machine the option tells to leave it empty.
      #
      # Everything else about a queue — which repos are checked out where,
      # which key runs which command, how wide the columns are — describes a
      # machine rather than an owner, and stays the host's in
      # programs.gh-dash.settings.
      #
      # Each list is separately mkDefault: a host replacing prSections keeps
      # the issue and notification tabs, and vice versa. Per-list rather than
      # per-tab by necessity — gh-dash reads a section list as a whole, and
      # there is no merge of two tab lists that isn't a guess about order.
      ghDashOrgTabs = {
        # Ordered by how often you look at them.
        #
        # `is:open`, NOT `is:unmerged`: unmerged means "not merged", which is
        # true of every closed-without-merging PR forever, so the live tabs
        # slowly fill with abandoned branches. `is:open` is open + draft and
        # nothing else — exactly the working queue. `shipped` is the only tab
        # here that looks at finished PRs.
        prSections = lib.mkDefault [
          {
            title = "open";
            filters = "org:${gitCfg.org} is:pr is:open";
          }
          # green and red sit side by side because together they ARE the merge
          # decision: green is the queue a ship can take, red is the queue that
          # needs a session reopened. `status:` reads the check state of a PR's
          # head commit, so a branch still building shows in neither — which is
          # the point, that's the "come back in a minute" bucket.
          {
            title = "green";
            filters = "org:${gitCfg.org} is:pr is:open status:success";
          }
          {
            title = "red";
            filters = "org:${gitCfg.org} is:pr is:open status:failure";
          }
          # One week of landings. `nowModify` is gh-dash's own template
          # function; GitHub's `merged:` qualifier wants the rendered date
          # immediately after >=, with no spaces around the operator.
          {
            title = "shipped";
            filters = ''is:pr is:merged org:${gitCfg.org} merged:>={{ nowModify "-7d" }}'';
            limit = 10;
          }
        ];

      };

      # The half that asks who you are rather than where you work, and so ships
      # with the dashboard itself.
      ghDashSelfTabs = {
        # Not org-scoped, unlike the PR tabs: an issue you filed or were handed
        # matters wherever it is, and the one in somebody else's repo is the one
        # you're most likely to forget.
        issuesSections = lib.mkDefault [
          {
            title = "mine";
            filters = "is:open author:@me";
          }
          {
            title = "assigned";
            filters = "is:open assignee:@me";
          }
        ];

        # gh-dash ships EIGHT notification tabs. Two.
        #
        # `is:unread` rather than an empty filter, even though the tab is
        # already called unread: with no filters gh-dash matches GitHub's own
        # default and returns read notifications too (that's
        # `includeReadNotifications`, which defaults to true). An explicit
        # `is:unread` overrides it for this section, so the tab's count is a
        # number of things you haven't seen — the only number worth a tab.
        notificationsSections = lib.mkDefault [
          {
            title = "unread";
            filters = "is:unread";
          }
          {
            title = "participating";
            filters = "reason:participating";
          }
        ];
      };

      # Two edits to gh-dash, for two different surfaces.
      #
      # 1. The CLI banner (`gh dash --help`) hardcodes gh-dash's own wordmark.
      #    Once Terminal owns the dashboard integration, the house mark belongs
      #    there: patch the same-width glyphs in place. --replace-fail makes an
      #    upstream redraw a loud build failure instead of silently putting the
      #    stock mark back. This is the ONLY place the mark survives — the TUI
      #    no longer draws it at all (see below) — and it keeps gh-dash's own
      #    hardcoded cyan, because the theme-following colour we used to inject
      #    only ever applied to the TUI copy that's now gone.
      #
      # 2. plain-chrome.patch strips the TUI's decoration. gh-dash spends its
      #    header's right slot on the wordmark + version string, and a whole
      #    bottom row on a coloured bar carrying a view switcher, repo/user
      #    pills and a donate link. In a full-window Cmd-G overlay none of that
      #    is information — the section tabs already say which view you're in,
      #    and the version renders as "dev" no matter what nixpkgs stamps into
      #    `cmd.Version`, because the TUI takes its version from
      #    `debug.ReadBuildInfo()` (ui.go) and a from-source Go build leaves
      #    `Main.Sum` empty. So: the header slot carries the `? help` hint
      #    instead, and the footer bar goes unstyled. The footer ROW is
      #    deliberately kept (one blank line): it is also where y/N prompt
      #    confirmations, the list pager and running-task status are drawn —
      #    each still carrying its own background, so they read as an island on
      #    a bare row — and it is what `?` expands the full keymap out of.
      #    Blanking it outright would hide a prompt that still eats the
      #    keypress. A patch file rather than more substituteInPlace because the
      #    edits are multi-line Go; it fails just as loudly on an upstream bump,
      #    which is the point — a nixpkgs bump that reshapes footer.go or
      #    tabs.go now fails the whole system build on a ghDash host.
      #
      # One thing deliberately NOT wired into this override, with the reason kept
      # so nobody has to rediscover it: gh-dash has a FOURTH view — the local
      # repo's branches, each with its PR and checks — behind an `FF_REPO_VIEW`
      # env-var feature flag, and it looks like the git-side twin of the agent
      # HUD (scruff's branches, seen from GitHub). It is not usable yet, in two
      # distinct ways, both measured on 4.25.2 rather than guessed:
      #
      #   1. Flag on, cwd outside a git repo → gh-dash doesn't degrade, it EXITS
      #      on startup with `FATA … failed parsing config file … not a git
      #      repository`. The message is a lie about which thing failed (ui.go
      #      reuses one `showError` closure for the config parse and for the
      #      git-remote lookup), and it means `gh-dash` from ~ simply quits.
      #      Survivable — a wrapper could set the flag only inside a repo.
      #   2. Flag on, cwd inside a repo, press `s` three times to reach the view
      #      → nil-pointer panic in `branch.(*Branch).renderRepoName`
      #      (branch/branch.go:170), taking the whole TUI down. Reproduced in two
      #      different repos; the 3-view cycle with the flag off is fine, so it's
      #      the view, not the key. That one no wrapper can fix.
      #
      # So this stays stock until upstream ships the view unflagged. Retesting is
      # two commands (`FF_REPO_VIEW=1 gh-dash` in a repo, then `sss`) — worth
      # doing on a gh-dash bump, because the view is genuinely wanted.
      ghDashPkg = pkgs.gh-dash.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./gh-dash/patches/plain-chrome.patch ];
        postPatch = (old.postPatch or "") + ''
          substituteInPlace internal/tui/constants/constants.go \
            --replace-fail '▜▔▚▐▔▌▚▔▐ ▌' '▐ ▌▐▔▌▐ ▌▚▔' \
            --replace-fail '▟▁▞▐▔▌▁▚▐▔▌' '▐▔▌▐▔▌▙▁▟▁▚'
        '';
      });

    in
    {
      home.sessionVariables = {
        CLICOLOR = "1";
        HOMEBREW_NO_ENV_HINTS = "1";
        EDITOR = terminalCfg.editor;
        VISUAL = terminalCfg.editor;
        # 🚨 The name is a cross-repo contract — don't rename it here alone.
        # `scruff` reads it as the LOWEST rung of `defaultAgent`
        # (`internal/commands/env.go`), below `~/.config/scruff/config.toml`'s
        # `agent =` — which this module also writes, but only under
        # `haus.ai.enable`. So this is what answers for a machine with the
        # agent room off, and it is the only rung a standalone scruff install
        # gets for free.
        HAUS_AGENT_DEFAULT = agentDefault;
      };

      # A lean terminal/dev toolbelt, gated by the developer pack. Personal
      # choices (AI CLIs, orbstack, your language toolchains) belong in your
      # host file, not the public desktop.
      home.packages =
        with pkgs;
        # duti is a roster entry (below, at the darwin level) rather than a
        # bare package — the room that installs an app declares it, and the
        # roster is what makes a second copy from a cask a build warning
        # instead of the silent duplicate it was for months (modules/roster
        # tells the story).
        lib.optionals devCfg.toolbelt.enable [
          chafa # fast terminal image previewer / layout engine
          glow # markdown renderer; yazi's glow previewer shells out to it
          fd # fast finder; used by yazi/zoxide navigation
        ]
        # Editing haus's own Nix is a developer activity; `haus edit` still
        # works without a formatter. `nixfmt`, not `nixfmt-rfc-style`: nixpkgs
        # aliased the latter to the former and now warns on every eval.
        ++ lib.optional devCfg.enable nixfmt
        ++ lib.optionals (builtins.elem "node" devCfg.languages) [
          bun
          fnm # node version manager (used by the initContent below)
        ]
        # The chosen editor, unless it is helix — that one arrives through
        # `programs.helix` below, which carries its settings and theme too.
        ++ lib.optional (editor.package != null) pkgs.${editor.package}
        # The coding-agent clients, one package per `ai.clients` entry.
        # Unlisted means uninstalled, and `ai.default` is asserted to be a
        # member — so the client the palette is about to spawn is on PATH by
        # construction, rather than discovered missing inside the pane.
        ++ map (c: agentPackages.${c}) agentClients
        # zmx — what a lane opens into. `lane-open.sh` defers to scruff's
        # built-in if it can't find zmx, so a missing binary degrades to a pane
        # rather than a dead lane; shipping the package is what stops it having
        # to find out at spawn time. From nixpkgs rather than upstream's flake:
        # that one builds through zig2nix, whose zon2json helper is IFD, so
        # merely EVALUATING a darwin system tried to build an aarch64-darwin
        # derivation — which CI, on Linux, cannot do. Same version either way.
        ++ lib.optional agentsCfg.enable pkgs.zmx;

      programs.zsh = {
        enable = true;
        enableCompletion = true;
        autosuggestion.enable = true;
        syntaxHighlighting.enable = true;

        # ~/.zshenv — sourced by EVERY zsh (interactive or not, login or not),
        # before zshrc and before home-manager's zoxide init. Keeping _ZO_DOCTOR
        # here rather than in initContent means non-interactive shells (Claude
        # agents, anything that shells out) also silence zoxide's false-positive
        # doctor warning — zshrc is interactive-only, so it never reached them.
        envExtra = ''
          export _ZO_DOCTOR=0
        '';

        # Each alias follows its own pack: aliasing `cat` to a bat that is not
        # installed would leave a shell that greets you with "command not found".
        shellAliases =
          lib.optionalAttrs devCfg.git.enable (gitShellAliases // { lg = "lazygit"; })
          # `c` is "the agent", not "claude" — it follows haus.ai.default
          # so a Codex or Opencode machine doesn't alias a client it never installs.
          // lib.optionalAttrs agentContrib.enable { c = agentDefault; }
          // lib.optionalAttrs devCfg.toolbelt.enable {
            cat = "bat --style=header,grid --tabs=2";
            ls = "lsd";
          }
          // {
            # mdcat's replacement: the same themed glow yazi's previewer uses, so
            # a terminal `mdcat file.md` renders markdown identically to the yazi
            # right-pane preview (Nebelung glamour port, tables and all).
            mdcat = ''glow -s "${glowStyle}"'';
          };

        history = {
          size = 5000;
          save = 5000;
          ignoreDups = true;
          ignoreSpace = true;
          path = "$HOME/.zsh_history";
        };

        historySubstringSearch.enable = true;

        plugins = [
          {
            name = "fzf-tab";
            src = pkgs.zsh-fzf-tab;
            file = "share/fzf-tab/fzf-tab.plugin.zsh";
          }
        ];

        initContent = lib.mkMerge [
          (lib.mkBefore ''
            export GPG_TTY=$(tty)

            # zoxide's doctor wants its init to be the LAST thing in the zshrc,
            # but home-manager injects `zoxide init` early — and we deliberately
            # add chpwd hooks after it (fnm --use-on-cd).
            # Those coexist fine with zoxide's `cd` override (see programs.zoxide
            # below), so the doctor is a false positive; it's silenced via
            # _ZO_DOCTOR=0 in the envExtra above (~/.zshenv) so agent shells —
            # which never source the interactive-only zshrc — get it too.

            # Homebrew (Apple Silicon)
            eval "$(/opt/homebrew/bin/brew shellenv)"

            # Secrets: prefer secretspec (ships with haus) — a project
            # declares its secrets in a committed secretspec.toml and
            # `secretspec run -- cmd` injects the values from your provider
            # (haus.secrets.provider) into just that process, nothing
            # plaintext on disk. Anything you truly need in EVERY shell,
            # export in your HOST file's initContent (this is the public desktop).

            # Custom completions: a dir you drop (or symlink) a `_foo` into,
            # for a CLI whose completion lives beside it in a checkout rather
            # than in a package. It has to be prepended HERE, in the block that
            # lands ABOVE home-manager's `compinit` — it used to sit further
            # down the zshrc, past the point compinit had already walked fpath,
            # so the dir was only ever scanned by accident: in a shell that
            # inherited an already-extended FPATH from a parent that got this
            # far. A top-level shell silently had no _foo at all. Prepended
            # rather than appended on purpose — the reason to keep a completion
            # in a checkout is for it to beat the packaged one.
            #
            # The glob asks both questions at once: does the dir exist, and is
            # it free of group/world write. compinit refuses to trust one that
            # isn't — it warns and then BLOCKS on a y/n prompt, and a shell with
            # no tty answers that by aborting completion entirely, fzf-tab
            # included. Harmless while this sat below compinit; above it, a dir
            # that arrived 0777 (an rsync from another box, a copy off exFAT)
            # would take the whole shell's completion down with it. So skip it
            # and say why once, rather than letting compinit ask.
            _haus_comps=(~/.zsh-completions(N/^WI))
            if (( $#_haus_comps )); then
              fpath=($_haus_comps $fpath)

              # A completion symlinked out of an agent worktree outlives the
              # worktree: scruff reaps the checkout, the link dangles, and
              # compinit (which reads the first line of every file it globs)
              # names the missing path in EVERY shell after that. A reaped
              # worktree never comes back, so drop links pointing into one.
              # Anything else that dangles is left alone and left noisy — an
              # unmounted volume comes back, and a link YOU made is yours to
              # fix, not ours to delete.
              for _haus_stale in $_haus_comps[1]/*(-@N); do
                # Either base: the scruff-named one, and the legacy path until
                # its one-release symlink is removed (scruff's docs/rename.md
                # §8.2 — the legacy spelling dies with that symlink at 1.2.0).
                [[ "$(readlink -- "$_haus_stale")" == "$HOME/.cache/scruff/"* ||
                   "$(readlink -- "$_haus_stale")" == "$HOME/.cache/claude-worktrees/"* ]] &&
                  rm -f -- "$_haus_stale"
              done
            elif [[ -d ~/.zsh-completions ]]; then
              print -u2 "haus: ignoring ~/.zsh-completions — it is group- or world-writable (chmod 755 it)"
            fi
            unset _haus_comps _haus_stale
          '')
          ''
            # Nebelung zsh-syntax-highlighting colours (replaces catppuccin's
            # port). Sourced before the plugin loads — like catppuccin did —
            # which is fine: ZSH_HIGHLIGHT_STYLES is read at highlight time.
            source ${nebelungRoot}/zsh-syntax-highlighting/themes/catppuccin_${nbFlavor}-zsh-syntax-highlighting.zsh

            ${lib.optionalString (builtins.elem "node" devCfg.languages) ''
              # fnm (Node version manager)
              export PATH="$HOME/.fnm:$PATH"
              eval "$(fnm env --use-on-cd --shell zsh)"
            ''}

            bindkey -e

            setopt appendhistory
            setopt sharehistory
            setopt hist_ignore_space
            setopt hist_ignore_all_dups
            setopt hist_save_no_dups
            setopt hist_ignore_dups
            setopt hist_find_no_dups

            # `#` starts a comment at the prompt, as it does in a script. zsh
            # leaves this OFF interactively, which means a pasted block with a
            # comment line in it does not do what the block says: the comment
            # runs as a command, prints "#: command not found", and — the part
            # that actually costs you — every line AFTER it runs anyway. Paste
            # a four-line recipe whose third line is "# now close the lid" and
            # the fourth line undoes the second, in four seconds, silently.
            # Every other shell here treats it as a comment; so should this one.
            setopt interactive_comments

            zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
            zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
            zstyle ':completion:*' menu no

            # New shells inherit the spawning surface's cwd — the ⌘N shell
            # window, the peek's Enter-on-dir window, a lane's own window. Next
            # to an agent's window that cwd is the agent's throwaway checkout
            # under ~/.cache/claude-worktrees, and a fresh interactive shell has
            # no business starting there: hop to the repo the worktree belongs
            # to (the parent of the shared .git).
            # $CLAUDECODE spares the agent's own subshells, and $HAUS_STAY
            # spares the deliberate "stay here" spawns — ⌘⇧N, and the
            # Enter-on-dir window of a ⌘⇧Y (--stay) peek, which bakes
            # HAUS_STAY=1 into the window's environment. Those must stay in the
            # worktree; the ⌘Y peek's Enter window is NOT spared, because that
            # peek was rooted at the main checkout to begin with.
            # Both fire once at shell birth, so unset HAUS_STAY afterward to
            # keep it out of child processes and later cd's.
            # Gated to the surface haus spawns — a Ghostty window — because
            # the hop is about ITS cwd inheritance. A third-party terminal (an
            # editor's integrated one, ssh) opened deliberately inside a
            # worktree must not be teleported out of it.
            if [[ "$TERM_PROGRAM" == ghostty ]] &&
               [[ -z "$CLAUDECODE" && -z "$HAUS_STAY" &&
                  ( "$PWD" == "$HOME/.cache/scruff/"* || "$PWD" == "$HOME/.cache/claude-worktrees/"* ) ]]; then
              # Either base name: scruff's own, and the legacy path until its
              # one-release symlink goes (docs/rename.md §8.2, at 1.2.0). A
              # lane opened through the symlink has a PWD spelling the legacy
              # way but the SAME gitdir as its scruff-named spelling.
              _wt_main="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
              [[ -n "$_wt_main" ]] && cd "''${_wt_main:h}"
              unset _wt_main
            fi
            unset HAUS_STAY

            # `reset`, minus 1979. The stock one is /usr/bin/reset — a link to
            # tset(1) — and it spends a full second in a sleep(1) 3BSD added so
            # mechanical printer-and-ink terminals could settle down. Measured
            # here: 1012 ms for the system binary, 7-10 ms for the two lines
            # below, which is the difference between a repair you reach for and
            # one you sit through. It is a FUNCTION shadowing the command, on
            # purpose and in the same spirit as the `cat`/`ls` aliases above:
            # `reset` is the muscle memory, and a second name is one more thing
            # to remember at the exact moment you can't see what you're typing.
            # Interactive shells only — zsh functions are not exported, so a
            # script that calls `reset` still gets the real tset.
            #
            # The two halves, which is why neither line is redundant:
            #   stty sane   the KERNEL tty — canonical mode, echo, signals,
            #               CR/NL and output processing. Needed because the
            #               `tput` this reaches is Apple's, and Apple's is
            #               ncurses 6.0.20150808 — older than the 2016 commit
            #               that moved termios repair into `tput reset`, so it
            #               alone leaves a shell in raw mode with no echo
            #               (measured). A host that puts a nix ncurses ahead of
            #               /usr/bin gets a tput that would do this half too;
            #               the line stays either way, since the machine this
            #               ships to is the one with the old one. Its cost over
            #               what tset does is a custom erase key: `sane`
            #               restores the stock control characters rather than
            #               preserving yours.
            #   the drain   the typeahead you mashed into a terminal that was
            #               not listening. `stty sane` restores modes without
            #               flushing the input queue, so without this every
            #               blind keystroke arrives the moment the line editor
            #               starts reading and RUNS — measured: 12 characters
            #               and a return, still queued, still executed. rst
            #               discards them with TCSAFLUSH; zsh can just read
            #               them. Guarded on a tty so `reset` in a pipeline
            #               reads nothing.
            #   tput reset  the EMULATOR — the terminal's own rs1/rs2/rs3 reset
            #               strings out of terminfo. The explicit printf ahead
            #               of it turns off the modes a crashed TUI leaves
            #               armed that not every reset string covers: mouse
            #               reporting (1000/1002/1003/1006), focus events,
            #               bracketed paste, synchronized output, alt screen.
            #
            # `reset -I && tput reset` is the more common recipe and it is a
            # TRAP on this desktop: with TERM=xterm-ghostty and no TERMINFO in
            # the environment — sudo, su, ssh out to an older host — tset can't
            # find the entry and PROMPTS "Terminal type?", so the command you
            # typed blind hangs forever waiting for an answer you can't see it
            # asking for (measured). Nothing here consults terminfo before it
            # has already made the tty readable, and tput failing just falls
            # through to the hardcoded VT sequence.
            reset() {
              # Arguments are tset's job (`reset -Q`, `reset vt100`): hand those
              # to the real binary rather than half-implementing TERM negotiation.
              if (( $# )); then
                command reset "$@"
                return
              fi
              stty sane 2>/dev/null
              if [[ -t 0 ]]; then
                while read -t 0 -k 1 -u 0 _; do :; done
              fi
              printf '\033[?1000l\033[?1002l\033[?1003l\033[?1006l\033[?1004l\033[?2004l\033[?2026l\033[?1049l'
              tput reset 2>/dev/null || printf '\033c\033[!p\033[?3;4l\033[4l\033>'
            }

            # The chpwd hook that renamed the zellij tab after the repo is
            # gone with the tabs. A window's name is not ours to write: for a
            # lane it is a FORCED --title carrying the `scruff.<repo>.<lane>` join
            # (lanes/lane-open.sh), and for a plain window it is whatever the
            # program inside emits as OSC 2 — which is the right answer, since
            # the thing the bar and the switcher need to see is what you are
            # running, not which directory you last cd'd into.
          ''
        ];
      };

      # Starship, tinted with the Nebelung palette instead of the stock flavor (the
      # whiskers starship port emits exactly this [palettes.catppuccin_<flavor>]
      # table; we inject the same name->#hex map so there's no duplication).
      programs.starship = {
        enable = true;
        enableZshIntegration = true;
        settings = {
          gcloud.disabled = true;
          palette = "catppuccin_${nbFlavor}";
          palettes."catppuccin_${nbFlavor}" = nebelungPalette;
        };
      };

      # Git — identity comes from haus.git.* (your host sets it).
      programs.git = {
        enable = devCfg.git.enable;

        # Nebelung delta theme: defines [delta "catppuccin-<flavor>"] (referenced
        # by programs.delta.options.features below). Rendered by whiskers in the
        # nebelung flake; replaces the catppuccin.delta module's include.
        #
        # Gotcha worth keeping: this ONE file carries a section for all four
        # catppuccin flavors, and only the flavor it was rendered as holds Nebelung
        # colours — the other three are stock upstream. So `features` below must
        # name the same flavor as the variant root this include came from, or delta
        # silently themes itself in stock Catppuccin. Both read nbFlavor, which is
        # what keeps them agreeing.
        includes = [ { path = "${nebelungRoot}/delta/catppuccin.gitconfig"; } ];
        signing = lib.mkIf (gitCfg.signingKey != "") {
          key = gitCfg.signingKey;
          signByDefault = true;
        };
        settings = {
          user.name = gitCfg.name;
          user.email = gitCfg.email;
          color.ui = "auto";
          push.autoSetupRemote = true;
          tag.gpgSign = gitCfg.signingKey != "";
        };
      };

      programs.delta = {
        enable = devCfg.git.enable;
        enableGitIntegration = true;
        options = {
          side-by-side = false;
          line-numbers = true;
          # Nebelung delta styles: the [delta "catppuccin-<flavor>"] feature is
          # defined in the whiskers-rendered gitconfig included via
          # programs.git.includes above (see the flavor gotcha there). Its
          # syntax-theme points at the matching bat theme, in Nebelung colours.
          features = "catppuccin-${nbFlavor}";
        };
      };

      # Nebelung theme (mauve accent) injected straight into settings from
      # nebelungPalette — mirrors catppuccin/lazygit's theme for the selected
      # flavor in Nebelung colours (see the lazygit port in the nebelung repo for
      # the file form). Injected rather than sourced, so it follows the palette
      # without needing the flavor in a path.
      programs.lazygit = {
        enable = devCfg.git.enable;
        settings.gui = {
          theme = {
            activeBorderColor = [
              accentColor
              "bold"
            ];
            inactiveBorderColor = [ nebelungPalette.subtext0 ];
            searchingActiveBorderColor = [ nebelungPalette.yellow ];
            optionsTextColor = [ nebelungPalette.blue ];
            selectedLineBgColor = [ nebelungPalette.surface0 ];
            inactiveViewSelectedLineBgColor = [ nebelungPalette.overlay0 ];
            cherryPickedCommitFgColor = [ accentColor ];
            cherryPickedCommitBgColor = [ nebelungPalette.surface1 ];
            markedBaseCommitFgColor = [ nebelungPalette.blue ];
            markedBaseCommitBgColor = [ nebelungPalette.yellow ];
            unstagedChangesColor = [ nebelungPalette.red ];
            defaultFgColor = [ nebelungPalette.text ];
          };
          authorColors."*" = nebelungPalette.lavender;
        };
      };

      programs.lsd.enable = devCfg.toolbelt.enable;
      programs.lsd.enableZshIntegration = false;

      # Theme is the Nebelung-coloured "Catppuccin <Flavor>" tmTheme from the
      # nebelung flake. The UPSTREAM name is kept (rather than renamed to
      # "Nebelung") because delta's syntax-theme and yazi's syntect_theme both
      # reference it by that name — and the whiskers-rendered files on the other end
      # of those references are flavor-named too, so all three move together.
      # programs.bat.themes rebuilds the bat cache on activation so it's picked up.
      programs.bat = {
        enable = devCfg.toolbelt.enable;
        config = {
          style = "header,grid";
          tabs = "2";
          theme = batTheme;
        };
        themes.${batTheme} = {
          src = "${nebelungRoot}/bat/themes";
          file = "${batTheme}.tmTheme";
        };
      };

      programs.yazi = {
        enable = devCfg.toolbelt.enable;
        enableZshIntegration = true;
        shellWrapperName = "yy";
        settings.mgr.show_hidden = true;
        settings.mgr.ratio = [
          2
          5
          6
        ];
        # Default preview caps (600×900 px) leave kitty-protocol previews soft
        # on a retina display; size them for the near-fullscreen peek window.
        settings.preview.max_width = 2400;
        settings.preview.max_height = 1800;
        plugins = {
          # Vendored: nixpkgs' glow plugin still uses the pre-26 Lua API and
          # crashes on yazi 26.x. This copy ports it to the current API, and
          # bakes the Nebelung glamour style path in (glowPlugin, see the let).
          glow = glowPlugin;
          piper = pkgs.yaziPlugins.piper;
          # Vendored (not in nixpkgs yet): copy the hovered/selected file(s)'
          # contents — not their path — to the clipboard. `setup` makes
          # home-manager emit the require(...):setup() call in init.lua;
          # notification = a toast on copy so there's UI feedback.
          copy-file-contents = {
            package = ./yazi/plugins/copy-file-contents.yazi;
            setup = true;
            settings = {
              append_char = "\n";
              notification = true;
            };
          };
          # peek-open: Enter inside the ⌘Y peek overlay. On a directory it
          # spawns a new Ghostty WINDOW cwd'd there (the old browse-and-pick tab
          # picker, folded in here); on a file it pages as normal. Gated on
          # PEEK=1 (set only by
          # peek-run.sh), so in a plain `yy` session it's a no-op passthrough to
          # yazi's default Enter. See yazi/plugins/peek-open.yazi.
          peek-open.package = ./yazi/plugins/peek-open.yazi;
        };
        keymap.mgr.prepend_keymap = [
          {
            on = "<Esc>";
            run = "quit";
            desc = "Close the peek browser";
          }
          {
            # cmd+c can't reach a TUI (the terminal eats the Cmd modifier), so
            # copy-contents lives on Y. `desc` surfaces it in yazi's help (~).
            on = "Y";
            run = "plugin copy-file-contents";
            desc = "Copy file contents to clipboard";
          }
          {
            # Enter routes through peek-open: in the peek overlay a directory
            # opens a new window there, a file pages fullscreen; everywhere
            # else it's plain `open` (yazi's default Enter). See peek-open.yazi.
            on = "<Enter>";
            run = "plugin peek-open";
            desc = "Peek: open dir in a window / page file (else default open)";
          }
        ];
        settings.plugin.prepend_previewers = [
          {
            url = "*.md";
            run = "glow";
          }
          {
            url = "*.mdx";
            run = "glow";
          }
          {
            mime = "text/*";
            run = batPreviewer;
          }
          {
            mime = "*/{xml,javascript,x-wine-extension-ini}";
            run = batPreviewer;
          }
          {
            mime = "application/{json,ndjson}";
            run = batPreviewer;
          }
        ];
        settings.opener = {
          read = [
            {
              # glow otherwise reads its global width (80 columns by default),
              # even though Enter has suspended yazi and given it the whole
              # terminal. Resolve the live terminal width at open time so the
              # fullscreen pager wraps where the visible window ends.
              run = ''glow -s "${glowStyle}" -w "$(tput cols)" -p "$@"'';
              block = true;
              desc = "glow";
            }
          ];
          pager = [
            {
              run = ''bat --style=full --paging=always "$@"'';
              block = true;
              desc = "bat";
            }
          ];
          image_preview = [
            {
              run = ''~/.config/haus/term/image-preview.sh "$@"'';
              block = true;
              desc = "Preview";
            }
          ];
          open = [
            {
              run = ''open "$@"'';
              orphan = true;
              desc = "Open";
            }
          ];
        };
        settings.open.rules = [
          {
            mime = "image/*";
            use = "image_preview";
          }
          {
            mime = "video/*";
            use = "open";
          }
          {
            mime = "audio/*";
            use = "open";
          }
          {
            mime = "application/pdf";
            use = "open";
          }
          {
            url = "*.md";
            use = "read";
          }
          {
            url = "*.mdx";
            use = "read";
          }
          {
            url = "*";
            use = "pager";
          }
        ];
      };

      programs.zoxide = {
        enable = devCfg.toolbelt.enable;
        enableZshIntegration = true;
        # Let zoxide take over `cd`: `cd proj` jumps by frecency, `cdi` opens
        # the interactive fzf picker. The chpwd hooks elsewhere in this room
        # still fire — zoxide's cd triggers the same chpwd event as builtin cd.
        options = [ "--cmd cd" ];
      };

      # Nebelung colours injected from nebelungPalette (matches catppuccin/fzf's
      # --color mapping for the selected flavor, blue muted out). home-manager turns
      # these into the --color flags in FZF_DEFAULT_OPTS.
      programs.fzf = {
        enable = devCfg.toolbelt.enable;
        enableZshIntegration = true;
        colors = {
          "bg+" = nebelungPalette.surface0;
          "bg" = nebelungPalette.base;
          "spinner" = nebelungPalette.rosewater;
          "hl" = nebelungPalette.red;
          "fg" = nebelungPalette.text;
          "header" = nebelungPalette.red;
          "info" = accentColor;
          "pointer" = nebelungPalette.rosewater;
          "marker" = nebelungPalette.lavender;
          "fg+" = nebelungPalette.text;
          "prompt" = accentColor;
          "hl+" = nebelungPalette.red;
          "selected-bg" = nebelungPalette.surface1;
          "border" = nebelungPalette.overlay0;
          "label" = nebelungPalette.text;
        };
      };

      # helix is installed by its own home-manager module rather than as a bare
      # package, because the settings and the Nebelung theme below ride with
      # it. Every other editor in the table is a package in `home.packages`.
      programs.helix = lib.mkIf (terminalCfg.editorName == "helix") {
        enable = true;
        settings = {
          theme = "nebelung";
          editor = {
            line-number = "relative";
            mouse = true;
            cursorline = true;
            color-modes = true;
            cursor-shape = {
              normal = "block";
              insert = "bar";
              select = "underline";
            };
            file-picker = {
              hidden = false;
            };
            lsp = {
              display-messages = true;
            };
            statusline = {
              left = [
                "mode"
                "spinner"
              ];
              center = [ "file-name" ];
              right = [
                "diagnostics"
                "selections"
                "position"
                "file-encoding"
                "file-line-ending"
                "file-type"
              ];
              separator = "│";
              mode = {
                normal = "NORMAL";
                insert = "INSERT";
                select = "SELECT";
              };
            };
          };
        };
      };

      # Opt-in because a GitHub dashboard is not something to hand someone who
      # never asked for one. Terminal supplies the patched binary, the Nebelung
      # include, the Cmd-G overlay and the self tabs; the PR tabs come from
      # haus.git.org (see above), and with no owner set Terminal writes none of
      # them rather than guessing — gh-dash keeps its own, and a host composing
      # its own PR queue in programs.gh-dash.settings has nothing to fight.
      programs.gh-dash = lib.mkIf ghDashCfg.enable {
        enable = true;
        package = lib.mkDefault ghDashPkg;
        settings = lib.mkMerge [
          { include = lib.mkBefore [ ghDashTheme ]; }
          ghDashSelfTabs
          (lib.mkIf (gitCfg.org != "") ghDashOrgTabs)
        ];
      };

      # Catppuccin: `catppuccin.flavor` is the single source of truth — every
      # integration follows it. Raw dotfiles nix can't inject into (the ghostty
      # config) name the flavor manually; keep them in sync.
      # Every port here is themed by Nebelung instead of stock catppuccin —
      # either by pointing the program at a whiskers-rendered file from the
      # nebelung flake (bat/delta/lsd/yazi), or by injecting nebelungPalette
      # colours straight into the program's settings (starship/fzf/lazygit).
      # Each catppuccin integration is disabled so it doesn't clobber our wiring.
      # Colours are Nebelung; the upstream catppuccin *names* are kept (nebelung's
      # own convention — its ghostty output is literally catppuccin-<flavor>.conf),
      # which is why nbFlavor turns up in so many paths here.
      catppuccin.autoEnable = true;
      catppuccin.enable = true;
      catppuccin.flavor = nbFlavor;
      catppuccin.bat.enable = false;
      catppuccin.starship.enable = false;
      catppuccin.delta.enable = false;
      catppuccin.fzf.enable = false;
      catppuccin.glamour.enable = false; # GLAMOUR_STYLE wired to nebelung above
      catppuccin.helix.enable = false;
      catppuccin.lazygit.enable = false;
      catppuccin.lsd.enable = false;
      catppuccin.yazi.enable = false;
      catppuccin.gh-dash.enable = false;
      catppuccin.zsh-syntax-highlighting.enable = false;

      # nix-index + comma (`, foo` runs a program without installing it):
      # unambiguously developer tooling, and the index is not small, so a
      # machine with the pack off shouldn't carry it.
      programs.nix-index = {
        enable = devCfg.enable;
        enableZshIntegration = devCfg.enable;
      };
      programs.nix-index-database.comma.enable = devCfg.enable;

      programs.home-manager.enable = true;

      # Zen browser — drop the Nebelung userChrome/userContent into every Zen
      # profile. Zen's chrome lives INSIDE the (randomly-named) browser profile,
      # not under XDG, so home.file can't target it — we write into each
      # Profiles/*/chrome at activation instead. Also flips on Firefox's
      # legacy userChrome/userContent stylesheets, which fresh profiles ship off.
      # Zen isn't installed here (themed-but-manual); the loop no-ops if absent.
      #
      # COPIES, not symlinks, and that is the whole reason any of this renders.
      # Gecko resolves `chrome/userContent.css` before it reads it and ignores
      # the file when the resolved path lands outside the profile directory — so
      # a link into /nix/store is read as nothing at all. Measured in Zen, four
      # runs, one sheet: same bytes as a copy themed news.ycombinator.com and as
      # a link did not, and a link to a sibling INSIDE chrome/ themed it again.
      # Propagation is unchanged — activation is what runs on a rebuild either
      # way. The `rm -f` is not tidiness: it is what MIGRATES a profile that
      # still holds the old symlink, and what stops `install` from following
      # that link and trying to write 0444 store bytes. The explicit mode is
      # because a store file arrives read-only and would stay that way.
      #
      # userContent is `zenUserContent`, not nebelung's file directly: with
      # haus.zen.userStyles set it's the same file with the compiled site styles
      # appended (see there). userChrome is nebelung's alone — that one themes
      # Zen's OWN interface, and its selectors are Zen's.
      home.activation.zenNebelung = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        zenProfiles="$HOME/Library/Application Support/zen/Profiles"
        if [ -d "$zenProfiles" ]; then
          for prof in "$zenProfiles"/*/; do
            [ -d "$prof" ] || continue
            chrome="$prof"chrome
            $DRY_RUN_CMD mkdir -p "$chrome"
            $DRY_RUN_CMD rm -f "$chrome/userChrome.css" "$chrome/userContent.css"
            $DRY_RUN_CMD install -m 0644 "${zenTheme}/userChrome.css" "$chrome/userChrome.css"
            $DRY_RUN_CMD install -m 0644 "${zenUserContent}" "$chrome/userContent.css"
            userjs="$prof"user.js
            if [ ! -e "$userjs" ] || ! ${pkgs.gnugrep}/bin/grep -qF \
                'toolkit.legacyUserProfileCustomizations.stylesheets' "$userjs"; then
              printf '%s\n' 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' \
                | $DRY_RUN_CMD tee -a "$userjs" >/dev/null
            fi
          done
        fi
      '';

      # Obsidian stores theme choice inside each vault rather than in one app
      # config. Only touch explicitly listed, already-existing vaults: copy the
      # generated full theme from the store, then JSON-merge our two appearance
      # choices so Obsidian keeps ownership of every unrelated setting. Copies
      # are deliberate: these directories often sync through iCloud, where a
      # /nix/store symlink would be dangling on every other device.
      #
      # ⚠️ A synced vault's own JSON is not reliably READABLE, and that is what
      # makes this the only activation script here that has to check. iCloud
      # evicts small files it thinks are cold, leaving a `dataless` stub with
      # the real size in its stat — so every emptiness test still passes.
      # Touching one normally blocks while the file provider fetches it, but
      # activation runs with dataless materialisation OFF (the same policy every
      # launchd job inherits), so the read fails outright with EDEADLK. That
      # surfaced as a bare `jq: error: Resource deadlock avoided` in the middle
      # of a rebuild — no filename, no vault, and an aborted activation, because
      # jq's failure took the whole script down with it. `brctl download` asks
      # the provider for the bytes without needing the policy; if the file still
      # won't read, or won't parse, this leaves that vault's settings untouched
      # and says which vault and why. A themed editor is never worth a machine
      # that won't finish switching.
      home.activation.obsidianNebelung = lib.mkIf (terminalCfg.obsidianVaults != [ ]) (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          # One byte is enough: a dataless stub fails the read, an evicted file
          # that brctl has since fetched does not, and an empty file is fine
          # either way (the seed path below handles that).
          readableObsidianJson() {
            ${pkgs.coreutils}/bin/head -c 1 "$1" >/dev/null 2>&1
          }

          installObsidianNebelung() {
            vaultRel="$1"
            vault="$HOME/$vaultRel"
            obsidian="$vault/.obsidian"

            if [ ! -d "$obsidian" ]; then
              echo "warning: Obsidian vault has no .obsidian directory; skipping: $vault" >&2
              return 0
            fi

            themeDir="$obsidian/themes/Nebelung"
            $DRY_RUN_CMD mkdir -p "$themeDir"
            $DRY_RUN_CMD install -m 0644 "${obsidianTheme}/theme.css" "$themeDir/theme.css"
            $DRY_RUN_CMD install -m 0644 "${obsidianTheme}/manifest.json" "$themeDir/manifest.json"

            appearance="$obsidian/appearance.json"
            if [ -e "$appearance" ] && ! readableObsidianJson "$appearance"; then
              if [ -x /usr/bin/brctl ]; then
                $DRY_RUN_CMD /usr/bin/brctl download "$appearance" || true
                # brctl asks; it does not promise the bytes have landed by the
                # time it returns. Ten tries at 200ms is the whole budget —
                # past that the provider is still fetching over the network,
                # and this vault gets themed on the next rebuild rather than
                # holding one up.
                tries=0
                while [ $tries -lt 10 ] && ! readableObsidianJson "$appearance"; do
                  ${pkgs.coreutils}/bin/sleep 0.2
                  tries=$((tries + 1))
                done
              fi
            fi
            if [ -e "$appearance" ] && ! readableObsidianJson "$appearance"; then
              echo "warning: iCloud has not downloaded $appearance; Nebelung is installed in this vault but not selected: $vault" >&2
              return 0
            fi

            run sh -c '
              appearance="$0"
              tmp="$appearance.hm-seed"
              base="$appearance"
              if [ ! -s "$appearance" ]; then
                base="$tmp.base"
                printf "{}\n" > "$base"
              fi
              if ! ${pkgs.jq}/bin/jq ".cssTheme = \"Nebelung\"
                | .theme = \"obsidian\"
                | .enabledCssSnippets = ((.enabledCssSnippets // []) | map(select(. != \"nebelung\")))" \
                "$base" > "$tmp"; then
                rm -f "$tmp" "$tmp.base"
                echo "warning: could not rewrite $appearance; leaving this vault untouched" >&2
                exit 0
              fi
              mv "$tmp" "$appearance"
              rm -f "$tmp.base"
            ' "$appearance"
          }

          ${lib.concatMapStringsSep "\n" (
            vault: "installObsidianNebelung ${lib.escapeShellArg vault}"
          ) terminalCfg.obsidianVaults}
          unset -f installObsidianNebelung readableObsidianJson
        ''
      );

      # ---- dotfiles + Nebelung theme drops ----
      # The agent instructions and the `haus` skill used to be merged in here,
      # from a path table in this file's `let`. They are modules/ai's own now —
      # it writes its own `home.file` into this same user, and home-manager
      # merges the two attrsets. What is left below is dotfiles: theme drops and
      # client config this room writes whether or not the AI room is on.
      home.file = {

        # opencode
        ".config/opencode/themes/nebelung.json".source = "${nebelungRoot}/opencode/nebelung.json";
        ".config/opencode/tui.json".text = ''
          {
            "$schema": "https://opencode.ai/tui.json",
            "theme": "nebelung"
          }
        '';
      }
      // lib.optionalAttrs agentsCfg.enable {
        # scruff's durable machine default. launchd daemons and zmx sessions
        # can outlive the environment that started them, so `scruff new` resolves
        # this generated file instead of inheriting a stale client selection.
        # A standalone scruff install can own the same file by hand.
        #
        # ⚠️ scruff reads `~/.config/scruff` and nothing else, and every ADAPTER
        # rides the same answer — so a namer adapter that is not under this
        # directory is not found, and lane names fall back to a random word
        # pair with the warning going to a launchd stderr nobody reads. Putting
        # it there is the operator's job: the adapter is theirs and may be a
        # file haus has never seen.
        ".config/scruff/config.toml".text = ''
          # Generated from haus.ai.default + haus.ai.namer — edit those options, not here.
          agent = "${agentDefault}"
          ${lib.optionalString (agentNamer != "") ''

            # What names a lane that arrives with a task but no name
            # (haus.ai.namer). scruff runs ONE argv from
            # ~/.config/scruff/adapters/namer/${agentNamer}.toml and reads a word
            # off stdout, so the adapter file is this MACHINE's rather than
            # haus's — and without it scruff falls back to a random word pair
            # instead of failing the lane.
            namer = "${agentNamer}"
          ''}
          # `open` and `resume` are the two seams scruff answers by exec'ing a
          # client; both are answered here by the same script, because with zmx
          # they are the same act — `zmx attach` creates the session or joins
          # the live one.
          #
          # The path is under ~, not a store path: scruff's own docs list "a hook
          # pointing at a store path from a rebuild ago" as a way for this to
          # break, and home.file below keeps this one current.
          [hooks]
          open = "${config.home.homeDirectory}/.config/haus/lanes/lane-open.sh"
          resume = "${config.home.homeDirectory}/.config/haus/lanes/lane-open.sh"

          # `focus` is the third seam, and the one only this room can
          # answer: go to the window a lane is ALREADY in, rather than
          # opening one. The lane→window join is lane-open.sh's. When
          # there is nothing to raise — the session is detached, no
          # window holds it — the hook defers and scruff falls back to
          # resume, which comes back through lane-open.sh and opens a
          # properly placed one. Clicking a trill lane banner runs it.
          focus = "${config.home.homeDirectory}/.config/haus/lanes/lane-focus.sh"
        '';

        # The lane opener itself — what scruff's [hooks] above exec.
        ".config/haus/lanes/lane-open.sh" = {
          source = ./lanes/lane-open.sh;
          executable = true;
        };

        # The `focus` seam's half: raise the window a lane is already in,
        # through the same scripts/raise-session.sh the bar and ⌘F reach for,
        # or defer to scruff when there is no window to raise.
        ".config/haus/lanes/lane-focus.sh" = {
          source = ./lanes/lane-focus.sh;
          executable = true;
        };

        # The other end of that seam: focusing a lane's window YOURSELF — no
        # banner clicked — takes its parked fin down. modules/windows runs it
        # from AeroSpace's `on-focus-changed`, which is why the script's own
        # first act is to establish that there is nothing to do.
        ".config/haus/lanes/lane-seen.sh" = {
          source = ./lanes/lane-seen.sh;
          executable = true;
        };

        # The chord's half: what pounce's Ghostty-scoped ⌘↵ runs, through the
        # launcher's `cmd:lane-here` command. A chord pointing at a file that
        # isn't there is the one failure mode a rebuild can't warn about.
        ".config/haus/lanes/lane-spawn.sh" = {
          source = ./lanes/lane-spawn.sh;
          executable = true;
        };

        # The shared "which directory is the focused window looking at?"
        # resolver — lane-spawn.sh's cwd half, split out so the launcher's
        # shell-here command (⌘N/⌘⇧N under zmx) asks the identical question
        # instead of drifting a copy of the awk.
        ".config/haus/lanes/lane-cwd.sh" = {
          source = ./lanes/lane-cwd.sh;
          executable = true;
        };

        # Opencode's half of the agent status the bar's `agents` pill draws.
        # Claude Code's equivalent is four hooks in ~/.claude/settings.json,
        # which the USER wires (Claude owns that file and rewrites it, so haus
        # never has); opencode instead auto-loads every file under this directory,
        # so haus can own the whole wiring and a fresh machine gets a working
        # pill for opencode panes with nothing to configure.
        # @AGENT_STATE@ → core's `agent-state` by absolute path: a plugin runs
        # inside opencode's server process, which is given no PATH guarantees.
        ".config/opencode/plugin/haus-agent-state.js".text =
          builtins.replaceStrings [ "@AGENT_STATE@" ] [ "/run/current-system/sw/bin/agent-state" ]
            (builtins.readFile ./opencode/agent-state.js);

        # pi's half of the same thing — and of the LANE BANNERS, which is where
        # it stops resembling the block above it. pi has one seam, not two: no
        # hook file to append a second command to, so the one extension reports
        # state to `agent-state` AND hands `scruff hook notify` the same
        # Claude-shaped payload the Claude Code merge below wires four events
        # of. Everything downstream of those four event names — the lane
        # lookup, the fin key, the "Go to lane" action, the resolve — is
        # client-agnostic, so a pi lane's trill fin is the Claude path's, not a
        # second copy of it. The file's own header carries the event map and
        # the two pi-only banners (a failed compaction, a provider refusing the
        # session) that go through `haus-notify` instead, having nothing to
        # resolve them.
        #
        # NOT gated on pi being in `ai.clients`, unlike the settings merge
        # below: this file is inert without pi, so it costs a machine without
        # one nothing and hands a hand-installed pi a working pill and working
        # banners — the same reasoning as the Claude Code block, and the
        # opposite of `piSettings`, which seeds a list of npm sources to fetch
        # and so must not be written for a client that is not here.
        #
        # A `.ts` FILE and not a directory: pi discovers `extensions/*.ts`
        # (symlinks included — this one is a home-manager link into the store)
        # one level deep, so a bare file is the smallest thing that works and
        # cannot collide with a host that wires its own extension DIRECTORY
        # beside it. Three absolute /run/current-system paths, for the reason
        # the opencode plugin gives: an extension runs inside pi's own process,
        # which is given no PATH guarantees.
        ".pi/agent/extensions/haus-agent-state.ts".text =
          builtins.replaceStrings
            [ "@AGENT_STATE@" "@SCRUFF@" "@HAUS_NOTIFY@" ]
            [
              "/run/current-system/sw/bin/agent-state"
              "/run/current-system/sw/bin/scruff"
              "/run/current-system/sw/bin/haus-notify"
            ]
            (builtins.readFile ./pi/agent-state.ts);

        # pi's cache-burn watchdog — the alarm half of the prompt-cache room
        # above. The affinity header makes meridian resume instead of replay,
        # and the resume path has a degenerate mode where a lane's reads stop
        # growing (the replay only ever hits a frozen head) while every turn
        # re-writes the whole growing tail at 1-hour-TTL prices — measured at
        # $221.78 of a $233.45 session. Nothing pi can set moves that number,
        # so this file watches per-turn usage and banners through haus-notify
        # when the signature appears; its own header carries the full story.
        # A .mjs SOURCE rendered to a .ts NAME: the bytes are plain JS (a TS
        # subset, so the transpile is a no-op) and test/cache-watchdog.bats
        # imports the source file directly — the tested bytes and the rendered
        # bytes cannot drift.
        ".pi/agent/extensions/haus-cache-watchdog.ts".text =
          builtins.replaceStrings [ "@HAUS_NOTIFY@" ] [ "/run/current-system/sw/bin/haus-notify" ]
            (builtins.readFile ./pi/cache-watchdog.mjs);

        # pi's half of the desktop guard — the thing that keeps an agent from
        # foregrounding an app, moving a window or redrawing the desktop while
        # somebody is typing into something else. Claude Code panes have had it
        # as a PreToolUse hook (the `agent-desktop-guard` merge below); pi had
        # NOTHING, because pi has no permission modes, no permission prompt and
        # no sandbox at all. `tool_call` is its seam: it fires before the tool,
        # it can block, and the handler may be async — so it can hold the turn
        # open while a human answers.
        #
        # It does NOT carry a second copy of the ruleset: it shells out to the
        # very same `agent-desktop-guard` binary, with the same hook-shaped JSON
        # on stdin and the same verdict back out, so the line falls in one place
        # for both clients and test/desktop-guard.bats pins it for both. That
        # matters more here than the indirection costs — the guard's whole value
        # is WHERE the line is, and both sides of it fail silently.
        #
        # The question goes up as a `trill ask`, racing pi's own in-pane dialog,
        # first definite answer wins. A Claude prompt can only be answered by
        # finding the pane; the reason a lane has its own window is that nobody
        # is watching it. Direct `trill`, not `haus-notify`, because haus-notify
        # is send-only and its no-trill fallback is Apple's banner, which has no
        # buttons — an ask has no such fallback, so the pane IS the fallback.
        #
        # Unconditional for the same reason the file above it is: inert without
        # pi, so a hand-installed pi gets the guard with nothing to configure —
        # PROVIDED the ai room is on, because `agent-desktop-guard` ships under
        # its `mkIf`. With `haus.ai.enable = false` the binary is absent, the
        # spawn fails, and the extension does what every other failure here does
        # and returns no opinion. That is the right direction (a machine that
        # asked for no AI room gets no gate rather than a broken one), and it is
        # the same shape agent-state.ts has with `agent-state`.
        # `HAUS_DESKTOP_OK=1` turns it off for a pane, exactly as it does for
        # Claude Code — one variable, both clients.
        ".pi/agent/extensions/haus-desktop-guard.ts".text =
          builtins.replaceStrings
            [ "@DESKTOP_GUARD@" "@TRILL@" ]
            [
              "/run/current-system/sw/bin/agent-desktop-guard"
              "/run/current-system/sw/bin/trill"
            ]
            (builtins.readFile ./pi/desktop-guard.ts);
      }
      # Helix nebelung theme, from the nebelung flake. This used to be a
      # hand-written [palette] block inheriting helix's BUILT-IN
      # catppuccin_<flavor>; nebelung now carries the real catppuccin/helix
      # port, so the theme comes rendered like every other tool here and the
      # syntax scopes track upstream instead of whatever helix ships.
      # Kept under the `nebelung` name that programs.helix.settings.theme
      # points at (the port also renders a no_italics/ sibling).
      #
      # Conditional for the same reason the helix PORT is: on a machine whose
      # `haus.terminal.editorName` is not helix, this room installs no helix, and
      # a theme file for an editor that is not there is just litter in ~.
      // lib.optionalAttrs (terminalCfg.editorName == "helix") {
        ".config/helix/themes/nebelung.toml".source =
          "${nebelungRoot}/helix/themes/default/catppuccin_${nbFlavor}.toml";
      }
      # ── ~/.profile — the file two spawn paths read before this room's ────
      # Not a shell we configure and not one anybody types in, which is exactly
      # why it went unnoticed. Two paths read it:
      #
      #   a window   ghostty wraps EVERY surface in a login /bin/sh
      #              (`/usr/bin/login -flp $USER /bin/sh -c "exec -l <cmd>"`,
      #              measured on 1.3.x), and a login sh reads /etc/profile then
      #              ~/.profile before it ever execs `command` — launch.sh.
      #   a lane     lanes/lane-open.sh ends in `zmx attach <s> bash -lc <held>`,
      #              and a login bash with no ~/.bash_profile / ~/.bash_login —
      #              this room writes neither — falls through to ~/.profile too.
      #
      # So it is on the hot path of both spawn chords while belonging to
      # nobody, and it is the one dotfile THIRD PARTIES write into, unguarded:
      # rustup and uv each append a bare `. "$HOME/.cargo/env"` /
      # `. "$HOME/.local/bin/env"`. Move that tool to nix and the file it names
      # is gone, so the login sh prints two "No such file or directory" lines —
      # a FLASH ON EVERY WINDOW SPAWN, before any shell paints, with no shell
      # left to ask about it. Guarded sources make an absent file silence, and
      # owning the file makes it a read-only store symlink, so the next
      # installer's `>>` fails loudly instead of quietly re-arming the flash.
      #
      # Two things to know before this lands on a machine that already has one:
      #
      #   * A REGULAR ~/.profile is moved aside — mkHaus sets
      #     home-manager.backupFileExtension, so it becomes ~/.profile.backup
      #     with a warning and nothing sources it any more. Anything still
      #     wanted goes in ~/.profile.local, which the file below sources.
      #   * A ~/.profile that is a SYMLINK (a dotfiles repo, stow, chezmoi), or
      #     a machine that already has BOTH ~/.profile and ~/.profile.backup,
      #     is a home-manager COLLISION rather than a backup — activation fails
      #     until the path is cleared by hand. Deliberately not `force = true`:
      #     that would delete a symlink into someone's dotfiles repo silently.
      #     The opt-out is home-manager's own, no haus option needed:
      #     `home.file.".profile".enable = false`.
      #
      # Skipped entirely when a host turns on `programs.bash` — home-manager's
      # bash module writes its own ~/.profile (sourcing hm-session-vars.sh), and
      # two definitions of one target is an eval error, so the host's explicit
      # ask wins over our silencer.
      // lib.optionalAttrs (!config.programs.bash.enable) {
        ".profile".text = ''
          # Generated by haus (modules/terminal). Edit ~/.profile.local instead.
          #
          # Read by POSIX login shells only — including the one ghostty wraps
          # every terminal window in, and the `bash -lc` an agent lane opens
          # into. Which is why NOTHING here may print: there is no shell on
          # screen yet to blame it on, so output here is a flash at spawn.
          # That applies to ~/.profile.local as well — keep it silent too.
          #
          # Guard every source: a line naming a file that is not there costs an
          # error on every new terminal window, which is what the installers
          # that append here (rustup, uv) leave behind once their tool moves to
          # nix.
          for _hausf in "$HOME/.cargo/env" "$HOME/.local/bin/env" "$HOME/.profile.local"; do
              [ -r "$_hausf" ] && . "$_hausf"
          done
          unset _hausf
          true
        '';
      }
      // {

        # ghostty (config lives in Application Support; theme lookup is XDG)
        # ghostty's `command` runs scripts/launch.sh by absolute path; render
        # @HOME@ → the user's home so it isn't pinned to one account.
        "Library/Application Support/com.mitchellh.ghostty/config".text =
          builtins.replaceStrings
            [ "@HOME@" "@FONT_FAMILY@" "@FONT_SIZE@" ]
            [
              config.home.homeDirectory
              fontsCfg.mono.name
              (toString fontsCfg.mono.size)
            ]
            ghosttyConfigTemplate;
        ".config/ghostty/themes/nebelung".source =
          "${nebelungRoot}/ghostty/themes/catppuccin-${nbFlavor}.conf";

        # lsd colours (replaces catppuccin.lsd). lsd auto-reads this file.
        ".config/lsd/colors.yaml".source = "${nebelungRoot}/lsd/themes/catppuccin-${nbFlavor}/colors.yaml";

        # yazi theme (replaces catppuccin.yazi): mgr/status/mode palette (mauve
        # accent) plus the syntect theme its syntect_theme line points at —
        # reusing the Nebelung bat tmTheme so previews match bat.
        ".config/yazi/theme.toml".source =
          "${nebelungRoot}/yazi/themes/${nbFlavor}/catppuccin-${nbFlavor}-${accent}.toml";
        # This target's NAME is pinned by the rendered theme.toml above: its
        # syntect_theme line reads ~/.config/yazi/Catppuccin-<flavor>.tmTheme, so it
        # has to carry the flavor or yazi's code previews lose their colours.
        ".config/yazi/Catppuccin-${nbFlavor}.tmTheme".source =
          "${nebelungRoot}/bat/themes/${batTheme}.tmTheme";

        # ── ~/.config/haus/term — the scripts that outlived the multiplexer ──
        # This whole block lived under ~/.config/zellij until zellij was
        # removed. The directory moved with the scripts rather than being kept
        # for compatibility: nothing but haus ever wrote to it, and a
        # path named for a tool the machine no longer has is a lie that costs
        # nothing to stop telling. What survived is below; the plugin wasm, the
        # two layouts, config.kdl, the theme and copy-clean.pl went with it.
        ".config/haus/term/launch.sh" = {
          # Templated for one bit: whether the FIRST window of a Ghostty puts
          # the parked sessions back (haus.terminal.restoreWindows). Baked
          # rather than read at runtime because this script runs before any
          # shell does — there is no environment to have read it from.
          text =
            builtins.replaceStrings [ "@restore@" ] [ (if terminalCfg.restoreWindows then "1" else "0") ]
              (builtins.readFile ./scripts/launch.sh);
          executable = true;
        };
        # "Put my terminal back the way I left it": one window per parked zmx
        # session. Called by launch.sh for the first window of a Ghostty, and by
        # the palette on demand. It reaches raise-session.sh for lanes rather
        # than carrying a second copy of the forced-title spawn.
        ".config/haus/term/restore-windows.sh" = {
          source = ./scripts/restore-windows.sh;
          executable = true;
        };
        ".config/haus/term/image-preview.sh" = {
          source = ./scripts/image-preview.sh;
          executable = true;
        };
        # The one window → zmx-session join, and the one tiled-window spawn.
        # Both are libraries rather than chords: focused-session.sh is what
        # ⌘F/⌘L and lanes/lane-cwd.sh all ask "which window is this", and
        # new-window.sh is what every "open this somewhere" script ends in.
        ".config/haus/term/focused-session.sh" = {
          source = ./scripts/focused-session.sh;
          executable = true;
        };
        # The one reader for the `zmx ls` wire format — the attached-row
        # marker, the 0.7.0 start_dir/cwd rename, first-"=" splitting, and
        # `zmx get`'s tab→space flip all live in its header instead of in
        # every caller's awk. A library like focused-session.sh: modules/bar
        # and modules/launcher reach it at this path, the way they already
        # reach raise-session.sh and float-term.sh.
        ".config/haus/term/zmx-rows.sh" = {
          source = ./scripts/zmx-rows.sh;
          executable = true;
        };
        ".config/haus/term/new-window.sh" = {
          source = ./scripts/new-window.sh;
          executable = true;
        };
        # The mirror of focused-session.sh: "put THAT session's window in
        # front". Two callers with a copy each until 2026-08-19 — the bar's
        # agents popup and ⌘F's ⏎ — which is why it lives here rather than in
        # either of them. modules/bar reaches it at this path, the way it
        # already reaches float-term.sh.
        ".config/haus/term/raise-session.sh" = {
          source = ./scripts/raise-session.sh;
          executable = true;
        };
        # Both peek chords run this one script: ⌘Y hops out of an agent
        # worktree to the repo's main checkout, ⌘⇧Y passes --stay and doesn't.
        # Both are pounce appHotkeys now (cmd:peek / cmd:peek-stay).
        ".config/haus/term/peek.sh" = {
          source = ./scripts/peek.sh;
          executable = true;
        };
        ".config/haus/term/peek-run.sh" = {
          source = ./scripts/peek-run.sh;
          executable = true;
        };
        # ⌘F / ⌘⇧F: full-text search over this window's zmx scrollback, or over
        # every session at once — agent windows through their Claude
        # transcript (an alt-screen has no scrollback to search), everything
        # else through `zmx history`.
        ".config/haus/term/find.sh" = {
          source = ./scripts/find.sh;
          executable = true;
        };
        # ⌘G: gh-dash in its own near-fullscreen floating window. The chord is
        # armed only when ghDash is on.
        ".config/haus/term/gh-dash.sh" = {
          source = ./scripts/gh-dash.sh;
          executable = true;
        };
        # The one floating-Ghostty helper (geom + spawn + ring + pin); peek.sh, the
        # Rebuild System pounce command, and the agent-peek popup all route
        # through it. The outline's binary/colour/width are baked in rather than
        # passed per caller, so haus.terminal.floatBorder moves all three at once
        # — and so the pounce command, which runs on launchd's bare PATH, gets
        # floatring by store path instead of hoping it's installed. AeroSpace's
        # outer gaps ride in the same way (floatGaps above), because `geom
        # --tiled` has to know where the tiled desktop ends and there is no
        # runtime query for it that doesn't shell out to aerospace per summon.
        ".config/haus/term/float-term.sh" = {
          text =
            builtins.replaceStrings
              [
                "@floatring@"
                "@floatpin@"
                "@ring_color@"
                "@ring_width@"
                "@gap_top_builtin@"
                "@gap_top_external@"
                "@gap_bottom_builtin@"
                "@gap_bottom_external@"
                "@gap_side_builtin@"
                "@gap_side_external@"
              ]
              [
                # "off" renders BOTH empty, so an opted-out machine doesn't even
                # carry the binary in its closure (a store path in the script's
                # text is a real dependency — the swiftc build would run anyway).
                (if terminalCfg.floatBorder == "off" then "" else "${floatring}/bin/floatring")
                (if terminalCfg.floatOnTop then "${floatpin}/bin/floatpin" else "")
                floatBorderColor
                "2"
                (toString floatGaps.outer.top.builtin)
                (toString floatGaps.outer.top.external)
                (toString floatGaps.outer.bottom.builtin)
                (toString floatGaps.outer.bottom.external)
                (toString floatGaps.outer.left.builtin)
                (toString floatGaps.outer.left.external)
              ]
              (builtins.readFile ./scripts/float-term.sh);
          executable = true;
        };
        # The one "open in the editor" launcher — a new Ghostty window running
        # haus.terminal.editor (baked into @editor@). Shared by the "Nix
        # Config" palette/bar commands and the file-association hijack.
        ".config/haus/term/editor-open-pane.sh" = {
          text = builtins.replaceStrings [ "@editor@" ] [ terminalCfg.editor ] (
            builtins.readFile ./scripts/editor-open-pane.sh
          );
          executable = true;
        };
        # pounce's terminal launcher (POUNCE_TERMINAL_LAUNCHER, wired in
        # modules/launcher) — opens `ssh <host>` etc. in a new window, same
        # flow as editor-open-pane.sh above.
        ".config/haus/term/pounce-terminal.sh" = {
          source = ./scripts/pounce-terminal.sh;
          executable = true;
        };
        # The one "open the nix config" opener — resolves this host's
        # hosts/@hostname@/default.nix and hands it to the launcher above with
        # the flake root as cwd. The "Nix Config" palette command (pounce) and
        # the bar's nix pill (bar) both exec this.
        ".config/haus/term/nix-config-open.sh" = {
          text = builtins.replaceStrings [ "@hostname@" ] [ hostname ] (
            builtins.readFile ./scripts/nix-config-open.sh
          );
          executable = true;
        };
      };

      # Keep nix-installed .app bundles findable by LaunchServices.
      #
      # A GUI app from nixpkgs — anything a roster entry names with `package` —
      # is linked into ~/Applications/Home Manager Apps as a SYMLINK, and
      # LaunchServices resolves that to the /nix/store path when it registers the
      # bundle, so every record it keeps is pinned to a store hash. Bump the
      # package and the hash changes: the "Open With" entry, the default-handler
      # binding, and `open -b <bundle-id>` all still name a path that garbage
      # collection is about to remove, and the app quietly stops being the
      # handler for its own file types. (Masked for anyone who ALSO has the app
      # from a cask — the /Applications copy keeps answering for the shared
      # bundle id, which is how a machine can carry two copies of one app and
      # never notice.)
      #
      # Re-registering on every activation is the fix, because activation is
      # exactly when the store path changes. `-f` forces a refresh of records
      # that already exist, `-r` walks the directory; both are cheap on a handful
      # of symlinks, and neither touches which app is the DEFAULT for a type —
      # that binding is by bundle id and is the user's to set (duti, or Finder's
      # Get Info), so this only makes sure the id keeps resolving.
      home.activation.nixAppsLaunchServices = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        nixApps="$HOME/Applications/Home Manager Apps"
        if [ -d "$nixApps" ]; then
          $DRY_RUN_CMD /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
            -f -r "$nixApps" 2>/dev/null || true
        fi
      '';

      # File-association hijack — opt-in (haus.terminal.hijackFileAssociations).
      # Off by default: silently making EditorOpen.app the handler for a dozen
      # extensions is a jarring, hard-to-undo surprise on someone else's machine.
      # It opens files in haus's editor (haus.terminal.editor) via the same
      # window launcher the palette/bar use.
      home.activation.editorOpenApp = lib.mkIf terminalCfg.hijackFileAssociations (
        lib.hm.dag.entryAfter [ "writeBoundary" ] (
          let
            # Extensions EditorOpen.app claims as an Editor (see the "declare in
            # the app" note in the script). Deliberately EXCLUDES web-content
            # types (html/htm/xhtml — browsers own public.html and won't yield,
            # and you want those in a browser anyway) and image types (handled by
            # yazi's own image preview — scripts/image-preview.sh).
            #
            # This is the ONLY list of file types haus claims, and it has to
            # stay the only one — that is a rule, not a coincidence. Two
            # haus-owned apps claiming one type never settles: both claims
            # re-run on every activation and macOS stops to ask the user which
            # app wins, every rebuild, forever. Measured, not theoretical — a
            # video player pick once claimed `mts` alongside this list, and
            # because `.mts` and `.m2ts` resolve to ONE shared AVCHD UTI the
            # dialog came back on every single rebuild until the two lists were
            # reconciled. So if a second room ever claims a type, reconcile by
            # UTI rather than by spelling: one UTI can carry several
            # extensions.
            editorExts = [
              "json"
              "jsonc"
              "txt"
              "md"
              "mdx"
              "markdown"
              "rst"
              "adoc"
              "org"
              "ts"
              "tsx"
              "mts"
              "cts"
              "js"
              "jsx"
              "mjs"
              "cjs"
              "rs"
              "go"
              "py"
              "rb"
              "lua"
              "pl"
              "php"
              "java"
              "kt"
              "kts"
              "swift"
              "scala"
              "clj"
              "c"
              "h"
              "cc"
              "cpp"
              "hpp"
              "hh"
              "cs"
              "nix"
              "toml"
              "yaml"
              "yml"
              "kdl"
              "conf"
              "ini"
              "cfg"
              "properties"
              "env"
              "css"
              "scss"
              "sass"
              "less"
              "styl"
              "vue"
              "svelte"
              "astro"
              "sh"
              "bash"
              "zsh"
              "fish"
              "vim"
              "ps1"
              "sql"
              "graphql"
              "gql"
              "prisma"
              "proto"
              "xml"
              "csv"
              "tsv"
              "diff"
              "patch"
              "log"
              "lock"
              "tex"
              "bib"
              "editorconfig"
              "gitignore"
              "gitattributes"
              "dockerignore"
              "npmrc"
            ];
            # NOTE on extensionless executables (`bench` & friends): they're
            # typed public.unix-executable and RUN in Terminal on click. That one
            # can't be automated here — macOS gates changing the executable
            # handler behind an INTERACTIVE confirmation dialog that
            # `darwin-rebuild switch` can't answer (and neither declaration nor
            # lsregister overrides Terminal's claim). To send them to the editor,
            # run once by hand and click through the prompt:
            #   duti -s com.hausfold.editoropen public.unix-executable all
            plistBuddy = "/usr/libexec/PlistBuddy";
            lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister";
            # One PlistBuddy "Add …:CFBundleTypeExtensions:<i> string <ext>" per
            # extension, index-ordered.
            declareExts = lib.concatStringsSep "\n" (
              lib.imap0 (
                i: ext:
                ''$DRY_RUN_CMD ${plistBuddy} -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:${toString i} string ${ext}" "$PL"''
              ) editorExts
            );
            dutiPins = lib.concatStringsSep "\n" (
              map (
                t:
                ''$DRY_RUN_CMD "${pkgs.duti}/bin/duti" -s com.hausfold.editoropen "${t}" all 2>/dev/null || true''
              ) editorExts
            );
          in
          ''
            appDir="$HOME/Applications"
            $DRY_RUN_CMD mkdir -p "$appDir"
            $DRY_RUN_CMD /usr/bin/osacompile -o "$appDir/EditorOpen.app" -e 'on open theFiles' -e 'repeat with theFile in theFiles' -e 'set file_path to POSIX path of theFile' -e 'do shell script "$HOME/.config/haus/term/editor-open-pane.sh " & quoted form of file_path' -e 'end repeat' -e 'end open'
            PL="$appDir/EditorOpen.app/Contents/Info.plist"
            $DRY_RUN_CMD /usr/bin/plutil -replace CFBundleIdentifier -string "com.hausfold.editoropen" "$PL"

            # Declare the file types EditorOpen.app owns IN THE APP ITSELF — not
            # just via duti. This is load-bearing: `duti -s <ext>` can only bind an
            # extension whose UTI some installed app already declares; for a type
            # nothing else on the machine declares (rs, go, kdl, lua, fish, …) duti
            # hits a FATAL LaunchServices -50 and silently no-ops, so those files
            # keep opening in nothing/Terminal. Declaring the extension here
            # materializes its UTI and registers this app as the owner, and
            # `lsregister -f` makes it the default — even beating an existing owner
            # (a bare .py that would otherwise open in Xcode). Delete-first keeps
            # the block idempotent across re-activations.
            $DRY_RUN_CMD ${plistBuddy} -c "Delete :CFBundleDocumentTypes" "$PL" 2>/dev/null || true
            $DRY_RUN_CMD ${plistBuddy} -c "Add :CFBundleDocumentTypes array" "$PL"
            $DRY_RUN_CMD ${plistBuddy} -c "Add :CFBundleDocumentTypes:0 dict" "$PL"
            $DRY_RUN_CMD ${plistBuddy} -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string Source" "$PL"
            $DRY_RUN_CMD ${plistBuddy} -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Editor" "$PL"
            $DRY_RUN_CMD ${plistBuddy} -c "Add :CFBundleDocumentTypes:0:LSHandlerRank string Owner" "$PL"
            $DRY_RUN_CMD ${plistBuddy} -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions array" "$PL"
            ${declareExts}

            # Register the freshly-declared bundle so LaunchServices sees the new
            # types before we pin defaults against them.
            $DRY_RUN_CMD ${lsregister} -f "$appDir/EditorOpen.app" 2>/dev/null || true

            # Belt-and-suspenders: pin us as the *user default* for every type
            # where the UTI is bindable. duti prints (and this swallows) a benign
            # -50 on the pure-dynamic types the declaration above already handled;
            # a real failure isn't worth aborting activation over.
            if [ -x "${pkgs.duti}/bin/duti" ]; then
            ${dutiPins}
            fi
          ''
        )
      );

      # Claude Code — seed a couple of defaults into settings.json:
      #   permissions.defaultMode = "auto"  — pin the permission mode here
      #     instead of passing --dangerously-skip-permissions on the command
      #     line (the lane spawner no longer does). "auto" runs agents
      #     unattended but keeps the background safety checks that block
      #     dangerous escalations, so it's safe on the host — unlike
      #     bypassPermissions, which is the flag's exact, check-free behaviour
      #     and wants a container.
      #   tui = "fullscreen"  — render Claude Code in the alt-screen (fullscreen)
      #     TUI rather than inline. `/tui fullscreen` sets this per-session and
      #     relaunches; seeding it makes fullscreen the default on every new
      #     machine. Ghostty's own ⇧-drag selection still reaches the
      #     alt-screen, so there's no tradeoff to the classic inline renderer.
      #   disableAgentView = true  — turn off the built-in agent-manager view
      #     (`claude agents`, `--bg`, /background, its on-demand daemon) and the
      #     "← for agents" toolbar hint that advertises it. Undocumented key,
      #     equivalent to CLAUDE_CODE_DISABLE_AGENT_VIEW=1. Parallel Claude
      #     sessions here go through `scruff` + zmx windows (core/terminal), not the
      #     in-app view, so the hint is pure noise — kill it at the haus level.
      #   statusLine  — point Claude Code's status bar at `claude-statusline`
      #     (core ships it on PATH). It renders THIS session's `scruff` worktree +
      #     the sister worktrees in flight across every repo — the agent-worktree
      #     HUD the built-in bar can't give. refreshInterval keeps the sister
      #     list current while the main session sits idle watching other panes.
      #     It is also the ONLY feed behind bar's `claudeUsage` pill — Claude
      #     Code hands the statusline its rate-limit percentages and nothing
      #     else on this machine sees them — so unsetting this key freezes that
      #     pill (it greys itself out after 30 minutes rather than lying).
      #   spinnerTipsEnabled = false  — drop the rotating "Tip:" line under the
      #     spinner; the status bar already carries the context that matters.
      #     (The built-in mode/`esc to interrupt` footer badge has no such knob
      #     in Claude Code — statusLine renders above it and can't replace it.)
      #   footerLinksRegexes  — CC scans conversation output for these patterns
      #     and renders a native, clickable badge in the footer for each hit. We
      #     match GitHub `owner/repo#N` shorthand → the PR's github.com page, so
      #     a family PR reference anywhere in the transcript is one click away.
      #     This is the maintained clickable-PR path: CC 2.1.3+ STRIPS the OSC 8
      #     hyperlinks the statusline (core/statusline.sh) emits for its "#N" PR
      #     pills — colored but no longer clickable at all (upstream regression,
      #     anthropics/claude-code#21586). footerLinksRegexes needs no OSC 8, so
      #     it survives that. Note it's a DIFFERENT surface (the footer, keyed
      #     off conversation text) — it doesn't restore clickability to the
      #     statusline pills themselves; those relight if/when CC stops filtering.
      #     Pattern uses char classes ([0-9], not \d) on purpose: a backslash
      #     would have to survive the nix'' → sh"" → jq"" escaping layers below.
      # Claude owns settings.json (it rewrites the file as plugins/statusline/
      # permission grants change), so we merge our keys in at activation and
      # never own it — every other key it holds must survive. jq is pinned from
      # the store because activation runs with a bare PATH.
      #
      # The two WorktreeCreate/WorktreeRemove hooks are set here, and that is a
      # change from how they used to live: hand-written, once, and hoped for.
      # The risk was never a rebuild clobbering them — this merge only touches
      # the keys it names — it was the sentence above. Claude REWRITES this file
      # on its own schedule, and a hand-edited hook it doesn't know about can go
      # with it; you would find out at pane-close, by losing a worktree's
      # parking. Declaring them makes them self-healing: every rebuild
      # re-asserts them, so the worst case is one `haus rebuild` rather than
      # silent data loss.
      #
      # Set as whole arrays, not merged into: these two events are haus plumbing
      # pointing at a haus-controlled /run/current-system path, and there is no
      # sensible second handler for "make me a worktree". Every other hook
      # ENTRY in the file survives: the four agent-state hooks stay yours (see
      # modules/bar/options.nix) — on Notification and Stop haus appends its own
      # entry beside yours, never in place of them.
      #
      # The `&& mv` is load-bearing: this program's PreToolUse filter is the
      # first one here that can ERROR on user-shaped data (`map` over a
      # non-array, if something writes `\"PreToolUse\": \"…\"`), and the `sh -c`
      # body has no `set -e` — an unconditional `mv` would install jq's empty
      # output as the user's whole settings.json and report success.
      #
      # PreToolUse is the exception, and is APPENDED rather than set: unlike the
      # worktree events it is a general-purpose event that Claude, a plugin or you
      # may well have opinions on too, so the merge drops any stale copy of our own
      # handler by command path and re-appends one, leaving every other entry in
      # place. The filter drops BOTH spellings of our own handler: the current
      # one, and `agent-desktop-ask` — the name this hook wore before #596
      # renamed it. A settings.json written while the old binary was live
      # still carries the old path, and without it in the filter that stale
      # entry survives every rebuild beside the fresh one — every Bash call
      # asked twice, forever. Dropping a dead spelling is safe exactly because
      # nothing re-inserts it: the append below is the only writer this filter
      # feeds, and it writes the new name only. It points at
      # `agent-desktop-guard` (modules/ai), which re-asks
      # before a tool call moves the pointer, takes focus or redraws the desktop —
      # the counterweight to the `defaultMode = "auto"` two lines below, which is
      # right for files and wrong for the screen. It refuses nothing.
      # FOUR events get `scruff hook notify` APPENDED the same way, and they are
      # two directions of one thing. Notification and Stop turn "this lane is
      # blocked on its user" / "this lane finished" into a trill banner — an ask
      # parked on trill's ledge, or a done. UserPromptSubmit and PostToolUse
      # take an answered ask back DOWN: the user typed, or a tool actually ran,
      # which is what approving a permission prompt leads to. Without those two
      # the ledge kept saying "waiting on you" while the agent was already ten
      # minutes into the work.
      #
      # The filter drops only what it is about to insert — the append's whole
      # safety is there (this is an append, not the assignment
      # WorktreeCreate/Remove use, which self-heal). It filters on the one
      # spelling of the command, which is only safe because every settings.json
      # on the machine has since been rewritten with it — dropping a spelling
      # from the filter while entries using it are still in the file leaves
      # them in place beside the new one: every agent pane firing two
      # notifications, forever.
      #
      # A third way down is not a hook at all and does not live here:
      # lanes/lane-seen.sh clears a lane's fin when you FOCUS its window, which
      # is the earlier signal — you can read a question and think for a minute
      # before typing, and the ledge should stop flagging it the moment you are
      # standing in front of it. These two stay because focus is not always
      # observable (no tiler, a lane answered from the Claude Code desktop app)
      # and because answering from somewhere else must still clear it.
      #
      # PostToolUse fires on every tool call in every pane, so the cost matters:
      # scruff gates the whole path behind one marker file per outstanding fin, so
      # an ordinary tool call reads one directory and stops — no registry read,
      # no launch of Trill.app's binary. Drop that event from the list if you
      # would rather pay nothing at all; the fin then clears at the end of the
      # turn instead, when Stop replaces it.
      #
      # Appended, never set: all four also carry the user's own agent-state
      # hooks (the bar's agents pill — see modules/bar), which must survive
      # every rebuild. The hook itself is scruff's and exits 0 no matter what — no
      # trill installed, daemon down, garbage payload — so wiring it on a
      # machine without trill is a silent no-op, never a broken session.
      # Claude Code settings/hooks/statusline are agent tooling; a machine that
      # runs no agents should not have its ~/.claude/settings.json rewritten.
      home.activation.claudeCodeSettings = lib.mkIf agentsCfg.enable (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run sh -c '
            settings="$0"
            mkdir -p "''${settings%/*}"
            tmp="$settings.hm-seed"
            if [ -s "$settings" ]; then base="$settings"; else base="$tmp.base"; printf "{}" > "$base"; fi
            ${pkgs.jq}/bin/jq ".hooks.WorktreeCreate = [{hooks: [{type: \"command\", command: \"/run/current-system/sw/bin/scruff hook create\"}]}]
              | .hooks.WorktreeRemove = [{hooks: [{type: \"command\", command: \"/run/current-system/sw/bin/scruff hook remove\"}]}]
              | .hooks.PreToolUse = (((.hooks.PreToolUse // []) | map(select([.hooks[]?.command] | any(. == \"/run/current-system/sw/bin/agent-desktop-guard\" or . == \"/run/current-system/sw/bin/agent-desktop-ask\") | not))) + [{matcher: \"Bash|mcp__computer-use__.*\", hooks: [{type: \"command\", command: \"/run/current-system/sw/bin/agent-desktop-guard\"}]}])
              | .hooks.Notification = (((.hooks.Notification // []) | map(select([.hooks[]?.command] | index(\"/run/current-system/sw/bin/scruff hook notify\") | not))) + [{hooks: [{type: \"command\", command: \"/run/current-system/sw/bin/scruff hook notify\"}]}])
              | .hooks.Stop = (((.hooks.Stop // []) | map(select([.hooks[]?.command] | index(\"/run/current-system/sw/bin/scruff hook notify\") | not))) + [{hooks: [{type: \"command\", command: \"/run/current-system/sw/bin/scruff hook notify\"}]}])
              | .hooks.UserPromptSubmit = (((.hooks.UserPromptSubmit // []) | map(select([.hooks[]?.command] | index(\"/run/current-system/sw/bin/scruff hook notify\") | not))) + [{hooks: [{type: \"command\", command: \"/run/current-system/sw/bin/scruff hook notify\"}]}])
              | .hooks.PostToolUse = (((.hooks.PostToolUse // []) | map(select([.hooks[]?.command] | index(\"/run/current-system/sw/bin/scruff hook notify\") | not))) + [{hooks: [{type: \"command\", command: \"/run/current-system/sw/bin/scruff hook notify\"}]}])
              | .permissions.defaultMode = \"auto\"
              | .tui = \"fullscreen\"
              | .disableAgentView = true
              | .spinnerTipsEnabled = false
              | .statusLine = {type: \"command\", command: \"/run/current-system/sw/bin/claude-statusline\", refreshInterval: 12}
              | .footerLinksRegexes = [{type: \"regex\", pattern: \"(?<owner>[A-Za-z0-9_.-]+)/(?<repo>[A-Za-z0-9_.-]+)#(?<pr>[0-9]+)\", url: \"https://github.com/{owner}/{repo}/pull/{pr}\", label: \"{repo}#{pr}\"}]" \
              "$base" > "$tmp" && mv "$tmp" "$settings"
            rm -f "$tmp.base"
          ' "$HOME/.claude/settings.json"
        ''
      );

      # Codex — the same agent status wiring, in Codex's own hook file, so a
      # Codex window lights the `agents` pill exactly like a Claude or Opencode
      # one. Three of its ten events carry the states we draw:
      #
      #   UserPromptSubmit  → working
      #   PermissionRequest → waiting    ← the urgent one; the pill goes red
      #   Stop              → idle
      #
      # There is deliberately no fourth: Codex has no session-END event (its list
      # stops at Stop), so nothing can report `remove`. A zmx session closes that
      # by construction: its labels live in the session and die with it, so a
      # window that goes away takes its row with it — which also cleans up after
      # any client that dies without saying goodbye. Schema verified against codex-cli 0.145.0 by running a real turn
      # with `--dangerously-bypass-hook-trust` and watching the hooks fire: it is
      # Claude-shaped (PascalCase event → matcher groups → `{type, command}`
      # handlers), the command runs under `$SHELL -lc` with the session's cwd, and
      # it inherits $ZMX_SESSION — which is the whole addressing scheme.
      #
      # First launch after this lands, Codex will ask you to REVIEW the hooks
      # ("Hooks need review") and won't run them until you trust them. That gate
      # is Codex's, it is a good one, and haus does not try to defeat it —
      # `--dangerously-bypass-hook-trust` exists but appears nowhere here.
      #
      # Merged with jq rather than owned outright: hooks.json is a user-editable
      # file and may hold hooks of your own, which must survive a rebuild.
      # Only written when Codex is actually installed (`ai.clients`).
      home.activation.codexAgentHooks = lib.mkIf (agentsCfg.enable && lib.elem "codex" agentClients) (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run sh -c '
            hooks="$0"
            bin="$1"
            mkdir -p "''${hooks%/*}"
            tmp="$hooks.hm-seed"
            if [ -s "$hooks" ]; then base="$hooks"; else base="$tmp.base"; printf "{}" > "$base"; fi
            ${pkgs.jq}/bin/jq --arg bin "$bin" ".hooks.UserPromptSubmit = [{hooks:[{type:\"command\",command:(\$bin + \" working codex\")}]}]
              | .hooks.PermissionRequest = [{hooks:[{type:\"command\",command:(\$bin + \" waiting codex\")}]}]
              | .hooks.Stop = [{hooks:[{type:\"command\",command:(\$bin + \" idle codex\")}]}]" \
              "$base" > "$tmp"
            mv "$tmp" "$hooks"
            rm -f "$tmp.base"
          ' "$HOME/.codex/hooks.json" "/run/current-system/sw/bin/agent-state"
        ''
      );

      # pi — the same idea in pi's own settings file, and the same split every
      # merge here makes between "what makes this a haus lane" and "what is
      # yours". Two keys are RE-ASSERTED every rebuild, two are only SEEDED when
      # the file has no opinion yet, and the package list is UNIONED.
      #
      # Re-asserted, because they are how a lane looks rather than what you
      # think about it:
      #   tuiMode = "fullscreen"  — the alt-screen renderer, the same choice
      #     `.tui = "fullscreen"` makes for Claude Code above, so two panes side
      #     by side are the same shape. Ghostty's ⇧-drag selection still reaches
      #     the alt-screen, so it costs nothing.
      #   quietStartup = true     — drop pi's startup header. A lane pane opens
      #     already knowing what it is; the statusline carries the rest.
      #
      # Seeded once, because they are taste and pi lets you change them from
      # `/settings` mid-session — a rebuild that reverted what you just chose
      # would be haus arguing with you:
      #   hideThinkingBlock       — thinking folded away by default.
      #   modelThinkingLevels     — think hard on the Anthropic models by
      #     default.
      #
      # Both are guarded on `has()` rather than merged, and the object one is
      # the reason why: `{ours} + (.yours // {})` looks like seed-once and
      # isn't. A level you CHANGED wins, but one you DELETED in `/settings`
      # comes back at the next rebuild — which is precisely the arguing this
      # split exists to avoid. `has()` asks the only question that separates
      # "never had an opinion" from "had one and dropped it".
      #
      # And `packages` is a union, never a set: `ai.pi.packages` is added beside
      # whatever `pi install` put there, so the file stays yours. The corollary
      # is in that option's docs — dropping an entry from the Nix list does not
      # uninstall it, because haus does not own this array and must not delete
      # from it.
      #
      # `agentsCfg`, not `config.haus.…`: everything from here down is inside
      # `home-manager.users.<name>`, where `config` is home-manager's own and
      # has no `haus`. The let-binding at the top of this file is the outer one.
      #
      # Gated on pi actually being installed, unlike the Claude block above
      # which follows the room alone. The difference is what the two write: a
      # statusline path and some hooks help a hand-installed Claude Code and
      # cost a machine without one nothing, while this seeds a list of npm
      # sources — a settings file naming code to fetch, for a client that isn't
      # here, is litter with a sharp edge.
      home.activation.piSettings = lib.mkIf (agentsCfg.enable && lib.elem "pi" agentClients) (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run sh -c '
            settings="$0"
            packages="$1"
            mkdir -p "''${settings%/*}"
            tmp="$settings.hm-seed"
            if [ -s "$settings" ]; then base="$settings"; else base="$tmp.base"; printf "{}" > "$base"; fi
            ${pkgs.jq}/bin/jq --argjson add "$packages" ".tuiMode = \"fullscreen\"
              | .quietStartup = true
              | (if has(\"hideThinkingBlock\") then . else .hideThinkingBlock = true end)
              | (if has(\"modelThinkingLevels\") then . else .modelThinkingLevels = {\"anthropic/claude-opus-5\": \"high\", \"anthropic/claude-fable-5\": \"high\", \"anthropic/claude-sonnet-5\": \"high\"} end)
              | .packages = ((.packages // []) + (\$add - (.packages // [])))" \
              "$base" > "$tmp" && mv "$tmp" "$settings"
            # Both, not just the base: when jq fails the `&& mv` short-circuits
            # and a half-written "$tmp" would otherwise sit beside the real
            # settings file forever, looking like something pi should read.
            #
            # 🚨 NO APOSTROPHE ANYWHERE IN THIS BLOCK, comments included. The
            # whole script is ONE single-quoted `sh -c` argument, so a lone
            # apostrophe in a COMMENT ends that argument early and every word
            # after it re-parses. Not a style nit — it is how this activation
            # died on 2026-08-27. The comment above used to read "beside pi"
            # plus an apostrophe plus "s real": the quote ended at pi, the two
            # arguments on the closing line were swallowed into the wreckage,
            # `$1` arrived empty, and `jq --argjson add` got an empty string.
            # jq exits 2 with "invalid JSON text passed to --argjson", which
            # aborts activation BEFORE /run/current-system moves — so the Mac
            # silently keeps its old generation and every later step never
            # runs. A comment written to explain a safety measure is what
            # broke the thing it explained.
            #
            # It built fine, too: the stray apostrophe happened to pair with
            # the one on the closing line, so the script stayed syntactically
            # valid while meaning something else entirely. Nothing catches
            # that but running it. Say "the real settings file", never
            # possessives, and keep every quoted word double-quoted.
            rm -f "$tmp" "$tmp.base"
          ' "$HOME/.pi/agent/settings.json" ${lib.escapeShellArg (builtins.toJSON agentsCfg.pi.packages)}
        ''
      );
    };
}

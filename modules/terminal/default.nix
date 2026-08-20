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
  # now pounce appHotkeys entries (modules/launcher), and a Nix assertion cannot
  # see into another room's generated JSON. The table and the appHotkeys list are
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
    # ⌘B — consumed by pounce (cmd:bench-lane): build+activate this window's holt
    # LANE — this worktree plus every `holt child` worktree spawned from it — in
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

in
{
  # ---- what this room contributes to other rooms ------------------------------
  # Nothing, since 2026-08-18. This room used to hand windows the agent-spawn
  # chord's script (`_contrib.windows.agents`, when the chord was the global
  # ⌃⌘A); ⌘↵ is a Ghostty-scoped pounce hotkey now, and pounce reaches the same
  # script through its own `cmd:lane-here` command rather than through an
  # option. The file this room installs at
  # ~/.config/haus/lanes/lane-spawn.sh is still the one thing the chord runs.

  # The agent assertions that used to sit here — default-not-in-clients, clients
  # without the tooling, a client nixpkgs can't build — are the AI room's own
  # invariants and moved to modules/ai with its switch. They named only
  # `haus.ai.*`, and they have to fail the rebuild on a machine with no
  # terminal room at all.
  # Agent lanes used to ASSERT haus.windows.enable here, and that was one room
  # deciding another room's business. What actually needed the tiler was never
  # the lane — the zmx session that outlives its window, the hold-on-error, the
  # bar row, holt's registry are all tiler-free — it was PLACEMENT (which has no
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
  #                            the option (see modules/renamed.nix).
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
  # IINA used to sit here too, purely because this room's hijack code was next
  # door. It's an editorial pick, not shell config, so it lives in modules/apps
  # now — the room whose whole job is the apps the rice chooses for you.
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
  ++ lib.optional ghDashCfg.enable "gh-dash";

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
      # haus.theme.{flavor,contrast} select which rendered variant everything
      # below reads — see ../lib/nebelung.nix, which owns that resolution for
      # terminal, bar and theme alike (it was duplicated in all three the moment
      # `contrast` landed; the `flavor` axis would have made that six blocks).
      #
      # nbFlavor is not decoration. whiskers names its output after the flavor it
      # rendered, so every path below that used to say "mocha" is now built from
      # nbFlavor and a latte rice resolves to catppuccin-latte.conf under the latte
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
      floatring = pkgs.callPackage ./package-floatring.nix { };
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
      glowPlugin = pkgs.runCommand "glow.yazi" { } ''
        # Nix interpolates a store path into a string without asserting anything is
        # there, and accent-reach fingerprints this plugin's TEXT — the accent varies
        # only INSIDE the path, so a missing referent would still read `moves`. This
        # is the one place the build can see the file, so check it here.
        [ -f "${glowStyle}" ] || {
          echo "terminal: nebelung has no glamour port at ${glowStyle}" >&2
          echo "  (haus.theme.flavor/accent moved past what the pinned nebelung ships)" >&2
          echo "  Pick another accent, or — if you author haus — nix flake update nebelung." >&2
          exit 1
        }
        cp -r ${./yazi/plugins/glow.yazi} $out
        chmod -R +w $out
        substituteInPlace $out/main.lua --subst-var-by glowStyle ${glowStyle}
      '';

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
      # HUD (holt's branches, seen from GitHub). It is not usable yet, in two
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
        # `holt` reads it as the LOWEST rung of `defaultAgent`
        # (`internal/commands/env.go`), below `~/.config/holt/config.toml`'s
        # `agent =` — which this module also writes, but only under
        # `haus.ai.enable`. So this is what answers for a machine with the
        # agent room off, and it is the only rung a standalone holt install
        # gets for free.
        HAUS_AGENT_DEFAULT = agentDefault;
      };

      # A lean terminal/dev toolbelt, gated by the developer pack. Personal
      # choices (AI CLIs, orbstack, your language toolchains) belong in your
      # host file, not the public rice.
      home.packages =
        with pkgs;
        # duti is a roster entry (below, at the darwin level) rather than a
        # bare package — the room that installs an app declares it, and the
        # roster is what makes a second copy from a cask a build warning
        # instead of the silent duplicate IINA was for months (modules/apps
        # owns that pick now; modules/roster tells the story).
        lib.optionals devCfg.toolbelt.enable [
          chafa # fast terminal image previewer / layout engine
          glow # markdown renderer; yazi's glow previewer shells out to it
          fd # fast finder; used by yazi/zoxide navigation
        ]
        # Editing the rice's own Nix is a developer activity; `haus edit` still
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
        # zmx — what a lane opens into. `lane-open.sh` defers to holt's
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

            # Secrets: prefer secretspec (ships with the rice) — a project
            # declares its secrets in a committed secretspec.toml and
            # `secretspec run -- cmd` injects the values from your provider
            # (haus.secrets.provider) into just that process, nothing
            # plaintext on disk. Anything you truly need in EVERY shell,
            # export in your HOST file's initContent (this is the public rice).

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
              # worktree: holt reaps the checkout, the link dangles, and
              # compinit (which reads the first line of every file it globs)
              # names the missing path in EVERY shell after that. A reaped
              # worktree never comes back, so drop links pointing into one.
              # Anything else that dangles is left alone and left noisy — an
              # unmounted volume comes back, and a link YOU made is yours to
              # fix, not ours to delete.
              for _haus_stale in $_haus_comps[1]/*(-@N); do
                [[ "$(readlink -- "$_haus_stale")" == "$HOME/.cache/claude-worktrees/"* ]] &&
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
            # Gated to the surface this rice spawns — a Ghostty window — because
            # the hop is about ITS cwd inheritance. A third-party terminal (an
            # editor's integrated one, ssh) opened deliberately inside a
            # worktree must not be teleported out of it.
            if [[ "$TERM_PROGRAM" == ghostty ]] &&
               [[ -z "$CLAUDECODE" && -z "$HAUS_STAY" && "$PWD" == "$HOME/.cache/claude-worktrees/"* ]]; then
              _wt_main="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
              [[ -n "$_wt_main" ]] && cd "''${_wt_main:h}"
              unset _wt_main
            fi
            unset HAUS_STAY

            # The chpwd hook that renamed the zellij tab after the repo is
            # gone with the tabs. A window's name is not ours to write: for a
            # lane it is a FORCED --title carrying the `holt.<repo>.<lane>` join
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
      # not under XDG, so home.file can't target it — we symlink into each
      # Profiles/*/chrome at activation instead. Symlinks (not copies) so a
      # palette rebuild propagates like every other port. Also flips on Firefox's
      # legacy userChrome/userContent stylesheets, which fresh profiles ship off.
      # Zen isn't installed here (themed-but-manual); the loop no-ops if absent.
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
            $DRY_RUN_CMD ln -sf "${zenTheme}/userChrome.css" "$chrome/userChrome.css"
            $DRY_RUN_CMD ln -sf "${zenUserContent}" "$chrome/userContent.css"
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
      home.activation.obsidianNebelung = lib.mkIf (terminalCfg.obsidianVaults != [ ]) (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
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
                exit 1
              fi
              mv "$tmp" "$appearance"
              rm -f "$tmp.base"
            ' "$obsidian/appearance.json"
          }

          ${lib.concatMapStringsSep "\n" (
            vault: "installObsidianNebelung ${lib.escapeShellArg vault}"
          ) terminalCfg.obsidianVaults}
          unset -f installObsidianNebelung
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
        # Holt's durable machine default. launchd daemons and zmx sessions
        # can outlive the environment that started them, so `holt new` resolves
        # this generated file instead of inheriting a stale client selection.
        # A standalone Holt install can own the same file by hand.
        ".config/holt/config.toml".text = ''
          # Generated from haus.ai.default — edit that option, not here.
          agent = "${agentDefault}"

          # `open` and `resume` are the two seams holt answers by exec'ing a
          # client; both are answered here by the same script, because with zmx
          # they are the same act — `zmx attach` creates the session or joins
          # the live one.
          #
          # The path is under ~, not a store path: holt's own docs list "a hook
          # pointing at a store path from a rebuild ago" as a way for this to
          # break, and home.file below keeps this one current.
          [hooks]
          open = "${config.home.homeDirectory}/.config/haus/lanes/lane-open.sh"
          resume = "${config.home.homeDirectory}/.config/haus/lanes/lane-open.sh"
        '';

        # The lane opener itself — what holt's [hooks] above exec.
        ".config/haus/lanes/lane-open.sh" = {
          source = ./lanes/lane-open.sh;
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

        # Opencode's half of the agent status the bar's paw pill draws.
        # Claude Code's equivalent is four hooks in ~/.claude/settings.json,
        # which the USER wires (Claude owns that file and rewrites it, so the rice
        # never has); opencode instead auto-loads every file under this directory,
        # so the rice can own the whole wiring and a fresh machine gets working
        # paws for opencode panes with nothing to configure.
        # @AGENT_STATE@ → core's `agent-state` by absolute path: a plugin runs
        # inside opencode's server process, which is given no PATH guarantees.
        ".config/opencode/plugin/haus-agent-state.js".text =
          builtins.replaceStrings [ "@AGENT_STATE@" ] [ "/run/current-system/sw/bin/agent-state" ]
            (builtins.readFile ./opencode/agent-state.js);
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
        # for compatibility: nothing but this rice ever wrote to it, and a
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
        # The one floating-Ghostty helper (geom + spawn + ring); peek.sh, the
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
      # A GUI app from nixpkgs (IINA, which modules/apps ships) is linked
      # into ~/Applications/Home Manager Apps as a SYMLINK, and LaunchServices
      # resolves that to the /nix/store path when it registers the bundle — so
      # every record it keeps is pinned to a store hash. Bump the package and the
      # hash changes: the "Open With" entry, the default-handler binding, and
      # `open -b <bundle-id>` all still name a path that garbage collection is
      # about to remove, and the app quietly stops being the handler for its own
      # file types. (Masked for anyone who ALSO has the app from a cask — the
      # /Applications copy keeps answering for the shared bundle id, which is how
      # a machine can carry two copies of one app and never notice.)
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
      # It opens files in the rice editor (haus.terminal.editor) via the same
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
            # The rice owns each of these EXCLUSIVELY, and that is a rule, not a
            # coincidence: modules/apps keeps `ts`, `mts` and `m2ts` out of
            # IINA's video list precisely so nothing here is contested. Two
            # rice-owned apps claiming one type never settles — both claims
            # re-run on every activation and macOS stops to ask the user which
            # app wins, every rebuild, forever. So before adding an extension,
            # check it against `iinaVideoExts` in modules/apps/default.nix — by
            # UTI, not by spelling, since one UTI can carry several extensions
            # (claiming `mts` drags `.m2ts` along; AVCHD gives them one).
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
      #     sessions here go through `holt` + zmx windows (core/terminal), not the
      #     in-app view, so the hint is pure noise — kill it at the rice level.
      #   statusLine  — point Claude Code's status bar at `claude-statusline`
      #     (core ships it on PATH). It renders THIS session's `holt` worktree +
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
      # Set as whole arrays, not merged into: these two events are rice plumbing
      # pointing at a rice-controlled /run/current-system path, and there is no
      # sensible second handler for "make me a worktree". Every OTHER hook event
      # in the file is untouched — including the four agent-state hooks, which
      # stay yours (see modules/bar/options.nix).
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
      # place. It points at `agent-desktop-guard` (modules/ai), which re-asks
      # before a tool call moves the pointer, takes focus or redraws the desktop —
      # the counterweight to the `defaultMode = "auto"` two lines below, which is
      # right for files and wrong for the screen. It refuses nothing.
      # Claude Code settings/hooks/statusline are agent tooling; a machine that
      # runs no agents should not have its ~/.claude/settings.json rewritten.
      home.activation.claudeCodeSettings = lib.mkIf agentsCfg.enable (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run sh -c '
            settings="$0"
            mkdir -p "''${settings%/*}"
            tmp="$settings.hm-seed"
            if [ -s "$settings" ]; then base="$settings"; else base="$tmp.base"; printf "{}" > "$base"; fi
            ${pkgs.jq}/bin/jq ".hooks.WorktreeCreate = [{hooks: [{type: \"command\", command: \"/run/current-system/sw/bin/holt hook create\"}]}]
              | .hooks.WorktreeRemove = [{hooks: [{type: \"command\", command: \"/run/current-system/sw/bin/holt hook remove\"}]}]
              | .hooks.PreToolUse = (((.hooks.PreToolUse // []) | map(select([.hooks[]?.command] | index(\"/run/current-system/sw/bin/agent-desktop-guard\") | not))) + [{matcher: \"Bash|mcp__computer-use__.*\", hooks: [{type: \"command\", command: \"/run/current-system/sw/bin/agent-desktop-guard\"}]}])
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
      # Codex window lights the `agents` paw exactly like a
      # Claude or Opencode one. Three of its ten events carry the states we draw:
      #
      #   UserPromptSubmit  → working
      #   PermissionRequest → waiting    ← the urgent one; the pill goes amber
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
      # is Codex's, it is a good one, and the rice does not try to defeat it —
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
    };
}

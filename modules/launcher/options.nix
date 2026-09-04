# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# The launcher room's options — the ⌘Space palette daemon and its window switcher.
{ lib, config, ... }:

let
  contrib = import ../lib/contrib.nix { inherit lib; };
in
{
  options.haus = {
    # ---- the Launcher room's extension points ---------------------------------
    # See modules/lib/contrib.nix for the contract, and modules/ai for today's
    # only writer.
    _contrib.launcher.agents = contrib.mkExtensionPoint {
      description = ''
        The AI room's palette surface: the client **Spawn Agent** starts, and the
        Agent Worktrees cards on the cheatsheet's Tips page.

        Off, the palette carries no agent rows — the same gate the agent cards
        on the Keys page already used, named once here instead of re-derived from
        `haus.ai.clients` in three separate places.
      '';
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether the palette carries the agent commands and cards.";
        };
        default = lib.mkOption {
          type = lib.types.str;
          default = "claude";
          description = ''
            The client Spawn Agent starts by default — `haus.ai.default`. Its
            prompt box's `⇥` chip can pick another for one lane, and falls back
            to an installed client if this one is not there.
          '';
        };
        repoRoots = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Where Spawn Agent looks for repositories — `haus.ai.repoRoots`,
            verbatim, tildes and all. The launcher writes it into the pounce
            daemon's environment as `HAUS_REPO_ROOTS`; expanding and reading it
            is the command's business, not this room's.
          '';
        };
        namer = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            Whether this machine has a scruff namer, and which — `haus.ai.namer`.
            Spawn Agent needs to know because it has always named the lane
            ITSELF, from a stopword slug of the prompt, and a name given to
            `scruff spawn` always wins: with a namer configured the command hands
            scruff no name at all and lets the brief name the lane. The slug
            survives as the offline answer, handed down as
            `SCRUFF_NAMER_FALLBACK`.

            `claude`, scruff's built-in, is passed through but deliberately not
            acted on: it reads no environment (so it cannot honour the floor)
            and costs 8-12s, all of it between Return and the lane, with the
            palette already gone. The command's own comment carries the reasoning.

            Reaches the command as `HAUS_LANE_NAMER`, the same way `repoRoots`
            reaches it — a launchd GUI agent inherits nothing from a shell, so
            the daemon's environment is the only channel.
          '';
        };
      };
    };

    # The Focus room's palette surface. Two facts, and the second is why this
    # point carries data rather than only a switch: a scene is generated into
    # its own palette command and its own cheatsheet row, so the launcher needs
    # the scenes themselves — but only the one field it renders. `hooks`,
    # `apps`, `audio` and the rest never cross, which is the difference between
    # a declared point and reading `config.haus.focus.scenes` whole.
    _contrib.launcher.focus = contrib.mkExtensionPoint {
      description = ''
        The Focus room's palette rows: **Toggle Focus**, one **Scene** command
        per declared scene, and **Leave Scene** beside them.

        Off, none of them is installed and none appears on the cheatsheet — the
        commands exec `~/.local/bin/focus`, which only that room ships.
      '';
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether the palette carries the focus commands and rows.";
        };
        scenes = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options.description = lib.mkOption {
                type = lib.types.str;
                default = "";
                description = "The scene's one-line description — `haus.focus.scenes.<name>.description`.";
              };
            }
          );
          default = { };
          description = ''
            The declared scenes, keyed by name. The key is what `focus scene`
            takes and what the row fuzzy-matches, so the palette row and the
            CLI teach each other; the description is the only field the palette
            renders.
          '';
        };
      };
    };

    _contrib.launcher.mouseChords = contrib.mkExtensionPoint {
      description = ''
        The windows room's pointer chord: a modifier + a click, acting on the
        window under the cursor rather than on the focused one.

        It lands here because the palette is the only thing on the machine that can
        carry it — AeroSpace has no mouse bindings at all, and Ghostty's
        keybind triggers are keys or Unicode codepoints, so a consuming
        CGEventTap is the mechanism and the palette already runs two of them behind
        the Accessibility grant they need. What the chord DOES is still the
        windows room's business; the launcher only writes it into
        `config.json`.

        Off, the palette's `mouseChords` block isn't written at all and every click
        keeps its stock meaning.
      '';
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether the palette arms a mouse chord at all.";
        };
        button = lib.mkOption {
          type = lib.types.enum [
            "left"
            "right"
          ];
          default = "right";
          description = "Which button the chord uses — `haus.windows.mouseFullscreen`.";
        };
        modifiers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "alt" ];
          description = ''
            The modifiers held, in the palette's spelling. Follows
            `haus.keys.windowNav`, so the pointer chord and `<mod>f` are one
            vocabulary. Never empty: the palette refuses a bare chord, and the
            windows room asserts the pair before it gets here.
          '';
        };
        action = lib.mkOption {
          type = lib.types.str;
          default = "fullscreen";
          description = "The palette action the chord fires.";
        };
      };
    };

    launcher.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "The pounce command palette daemon (⌘Space) + the palette commands haus ships.";
    };

    launcher.windowSwitcher = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Replace the stock ⌘Tab app switcher with the palette's MRU *window*
        switcher: tap ⌘⇥ to toggle to the last window (across workspaces), hold ⌘ and keep
        tapping ⇥ to walk older ones, type while holding to fuzzy-filter
        (frecency-ranked). Rows are gathered by AeroSpace workspace under a
        header each, and focusing goes through `aerospace focus --window-id` so
        a window parked on another workspace surfaces correctly.

        Because the tiler is running here, a bare tap deliberately looks past the
        workspace you're on and takes the most recent window on a different
        one — with two panes tiled side by side the most recent window is one
        you're already looking at, so landing there wouldn't be a switch.
        Moving between visible tiles stays windowNav's focus keys; the skipped
        siblings are still the rows just below you in the list.

        Pages count as the workspace they belong to: `T`, `T/haus` and `T/main`
        are one place, so walking pages with ⌃⇥ and then tapping ⌘⇥ takes you
        off `T` altogether rather than back to the page you just left. Getting
        between pages is the ⌃⇥ walk's job, the same division of labour as
        windowNav's focus keys above.

        Needs the daemon to hold an Accessibility grant. The daemon runs the
        release app (whose team-anchored signing requirement is what keeps the
        grant alive across rebuilds), so on a haus machine this is a one-time
        approval, not a rebuild-by-rebuild ritual. Without the grant the event
        tap can't install and stock ⌘Tab keeps working, so this default is safe
        on a fresh, not-yet-granted install. false leaves ⌘Tab native even when
        the grant is there.
      '';
    };

    launcher.autoQuit.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Quit an app when you close its last window, the way Windows does it.
        macOS keeps a windowless app running, so every one of them is a ⌘Q you
        forgot; with this on, the palette notices the last window go away and asks
        the app to quit.

        *Asked*, not killed — it is the same Quit event ⌘Q sends, so an app
        with unsaved work puts its sheet up and stays. Nothing here can lose
        work that ⌘Q wouldn't. What it CAN do is stop background work you were
        keeping a window open for: close Docker Desktop's dashboard and Docker
        is asked to quit, which stops your containers. Media players, torrent
        clients and chat apps have the same shape — that class of app is what
        haus.launcher.autoQuit.exclude is for.

        Reads the same window snapshot as the ⌘Tab switcher, so it wants the
        same Accessibility grant (a one-time approval of the release app) and
        shares the observers rather than taking its own. Without the grant it
        stays off and says so in the log rather than guessing.

        Off by default: this changes when your apps die, which is a thing you
        feel, and the muscle memory it suits is not everyone's.

        Unlike the rest of the palette's config, the auto-quit settings are read once
        — when the daemon arms them — rather than per open. So a rebuild that
        touches any of the three restarts the palette daemon, which haus does
        for you; nothing here needs a log-out to land.
      '';
    };

    launcher.autoQuit.delay = lib.mkOption {
      type = lib.types.numbers.between 0.25 3600;
      default = 2;
      example = 5;
      description = ''
        Seconds to wait after the last window closes before looking again and
        quitting. Load-bearing, not politeness: it is what tells "I'm done with
        this app" apart from "close this window, open another" — which is what
        a browser does when you close its last window and hit ⌘N. Anything open
        at the end of the wait, including panels and dialogs the ⌘Tab switcher
        wouldn't list, calls the quit off.

        Two seconds is the responsive end of that trade. It is deliberately not
        enough for a cold IDE reopening a project — that is a case for
        haus.launcher.autoQuit.exclude rather than for a delay you would feel on
        every app.

        Read once, when auto-quit arms — changing it bounces the palette daemon
        on the next rebuild.
      '';
    };

    launcher.autoQuit.exclude = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      defaultText = lib.literalMD "the palette's own list — `[ \"com.apple.finder\" ]`";
      example = [
        "com.apple.finder"
        "com.docker.docker"
        "com.spotify.client"
      ];
      description = ''
        Bundle ids never auto-quit. `null` leaves the palette's own default in
        place, which is `[ "com.apple.finder" ]` — Finder is the one app macOS
        runs windowless by design, and quitting it blinks the desktop out while
        it relaunches.

        A list you write **replaces** that default rather than extending it, so
        put Finder back in it unless you mean to drop it. `[ ]` really does
        mean nothing is excluded.

        Read a bundle id off any running app with
        `osascript -e 'id of app "Notes"'`.

        Read once, when auto-quit arms — adding an app here bounces the palette
        daemon on the next rebuild, so the app stops being quit immediately
        rather than at the next log-in.
      '';
    };

    launcher.windowMode = lib.mkOption {
      type = lib.types.enum [
        "default"
        "compact"
      ];
      # Matches pounce's own default. Compact hides the list until you type,
      # which reads as an empty palette to anyone who has not been told
      # otherwise — not the first thing a new machine should show.
      default = "default";
      description = ''
        The palette's proportions. `default` is the palette's roomier layout,
        which shows the top results the moment it opens — pounce's own default,
        and haus's. `compact` is narrower with tighter rows and keeps its list
        hidden until you type; it also turns off the Stage, whose tiles are
        exactly the "something on an empty query" compact exists to avoid.

        This is shape, not size: how BIG the palette is drawn is
        haus.launcher.scale. The two compose — a compact palette at scale 1.4
        is still the compact layout, just readable from further away.
      '';
    };

    launcher.scale = lib.mkOption {
      type = lib.types.numbers.between 0.8 2.0;
      default = lib.min 2.0 (lib.max 0.8 config.haus.ui.scale);
      # Prose, so literalMD — see haus.developer.languages in modules/options.nix.
      defaultText = lib.literalMD "haus.ui.scale, held inside the palette's 0.8-2.0";
      example = 1.4;
      description = ''
        How big the palette is drawn. Multiplies every size in its UI — the
        launcher's rows, header, icons and action bar, and the panels behind it:
        the emoji grid, clipboard history, recent screenshots, camera peek, Find
        Files, the cheatsheet and the window switcher.

        Follows haus.ui.scale by default, so you rarely set this directly.
        It exists as its own option for the case where the palette wants a
        different size from the rest of haus — the launcher is read at arm's
        length for a second, not lived in like the terminal.

        The palette's own range is narrower than ui.scale's, so a machine at
        `ui.scale = 2.5` gets a palette at 2.0 rather than an evaluation error.

        Two things adapt on their own, which is why one number is enough: the
        launcher shows fewer rows when the scaled rows stop fitting on screen, and
        every panel's width is held inside the visible frame. That matters most
        alongside `haus.displays.<name>.uiScale` — a larger-text display mode
        and a larger palette multiply, and the palette is the one that would
        otherwise run off the edge.
      '';
    };

    launcher.followSystemAppearance = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Let the launcher follow macOS Light/Dark Mode instead of pinning one
        polarity: it gets the nebelung variant AND its latte counterpart at
        your haus.theme.contrast, as its `theme`/`themeLight` pair, and
        picks between them per open (no rebuild, no daemon restart).

        Honest scope: this makes the launcher the one themed tool that does NOT follow
        haus.theme.flavor — a flavor pin is a *palette* choice, and asking
        to follow the system says the polarity is macOS's call. The contrast
        axis still applies to both halves. Every other themed tool keeps
        whatever flavor pins.

        false pins the launcher to the flavor like every other port, which is exactly
        what it did before this option existed.
      '';
    };

    launcher.fnKey = lib.mkOption {
      type = lib.types.enum [
        "tap"
        "remap"
      ];
      # Defaults to the SHARING mechanism, even though it is the one that loses
      # races: `remap` takes the physical Fn key away from every app on the
      # machine, and haus wires mode:emoji to Fn by default (see default.nix) —
      # turning that into "my Fn+arrows stopped working" for someone who never
      # asked is not a default's job.
      default = "tap";
      example = "remap";
      description = ''
        How the palette gets the Fn/Globe key when an item binds it — which
        haus does by default, with haus.launcher.items."mode:emoji".hotkey = "fn".

        `tap` reads Fn with an event tap. It needs Pounce's Accessibility grant,
        and it SHARES the key with macOS: HIToolbox carries its own Globe handler
        inside every process, below the event stream a tap can see, so macOS's
        Emoji & Symbols picker can still open alongside the palette's. Setting System
        Settings ▸ Keyboard ▸ "Press 🌐 key to" to Do Nothing helps, but that
        value is read from login-session state — it wants a full logout, and even
        then the two handlers are racing rather than one owning the key.

        `remap` takes Fn away at the HID layer instead: it becomes F19, which
        the palette binds like any ordinary key. No Accessibility grant for this
        binding, and nothing left for macOS to race, because there is no Fn key
        in the system any more. That last part is also the cost — Fn stops being
        Fn EVERYWHERE, so no Fn+arrows (Home/End/PageUp/PageDown), no Fn+Delete,
        no Fn+F1–F12. Worth it on a Mac where Fn is only ever the emoji key; a
        bad trade on one where Fn+arrows is muscle memory.

        Three things `remap` does not promise:

        - F19 is a real key on the full-size Magic Keyboard (the one with a
          numeric keypad), where pressing it fires the binding too.
        - A keyboard that re-enumerates — an external one replugged, some
          sleep/wake cycles — drops the mapping, and the binding stays dead
          until the palette daemon restarts. `pounce doctor` reports it.
        - If F19 is already taken, or the keyboard doesn't expose Fn to IOHID,
          the palette undoes the remap and falls back to the tap — Accessibility
          grant and all.

        On haus the mapping is declared rather than left to the daemon
        (modules/launcher/default.nix says why: nix-darwin writes IOKit's
        UserKeyMapping whole, so a rebuild would otherwise drop a mapping the palette
        installed). It shares that list with the Caps Lock leader's remap, is
        re-applied at each activation, and does not survive a reboot — but it
        DOES outlive the daemon, so Fn stays remapped and inert while the palette is
        stopped. `pounce doctor` reports which of the two mechanisms is actually
        carrying the key.

        Inert unless something binds `fn`: with no such item, this is a key
        the palette reads and does nothing with. On a default haus that item is the
        emoji grid and Fn is its ONLY key — the Caps-Lock leader dropped `e` once
        one key did the job — so a host that turns the Fn binding off wants to
        put mode:emoji on something else.
      '';
    };

    launcher.items = lib.mkOption {
      default = { };
      example = {
        "cmd:emoji" = {
          alias = "emo";
          hotkey = "opt+e";
        };
        "cmd:brew-services".listed = false;
        "cmd:lane-here".workspaces = [ "T" ];
        "cmd:peek".bundleIds = [ "com.mitchellh.ghostty" ];
        "app:/Applications/Ghostty.app".hotkey = "opt+t";
        "shortcut:0ECC8F7A-3A52-467A-84C0-511CCE1CB9B7".alias = "shelf";
        "mode:clipboard".hotkey = "cmd+shift+v";
      };
      description = ''
        Per-item palette settings, keyed by the item's own address. One entry is
        one row of the palette: hide it, give it a search shorthand, give it a
        key, or list it only where it is useful (`workspaces` / `bundleIds`).

          "cmd:<id>"                       a command, by script name without .sh
          "app:/Applications/Foo.app"      an application, by path
          "shortcut:<uuid>"                a Shortcuts-library entry, by the id
                                           `shortcuts list --show-identifiers` prints
          "mode:<name>"                    a built-in window — launcher, clipboard,
                                           emoji, screenshots, camera, filesearch

        Those keys are the palette's own address space (the same strings its frecency
        store and `pounce run` use), so a key written here is also what you'd type
        to invoke the thing from a script or another tool's binding.

        Hotkeys can be a single chord ("opt+e") or a LEADER SEQUENCE — steps
        separated by spaces, modifiers by "+", the notation Emacs and VS Code use:

          hotkey = "opt+space e";          # ⌥Space, then E
          hotkey = [ "cmd+k" "cmd+c" ];    # the same thing, step by step

        The modifier-only laptop Fn/Globe key is the one special single-step
        value: hotkey = "fn". By default it is read with an event tap, which
        needs Pounce's Accessibility grant (unlike a Carbon chord or leader
        sequence) and fires only when Fn is tapped alone — and which SHARES the
        key with macOS's own Globe action, so the system emoji picker can still
        open alongside the palette's. haus.launcher.fnKey = "remap" is the way to own
        the key outright; read that option before reaching for it, because it
        costs Fn's other jobs. haus uses Fn for mode:emoji by default; set that
        item's hotkey to null to leave the Globe key to macOS — but Fn is the ONLY
        key haus gives the emoji grid. The Caps-Lock leader carried it on `e`
        until the Fn tap made that second binding redundant (`e` is unbound now,
        and `f` is Find Files), so nulling this leaves ⌘Space → "emoji" as the
        only route. Give mode:emoji another hotkey in the same breath if you want
        a key for it.

        Sequences are worth knowing about on a tiling desktop: they open a namespace
        that structurally can't collide with the ⌥/⌘ chords windows already claims,
        and they need no Accessibility grant (the palette grabs the second step as an
        ordinary global hotkey for a couple of seconds rather than tapping events).

        Two things this checks at build time, because both fail SILENTLY at
        runtime: a key that names no real item shape (a "mode:" typo binds
        nothing at all), and a chord already claimed by haus.keys.palette,
        haus.keys.leader, or a terminal binding (whoever registers first
        wins, and it isn't always the same one). What it can't check is whether
        `cmd:<id>` names a command that exists — command scripts are discovered
        at runtime, so the palette warns about that itself when the daemon starts, and
        `pounce doctor` lists any binding that failed to arm.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            listed = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                Whether the item appears in the palette's list.

                Named `listed` rather than `enable` because that is precisely what
                it does: false removes the ROW, and a `hotkey` on the same item
                keeps working. It's how you hide a command you only ever want to
                reach by key — or clear the launcher of tools someone else on this
                Mac has no use for, which is the closest thing to a "pack" the
                surface has today. (It writes the palette's own `enabled` key.)
              '';
            };

            alias = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "emo";
              description = ''
                A search shorthand, matched at a bonus over the item's real name —
                so "emo" can find the Emoji Picker without renaming it.
              '';
            };

            caption = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              example = "Clipboard history";
              description = ''
                How this item reads on the cheatsheet page that lists your item
                hotkeys (⌘Space then ⇥, or the leader's `/`). Only used when the
                item has a `hotkey` — a row without a key has nothing to teach.

                Defaults to a name derived from the key, which is right often
                enough to leave alone: `mode:clipboard` becomes "Clipboard
                history", `app:/Applications/Ghostty.app` becomes "Ghostty", and
                `cmd:brew-services` becomes "Brew services". Set this when the
                derived name isn't what the palette actually calls the row —
                haus can't read a command's own `# pounce: name` header at
                evaluation time, so that one is a guess.

                A `shortcut:<uuid>` key derives nothing better than "Shortcut":
                the name lives in your Shortcuts library, which no build can
                read. Give any shortcut you bind a key a caption.
              '';
            };

            hotkey = lib.mkOption {
              type = lib.types.nullOr (lib.types.either lib.types.str (lib.types.listOf lib.types.str));
              default = null;
              example = "opt+space e";
              description = ''
                A global chord, or a leader sequence, that invokes this item
                directly without opening the palette first. Modifier names follow
                the palette's spelling: cmd/command/super/meta · opt/option/alt ·
                ctrl/control · shift.

                Whether the KEY name is one the palette can bind is not checked here
                (that vocabulary lives in the app); a chord it can't register is
                reported by `pounce doctor` rather than silently dropped.

                `fn` is the modifier-only exception, and how it is carried is
                haus.launcher.fnKey: by default an Accessibility-gated event tap
                that fires on a lone tap and SHARES the key with macOS's own
                Globe action, or `remap`, which takes the key away from macOS
                entirely at the cost of Fn's other jobs.
              '';
            };

            workspaces = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = [ "T" ];
              description = ''
                List this row only while one of these workspaces is in front.
                Empty — the default — means everywhere.

                A bare name matches that page AND its children, the same rule
                the ⌃⇥ page walk's prefix uses: `"T"` covers T and every
                T/<repo> lane page. `"T/*"` is the children only, and `"T/main"`
                is that one page. Case-insensitive.

                It scopes the ROW, never this item's `hotkey` — a key you bound
                stays bound, exactly as it does under `listed = false`. What
                this is FOR is a row whose command needs the window you were
                looking at: an agent lane or a shell "here" reads the focused
                terminal's directory, and from a browser it has nothing to read.

                Which page you are on is read from the workspace-recency file
                the windows room's AeroSpace hook maintains. **With no such file
                — no tiler, or the windows room off — this filters nothing**,
                deliberately: a machine that cannot answer the question would
                otherwise hide the row forever.
              '';
            };

            bundleIds = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = [ "com.mitchellh.ghostty" ];
              description = ''
                List this row only while one of these apps is frontmost. Empty —
                the default — means any app.

                The tighter twin of `workspaces` for a row that needs a
                particular app rather than a particular page: a Ghostty window
                dragged onto another page still satisfies this one, and a
                browser parked on a terminal page does not. Set both and the row
                wants both. Case-insensitive.

                Like `workspaces`, it scopes the row alone. Scoping a KEY to an
                app is a different mechanism with a different cost — the palette
                has to consume the keystroke to do it — and haus writes those
                itself (the ⌘↵ and ⌘N Ghostty taps).
              '';
            };
          };
        }
      );
    };

    launcher.plugins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "docker"
        "tailscale"
      ];
      description = ''
        Optional palette commands to install, by id. Each one assumes a
        specific tool, service or app it cannot provision, so the whole set is
        off until you name what you have:

          audio  bluetooth  caffeinate  docker  github
          perplexity  spotify  ssh  tailscale

        Enabling one installs the command AND the plain CLI it shells out to —
        bluetooth pulls blueutil, audio pulls switchaudio-osx, github pulls gh
        — so the command stops guarding "not found" with no separate install.
        The ones that want an app or a daemon instead (Spotify, a Docker
        engine, tailscaled) stay yours to provide; those guard at runtime with
        an install hint.

        The ids are pounce's own `optional/` filenames without .sh, not a
        vocabulary haus invents on top. A typo fails the build naming the set
        that exists, which is why this is a plain list rather than an enum
        haus would have to keep in step with pounce's lock.

        This is the whole of what a "pack" is here, and the other two halves
        already exist: haus's own commands are gated by the feature that owns
        them (`bench-lane` by haus.developer.enable, `gh-dash` by
        haus.terminal.ghDash.enable, the lane commands by the AI room), and
        haus.launcher.items.<addr>.listed = false hides a row you would rather
        reach only by key.
      '';
    };

    # Where haus's own palette commands (modules/launcher/commands) landed in
    # the store. Internal, and the same shape as _roster: one resolved value
    # every room reads instead of each recomputing it. Empty when the launcher is off.
    #
    # It exists because SketchyBar's plugins are copied into ~/.config verbatim
    # rather than generated, so a plugin cannot interpolate a store path of its
    # own — and the alternative to handing it this one is a second copy of
    # rebuild.sh and reload-bar.sh living inside the bar. Only the palette's BUILT-IN
    # commands get a `pounce-<id>` bin on PATH (pkgs/pounce-commands wraps
    # `builtinIds`); a haus command arrives through `extraCommandDirs`, which
    # the palette discovers at runtime and nothing puts a launcher in front of.
    # No `readOnly`, unlike _roster: readOnly counts the option's own `default`
    # as a definition, so an option that has both can never be assigned.
    _pounceCommands = lib.mkOption {
      type = lib.types.str;
      internal = true;
      default = "";
      description = "Store path of haus's own palette commands, for rooms that invoke one directly.";
    };
  };
}

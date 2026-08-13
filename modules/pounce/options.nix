# Part of the nebelhaus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# pounce's options — the ⌘Space palette daemon and its window switcher.
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

        Off, the palette carries no agent rows — the same gate the ⌘A card on the
        Keys page already used, named once here instead of re-derived from
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
          description = "The client Spawn Agent starts — `haus.ai.default`.";
        };
      };
    };

    pounce.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "The pounce command palette daemon (⌘Space) + its rice commands.";
    };

    pounce.windowSwitcher = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Replace the stock ⌘Tab app switcher with pounce's MRU *window* switcher:
        tap ⌘⇥ to toggle to the last window (across workspaces), hold ⌘ and keep
        tapping ⇥ to walk older ones, type while holding to fuzzy-filter
        (frecency-ranked). Rows are gathered by AeroSpace workspace under a
        header each, and focusing goes through `aerospace focus --window-id` so
        a window parked on another workspace surfaces correctly.

        Because prowl is tiling here, a bare tap deliberately looks past the
        workspace you're on and takes the most recent window on a different
        one — with two panes tiled side by side the most recent window is one
        you're already looking at, so landing there wouldn't be a switch.
        Moving between visible tiles stays windowNav's focus keys; the skipped
        siblings are still the rows just below you in the list.

        Needs the daemon to hold an Accessibility grant — in practice, set
        haus.pounce.signingIdentity so the grant survives rebuilds. Without
        the grant the event tap can't install and stock ⌘Tab keeps working, so
        this default is safe on a fresh, not-yet-granted install. false leaves
        ⌘Tab native even when the grant is there.
      '';
    };

    pounce.autoQuit.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Quit an app when you close its last window, the way Windows does it.
        macOS keeps a windowless app running, so every one of them is a ⌘Q you
        forgot; with this on, pounce notices the last window go away and asks
        the app to quit.

        *Asked*, not killed — it is the same Quit event ⌘Q sends, so an app
        with unsaved work puts its sheet up and stays. Nothing here can lose
        work that ⌘Q wouldn't. What it CAN do is stop background work you were
        keeping a window open for: close Docker Desktop's dashboard and Docker
        is asked to quit, which stops your containers. Media players, torrent
        clients and chat apps have the same shape — that class of app is what
        haus.pounce.autoQuit.exclude is for.

        Reads the same window snapshot as the ⌘Tab switcher, so it wants the
        same Accessibility grant (set haus.pounce.signingIdentity so it
        survives rebuilds) and shares the observers rather than taking its own.
        Without the grant it stays off and says so in the log rather than
        guessing.

        Off by default: this changes when your apps die, which is a thing you
        feel, and the muscle memory it suits is not everyone's.

        Unlike the rest of pounce's config, the auto-quit settings are read once
        — when the daemon arms them — rather than per open. So a rebuild that
        touches any of the three restarts the pounce daemon, which the rice does
        for you; nothing here needs a log-out to land.
      '';
    };

    pounce.autoQuit.delay = lib.mkOption {
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
        haus.pounce.autoQuit.exclude rather than for a delay you would feel on
        every app.

        Read once, when auto-quit arms — changing it bounces the pounce daemon
        on the next rebuild.
      '';
    };

    pounce.autoQuit.exclude = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = null;
      defaultText = lib.literalMD "pounce's own list — `[ \"com.apple.finder\" ]`";
      example = [
        "com.apple.finder"
        "com.docker.docker"
        "com.spotify.client"
      ];
      description = ''
        Bundle ids never auto-quit. `null` leaves pounce's own default in
        place, which is `[ "com.apple.finder" ]` — Finder is the one app macOS
        runs windowless by design, and quitting it blinks the desktop out while
        it relaunches.

        A list you write **replaces** that default rather than extending it, so
        put Finder back in it unless you mean to drop it. `[ ]` really does
        mean nothing is excluded.

        Read a bundle id off any running app with
        `osascript -e 'id of app "Notes"'`.

        Read once, when auto-quit arms — adding an app here bounces the pounce
        daemon on the next rebuild, so the app stops being quit immediately
        rather than at the next log-in.
      '';
    };

    pounce.windowMode = lib.mkOption {
      type = lib.types.enum [
        "default"
        "compact"
      ];
      default = "compact";
      description = ''
        The palette's proportions. `compact` is narrower with tighter rows and
        keeps its list hidden until you type — the rice's tuned look, and what it
        shipped before this option existed. `default` is pounce's roomier layout,
        which shows the top results the moment it opens.

        This is shape, not size: how BIG the palette is drawn is
        haus.pounce.scale. The two compose — a compact palette at scale 1.4
        is still the compact layout, just readable from further away.
      '';
    };

    pounce.scale = lib.mkOption {
      type = lib.types.numbers.between 0.8 2.0;
      default = lib.min 2.0 (lib.max 0.8 config.haus.ui.scale);
      # Prose, so literalMD — see haus.developer.languages in modules/options.nix.
      defaultText = lib.literalMD "haus.ui.scale, held inside pounce's 0.8-2.0";
      example = 1.4;
      description = ''
        How big the palette is drawn. Multiplies every size in pounce's UI — the
        launcher's rows, header, icons and action bar, and the panels behind it:
        the emoji grid, clipboard history, recent screenshots, camera peek, Find
        Files, the cheatsheet and the window switcher.

        Follows haus.ui.scale by default, so you rarely set this directly.
        It exists as its own option for the case where the palette wants a
        different size from the rest of the rice — the launcher is read at arm's
        length for a second, not lived in like the terminal.

        pounce's own range is narrower than ui.scale's, so a rice at
        `ui.scale = 2.5` gets a palette at 2.0 rather than an evaluation error.

        Two things adapt on their own, which is why one number is enough: the
        launcher shows fewer rows when the scaled rows stop fitting on screen, and
        every panel's width is held inside the visible frame. That matters most
        alongside `haus.displays.<name>.uiScale` — a larger-text display mode
        and a larger palette multiply, and the palette is the one that would
        otherwise run off the edge.
      '';
    };

    pounce.followSystemAppearance = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Let the palette follow macOS Light/Dark Mode instead of pinning one
        polarity: pounce gets the nebelung variant AND its latte counterpart at
        your haus.theme.contrast, as its `theme`/`themeLight` pair, and
        picks between them per open (no rebuild, no daemon restart).

        Honest scope: this makes pounce the one themed tool that does NOT follow
        haus.theme.flavor — a flavor pin is a *palette* choice, and asking
        to follow the system says the polarity is macOS's call. The contrast
        axis still applies to both halves. Everything else on the rice keeps
        whatever flavor pins.

        false pins pounce to the flavor like every other port, which is exactly
        what it did before this option existed.
      '';
    };

    pounce.items = lib.mkOption {
      default = { };
      example = {
        "cmd:emoji" = {
          alias = "emo";
          hotkey = "opt+e";
        };
        "cmd:brew-services".listed = false;
        "app:/Applications/Ghostty.app".hotkey = "opt+t";
        "mode:clipboard".hotkey = "cmd+shift+v";
      };
      description = ''
        Per-item palette settings, keyed by the item's own address. One entry is
        one row of the palette: hide it, give it a search shorthand, give it a key.

          "cmd:<id>"                       a command, by script name without .sh
          "app:/Applications/Foo.app"      an application, by path
          "mode:<name>"                    a built-in window — launcher, clipboard,
                                           emoji, screenshots, camera, filesearch

        Those keys are pounce's own address space (the same strings its frecency
        store and `pounce run` use), so a key written here is also what you'd type
        to invoke the thing from a script or another tool's binding.

        Hotkeys can be a single chord ("opt+e") or a LEADER SEQUENCE — steps
        separated by spaces, modifiers by "+", the notation Emacs and VS Code use:

          hotkey = "opt+space e";          # ⌥Space, then E
          hotkey = [ "cmd+k" "cmd+c" ];    # the same thing, step by step

        The modifier-only laptop Fn/Globe key is the one special single-step
        value: hotkey = "fn". It needs Pounce's Accessibility grant, unlike a
        Carbon chord or leader sequence, and fires only when Fn is tapped alone.
        The rice uses it for mode:emoji by default; set that item's hotkey to
        null to leave the Globe key to macOS.

        Sequences are worth knowing about on a tiling rice: they open a namespace
        that structurally can't collide with the ⌥/⌘ chords prowl already claims,
        and they need no Accessibility grant (pounce grabs the second step as an
        ordinary global hotkey for a couple of seconds rather than tapping events).

        Two things this checks at build time, because both fail SILENTLY at
        runtime: a key that names no real item shape (a "mode:" typo binds
        nothing at all), and a chord already claimed by haus.keys.palette,
        haus.keys.leader, or a terminal binding (whoever registers first
        wins, and it isn't always the same one). What it can't check is whether
        `cmd:<id>` names a command that exists — command scripts are discovered
        at runtime, so pounce warns about that itself when the daemon starts, and
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
                surface has today. (It writes pounce's own `enabled` key.)
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
                derived name isn't what the palette actually calls the row — the
                rice can't read a command's own `# pounce: name` header at
                evaluation time, so that one is a guess.
              '';
            };

            hotkey = lib.mkOption {
              type = lib.types.nullOr (lib.types.either lib.types.str (lib.types.listOf lib.types.str));
              default = null;
              example = "opt+space e";
              description = ''
                A global chord, or a leader sequence, that invokes this item
                directly without opening the palette first. Modifier names follow
                pounce's spelling: cmd/command/super/meta · opt/option/alt ·
                ctrl/control · shift.

                Whether the KEY name is one pounce can bind is not checked here
                (that vocabulary lives in the app); a chord it can't register is
                reported by `pounce doctor` rather than silently dropped.

                `fn` is the modifier-only exception: it uses Pounce's
                Accessibility-gated event tap, fires only on a lone tap, and
                suppresses macOS's stock Globe action while armed.
              '';
            };
          };
        }
      );
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

    # Where this rice's own palette commands (modules/pounce/commands) landed in
    # the store. Internal, and the same shape as _roster: one resolved value
    # every room reads instead of each recomputing it. Empty when pounce is off.
    #
    # It exists because SketchyBar's plugins are copied into ~/.config verbatim
    # rather than generated, so a plugin cannot interpolate a store path of its
    # own — and the alternative to handing it this one is a second copy of
    # rebuild.sh and reload-bar.sh living inside the bar. Only pounce's BUILT-IN
    # commands get a `pounce-<id>` bin on PATH (pkgs/pounce-commands wraps
    # `builtinIds`); a rice command arrives through `extraCommandDirs`, which
    # the palette discovers at runtime and nothing puts a launcher in front of.
    # No `readOnly`, unlike _roster: readOnly counts the option's own `default`
    # as a definition, so an option that has both can never be assigned.
    _pounceCommands = lib.mkOption {
      type = lib.types.str;
      internal = true;
      default = "";
      description = "Store path of this rice's pounce commands, for rooms that invoke one directly.";
    };
  };
}

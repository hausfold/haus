# Part of the nebelhaus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# pounce's options — the ⌘Space palette daemon and its window switcher.
{ lib, ... }:

{
  options.nebelhaus = {
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

    pounce.followSystemAppearance = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Let the palette follow macOS Light/Dark Mode instead of pinning one
        polarity: pounce gets the nebelung variant AND its latte counterpart at
        your nebelhaus.theme.contrast, as its `theme`/`themeLight` pair, and
        picks between them per open (no rebuild, no daemon restart).

        Honest scope: this makes pounce the one themed tool that does NOT follow
        nebelhaus.theme.flavor — a flavor pin is a *palette* choice, and asking
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

        Sequences are worth knowing about on a tiling rice: they open a namespace
        that structurally can't collide with the ⌥/⌘ chords prowl already claims,
        and they need no Accessibility grant (pounce grabs the second step as an
        ordinary global hotkey for a couple of seconds rather than tapping events).

        Two things this checks at build time, because both fail SILENTLY at
        runtime: a key that names no real item shape (a "mode:" typo binds
        nothing at all), and a chord already claimed by nebelhaus.keys.palette or
        nebelhaus.keys.leader (whoever registers first wins, and it isn't always
        the same one). What it can't check is whether `cmd:<id>` names a command
        that exists — command scripts are discovered at runtime, so pounce warns
        about that itself when the daemon starts, and `pounce doctor` lists any
        binding that failed to arm.
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
  };
}

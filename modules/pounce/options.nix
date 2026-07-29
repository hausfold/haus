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

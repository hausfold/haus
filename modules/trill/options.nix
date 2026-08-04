# Part of the nebelhaus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# trill's options — the Messages client.
{ lib, ... }:

{
  options.nebelhaus = {
    trill.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        The trill Messages client, installed via the trill flake (copied to
        /Applications).

        **Opt-in since 2026-08-04** — it used to default to true. Trill reads
        and sends, and the features past that (tapbacks, threaded replies,
        marking read upstream) are ones Messages.app gives no automation
        surface for, so they are not coming. Installing an app that isn't
        being finished on every machine by default set the bar for the rest of
        the house, so it stopped being part of it. The module itself is
        unchanged and fully supported: set this true and it installs exactly
        as before, theming and all.

        Turning it OFF does not remove an existing /Applications/Trill.app —
        this module only ever copies, and deleting an app you might still want
        is not the rice's call. To clean up after disabling:

            sudo rm -rf /Applications/Trill.app
            sudo rm -f "/Library/Application Support/nebelhaus/trill.installed-from"

        If you KEEP the app, remove the marker anyway. Trill reads it to decide
        whether it may update itself; a stale marker leaves it waiting for a
        `haus update` that no longer carries it, while without the marker it
        sees a direct install and resumes updating itself.
      '';
    };

    trill.followSystemAppearance = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Let trill's palette follow macOS Light/Dark Mode instead of pinning one
        polarity: trill gets the nebelung variant AND its latte counterpart at
        your nebelhaus.theme.contrast, and picks between them itself — no
        rebuild, no relaunch.

        Same honest scope as the pounce option of the same name: with this on,
        trill does NOT follow nebelhaus.theme.flavor, because asking to follow
        the system says the polarity is macOS's call. The contrast axis still
        applies to both halves. Set it false to pin trill to theme.flavor like
        every other themed tool.

        Either way this writes only the DEFAULT: a palette chosen in trill's own
        Settings ▸ Theme wins over what the rice writes, and so does trill's
        appearance preference (Follow macOS / Dark / Light), which lives in its
        settings rather than here.
      '';
    };
  };
}

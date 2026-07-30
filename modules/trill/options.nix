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
      default = true;
      description = "The trill Messages client, installed via the trill flake (copied to /Applications).";
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

# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# focus's options — the one quiet switch (Do Not Disturb + Slack + hooks).
{ lib, ... }:

{
  options.haus = {
    # ---- focus ----
    focus.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        The focus room: one quiet switch — bar pill, palette command, and a
        `focus` CLI — that turns macOS Do Not Disturb on/off (via the
        declaratively-bound symbolic hotkey 175, pressed synthetically),
        optionally sets your Slack status, and runs your hooks.

        Honest scope: focus flips the built-in Do Not Disturb, not named Focus
        modes, and it doesn't manage which apps break through — curate that
        once in System Settings. The keypress needs an Accessibility grant on
        whatever app invokes focus (palette runs inherit pounce's; grant
        sketchybar once for the pill). `focus doctor` walks the one-time steps.
      '';
    };

    focus.slack = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Also set a Slack status and snooze Slack notifications (all devices,
          phone included) while quiet. Off by default: it needs a personal
          Slack user token (scopes users.profile:write + dnd:write) provided
          via tokenCommand. The previous status is saved and restored on
          turning it off.
        '';
      };
      tokenCommand = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "security find-generic-password -s focus-slack -w";
        description = ''
          Shell command that prints the Slack user token (xoxp-…) to stdout.
          Keychain-first so no secret ever lands in the store or a dotfile:
            security add-generic-password -s focus-slack -a $USER -w 'xoxp-…'
        '';
      };
      statusText = lib.mkOption {
        type = lib.types.str;
        default = "heads down";
        description = "Slack status text while quiet.";
      };
      statusEmoji = lib.mkOption {
        type = lib.types.str;
        default = ":no_bell:";
        description = "Slack status emoji while quiet.";
      };
      snooze = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Also pause Slack's own notifications (dnd.setSnooze) while quiet —
          this is what silences the phone. Ended when it turns off; capped at 24h as
          a failsafe if you forget.
        '';
      };
    };

    focus.hooks = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.path lib.types.str);
      default = [ ];
      example = lib.literalExpression ''[ ./onair-light.sh "/Users/ada/bin/pause-music" ]'';
      description = ''
        Extra scripts run on every switch, both ways, each called with a single
        argument "on" or "off". Paths are copied into the store; strings are
        run as-is (so $HOME paths work). Failures are logged, never fatal —
        a broken hook can't wedge the toggle.
      '';
    };
  };
}

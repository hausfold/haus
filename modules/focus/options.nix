# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# focus's options — the one quiet switch (Do Not Disturb + Slack + hooks), and
# the named states around it (`scenes`), of which quiet is the built-in one.
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

        The same switch generalises: `haus.focus.scenes.<name>` declares other
        named states (stay awake, this microphone, these apps, these hooks) and
        `focus scene <name>` enters one. Quiet is the built-in scene, and the
        one every surface above already means.

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

    focus.scenes = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            description = lib.mkOption {
              type = lib.types.str;
              default = "";
              example = "camera on, nothing interrupts";
              description = "One line, shown by `focus scene list`. The scene's own name is the address.";
            };

            dnd = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                Turn Do Not Disturb on while this scene is. `false` means the
                scene leaves DND exactly as it found it — not that it turns it
                off.

                Entering a DND scene runs the Slack leg and `haus.focus.hooks`
                too, because it is the same quiet the bar pill and `focus on`
                mean — but only when the scene is what makes the Mac quiet.
                Entering one while already quiet changes nothing, so nothing
                fires, and leaving it fires nothing either: the two edges stay
                paired.
              '';
            };

            preventSleep = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Hold a `caffeinate` assertion (display, disk, idle and system)
                for as long as the scene is on. Released on exit. A reboot kills
                the assertion and leaves only a stale pid file behind, which the
                next entry clears — and the release checks the pid is still a
                caffeinate before signalling it, so a reused pid is never the
                one that gets killed.
              '';
            };

            apps.open = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = [
                "OBS"
                "Reminders"
              ];
              description = ''
                Apps to launch on entry, by the name or bundle id `open -a`
                takes. Honest scope: exiting a scene never closes them. Quitting
                an app you were mid-sentence in is not a decision a config file
                should make, so that reversal stays yours.
              '';
            };

            audio.input = lib.mkOption {
              type = lib.types.str;
              default = "";
              example = "Studio Mic";
              description = ''
                Switch the system input device on entry, by the exact name
                `SwitchAudioSource -a -t input` prints. Put back by `focus scene
                off` when the scene is what changed it — unlike DND there is no
                "off" for an input device, so `restorePreviousState` doesn't
                govern it. Naming a device that isn't plugged in logs and moves
                on; the rest of the scene still applies.
              '';
            };

            hooks = lib.mkOption {
              type = lib.types.listOf (lib.types.either lib.types.path lib.types.str);
              default = [ ];
              example = lib.literalExpression "[ ./key-light.sh ]";
              description = ''
                Scripts run on entry and exit, each called with "on" or "off" —
                the same contract as `haus.focus.hooks`, scoped to this scene.
                Failures are logged, never fatal.
              '';
            };

            restorePreviousState = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                On exit, put Do Not Disturb back the way it was before the scene
                started rather than always turning it off. It has exactly one
                case: you were **already quiet** when you entered. Left true,
                leaving the scene keeps you quiet, because nothing asked to be
                un-quieted. Set false, leaving always ends quiet-off.

                It doesn't govern anything else — a scene only ever reverses a
                lever it actually moved, so there is nothing else for "restore"
                and "off" to disagree about.
              '';
            };
          };
        }
      );
      default = { };
      example = lib.literalExpression ''
        {
          recording = {
            description = "camera on, nothing interrupts";
            preventSleep = true;
            audio.input = "Studio Mic";
            apps.open = [ "OBS" ];
          };
        }
      '';
      description = ''
        Named machine states, entered with `focus scene <name>` and left with
        `focus scene off`. One at a time: entering a scene leaves whichever was
        running, so the Mac is only ever in one.

        `quiet` is the built-in — it is what `focus on`, the bar pill and the
        palette command already enter — so the name is reserved and defining it
        here is an error. Shape quiet through `haus.focus.slack` and
        `haus.focus.hooks` instead.

        With the launcher room on, every scene is a palette row too — a
        generated `Scene: <name>` command, plus `Leave Scene`, each with a line
        on the cheatsheet's Palette Commands page — so entering one doesn't
        mean remembering its name in a terminal. A `haus.keys.leaderExtras`
        chord remains the way to give one a key.

        The half that is still deliberate scope: **nothing enters a scene for
        you** — no clock, no Wi-Fi network, no display appearing. Declaring
        the states is the cheap half and this is it; a daemon that decides
        *when* is a separate piece of work, and not one to pay for before a
        single scene has proved useful.
      '';
    };
  };
}

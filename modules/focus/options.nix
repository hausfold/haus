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
        whatever app invokes focus (palette runs inherit pounce's; the pill
        needs one on sketchybar itself, and TCC keys that to the binary — so
        it is asked again after a rebuild that moves it). `focus doctor` walks
        those steps.
      '';
    };

    focus.slack = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Also set a Slack status and snooze Slack notifications (all devices,
          phone included) while quiet. Off by default: it needs a personal
          Slack user token (scopes users.profile:write + dnd:write), which haus
          asks you for once (`haus-secret --check`) unless tokenCommand names
          another way to fetch it. The previous status is saved and restored on
          turning it off.
        '';
      };
      tokenCommand = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "op read op://private/slack/token";
        description = ''
          Shell command that prints the Slack user token (xoxp-…) to stdout.
          A command rather than a value so no secret ever lands in the store or
          a dotfile.

          EMPTY (the default) means haus holds it: with `slack.enable` on, this
          room declares SLACK_USER_TOKEN to the secrets room, `haus-secret
          --check` asks for it once, and `haus.secrets.provider` decides where
          it is kept. Set this only to fetch the token some other way.
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

    focus.triggers.interval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = ''
        Seconds between checks of every `scenes.<name>.when` condition. The
        agent that runs them exists only when some scene declares a condition,
        so a machine whose scenes are all hand-entered runs nothing at all and
        this option decides nothing.

        Thirty seconds is the compromise a clock wants: a window that opens at
        09:00 is entered by 09:00:30, and the check costs one short shell run.
        Raise it if a probe on this machine is expensive — the screen count
        falls back to `system_profiler` without the displays room, which is the
        one probe here that takes a visible moment.
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
                takes. Exiting a scene leaves them running unless
                `apps.closeOnExit` says otherwise — quitting an app you were
                mid-sentence in is not a decision a config file should make by
                default.
              '';
            };

            apps.closeOnExit = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                On exit, quit the apps this scene STARTED — the ones from
                `apps.open` that weren't already running when you entered. An
                app you already had open is not a lever the scene pulled, so
                leaving never closes it; that is the same rule DND and the input
                device follow, and it is what keeps a work mode from taking your
                editor down with it.

                The quit is the polite one (the same message ⌘Q sends), so an app
                with unsaved work still gets to ask. It is recorded on entry, so
                exit closes what it opened even if the scene has since been
                edited out of the table.
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

            # The trigger half. Every field here is a CONDITION — something that
            # is true or false about the machine right now — and they are ANDed:
            # a scene with a window and a network is entered inside the window
            # AND on that network. A scene that sets none of them is entered by
            # a person and nothing else, which is every scene that existed
            # before this option did.
            when = {
              time = lib.mkOption {
                type = lib.types.str;
                default = "";
                example = "09:00-17:00";
                description = ''
                  Enter this scene inside a daily window, `HH:MM-HH:MM` in
                  24-hour local time. An end earlier than the start wraps
                  midnight, so `22:00-06:00` is one night rather than an empty
                  window. Unset, the clock never enters this scene.

                  A window is a condition, not an alarm: the scene is entered on
                  the edge where the window opens, so leaving it by hand at ten
                  past nine leaves you out of it until tomorrow. The `scenes`
                  description says why that rule is the whole design.
                '';
              };

              days = lib.mkOption {
                type = lib.types.listOf (
                  lib.types.enum [
                    "mon"
                    "tue"
                    "wed"
                    "thu"
                    "fri"
                    "sat"
                    "sun"
                  ]
                );
                default = [ ];
                example = [
                  "mon"
                  "tue"
                  "wed"
                  "thu"
                  "fri"
                ];
                description = ''
                  Limit the trigger to these weekdays. Empty means every day.
                  It narrows the other conditions rather than standing on its
                  own: a scene whose only condition is a list of days is on for
                  all of every one of them.
                '';
              };

              wifi = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                example = [ "Home" ];
                description = ''
                  Enter this scene while joined to one of these Wi-Fi networks,
                  by the exact SSID. Empty means the network is not part of this
                  scene's condition.

                  Honest scope: the current SSID is the one probe macOS can
                  refuse to answer, and an unreadable SSID can't enter a scene —
                  which looks exactly like a network you are not on. `focus auto
                  --probe` prints what it reads right now and `focus doctor`
                  says when it comes back empty, so the difference is one
                  command rather than a guess.

                  It cannot END a scene either. macOS reports no network during
                  sleep/wake, roaming and VPN reconnects, so "I can't tell" holds
                  a running scene exactly where it is; only an SSID that reads
                  clearly and isn't in this list leaves.
                '';
              };

              power = lib.mkOption {
                type = lib.types.enum [
                  "any"
                  "ac"
                  "battery"
                ];
                default = "any";
                description = ''
                  Enter this scene only on wall power (`ac`) or only off it
                  (`battery`). `any` — the default — leaves the power source out
                  of this scene's condition.
                '';
              };

              displays = lib.mkOption {
                type = lib.types.nullOr lib.types.ints.positive;
                default = null;
                example = 2;
                description = ''
                  Enter this scene while at least this many displays are active,
                  the built-in screen included — so `2` is "docked" on a laptop,
                  and `null`, the default, leaves the screens out of this
                  scene's condition.

                  A count rather than a display's name, on purpose: which panel
                  is on your desk is a fact about one machine (the same reason
                  `haus.displays.<uuid>` is host-only), while "more than one
                  screen" is a shape any desktop can share.

                  Screens re-negotiate on wake, and a count that comes back
                  unreadable holds a running scene where it is rather than
                  ending it — the same rule `when.wifi` follows, for the same
                  reason. Where the count comes from is `focus doctor`'s
                  business: with the displays room on it is that room's helper,
                  and without it `system_profiler`, which can also count a
                  sleeping built-in panel the helper leaves out.
                '';
              };
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

        A scene with a `when` is entered for you — a daily window, a set of
        weekdays, a Wi-Fi network, the power source, how many screens are
        attached. One rule governs all of it, and it is the reason this is
        safe to leave running: **the daemon never overrides a state you
        chose.** It enters a scene on the EDGE where the condition becomes
        true and only from a neutral Mac, it leaves only the scene it entered
        itself, and it never re-enters one you walked out of until that
        condition has gone false and true again. So a scene you leave at ten
        past nine stays left, and a scene you enter by hand is never taken
        away from you.
      '';
    };
  };
}

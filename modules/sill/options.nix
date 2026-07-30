# Part of the nebelhaus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# sill's options — the menu bar: whether it's drawn, which pills, and the
# first-run tour that rides in it.
{ lib, ... }:

{
  options.nebelhaus = {
    sill.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        The SketchyBar menu bar. When off, the native macOS menu bar is kept
        (nebelhaus stops hiding it) and no bar is drawn.
      '';
    };

    sill.position = lib.mkOption {
      type = lib.types.enum [
        "top"
        "bottom"
        "auto"
      ];
      default = "top";
      example = "auto";
      description = ''
        Where the bar sits. `top` and `bottom` pin it there. `auto` flips it
        at runtime — `bottom` whenever an external display is attached (docked
        with the lid open, or clamshell), `top` on the built-in display alone —
        driven by a `display_change` hook, so the bar moves the moment you dock
        or undock, without a rebuild.

        The bar's height/pill offsets are tuned for the notch, which only
        exists at the top of the built-in display; at `bottom` there's no notch
        to tuck under, so `auto` conveniently keeps the notch case (`top`) on
        the notched screen and the plain case (`bottom`) on the external.
      '';
    };

    tour.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        The haus tour — a first-run tutor that walks the four moves (launch /
        navigate / resize / palette) as ONE quiet pill in the bar, advancing
        live as each move is detected. It never opens a window or steals
        focus: a fresh machine just shows a dormant "new here?" hint, clicking
        it (or `haus tour`, or ⌘Space → tour) starts the lap, right-click
        hides it forever. Detection reuses signals the rice already fires (the
        leader-mode scripts) — no key logging, no Accessibility.

        Needs prowl + sill (it silently stays out of the bar without them);
        the ⌘Space step is dropped when pounce is off. Progress lives in
        ~/.local/state/nebelhaus — `haus tour reset` re-arms a finished tour.
      '';
    };

    tour.steps = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.nonEmptyListOf (
          lib.types.submodule {
            options = {
              hint = lib.mkOption {
                type = lib.types.str;
                example = "Press ⌘Space, type calendar, then hit ↵";
                description = "The instruction shown in the tour pill for this step.";
              };

              detect = lib.mkOption {
                type = lib.types.enum [
                  "launch"
                  "workspace"
                  "navigate"
                  "resize"
                  "palette"
                ];
                example = "palette";
                description = ''
                  The existing rice signal that completes this step: entering launch,
                  navigate or resize mode; changing workspace; or running the Haus Tour
                  command from Pounce (`palette`). The tour observes outcomes, never
                  keystrokes. Clicking the pill still skips a step that cannot be
                  detected in the current setup.
                '';
              };
            };
          }
        )
      );
      default = null;
      example = [
        {
          hint = "Press ⌘Space, type tour, then hit ↵";
          detect = "palette";
        }
      ];
      description = ''
        A community-authored tour, in order. null keeps the built-in four-move
        nebelhaus tour unchanged; supplying a list replaces it, so a shared rice can
        teach its own workflow without shipping scripts or reaching outside the
        `nebelhaus.*` option surface.

        Detection reuses signals the rice already emits. `launch`, `workspace`,
        `navigate` and `resize` need prowl; `palette` needs Pounce and its palette
        binding. The module warns when a chosen detector's room is disabled.
      '';
    };

    # Per-pill on/off for the whole right side of the bar. One bool per item in a
    # submodule (not attrsOf) so unknown keys are rejected and each item carries
    # its own default: the core pills default true, the extras default false. The
    # descriptions here are the single source for the options reference.

    sill.items =
      let
        core = {
          clock = "The clock pill, pinned to the far right.";
          weather = "The weather pill and its click-to-open forecast popover.";
          media = "The now-playing track (scrolls; auto-hides when nothing plays).";
          battery = "The battery pill.";
          wifi = "The Wi-Fi status pill.";
        };
        extra = {
          cpu = "Total CPU load, as a percentage pill.";
          memory = "Memory-pressure percentage pill.";
          volume = "Output volume / mute state.";
          calendar = "Your next timed event, with a click-popup of the next five. Pulls in `ical-buddy` automatically and reads Calendar, so macOS prompts for Calendar access on first run.";
          caffeinate = "A coffee pill that prevents idle system sleep for 1/2/4/8 hours, a custom whole-hour duration, or indefinitely. The display may still turn off; closing a MacBook lid still sleeps it. Uses macOS's built-in `caffeinate`, so there is no extra package.";
          agents = "A paw pill tracking your `claude --worktree` agent panes — amber when one is blocked on you, click for the per-agent list; left-click a row to jump to that pane, ⌥/right-click for a live `zellij subscribe` peek. Fed by Claude Code hooks (point them at ~/.config/sketchybar/plugins/agents-hook.sh); dormant until they fire.";
          claudeUsage = "A gauge pill showing how much of your Claude Code usage you've spent — `<5-hour>·<weekly>` as percentages, coloured by whichever window is closest to biting (green under 50, red at 90). Click for both windows with their reset times. The numbers ride Claude Code's own statusline feed, so nothing is polled and no token is read; the pill stays hidden until a Claude session first reports, and greys out if none has in half an hour.";
          elgato = "Toggles an Elgato Key Light on the local network.";
          harvest = "A Harvest time-tracking pill; needs a ~/.config/sketchybar/harvest_secrets.sh you provide.";
        };
        mkItem = default: desc: lib.mkOption {
          type = lib.types.bool;
          inherit default;
          description = desc;
        };
      in
      lib.mkOption {
        type = lib.types.submodule {
          options = lib.mapAttrs (_: mkItem true) core // lib.mapAttrs (_: mkItem false) extra;
        };
        default = { };
        example = {
          weather = false;
          cpu = true;
        };
        description = ''
          Which SketchyBar pills to draw, one bool each. The core pills —
          `clock`, `weather`, `media`, `battery`, `wifi` — default true; the extras
          — the readouts `cpu`, `memory`, `volume`, `calendar`, `caffeinate`
          and the personal `agents`, `claudeUsage`, `elgato`, `harvest` —
          default false. Set
          only what you want to change:

            nebelhaus.sill.items = {
              weather = false;   # drop a default-on core pill
              cpu = true;        # add an off-by-default readout
              caffeinate = true; # add the keep-awake controller
            };

          A pill set false is never created (its update script doesn't run either).
          The hush (Do-Not-Disturb) pill is separate — it rides
          nebelhaus.hush.enable, not this set.
        '';
      };
  };
}

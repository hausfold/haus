# Part of the nebelhaus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# sill's options — the bar(s): whether one is drawn, which pills go on it, the
# optional second bar along the bottom of the screen, and the first-run tour
# that rides in the top one.
{ lib, ... }:

let
  agentClients = import ../lib/agents.nix;

  # Per-pill on/off for the whole right side of the bar. One bool per item in a
  # submodule (not attrsOf) so unknown keys are rejected and each item carries
  # its own default: the core pills default true, the extras default false. The
  # descriptions here are the single source for the options reference.
  #
  # Up here rather than inside `sill.items` because `sill.bottom.items` reads the
  # same tables — a pill's description is written once and both bars'
  # option pages render it.
  core = {
    clock = "The clock pill, pinned to the far right.";
    weather = "The weather pill and its click-to-open forecast popover.";
    media = "The now-playing track (scrolls; auto-hides when nothing plays, dims when paused, click to play/pause). It reads the same system-wide session Control Center does, so it follows a browser tab as readily as Apple Music or Spotify, and its icon says which app the sound is coming from. SketchyBar's own `media_change` event has been dead since macOS 15.4, where Apple started requiring an entitlement to talk to `mediaremoted`; the pill is fed instead by `media-control`, which does the read from inside the entitled `/usr/bin/perl`. That is a private-framework route Apple could close in any point release — `media-control test` exits non-zero once it has.";
    battery = "The battery pill.";
    wifi = "The Wi-Fi status pill.";
  };
  extra = {
    cpu = "Total CPU load, as a percentage pill.";
    memory = "Memory-pressure percentage pill.";
    volume = "Output volume / mute state.";
    calendar = "Your next timed event, with a click-popup of the next five. Pulls in `ical-buddy` automatically and reads Calendar, so macOS prompts for Calendar access on first run.";
    caffeinate = "A coffee pill that prevents idle system sleep for 1/2/4/8 hours, a custom whole-hour duration, or indefinitely. The display may still turn off; closing a MacBook lid still sleeps it. Uses macOS's built-in `caffeinate`, so there is no extra package.";
    agents = "A paw pill tracking your agent-worktree panes — amber when one is blocked on you, click for the per-agent list, each row marked with the client sitting in it; left-click a row to jump to that pane, ⌥/right-click for a live `zellij subscribe` peek. Fed by each client's own lifecycle hooks, which all call `agent-state` (also installed as ~/.config/sketchybar/plugins/agents-hook.sh): Opencode's plugin and Codex's ~/.codex/hooks.json are written for you (Codex asks you to trust its hooks the first time it sees them), while Claude Code's four agent-state hooks stay yours to point at it in ~/.claude/settings.json — Claude owns that file and rewrites it, so the rice merges in only the keys it must and never touches those four. (The two worktree hooks ARE declared, in hearth: they point at a rice-controlled path and self-heal on rebuild.) A row whose zellij pane is gone drops off by itself, which is what stands in for the session-end event Codex doesn't have. Dormant until a client fires.";
    aiUsage = "A gauge pill showing AI usage (Claude Code/Codex subscription rate limits as %, or Opencode API token cost as daily $). Automatically shows whichever provider reported most recently. Click for expanded session/weekly limits and daily/monthly API costs with model breakdowns. Claude and Opencode are read off disk; Codex has no local usage data, so its row is polled from your ChatGPT account with the OAuth token in ~/.codex/auth.json (refreshed and rewritten in place) — no Codex login on the machine, no call is made. Claude's row is pushed by its statusline; the Codex and Opencode rows are pulled by the pill itself on a 3-minute TTL, so they stay current on a machine that never opens Claude at all. Claude and Opencode also get a `tokens` block in the dropdown — raw tokens moved today, this week, this month and all time (cache reads and all), two periods to a line so a full set reads as a 2×2, purely for the fun of watching the number climb. A period with nothing in it is left out rather than printed as a zero, so the block simply gets smaller, and a closing `∑ Everything` adds every provider up when more than one is reporting. It is a score, not a limit: nothing acts on it, and it never reaches the pill's own label. Claude's is summed from your transcripts on a 15-minute TTL behind an index, so only sessions that grew since the last pass are re-read; Codex has no row because it keeps no local history to count.";
    claudeUsage = "Deprecated alias for `aiUsage`.";
    elgato = "Toggles an Elgato Key Light on the local network. The light is found over mDNS (or pinned with `haus.sill.elgato.host`), and the pill draws dim when it can't be reached at all — a light that dropped off the wifi is not the same thing as a light that's switched off.";
    harvest = "A Harvest time-tracking pill; needs a ~/.config/sketchybar/harvest_secrets.sh you provide.";
  };
  mkItem =
    default: desc:
    lib.mkOption {
      type = lib.types.bool;
      inherit default;
      description = desc;
    };

  # Which pills the SECOND bar can host. The whole right side is emitted from
  # one parameterized block table, so core and extra pills can move without a
  # second source copy. `claudeUsage` is left out because it is only a
  # deprecated alias for `aiUsage`.
  movable = core // builtins.removeAttrs extra [ "claudeUsage" ];
in
{
  options.haus = {
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

    sill.battery.hideOver = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 80;
      description = ''
        Hide the battery pill when charge percentage is above this threshold
        (e.g., set to 80 to show the battery pill only when charge is at or below 80%).
      '';
    };

    sill.clock.mode = lib.mkOption {
      type = lib.types.enum [
        "full"
        "compact"
      ];
      default = "full";
      example = "compact";
      description = ''
        The display mode for the clock pill: `full` (default, e.g. "Fri Jul 31  09:41 AM" with calendar icon)
        or `compact` (e.g. "Fri 31/7 9:41" without icon and trimmed spacing).
      '';
    };

    sill.aiUsage.provider = lib.mkOption {
      # The clients come from modules/lib/agents.nix — the same list
      # haus.agents.clients and .default read, so a fourth client is one
      # edit rather than one per room. `latest` is sill's own extra: it is a
      # selection rule, not a client, which is why it is prepended here.
      type = lib.types.enum ([ "latest" ] ++ agentClients);
      default = "latest";
      example = "claude";
      description = ''
        Which AI provider to display in the main pill: `latest` (default, automatically
        shows whichever provider reported most recently), or one of
        ${lib.concatMapStringsSep ", " (c: "`${c}`") agentClients}.
        Clicking the pill always displays the full dropdown with all reporting providers.

        Note this is about *usage readouts*, not about which client `holt` can
        spawn: a provider reports here whenever it has data for your account —
        Codex notably does so from a ChatGPT login alone, with no CLI installed
        — so it is deliberately not tied to `haus.agents.clients`.
      '';
    };

    sill.elgato.host = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "elgato-key-light-mini-57a3.local";
      description = ''
        Which Elgato Key Light the `elgato` pill toggles — a hostname or IP,
        optionally with a `:port` (the light's HTTP API is on 9123).

        Empty (the default) means discover it: the pill browses mDNS for
        `_elg._tcp`, caches what it found in
        `~/.local/state/nebelhaus/elgato-host`, and re-browses at most once a
        minute whenever the light stops answering — so a light that took a new
        DHCP address comes back on its own, without a rebuild. Pin this when
        you have more than one light, when the light has a static lease, or
        when mDNS is unreliable on your network.
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
                example = "Press {palette}, type calendar, then hit ↵";
                description = ''
                  The instruction shown in the tour pill for this step.

                  Name keys with the placeholders `{palette}`, `{leader}` and
                  `{leaderName}` rather than typing a chord: they expand to what
                  THIS machine resolved, so a tour written once still teaches the
                  right keys on a rice that moved `keys.palette` or `keys.leader`.
                  A hardcoded "⌘Space" is wrong on that machine and the author
                  never sees it — the consumer does.
                '';
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
          hint = "Press {palette}, type tour, then hit ↵";
          detect = "palette";
        }
      ];
      description = ''
        A community-authored tour, in order. null keeps the built-in four-move
        nebelhaus tour unchanged; supplying a list replaces it, so a shared rice can
        teach its own workflow without shipping scripts or reaching outside the
        `haus.*` option surface.

        Detection reuses signals the rice already emits. `launch`, `workspace`,
        `navigate` and `resize` need prowl; `palette` needs Pounce and its palette
        binding. The module warns when a chosen detector's room is disabled.

        Authoring a tour is also the ONLY way to have one without prowl: the
        built-in lap is three leader moves plus the palette, so `tour.enable` on a
        rice with `prowl.enable = false` draws nothing at all. `presets/everyday.nix`
        is the worked example — one step, the launcher.
      '';
    };

    sill.items = lib.mkOption {
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
        and the personal `agents`, `aiUsage`, `elgato`, `harvest` —
        default false. Set
        only what you want to change:

          haus.sill.items = {
            weather = false;   # drop a default-on core pill
            cpu = true;        # add an off-by-default readout
            caffeinate = true; # add the keep-awake controller
          };

        A pill set false is never created (its update script doesn't run either).
        The hush (Do-Not-Disturb) pill is separate — it rides
        haus.hush.enable, not this set.

        This is the MENU BAR's set. `haus.sill.bottom.items` is the same table
        for the optional second bar along the bottom of the screen, and a pill
        named there moves down rather than being drawn twice.
      '';
    };

    sill.bottom.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Draw a SECOND bar along the bottom of the screen, at the same time as
        the menu bar one. `haus.sill.bottom.items` picks what goes on it; an
        empty set draws an empty strip, which the module warns about.

        SketchyBar has no two-bars-in-one-process mode — an instance is named
        after `basename(argv[0])` and keys both its lock file and its mach
        service on that name — so this is a second launchd agent running the
        SAME binary under a second name, `sill-bottom`. That name is also the
        CLI for it: `sill-bottom --set cpu label=…` talks to the bottom bar the
        way `sketchybar --set` talks to the menu bar one.

        Two things macOS does not do for you here. It reserves the top strip of
        every display for the menu bar but reserves NOTHING at the bottom, so
        windows would sit under this bar: prowl carves the room out of its
        outer-bottom gap whenever this is on (with `haus.prowl.enable = false`,
        nothing reserves it and your windows will run underneath). And the Dock,
        if you keep it at the bottom, shares that edge — move it to a side, or
        leave it hidden.
      '';
    };

    sill.bottom.items = lib.mkOption {
      type = lib.types.submodule { options = lib.mapAttrs (_: mkItem false) movable; };
      default = { };
      example = {
        weather = true;
        media = true;
        cpu = true;
      };
      description = ''
        Which pills the bottom bar draws, one bool each, all default false. A
        pill named here MOVES: it is drawn on the bottom bar and not on the menu
        bar, whatever `haus.sill.items` says about it — so there is one switch
        per pill per bar and never two copies of the same readout.

        The set is the five core pills (`clock`, `weather`, `media`, `battery`,
        `wifi`) plus the `haus.sill.items` extras (`cpu`, `memory`, `volume`,
        `calendar`, `caffeinate`, `agents`, `aiUsage`, `elgato`, `harvest`). The
        whole left side (workspace pills, front app, the leader picker) and the
        tour stay on the menu bar. The hush pill stays up top too — it rides
        `haus.hush.enable` rather than this table.

        Needs `haus.sill.bottom.enable`; without it nothing here is drawn.
      '';
    };
  };
}

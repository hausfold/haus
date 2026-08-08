# Sill — a windowsill for your menu bar. SketchyBar, launched via nix-darwin,
# with the stray-agent eviction that keeps a rogue `brew services` instance from
# stealing the lock file.
#
# The workspace pills are data-driven: WORKSPACES / ws_icon are generated from
# haus._workspaces, LAUNCHER_KEYS from haus._launchers (the resolved
# shared app roster) — so the bar can't drift from AeroSpace's launcher. Every
# right-side pill is individually
# toggleable via haus.sill.items (one bool per pill): the core
# clock/weather/media/battery/wifi default on, the extras cpu/memory/volume/
# calendar/caffeinate plus the personal agents/elgato/harvest default off.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  withGUIWait = (import ../lib/gui-wait.nix).wrap;
  userPath = "/run/current-system/sw/bin:/etc/profiles/per-user/${username}/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin";

  sillpop = pkgs.callPackage ./sillpop.nix { };
  # What a pill with a dropdown uses instead of a bare `popup.drawing=toggle`, so
  # the dropdown also closes on a click anywhere else — sketchybar alone only ever
  # sees clicks on its own items (see sillpop.swift).
  #
  # The toggle stays FIRST and unchanged, so opening a dropdown costs exactly what
  # it always did; the guard is armed after it, backgrounded, and nothing waits on
  # it. That ordering is the whole latency story — armed inline, it added ~200 ms
  # to every open. `&` also means no fallback is needed: if the binary is missing
  # the popup has already opened, and only the dismissal is lost.
  popToggle =
    item:
    "sketchybar --set ${item} popup.drawing=toggle; /run/current-system/sw/bin/sillpop arm ${item} 2>/dev/null &";

  # Every dropdown on a RIGHT-side pill carries this. SketchyBar's popup.align
  # defaults to `left`, i.e. the popup's left edge is pinned to the pill's left
  # edge and the rows grow rightward — fine under the apple menu at the far left,
  # but on the right half of the bar a wide row (an agent's repo/branch, a usage
  # gauge) runs straight off the screen edge. `right` pins the popup's RIGHT edge
  # to the pill instead, so it opens leftward, into the bar. Left-side items
  # (apple.logo) deliberately keep the default.
  popupAlign = "popup.align=right";

  # haus.workspaces drives the pills now (workspace membership earns
  # one, not an app field — see notes/options-roadmap.md §5.4); the keyed
  # roster subset still drives the leader picker.
  launchers = config.haus._launchers;
  workspaces = config.haus._workspaces;
  appWorkspaceId = a: config.haus._appWorkspace.${a.id} or null;

  # ---- type sizes: ui.scale, up to the menu bar's own ceiling -----------------
  # Resolved in ../lib/bar.nix, not here, because PROWL reads the same resolution
  # to decide how much room to leave beside the bar — the bar's type and the gap
  # next to it have to move together, and a rule mirrored in two rooms is exactly
  # what modules/lib exists to prevent. See that file for why there's a ceiling at
  # all (short version: the bar's height belongs to the macOS menu-bar band, which
  # was measured to have no setting behind it).
  bar = import ../lib/bar.nix {
    inherit lib;
    scale = config.haus.ui.scale;
  };
  inherit (bar) sizes;

  # ---- the bar's type FAMILY, from the same option as the terminal's ----------
  # Everything in the bar except the workspace logos is drawn in this. It used to
  # be the literal "Hack Nerd Font", written into the rc, four plugins and six
  # generated blocks — so a rice that changed haus.fonts.mono.name got a
  # machine with two type families and no way to say otherwise, which is a
  # promise the option never made and a limit nothing wrote down.
  #
  # It is the MONO family on purpose: the bar draws Nerd Font icon glyphs
  # (nf-md-*) in the same runs as its labels, so it needs the same patched font
  # the terminal does, and `fonts.mono` is where a rice names one (with the
  # package, and the warning when the two disagree). Taken verbatim rather than
  # transformed — a "Nerd Font Mono" family name is what the option holds, and
  # deriving the propositional variant by trimming " Mono" would silently
  # invent a family for anything not following Nerd Font's naming (Berkeley
  # Mono → "Berkeley", which does not exist).
  barFont = config.haus.fonts.mono.name;

  bashArray = xs: lib.concatMapStringsSep " " (x: ''"${x}"'') xs;
  appWorkspaces = map (ws: ws.id) workspaces;
  iconFont =
    icon:
    if lib.hasPrefix ":" icon then
      "sketchybar-app-font:Regular:${sizes.appIcon}"
    else
      "${barFont}:Bold:${sizes.icon}";
  wsIconCases = lib.concatMapStrings (
    ws:
    lib.optionalString (ws.icon != null) (
      "    ${ws.id}) ICON=${lib.escapeShellArg ws.icon} ; IFONT=${lib.escapeShellArg (iconFont ws.icon)} ;;\n"
    )
  ) workspaces;
  # Leader-key -> workspace map for launch_mode.sh, same colon-joined shape it
  # used to hardcode. Digits 1-4 focus the numbered workspaces; each app key maps
  # to the workspace it belongs to (haus._appWorkspace, populated from
  # haus.workspaces.*.apps); no membership renders as "<key>:" (always
  # closed/grey).
  launchersStr = lib.concatStringsSep " " (
    [
      "1:1"
      "2:2"
      "3:3"
      "4:4"
    ]
    ++ map (
      a: "${a.key}:${lib.optionalString (appWorkspaceId a != null) (appWorkspaceId a)}"
    ) launchers
  );

  # Sourced by sketchybarrc: the workspace roster + a per-workspace icon lookup.
  # bash 3.2 (macOS /bin/bash) has no associative arrays, hence the case in a fn.
  workspacesSh = ''
    #!/bin/bash
    # GENERATED from haus._roster by modules/sill/default.nix — do not edit.
    WORKSPACES=(${
      bashArray (
        [
          "1"
          "2"
          "3"
          "4"
        ]
        ++ appWorkspaces
      )
    })
    # Leader picker bubbles: the digits 1-4 (focus a numbered workspace) plus one
    # per app key (jump to its workspace) — mirrors [mode.launch.binding].
    LAUNCHER_KEYS=(${
      bashArray (
        [
          "1"
          "2"
          "3"
          "4"
        ]
        ++ map (a: a.key) launchers
      )
    })
    # Leader hotkey -> assigned workspace, parsed by launch_mode.sh (bash 3.2 has
    # no associative arrays, so a plain space-separated "<key>:<ws>" string). An
    # empty <ws> means no assigned space (always shown closed/grey).
    LAUNCHERS="${launchersStr}"

    # ws_icon <workspace>: sets ICON + IFONT. Default is the workspace's own
    # letter in the bar's Nerd Font; app-workspaces override to their logo glyph.
    ws_icon() {
      ICON="$1"
      IFONT="${barFont}:Bold:${sizes.icon}"
      case "$1" in
    ${wsIconCases}  esac
    }
  '';

  # The hush pill — generic (no personal hardware/service), so unlike the
  # sill.items extras below it rides haus.hush.enable, not an opt-in
  # list. hush_change is fired by the hush engine after its own toggles and by
  # the hush-watcher agent (modules/hush) when the Focus DB changes; the
  # update_freq poll is only a backstop for missed events.
  hushBlock = ''
    sketchybar --add event hush_change
    sketchybar --add item hush right \
        --set hush \
            update_freq=30 \
            script="$HOME/.config/sketchybar/plugins/hush.sh" \
            background.color=$SURFACE0 \
            icon.padding_left=10 \
            icon.padding_right=10 \
            label.drawing=off \
        --subscribe hush mouse.clicked hush_change system_woke
  '';

  # The opt-in pills, emitted only for the ones haus.sill.items switches on.
  # They reference $SURFACE0 (from colors.sh) and $HOME, both live when
  # sketchybarrc sources this file.
  optionalPluginBlocks = {
    # Agent-pane status, for whichever client the pane runs (Claude Code, Codex,
    # Opencode). The refresh is push, not poll: agents-hook.sh invokes
    # agents.sh directly on every agent state change, so the pill updates even
    # while hidden (a drawing=off item's own update_freq never ticks, and custom
    # --trigger events are delivered inconsistently across --reload — neither can
    # revive a hidden pill). update_freq is only a while-visible backstop to reap
    # stale files. Starts hidden; agents.sh flips it on when a pane is live.
    # Popup styling mirrors the apple-logo menu.
    agents = ''
      sketchybar --add item agents right \
          --set agents \
              update_freq=10 \
              drawing=off \
              icon.padding_left=10 \
              icon.padding_right=4 \
              label.padding_right=10 \
              label.font="${barFont}:Bold:${sizes.label}" \
              popup.background.border_width=2 \
              popup.background.corner_radius=10 \
              popup.background.border_color=$SURFACE0 \
              popup.background.color=$MANTLE \
              ${popupAlign} \
              popup.horizontal=off \
              script="$HOME/.config/sketchybar/plugins/agents.sh" \
              click_script="$HOME/.config/sketchybar/plugins/agents.sh" \
          --subscribe agents mouse.clicked system_woke
    '';
    # AI rate-limit gauges (5-hour session + 7-day weekly) and API spend, one row
    # per reporting client. Two feed shapes, both ending in
    # ~/.cache/claude-statusline/usage-*.tsv:
    #   • pushed — modules/den/statusline.sh stashes the percentages Claude Code
    #     hands every statusline render, then invokes ai_usage.sh when one moves.
    #   • pulled — Codex (an account API call) and Opencode (a sqlite read) have
    #     no client-side writer, so claude-statusline-refresh --usage-only fetches
    #     them. The plugin kicks that itself on a TTL, which is what keeps this
    #     pill honest on a machine that never opens Claude at all.
    # update_freq is the while-visible backstop that rolls a window over to 0% at
    # its reset. Starts hidden until the first row lands.
    aiUsage = ''
      sketchybar --add item ai_usage right \
          --set ai_usage \
              update_freq=15 \
              drawing=off \
              icon.padding_left=10 \
              icon.padding_right=4 \
              label.padding_right=10 \
              label.font="${barFont}:Bold:${sizes.label}" \
              popup.background.border_width=2 \
              popup.background.corner_radius=10 \
              popup.background.border_color=$SURFACE0 \
              popup.background.color=$MANTLE \
              ${popupAlign} \
              popup.horizontal=off \
              script="$HOME/.config/sketchybar/plugins/ai_usage.sh" \
              click_script="$HOME/.config/sketchybar/plugins/ai_usage.sh" \
          --subscribe ai_usage mouse.clicked system_woke
      # One kick at bar start, backgrounded. The item is drawing=off until a first
      # row exists and a hidden item's update_freq never ticks — so on a machine
      # driving Codex or Opencode this is what pulls the first row and reveals the
      # pill at all. After that the plugin's own TTL keeps the feeds warm.
      ("$HOME/.config/sketchybar/plugins/ai_usage.sh" >/dev/null 2>&1 &)
    '';
    # System readouts. Each pill's colour comes from the --set here (the palette
    # vars are live via colors.sh, sourced by sketchybarrc before this file); the
    # plugin script only refreshes icon+label on its update_freq tick.
    cpu = ''
      sketchybar --add item cpu right \
          --set cpu \
              update_freq=5 \
              icon.color=$PEACH \
              background.color=$SURFACE0 \
              background.padding_left=8 \
              background.padding_right=8 \
              script="$HOME/.config/sketchybar/plugins/cpu.sh"
    '';
    memory = ''
      sketchybar --add item memory right \
          --set memory \
              update_freq=15 \
              icon.color=$GREEN \
              background.color=$SURFACE0 \
              background.padding_left=8 \
              background.padding_right=8 \
              script="$HOME/.config/sketchybar/plugins/memory.sh"
    '';
    volume = ''
      sketchybar --add item volume right \
          --set volume \
              update_freq=5 \
              icon.color=$SKY \
              background.color=$SURFACE0 \
              background.padding_left=8 \
              background.padding_right=8 \
              script="$HOME/.config/sketchybar/plugins/volume.sh" \
              click_script="open -a 'System Settings' 'x-apple.systempreferences:com.apple.Sound-Settings.extension'"
    '';
    # Next timed event + a click-popup of the next five. calendar.sh fills the
    # popup children (calendar.event.1..5) added below; the toggle uses the literal
    # item name so no $NAME has to survive add-time expansion.
    # Opening goes through sillpop (see popToggle above) so the dropdown closes on
    # the next click anywhere else, not only on a second click of the pill.
    calendar = ''
      sketchybar --add item calendar right \
          --set calendar \
              update_freq=60 \
              icon="󰃭" \
              icon.color=$MAUVE \
              background.color=$SURFACE0 \
              popup.background.border_width=2 \
              popup.background.corner_radius=10 \
              popup.background.border_color=$SURFACE0 \
              popup.background.color=$MANTLE \
              ${popupAlign} \
              script="$HOME/.config/sketchybar/plugins/calendar.sh" \
              click_script="${popToggle "calendar"}" \
          --subscribe calendar mouse.clicked system_woke
      for i in 1 2 3 4 5; do
          sketchybar --add item calendar.event.$i popup.calendar \
              --set calendar.event.$i \
                  icon.color=$MAUVE \
                  label.color=$TEXT \
                  icon.padding_left=10 \
                  label.padding_right=10 \
                  drawing=off
      done
    '';
    # Keep-awake controller. The rice-level `awake` CLI + launchd job own the
    # assertion; this popup only chooses a duration and renders state. A bar
    # reload therefore cannot accidentally release an active assertion.
    caffeinate = ''
      sketchybar --add event caffeinate_change
      sketchybar --add item caffeinate right \
          --set caffeinate \
              update_freq=30 \
              icon="󰅶" \
              icon.padding_left=10 \
              icon.padding_right=10 \
              label.padding_right=10 \
              label.font="${barFont}:Bold:${sizes.small}" \
              background.color=$SURFACE0 \
              popup.background.border_width=2 \
              popup.background.corner_radius=10 \
              popup.background.border_color=$SURFACE0 \
              popup.background.color=$MANTLE \
              ${popupAlign} \
              script="$HOME/.config/sketchybar/plugins/caffeinate.sh" \
          --subscribe caffeinate mouse.clicked caffeinate_change system_woke

      CAFFEINATE_POPUP=(
          icon.padding_left=10
          label.padding_right=10
          background.height=30
          background.padding_left=0
          background.padding_right=0
          background.color=0x00000000
          background.drawing=off
      )
      sketchybar --add item caffeinate.1h popup.caffeinate \
          --set caffeinate.1h "''${CAFFEINATE_POPUP[@]}" icon="1" label="1 hour" \
              click_script="/run/current-system/sw/bin/awake 1h >/dev/null; sketchybar --set caffeinate popup.drawing=off"
      sketchybar --add item caffeinate.2h popup.caffeinate \
          --set caffeinate.2h "''${CAFFEINATE_POPUP[@]}" icon="2" label="2 hours" \
              click_script="/run/current-system/sw/bin/awake 2h >/dev/null; sketchybar --set caffeinate popup.drawing=off"
      sketchybar --add item caffeinate.4h popup.caffeinate \
          --set caffeinate.4h "''${CAFFEINATE_POPUP[@]}" icon="4" label="4 hours" \
              click_script="/run/current-system/sw/bin/awake 4h >/dev/null; sketchybar --set caffeinate popup.drawing=off"
      sketchybar --add item caffeinate.8h popup.caffeinate \
          --set caffeinate.8h "''${CAFFEINATE_POPUP[@]}" icon="8" label="8 hours" \
              click_script="/run/current-system/sw/bin/awake 8h >/dev/null; sketchybar --set caffeinate popup.drawing=off"
      sketchybar --add item caffeinate.custom popup.caffeinate \
          --set caffeinate.custom "''${CAFFEINATE_POPUP[@]}" icon="󰅐" label="Custom hours…" \
              click_script="$HOME/.config/sketchybar/plugins/caffeinate.sh custom"
      sketchybar --add item caffeinate.indefinite popup.caffeinate \
          --set caffeinate.indefinite "''${CAFFEINATE_POPUP[@]}" icon="∞" label="Until stopped" \
              click_script="/run/current-system/sw/bin/awake indefinitely >/dev/null; sketchybar --set caffeinate popup.drawing=off"
      sketchybar --add item caffeinate.stop popup.caffeinate \
          --set caffeinate.stop "''${CAFFEINATE_POPUP[@]}" icon="󰅖" icon.color=$RED label="Allow sleep" \
              click_script="/run/current-system/sw/bin/awake off >/dev/null; sketchybar --set caffeinate popup.drawing=off"
    '';
    elgato = ''
      sketchybar --add item elgato right \
          --set elgato \
              update_freq=5 \
              script="$HOME/.config/sketchybar/plugins/elgato.sh" \
              background.color=$SURFACE0 \
              icon.padding_left=10 \
              icon.padding_right=10 \
              click_script="$HOME/.config/sketchybar/plugins/elgato.sh" \
          --subscribe elgato mouse.clicked
    '';
    harvest = ''
      sketchybar --add event harvest_update
      sketchybar --add item harvest right \
          --set harvest \
              update_freq=3 \
              script="$HOME/.config/sketchybar/plugins/harvest.sh" \
          --subscribe harvest mouse.clicked harvest_update system_woke
    '';
  };
  # The opt-in pills sit in an attrset (no inherent order), so emission follows
  # this fixed left-to-right order — only the ones sill.items switches on are drawn.
  extraOrder = [
    "agents"
    "aiUsage"
    "cpu"
    "memory"
    "volume"
    "calendar"
    "caffeinate"
    "elgato"
    "harvest"
  ];
  enabledExtras = lib.filter (
    name:
    if name == "aiUsage" then
      config.haus.sill.items.aiUsage || config.haus.sill.items.claudeUsage
    else
      config.haus.sill.items.${name}
  ) extraOrder;

  # The always-on core pills; a false in sill.items hides one.
  coreItems = [
    "clock"
    "weather"
    "media"
    "battery"
    "wifi"
  ];
  hiddenCore = lib.filter (name: !config.haus.sill.items.${name}) coreItems;

  optionalItemsSh = ''
    #!/bin/bash
    # GENERATED from haus.hush.enable + haus.sill.items by
    # modules/sill/default.nix — do not edit.
  ''
  + lib.optionalString config.haus.hush.enable hushBlock
  + lib.concatMapStrings (name: optionalPluginBlocks.${name}) enabledExtras;

  # Which core pills the user turned off (a false in haus.sill.items). Sourced
  # by sketchybarrc BEFORE the core `--add`s so each can guard on sill_hidden and
  # simply not create the item — cleaner than adding-then-hiding (media.sh flips
  # its own drawing on when a track plays, so a post-hoc drawing=off wouldn't
  # stick). bash 3.2 (macOS) has no associative arrays, hence the substring match.
  hiddenItemsSh = ''
    #!/bin/bash
    # GENERATED from haus.sill.items by modules/sill/default.nix — do not edit.
    SILL_HIDDEN="${lib.concatStringsSep " " hiddenCore}"
    sill_hidden() { case " $SILL_HIDDEN " in *" $1 "*) return 0 ;; *) return 1 ;; esac ; }
  '';

  # Bar position (haus.sill.position). Sourced by sketchybarrc — which sets
  # `position=$(bar_position)` on --bar — and, in auto mode, re-run by
  # plugins/position.sh on every display_change. bar_position() echoes the
  # position to hand sketchybar. In auto mode "docked" means any non-built-in
  # display is attached: system_profiler is the only guaranteed source of a
  # display's connection type, so it (not a bare display count) is what tells a
  # clamshell external apart from the built-in. It's slow (~1s) but
  # display_change fires rarely, so the cost is only paid on dock/undock/boot.
  positionSh = ''
    #!/bin/bash
    # GENERATED from haus.sill.position by modules/sill/default.nix — do not edit.
    SILL_POSITION_MODE="${config.haus.sill.position}"

    bar_position() {
      case "$SILL_POSITION_MODE" in
        top | bottom) echo "$SILL_POSITION_MODE" ;;
        auto)
          local info total internal
          info="$(system_profiler SPDisplaysDataType 2>/dev/null)"
          total="$(grep -c 'Resolution:' <<<"$info")"
          internal="$(grep -c 'Connection Type: Internal' <<<"$info")"
          if [ "$(( total - internal ))" -gt 0 ]; then echo bottom; else echo top; fi
          ;;
      esac
    }
  '';

  # The haus-tour pill (plugins/tour.sh) — the first-run tutor. It must live on
  # the RIGHT (launch mode replaces the LEFT side of the bar exactly when the
  # user is mid-step), but --move'd next to the clock at the far right: added
  # last it would land nearest the center, which a MacBook notch covers. It is
  # still sourced by sketchybarrc AFTER the other right-side items so `init`
  # sees them all — mid-tour it hides them (tour.sh mute) to make room.
  # Empty when the tour isn't wired. The built-in tour needs prowl because its
  # first three moves teach the leader; a custom tour can consist entirely of
  # other existing signals (for example Pounce), so it needs only Sill itself.
  # `init` repaints whatever state the last session left: mid-tour step, done
  # (hidden), or the dormant hint.
  customTourSteps = config.haus.tour.steps;
  customTour = customTourSteps != null;
  tourWired = config.haus.tour.enable && (customTour || config.haus.prowl.enable);
  tourItemSh = ''
    #!/bin/bash
    # GENERATED from haus.tour.* by modules/sill/default.nix — do not edit.
  ''
  + lib.optionalString tourWired ''
    sketchybar --add item tour right \
        --set tour \
            drawing=off \
            icon.padding_left=10 \
            icon.padding_right=4 \
            label.padding_right=10 \
            label.font="${barFont}:Bold:${sizes.small}" \
            background.color=$MANTLE \
            click_script="$HOME/.config/sketchybar/plugins/tour.sh click"
    sketchybar --move tour after clock
    "$HOME/.config/sketchybar/plugins/tour.sh" init
  '';
  # The resolved keymap (../lib/keys.nix). The tour's prompts must name the keys
  # THIS machine is bound to — a tutor telling you to tap Caps Lock on a rice where
  # keys.leader = "alt-space" teaches a chord that does nothing.
  k = import ../lib/keys.nix {
    inherit lib;
    keys = config.haus.keys;
  };

  # Placeholders an authored hint may use; tour.sh expands them at render time
  # from the same values the built-in lap interpolates (see `expand_keys`).
  knownPlaceholders = [
    "palette"
    "leader"
    "leaderName"
  ];
  badPlaceholders = lib.unique (
    lib.filter (name: !(builtins.elem name knownPlaceholders)) (
      lib.concatMap (
        step:
        map (m: builtins.elemAt m 0) (
          lib.filter builtins.isList (builtins.split "\\{([A-Za-z]+)\\}" step.hint)
        )
      ) (if customTour then customTourSteps else [ ])
    )
  );

  customStepCases =
    field:
    lib.concatStringsSep "\n" (
      lib.imap0 (
        index: step: "      ${toString (index + 1)}) printf '%s\\n' ${lib.escapeShellArg step.${field}} ;;"
      ) (if customTour then customTourSteps else [ ])
    );

  tourConfigSh = ''
        #!/bin/bash
        # GENERATED from haus.tour.steps + pounce.enable + keys.* by
        # modules/sill/default.nix — do not edit. TOUR_CUSTOM switches from the
        # built-in four-move lap to the authored list below. TOUR_HAS_PALETTE decides
        # whether the built-in lap has a step 4 (it needs pounce); the glyphs name the
        # leader and palette chords this rice actually binds.
        TOUR_CUSTOM=${if customTour then "1" else "0"}
        TOUR_CUSTOM_COUNT=${toString (if customTour then builtins.length customTourSteps else 0)}
        TOUR_HAS_PALETTE=${if config.haus.pounce.enable && k.palette != null then "1" else "0"}
        TOUR_LEADER=${lib.escapeShellArg (if k.leader != null then k.leader.glyph else "⇪")}
        TOUR_LEADER_NAME=${lib.escapeShellArg (if k.leader != null then k.leader.name else "Caps Lock")}
        TOUR_PALETTE=${lib.escapeShellArg (if k.palette != null then k.palette.glyph else "⌘ Space")}

        tour_custom_hint() {
          case "$1" in
    ${customStepCases "hint"}
            *) return 1 ;;
          esac
        }

        tour_custom_detect() {
          case "$1" in
    ${customStepCases "detect"}
            *) return 1 ;;
          esac
        }
  '';
in
lib.mkIf config.haus.sill.enable {
  warnings =
    lib.optional
      (
        customTour
        && !config.haus.prowl.enable
        && lib.any (
          step:
          builtins.elem step.detect [
            "launch"
            "workspace"
            "navigate"
            "resize"
          ]
        ) customTourSteps
      )
      "haus.tour.steps uses a prowl detector while haus.prowl.enable is false; that step can only be skipped."
    ++
      lib.optional
        (
          customTour
          && (!config.haus.pounce.enable || k.palette == null)
          && lib.any (step: step.detect == "palette") customTourSteps
        )
        "haus.tour.steps uses the palette detector while Pounce or its palette binding is disabled; that step can only be skipped."
    ++
      # A misspelled placeholder renders literally — `{palete}` sits in the bar
      # of whoever IMPORTED the rice, and the author, whose own hints they never
      # re-read, is the last person to find out. Same asymmetry as a pack's
      # leader key: check the thing the author can't see.
      lib.optional (customTour && badPlaceholders != [ ]) (
        "haus.tour.steps names unknown placeholders: "
        + lib.concatStringsSep ", " badPlaceholders
        + ". Known: {palette}, {leader}, {leaderName}; anything else renders as typed."
      );

  # SketchyBar (brew) + its tap. sketchybar-app-font renders the workspace pill
  # glyphs (an icon ligature font: `:ghostty:` → that app's logo).
  homebrew.taps = [ "FelixKratz/formulae" ];
  # Roster entries, not raw brews — a formula with no .app is still something the
  # machine has, and keeping it in the one list is what lets `haus` and the agent
  # skill answer "what's installed here?" completely. ical-buddy backs the opt-in
  # `calendar` pill (plugins/calendar.sh shells out to it); pulled in only when
  # that plugin is enabled so a default bar stays lean. If a host ALSO declares
  # ical-buddy, the two definitions merge on the shared id rather than
  # double-installing — which is the difference between a keyed roster and a list.
  haus.roster = {
    sketchybar.brew = lib.mkDefault "FelixKratz/formulae/sketchybar";
  }
  // lib.optionalAttrs config.haus.sill.items.calendar {
    ical-buddy.brew = lib.mkDefault "ical-buddy";
  };
  # sketchybar-app-font draws the workspace-pill logos, and nothing else does —
  # so this is the one font sill still installs for itself. Everything else in
  # the bar is drawn in `barFont`, i.e. haus.fonts.mono.name, whose package
  # den installs (and warns about when a rice names a family it wasn't given).
  #
  # The rule that keeps this honest is the one that put Hack here in the first
  # place: DECLARE WHAT WE NAME. The bar used to name "Hack Nerd Font" while
  # den shipped JetBrains Mono, so a fresh machine drew tofu across the whole
  # bar and only a hand-installed Hack hid it. The fix then was to install the
  # font we named; the fix now is to name the font we install.
  fonts.packages = [ pkgs.sketchybar-app-font ];

  # The dropdown dismisser the pills' click_scripts call by its
  # /run/current-system/sw/bin path. On PATH as well because it's the one honest
  # way to open a bar popup by hand (`sillpop toggle calendar`) — a raw
  # `popup.drawing=on` leaves a dropdown nothing will close.
  environment.systemPackages = [ sillpop ];

  launchd.user.agents.sketchybar = {
    serviceConfig = {
      ProgramArguments = withGUIWait "/opt/homebrew/opt/sketchybar/bin/sketchybar";
      KeepAlive = true;
      RunAtLoad = true;
      ProcessType = "Interactive";
      StandardOutPath = "/tmp/sketchybar.out.log";
      StandardErrorPath = "/tmp/sketchybar.err.log";
      EnvironmentVariables = {
        LANG = "en_US.UTF-8";
        PATH = userPath;
      };
    };
  };

  # SketchyBar is launched solely by the agent above — never by `brew services`.
  # If a stray `brew services` plist is left behind, that second instance grabs
  # the lock file and our agent silently fails to draw (symptom: empty menu bar,
  # "could not acquire lock-file … already running?" in the err log). Boot it out
  # and delete its plist on every rebuild. Idempotent no-op when clean.
  system.activationScripts.postActivation.text = ''
    uid=$(/usr/bin/id -u ${username})
    strayPlist="/Users/${username}/Library/LaunchAgents/homebrew.mxcl.sketchybar.plist"
    if [ -e "$strayPlist" ]; then
      echo "[activation] evicting stray homebrew.mxcl.sketchybar agent" >&2
      /bin/launchctl bootout "gui/$uid/homebrew.mxcl.sketchybar" 2>/dev/null || true
      rm -f "$strayPlist"
    fi
  '';

  home-manager.users.${username} =
    {
      lib,
      osConfig,
      nebelung,
      ...
    }:
    let
      # haus.theme.{flavor,contrast} select which rendered variant everything
      # below reads — ../lib/nebelung.nix owns that resolution for hearth, sill and
      # theme alike, so the flavor axis landed in one place rather than three.
      #
      # The bar needs only the palette, never a rendered file: every colour it
      # draws comes from the generated colors.sh below, so light mode reaches the
      # bar with no path change at all. (The previous `nebelungRoot` binding here
      # was never used — dropped rather than extended.)
      nebelungPalette =
        (import ../lib/nebelung.nix {
          inherit lib nebelung;
          theme = osConfig.haus.theme;
        }).palette;
      # Type sizes, resolved from haus.ui.scale against the menu bar's own
      # ceiling (see ../lib/bar.nix). Sourced by sketchybarrc and by the plugins
      # that set a font, exactly like colors.sh — so the bar's sizes are
      # single-sourced the same way its colours are, and neither the rc nor a
      # plugin carries a tuned number of its own.
      sizesSh = ''
        #!/bin/bash
        # GENERATED from haus.ui.scale by modules/sill/default.nix — do not
        # edit by hand.
        #
        # The bar's HEIGHT never scales: 36pt of bar with 28pt pills is what keeps
        # the pills inside the 32pt menu-bar band the hidden bar's hover-reveal
        # covers. Only the type inside the pills follows ui.scale, and only up to
        # the largest that still fits one. See modules/lib/bar.nix.
        SILL_SCALE="${toString bar.typeScale}"
        # The family every pill draws in, from haus.fonts.mono.name — the
        # same one Ghostty uses. Here rather than in the rc for the reason the
        # sizes are: the rc and four plugins all name it, and a font written in
        # five places is a font that ends up being two.
        BAR_FONT="${barFont}"
        FS_ICON="${sizes.icon}"
        FS_LABEL="${sizes.label}"
        FS_SMALL="${sizes.small}"
        FS_TINY="${sizes.tiny}"
        FS_APP_ICON="${sizes.appIcon}"
      '';

      # The Nebelung palette (name -> "#rrggbb") rendered as sketchybar's
      # 0xAARRGGBB colour literals, fully opaque. Generated so the palette stays
      # single-sourced from the nebelung input — sketchybarrc and every plugin
      # `source` this instead of hardcoding Catppuccin hexes. Var names are the
      # UPPER-cased palette keys (BASE, SURFACE0, MAUVE, …).
      colorsSh = ''
        #!/bin/bash
        # GENERATED from the `nebelung` flake input (nebelungPalette). Do not edit
        # by hand — change colours in ~/code/workshop/nebelung and rebuild.
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            name: hex: "export ${lib.toUpper name}=0xff${lib.removePrefix "#" hex}"
          ) nebelungPalette
        )}
      '';
    in
    {
      home.file = {
        ".config/sketchybar/colors.sh".text = colorsSh;
        ".config/sketchybar/sizes.sh".text = sizesSh;
        ".config/sketchybar/workspaces.sh".text = workspacesSh;
        ".config/sketchybar/optional_items.sh".text = optionalItemsSh;
        ".config/sketchybar/hidden_items.sh".text = hiddenItemsSh;
        ".config/sketchybar/position.sh".text = positionSh;
        ".config/sketchybar/tour_item.sh".text = tourItemSh;
        ".config/sketchybar/tour_config.sh".text = tourConfigSh;
        ".config/sketchybar/battery_config.sh".text = ''
          #!/bin/bash
          # GENERATED from haus.sill.battery.* by modules/sill/default.nix — do not edit.
          SILL_BATTERY_HIDE_OVER="${
            if config.haus.sill.battery.hideOver != null then
              toString config.haus.sill.battery.hideOver
            else
              ""
          }"
        '';
        ".config/sketchybar/clock_config.sh".text = ''
          #!/bin/bash
          # GENERATED from haus.sill.clock.* by modules/sill/default.nix — do not edit.
          SILL_CLOCK_MODE="${config.haus.sill.clock.mode}"
        '';
        # Empty by default: plugins/elgato.sh then discovers the light over
        # mDNS rather than the rice shipping somebody's device hostname.
        ".config/sketchybar/elgato_config.sh".text = ''
          #!/bin/bash
          # GENERATED from haus.sill.elgato.* by modules/sill/default.nix — do not edit.
          SILL_ELGATO_HOST="${config.haus.sill.elgato.host}"
        '';
        ".config/sketchybar/ai_usage_config.sh".text = ''
          #!/bin/bash
          # GENERATED from haus.sill.aiUsage.* by modules/sill/default.nix — do not edit.
          SILL_AI_USAGE_PROVIDER="${config.haus.sill.aiUsage.provider}"
        '';
        ".config/sketchybar/sketchybarrc".source = ./sketchybar/sketchybarrc;
        # The far-left logo pill's image: the nebelhaus ears (the two cat-ear
        # shapes of the org mark, extracted from web/logos/nebelhaus-mark and
        # tinted PINK). Drawn as apple.logo's background.image in sketchybarrc.
        ".config/sketchybar/nebelhaus-ears.png".source = ./sketchybar/nebelhaus-ears.png;
        ".config/sketchybar/aerospace-notify.sh".source = ./sketchybar/aerospace-notify.sh;
        ".config/sketchybar/plugins".source = ./sketchybar/plugins;
      };
    };
}

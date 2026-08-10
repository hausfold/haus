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
#
# haus.sill.bottom.enable adds a SECOND bar along the bottom of the screen,
# running at the same time as this one, with the extras named in
# haus.sill.bottom.items moved down onto it. Down there each pill also names its
# GROUP — left, center or right, SketchyBar's own three regions — because that
# bar has no workspace pills, no front-app slot and no notch competing for the
# other two; up here every movable pill is on the right and always was. It is a
# second launchd agent running the same binary under a second name — see
# `sillBottom` below for why there is no other way, and `barSh` for how a shared
# plugin knows which of the two it is talking to.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  guiWait = import ../lib/gui-wait.nix;
  withGUIWait = guiWait.wrap;
  userPath = "/run/current-system/sw/bin:/etc/profiles/per-user/${username}/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin";

  cfg = config.haus.sill;

  sillpop = pkgs.callPackage ./sillpop.nix { };

  # ---- the second bar, and why it is a symlink -------------------------------
  # SketchyBar has no two-bars-in-one-process mode. An instance names itself
  # after `basename(argv[0])` (src/sketchybar.c) and keys BOTH its lock file
  # (/tmp/<name>_<user>.lock) and its mach service (git.felix.<name>) on that
  # name — so two bars means the SAME binary invoked under two names, and the
  # name has to reach it through argv[0]. There is no flag and no environment
  # variable for it: BAR_NAME is EXPORTED to plugins, never read, so setting it
  # on the way in does nothing at all.
  #
  # Hence a symlink rather than a wrapper script: `exec -a` would work too, but a
  # link is the whole mechanism in one line, and it is what the client half needs
  # anyway. `sill-bottom --set cpu label=…` addresses the bottom bar exactly the
  # way `sketchybar --set` addresses the top one — same binary, second name,
  # second mach service — which is why this lands on PATH and not just in the
  # launchd agent. It dangles at build time (Homebrew's prefix isn't in the
  # sandbox) and resolves at run time, same as the agent's own ProgramArguments.
  sillBottom = pkgs.runCommand "sill-bottom" { } ''
    mkdir -p "$out/bin"
    ln -s /opt/homebrew/opt/sketchybar/bin/sketchybar "$out/bin/sill-bottom"
  '';

  # How each bar is addressed from a config file or a plugin. BOTH are absolute:
  # a misdirected --set is silent (it targets the other bar's instance and says
  # nothing), so neither is left to whatever `sketchybar` a PATH happens to
  # resolve — and sillpop takes the same string as its SKETCHYBAR_BIN, which has
  # to be a path it can stat. The plugins have always spelled the top one out
  # this way; this is the generated blocks catching up.
  barTopPath = "/opt/homebrew/bin/sketchybar";
  barBottomPath = "/run/current-system/sw/bin/sill-bottom";

  # What feeds the media pill now that SketchyBar's own media_change event is
  # dead on macOS 15.4+. Reached by absolute store path from media_config.sh
  # rather than put on PATH, and only when the pill is actually on, so a rice
  # with `sill.items.media = false` doesn't carry it in its closure.
  mediaControl = pkgs.callPackage ./media-control.nix { };

  # What a pill with a dropdown uses instead of a bare `popup.drawing=toggle`, so
  # the dropdown also closes on a click anywhere else — sketchybar alone only ever
  # sees clicks on its own items (see sillpop.swift).
  #
  # The toggle stays FIRST and unchanged, so opening a dropdown costs exactly what
  # it always did; the guard is armed after it, backgrounded, and nothing waits on
  # it. That ordering is the whole latency story — armed inline, it added ~200 ms
  # to every open. `&` also means no fallback is needed: if the binary is missing
  # the popup has already opened, and only the dismissal is lost.
  #
  # SKETCHYBAR_BIN is how sillpop is told WHICH bar's popup it is guarding: it
  # resolves its own client from that variable first (sillpop.swift), and unset
  # it queries the top bar — so on a pill moved to the bottom bar it would find
  # no such item and exit before arming, leaving a dropdown that only a second
  # click on the pill can close. Which is the whole thing sillpop exists to fix.
  # `sb` is an absolute path on both bars precisely so it can serve as both.
  popToggle =
    sb: item:
    "${sb} --set ${item} popup.drawing=toggle; SKETCHYBAR_BIN=${sb} /run/current-system/sw/bin/sillpop arm ${item} 2>/dev/null &";

  # Every dropdown carries this, aligned to the GROUP its pill sits in.
  # SketchyBar's popup.align defaults to `left`, i.e. the popup's left edge is
  # pinned to the pill's left edge and the rows grow rightward — fine under the
  # apple menu at the far left, but on the right half of the bar a wide row (an
  # agent's repo/branch, a usage gauge) runs straight off the screen edge.
  # `right` pins the popup's RIGHT edge to the pill instead, so it opens
  # leftward, into the bar; `center` grows both ways from the pill's middle.
  #
  # Taking the side as an argument is what keeps that true on the bottom bar's
  # left and center groups: a pill moved there would otherwise still carry
  # `align=right` and open away from the screen edge it is now nowhere near.
  # The hand-written left-side items in sketchybarrc (apple.logo) never come
  # through here and keep the default.
  popupAlign = side: "popup.align=${side}";

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
    ++ map (a: "${a.key}:${lib.optionalString (appWorkspaceId a != null) (appWorkspaceId a)}") launchers
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
  hushBlock = sb: side: ''
    ${sb} --add event hush_change
    ${sb} --add item hush ${side} \
        --set hush \
            update_freq=30 \
            script="$HOME/.config/sketchybar/plugins/hush.sh" \
            background.color=$SURFACE0 \
            icon.padding_left=10 \
            icon.padding_right=10 \
            label.drawing=off \
        --subscribe hush mouse.clicked hush_change system_woke
  '';

  # Every movable pill, emitted only for the bar that owns it. The definitions
  # live once and take TWO arguments: the target bar client, and the group the
  # pill is being added to (`left`, `center` or `right` — SketchyBar's own three
  # regions). Nix renders the selected blocks into the top and bottom item
  # files. The menu bar always passes `right`, because its left and center are
  # spoken for; the bottom bar passes whatever haus.sill.bottom.items said. They
  # reference $SURFACE0 (from colors.sh) and $HOME, both live when either rc
  # sources its generated item file.
  mkPluginBlocks = sb: side: {
    hush = hushBlock sb side;
    clock = ''
      ${sb} --add item clock ${side} \
          --set clock \
              update_freq=10 \
              icon= \
              icon.color=$PINK \
              background.color=$MANTLE \
              background.padding_left=8 \
              background.padding_right=8 \
              script="$HOME/.config/sketchybar/plugins/clock.sh" \
              click_script="open -a 'Notion Calendar'"
    '';
    # Right-click opens Weather; left-click goes through popToggle so sillpop
    # guards the popup on the same bar instance that owns the pill.
    weather = ''
      ${sb} --add item weather ${side} \
          --set weather \
              update_freq=600 \
              icon="󰖐" \
              icon.color=$SKY \
              background.color=$SURFACE0 \
              popup.background.border_width=2 \
              popup.background.corner_radius=10 \
              popup.background.border_color=$SURFACE0 \
              popup.background.color=$MANTLE \
              ${popupAlign side} \
              script="$HOME/.config/sketchybar/plugins/weather.sh" \
              click_script="if [ \"\$BUTTON\" = \"right\" ]; then open -a Weather; else ${popToggle sb "weather"} fi" \
          --subscribe weather system_woke mouse.clicked

      WEATHER_POPUP_ITEM=(
          icon.padding_left=10
          label.padding_right=10
          background.height=30
          background.padding_left=0
          background.padding_right=0
          background.color=0x00000000
          background.drawing=off
          icon.font="${barFont}:Bold:${sizes.appIcon}"
          label.font="${barFont}:Regular:${sizes.label}"
      )

      ${sb} --add item weather.location popup.weather \
          --set weather.location "''${WEATHER_POPUP_ITEM[@]}" \
              icon.color=$BLUE label.color=$TEXT
      ${sb} --add item weather.condition popup.weather \
          --set weather.condition "''${WEATHER_POPUP_ITEM[@]}" \
              icon.color=$SKY label.color=$SUBTEXT0
      ${sb} --add item weather.temp popup.weather \
          --set weather.temp "''${WEATHER_POPUP_ITEM[@]}" \
              icon.color=$PEACH label.color=$TEXT
      ${sb} --add item weather.highlow popup.weather \
          --set weather.highlow "''${WEATHER_POPUP_ITEM[@]}" \
              icon.color=$RED label.color=$SUBTEXT0
      ${sb} --add item weather.sun popup.weather \
          --set weather.sun "''${WEATHER_POPUP_ITEM[@]}" \
              icon.color=$YELLOW label.color=$TEXT
      ${sb} --add item weather.wind popup.weather \
          --set weather.wind "''${WEATHER_POPUP_ITEM[@]}" \
              icon.color=$TEAL label.color=$TEXT
      ${sb} --add item weather.humidity popup.weather \
          --set weather.humidity "''${WEATHER_POPUP_ITEM[@]}" \
              icon.color=$SAPPHIRE label.color=$TEXT
      ${sb} --add item weather.uv popup.weather \
          --set weather.uv "''${WEATHER_POPUP_ITEM[@]}" \
              icon.color=$YELLOW label.color=$TEXT
      ${sb} --add item weather.precip popup.weather \
          --set weather.precip "''${WEATHER_POPUP_ITEM[@]}" \
              icon.color=$BLUE label.color=$TEXT

      for i in 0 1 2 3; do
          ${sb} --add item weather.hour.$i popup.weather \
              --set weather.hour.$i "''${WEATHER_POPUP_ITEM[@]}" \
                  icon.color=$LAVENDER label.color=$SUBTEXT0
      done
      for i in 1 2 3; do
          ${sb} --add item weather.forecast.$i popup.weather \
              --set weather.forecast.$i "''${WEATHER_POPUP_ITEM[@]}" \
                  icon.color=$MAUVE label.color=$TEXT
      done
    '';
    # SketchyBar's media_change event is dead on macOS 15.4+, so a detached
    # media-control stream owns repainting. updates=on lets a hidden media pill
    # keep running its watchdog tick and recover a dead stream — and the tick is
    # also what advances a long-form countdown, which no payload announces (see
    # plugins/media.sh), hence 30s rather than the old 60.
    #
    # scroll_texts is deliberately NOT set on here any more: the streamer turns
    # the marquee on for a few seconds after a track changes and settles it
    # again, so a long title stops scrolling forever in the corner of your eye.
    # Hovering brings it back, which is what mouse.entered/exited are for.
    media = ''
      ${sb} --add item media ${side} \
          --set media \
              icon= \
              icon.color=$PINK \
              updates=on \
              update_freq=30 \
              background.color=$SURFACE0 \
              background.padding_left=8 \
              background.padding_right=8 \
              label.max_chars=25 \
              drawing=off \
              popup.background.border_width=2 \
              popup.background.corner_radius=10 \
              popup.background.border_color=$SURFACE0 \
              popup.background.color=$MANTLE \
              ${popupAlign side} \
              popup.horizontal=off \
              script="$HOME/.config/sketchybar/plugins/media.sh" \
              click_script="$HOME/.config/sketchybar/plugins/media.sh click" \
          --subscribe media mouse.clicked mouse.entered mouse.exited mouse.exited.global mouse.scrolled system_woke
      # Exec'd rather than sourced, with its output on /dev/null — so
      # media_stream.sh has to carry the +x bit in git (home.file copies the
      # source mode verbatim). Without it both this launch and media.sh's
      # watchdog restart fail silently and the pill simply never lights up.
      # media_art.sh is launched the same way, from the streamer, and needs it
      # for the same reason; media_lib.sh is sourced, so it stays 644.
      ("$HOME/.config/sketchybar/plugins/media_stream.sh" >/dev/null 2>&1 &)
    '';
    # updates=on is load-bearing: battery.sh hides the pill over the configured
    # threshold, and a when_shown item could never notice charge later dropped.
    battery = ''
      ${sb} --add item battery ${side} \
          --set battery \
              icon.color=$GREEN \
              update_freq=30 \
              updates=on \
              background.color=$SURFACE0 \
              script="$HOME/.config/sketchybar/plugins/battery.sh" \
              click_script="open -a 'System Settings' 'x-apple.systempreferences:com.apple.preference.battery'" \
          --subscribe battery system_woke power_source_change
    '';
    wifi = ''
      ${sb} --add item wifi ${side} \
          --set wifi \
              icon=󰖩 \
              label.drawing=off \
              icon.color=$TEAL \
              background.color=$SURFACE0 \
              icon.padding_left=10 \
              icon.padding_right=10 \
              script="$HOME/.config/sketchybar/plugins/wifi.sh" \
              click_script="open -a 'System Settings' 'x-apple.systempreferences:com.apple.wifi-settings-extension'" \
              update_freq=10
    '';
    # Agent-pane status, for whichever client the pane runs (Claude Code, Codex,
    # Opencode). The refresh is push, not poll: agents-hook.sh invokes
    # agents.sh directly on every agent state change, so the pill updates even
    # while hidden (a drawing=off item's own update_freq never ticks, and custom
    # --trigger events are delivered inconsistently across --reload — neither can
    # revive a hidden pill). update_freq is only a while-visible backstop to reap
    # stale files. Starts hidden; agents.sh flips it on when a pane is live.
    # Popup styling mirrors the apple-logo menu.
    agents = ''
      ${sb} --add item agents ${side} \
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
              ${popupAlign side} \
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
      ${sb} --add item ai_usage ${side} \
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
              ${popupAlign side} \
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
      ${sb} --add item cpu ${side} \
          --set cpu \
              update_freq=5 \
              icon.color=$PEACH \
              background.color=$SURFACE0 \
              background.padding_left=8 \
              background.padding_right=8 \
              script="$HOME/.config/sketchybar/plugins/cpu.sh"
    '';
    memory = ''
      ${sb} --add item memory ${side} \
          --set memory \
              update_freq=15 \
              icon.color=$GREEN \
              background.color=$SURFACE0 \
              background.padding_left=8 \
              background.padding_right=8 \
              script="$HOME/.config/sketchybar/plugins/memory.sh"
    '';
    volume = ''
      ${sb} --add item volume ${side} \
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
      ${sb} --add item calendar ${side} \
          --set calendar \
              update_freq=60 \
              icon="󰃭" \
              icon.color=$MAUVE \
              background.color=$SURFACE0 \
              popup.background.border_width=2 \
              popup.background.corner_radius=10 \
              popup.background.border_color=$SURFACE0 \
              popup.background.color=$MANTLE \
              ${popupAlign side} \
              script="$HOME/.config/sketchybar/plugins/calendar.sh" \
              click_script="${popToggle sb "calendar"}" \
          --subscribe calendar mouse.clicked system_woke
      for i in 1 2 3 4 5; do
          ${sb} --add item calendar.event.$i popup.calendar \
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
      ${sb} --add event caffeinate_change
      ${sb} --add item caffeinate ${side} \
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
              ${popupAlign side} \
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
      ${sb} --add item caffeinate.1h popup.caffeinate \
          --set caffeinate.1h "''${CAFFEINATE_POPUP[@]}" icon="1" label="1 hour" \
              click_script="/run/current-system/sw/bin/awake 1h >/dev/null; ${sb} --set caffeinate popup.drawing=off"
      ${sb} --add item caffeinate.2h popup.caffeinate \
          --set caffeinate.2h "''${CAFFEINATE_POPUP[@]}" icon="2" label="2 hours" \
              click_script="/run/current-system/sw/bin/awake 2h >/dev/null; ${sb} --set caffeinate popup.drawing=off"
      ${sb} --add item caffeinate.4h popup.caffeinate \
          --set caffeinate.4h "''${CAFFEINATE_POPUP[@]}" icon="4" label="4 hours" \
              click_script="/run/current-system/sw/bin/awake 4h >/dev/null; ${sb} --set caffeinate popup.drawing=off"
      ${sb} --add item caffeinate.8h popup.caffeinate \
          --set caffeinate.8h "''${CAFFEINATE_POPUP[@]}" icon="8" label="8 hours" \
              click_script="/run/current-system/sw/bin/awake 8h >/dev/null; ${sb} --set caffeinate popup.drawing=off"
      ${sb} --add item caffeinate.custom popup.caffeinate \
          --set caffeinate.custom "''${CAFFEINATE_POPUP[@]}" icon="󰅐" label="Custom hours…" \
              click_script="$HOME/.config/sketchybar/plugins/caffeinate.sh custom"
      ${sb} --add item caffeinate.indefinite popup.caffeinate \
          --set caffeinate.indefinite "''${CAFFEINATE_POPUP[@]}" icon="∞" label="Until stopped" \
              click_script="/run/current-system/sw/bin/awake indefinitely >/dev/null; ${sb} --set caffeinate popup.drawing=off"
      ${sb} --add item caffeinate.stop popup.caffeinate \
          --set caffeinate.stop "''${CAFFEINATE_POPUP[@]}" icon="󰅖" icon.color=$RED label="Allow sleep" \
              click_script="/run/current-system/sw/bin/awake off >/dev/null; ${sb} --set caffeinate popup.drawing=off"
    '';
    elgato = ''
      ${sb} --add item elgato ${side} \
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
      ${sb} --add event harvest_update
      ${sb} --add item harvest ${side} \
          --set harvest \
              update_freq=3 \
              script="$HOME/.config/sketchybar/plugins/harvest.sh" \
          --subscribe harvest mouse.clicked harvest_update system_woke
    '';
  };
  # Item blocks sit in an attrset (no inherent order), so emission follows these
  # fixed left-to-right orders — only the ones each bar owns are drawn.
  coreOrder = [
    "clock"
    "weather"
    "media"
    "battery"
    "wifi"
  ];
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
  itemOrder = coreOrder ++ [ "hush" ] ++ extraOrder;

  # Is this pill switched on in the MENU BAR's table? Kept bool-only on purpose:
  # the top bar has exactly one group to offer, and `claudeUsage` — the
  # deprecated alias, which only this table carries — is honoured here, in one
  # place. The bottom table is read through `bottomSideOf` instead, because its
  # values answer a second question.
  wantsItem =
    items: name:
    if name == "aiUsage" then
      (items.aiUsage or false) || (items.claudeUsage or false)
    else
      items.${name} or false;

  # ---- the second bar's three groups -----------------------------------------
  # Which group of the bottom bar a pill was asked for, or null for "not on this
  # bar at all". `haus.sill.bottom.items.<pill>` is a side name, or a bool: the
  # option shipped bool-only, so `true` still has to mean the right group, which
  # is where every pill landed then.
  bottomSides = import ./sides.nix;
  bottomSideOf =
    name:
    let
      v = cfg.bottom.items.${name} or false;
    in
    if lib.isString v then
      v
    else if v then
      "right"
    else
      null;

  # The pills each group claims, in the same fixed order everywhere. SketchyBar
  # packs a group outward from its own edge, so `right` still reads outside-in
  # (clock furthest right, exactly as on the menu bar) while `left` fills
  # rightward from the left edge — the two are mirrors of one list, not two
  # lists.
  bottomGroup =
    side:
    lib.optionals cfg.bottom.enable (
      lib.filter (
        name: bottomSideOf name == side && (name != "hush" || config.haus.hush.enable)
      ) itemOrder
    );

  # Every pill on the SECOND bar, whichever group it sits in, and then the ones
  # left for the menu bar. A pill MOVES rather than duplicating: the bottom table
  # wins outright, so there is one switch per pill per bar and never two live
  # copies of a readout racing each other's update_freq. This flattened list is
  # what the "is it down there?" questions read — the top bar's exclusion, the
  # bar.sh routing table, the media/calendar closure — none of which care about
  # the group.
  bottomItems = lib.concatMap bottomGroup bottomSides;
  topCore = lib.filter (
    name: wantsItem cfg.items name && !(builtins.elem name bottomItems)
  ) coreOrder;
  topExtras = lib.filter (
    name: wantsItem cfg.items name && !(builtins.elem name bottomItems)
  ) extraOrder;
  topHush = config.haus.hush.enable && !(builtins.elem "hush" bottomItems);
  topItems = topCore ++ lib.optional topHush "hush" ++ topExtras;

  # nix name -> the item name SketchyBar knows it by. Identity for all but the
  # camel-cased one, and the plugins' own $NAME is the sketchybar side — so this
  # is what the routing list in bar.sh has to be written in.
  itemId = name: if name == "aiUsage" then "ai_usage" else name;

  topItemsSh = ''
    #!/bin/bash
    # GENERATED from haus.hush.enable + haus.sill.items by
    # modules/sill/default.nix — do not edit.
  ''
  + lib.concatMapStrings (name: (mkPluginBlocks barTopPath "right").${name}) topCore
  + lib.optionalString topHush (hushBlock barTopPath "right")
  + lib.concatMapStrings (name: (mkPluginBlocks barTopPath "right").${name}) topExtras;

  # The same blocks again, emitted against the OTHER bar and grouped by side.
  # $SB is set by bar.sh, which sill-bottomrc sources before this file — an
  # absolute path to the `sill-bottom` symlink, so both the `--add`s here and
  # every click_script string they carry address the bottom instance. Emitting
  # `sketchybar` down here would silently build the whole strip on the top bar
  # instead.
  bottomItemsSh = ''
    #!/bin/bash
    # GENERATED from haus.sill.bottom.items by modules/sill/default.nix — do not
    # edit. One `# --- <side>` run per group, in left/center/right order.
  ''
  + lib.concatMapStrings (
    side:
    let
      names = bottomGroup side;
    in
    lib.optionalString (names != [ ]) (
      "\n# --- ${side} ---\n" + lib.concatMapStrings (name: (mkPluginBlocks "$SB" side).${name}) names
    )
  ) bottomSides;

  # Which bar a plugin should talk to. Sourced by every plugin that can end up on
  # either one, and the answer is nearly always $BAR_NAME: SketchyBar exports it
  # into every script and click_script it runs, so a pill's own update knows the
  # instance that asked for it without anything being generated at all.
  #
  # The list is the fallback for the OTHER caller — a plugin invoked by a HOOK
  # rather than by a bar (agents-hook.sh on an agent state change, the
  # statusline's ai_usage push). Those have no bar, hence no $BAR_NAME, so they
  # fall back to the item they are updating: $NAME when the caller set one, else
  # the SILL_ITEM the plugin declares about itself.
  barSh = ''
    #!/bin/bash
    # GENERATED from haus.sill.bottom.items by modules/sill/default.nix — do not
    # edit. Sets $SB to the SketchyBar instance this invocation belongs to.
    SILL_BAR_TOP="${barTopPath}"
    SILL_BAR_BOTTOM="${barBottomPath}"
    SILL_BOTTOM_ITEMS="${lib.concatMapStringsSep " " itemId bottomItems}"

    case "''${BAR_NAME:-}" in
      sill-bottom) SB="$SILL_BAR_BOTTOM" ;;
      ?*) SB="$SILL_BAR_TOP" ;;
      *)
        SB="$SILL_BAR_TOP"
        sill_item="''${SILL_ITEM:-''${NAME:-}}"
        if [ -n "$sill_item" ]; then
          case " $SILL_BOTTOM_ITEMS " in
            *" $sill_item "*) SB="$SILL_BAR_BOTTOM" ;;
          esac
        fi
        ;;
    esac
  '';

  # Bar position (haus.sill.position). Sourced by sketchybarrc — which sets
  # `position=` / `topmost=` on --bar from these two — and, in auto mode, re-run
  # by plugins/position.sh on every display_change. bar_position() echoes the
  # position to hand sketchybar. In auto mode "docked" means any non-built-in
  # display is attached: system_profiler is the only guaranteed source of a
  # display's connection type, so it (not a bare display count) is what tells a
  # clamshell external apart from the built-in. It's slow (~1s) but
  # display_change fires rarely, so the cost is only paid on dock/undock/boot.
  #
  # bar_topmost() answers from SILL_POSITION_MODE alone and so costs nothing —
  # only the fixed `bottom` mode is lifted, for the reasons in its own comment.
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

    # Which window level the bar draws at. Keyed on the MODE, not on the
    # resolved position — see the `auto` carve-out below — so the answer is
    # fixed for the life of the process and plugins/position.sh never re-sends
    # it (bar_manager_set_topmost has no unchanged-guard: it calls
    # bar_manager_reset() every time, tearing down and rebuilding every bar and
    # item window, where re-sending the same `position=` is a real no-op).
    #
    # SketchyBar draws at kCGBackstopMenuLevel (-20), BELOW normal windows. At
    # the top that costs nothing: macOS reserves the menu-bar strip, so nothing
    # tiles into it and nothing is there to shadow it. (Fullscreen is not the
    # reason to stay low — a bar leaves a fullscreen space by space TYPE, not by
    # level: SLSSpaceGetType == 4, with show_in_fullscreen off.)
    #
    # At the bottom macOS reserves nothing, so prowl carves the room out of its
    # own outer-bottom gap — and the tiled window directly above then drops its
    # macOS shadow straight down into that gap. At -20 the shadow composites
    # OVER the bar, darkening the strip and making it read as recessed. Not a
    # transparency problem: an opaque `color=` is painted over just the same.
    # `topmost=window` (kCGFloatingWindowLevel, 3) lifts the bar above the
    # window — and so above its shadow — with the floating-pill look intact.
    #
    # `auto` deliberately does NOT get the lift, even though it resolves to
    # `bottom` while docked. Lifting is only safe where the room underneath is
    # actually reserved, and in auto mode it isn't: prowl's outerBottom is
    # `monLine (gap 10) (barGap 40)` (modules/prowl/default.nix), because
    # AeroSpace gaps can't flip per dock-state and the built-in has to keep a
    # bottom gap sized for the undocked case, when the bar is up at the top.
    # Docked with the lid open the bar draws along the BOTTOM of both displays,
    # so on the built-in it already overlaps the tiled windows — prowl's comment
    # calls that out. Today the window covers the bar there; at level 3 the bar
    # would cover the bottom ~26pt of every window on the laptop screen instead,
    # which is a good deal worse than a shadow. Fixed `position = "bottom"`
    # reserves barGap 40 on both displays and is safe, as is the dedicated
    # second bar (haus.sill.bottom.enable), which reserves it unconditionally.
    bar_topmost() {
      case "$SILL_POSITION_MODE" in
        bottom) echo window ;;
        *) echo off ;;
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
  topRightItems = topItems;
  tourAnchor = if topRightItems == [ ] then null else itemId (builtins.head topRightItems);
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
    ${lib.optionalString (tourAnchor != null) "sketchybar --move tour after ${tourAnchor}"}
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
      )
    ++
      # A bar with nothing on it still costs a launchd job and, via prowl, a
      # 40pt strip of every display — and it draws no pill to explain either.
      lib.optional (cfg.bottom.enable && bottomItems == [ ]) (
        "haus.sill.bottom.enable is on with no haus.sill.bottom.items — the second bar draws an empty strip and still reserves room at the bottom of every display."
      )
    ++
      # Both bars on the same edge overlap: SketchyBar pins each instance to the
      # edge it was told, and neither knows the other is there.
      lib.optional (cfg.bottom.enable && cfg.position != "top") (
        "haus.sill.bottom.enable is on while haus.sill.position = \"${cfg.position}\"; the two bars share the bottom edge and will draw on top of each other (position = \"auto\" only when an external display is attached)."
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
  #
  # Keyed off "is the pill drawn ANYWHERE", not off sill.items: the documented
  # way to put the pill on the bottom bar is `sill.bottom.items.calendar = true`
  # with `sill.items.calendar` left at its default false, and reading only the
  # top table there would draw the pill with no icalBuddy behind it — which
  # calendar.sh reports as a permanent, silent "No events".
  haus.roster = {
    sketchybar.brew = lib.mkDefault "FelixKratz/formulae/sketchybar";
  }
  // lib.optionalAttrs (builtins.elem "calendar" (topItems ++ bottomItems)) {
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
  # sillpop, plus — when the second bar is on — the `sill-bottom` name that IS
  # that bar. On PATH for the same reason `sketchybar` is: it's the CLI half,
  # the only way to poke the bottom bar by hand or from a script.
  environment.systemPackages = [ sillpop ] ++ lib.optional cfg.bottom.enable sillBottom;

  launchd.user.agents = {
    sketchybar = {
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
  }
  // lib.optionalAttrs cfg.bottom.enable {
    # The second bar: the same agent, the same binary, launched under the second
    # NAME (see `sillBottom` above — argv[0] is the whole mechanism) and pointed
    # at its own config. --config is not optional here: SketchyBar's default is
    # ~/.config/sketchybar/sketchybarrc for every instance, so without it both
    # jobs would build the menu bar and the second would just lose the race for
    # its own lock.
    sill-bottom = {
      serviceConfig = {
        ProgramArguments = guiWait.wrapArgs barBottomPath [
          "--config"
          "/Users/${username}/.config/sketchybar/sill-bottomrc"
        ];
        KeepAlive = true;
        RunAtLoad = true;
        ProcessType = "Interactive";
        StandardOutPath = "/tmp/sill-bottom.out.log";
        StandardErrorPath = "/tmp/sill-bottom.err.log";
        EnvironmentVariables = {
          LANG = "en_US.UTF-8";
          PATH = userPath;
        };
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
      # Every file the two bars read. Bound here rather than assigned straight
      # to home.file so the reload stamp below can hash it — see there for why
      # the reload hangs off one derived file rather than off each of these.
      barFiles = {
        ".config/sketchybar/colors.sh".text = colorsSh;
        ".config/sketchybar/sizes.sh".text = sizesSh;
        ".config/sketchybar/workspaces.sh".text = workspacesSh;
        ".config/sketchybar/top_items.sh".text = topItemsSh;
        ".config/sketchybar/bar.sh".text = barSh;
        ".config/sketchybar/position.sh".text = positionSh;
        ".config/sketchybar/tour_item.sh".text = tourItemSh;
        ".config/sketchybar/tour_config.sh".text = tourConfigSh;
        ".config/sketchybar/battery_config.sh".text = ''
          #!/bin/bash
          # GENERATED from haus.sill.battery.* by modules/sill/default.nix — do not edit.
          SILL_BATTERY_HIDE_OVER="${
            if config.haus.sill.battery.hideOver != null then toString config.haus.sill.battery.hideOver else ""
          }"
        '';
        ".config/sketchybar/clock_config.sh".text = ''
          #!/bin/bash
          # GENERATED from haus.sill.clock.* by modules/sill/default.nix — do not edit.
          SILL_CLOCK_MODE="${config.haus.sill.clock.mode}"
        '';
        # Empty when the pill is off, which is what keeps media-control out of a
        # rice that doesn't draw it — plugins/media.sh, media_stream.sh and
        # media_art.sh all exit 0 on an empty value rather than assuming the
        # binary is there.
        #
        # SILL_MEDIA_ICONS is the glyph override table, one "key<TAB>glyph" per
        # line. Real tabs and newlines rather than \t/\n escapes because the
        # consumer is a plain double-quoted bash string, where a backslash-t is
        # two characters and nothing would ever match.
        ".config/sketchybar/media_config.sh".text = ''
          #!/bin/bash
          # GENERATED from haus.sill{,.bottom}.items.media + haus.sill.media.* by
          # modules/sill/default.nix — do not edit.
          SILL_MEDIA_CONTROL="${
            lib.optionalString (builtins.elem "media" (topItems ++ bottomItems)) (lib.getExe mediaControl)
          }"
          SILL_MEDIA_COLLAPSE="${if cfg.media.collapse then "1" else "0"}"
          SILL_MEDIA_ARTWORK_TINT="${if cfg.media.artworkTint then "1" else "0"}"
          SILL_MEDIA_ICONS="${
            lib.concatStringsSep "\n" (lib.mapAttrsToList (key: glyph: "${key}\t${glyph}") cfg.media.icons)
          }"
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
      }
      // lib.optionalAttrs cfg.bottom.enable {
        # The second bar's rc + its item list. Deployed only when the bar is on,
        # so a rice without it carries neither file and `sill-bottomrc` can't be
        # run by hand against a `sill-bottom` that isn't installed.
        ".config/sketchybar/sill-bottomrc".source = ./sketchybar/sill-bottomrc;
        ".config/sketchybar/bottom_items.sh".text = bottomItemsSh;
      }
      // {
        # The far-left logo pill's image: the nebelhaus ears (the two cat-ear
        # shapes of the org mark, extracted from web/logos/nebelhaus-mark and
        # tinted PINK). Drawn as apple.logo's background.image in sketchybarrc.
        ".config/sketchybar/nebelhaus-ears.png".source = ./sketchybar/nebelhaus-ears.png;
        ".config/sketchybar/aerospace-notify.sh".source = ./sketchybar/aerospace-notify.sh;
        ".config/sketchybar/plugins".source = ./sketchybar/plugins;
      };
    in
    {
      # A rebuild rewrites every file above, but SketchyBar is a KeepAlive
      # launchd agent that read its config once at boot: it keeps the old items
      # in memory until something tells it to re-read. So a pill added, a colour
      # changed or a `sill.items` reorder all land on disk and change nothing
      # anybody can see, until the next reboot or a hand-run `sketchybar
      # --reload`. This is the same trap prowl's aerospace.toml onChange fixes
      # for AeroSpace (modules/prowl/default.nix), for the same reason.
      #
      # Why ONE derived file instead of an onChange on each of the ~20 above:
      # onChange fires per file, so a colour change that touches colors.sh,
      # sizes.sh and both item lists would reload the bar four times over. The
      # stamp is a content hash of the whole set, so it changes exactly once
      # when anything the bar reads changes, and not at all when nothing does —
      # which is the "only when their config changes" half of this. Hashing
      # barFiles itself rather than a hand-listed set is what keeps that true:
      # a pill added next month is covered without anyone remembering to extend
      # a list, and a forgotten entry here would fail silently, as staleness.
      # toJSON of each entry rather than its `.text or .source` for the same
      # reason — it also covers whatever attrs an entry grows later, so a file
      # that gains `executable = true` reloads the bar on the mode flip alone.
      #
      # The plugins directory is deliberately in the hash. Most plugins are
      # re-exec'd per tick and would take a change without any reload, so
      # including them costs a bar flash on rebuilds that didn't strictly need
      # one — but several (tour.sh init, media_stream.sh, ai_usage.sh) only ever
      # run from the rc at init, and a bar silently stale after a plugin edit is
      # the exact failure this exists to end. A visible flash beats invisible
      # staleness.
      #
      # Absolute paths for both bars, from the same constants every generated
      # block uses: a misdirected client call is silent (see barTopPath above).
      # Guarded so first-boot activation, where no bar is running yet, doesn't
      # fail the rebuild — launchd's RunAtLoad then starts each bar on the fresh
      # config anyway, and a plist change restarts the agent outright, so the
      # two mechanisms cover between them everything a rebuild can move.
      home.file = barFiles // {
        ".config/sketchybar/.haus-stamp" = {
          text = ''
            # GENERATED by modules/sill/default.nix — do not edit, and do not
            # source: this file exists only so its content hash changes when the
            # bar's config does. Nothing reads it.
            ${builtins.hashString "sha256" (
              lib.concatStrings (lib.mapAttrsToList (name: f: name + builtins.toJSON f) barFiles)
            )}
          '';
          onChange = lib.concatLines (
            [ "${barTopPath} --reload 2>/dev/null || true" ]
            ++ lib.optional cfg.bottom.enable "${barBottomPath} --reload 2>/dev/null || true"
          );
        };
      };
    };
}

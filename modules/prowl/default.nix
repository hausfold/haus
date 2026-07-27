# Prowl — stake out your screen. AeroSpace tiling, launched via nix-darwin
# (not Login Items) so it survives cold boot, plus the Caps→F18 leader remap and
# a wake-time window re-sort.
#
# The launcher (which app lives on which workspace, its leader key + window
# rules) is data-driven: keyed nebelhaus.apps entries are the composable source
# of truth, normalized here into nebelhaus._apps. This module renders that list
# into aerospace.toml (+ the wake-time resort script); SketchyBar and pounce read
# the same resolved option so nothing drifts.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  withGUIWait = import ../lib/gui-wait.nix;
  userPath = "/run/current-system/sw/bin:/etc/profiles/per-user/${username}/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin";

  # Absolute paths baked into the generated configs. AeroSpace's exec-and-forget
  # doesn't shell-expand $HOME, so the home path must be a literal — hence the
  # generation (a plain source file couldn't be user-agnostic).
  homeDir = "/Users/${username}";
  binDir = "/etc/profiles/per-user/${username}/bin";
  launchSh = "${homeDir}/.config/aerospace/launch.sh";

  namedEntries = lib.mapAttrsToList (id: app: { inherit id app; }) (
    lib.filterAttrs (_: app: app.enable) config.nebelhaus.apps
  );
  orderedNamedEntries = lib.sort (
    a: b: a.app.order < b.app.order || (a.app.order == b.app.order && a.id < b.id)
  ) namedEntries;
  apps = map (entry: entry.app) orderedNamedEntries;
  appKeys = map (app: app.key) apps;
  duplicateKeys = lib.unique (
    lib.filter (key: lib.count (candidate: candidate == key) appKeys > 1) appKeys
  );

  # The static tiling/workspace/service bindings, shared with the pounce
  # cheatsheet (see ./wm-bindings.nix — one table, rendered both ways so they
  # can't drift). Render each item's `binds` into aerospace.toml lines; a chord
  # maps to a single command ('cmd') or a list of commands (['a', 'b']).
  wmBindings = import ./wm-bindings.nix;
  renderCmd = c: if lib.isList c then "[" + lib.concatMapStringsSep ", " (x: "'${x}'") c + "]" else "'${c}'";
  renderBinds =
    binds: lib.concatStrings (lib.mapAttrsToList (chord: cmd: "${chord} = ${renderCmd cmd}\n") binds);
  sectionBinds = section: lib.concatMapStrings (
    it: lib.optionalString (it ? binds) (renderBinds it.binds)
  ) section.items;
  bindingsForMode = mode: lib.concatMapStrings sectionBinds (
    lib.filter (s: (s.mode or "main") == mode) wmBindings
  );
  # Resolve @HOME@/@BIN@ here: builtins.replaceStrings makes one non-rescanning
  # pass, so tokens these rendered lines introduce wouldn't be caught by the
  # outer substitution below.
  subTokens = builtins.replaceStrings [ "@HOME@" "@BIN@" ] [ homeDir binDir ];
  mainStatic = subTokens (bindingsForMode "main");
  serviceStatic = subTokens (bindingsForMode "service");

  # ⌥⇧<key> throws a window to an app's workspace. Fixed actions stay out of
  # this namespace so every roster letter remains available.
  isRealAssign = a: a.appId != null && a.workspace != null && a.appId != "com.mitchellh.ghostty";
  launchInvocation = a: ''${launchSh} "${a.name}"'' + lib.optionalString (a.workspace != null) " ${a.workspace}";

  mainMoves = lib.concatMapStrings (
    a:
    lib.optionalString (a.workspace != null)
      "alt-shift-${a.key} = 'move-node-to-workspace ${a.workspace}'\n"
  ) apps;

  launchLetters = lib.concatMapStrings (
    a: "${a.key} = ['exec-and-forget ${launchInvocation a}', 'mode main']\n"
  ) apps;

  windowRules = lib.concatMapStrings (
    a:
    lib.optionalString (isRealAssign a)
      "[[on-window-detected]]\nif.app-id = '${a.appId}'\nrun = 'move-node-to-workspace ${a.workspace}'\n\n"
  ) apps;

  resortCases = lib.concatMapStrings (
    a: lib.optionalString (isRealAssign a) ''        ${a.appId}) target="${a.workspace}" ;;''
    + lib.optionalString (isRealAssign a) "\n"
  ) apps;

  # Window gaps follow nebelhaus.ui.scale. Base values are the tuned ones: 10 on
  # the built-in display, 20 around an external. One outer edge reserves bar room
  # (40) — whichever edge sill's bar sits on (nebelhaus.sill.position).
  gap = base: toString (builtins.floor (base * config.nebelhaus.ui.scale + 0.5));

  # The bar-room reservation follows the bar. A built-in display's TOP is under
  # the notch/menu-bar strip macOS already excludes, so a top bar needs no extra
  # reservation there; the external, and a built-in's bottom, have no such strip,
  # so the room is carved explicitly. `auto` maps cleanly onto the per-monitor
  # keys — it pins the bar to the external's bottom and the built-in's notched top
  # — so statically it reads as "bottom on external, top on built-in". (Caveat:
  # docked with the lid open the bar sits at the bottom on BOTH displays; aerospace
  # gaps can't flip per dock-state, so the built-in keeps its notch-tuned top in
  # `auto`, leaving a small overlap at the built-in's bottom in that one case.)
  barPos = if config.nebelhaus.sill.enable then config.nebelhaus.sill.position else "top";
  monLine = builtin: external: ''[{ monitor."Built-in Retina Display" = ${builtin} }, ${external}]'';
  outerTop =
    {
      top = monLine (gap 10) (gap 40);
      bottom = monLine (gap 10) (gap 20);
      auto = monLine (gap 10) (gap 20);
    }
    .${barPos};
  outerBottom =
    {
      top = monLine (gap 10) (gap 20);
      bottom = monLine (gap 40) (gap 40);
      auto = monLine (gap 10) (gap 40);
    }
    .${barPos};

  aerospaceToml = builtins.replaceStrings
    [ "@HOME@" "@BIN@" "@MAIN_STATIC@" "@SERVICE_STATIC@" "@MAIN_MOVES@" "@LAUNCH_LETTERS@" "@WINDOW_RULES@" "@GAP_BUILTIN@" "@GAP_EXTERNAL@" "@GAP_OUTER_TOP@" "@GAP_OUTER_BOTTOM@" ]
    [ homeDir binDir mainStatic serviceStatic mainMoves launchLetters windowRules (gap 10) (gap 20) outerTop outerBottom ]
    (builtins.readFile ./aerospace.toml);

  resortScript = builtins.replaceStrings [ "@RESORT_CASES@" ] [ resortCases ] (
    builtins.readFile ./scripts/resort-windows.sh
  );

  # Any roster app with a cask installs itself — declaring the app also brings it.
  rosterCasks = lib.filter (c: c != null) (map (a: a.cask) apps);
in
lib.mkMerge [
  {
    # One ordered view for prowl, sill, and pounce.
    nebelhaus._apps = apps;
  }

  (lib.mkIf config.nebelhaus.prowl.enable {
    # A fresh host gets a useful terminal + browser. These are field-level
    # defaults, so keyed entries compose with them and can override by app id.
    nebelhaus.apps = {
      ghostty = {
        enable = lib.mkDefault true;
        order = lib.mkDefault 10;
        key = lib.mkDefault "t";
        name = lib.mkDefault "Ghostty";
        workspace = lib.mkDefault "T";
        appId = lib.mkDefault "com.mitchellh.ghostty";
        barIcon = lib.mkDefault ":ghostty:";
        label = lib.mkDefault "Ghostty (Terminal)";
      };
      zen = {
        enable = lib.mkDefault true;
        order = lib.mkDefault 20;
        key = lib.mkDefault "b";
        name = lib.mkDefault "Zen";
        workspace = lib.mkDefault "B";
        appId = lib.mkDefault "app.zen-browser.zen";
        barIcon = lib.mkDefault ":zen_browser:";
        label = lib.mkDefault "Zen (Browser)";
        cask = lib.mkDefault "zen";
      };
    };

    assertions = [
      {
        assertion = duplicateKeys == [ ];
        message = "nebelhaus app leader keys must be unique; duplicated: ${lib.concatStringsSep ", " duplicateKeys}";
      }
    ];
  # AeroSpace itself (cask) + its tap. Roster apps that name a cask ride along.
  # Merged into den's homebrew config.
  homebrew.taps = [ "nikitabobko/tap" ];
  homebrew.casks = [ "aerospace" ] ++ rosterCasks;

  # Caps Lock → F18, feeding AeroSpace's `launch` leader mode. Decimal values are
  # the hidutil HID usage codes (caps lock → F18).
  system.keyboard.enableKeyMapping = true;
  system.keyboard.userKeyMapping = [
    {
      HIDKeyboardModifierMappingSrc = 30064771129; # 0x700000039 caps lock
      HIDKeyboardModifierMappingDst = 30064771181; # 0x70000006D F18
    }
  ];

  launchd.user.agents.aerospace = {
    serviceConfig = {
      ProgramArguments = withGUIWait "/Applications/AeroSpace.app/Contents/MacOS/AeroSpace";
      KeepAlive = true;
      RunAtLoad = true;
      ProcessType = "Interactive";
      StandardOutPath = "/tmp/aerospace.out.log";
      StandardErrorPath = "/tmp/aerospace.err.log";
      EnvironmentVariables = {
        LANG = "en_US.UTF-8";
        PATH = userPath;
      };
    };
  };

  # On wake, re-sort AeroSpace windows back to their assigned workspaces (macOS
  # otherwise dumps them all onto the current workspace).
  launchd.user.agents.sleepwatcher = {
    serviceConfig = {
      ProgramArguments = [
        "${pkgs.sleepwatcher}/bin/sleepwatcher"
        "-w"
        "/Users/${username}/.config/aerospace/on-wake.sh"
      ];
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/tmp/sleepwatcher.out.log";
      StandardErrorPath = "/tmp/sleepwatcher.err.log";
      EnvironmentVariables.PATH = userPath;
    };
  };

  home-manager.users.${username}.home.file = {
    ".config/aerospace/aerospace.toml" = {
      text = aerospaceToml;
      # AeroSpace runs as a KeepAlive launchd agent, so a rebuild rewrites this
      # file but the live daemon keeps its old in-memory bindings until it's
      # told to reload. Without this, every binding edit silently fails to take
      # until a manual `aerospace reload-config` or a reboot — which is exactly
      # how the caps→1-4 workspace focus binds looked "broken" after landing.
      # Guarded so first-boot activation (no daemon yet) doesn't fail; launchd
      # RunAtLoad then starts AeroSpace with the fresh config anyway.
      onChange = ''
        /opt/homebrew/bin/aerospace reload-config 2>/dev/null || true
      '';
    };
    ".config/aerospace/resort-windows.sh" = {
      text = resortScript;
      executable = true;
    };
    # caps→z reopen-last-closed-app: pops the stack sill's last_closed_app.sh
    # plugin fills on every app quit, and `open -b`s it back (browser ⌘⇧T analog).
    ".config/aerospace/reopen-last-app.sh" = {
      source = ./scripts/reopen-last-app.sh;
      executable = true;
    };
    ".config/aerospace/on-wake.sh" = {
      source = ./scripts/on-wake.sh;
      executable = true;
    };
    ".config/aerospace/launch.sh" = {
      source = ./scripts/launch.sh;
      executable = true;
    };
  };
  })
]

# Prowl — stake out your screen. AeroSpace tiling, launched via nix-darwin
# (not Login Items) so it survives cold boot, plus the leader-key remap and
# a wake-time window re-sort.
#
# The KEYMAP is haus.keys.* (resolved by ../lib/keys.nix), not baked in:
# `leader` picks what enters launch mode (or removes it), `windowNav` picks the
# modifier every window chord hangs off (or removes them). Both can be "none",
# which is what makes a mouse-first rice — or a non-US-layout one, where ⌥+letter
# belongs to the keyboard rather than to a window manager — expressible at all.
#
# The launcher (which app lives on which workspace, its leader key + window
# rules) is data-driven: keyed haus.roster entries are the composable source
# of truth, resolved by ../roster into haus._roster / ._launchers. This module
# renders those lists into aerospace.toml (+ the wake-time resort script);
# SketchyBar and pounce read the same resolved options so nothing drifts.
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

  # Absolute paths baked into the generated configs. AeroSpace's exec-and-forget
  # doesn't shell-expand $HOME, so the home path must be a literal — hence the
  # generation (a plain source file couldn't be user-agnostic).
  homeDir = "/Users/${username}";
  binDir = "/etc/profiles/per-user/${username}/bin";
  launchSh = "${homeDir}/.config/aerospace/launch.sh";

  # Resolved by ../roster (which also owns the uniqueness assertion and the
  # installs). `apps` is the whole roster — what the WINDOW rules are built
  # from, since an app can float or belong to a workspace without claiming a
  # leader key. `launchers` is the keyboard half, and the only one allowed to
  # render a binding: a null key in [mode.launch.binding] would be the literal
  # string. `workspaces` is ../workspaces' resolved haus.workspaces list —
  # the workspace throw below is keyed off IT now, not off an app's own key,
  # so several apps can share one workspace and one throw.
  apps = config.haus._roster;
  launchers = config.haus._launchers;
  workspaces = config.haus._workspaces;
  appKeys = map (app: app.key) launchers;
  workspaceKeys = map (ws: ws.key) (lib.filter (ws: ws.key != null) workspaces);

  # Which workspace (if any) an app's window herds to, resolved by
  # ../workspaces from haus.workspaces.*.apps — the app itself no longer
  # carries a `workspace` field (see notes/options-roadmap.md §5.4).
  appWorkspaceId = a: config.haus._appWorkspace.${a.id} or null;

  # The resolved keymap: chords + the glyphs that document them, from one table.
  k = import ../lib/keys.nix {
    inherit lib;
    keys = config.haus.keys;
  };

  # The static tiling/workspace/service bindings, shared with the pounce
  # cheatsheet (see ./wm-bindings.nix — one table, rendered both ways so they
  # can't drift). Render each item's `binds` into aerospace.toml lines; a chord
  # maps to a single command ('cmd') or a list of commands (['a', 'b']).
  # A function of the keymap now, and it returns NO window sections when
  # keys.windowNav = "none" — so the toml and the cheatsheet both go quiet
  # together instead of one advertising what the other didn't bind.
  wmBindings = import ./wm-bindings.nix { inherit lib k; };
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

  # Leader then ⇧<key> throws the focused window to a workspace. Fixed
  # actions stay out of this namespace so every roster letter remains available.
  isRealAssign = a: a.appId != null && appWorkspaceId a != null && a.appId != "com.mitchellh.ghostty";
  launchInvocation =
    a: ''${launchSh} "${a.name}"'' + lib.optionalString (appWorkspaceId a != null) " ${appWorkspaceId a}";

  # The workspace roster for aerospace.toml's persistent-workspaces (config
  # schema v2 stopped inferring it from the binding right-hand sides). The fixed
  # digits are the ones hand-written into the toml's launch mode (focus AND
  # throw); the rest is every haus.workspaces id — Ghostty's T included,
  # even though its window rules are bespoke, since it's still declared there
  # for its pill and persistent workspace. Unconditional on the keymap: a
  # keys.* of "none" removes the chords, not the workspaces the window rules
  # still sort apps onto.
  workspaceRoster = lib.sort (a: b: a < b) (
    lib.unique ([ "1" "2" "3" "4" ] ++ map (ws: ws.id) workspaces)
  );
  persistentWorkspaces = lib.concatMapStringsSep ", " (w: ''"${w}"'') workspaceRoster;

  # Workspace throws — leader, then ⇧+the WORKSPACE's own key (not an app's:
  # several apps can share one workspace and one throw now — see
  # notes/options-roadmap.md §5.4). A LEADER action rather than the old
  # main-mode <mod>⇧<letter> chord, so "go there" (leader + an app's key opens
  # it here) and "take this there" (leader + ⇧ + the workspace's key) sit in
  # the same mode instead of on two unrelated modifiers. It also hands the
  # whole <mod>⇧<letter> namespace back to the OS: those chords were claimed
  # globally by AeroSpace, which is how windowNav = "ctrl-alt" used to eat
  # zellij's ⌃⌥⇧c. Follows keys.leader now, not keys.windowNav — "none" means
  # no throws (the palette still moves windows). `--focus-follows-window` so
  # the throw TAKES you there: you moved the window because you want to be
  # with it, and the old behaviour left you on the workspace it just vacated,
  # needing a second leader tap to catch up. Same shape as launchExtras: drop
  # the indicator, act, return to main; homeDir baked literally, so no
  # subTokens pass.
  launchMoves = lib.optionalString (k.leader != null) (
    lib.concatMapStrings (
      ws:
      lib.optionalString (ws.key != null) (
        "shift-${ws.key} = ['exec-and-forget ${homeDir}/.config/sketchybar/plugins/launch_mode.sh off', "
        + "'move-node-to-workspace --focus-follows-window ${ws.id}', 'mode main']\n"
      )
    ) workspaces
  );

  # Mode-entry chords. Structural plumbing rather than tiling commands, so they
  # aren't cheatsheet rows and live here instead of in wm-bindings.nix — but they
  # follow keys.* the same way, and "none" renders an empty line rather than a
  # binding nothing can reach.
  leaderEntry = lib.optionalString (k.leader != null) (
    "${k.leader.chord} = ['mode launch', "
    + "'exec-and-forget @HOME@/.config/sketchybar/plugins/launch_mode.sh on']\n"
  );
  serviceEntry = lib.optionalString (k.nav != null) (
    "${k.nav.chord}-shift-semicolon = 'mode service'\n"
  );

  launchLetters = lib.concatMapStrings (
    a: "${a.key} = ['exec-and-forget ${launchInvocation a}', 'mode main']\n"
  ) launchers;

  # Non-app leader actions (haus.keys.leaderExtras): a leader key that runs a
  # command instead of launching a roster app. Each command goes into its OWN
  # script file (leaderExtraFiles below) and the binding just execs that path —
  # NOT the command inlined. AeroSpace's toml array elements are single-quoted
  # literal strings with no escape, so a command carrying a `'` (an
  # `osascript -e '…'`, say) would close the string early and corrupt the config.
  # Bouncing through a script sidesteps the quoting, and it's the pattern the rice
  # already uses for reopen-last-app.sh / resort-windows.sh. Same
  # [mode.launch.binding] slot as the letters: drop the indicator, run, return to
  # main. homeDir is baked literally (like launchInvocation), so no subTokens pass.
  leaderExtras = config.haus.keys.leaderExtras;
  leaderExtraPath = e: "${homeDir}/.config/aerospace/leader-extra-${e.key}.sh";
  launchExtras = lib.concatMapStrings (
    e: "${e.key} = ['exec-and-forget ${homeDir}/.config/sketchybar/plugins/launch_mode.sh off', 'exec-and-forget ${leaderExtraPath e}', 'mode main']\n"
  ) leaderExtras;
  leaderExtraFiles = lib.listToAttrs (map (e: {
    name = ".config/aerospace/leader-extra-${e.key}.sh";
    value = {
      text = "#!/bin/sh\n# haus.keys.leaderExtras — leader → ${e.key}\nexec ${e.command}\n";
      executable = true;
    };
  }) leaderExtras);

  # The FIXED half of launch mode: the actions written into aerospace.toml's
  # [mode.launch.binding] by hand rather than generated from the roster (digits
  # and ⇧digits, arrows, resize, clipboard/emoji, reopen, settings, resort,
  # cheatsheet, exit). Split out of reservedLaunchKeys because TWO different
  # things can collide with it and only one of them was ever checked.
  builtinLaunchKeys = [
    "esc" "slash" "1" "2" "3" "4"
    "shift-1" "shift-2" "shift-3" "shift-4"
    "v" "e" "z" "comma" "backtick" "minus" "equal"
    "left" "down" "up" "right"
    "shift-left" "shift-down" "shift-up" "shift-right"
  ];

  # Keys already spoken for in launch mode, from leaderExtras' point of view:
  # the fixed actions above, the roster letters (appKeys, plain), and now the
  # WORKSPACE keys (workspaceKeys, shift-only — see launchMoves above for why
  # the throw moved off the app's own key).
  reservedLaunchKeys = appKeys ++ map (key: "shift-${key}") workspaceKeys ++ builtinLaunchKeys;

  # ...and the other direction, which had no check at all: a ROSTER app claiming
  # a letter one of the fixed actions already owns. `roster` asserts its keys are
  # unique among themselves, but it knows nothing about window management, so
  # nothing ever compared them to launch mode's built-ins. The result is two
  # bindings for the same key in one TOML table — AeroSpace keeps whichever it
  # parses last and the other vanishes with no error, which on "z" means quietly
  # losing reopen-last-app.
  #
  # Reachable by hand, but it's a SHARED RICE that makes it likely: an app pack
  # is written without knowing the leader vocabulary, and "z" is the obvious
  # letter for Zotero. Found exactly that way, writing packs/writing.nix.
  rosterBuiltinCollisions = lib.unique (lib.filter (key: lib.elem key builtinLaunchKeys) appKeys);

  # The workspace equivalents: two workspaces claiming the same key (their
  # shift-throws would collide, AeroSpace keeps one silently), and a workspace
  # key whose shift-form is already a built-in (⇧1-4 are the numbered
  # workspaces' own throws).
  duplicateWorkspaceKeys = lib.unique (
    lib.filter (key: lib.count (candidate: candidate == key) workspaceKeys > 1) workspaceKeys
  );
  workspaceBuiltinCollisions = lib.unique (
    lib.filter (key: lib.elem "shift-${key}" builtinLaunchKeys) workspaceKeys
  );

  extraKeys = map (e: e.key) leaderExtras;
  extraCollisions = lib.unique (lib.filter (key: lib.elem key reservedLaunchKeys) extraKeys);
  extraDuplicates = lib.unique (
    lib.filter (key: lib.count (candidate: candidate == key) extraKeys > 1) extraKeys
  );

  windowRules = lib.concatMapStrings (
    a:
    lib.optionalString (isRealAssign a)
      "[[on-window-detected]]\nif.app-id = '${a.appId}'\nrun = 'move-node-to-workspace ${appWorkspaceId a}'\n\n"
  ) apps;

  # `float` entries — the generalised shape the three FaceTime/Trill/Ghostty
  # rules used to be hardcoded as (notes/options-roadmap.md §5.4's "window
  # rules beyond assignment" box). Ghostty stays hand-written in aerospace.toml
  # (its rule is startup-vs-runtime, not a plain always-float — see the
  # comment there), so it never sets `float` itself. `titleRegex` scopes the
  # float to matching windows only; AeroSpace has no primitive for centering a
  # floating window's geometry or for a window pinned across every workspace
  # ("sticky") — verified against upstream's own docs, which call sticky
  # windows "not yet supported" — so neither is offered here; see the §5.4
  # status entry for the citation.
  floatRules = lib.concatMapStrings (
    a:
    lib.optionalString (a.appId != null && a.float) (
      "[[on-window-detected]]\nif.app-id = '${a.appId}'\n"
      + lib.optionalString (a.titleRegex != null) "if.window-title-regex-substring = '${a.titleRegex}'\n"
      + "run = 'layout floating'\n\n"
    )
  ) apps;

  resortCases = lib.concatMapStrings (
    a: lib.optionalString (isRealAssign a) ''        ${a.appId}) target="${appWorkspaceId a}" ;;''
    + lib.optionalString (isRealAssign a) "\n"
  ) apps;

  # Window gaps follow haus.ui.scale. Base values are the tuned ones: 10 on
  # the built-in display, 20 around an external. One outer edge reserves bar room
  # (40) — whichever edge sill's bar sits on (haus.sill.position).
  gap = base: toString (builtins.floor (base * config.haus.ui.scale + 0.5));

  # The bar's own resolution, shared with sill (../lib/bar.nix). prowl needs it
  # for `bar.room`: a scaled bar draws BIGGER TYPE IN THE SAME 28pt PILL, because
  # the pill's height belongs to the macOS menu-bar band rather than to us — so
  # everything the type gains, it gains inside a box that didn't move, and the bar
  # reads as full rather than as bigger. A full bar sitting flush against a tiled
  # window stops looking like chrome and starts looking like the top of the
  # window. `room` hands that growth back as space on the bar's edge — the
  # separation the pill couldn't take vertically. 0 at ui.scale = 1.0, 10pt at the
  # bar's ceiling.
  #
  # It rides the SAME barPos switch as the reservation below, so it lands above a
  # bottom bar and below a top one without a second table to keep in sync.
  bar = import ../lib/bar.nix {
    inherit lib;
    scale = config.haus.ui.scale;
  };
  # A gap plus the bar's breathing room, for the edge the bar is on. Written as
  # one function so the two can't be added in one branch and forgotten in another.
  barGap =
    base: toString (builtins.floor (base * config.haus.ui.scale + 0.5) + bar.room);

  # The bar-room reservation follows the bar. A built-in display's TOP is under
  # the notch/menu-bar strip macOS already excludes, so a top bar needs no extra
  # reservation there; the external, and a built-in's bottom, have no such strip,
  # so the room is carved explicitly. `auto` maps cleanly onto the per-monitor
  # keys — it pins the bar to the external's bottom and the built-in's notched top
  # — so statically it reads as "bottom on external, top on built-in". (Caveat:
  # docked with the lid open the bar sits at the bottom on BOTH displays; aerospace
  # gaps can't flip per dock-state, so the built-in keeps its notch-tuned top in
  # `auto`, leaving a small overlap at the built-in's bottom in that one case.)
  barPos = if config.haus.sill.enable then config.haus.sill.position else "top";
  monLine = builtin: external: ''[{ monitor."Built-in Retina Display" = ${builtin} }, ${external}]'';
  # `barGap` marks every edge a bar can sit on, `gap` every edge it can't. On the
  # built-in with a top bar that means barGap 10 rather than gap 10: the notch
  # strip already excludes the bar's height there, so the reservation stays at its
  # tuned 10 — but the pills still end right where the windows begin, which is the
  # one place the breathing room matters MOST rather than least.
  outerTop =
    {
      top = monLine (barGap 10) (barGap 40);
      bottom = monLine (gap 10) (gap 20);
      auto = monLine (barGap 10) (gap 20);
    }
    .${barPos};
  outerBottom =
    {
      top = monLine (gap 10) (gap 20);
      bottom = monLine (barGap 40) (barGap 40);
      auto = monLine (gap 10) (barGap 40);
    }
    .${barPos};

  aerospaceToml = builtins.replaceStrings
    [ "@HOME@" "@BIN@" "@MAIN_STATIC@" "@SERVICE_STATIC@" "@LAUNCH_MOVES@" "@LEADER_ENTRY@" "@SERVICE_ENTRY@" "@LAUNCH_LETTERS@" "@WINDOW_RULES@" "@FLOAT_RULES@" "@PERSISTENT_WS@" "@GAP_BUILTIN@" "@GAP_EXTERNAL@" "@GAP_OUTER_TOP@" "@GAP_OUTER_BOTTOM@" ]
    [ homeDir binDir mainStatic serviceStatic launchMoves (subTokens leaderEntry) serviceEntry (launchLetters + launchExtras) windowRules floatRules persistentWorkspaces (gap 10) (gap 20) outerTop outerBottom ]
    (builtins.readFile ./aerospace.toml);

  resortScript = builtins.replaceStrings [ "@RESORT_CASES@" ] [ resortCases ] (
    builtins.readFile ./scripts/resort-windows.sh
  );

in
lib.mkMerge [
  (lib.mkIf config.haus.prowl.enable {
    # A fresh host gets a useful terminal + browser. These are field-level
    # defaults, so keyed entries compose with them and can override by app id.
    haus.roster = {
      # `name` and `cask` are den's (it's den that installs the terminal) — this
      # adds only the tiling half, so the two modules never define one field
      # twice. That split is the pattern: whoever INSTALLS an app owns its
      # source fields, whoever gives it a KEY owns the launcher fields.
      ghostty = {
        enable = lib.mkDefault true;
        order = lib.mkDefault 10;
        key = lib.mkDefault "t";
        appId = lib.mkDefault "com.mitchellh.ghostty";
        label = lib.mkDefault "Ghostty (Terminal)";
      };
      zen = {
        enable = lib.mkDefault true;
        order = lib.mkDefault 20;
        key = lib.mkDefault "b";
        name = lib.mkDefault "Zen";
        appId = lib.mkDefault "app.zen-browser.zen";
        label = lib.mkDefault "Zen (Browser)";
        cask = lib.mkDefault "zen";
      };

      # Always-float utility windows — the generalised shape of what used to
      # be two hand-written aerospace.toml rules (§5.4's "window rules beyond
      # assignment" box). Neither installs anything (FaceTime is stock macOS;
      # Trill isn't shipped by this rice yet — its rule was hand-added ahead
      # of the module landing), so both are metadata-only entries whose only
      # job is naming a bundle id and setting `float`.
      facetime = {
        enable = lib.mkDefault true;
        order = lib.mkDefault 990;
        appId = lib.mkDefault "com.apple.FaceTime";
        float = lib.mkDefault true;
      };
      # Trill's status-item windows (Settings, Inbox) are user-summoned
      # utility windows, not tiled documents — same treatment as FaceTime.
      trill = {
        enable = lib.mkDefault true;
        order = lib.mkDefault 991;
        appId = lib.mkDefault "com.hausfold.trill";
        float = lib.mkDefault true;
      };
    };

    # Ghostty/Zen's workspace membership. A PLAIN `apps` list (not
    # lib.mkDefault) — see haus.workspaces.<id>.apps' own description for
    # why: a plain list here MERGES with whatever a host adds to T or B,
    # where an mkDefault one would be dropped whole the moment a host wrote
    # its own `apps` for the same workspace, silently losing ghostty's spot.
    haus.workspaces = {
      T = {
        key = lib.mkDefault "t";
        icon = lib.mkDefault ":ghostty:";
        apps = [ "ghostty" ];
      };
      B = {
        key = lib.mkDefault "b";
        icon = lib.mkDefault ":zen_browser:";
        apps = [ "zen" ];
      };
    };

    # A warning rather than an assertion, deliberately: the tour still works, it
    # just has less to teach, and blocking a legitimate combination is worse than
    # saying so. Same call as the universalaccess warning (nebelhaus#89).
    warnings = lib.optional (config.haus.tour.enable && k.leader == null) (
      "haus.tour.enable is on with haus.keys.leader = \"none\": three of "
      + "the tour's four steps teach leader moves this rice doesn't bind. Set a "
      + "leader, or turn the tour off."
    );

    assertions = [
      {
        # Cross-room: keys.leader is prowl's chord and keys.palette is pounce's
        # in-process hotkey, so nothing would have caught them claiming the same
        # one — and the failure is silent, whoever registers first wins.
        assertion = k.conflicts == [ ];
        message = "haus.keys assigns the same chord twice: " + lib.concatStringsSep "; " k.conflicts;
      }
      {
        # leaderExtras shares the launch mode with the roster letters and the fixed
        # actions; a clash there shadows one binding silently (whichever AeroSpace
        # reads last), so refuse it at eval instead.
        assertion = extraCollisions == [ ] && extraDuplicates == [ ];
        message =
          "haus.keys.leaderExtras keys must be unique and must not reuse a roster app's "
          + "key or a built-in launch-mode key; conflicting: "
          + lib.concatStringsSep ", " (lib.unique (extraCollisions ++ extraDuplicates));
      }
      {
        # The mirror of the assertion above, and the one that was missing. Same
        # failure — two bindings for one key in [mode.launch.binding], AeroSpace
        # silently keeps one — reached from the roster side instead.
        assertion = rosterBuiltinCollisions == [ ];
        message =
          "haus.roster leader keys must not reuse a built-in launch-mode key; conflicting: "
          + lib.concatStringsSep ", " rosterBuiltinCollisions
          + ". Those letters are leader actions the rice already binds (v clipboard, e emoji, "
          + "z reopen-last-app, , settings, ` resort, - / = resize, digits and arrows for "
          + "workspaces). Pick another letter for the app, or set its key to null and reach it "
          + "from the palette. If the entry came from a shared rice or app pack, override just "
          + "the key in your host file: haus.roster.<id>.key = \"…\";";
      }
      {
        # Two workspaces claiming the same key means two `shift-<key>` throws
        # collide in one TOML table; AeroSpace keeps whichever it parses last.
        assertion = duplicateWorkspaceKeys == [ ];
        message =
          "haus.workspaces keys must be unique; duplicated: "
          + lib.concatStringsSep ", " duplicateWorkspaceKeys;
      }
      {
        # A workspace key of "1".."4" would throw its shift-form onto the same
        # binding the fixed numbered-workspace throws already own.
        assertion = workspaceBuiltinCollisions == [ ];
        message =
          "haus.workspaces keys must not reuse a numbered workspace's digit (their "
          + "⇧-throw is already bound); conflicting: "
          + lib.concatStringsSep ", " workspaceBuiltinCollisions;
      }
    ];
  # AeroSpace itself, as a roster entry like everything else — no leader key,
  # because you don't launch your window manager, it's just running. Its tap
  # stays a raw homebrew.taps line: a tap isn't an app, and the roster models
  # what a machine HAS, not where Homebrew looks for it.
  homebrew.taps = [ "nikitabobko/tap" ];
  haus.roster.aerospace = {
    name = lib.mkDefault "AeroSpace";
    cask = lib.mkDefault "aerospace";
  };

  # Caps Lock → F18, feeding AeroSpace's `launch` leader mode: AeroSpace can't
  # bind Caps Lock itself. Decimal values are the hidutil HID usage codes (caps
  # lock → F18). Only for keys.leader = "caps" — every other value leaves the
  # keyboard alone, which is the difference between a rice you can hand to
  # someone else and one that takes their Caps Lock. hidutil mappings are
  # re-applied at each activation and don't survive a reboot, so dropping this
  # ends the remap rather than stranding it.
  system.keyboard.enableKeyMapping = k.leader != null && k.leader.capsRemap;
  system.keyboard.userKeyMapping = lib.optionals (k.leader != null && k.leader.capsRemap) [
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

  home-manager.users.${username}.home.file = leaderExtraFiles // {
    ".config/aerospace/aerospace.toml" = {
      text = aerospaceToml;
      # AeroSpace runs as a KeepAlive launchd agent, so a rebuild rewrites this
      # file but the live daemon keeps its old in-memory bindings until it's
      # told to reload. Without this, every binding edit silently fails to take
      # until a manual `aerospace reload-config` or a reboot — which is exactly
      # how the leader→1-4 workspace focus binds looked "broken" after landing.
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
    # leader→z reopen-last-closed-app: pops the stack sill's last_closed_app.sh
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

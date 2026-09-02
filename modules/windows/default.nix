# Windows — stake out your screen. AeroSpace tiling, launched via nix-darwin
# (not Login Items) so it survives cold boot, plus the leader-key remap and
# a wake-time window re-sort.
#
# The KEYMAP is haus.keys.* (resolved by ../lib/keys.nix), not baked in:
# `leader` picks what enters launch mode (or removes it), `windowNav` picks the
# modifier every window chord hangs off (or removes them). Both can be "none",
# which is what makes a mouse-first desktop — or a non-US-layout one, where ⌥+letter
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
  panes = import ../lib/settings-panes.nix;
  withGUIWait = (import ../lib/gui-wait.nix).wrap;

  # `hausrect` — on-screen window rects by window id, the one thing AeroSpace
  # cannot report about itself. scripts/tiling-mode.sh sizes the grid's columns
  # from it; see hausrect.swift for why the tiler has no answer and why this
  # reads WINDOWS rather than displays.
  hausrect = pkgs.callPackage ./package-hausrect.nix { };
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
  # The numbered workspaces, resolved from haus.windows.numberedWorkspaces by
  # ../workspaces. Each is `{ id; key; }` and the two differ only at ten, which
  # is id "10" on the `0` key — so every render below reads BOTH fields rather
  # than assuming a workspace is spelled the way you press it.
  numbered = config.haus._numberedWorkspaces;
  appKeys = map (app: app.key) launchers;
  workspaceKeys = map (ws: ws.key) (lib.filter (ws: ws.key != null) workspaces);

  cfg = config.haus.windows;

  # Which workspace (if any) an app's window herds to, resolved by
  # ../workspaces from haus.workspaces.*.apps — the app itself no longer
  # carries a `workspace` field.
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
  #
  # The agent-spawn chord used to be the exception here — a section outside the
  # windowNav gate, because ⌃⌘A was no navigation key. It left this room on
  # 2026-08-18 for pounce's Ghostty-scoped tap (⌘↵, `cmd:lane-here`), so the
  # table is once again nothing but window keys.
  wmBindings = import ./wm-bindings.nix {
    inherit lib k;
    inherit mouseFullscreen;
  };
  # Which button zooms the window under the pointer, or "none". The modifier is
  # k.nav's — see the option.
  mouseFullscreen = cfg.mouseFullscreen;

  renderCmd =
    c: if lib.isList c then "[" + lib.concatMapStringsSep ", " (x: "'${x}'") c + "]" else "'${c}'";
  renderBinds =
    binds: lib.concatStrings (lib.mapAttrsToList (chord: cmd: "${chord} = ${renderCmd cmd}\n") binds);
  sectionBinds =
    section:
    lib.concatMapStrings (it: lib.optionalString (it ? binds) (renderBinds it.binds)) section.items;
  bindingsForMode =
    mode: lib.concatMapStrings sectionBinds (lib.filter (s: (s.mode or "main") == mode) wmBindings);
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
    a:
    ''${launchSh} "${a.name}"'' + lib.optionalString (appWorkspaceId a != null) " ${appWorkspaceId a}";

  # The workspace roster for aerospace.toml's persistent-workspaces (config
  # schema v2 stopped inferring it from the binding right-hand sides). The
  # numbered ones come from haus.windows.numberedWorkspaces; the rest is every
  # haus.workspaces id — Ghostty's T included, even though its window rules are
  # bespoke, since it's still declared there for its pill and persistent
  # workspace. Unconditional on the keymap: a keys.* of "none" removes the
  # chords, not the workspaces the window rules still sort apps onto.
  #
  # Numbered first, in order, then the named ones sorted. NOT one sort over the
  # lot: a string sort files "10" between "1" and "2", and this list is the one
  # AeroSpace reads back when it enumerates workspaces.
  workspaceRoster =
    map (n: n.id) numbered
    ++ lib.sort (a: b: a < b) (
      lib.subtractLists (map (n: n.id) numbered) (lib.unique (map (ws: ws.id) workspaces))
    );
  persistentWorkspaces = lib.concatMapStringsSep ", " (w: ''"${w}"'') workspaceRoster;

  # Every generated [mode.launch.binding] row has one shape: drop the mode
  # indicator, run the commands, return to main. homeDir is baked literally
  # (like launchInvocation), so these need no subTokens pass.
  launchBind =
    chord: commands:
    "${chord} = ['exec-and-forget ${homeDir}/.config/sketchybar/plugins/launch_mode.sh off'"
    + lib.concatMapStrings (c: ", '${c}'") commands
    + ", 'mode main']\n";

  # What a workspace's key does, in one place for both the numbered digits and
  # the named workspaces — three bindings off one key:
  #
  #   <key>     focus it. NUMBERED ONLY: the bare-key namespace belongs to the
  #             roster's launcher letters, one of which usually doubles as
  #             "open something on this workspace".
  #   ⇧<key>    throw the focused window there AND follow it. You moved the
  #             window because you want to be with it, and the old
  #             throw-and-stay left you on the workspace it just vacated.
  #   ⌥⇧<key>   throw it there and STAY. The other half of that argument, and
  #             the reason the follow could become the default at all: sending
  #             something away to keep working is a real move, and it used to
  #             cost a throw plus a ⌘⇥ back. ⌥⇧ rather than ⇧⌘ because ⇧⌘3/4/5
  #             are macOS's screenshot hotkeys and win over AeroSpace's, which
  #             would have made the chord work on some digits and not others;
  #             ⌥⇧+letter's non-US-layout problem doesn't apply inside a mode,
  #             where you are pressing a key rather than typing one.
  #
  # A LEADER action rather than the old main-mode <mod>⇧<letter> chord, so "go
  # there" and "take this there" sit in the same mode instead of on two
  # unrelated modifiers. It also hands the whole <mod>⇧<letter> namespace back
  # to the OS: those chords were claimed globally by AeroSpace, which is how
  # windowNav = "ctrl-alt" used to eat the terminal's ⌃⌥⇧c. Follows keys.leader, not
  # keys.windowNav — "none" means no workspace keys at all (the palette still
  # moves windows).
  workspaceBinds =
    {
      key,
      id,
      focus,
    }:
    lib.optionalString focus (launchBind key [ "workspace ${id}" ])
    + launchBind "shift-${key}" [ "move-node-to-workspace --focus-follows-window ${id}" ]
    + launchBind "alt-shift-${key}" [ "move-node-to-workspace ${id}" ];

  # The numbered workspaces' own rows. Generated rather than hand-written in
  # aerospace.toml (where 1-4 lived until haus.windows.numberedWorkspaces existed)
  # — the count is an option now, so the toml can't spell the digits out.
  launchDigits = lib.optionalString (k.leader != null) (
    lib.concatMapStrings (
      n:
      workspaceBinds {
        inherit (n) key id;
        focus = true;
      }
    ) numbered
  );

  # ...and the named ones, keyed off the WORKSPACE rather than an app (several
  # apps can share one workspace and one throw).
  launchMoves = lib.optionalString (k.leader != null) (
    lib.concatMapStrings (
      ws:
      lib.optionalString (ws.key != null) (workspaceBinds {
        inherit (ws) key id;
        focus = false;
      })
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
  # Bouncing through a script sidesteps the quoting, and it's the pattern haus
  # already uses for reopen-last-app.sh / resort-windows.sh. Same
  # [mode.launch.binding] slot as the letters: drop the indicator, run, return to
  # main. homeDir is baked literally (like launchInvocation), so no subTokens pass.
  leaderExtras = config.haus.keys.leaderExtras;
  leaderExtraPath = e: "${homeDir}/.config/aerospace/leader-extra-${e.key}.sh";
  launchExtras = lib.concatMapStrings (
    e:
    "${e.key} = ['exec-and-forget ${homeDir}/.config/sketchybar/plugins/launch_mode.sh off', 'exec-and-forget ${leaderExtraPath e}', 'mode main']\n"
  ) leaderExtras;
  leaderExtraFiles = lib.listToAttrs (
    map (e: {
      name = ".config/aerospace/leader-extra-${e.key}.sh";
      value = {
        text = "#!/bin/sh\n# haus.keys.leaderExtras — leader → ${e.key}\nexec ${e.command}\n";
        executable = true;
      };
    }) leaderExtras
  );

  # The FIXED half of launch mode: the actions a host does not choose (arrows,
  # resize, clipboard, Find Files, reopen, settings, tiling cycle, resort,
  # cheatsheet, exit)
  # plus the numbered workspaces' three chords each. Split out of
  # reservedLaunchKeys because TWO different things can collide with it and only
  # one of them was ever checked; split into ./launch-keys.nix because the docs repo's
  # keybinding tripwire renders the same list from the same file (see its
  # header). The digit half is derived rather than listed, since
  # haus.windows.numberedWorkspaces decides how many digits are spoken for — a
  # literal 1-4 would have let a roster letter or a workspace key take "7" on a
  # machine that raised the count.
  builtinLaunchKeys = import ./launch-keys.nix { inherit lib numbered; };

  # Keys already spoken for in launch mode, from leaderExtras' point of view:
  # the fixed actions above, the roster letters (appKeys, plain), and the
  # WORKSPACE keys (workspaceKeys, ⇧ and ⌥⇧ only — see workspaceBinds above for
  # why the throw moved off the app's own key).
  reservedLaunchKeys =
    appKeys
    ++ lib.concatMap (key: [
      "shift-${key}"
      "alt-shift-${key}"
    ]) workspaceKeys
    ++ builtinLaunchKeys;

  # ...and the other direction, which had no check at all: a ROSTER app claiming
  # a letter one of the fixed actions already owns. `roster` asserts its keys are
  # unique among themselves, but it knows nothing about window management, so
  # nothing ever compared them to launch mode's built-ins. The result is two
  # bindings for the same key in one TOML table — AeroSpace keeps whichever it
  # parses last and the other vanishes with no error, which on "z" means quietly
  # losing reopen-last-app.
  #
  # Reachable by hand, but it's a SHARED FILE that makes it likely: a saved app
  # collection is written without knowing the leader vocabulary, and "z" is the
  # obvious letter for Zotero. Found exactly that way, writing packs/writing.nix.
  rosterBuiltinCollisions = lib.unique (lib.filter (key: lib.elem key builtinLaunchKeys) appKeys);

  # The workspace equivalents: two workspaces claiming the same key (their
  # shift-throws would collide, AeroSpace keeps one silently), and a workspace
  # key whose shift-form is already a built-in (a numbered workspace's own
  # throw — which digits those are depends on haus.windows.numberedWorkspaces).
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
    lib.optionalString (isRealAssign a) "[[on-window-detected]]\nif.app-id = '${a.appId}'\nrun = 'move-node-to-workspace ${appWorkspaceId a}'\n\n"
  ) apps;

  # `float` entries — the generalised shape the three FaceTime/Trill/Ghostty
  # rules used to be hardcoded as. Ghostty stays hand-written in aerospace.toml
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
    a:
    lib.optionalString (isRealAssign a) ''${a.appId}) target="${appWorkspaceId a}" ;;''
    + lib.optionalString (isRealAssign a) "\n"
  ) apps;

  # Every number in the [gaps] block, resolved from haus.ui.scale and the bar's
  # position. It lives in ../lib/gaps.nix rather than here because windows is no
  # longer the only room that needs it: the wallpaper draws its debug band at the
  # inset a tiled window will cover, which is these same reservations read back.
  # windows still owns the FORMATTING — the per-monitor table below is AeroSpace's
  # syntax and nobody else's — but not the arithmetic.
  gaps = import ../lib/gaps.nix {
    inherit lib;
    scale = config.haus.ui.scale;
    bar = config.haus.bar;
  };
  # AeroSpace's per-monitor form: a list whose first entry keys off the display's
  # name and whose last is the fallback everything else takes.
  monLine =
    edge:
    ''[{ monitor."Built-in Retina Display" = ${toString edge.builtin} }, ${toString edge.external}]'';

  # haus.windows.mouseFollowsFocus, as AeroSpace spells it. BOTH of its hooks,
  # because the option's name is a promise about focus and not about screens: a
  # monitor hook alone leaves the pointer behind when focus moves between two
  # windows on the same display, which is most of the time.
  #
  # `*-lazy-center` rather than plain `center` in both: lazy leaves the pointer
  # alone when it is already inside the thing that took focus, so the setting
  # fires on the jumps that lose the cursor and not on the ones that don't.
  #
  # The second entry is not about the pointer at all: it is whatever room asked
  # to be told that focus moved (`haus._contrib.windows.laneSeen`, declared in
  # options.nix — today the terminal room's agent lanes, taking a lane's parked
  # trill fin down once you are looking at its window). AeroSpace is the only
  # thing on this Mac that reports focus moving between two windows of ONE app,
  # and two lanes are both Ghostty, so this list is where it has to hang.
  #
  # Rendered from the contribution rather than from a `config.haus.ai` read: the
  # source room decides whether it has anything to run, this room decides how it
  # is run, and a source that is off — or a path it never wrote — leaves the
  # callback empty rather than pointing at a file that isn't there.
  laneSeen = config.haus._contrib.windows.laneSeen;
  focusChanged = lib.concatStringsSep ", " (
    lib.optional cfg.mouseFollowsFocus "'move-mouse window-lazy-center'"
    ++ lib.optional (laneSeen.enable && laneSeen.script != "") "'exec-and-forget ${laneSeen.script}'"
  );
  monitorChanged = lib.optionalString cfg.mouseFollowsFocus "'move-mouse monitor-lazy-center'";

  # haus.keys.layout → AeroSpace's [key-mapping]. Nothing at all on "qwerty":
  # that IS AeroSpace's default, and emitting `preset = 'qwerty'` would put a
  # line in every existing machine's config for no behaviour.
  keyMapping =
    let
      l = k.layout;
      table = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (notation: code: "${notation} = '${code}'") l.notationToKeyCode
      );
    in
    if l.preset == null then
      ""
    else
      "[key-mapping]\npreset = '${l.preset}'\n"
      + lib.optionalString (
        l.notationToKeyCode != { }
      ) "\n[key-mapping.key-notation-to-key-code]\n${table}\n";

  aerospaceToml =
    builtins.replaceStrings
      [
        "@HOME@"
        "@BIN@"
        "@KEY_MAPPING@"
        "@MAIN_STATIC@"
        "@SERVICE_STATIC@"
        "@LAUNCH_DIGITS@"
        "@LAUNCH_MOVES@"
        "@LEADER_ENTRY@"
        "@SERVICE_ENTRY@"
        "@LAUNCH_LETTERS@"
        "@WINDOW_RULES@"
        "@FLOAT_RULES@"
        "@PERSISTENT_WS@"
        "@DEFAULT_LAYOUT@"
        "@DEFAULT_ORIENTATION@"
        "@ACCORDION_PADDING@"
        "@FOCUS_CHANGED@"
        "@MONITOR_CHANGED@"
        "@GAP_BUILTIN@"
        "@GAP_EXTERNAL@"
        "@GAP_OUTER_TOP@"
        "@GAP_OUTER_BOTTOM@"
      ]
      [
        homeDir
        binDir
        keyMapping
        mainStatic
        serviceStatic
        launchDigits
        launchMoves
        (subTokens leaderEntry)
        serviceEntry
        (launchLetters + launchExtras)
        windowRules
        floatRules
        persistentWorkspaces
        cfg.defaultLayout
        cfg.defaultOrientation
        (toString cfg.accordionPadding)
        focusChanged
        monitorChanged
        (toString gaps.inner.builtin)
        (toString gaps.inner.external)
        (monLine gaps.outer.top)
        (monLine gaps.outer.bottom)
      ]
      (builtins.readFile ./aerospace.toml);

  # The float list the re-sort must not un-float, from the same `apps` the
  # floatRules above are built from — one source, so a `float` entry added to
  # the roster is exempt in both places at once.
  resortFloaters = lib.concatStringsSep " " (
    map (a: a.appId) (lib.filter (a: a.appId != null && a.float) apps)
  );

  resortScript =
    builtins.replaceStrings [ "@RESORT_CASES@" "@RESORT_FLOATERS@" ] [ resortCases resortFloaters ]
      (builtins.readFile ./scripts/resort-windows.sh);

in
lib.mkMerge [
  # ---- macOS's own window features (com.apple.WindowManager) ----------------
  # OUTSIDE the `windows.enable` gate on purpose — one of two blocks here that
  # are; the other is the stale-agent cleanup below, gated on `!enable` for the
  # same reason a `mkIf` cannot clean up after itself. These twelve keys are
  # macOS's own Stage Manager / native tiling /
  # desktop settings, not AeroSpace's, so a machine that turns the TILER off has
  # every reason to still want them — gating them behind the room switch would
  # make the two mutually exclusive in exactly the case where you want the other
  # one. They live in this room rather than in core (where the rest of §5.6's
  # settings groups live) because they are the one group that INTERLOCKS with
  # what the room does; see the warning below, which core could not have written.
  #
  # The write itself is an ordinary pass-through: null stays null, upstream's
  # `nullOr bool` already means "leave it alone", and nothing here is TCC-gated.
  # What is unusual is only WHEN it is felt — `../lib/restart-map.nix` marks the
  # domain `logout`, so core announces the wait into the built activation script
  # and every option's description carries the sentence from
  # `../lib/login-map.nix`. Nothing to do here for that; it is already said in
  # the two places a person looks.
  {
    # Built by walking ./window-manager-keys.nix rather than by listing the keys
    # again, so the table stays the single source: an entry whose option path
    # doesn't resolve fails at eval here (`getAttrFromPath` throws), which is the
    # other half of the check `mkWindowManagerOption` runs in ./options.nix. A
    # key with no option and an option with no key are both build failures.
    system.defaults.WindowManager = lib.mapAttrs (
      _: path: lib.getAttrFromPath path config.haus.windows
    ) (import ./window-manager-keys.nix);

    # ---- the room is off, so its two agents have to be gone ------------------
    # Outside the mkIf on purpose: this is the branch where the room is OFF, and
    # a `mkIf cfg.enable` block cannot clean up after itself.
    #
    # nix-darwin already removes a user agent that a generation stopped
    # declaring — its activation walks the PREVIOUS generation's
    # `user/Library/LaunchAgents` and deletes anything the new one does not ship.
    # Measured working: flipping `windows.enable` true → false took both plists
    # out. But it is a ONE-SHOT diff against the immediately-previous generation,
    # so a transition that misses it leaves the plist orphaned FOREVER — from the
    # next rebuild on, the previous generation no longer declares the agent
    # either, and nothing ever looks at it again. Seen on a machine that switched
    # desktops from `hacker` to a third-party one: three subsequent rebuilds, and
    # AeroSpace was still running off an Aug-22 plist with the room off, the
    # tiler tiling and `keys.leader` correctly claiming nothing — which is the
    # confusing half, because the leader key IS released, so the machine reads as
    # "the room went off but the tiler didn't".
    #
    # Removing a file that is already gone is free, so this runs on every rebuild
    # with the room off rather than trying to detect the orphaned case. It is
    # deliberately narrow: only the two agents THIS room declares, only when it is
    # off, and it never touches /Applications/AeroSpace.app — the cask is
    # `haus.homebrew.cleanup`'s business and "haus never deletes your apps" holds.
    system.activationScripts.postActivation.text = lib.mkIf (!config.haus.windows.enable) ''
      # --- windows: the room is off, so neither agent may be left running -----
      windowsUid="$(/usr/bin/id -u -- ${username})"
      for windowsAgent in org.nixos.aerospace org.nixos.sleepwatcher; do
        windowsPlist="/Users/${username}/Library/LaunchAgents/$windowsAgent.plist"
        [ -e "$windowsPlist" ] || continue
        echo "windows: room is off — removing stale $windowsAgent" >&2
        # bootout rather than `launchctl unload`: unload is the deprecated
        # spelling and is a no-op against a job loaded into a GUI domain from a
        # root activation. `|| true` because a job that is already gone exits
        # non-zero, which is the success case here.
        /bin/launchctl bootout "gui/$windowsUid/$windowsAgent" 2>/dev/null || true
        /bin/rm -f "$windowsPlist"
      done
    '';

    # The interlock the roadmap asked for, as a warning rather than an assertion.
    # Two window managers on one machine is a genuine, if unusual, way to work
    # ("Stage Manager on the laptop panel, tiling on the external"), so refusing
    # it would be wrong — but the far more likely reading of this pair is that
    # somebody turned on the tiler and cannot work out why windows keep sliding
    # back, or dragged a window past the screen edge and had macOS tile it into
    # the space AeroSpace was using. Naming both switches is the point: the
    # symptom gives no hint which of the two is doing it.
    warnings =
      let
        smOn = config.haus.windows.stageManager.enable == true;
        dragOn =
          config.haus.windows.nativeTiling.edgeDrag == true
          || config.haus.windows.nativeTiling.topEdgeFullscreen == true;
        both = config.haus.windows.enable && (smOn || dragOn);
      in
      lib.optional both ''
        haus: haus.windows.enable is on (AeroSpace tiling) and so is macOS's own
        window management: ${
          lib.concatStringsSep " + " (
            lib.optional smOn "stageManager.enable" ++ lib.optional dragOn "nativeTiling edge-drag"
          )
        }.

        Both decide where a window belongs, and they disagree: AeroSpace tiles a
        window into the layout, Stage Manager pulls it back to the strip, and an
        edge drag hands half the screen to a window the tiler was already
        placing. The usual symptom is "windows won't stay where I put them",
        which points at neither of them on its own.

        This is a warning and not an error because the combination can be
        deliberate. If it wasn't, the fix is one of:

            haus.windows.stageManager.enable = false;
            haus.windows.nativeTiling.edgeDrag = false;
            haus.windows.nativeTiling.topEdgeFullscreen = false;

        (`haus.windows.nativeTiling.optionAccelerator = true` alongside that
        first line keeps native tiling available on a held ⌥, rather than
        removing it — the two keys are independent, so it is an addition to
        `edgeDrag = false` and not a substitute for it.)

        Both of those land at your NEXT LOGIN — com.apple.WindowManager has no
        live-reload path on macOS 26 — so expect the fight to continue until then.
      '';
  }

  (lib.mkIf config.haus.windows.enable {
    # The tiler's card in core's manual-click deck. AeroSpace asks for this
    # itself the first time it runs, which is precisely why it belongs here
    # anyway: the prompt arrives during a rebuild nobody is watching, gets
    # dismissed, and the machine then looks like tiling is broken rather than
    # ungranted.
    haus._contrib.permissions.windows-accessibility = {
      order = 35;
      title = "Accessibility — AeroSpace";
      why = ''
        Moving, resizing and focusing other apps' windows is the entire job, and
        macOS only lets an app touch another app's windows with Accessibility.
      '';
      cost = "AeroSpace runs and answers, and no window ever moves";
      applies = "command -v aerospace >/dev/null 2>&1 && pgrep -qx AeroSpace";
      # Functional, not declarative: macOS exposes no way to ask about another
      # app's grant, but an AeroSpace that cannot see windows enumerates none.
      # It reads the whole session, so an empty answer means the grant, never an
      # empty desktop — the bar and the palette are windowless, but Finder,
      # the terminal you are typing this in and every running app are not.
      check = ''[ -n "$(aerospace list-windows --all 2>/dev/null)" ]'';
      pane = panes.accessibility;
      steps = [
        "Turn AeroSpace on in the list"
        "Then restart it: launchctl kickstart -k gui/$(id -u)/org.nixos.aerospace"
      ];
    };

    # A fresh host gets a useful terminal + browser. These are field-level
    # defaults, so keyed entries compose with them and can override by app id.
    haus.roster = {
      # `name` and `cask` are core's (it's core that installs the terminal) — this
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
      # assignment" box). Neither installs anything: FaceTime is stock macOS
      # and Trill arrives with the Notifications room
      # (`haus.notifications.compositor`, off by default), never from here. So
      # both are metadata-only entries whose only job is naming a bundle id
      # and setting `float`, which costs nothing on a machine that doesn't
      # have the app.
      # Floating is only half of a call window's job — the other half is
      # staying VISIBLE, and FaceTime is the one foreign window that can:
      # `Video > Always on Top` during a call is native. It has to be, because
      # nothing outside an app can raise its level with SIP on: WindowServer
      # discards level writes from a connection that doesn't own the window
      # (SLSSetWindowLevel returns 0 and applies nothing; SLSOrderWindow
      # refuses outright), and the one connection exempt is Dock's "universal
      # owner" — which is what yabai injects into under partially-disabled
      # SIP. The general SIP-on answer is a ScreenCaptureKit mirror of the
      # buried window; that plan is todo/pin-window.md in hausfold/ops.
      facetime = {
        enable = lib.mkDefault true;
        order = lib.mkDefault 990;
        appId = lib.mkDefault "com.apple.FaceTime";
        float = lib.mkDefault true;
      };
      # Trill's status-item windows (Settings, Inbox) are user-summoned
      # utility windows, not tiled documents — same treatment as FaceTime.
      # Pounce's settings window is the same shape and floats too, but its
      # roster entry lives in ../launcher/default.nix: that room installs the
      # palette, so it owns the entry, and a second definition here would just
      # split one app across two files.
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
    # saying so. Same call as the universalaccess warning (haus#89).
    warnings = lib.optional (config.haus.tour.enable && k.leader == null) (
      "haus.tour.enable is on with haus.keys.leader = \"none\": three of "
      + "the tour's four steps teach leader moves this desktop doesn't bind. Set a "
      + "leader, or turn the tour off."
    );

    # ---- what the room contributes to other rooms -------------------------------
    # The pointer twin of <mod>f. It has to be pounce's tap that carries it —
    # AeroSpace has no mouse bindings and Ghostty's keybind triggers are keys —
    # but WHAT it does is this room's, so the launcher only writes it out.
    # Modifiers follow k.nav, so moving haus.keys.windowNav moves the click with
    # the key; `k.nav.chord` is AeroSpace's dash-joined spelling and pounce takes
    # a list, which is the whole of the translation.
    haus._contrib.launcher.mouseChords = {
      enable = mouseFullscreen != "none" && k.nav != null;
      button = if mouseFullscreen == "none" then "right" else mouseFullscreen;
      modifiers = if k.nav == null then [ "alt" ] else lib.splitString "-" k.nav.chord;
      action = "fullscreen";
    };

    assertions = [
      {
        # windowNav = "none" leaves no modifier to hold, and a bare click chord
        # would swallow every click on the machine — pounce refuses one outright,
        # so without this the option would go quiet and look broken instead.
        assertion = mouseFullscreen == "none" || k.nav != null;
        message =
          "haus.windows.mouseFullscreen = \"${mouseFullscreen}\" needs a modifier to hold, "
          + "but haus.keys.windowNav is \"none\". Set windowNav, or set mouseFullscreen = \"none\".";
      }
      {
        # pounce's event tap is the only thing on the machine that can fire on a
        # click, so the chord is silently absent without the launcher room.
        assertion = mouseFullscreen == "none" || config.haus.launcher.enable;
        message =
          "haus.windows.mouseFullscreen = \"${mouseFullscreen}\" is carried by pounce's event tap "
          + "(AeroSpace has no mouse bindings), so it needs haus.launcher.enable.";
      }
      {
        # Cross-room: keys.leader is windows's chord and keys.palette is pounce's
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
          + ". Those letters are leader actions haus already binds (v clipboard, f Find Files, "
          + "z reopen-last-app, , settings, . tiling cycle, ` resort, - / = resize, digits and "
          + "arrows for "
          + "workspaces). Pick another letter for the app, or set its key to null and reach it "
          + "from the palette. If the entry came from a shared desktop, override just "
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
        # A workspace key that is one of the numbered workspaces' digits would
        # throw its ⇧- and ⌥⇧-forms onto bindings those already own. Which
        # digits that means follows haus.windows.numberedWorkspaces, so raising
        # the count can make a workspace key that was legal yesterday illegal
        # today — which is exactly what this message has to say.
        assertion = workspaceBuiltinCollisions == [ ];
        message =
          "haus.workspaces keys must not reuse a numbered workspace's digit (their "
          + "⇧-throw is already bound); conflicting: "
          + lib.concatStringsSep ", " workspaceBuiltinCollisions
          + ". haus.windows.numberedWorkspaces is ${toString cfg.numberedWorkspaces}, which "
          + "claims the digits "
          + lib.concatStringsSep " " (map (n: n.key) numbered)
          + ". Give the workspace another key, or lower the count.";
      }
    ];
    # AeroSpace itself, as a roster entry like everything else — no leader key,
    # because you don't launch your window manager, it's just running. Its tap
    # stays a raw homebrew.taps line: a tap isn't an app, and the roster models
    # what a machine HAS, not where Homebrew looks for it.
    homebrew.taps = [ "nikitabobko/tap" ];

    # In the SYSTEM profile, so the path tiling-mode.sh spells out
    # (/run/current-system/sw/bin/hausrect) is stable across rebuilds — the same
    # literal-path convention the bar's plugins use for barpop, and for the same
    # reason: a store path baked into a script would go stale the moment either
    # side is rebuilt without the other.
    environment.systemPackages = [ hausrect ];
    haus.roster.aerospace = {
      name = lib.mkDefault "AeroSpace";
      cask = lib.mkDefault "aerospace";
    };

    # Caps Lock → F18, feeding AeroSpace's `launch` leader mode: AeroSpace can't
    # bind Caps Lock itself. Decimal values are the hidutil HID usage codes (caps
    # lock → F18). Only for keys.leader = "caps" — every other value leaves the
    # keyboard alone, which is the difference between a desktop you can hand to
    # someone else and one that takes their Caps Lock. hidutil mappings are
    # re-applied at each activation and don't survive a reboot, so dropping this
    # ends the remap rather than stranding it.
    # mkDefault because the Launcher room can also want key mapping on
    # (haus.launcher.fnKey = "remap" adds Fn → F19 to the same list): a plain
    # definition in both rooms is a conflict the moment the two disagree.
    system.keyboard.enableKeyMapping = lib.mkDefault (k.leader != null && k.leader.capsRemap);
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
      # leader→. : advance the focused workspace's tiling mode one stop
      # (columns -> grid -> accordion -> columns), one one-shot reflow per press
      # — a single `aerospace eval`, so the windows are laid out once rather
      # than flying through every intermediate arrangement. Needs `hausrect`
      # above for the grid's column widths; accordion needs nothing, being a
      # root layout AeroSpace holds per workspace itself.
      ".config/aerospace/tiling-mode.sh" = {
        source = ./scripts/tiling-mode.sh;
        executable = true;
      };
      # <mod>f's whole body, behind the solo-window fullscreen guard — see the
      # binding in wm-bindings.nix and the script's own header.
      ".config/aerospace/fullscreen-toggle.sh" = {
        source = ./scripts/fullscreen-toggle.sh;
        executable = true;
      };
      # leader→z reopen-last-closed-app: pops the stack bar's last_closed_app.sh
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
      # Workspace recency: pushed by exec-on-workspace-change, read back by
      # launch.sh (page-aware `caps t`) and by pounce's ⌃⇥ page walk.
      ".config/aerospace/workspace-mru.sh" = {
        source = ./scripts/workspace-mru.sh;
        executable = true;
      };
    };
  })
]

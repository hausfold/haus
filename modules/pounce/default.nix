# Pounce — the launcher, wired into the system. Runs the pounce daemon as a
# launch agent and frees ⌘Space for it.
#
# The daemon needs a STABLE code-signing identity so a macOS Accessibility (TCC)
# grant survives rebuilds — a store path's adhoc cdhash changes every build,
# losing any grant keyed to it. The nix sandbox can't reach the login keychain,
# so when you provide `nebelhaus.pounce.signingIdentity` we sign impurely here in
# the Aqua session: copy Pounce.app to a fixed writable path, codesign it with
# that identity (a Developer ID cert by name gives the most durable designated
# requirement → grant persists across rebuilds and cert renewals), and exec the
# daemon from that copy. A marker records which store
# path the copy was signed from, so we only re-sign when pounce actually changed.
{
  config,
  lib,
  pkgs,
  hostname,
  username,
  ...
}:

let
  identity = config.nebelhaus.pounce.signingIdentity;

  # The resolved keymap (../lib/keys.nix). pounce needs it twice over: the palette
  # hotkey it registers in-process, and the cheatsheet — which must never teach a
  # key this machine doesn't have, so every page below is conditional on the
  # relevant part of nebelhaus.keys.* being present.
  k = import ../lib/keys.nix {
    inherit lib;
    keys = config.nebelhaus.keys;
  };

  # Rice-owned discovery shelf for Install App. This is deliberately not a
  # host option: it is the distro's editorial shortlist, while a host only owns
  # the apps it actually chooses. Keep the backing source invisible in the UI;
  # all current picks are Homebrew casks so they stay declarative and avoid the
  # Mac App Store's interactive install path.
  popularApps = [
    {
      cask = "zen";
      name = "Zen";
      description = "A calmer Firefox-based web browser";
      appId = "app.zen-browser.zen";
    }
    {
      cask = "legcord";
      name = "Legcord";
      description = "Privacy-minded Discord client";
      appId = "app.legcord.Legcord";
    }
    {
      cask = "obsidian";
      name = "Obsidian";
      description = "Local-first notes and knowledge base";
      appId = "md.obsidian";
    }
    {
      cask = "iina";
      name = "IINA";
      description = "Modern open-source media player";
      appId = "com.colliderli.iina";
    }
    {
      cask = "slack";
      name = "Slack";
      description = "Team chat and collaboration";
      appId = "com.tinyspeck.slackmacgap";
    }
    {
      cask = "firefox";
      name = "Firefox";
      description = "Private, independent web browser";
      appId = "org.mozilla.firefox";
    }
    {
      cask = "google-chrome";
      name = "Google Chrome";
      description = "Google's web browser";
      appId = "com.google.Chrome";
    }
    {
      cask = "1password";
      name = "1Password";
      description = "Password manager and secure wallet";
      appId = "com.1password.1password";
    }
    {
      cask = "discord";
      name = "Discord";
      description = "Voice, video, and community chat";
      appId = "com.hnc.Discord";
    }
    {
      cask = "signal";
      name = "Signal";
      description = "Private messaging and calls";
      appId = "org.whispersystems.signal-desktop";
    }
    {
      cask = "spotify";
      name = "Spotify";
      description = "Music and podcast player";
      appId = "com.spotify.client";
    }
    {
      cask = "visual-studio-code";
      name = "Visual Studio Code";
      description = "Code editor from Microsoft";
      appId = "com.microsoft.VSCode";
    }
    {
      cask = "vlc";
      name = "VLC";
      description = "Video and audio player";
      appId = "org.videolan.vlc";
    }
  ];

  popularAppsCatalog = pkgs.writeText "nebelhaus-popular-apps.tsv" (
    lib.concatMapStringsSep "\n" (
      app:
      lib.concatStringsSep "\t" [
        app.cask
        app.name
        app.description
        app.appId
      ]
    ) popularApps
    + "\n"
  );

  # Short form, for inline use in a cheatsheet row ("⇪ v ↵"). Only read where
  # k.leader is known non-null.
  leaderGlyph = if k.leader != null then k.leader.glyph else "";

  # What the running signed copy was signed FROM — the store path AND the
  # identity. The daemon writes this to the .signed-from marker; both the
  # re-sign guard (in the daemon script) and the kickstart activation compare
  # against it. Encoding the identity too means changing EITHER the pounce
  # version OR signingIdentity invalidates the marker → re-sign + bounce.
  # (Store path alone would silently keep a stale identity on an identity-only
  # change.) Unsigned mode keeps the bare store path, matching old behaviour.
  signedFrom =
    "${pkgs.pounce}/Applications/Pounce.app" + lib.optionalString (identity != "") "@@${identity}";

  # The app font's package installs only the TTF, but its pinned source also
  # carries the authoritative app-name → ligature mappings. Generate the same
  # shell case table as upstream's build.js and ship it beside Install App, so
  # roster entries can set barIcon deterministically — no web/AI guessing.
  appIconMap = pkgs.runCommand "sketchybar-app-icon-map" { } ''
        {
          cat <<'EOF'
    #!/bin/bash
    icon_result=":default:"
    case "$1" in
    EOF
          for mapping in ${pkgs.sketchybar-app-font.src}/mappings/*; do
            patterns="$(<"$mapping")"
            icon="$(basename "$mapping")"
            printf '  %s)\n    icon_result=%q\n    ;;\n' "$patterns" "$icon"
          done
          cat <<'EOF'
    esac
    printf '%s\n' "$icon_result"
    EOF
        } >"$out"
        chmod 555 "$out"
  '';

  # This rice's palette commands (see ./commands — one self-describing script
  # each, metadata in a `# pounce:` header). The generated app-font lookup is
  # private command data, not self-describing, so pounce ignores it.
  riceCommands = pkgs.runCommand "nebelhaus-pounce-commands" { } ''
    mkdir -p $out
    cp ${./commands}/*.sh $out/
    substituteInPlace $out/add-app.sh --replace-fail '@hostname@' '${hostname}'
    chmod 555 $out/*.sh
    install -m555 ${appIconMap} $out/app-icon-map
    # Pounce discovers every top-level file as a command. Keep picker payloads
    # nested so the catalog cannot appear in the launcher and be run as Bash.
    install -Dm444 ${popularAppsCatalog} $out/data/popular-apps.tsv
    ${lib.optionalString (!config.nebelhaus.hush.enable) "rm $out/hush.sh"}
  '';

  # The built-in command set exposed by the pounce-commands package. The daemon
  # discovers commands from these dirs itself (in-process launcher, see below),
  # so it needs the same values the pounce-palette wrapper bakes in.
  builtinCommandsDir = "${pkgs.pounce-commands}/share/pounce/commands";

  # Launch-mode cheatsheet rows — generated from the app roster so the leader
  # page always matches AeroSpace's launcher, then the fixed leader
  # actions (resize / clipboard / emoji / reopen-last-app / resort / exit)
  # appended. The whole page disappears when keys.leader = "none": there is no
  # launch mode to document, and a page teaching an unbound key is worse than none.
  # A few AeroSpace key names read badly as a bare cheatsheet glyph ("enter"); map
  # the common ones to their symbol. Anything unmapped (a letter, "period") shows
  # as-is, which is already fine.
  launchKeyGlyphs = {
    enter = "↵";
    space = "␣";
    tab = "⇥";
  };

  launchModeItems =
    (map (a: {
      key = a.key;
      action = if a.label != null then a.label else a.name;
    }) config.nebelhaus._apps)
    # Non-app leader actions (nebelhaus.keys.leaderExtras) — same source list the
    # AeroSpace [mode.launch.binding] renders from, so this page can't drift from
    # what the keys actually do.
    ++ (map (e: {
      key = launchKeyGlyphs.${e.key} or e.key;
      action = if e.caption != null then e.caption else e.command;
    }) config.nebelhaus.keys.leaderExtras)
    ++ [
      {
        key = "1-4";
        action = "Focus workspace 1-4";
      }
      # The workspace THROWS. Both halves used to be main-mode <mod>⇧ chords;
      # they're leader actions now, so "go there" and "take this there" differ
      # by ⇧ on the same key — and both leave you ON that workspace, since the
      # throw follows the window. The letter row is a pattern, not a binding —
      # the per-app chords are generated from the roster into
      # [mode.launch.binding] (the rows above already name every letter).
      {
        key = "⇧ 1-4";
        action = "Throw window to workspace 1-4 and follow it";
      }
      {
        key = "⇧ [Letter]";
        action = "Throw window to that app's workspace and follow it";
      }
      {
        key = "←↓↑→";
        action = "Move focus — enters navigate, arrows repeat (⎋ exits)";
      }
      {
        key = "⇧ ←↓↑→";
        action = "Move the focused window (in navigate)";
      }
      {
        key = "- / =";
        action = "Resize active tile — enters resize, repeats (⎋ exits)";
      }
      {
        key = "v / e";
        action = "Clipboard / Emoji";
      }
      {
        key = "z";
        action = "Reopen last closed app";
      }
      {
        key = ",";
        action = "System Settings";
      }
      {
        key = "`";
        action = "Resort windows";
      }
      {
        key = "/";
        action = "This cheatsheet";
      }
      {
        key = "⎋";
        action = "Exit launch mode";
      }
    ];

  # The tiling / workspace / service / system pages, rendered from the SAME table
  # that generates the aerospace.toml bindings (../prowl/wm-bindings.nix) — edit a
  # binding there and its cheatsheet row moves with it, so they can't drift. Only
  # items with a `keys` display appear (toml-only bindings are skipped).
  wmPages = map (section: {
    title = section.title;
    items = map (it: {
      key = it.keys;
      action = it.action;
    }) (lib.filter (it: it ? keys) section.items);
  }) (import ../prowl/wm-bindings.nix { inherit lib k; });

  # Wait for the GUI session (→ the /nix volume + an unlocked login keychain)
  # before touching the store path or codesign. Exec'ing via /bin/bash (boot
  # volume) also sidesteps the cold-boot exit-78 race for store-path executables.
  guiWait = ''
    until /usr/bin/pgrep -x Dock >/dev/null 2>&1; do sleep 1; done
    until /usr/bin/pgrep -x Finder >/dev/null 2>&1; do sleep 1; done
    until /usr/bin/pgrep -x SystemUIServer >/dev/null 2>&1; do sleep 1; done
  '';

  # Unsigned: just run the daemon from the store. Signed: copy + re-sign first.
  daemonScript =
    if identity == "" then
      ''
        ${guiWait}
        exec "${pkgs.pounce}/Applications/Pounce.app/Contents/MacOS/pounce" --daemon
      ''
    else
      ''
        ${guiWait}
        STORE_APP="${pkgs.pounce}/Applications/Pounce.app"
        STATE_DIR="$HOME/.local/state/pounce"
        DEST="$STATE_DIR/Pounce.app"
        MARKER="$STATE_DIR/.signed-from"

        if [ ! -d "$DEST" ] || [ "$(/bin/cat "$MARKER" 2>/dev/null)" != "${signedFrom}" ]; then
          /bin/mkdir -p "$STATE_DIR"
          /bin/rm -rf "$DEST"
          if /bin/cp -R "$STORE_APP" "$DEST" \
             && /bin/chmod -R u+w "$DEST" \
             && /usr/bin/codesign --force --identifier com.local.pounce -s "${identity}" "$DEST"; then
            /usr/bin/printf '%s' "${signedFrom}" > "$MARKER"
          else
            echo "pounce: codesign failed, falling back to unsigned store binary (no Accessibility)" >&2
            /bin/rm -f "$MARKER"
            exec "$STORE_APP/Contents/MacOS/pounce" --daemon
          fi
        fi
        exec "$DEST/Contents/MacOS/pounce" --daemon
      '';
  # ---- nebelhaus.pounce.items → config.json's `items` map ---------------------
  #
  # pounce owns the schema (its ItemSettings.swift): one map keyed by an item's
  # stable address, each entry carrying `enabled` / `alias` / `hotkey`. This is the
  # generator for it, so a rice can hide a command, alias one, or bind one without
  # anybody hand-editing JSON that lives in /nix/store anyway.
  #
  # Only the differences are written. An entry that says nothing is omitted
  # entirely, so the generated config stays readable and a diff shows intent.
  items = config.nebelhaus.pounce.items;

  itemsJSON = lib.mapAttrs (
    _: item:
    lib.optionalAttrs (!item.listed) { enabled = false; }
    // lib.optionalAttrs (item.alias != null) { alias = item.alias; }
    # Written in the canonical spelling: one space between steps, none around a
    # "+", whichever form the host used ("cmd + shift + v" and [ "opt+space" "t" ]
    # both come out as pounce writes them by hand). pounce would normalize either
    # way, but a generated file nobody can edit shouldn't need it to.
    // lib.optionalAttrs (item.hotkey != null) {
      hotkey = lib.concatStringsSep " " (stepStrings item.hotkey);
    }
  ) (lib.filterAttrs (_: item: !item.listed || item.alias != null || item.hotkey != null) items);

  # ---- validation: the two ways an items entry fails silently ----------------
  #
  # pounce is deliberately lenient at runtime — a malformed entry is skipped so one
  # bad line can't cost you the whole map. That's right for a hand-edited file and
  # wrong for a generated one: here the config comes from a Nix expression, so a
  # mistake should stop the build rather than leave a key that does nothing.

  # Mirrors ItemTarget.modes in pounce (ItemSettings.swift). Six strings, so it's
  # the size of mirror that's worth its risk: a "mode:" name pounce doesn't know
  # binds NOTHING at all, with no error anywhere, and pounce validates the shape
  # only when something actually fires.
  builtinModes = [
    "launcher"
    "clipboard"
    "emoji"
    "screenshots"
    "camera"
    "filesearch"
  ];

  itemKeyProblem =
    key:
    if lib.hasPrefix "cmd:" key then
      if lib.stringLength key > 4 then null else "\"${key}\" names no command"
    else if lib.hasPrefix "app:" key then
      if lib.hasPrefix "app:/" key && lib.hasSuffix ".app" key then
        null
      else
        "\"${key}\" should be an absolute path to a .app bundle (app:/Applications/Foo.app)"
    else if lib.hasPrefix "mode:" key then
      let
        mode = lib.removePrefix "mode:" key;
      in
      if lib.elem mode builtinModes then
        null
      else
        "\"${key}\" names no built-in window (expected one of: "
        + lib.concatMapStringsSep ", " (m: "mode:${m}") builtinModes
        + ")"
    else
      "\"${key}\" is not an item key (expected cmd:<id>, app:<path> or mode:<name>)";

  keyProblems = lib.filter (p: p != null) (map itemKeyProblem (lib.attrNames items));

  # Modifier synonyms, from pounce's HotKey.swift. Canonicalized so "opt+space"
  # and "alt+space" compare equal — otherwise the clash assertion below would miss
  # exactly the spelling difference that makes a clash hard to see by eye.
  modifierAliases = {
    command = "cmd";
    super = "cmd";
    meta = "cmd";
    option = "opt";
    alt = "opt";
    control = "ctrl";
  };
  knownModifiers = [
    "cmd"
    "opt"
    "ctrl"
    "shift"
  ];

  # "cmd + shift + v" is ONE step; "opt+space e" is two. Whitespace separates
  # steps, so spacing around a "+" has to go first (pounce normalizes the same way).
  squashPlusSpacing = s: lib.replaceStrings [ "+ " ] [ "+" ] (lib.replaceStrings [ " +" ] [ "+" ] s);
  stepStrings =
    spec:
    if lib.isList spec then
      map squashPlusSpacing spec
    else
      lib.filter (s: s != "") (lib.splitString " " (squashPlusSpacing spec));

  # A step in the same shape ../lib/keys.nix uses for its chords ("cmd-space"), so
  # an item hotkey and the palette/leader chord are comparable at all. Modifiers
  # sorted, because "cmd+shift+v" and "shift+cmd+v" are the same chord.
  normalizeStep =
    step:
    let
      parts = map (p: lib.toLower p) (lib.splitString "+" step);
      key = lib.last parts;
      mods = map (m: modifierAliases.${m} or m) (lib.init parts);
    in
    {
      inherit key;
      mods = lib.sort (a: b: a < b) mods;
      chord = lib.concatStringsSep "-" (lib.sort (a: b: a < b) mods ++ [ key ]);
    };

  itemBindings = lib.mapAttrsToList (key: item: {
    itemKey = key;
    caption = item.caption;
    steps = map normalizeStep (stepStrings item.hotkey);
  }) (lib.filterAttrs (_: item: item.hotkey != null) items);

  unknownModifiers = lib.concatMap (
    b:
    lib.concatMap (
      step:
      map (m: "${b.itemKey}: \"${m}\" is not a modifier") (
        lib.filter (m: !lib.elem m knownModifiers) step.mods
      )
    ) b.steps
  ) itemBindings;

  # The rice's own chords, in the same normalized shape. keys.nix already asserts
  # leader-vs-palette (nebelhaus#108); item hotkeys are the third claimant, and the
  # failure mode is identical: whoever registers first wins, silently.
  riceChords =
    lib.optional (k.palette != null) {
      what = "nebelhaus.keys.palette";
      chord = (normalizeStep (lib.concatStringsSep "+" (k.palette.modifiers ++ [ k.palette.key ]))).chord;
    }
    ++ lib.optional (k.leader != null) {
      what = "nebelhaus.keys.leader";
      # The leader's AeroSpace chord ("f18" for Caps Lock, "alt-space") is already
      # modifier-dash-key, so "+" is all that differs.
      chord = (normalizeStep (lib.replaceStrings [ "-" ] [ "+" ] k.leader.chord)).chord;
    };

  # Only the FIRST step can clash with a rice chord: a later step is grabbed for
  # ~2s after the leader fires, and pounce disarms it again.
  firstStepClashes = lib.concatMap (
    b:
    let
      first = (lib.head b.steps).chord;
    in
    map (rc: "${b.itemKey}'s hotkey ${first} is already ${rc.what}") (
      lib.filter (rc: rc.chord == first) riceChords
    )
  ) (lib.filter (b: b.steps != [ ]) itemBindings);

  # Two items claiming the identical sequence, or a bare chord that is another
  # item's leader step — both leave one of the two bindings dead. Sharing a leader
  # ("opt+space e" and "opt+space f") is fine and is the point of sequences.
  sequenceOf = b: lib.concatMapStringsSep " " (s: s.chord) b.steps;
  duplicateSequences =
    let
      seqs = map sequenceOf itemBindings;
    in
    map (s: "two items bind the same hotkey (${s})") (
      lib.unique (lib.filter (s: lib.count (x: x == s) seqs > 1) seqs)
    );
  leaderShadows = lib.concatMap (
    b:
    let
      bare = lib.length b.steps == 1;
      chord = (lib.head b.steps).chord;
      shadowed = lib.filter (
        other: lib.length other.steps > 1 && (lib.head other.steps).chord == chord
      ) itemBindings;
    in
    lib.optional (bare && shadowed != [ ]) (
      "${b.itemKey}'s hotkey ${chord} is also the leader of "
      + lib.concatMapStringsSep ", " (o: o.itemKey) shadowed
    )
  ) (lib.filter (b: b.steps != [ ]) itemBindings);

  # ---- the cheatsheet page for those bindings ---------------------------------
  #
  # Rendered from `itemBindings` — the SAME list the assertions above read, which is
  # the whole point. Every other key on this rice already comes from one table with
  # its caption (that was #108's lesson: the modifier was the last thing still typed
  # twice, once as a chord and once as a caption, in a document whose only job is
  # that those can't drift). An item hotkey is a working key that appears on no
  # page unless this exists.
  modGlyphs = {
    cmd = "⌘";
    opt = "⌥";
    ctrl = "⌃";
    shift = "⇧";
  };
  keyGlyphs = {
    space = "␣";
    tab = "⇥";
    enter = "↵";
    return = "↵";
    escape = "⎋";
    delete = "⌫";
    left = "←";
    right = "→";
    up = "↑";
    down = "↓";
  };
  # One step's glyphs are CONCATENATED and steps are separated by a space, so
  # "⌘⇧V" (one chord) can't be misread as "⌥␣ V" (press, then press) — a
  # distinction this page exists to teach.
  stepGlyph =
    step:
    lib.concatMapStrings (m: modGlyphs.${m} or m) step.mods
    # Parens matter: `x.${k} or f y` parses as `(x.${k} or f) y`.
    + (keyGlyphs.${step.key} or (lib.toUpper step.key));

  # The default caption. `mode:` names are display text mirrored from pounce, so a
  # wrong one is visible rather than silent; `cmd:` is a guess (the command's real
  # name lives in a `# pounce: name` header the rice can't read at eval), which is
  # why `items.<key>.caption` exists.
  modeCaptions = {
    launcher = "The palette itself";
    clipboard = "Clipboard history";
    emoji = "Emoji picker";
    screenshots = "Screenshot browser";
    camera = "Camera preview";
    filesearch = "File search";
  };
  humanize =
    id:
    let
      words = lib.splitString "-" id;
    in
    lib.concatStringsSep " " (
      lib.imap0 (
        i: w: if i == 0 then lib.toUpper (lib.substring 0 1 w) + lib.substring 1 (-1) w else w
      ) words
    );
  derivedCaption =
    itemKey:
    if lib.hasPrefix "mode:" itemKey then
      modeCaptions.${lib.removePrefix "mode:" itemKey} or itemKey
    else if lib.hasPrefix "app:" itemKey then
      lib.removeSuffix ".app" (baseNameOf itemKey)
    else
      humanize (lib.removePrefix "cmd:" itemKey);

  itemKeyPages = lib.optionals (itemBindings != [ ]) [
    {
      title = "Item Keys";
      page = "Tips";
      items = map (b: {
        key = lib.concatMapStringsSep " " stepGlyph b.steps;
        action = if b.caption != null then b.caption else derivedCaption b.itemKey;
      }) itemBindings;
    }
  ];
in
lib.mkIf config.nebelhaus.pounce.enable {
  assertions = [
    {
      assertion = keyProblems == [ ];
      message = "nebelhaus.pounce.items: " + lib.concatStringsSep "; " keyProblems;
    }
    {
      assertion = unknownModifiers == [ ];
      message =
        "nebelhaus.pounce.items: "
        + lib.concatStringsSep "; " unknownModifiers
        + ". Modifiers are cmd/command/super/meta, opt/option/alt, ctrl/control, shift "
        + "— an unrecognised one is ignored by pounce, which arms a chord you didn't ask for.";
    }
    {
      assertion = firstStepClashes ++ duplicateSequences ++ leaderShadows == [ ];
      message =
        "nebelhaus.pounce.items: "
        + lib.concatStringsSep "; " (firstStepClashes ++ duplicateSequences ++ leaderShadows)
        + ". A chord claimed twice is not an error at runtime — whoever registers "
        + "first wins — so it has to be one here.";
    }
  ];

  launchd.user.agents.pounce = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/bash"
        "-c"
        daemonScript
      ];
      KeepAlive = true;
      RunAtLoad = true;
      ProcessType = "Interactive";
      StandardOutPath = "/tmp/pounce.out.log";
      StandardErrorPath = "/tmp/pounce.err.log";
      EnvironmentVariables = {
        LANG = "en_US.UTF-8";
        HOME = "/Users/${username}";
        # A launchd GUI agent's PATH is bare (/usr/bin:/bin:/usr/sbin:/sbin), and
        # the daemon hands its own environment to every palette command it spawns
        # — so a command calling `sketchybar`, `aerospace`, `jq` or `nix` by name
        # dies with 127 while working fine in any shell. Give the agent the real
        # search path. (The daemon script above resolves everything by absolute
        # path, so this can't change how the daemon itself starts.)
        PATH = lib.concatStringsSep ":" [
          "/run/current-system/sw/bin"
          "/etc/profiles/per-user/${username}/bin"
          "/opt/homebrew/bin"
          "/opt/homebrew/sbin"
          "/usr/bin"
          "/bin"
          "/usr/sbin"
          "/sbin"
        ];
        # The daemon owns ⌘Space in-process and builds the launcher itself, so it
        # discovers commands from its OWN environment — the same dirs pounce-palette
        # uses. Built-ins + this rice's commands; ~/.config/pounce/commands is
        # always searched last by the daemon. (AeroSpace no longer spawns
        # pounce-palette on ⌘Space — see modules/prowl/aerospace.toml.)
        POUNCE_BUILTIN_DIR = builtinCommandsDir;
        POUNCE_EXTRA_COMMAND_DIRS = "${riceCommands}";
        # Where the ssh plugin (and any command that respects the hook) opens a
        # terminal: a new tab in the `main` zellij session instead of stock
        # Terminal. See modules/hearth/zellij/pounce-terminal.sh.
        POUNCE_TERMINAL_LAUNCHER = "/Users/${username}/.config/zellij/pounce-terminal.sh";
      };
    };
  };

  # Attribute the launch agent to Pounce.app in Login Items & Extensions.
  # Without an AssociatedBundleIdentifiers key, macOS Background Task Management
  # falls back to the signing certificate's owner: the agent execs /bin/bash and
  # the daemon copy is signed with an *individual* Developer ID, so a rice
  # install showed the maintainer's legal name instead of "Pounce". This is the
  # rice-side counterpart to the standalone Homebrew fix (nebelhaus/homebrew-tap#7);
  # the daemon self-registers the bundle via LSRegisterURL (nebelhaus/pounce#29)
  # so Launch Services can resolve com.local.pounce → the running signed copy.
  #
  # nix-darwin's launchd serviceConfig submodule is strictly typed with no
  # AssociatedBundleIdentifiers option (and no freeform escape on this pin), so
  # we can't set it above. Instead re-serialize the resolved agent plist with the
  # key appended and force it over nix-darwin's generated copy — identical output
  # aside from the one added key (same generators.toPlist call nix-darwin uses).
  environment.userLaunchAgents."${config.launchd.user.agents.pounce.serviceConfig.Label}.plist".text =
    lib.mkForce
      (
        lib.generators.toPlist { escape = true; } (
          config.launchd.user.agents.pounce.serviceConfig
          // {
            AssociatedBundleIdentifiers = [ "com.local.pounce" ];
          }
        )
      );

  # All home-manager wiring in ONE block — a dynamic attr key (${username}) can't
  # be merged across multiple statements. Passed as a module FUNCTION so it gets
  # home-manager's extended `lib` (for lib.hm.dag) and the overlaid `pkgs`.
  home-manager.users.${username} =
    {
      lib,
      pkgs,
      nebelung,
      ...
    }:
    let
      # theme.{flavor,contrast} resolved to the selected nebelung variant, the
      # same way hearth/sill/theme do it.
      nb = import ../lib/nebelung.nix {
        inherit lib nebelung;
        theme = config.nebelhaus.theme;
      };
      followAppearance = config.nebelhaus.pounce.followSystemAppearance;
      # Every rendered nebelung variant, dropped where pounce's runtime palette
      # loader looks (~/.config/pounce/themes/<name>.json, read per open — see
      # pounce's docs/reference.md). All of them, not just the selected one, so a
      # hand-edited `"theme"` in config.json can try any variant without a
      # rebuild. `or { }` on an older nebelung lock that predates the output;
      # pounce falls back to its compiled-in default for a name with no file.
      themeFiles = lib.mapAttrs' (
        variant: palette:
        lib.nameValuePair "pounce/themes/${variant}.json" {
          text = builtins.toJSON palette;
        }
      ) (nebelung.palettes or { });
    in
    {
      home.packages = [
        pkgs.pounce
        # The generic command library, plus this rice's own commands layered on
        # via runtime discovery. Same-filename scripts shadow pounce built-ins.
        (pkgs.pounce-commands.override { extraCommandDirs = [ riceCommands ]; })
      ]
      # The optional plugins are discovered via ~/.config/pounce/commands symlinks
      # (dev checkout), not the `plugins` override, so their CLI deps wouldn't come
      # along automatically. Pull every optional plugin's tool into the profile so
      # audio/bluetooth/github stop guarding "not found"; pounce-commands is the
      # single source of truth for that list (its pluginRuntimeDeps).
      ++ pkgs.pounce-commands.allPluginDeps;

      # The rendered variant palettes (see themeFiles above). xdg.configFile
      # rather than home.file only because the sibling home.file entries below
      # use static attr-paths a dynamic `home.file = …` set can't merge with.
      xdg.configFile = themeFiles;

      # Palette settings — pounce re-reads this on each open. Edit + rebuild.
      home.file.".config/pounce/config.json".text = builtins.toJSON (
        {
          windowMode = "compact"; # "default" | "compact"
          # The selected nebelung variant, following theme.{flavor,contrast}. The
          # default variant's name ("nebelung") matches pounce's compiled-in
          # palette, and an older pounce without runtime themes falls back to that
          # same compiled-in default — so this key is safe against both an old
          # pounce lock and an old nebelung lock (no themeFiles → fallback).
          #
          # With nebelhaus.pounce.followSystemAppearance (the default) we write the
          # dark/light PAIR at this contrast instead, and pounce picks per open.
          # An old pounce that doesn't know `themeLight` just reads `theme` and
          # stays dark — the extra key is inert, never an error.
          # Both keys are always written: equal values ARE the pinned case, in
          # pounce's own resolution rule, so there's no conditional attrset here.
          theme = if followAppearance then nb.darkVariant else nb.variant;
          themeLight = if followAppearance then nb.lightVariant else nb.variant;
          # The palette hotkey, registered in-process by the daemon for a near-instant
          # open (no shell/client spawn). Which chord — and whether there is one at all
          # — is nebelhaus.keys.palette.
          # nebelhaus.keys.palette; "none" hands the chord back to the OS entirely.
          hotkey = {
            enabled = k.palette != null;
            key = if k.palette != null then k.palette.key else "space";
            modifiers = if k.palette != null then k.palette.modifiers else [ "cmd" ];
          };
          # ⌘Tab → the MRU window switcher (the last stock macOS keybinding the rice
          # retires). Gated on Accessibility inside the daemon: unsigned/ungranted
          # installs keep stock ⌘Tab, so shipping this on is safe. The option exists
          # for hosts that want the native app switcher back.
          windows = {
            enabled = config.nebelhaus.pounce.windowSwitcher;
            key = "tab";
            modifiers = [ "cmd" ];
          };
          clipboard = {
            enabled = true;
            maxEntries = 200;
            blacklistBundleIds = [ "com.apple.Passwords" ];
            autoPaste = true; # synthesize ⌘V into the prior app; needs Accessibility
          };
        }
        # nebelhaus.pounce.items — hidden rows, aliases and per-item hotkeys (see the
        # generator in the let-block). Omitted entirely when nothing is configured:
        # this file is a /nix/store symlink, so the rice is its only writer, and an
        # empty `items: {}` would just be a key nobody set.
        // lib.optionalAttrs (itemsJSON != { }) { items = itemsJSON; }
      );

      home.file.".config/pounce/cheatsheet.json".text = builtins.toJSON (
        lib.optionals (k.leader != null) [
          {
            title = "Launch Mode [${k.leader.name}]";
            items = launchModeItems;
          }
        ]
        ++ wmPages
        # The whole page is conditional — a cheatsheet teaching keys that do
        # nothing would be worse than no page. Keys must stay true to the
        # `windows` block written into config.json above.
        ++ lib.optionals config.nebelhaus.pounce.windowSwitcher [
          {
            title = "Window Switcher [⌘ ⇥]";
            page = "Tips";
            items = [
              {
                key = "⌘ ⇥";
                action = "Toggle to the last window — release to land";
              }
              {
                key = "⌘ ⇥ ⇥ …";
                action = "Walk all windows, most-recent first (⌘⇧⇥ backwards)";
              }
              {
                key = "⌘ + type";
                action = "Filter windows while holding (frecency-ranked)";
              }
              {
                key = "↵ / ⎋";
                action = "Commit / cancel without releasing ⌘";
              }
              {
                key = "⌥ ⇥";
                action = "Its workspace-level sibling: last workspace";
              }
            ];
          }
        ]
        # Your own per-item keys (nebelhaus.pounce.items), from the same list the
        # collision assertions read. Absent when nothing is bound.
        ++ itemKeyPages
        ++ [
          # ── Tips page (⇥ flips to it) — workflows and the stuff that's hard to
          # remember. Keep every entry TRUE to the configs it describes: keys from
          # hearth/zellij/config.kdl + prowl/aerospace.toml, palette queries from
          # the `# pounce: name` headers in ./commands.
          {
            title = "Terminal · Zellij";
            page = "Tips";
            items = [
              {
                key = "⌃ ⇥";
                action = "Cycle tabs, in any mode";
              }
              {
                key = "⌥ Click path";
                action = "Open a repo-named tab cwd'd there";
              }
              {
                key = "Click image";
                action = "Near-fullscreen chafa preview";
              }
              {
                key = "⌘ p / ⌘ t";
                action = "New pane (same cwd) / new tab (~)";
              }
              {
                key = "⌘ ⇧ t";
                action = "New tab via folder picker";
              }
              {
                key = "⌘ y / ⌘ ⇧ y";
                action = "Yazi: peek files / jump to a shell";
              }
            ];
          }
          {
            title = "Claude Agents";
            page = "Tips";
            items = [
              {
                key = "⌘ c";
                action = "Agent in an isolated worktree branch";
              }
              {
                key = "⌃ ⌥ ⇧ c";
                action = "Agent in this checkout (one per tab)";
              }
              {
                key = "bench status";
                action = "Agent branches, dirty repos, stale locks";
              }
              {
                key = "bench try";
                action = "Build against local checkouts (no push)";
              }
              {
                key = "bench ship";
                action = "Push the chain, bumping locks per hop";
              }
            ];
          }
          # Every row here is a LEADER workflow, so the page only exists when there is
          # a leader — and the glyph is k.leader's, not a hardcoded ⇪.
          {
            title = "Workflows";
            page = "Tips";
            items = lib.optionals (k.leader != null) (
              [
                {
                  key = "${leaderGlyph} v ↵";
                  action = "Pastes straight into the app you left";
                }
              ]
              # The throw follows the window now, so the old two-step (main-mode
              # ⇧chord to send, leader to catch up) is gone — one key does it, and
              # the sequel is bouncing BACK to what you were doing.
              ++ lib.optional (k.nav != null) {
                key = "${leaderGlyph} ⇧ x → ${k.nav.glyph} ⇥";
                action = "Throw window to app's workspace, land with it, bounce back";
              }
              ++ [
                {
                  key = "${leaderGlyph} → → →";
                  action = "Navigate: arrows move focus, ⇧+arrow moves the window (⎋ ends)";
                }
                {
                  key = "${leaderGlyph} - - -";
                  action = "Resize repeats without re-tapping the leader (⎋ ends)";
                }
                {
                  key = "${leaderGlyph} → - →";
                  action = "Navigate and resize flow into each other — no re-tap";
                }
                {
                  key = "${leaderGlyph} `";
                  action = "Untangle windows after a laptop wake";
                }
              ]
            );
          }
          {
            title = "Palette Recipes [${if k.palette != null then k.palette.glyph else "haus"}]";
            page = "Tips";
            items = [
              {
                key = "rebuild";
                action = "Rebuild + switch this Mac";
              }
              {
                key = "nix";
                action = "Open the nix config in your editor";
              }
              {
                key = "reload";
                action = "Reload SketchyBar / AeroSpace";
              }
              {
                key = "force";
                action = "Force-quit an app";
              }
              {
                key = "tour";
                action = "The guided haus tour (the four moves)";
              }
            ];
          }
        ]
      );

      # Free ⌘Space for the palette by disabling Spotlight's "Show Spotlight
      # search" shortcut (symbolic hotkey 64). Integer-typed values are REQUIRED —
      # a string fragment leaves the binding half-alive and it races the daemon's
      # Carbon ⌘Space registration. Full effect on next login; activateSettings -u
      # applies what it can now.
      #
      # ONLY when the palette actually claims ⌘Space. This used to run
      # unconditionally, so a machine whose palette lived elsewhere — or had no
      # palette hotkey at all — still lost Spotlight's shortcut for nothing.
      home.activation.disableSpotlightCmdSpace =
        lib.mkIf (k.palette != null && k.palette.stealsSpotlight)
          (
            lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              $DRY_RUN_CMD /usr/bin/defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys \
                -dict-add 64 '<dict><key>enabled</key><integer>0</integer><key>value</key><dict><key>type</key><string>standard</string><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>1048576</integer></array></dict></dict>'
              $DRY_RUN_CMD /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u || true
            ''
          );

      # A rebuild swaps the store path under the KeepAlive'd daemon, but launchd
      # keeps the OLD image running until something bounces it. The .signed-from
      # marker records the store path + identity the running copy was signed from
      # — when it lags (a pounce bump OR a signingIdentity change), kick the agent;
      # the respawn re-copies + re-signs (a stable identity keeps the Accessibility
      # grant) and clipboard history is on disk, so the bounce loses nothing.
      # Marker match → unchanged → no bounce. Runs in home-manager activation, i.e.
      # after nix-darwin has loaded the new agent plist.
      home.activation.kickstartPounce = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ "$(/bin/cat "$HOME/.local/state/pounce/.signed-from" 2>/dev/null)" != "${signedFrom}" ]; then
          $DRY_RUN_CMD /bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/org.nixos.pounce" || true
        fi
      '';
    };
}

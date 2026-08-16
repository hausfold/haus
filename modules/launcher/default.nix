# Launcher — Pounce, wired into the system. Runs the pounce daemon as a
# launch agent and frees ⌘Space for it.
#
# The daemon needs a STABLE code-signing identity so a macOS Accessibility (TCC)
# grant survives rebuilds — a store path's adhoc cdhash changes every build,
# losing any grant keyed to it. The nix sandbox can't reach the login keychain,
# so when you provide `haus.launcher.signingIdentity` we sign impurely here in
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
  identity = config.haus.launcher.signingIdentity;

  # The resolved keymap (../lib/keys.nix). pounce needs it twice over: the palette
  # hotkey it registers in-process, and the cheatsheet — which must never teach a
  # key this machine doesn't have, so every page below is conditional on the
  # relevant part of haus.keys.* being present.
  k = import ../lib/keys.nix {
    inherit lib;
    keys = config.haus.keys;
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

  popularAppsCatalog = pkgs.writeText "haus-popular-apps.tsv" (
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

  # What the running signed copy was signed FROM — the store path, identity AND
  # bundle-ID schema. The daemon writes this to the .signed-from marker; both the
  # re-sign guard (in the daemon script) and the kickstart activation compare
  # against it. Encoding the identity too means changing EITHER the pounce
  # version, signingIdentity OR identifier invalidates the marker → re-sign +
  # bounce. The identifier suffix is what forces the one-time
  # com.local.pounce → com.hausfold.pounce migration even if the package pin and
  # certificate did not move.
  # (Store path alone would silently keep a stale identity on an identity-only
  # change.) Unsigned mode keeps the bare store path, matching old behaviour.
  signedFrom =
    "${pkgs.pounce}/Applications/Pounce.app"
    + lib.optionalString (identity != "") "@@${identity}@@com.hausfold.pounce";

  # Whether Fn is taken away from macOS at the HID layer rather than read with
  # an event tap — haus.launcher.fnKey. Named once: it decides both the key
  # written into config.json and the mapping declared below.
  fnRemap = config.haus.launcher.fnKey == "remap";

  # Every pounce setting the daemon reads ONCE at startup, as one opaque word —
  # the activation marker's whole content, see home.activation.kickstartPounce.
  # A rebuild that moves any of them bounces the daemon, because the alternative
  # is a rebuild that reports success while the running daemon keeps the old
  # behaviour until the next log-in.
  #
  #   autoQuit  the WHOLE block, not just the flag: pounce's AutoQuit captures
  #             delay and exclude when it arms and never re-reads them
  #             (pkgs/pounce/AutoQuit.swift's init). A marker tracking `enable`
  #             alone would let a rebuild that adds a bundle id to `exclude`
  #             report success while the daemon kept quitting that app.
  #   fnKey     which mechanism carries a `hotkey = "fn"` item: pounce picks it
  #             when it REGISTERS the binding, so switching modes needs the
  #             daemon to re-register. Flipping remap → tap also has to reach a
  #             running daemon, since the daemon is what gives the Fn key back.
  #   lanesZmx  whether the appHotkeys/pages blocks are written at all (they
  #             follow haus.terminal.lanes.backend): pounce arms both taps once
  #             at startup, so flipping the backend has to bounce the daemon or
  #             ⌘P/⌃⇥ keep last boot's meaning until the next log-in.
  #
  # Hashed rather than inlined so the marker is one short line whatever the
  # exclude list grows to, and prefixed so an absent or empty marker (a machine
  # that predates this) can never collide with a real state.
  startupState = "v2-${
    builtins.hashString "sha256" (
      builtins.toJSON {
        autoQuit = config.haus.launcher.autoQuit;
        fnKey = config.haus.launcher.fnKey;
        lanesZmx = config.haus.terminal.lanes.backend == "zmx";
      }
    )
  }";

  # The app font's package installs only the TTF, but its pinned source also
  # carries the authoritative app-name → ligature mappings. Generate the same
  # shell case table as upstream's build.js and ship it beside Install App, so
  # a workspace's `icon` can be set deterministically — no web/AI guessing.
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

  # ---- scenes → palette commands + cheatsheet rows ---------------------------
  #
  # A declared scene used to have no surface but the CLI (its option's own
  # wording, since amended): quiet had a pill and a palette row while `focus
  # scene recording` had a terminal. These commands are generated from
  # `config.haus.focus.scenes` — NOT read from ./commands — so the installed
  # script and its cheatsheet row exist exactly when the scene does, and
  # nothing here reads a generated file at eval (the IFD trap the static-dir
  # comment below riceCommandRows describes). A scene name is a safe filename
  # and a safe shell word by construction: focus's own assertion pins it to
  # one word of [A-Za-z0-9_-], never starting with `-`.
  scenes = lib.optionalAttrs config.haus.focus.enable config.haus.focus.scenes;

  # The `# pounce:` header is line-based, so a description must stay one line —
  # a newline in a host's string would end the header early and turn the rest
  # into script body.
  oneLine = s: lib.replaceStrings [ "\n" ] [ " " ] s;
  sceneDescription =
    name: s: if s.description != "" then oneLine s.description else "Enter the ${name} scene";

  sceneCommand =
    name: s:
    pkgs.writeText "pounce-scene-${name}.sh" ''
      #!/bin/bash
      # pounce: name = Scene: ${name}
      # pounce: description = ${sceneDescription name s}
      # pounce: icon = theatermasks.fill
      # Generated from haus.focus.scenes.${name} — the palette surface a scene
      # doesn't get from the static ./commands dir. Absolute path: the
      # daemon's environment has no user PATH.
      exec "$HOME/.local/bin/focus" scene ${name}
    '';

  # `focus scene off` beside them, so the palette can end what it started.
  # A no-op when no scene is on, so shipping it whenever scenes exist is safe.
  # One string for the header and the cheatsheet row — same rule as the scene
  # rows: the two surfaces read one source, so they can't drift.
  sceneOffDescription = "Exit the active scene, reversing what it took";
  sceneOffCommand = pkgs.writeText "pounce-scene-off.sh" ''
    #!/bin/bash
    # pounce: name = Leave Scene
    # pounce: description = ${sceneOffDescription}
    # pounce: icon = theatermasks
    exec "$HOME/.local/bin/focus" scene off
  '';

  # This rice's palette commands (see ./commands — one self-describing script
  # each, metadata in a `# pounce:` header). The generated app-font lookup is
  # private command data, not self-describing, so pounce ignores it.
  riceCommands = pkgs.runCommand "haus-pounce-commands" { } ''
    mkdir -p $out
    cp ${./commands}/*.sh $out/
    substituteInPlace $out/add-app.sh --replace-fail '@hostname@' '${hostname}'
    chmod 555 $out/*.sh
    install -m555 ${appIconMap} $out/app-icon-map
    # Pounce discovers every top-level file as a command. Keep picker payloads
    # nested so the catalog cannot appear in the launcher and be run as Bash.
    install -Dm444 ${popularAppsCatalog} $out/data/popular-apps.tsv
    ${lib.optionalString (!config.haus.focus.enable) "rm $out/focus.sh"}
    # The lane picker and the ⌘P/⌘⇧P window spawns only make sense where a lane
    # is a window: under the zellij lane backend those chords are zellij binds
    # and the picker's `zmx ls` half doesn't exist, so the commands go too.
    ${lib.optionalString (
      config.haus.terminal.lanes.backend != "zmx"
    ) "rm $out/lanes.sh $out/shell-here.sh $out/shell-here-stay.sh"}
    # The scene commands (see the let-block above). `scene-` can't collide
    # with a static command — none is named that way — and `off` is a name
    # focus reserves, so scene-off.sh is always ours to claim.
    ${lib.concatStrings (
      lib.mapAttrsToList (name: s: "install -m555 ${sceneCommand name s} $out/scene-${name}.sh\n") scenes
    )}
    ${lib.optionalString (scenes != { }) "install -m555 ${sceneOffCommand} $out/scene-off.sh"}
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

  # The numbered workspaces, as a cheatsheet caption. One row per workspace
  # would be a wall of near-identical lines, so the three digit rows below name
  # the RANGE — which is not just "1-N", because the tenth workspace is reached
  # by `0`. `null` when the count is 0, and then the digit rows don't render at
  # all rather than teaching a key nothing binds.
  numberedKeys = map (n: n.key) config.haus._numberedWorkspaces;
  digitRange =
    if numberedKeys == [ ] then
      null
    else if lib.length numberedKeys == 1 then
      "1"
    else if lib.last numberedKeys == "0" then
      "1-9 0"
    else
      "1-${lib.last numberedKeys}";

  launchModeItems =
    # _launchers, not _roster: an install-only roster entry has no leader key, so
    # there is no row to teach.
    (map (a: {
      key = a.key;
      action = if a.label != null then a.label else a.name;
    }) config.haus._launchers)
    # Non-app leader actions (haus.keys.leaderExtras) — same source list the
    # AeroSpace [mode.launch.binding] renders from, so this page can't drift from
    # what the keys actually do.
    ++ (map (e: {
      key = launchKeyGlyphs.${e.key} or e.key;
      action = if e.caption != null then e.caption else e.command;
    }) config.haus.keys.leaderExtras)
    # The numbered workspaces: focus, throw-and-follow, throw-and-stay. Nothing
    # to teach when haus.windows.numberedWorkspaces is 0, and a page that names an
    # unbound key is worse than a page that doesn't mention it.
    ++ lib.optionals (digitRange != null) [
      {
        key = digitRange;
        action = "Focus that workspace";
      }
      # The workspace THROWS. All three used to be main-mode <mod>⇧ chords;
      # they're leader actions now, so "go there", "take this there" and "send
      # this there" differ only by the modifier on one key. ⇧ follows the window
      # because you usually moved it to be with it; ⌥⇧ stays, which used to cost
      # a throw plus a ⌘⇥ back. The letter row is a pattern, not a binding —
      # the per-app chords are generated from the roster into
      # [mode.launch.binding] (the rows above already name every letter).
      {
        key = "⇧ ${digitRange}";
        action = "Throw window there and follow it";
      }
      {
        key = "⌥ ⇧ ${digitRange}";
        action = "Throw window there and stay";
      }
    ]
    ++ [
      {
        key = "⇧ [Letter]";
        action = "Throw window to that app's workspace and follow it";
      }
      {
        key = "⌥ ⇧ [Letter]";
        action = "Throw window to that app's workspace and stay";
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
  # that generates the aerospace.toml bindings (../windows/wm-bindings.nix) — edit a
  # binding there and its cheatsheet row moves with it, so they can't drift. Only
  # items with a `keys` display appear (toml-only bindings are skipped).
  wmPages = map (section: {
    title = section.title;
    items = map (it: {
      key = it.keys;
      action = it.action;
    }) (lib.filter (it: it ? keys) section.items);
  }) (
    import ../windows/wm-bindings.nix {
      inherit lib k;
      # Same contribution windows itself reads, so the card and the bind appear
      # and disappear together — the whole reason this table is imported twice
      # rather than written twice.
      agents = config.haus._contrib.windows.agents;
    }
  );

  # The Terminal cards, from the SAME table terminal asserts zellij/config.kdl
  # against (../terminal/term-bindings.nix). So every terminal chord on this
  # cheatsheet is a chord that is really bound, and every bound chord is on it —
  # terminal's assertion fails the build otherwise. The Tips page used to teach
  # these by hand, and spent months saying ⌘C started an agent; it had been ⌘A
  # since the bind stopped being Claude-only.
  # What the AI room contributes to the launcher, through the extension point
  # this room declares (modules/launcher/options.nix). The Terminal cards read the
  # DEVELOPMENT point instead: they describe the terminal's chords, so they must
  # say exactly what the terminal bound, not what the palette knows.
  agentContrib = config.haus._contrib.launcher.agents;
  termAgentContrib = config.haus._contrib.development.agents;

  termBindings = import ../terminal/term-bindings.nix {
    inherit lib;
    agentDefault = termAgentContrib.default;
    agentsEnabled = termAgentContrib.enable;
    ghDashEnabled = config.haus.terminal.ghDash.enable;
    benchLaneEnabled = config.haus.developer.enable;
    rightClickFullscreenEnabled = config.haus.terminal.rightClickFullscreen;
    laneBackend = config.haus.terminal.lanes.backend;
  };
  termPages = termBindings.pages;

  # The rice's palette commands, read from the `# pounce: name/description`
  # headers of ./commands — the same files riceCommands installs, so renaming a
  # command renames its row and deleting one deletes it. focus.sh is dropped from
  # that derivation on a host without focus, so drop its row with it.
  #
  # The RICE's commands only. pounce's own built-ins (Force Quit, Find Files, …)
  # live in a derivation, and reading their headers here would be IFD on every
  # eval — the palette lists those itself the moment you open it.
  commandField =
    file: field:
    let
      hits = lib.concatMap (
        line:
        let
          m = builtins.match "# pounce: ${field} = (.*)" line;
        in
        lib.optionals (m != null) m
      ) (lib.splitString "\n" (builtins.readFile (./commands + "/${file}")));
    in
    if hits == [ ] then null else lib.head hits;

  # key = what you TYPE, not the full name: the palette fuzzy-matches, so the
  # shortest thing that gets you there is the row, and a full name ("Report
  # haus Issue") in a monospace key box would eat the column the caption
  # needs. The name's first word by default; a command whose first word is the
  # generic half of the pair ("Toggle Focus", the two "Reload …"s) declares the
  # useful word itself with a `# pounce: cheat = …` header. pounce ignores
  # header fields it doesn't know, so that line costs the command nothing.
  riceCommandRows =
    map
      (file: {
        key =
          let
            cheat = commandField file "cheat";
          in
          if cheat != null then
            cheat
          else
            lib.toLower (lib.head (lib.splitString " " (commandField file "name")));
        action = commandField file "description";
      })
      (
        lib.filter (f: f != "focus.sh" || config.haus.focus.enable) (
          lib.naturalSort (
            lib.attrNames (
              lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".sh" n) (builtins.readDir ./commands)
            )
          )
        )
      );

  # The scene commands' rows, from the SAME config the scripts above are
  # generated from — not from their headers, which would be reading a generated
  # file at eval. Key = the scene's name, which is both what you type to
  # fuzzy-match the row and what `focus scene <name>` takes, so the palette row
  # and the CLI teach each other. mapAttrsToList is attr-sorted, so the page
  # order is stable.
  sceneCommandRows =
    lib.mapAttrsToList (name: s: {
      key = name;
      action = sceneDescription name s;
    }) scenes
    ++ lib.optional (scenes != { }) {
      key = "leave";
      action = sceneOffDescription;
    };

  # Wait for the GUI session (→ the /nix volume + an unlocked login keychain)
  # before touching the store path or codesign. Exec'ing via /bin/bash (boot
  # volume) also sidesteps the cold-boot exit-78 race for store-path executables.
  # Shared with windows/bar, and bounded — see ../lib/gui-wait.nix for why the
  # bound matters (an unbounded wait for Finder wedges the daemon after ⌘Q).
  guiWait = (import ../lib/gui-wait.nix).script;

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
             && /usr/bin/plutil -replace CFBundleIdentifier -string com.hausfold.pounce "$DEST/Contents/Info.plist" \
             && /usr/bin/codesign --force --identifier com.hausfold.pounce -s "${identity}" "$DEST"; then
            /usr/bin/printf '%s' "${signedFrom}" > "$MARKER"
          else
            echo "pounce: codesign failed, falling back to unsigned store binary (no Accessibility)" >&2
            /bin/rm -f "$MARKER"
            exec "$STORE_APP/Contents/MacOS/pounce" --daemon
          fi
        fi
        exec "$DEST/Contents/MacOS/pounce" --daemon
      '';
  # ---- haus.launcher.items → config.json's `items` map ---------------------
  #
  # pounce owns the schema (its ItemSettings.swift): one map keyed by an item's
  # stable address, each entry carrying `enabled` / `alias` / `hotkey`. This is the
  # generator for it, so a rice can hide a command, alias one, or bind one without
  # anybody hand-editing JSON that lives in /nix/store anyway.
  #
  # Only the differences are written. An entry that says nothing is omitted
  # entirely, so the generated config stays readable and a diff shows intent.
  items = config.haus.launcher.items;

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

  # pounce's own address space, mirrored in ./item-grammar.nix and pinned to the
  # LOCKED pounce by `nix flake check`'s `pounce-item-grammar`. Both halves are
  # mirrors and both fail in the user's face rather than ours: a "mode:" name
  # pounce doesn't know binds NOTHING at all, with no error anywhere, while a
  # PREFIX pounce has learned since we last looked is rejected here as a typo.
  # The second half is the one that actually drifted — see the file's header.
  grammar = import ./item-grammar.nix;
  builtinModes = grammar.modes;

  itemKeyProblem =
    key:
    if lib.hasPrefix "cmd:" key then
      if lib.stringLength key > 4 then null else "\"${key}\" names no command"
    else if lib.hasPrefix "app:" key then
      if lib.hasPrefix "app:/" key && lib.hasSuffix ".app" key then
        null
      else
        "\"${key}\" should be an absolute path to a .app bundle (app:/Applications/Foo.app)"
    else if lib.hasPrefix "shortcut:" key then
      # As lenient as `ItemTarget.parse`, on purpose: a stricter mirror (a UUID
      # regex) would refuse keys the daemon accepts, which is this file's own
      # bug in the other direction. Whether the library still holds that entry
      # is pounce's question, at fire time — the same rule `cmd:` gets.
      if lib.stringLength key > 9 then
        null
      else
        "\"${key}\" names no shortcut (shortcut:<uuid>, from `shortcuts list --show-identifiers`)"
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
      "\"${key}\" is not an item key ${grammar.expectedText}";

  keyProblems = lib.filter (p: p != null) (map itemKeyProblem (lib.attrNames items));

  # The half `pounce-item-grammar` structurally cannot check: that the shapes
  # this repo CLAIMS to accept are the shapes the chain above actually accepts.
  # Without it, the next prefix pounce adds is "fixed" by appending one string to
  # item-grammar.nix — the check goes green while `itemKeyProblem` still rejects
  # the key, with an error message that now lists the very shape it refused. So
  # every shape needs a sample, and every sample has to survive the validator.
  grammarUnsampled = lib.subtractLists (lib.attrNames grammar.samples) grammar.shapes;
  grammarRejected = lib.filter (s: itemKeyProblem grammar.samples.${s} != null) (
    lib.attrNames grammar.samples
  );

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
  # Pounce accepts all three names for the one physical modifier-only key.
  # Canonicalize them before collision checks so `fn` + `globe` cannot pass Nix
  # evaluation and then fight over the same event tap at runtime.
  keyAliases = {
    function = "fn";
    globe = "fn";
  };

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
      rawKey = lib.last parts;
      key = keyAliases.${rawKey} or rawKey;
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

  # The rice's own GLOBAL chords, in the same normalized shape. keys.nix already
  # asserts leader-vs-palette (haus#108); item hotkeys are the third
  # claimant, and the failure mode is identical: whoever registers first wins,
  # silently. Terminal chords count too: Pounce registers item hotkeys globally,
  # so a cmd+g item would swallow Zellij's Super-g before Ghostty ever saw it.
  # termBindings is already feature-aware (gh-dash is absent when disabled), so
  # the assertion reserves exactly the terminal surface this host actually has.
  riceChords =
    lib.optional (k.palette != null) {
      what = "haus.keys.palette";
      chord = (normalizeStep (lib.concatStringsSep "+" (k.palette.modifiers ++ [ k.palette.key ]))).chord;
    }
    ++ lib.optional (k.leader != null) {
      what = "haus.keys.leader";
      # The leader's AeroSpace chord ("f18" for Caps Lock, "alt-space") is already
      # modifier-dash-key, so "+" is all that differs.
      chord = (normalizeStep (lib.replaceStrings [ "-" ] [ "+" ] k.leader.chord)).chord;
    }
    ++ map (chord: {
      what = "terminal binding ${chord}";
      chord = (normalizeStep (lib.replaceStrings [ " " ] [ "+" ] chord)).chord;
    }) termBindings.chords;

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
    fn = "fn";
    function = "fn";
    globe = "🌐";
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
    else if lib.hasPrefix "shortcut:" itemKey then
      # The only key whose name is unknowable here: it lives in the user's
      # Shortcuts library, not in anything this repo can read. A bare "Shortcut"
      # is a poor cheatsheet row and deliberately not an error — a build that
      # fails over a label would be worse — so `caption` says so out loud.
      "Shortcut"
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
lib.mkIf config.haus.launcher.enable {
  # Published so another room can run one of these scripts directly instead of
  # keeping a second copy of it — bar's logo pill is the first caller (the
  # option in ./options.nix says why a bar plugin can't resolve this itself).
  haus._pounceCommands = "${riceCommands}";

  # The palette runs from a nix-store bundle rather than a cask, so no source
  # field describes it; `installedBy` keeps it visible in the machine's one list
  # instead of being the app that mysteriously isn't declared anywhere.
  haus.roster.pounce = {
    name = lib.mkDefault "Pounce";
    installedBy = lib.mkDefault "haus.launcher";
  };

  # A bare laptop Fn/Globe tap opens Pounce's emoji grid. By default that runs
  # through the same Accessibility-gated session event tap as the window
  # switcher, which SHARES the key with macOS's own Globe action rather than
  # replacing it — HIToolbox carries that action inside every process, below the
  # event stream a tap can see, so the stock emoji picker can still open
  # alongside Pounce's. haus.launcher.fnKey = "remap" is the way to own the key
  # outright. An ungranted or stopped daemon leaves macOS's action untouched
  # either way. mkDefault keeps the opinion easy to undo with
  #   haus.launcher.items."mode:emoji".hotkey = null;
  haus.launcher.items."mode:emoji".hotkey = lib.mkDefault "fn";

  # haus.launcher.fnKey = "remap": Fn → F19 at the HID layer, declared HERE and
  # not left to the daemon, even though pounce can install it itself.
  #
  # UserKeyMapping is one list and nix-darwin's keyboard activation writes it
  # WHOLE — including the Caps Lock leader's entry (modules/windows). A mapping
  # pounce installed at daemon start would therefore be dropped by the next
  # `haus rebuild`, leaving the emoji key dead until the daemon next restarted:
  # the rebuild breaks the key it just configured. Declaring it means activation
  # and pounce agree, pounce finds it already in place, and neither clobbers the
  # other.
  #
  # The consequence is deliberate and is the one difference from standalone
  # pounce: here the remap belongs to the machine's keyboard rather than to the
  # daemon's lifetime, so Fn stays remapped — and inert — while the daemon is
  # stopped. Like the Caps leader, it is re-applied each activation and does not
  # survive a reboot, so dropping the option ends the remap rather than
  # stranding it.
  system.keyboard.enableKeyMapping = lib.mkIf fnRemap true;
  system.keyboard.userKeyMapping = lib.optionals fnRemap [
    {
      HIDKeyboardModifierMappingSrc = 1095216660483; # 0xFF00000003 fn/globe
      HIDKeyboardModifierMappingDst = 30064771182; # 0x70000006E F19
    }
  ];

  assertions = [
    {
      assertion = keyProblems == [ ];
      message = "haus.launcher.items: " + lib.concatStringsSep "; " keyProblems;
    }
    {
      assertion = grammarUnsampled == [ ] && grammarRejected == [ ];
      message =
        "modules/launcher/item-grammar.nix lists "
        + lib.concatStringsSep ", " (grammarUnsampled ++ grammarRejected)
        + " but modules/launcher/default.nix's itemKeyProblem "
        + (if grammarUnsampled != [ ] then "has no sample key for it" else "still rejects its sample")
        + ". The grammar file says what this layer accepts and the if-chain is what "
        + "does the accepting; a shape in one and not the other refuses a key while "
        + "the error message advertises it.";
    }
    {
      assertion = lib.subtractLists (lib.attrNames modeCaptions) grammar.modes == [ ];
      message =
        "modules/launcher/default.nix: modeCaptions has no entry for "
        + lib.concatStringsSep ", " (lib.subtractLists (lib.attrNames modeCaptions) grammar.modes)
        + " — the cheatsheet falls back to printing the raw key, which is a wrong "
        + "row rather than a missing one.";
    }
    {
      assertion = unknownModifiers == [ ];
      message =
        "haus.launcher.items: "
        + lib.concatStringsSep "; " unknownModifiers
        + ". Modifiers are cmd/command/super/meta, opt/option/alt, ctrl/control, shift "
        + "— an unrecognised one is ignored by pounce, which arms a chord you didn't ask for.";
    }
    {
      assertion = firstStepClashes ++ duplicateSequences ++ leaderShadows == [ ];
      message =
        "haus.launcher.items: "
        + lib.concatStringsSep "; " (firstStepClashes ++ duplicateSequences ++ leaderShadows)
        + ". A chord claimed twice is not an error at runtime — whoever registers "
        + "first wins — so it has to be one here.";
    }
  ];

  launchd.user.agents.pounce = {
    serviceConfig = {
      Label = "com.hausfold.pounce";
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
        # pounce-palette on ⌘Space — see modules/windows/aerospace.toml.)
        POUNCE_BUILTIN_DIR = builtinCommandsDir;
        POUNCE_EXTRA_COMMAND_DIRS = "${riceCommands}";
        # The Spawn Agent command runs underneath this launchd environment, not
        # an interactive shell. Keep the selected client explicit here so a
        # palette spawn and a later `holt <name>` agree on its default.
        HAUS_AGENT_DEFAULT = agentContrib.default;
        # Where the ssh plugin (and any command that respects the hook) opens a
        # terminal: a new tab in the `main` zellij session instead of stock
        # Terminal. See modules/terminal/zellij/pounce-terminal.sh.
        POUNCE_TERMINAL_LAUNCHER = "/Users/${username}/.config/zellij/pounce-terminal.sh";
      };
    };
  };

  # Attribute the launch agent to Pounce.app in Login Items & Extensions.
  # Without an AssociatedBundleIdentifiers key, macOS Background Task Management
  # falls back to the signing certificate's owner: the agent execs /bin/bash and
  # the daemon copy is signed with an *individual* Developer ID, so a rice
  # install showed the maintainer's legal name instead of "Pounce". This is the
  # rice-side counterpart to the standalone Homebrew fix (hausfold/homebrew-tap#7);
  # the daemon self-registers the bundle via LSRegisterURL (hausfold/pounce#29)
  # so Launch Services can resolve com.hausfold.pounce → the running signed copy.
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
            # One id, deliberately. This briefly also listed the legacy
            # com.local.pounce, as a narrow compatibility association covering
            # the two paths that execute the immutable store app WITHOUT
            # rewriting its Info.plist — the supported unsigned path and the
            # signing-failure fallback — because until this flake pinned the
            # Pounce source change, that store app still declared the old id.
            # It does not any more: the pinned pounce ships
            # com.hausfold.pounce in pkgs/pounce/Info.plist, so both of those
            # paths now resolve to the id already listed here and the legacy
            # entry named nothing that exists. Removed.
            #
            # Don't re-add an id "just in case": this key is what Background
            # Task Management reads to attribute the agent, and an entry that
            # resolves to no installed bundle is how the fallback-to-the-
            # certificate-owner bug (the maintainer's legal name in the Login
            # Items row) gets back in.
            AssociatedBundleIdentifiers = [ "com.hausfold.pounce" ];
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
      # same way terminal/bar/theme do it.
      nb = import ../lib/nebelung.nix {
        inherit lib nebelung;
        theme = config.haus.theme;
      };
      followAppearance = config.haus.launcher.followSystemAppearance;
      autoQuit = config.haus.launcher.autoQuit;
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
          # Shape and size, kept apart on purpose: windowMode picks the layout's
          # proportions, scale picks how big it's drawn. scale follows
          # haus.ui.scale, so the palette grows with the terminal and the
          # Dock rather than staying the one thing that didn't.
          # An older pounce that predates `scale` ignores the key rather than
          # failing on it — same lenient parse as `themeLight`.
          windowMode = config.haus.launcher.windowMode;
          scale = config.haus.launcher.scale;
          # The selected nebelung variant, following theme.{flavor,contrast}. The
          # default variant's name ("nebelung") matches pounce's compiled-in
          # palette, and an older pounce without runtime themes falls back to that
          # same compiled-in default — so this key is safe against both an old
          # pounce lock and an old nebelung lock (no themeFiles → fallback).
          #
          # With haus.launcher.followSystemAppearance (the default) we write the
          # dark/light PAIR at this contrast instead, and pounce picks per open.
          # An old pounce that doesn't know `themeLight` just reads `theme` and
          # stays dark — the extra key is inert, never an error.
          # Both keys are always written: equal values ARE the pinned case, in
          # pounce's own resolution rule, so there's no conditional attrset here.
          theme = if followAppearance then nb.darkVariant else nb.variant;
          themeLight = if followAppearance then nb.lightVariant else nb.variant;
          # The palette hotkey, registered in-process by the daemon for a near-instant
          # open (no shell/client spawn). Which chord — and whether there is one at all
          # — is haus.keys.palette.
          # haus.keys.palette; "none" hands the chord back to the OS entirely.
          hotkey = {
            enabled = k.palette != null;
            key = if k.palette != null then k.palette.key else "space";
            modifiers = if k.palette != null then k.palette.modifiers else [ "cmd" ];
          };
          # How an item's `hotkey = "fn"` is carried — haus.launcher.fnKey. `tap`
          # (the default) shares the key with macOS's own Globe handler, which
          # lives inside every process below the event stream and therefore wins
          # races a tap can't even see; `remap` takes Fn away at the HID layer,
          # at the cost of Fn's other jobs. Written unconditionally: it is inert
          # without an `fn` binding, and an older pounce that predates the key
          # ignores it rather than failing on it — the same lenient parse as
          # `themeLight`.
          fnKey = config.haus.launcher.fnKey;
          # ⌘Tab → the MRU window switcher (the last stock macOS keybinding the rice
          # retires). Gated on Accessibility inside the daemon: unsigned/ungranted
          # installs keep stock ⌘Tab, so shipping this on is safe. The option exists
          # for hosts that want the native app switcher back.
          windows = {
            enabled = config.haus.launcher.windowSwitcher;
            key = "tab";
            modifiers = [ "cmd" ];
          };
          # Quit an app when its last window closes — haus.launcher.autoQuit, off
          # by default. Reads the same window snapshot as the `windows` switcher
          # above and wants the same Accessibility grant; without it the daemon
          # keeps auto-quit off rather than acting on a snapshot it can't see
          # into. `exclude` is omitted when the option is null, because pounce's
          # own default ([ "com.apple.finder" ]) applies only to a MISSING key —
          # writing a list here replaces it, and writing [] would leave Finder
          # quittable. An older pounce that predates autoQuit ignores the whole
          # block rather than failing on it, same lenient parse as `themeLight`.
          autoQuit = {
            enabled = autoQuit.enable;
            delay = autoQuit.delay;
          }
          // lib.optionalAttrs (autoQuit.exclude != null) { exclude = autoQuit.exclude; };
          clipboard = {
            enabled = true;
            maxEntries = 200;
            blacklistBundleIds = [ "com.apple.Passwords" ];
            autoPaste = true; # synthesize ⌘V into the prior app; needs Accessibility
          };
        }
        # The zmx lane backend's window-layer chords, both riding the same
        # consuming event tap the ⌘⇥ switcher already runs (and the same
        # Accessibility gate — ungranted installs simply keep the chords' stock
        # meanings). Both are APP-SCOPED to Ghostty: consumed only while it is
        # frontmost, passed through untouched everywhere else, so ⌘P stays
        # print and ⌃⇥ stays next-tab in every other app. An older pounce that
        # predates the keys ignores both blocks — the same lenient parse as
        # `themeLight`.
        // lib.optionalAttrs (config.haus.terminal.lanes.backend == "zmx") {
          # ⌘P / ⌘⇧P — the zellij NewPane chords' heirs: a shell WINDOW in the
          # focused window's directory (cmd:shell-here[-stay], this rice's own
          # command scripts). Targets are pounce's one dispatch grammar, so a
          # scoped chord and a palette row are the same address.
          appHotkeys = {
            enabled = true;
            scopes = [
              {
                bundleId = "com.mitchellh.ghostty";
                keys = [
                  {
                    key = "p";
                    modifiers = [ "cmd" ];
                    target = "cmd:shell-here";
                  }
                  {
                    key = "p";
                    modifiers = [
                      "cmd"
                      "shift"
                    ];
                    target = "cmd:shell-here-stay";
                  }
                ];
              }
            ];
          };
          # ⌃⇥ / ⌃⇧⇥ — the MRU walk over the non-empty T/* lane pages
          # (lane-open.sh tiles every repo's lanes onto T/<repo>). Recency
          # comes from the file windows' exec-on-workspace-change hook keeps,
          # so the walk and page-aware `caps t` agree about "last used".
          pages = {
            enabled = true;
            key = "tab";
            modifiers = [ "ctrl" ];
            prefix = "T";
            bundleId = "com.mitchellh.ghostty";
            mruFile = "/Users/${username}/.local/state/haus/workspace-mru";
          };
        }
        # haus.launcher.items — hidden rows, aliases and per-item hotkeys (see the
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
        # The terminal's keys (Keys page) and its mouse gestures (Tips), from
        # terminal's table — see termPages in the let-block.
        ++ termPages
        # The whole page is conditional — a cheatsheet teaching keys that do
        # nothing would be worse than no page. Keys must stay true to the
        # `windows` block written into config.json above.
        ++ lib.optionals config.haus.launcher.windowSwitcher [
          {
            title = "Window Switcher [⌘ ⇥]";
            page = "Tips";
            items = [
              {
                key = "⌘ ⇥";
                action = "Toggle to the last window you can't see — release to land";
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
              # No ⌥⇥ row any more: workspace back-and-forth is retired, and this
              # switcher is what replaced it. Its rows are gathered by workspace
              # and focusing goes through `aerospace focus --window-id`, so it
              # crosses workspaces on its own — and a bare tap takes the most
              # recent window on a DIFFERENT workspace, which is what makes it
              # land where you came from rather than on the pane next door.
              # Deliberately no "move between visible tiles" row here: that's
              # windowNav's focus keys, whose modifier is configurable, and the
              # generated windows page already prints them with the real token.
              {
                key = "⌘ ⇥ → other space";
                action = "Rows group by workspace; landing follows you there";
              }
            ];
          }
        ]
        # Your own per-item keys (haus.launcher.items), from the same list the
        # collision assertions read. Absent when nothing is bound.
        ++ itemKeyPages
        # ── Tips page (⇥ flips to it) — workflows and the stuff that's hard to
        # remember. NO plain key rows are hand-typed here any more: the terminal's
        # come from terminal's table (termPages above) and the window manager's from
        # windows's, because the two cards that WERE hand-typed — "Terminal · Zellij"
        # and "Claude Agents" — are exactly the two that went stale, teaching ⌘C
        # for agents and a folder picker that had long since folded into Peek.
        # What's left below is workflow: the things a key list can't say.
        #
        # The agent worktree loop. `holt` is shipped BY the rice (a flake input on
        # PATH), unlike the family's `bench`, which the old card taught to every
        # install that had never seen the workshop — so these rows are true on any
        # machine running this rice. Off when no agent client is installed, same
        # gate as the ⌘A card on the Keys page.
        ++ lib.optionals agentContrib.enable [
          {
            title = "Agent Worktrees";
            page = "Tips";
            items = [
              {
                key = "holt";
                action = "List every agent worktree, live or parked";
              }
              {
                key = "holt <name>";
                action = "Rebuild a parked one and resume its session";
              }
              {
                key = "holt park";
                action = "Set this tree aside as a wip: commit (not git stash)";
              }
              {
                key = "holt reship";
                action = "PR merged but you kept committing? Ship the rest";
              }
              {
                key = "holt reap";
                action = "Delete the worktrees whose branches landed";
              }
            ];
          }
        ]
        ++ [
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
          # Generated from the `# pounce: name/description` headers of the rice's
          # own ./commands (riceCommandRows in the let-block) — type any part of
          # the name, the palette fuzzy-matches it. Hand-typed queries lived here
          # before, which is how the card kept a "force" row for a command the
          # rice doesn't own and lost every command added since.
          {
            title = "Palette Commands [${if k.palette != null then k.palette.glyph else "haus"}]";
            page = "Tips";
            # The static commands' rows, then the generated scene rows — the
            # same split riceCommands installs, so a row exists iff its command
            # does.
            items = riceCommandRows ++ sceneCommandRows;
          }
        ]
      );

      # Free ⌘Space for the palette by disabling Spotlight's "Show Spotlight
      # search" shortcut (symbolic hotkey 64). Integer-typed values are REQUIRED —
      # a string fragment leaves the binding half-alive and it races the daemon's
      # Carbon ⌘Space registration. Full effect on next login; core's
      # end-of-activation activateSettings -u applies what it can now (it runs
      # after home-manager, so this write is covered without a call of its own).
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
            ''
          );

      # A rebuild swaps the store path under the KeepAlive'd daemon, but launchd
      # keeps the OLD image running until something bounces it. The .signed-from
      # marker records the store path + identity the running copy was signed from
      # — when it lags (a pounce bump OR a signingIdentity change), kick the agent;
      # the respawn re-copies + re-signs. A stable identity normally keeps the
      # Accessibility grant; the one-time com.local.pounce →
      # com.hausfold.pounce identifier migration deliberately changes the code
      # requirement, so that activation needs one fresh approval. Clipboard
      # history is on disk, so the bounce itself loses nothing.
      # Marker match → unchanged → no bounce. Runs in home-manager activation, i.e.
      # after nix-darwin has loaded the new agent plist.
      #
      # The SECOND marker is autoQuit: the daemon reads that whole block once, at
      # startup, rather than per open like the rest of config.json, so a rebuild
      # that touches haus.launcher.autoQuit would otherwise write the file and
      # change nothing until the next login. It gets its own marker instead of
      # being folded into .signed-from, because that one also drives the re-copy
      # + re-sign in the daemon script — and a settings change has no business
      # re-signing the app.
      home.activation.kickstartPounce = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        # Retire the pre-hausfold launchd label explicitly. nix-darwin normally
        # unloads removed plists, but a stale KeepAlive job must never survive
        # beside the canonical agent after this one-time migration.
        $DRY_RUN_CMD /bin/launchctl bootout "gui/$(/usr/bin/id -u)/org.nixos.pounce" 2>/dev/null || true

        pounceBounce=0
        if [ "$(/bin/cat "$HOME/.local/state/pounce/.signed-from" 2>/dev/null)" != "${signedFrom}" ]; then
          pounceBounce=1
        fi
        # Named .auto-quit for what it used to track alone; it now holds every
        # startup-only setting (see startupState). Kept under the old name so an
        # existing machine isn't left with a stranded file — the v2- prefix is
        # what forces the one migration bounce.
        if [ "$(/bin/cat "$HOME/.local/state/pounce/.auto-quit" 2>/dev/null)" != "${startupState}" ]; then
          pounceBounce=1
        fi
        if [ "$pounceBounce" = 1 ]; then
          # The marker is written only on a kickstart that took, so a bounce that
          # failed (no agent loaded yet on a fresh install) is retried next rebuild
          # rather than being recorded as done.
          if $DRY_RUN_CMD /bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/com.hausfold.pounce"; then
            # One /bin/sh -c so the redirection is INSIDE what $DRY_RUN_CMD
            # wraps — a bare `> "$HOME/…"` here would write the marker even on
            # a dry run, and then the real activation would skip the bounce.
            # `|| true` like every sibling here: activation runs under `set -eu`,
            # and a bookkeeping file must never be able to fail a rebuild. Losing
            # the write just means one redundant bounce next time.
            $DRY_RUN_CMD /bin/sh -c '/bin/mkdir -p "$HOME/.local/state/pounce" && /usr/bin/printf "%s" "${startupState}" > "$HOME/.local/state/pounce/.auto-quit"' || true
          fi
        fi
      '';
    };
}

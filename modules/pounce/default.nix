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
      # by ⇧ on the same key. The letter row is a pattern, not a binding — the
      # per-app chords are generated from the roster into [mode.launch.binding]
      # (the rows above already name every letter).
      {
        key = "⇧ 1-4";
        action = "Throw window to workspace 1-4";
      }
      {
        key = "⇧ [Letter]";
        action = "Throw window to that app's workspace";
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
in
lib.mkIf config.nebelhaus.pounce.enable {
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
    lib.mkForce (
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
  home-manager.users.${username} = { lib, pkgs, ... }: {
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

    # Palette settings — pounce re-reads this on each open. Edit + rebuild.
    home.file.".config/pounce/config.json".text = builtins.toJSON {
      windowMode = "compact"; # "default" | "compact"
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
    };

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
          { key = "⌘ ⇥"; action = "Toggle to the last window — release to land"; }
          { key = "⌘ ⇥ ⇥ …"; action = "Walk all windows, most-recent first (⌘⇧⇥ backwards)"; }
          { key = "⌘ + type"; action = "Filter windows while holding (frecency-ranked)"; }
          { key = "↵ / ⎋"; action = "Commit / cancel without releasing ⌘"; }
          { key = "⌥ ⇥"; action = "Its workspace-level sibling: last workspace"; }
        ];
      }
    ]
    ++ [
      # ── Tips page (⇥ flips to it) — workflows and the stuff that's hard to
      # remember. Keep every entry TRUE to the configs it describes: keys from
      # hearth/zellij/config.kdl + prowl/aerospace.toml, palette queries from
      # the `# pounce: name` headers in ./commands.
      {
        title = "Terminal · Zellij";
        page = "Tips";
        items = [
          { key = "⌃ ⇥"; action = "Cycle tabs, in any mode"; }
          { key = "⌥ Click path"; action = "Open a repo-named tab cwd'd there"; }
          { key = "Click image"; action = "Near-fullscreen chafa preview"; }
          { key = "⌘ p / ⌘ t"; action = "New pane (same cwd) / new tab (~)"; }
          { key = "⌘ ⇧ t"; action = "New tab via folder picker"; }
          { key = "⌘ y / ⌘ ⇧ y"; action = "Yazi: peek files / jump to a shell"; }
        ];
      }
      {
        title = "Claude Agents";
        page = "Tips";
        items = [
          { key = "⌘ c"; action = "Agent in an isolated worktree branch"; }
          { key = "⌃ ⌥ ⇧ c"; action = "Agent in this checkout (one per tab)"; }
          { key = "bench status"; action = "Agent branches, dirty repos, stale locks"; }
          { key = "bench try"; action = "Build against local checkouts (no push)"; }
          { key = "bench ship"; action = "Push the chain, bumping locks per hop"; }
        ];
      }
      # Every row here is a LEADER workflow, so the page only exists when there is
      # a leader — and the glyph is k.leader's, not a hardcoded ⇪.
      {
        title = "Workflows";
        page = "Tips";
        items = lib.optionals (k.leader != null) (
          [
            { key = "${leaderGlyph} v ↵"; action = "Pastes straight into the app you left"; }
          ]
          ++ lib.optional (k.nav != null) {
            key = "${k.nav.glyph} ⇧ x → ${leaderGlyph} x";
            action = "Throw window to app's workspace, follow it";
          }
          ++ [
            { key = "${leaderGlyph} → → →"; action = "Navigate: arrows move focus, ⇧+arrow moves the window (⎋ ends)"; }
            { key = "${leaderGlyph} - - -"; action = "Resize repeats without re-tapping the leader (⎋ ends)"; }
            { key = "${leaderGlyph} → - →"; action = "Navigate and resize flow into each other — no re-tap"; }
            { key = "${leaderGlyph} `"; action = "Untangle windows after a laptop wake"; }
          ]
        );
      }
      {
        title = "Palette Recipes [${if k.palette != null then k.palette.glyph else "haus"}]";
        page = "Tips";
        items = [
          { key = "rebuild"; action = "Rebuild + switch this Mac"; }
          { key = "nix"; action = "Open the nix config in your editor"; }
          { key = "reload"; action = "Reload SketchyBar / AeroSpace"; }
          { key = "force"; action = "Force-quit an app"; }
          { key = "tour"; action = "The guided haus tour (the four moves)"; }
        ];
      }
    ]);

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
      (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD /usr/bin/defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys \
        -dict-add 64 '<dict><key>enabled</key><integer>0</integer><key>value</key><dict><key>type</key><string>standard</string><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>1048576</integer></array></dict></dict>'
      $DRY_RUN_CMD /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u || true
    '');

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

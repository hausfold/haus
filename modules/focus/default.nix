# Focus — quiet as a switch. One toggle (bar pill · palette command · `focus`
# CLI) that turns macOS Do Not Disturb on/off, optionally sets your Slack
# status + snoozes Slack push, and runs host hooks. All surfaces call the one
# engine script this module builds, so they can never disagree.
#
# The trick: Apple ships no public API to set a Focus — every "focus CLI" in
# the wild is a Shortcuts wrapper. Instead, this module makes the binding
# itself declarative: it writes symbolic hotkey 175 ("Turn Do Not Disturb
# On/Off" — present on every Mac, disabled and buried in Settings) to an
# obscure chord at activation, and the engine presses that chord
# synthetically. No Shortcuts app, nothing to author by hand.
#
# TCC honesty: the synthetic keypress needs Accessibility on whatever app
# invokes focus (palette runs inherit pounce's grant; the pill needs sketchybar
# granted once), and exact state reads of Assertions.json need Full Disk
# Access — without it focus falls back to remembering its own last toggle.
# `focus doctor` checks and explains all of it.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  cfg = config.haus.focus;

  # ⌃⌥⇧⌘ F13 — a chord no keyboard layout or app claims. 65535 = "no ASCII
  # char", 105 = F13's key code, 1966080 = ctrl(262144) + opt(524288) +
  # shift(131072) + cmd(1048576). focus.sh presses key code @keyCode@ with the
  # same four modifiers — keep the two in lockstep.
  keyCode = 105;
  hotkeyXml = "<dict><key>enabled</key><true/><key>value</key><dict><key>parameters</key><array><integer>65535</integer><integer>${toString keyCode}</integer><integer>1966080</integer></array><key>type</key><string>standard</string></dict></dict>";

  # Double-escaped substitutions: the inner escape is what lands in the script
  # (a shell-quoted literal at runtime), the outer quotes it for the build cmd.
  shq = v: lib.escapeShellArg (lib.escapeShellArg v);
  hooksStr = lib.concatMapStringsSep " " (h: lib.escapeShellArg (toString h)) cfg.hooks;

  # Scenes are DATA, not generated shell: the engine reads this file at runtime
  # and the option surface is the only thing that decides what a scene may do.
  # A scene that rendered into the script would make every field a place where
  # a desktop's string becomes code — the same reason `haus.bar.media.icons`
  # has a key rule in the desktop walk.
  scenesJson = pkgs.writeText "focus-scenes.json" (
    builtins.toJSON (
      lib.mapAttrs (_: s: {
        inherit (s)
          description
          dnd
          preventSleep
          restorePreviousState
          ;
        apps = s.apps.open;
        closeApps = s.apps.closeOnExit;
        audioInput = s.audio.input;
        hooks = map toString s.hooks;
        # The conditions ride the same file for the same reason the rest of the
        # scene does: `focus auto` asks the table what a scene wants and the
        # option surface is the only thing that decides what it may want. A
        # trigger rendered into shell would be a desktop's string running on a
        # timer, forever — the one thing `haus.bar.widgets.<name>.command`
        # is host-only to prevent, arriving through a different door.
        when = {
          inherit (s.when)
            time
            days
            wifi
            power
            displays
            ;
        };
      }) cfg.scenes
    )
  );

  # Only pulled in when a scene actually names an input device — macOS ships no
  # CLI for this, and a room shouldn't grow a closure for a field nobody set.
  wantsAudio = lib.any (s: s.audio.input != "") (lib.attrValues cfg.scenes);
  switchAudio = lib.optionalString wantsAudio "${pkgs.switchaudio-osx}/bin/SwitchAudioSource";

  # The same rule for a launchd agent rather than a closure: a machine whose
  # scenes are all hand-entered runs no daemon at all. `haus.focus.triggers`
  # has no `enable` because this IS the enable — declaring a condition is what
  # asks for the thing that checks it, and an enable beside it would be a second
  # switch that can disagree with the data.
  hasWhen =
    s:
    s.when.time != ""
    || s.when.days != [ ]
    || s.when.wifi != [ ]
    || s.when.power != "any"
    || s.when.displays != null;
  wantsTriggers = lib.any hasWhen (lib.attrValues cfg.scenes);

  engine = pkgs.runCommand "focus" { } ''
    mkdir -p $out/bin
    substitute ${./focus.sh} $out/bin/focus \
      --subst-var-by jq ${pkgs.jq}/bin/jq \
      --subst-var-by keyCode ${toString keyCode} \
      --subst-var-by slackEnabled ${if cfg.slack.enable then "1" else "0"} \
      --subst-var-by slackTokenCommand ${shq cfg.slack.tokenCommand} \
      --subst-var-by slackStatusText ${shq cfg.slack.statusText} \
      --subst-var-by slackStatusEmoji ${shq cfg.slack.statusEmoji} \
      --subst-var-by slackSnooze ${if cfg.slack.snooze then "1" else "0"} \
      --subst-var-by hooks ${lib.escapeShellArg hooksStr} \
      --subst-var-by scenes ${scenesJson} \
      --subst-var-by switchAudio ${lib.escapeShellArg switchAudio}
    chmod 555 $out/bin/focus
  '';
  # Every address that asked for the focus pill, on either bar. The room's own
  # config is read here rather than contributed FROM here because the question
  # is the receiver's ("did someone ask?"), and the answer has to be available
  # when this room is off — which is exactly when nothing it writes exists.
  # Both bars, because `contributed` filters both and a warning that knew only
  # about the menu bar would leave the second one silent. Same shape as the AI
  # room's `pillAsks`, for the same reason.
  #
  # `widgets.focus.enable` is `mkDefault`ed from this room's contribution, so
  # with the room on it reads true and the warning below cannot fire; with the
  # room off it reads true only if someone WROTE it, which is the case worth a
  # sentence.
  #
  # DEFAULTED, and the first draft was not: `haus.bar.widgets` is an attrset
  # option, and the bundled pills are keys BAR'S IMPLEMENTATION writes into it,
  # not options the declaration file carries. So a standalone
  # `darwinModules.focus` — which imports every room's options.nix and only the
  # focus implementation — has the attrset and no `focus` key in it, and a bare
  # `.focus.enable` threw `attribute 'focus' missing` from a module that had
  # simply been imported on its own. Caught by `standalone-modules`, which is
  # the check shaped like exactly that caller.
  pillAsks =
    lib.optional (config.haus.bar.widgets.focus.enable or false) "haus.bar.widgets.focus.enable"
    ++ lib.optional (
      config.haus.bar.bottom.enable && (config.haus.bar.bottom.items.focus or false) != false
    ) "haus.bar.bottom.items.focus";
in
lib.mkMerge [
  {
    # OUTSIDE the enable gate, and that placement is the whole point: a room
    # that only speaks when it is on cannot tell you it is off. A pill with no
    # room behind it is not a smaller feature, it is a dead one — the bar drops
    # it (modules/bar's `contributed`), so without this the only trace is a
    # source comment. Not an assertion: the bar is correct without the pill, and
    # a rebuild that refused over one would be worse than its absence.
    warnings = lib.optional (pillAsks != [ ] && !cfg.enable) (
      "${lib.concatStringsSep " and " pillAsks} asks for the focus pill, but the Focus room is "
      + "off (haus.focus.enable). The pill's click runs ~/.local/bin/focus, which only that room "
      + "installs, so it would report nothing and toggle nothing — the bar leaves it out."
    );
  }
  (lib.mkIf cfg.enable {
    # A scene's name is what a person types after `focus scene`, so the four
    # words that subcommand already spends are names a scene could hold and never
    # be entered under — it would build, validate, appear in `focus scene list`,
    # and do nothing. `quiet` is the interesting one: it is a real scene, spelled
    # through slack/hooks rather than through `scenes`, and a second thing by that
    # name would be one the pill and the palette command could never reach.
    #
    # The shape rule sits here as well as in the desktop walk on purpose: that
    # walk runs on a DESKTOP, so a HOST writing `scenes."deep work"` would
    # otherwise get a name it can only reach through quoting it never sees.
    assertions =
      let
        reserved = [
          "list"
          "off"
          "quiet"
          "status"
        ];
        names = lib.attrNames cfg.scenes;
        claimed = lib.intersectLists reserved names;
        malformed = lib.filter (n: builtins.match "[A-Za-z0-9][A-Za-z0-9_-]*" n == null) names;
        # A window is read by a shell that can only answer yes or no, so a
        # misspelling has no way to complain at 09:00 — it just never matches.
        # That is the "degrades to silence" shape this layer refuses everywhere
        # else, and eval is the only place it can be caught.
        window = n: cfg.scenes.${n}.when.time;
        badWindow =
          n:
          window n != ""
          && builtins.match "([01][0-9]|2[0-3]):[0-5][0-9]-([01][0-9]|2[0-3]):[0-5][0-9]" (window n) == null;
        emptyWindow = n: window n != "" && lib.substring 0 5 (window n) == lib.substring 6 5 (window n);
        badWindows = lib.filter badWindow names;
        emptyWindows = lib.filter emptyWindow names;
      in
      [
        {
          assertion = claimed == [ ];
          message = ''
            haus.focus.scenes.${lib.concatStringsSep " / " claimed} uses a name
            `focus scene` already spends (${lib.concatStringsSep ", " reserved}).
            `quiet` is the built-in scene — the one `focus on`, the bar pill and
            the palette command enter; shape it with haus.focus.slack.* and
            haus.focus.hooks. The other three are subcommands. Rename the scene.
          '';
        }
        {
          assertion = malformed == [ ];
          message = ''
            haus.focus.scenes."${lib.concatStringsSep "\" / \"" malformed}" is not
            a plain scene name. A scene name is typed after `focus scene`, so it
            has to be one word: letters, digits, `_` and `-`, not starting with
            `-`.
          '';
        }
        {
          assertion = badWindows == [ ];
          message = ''
            haus.focus.scenes.${lib.concatStringsSep " / " badWindows}.when.time is
            not a daily window. Write it as HH:MM-HH:MM in 24-hour time, e.g.
            "09:00-17:00" — an end earlier than the start wraps midnight, so
            "22:00-06:00" is one night. The engine can only answer yes or no about
            a window, so anything else would simply never match.
          '';
        }
        {
          assertion = emptyWindows == [ ];
          message = ''
            haus.focus.scenes.${lib.concatStringsSep " / " emptyWindows}.when.time
            opens and closes at the same minute, so it can never hold and the
            scene would never be entered. For a whole day, leave `when.time`
            unset and say the rest of the condition instead.
          '';
        }
      ];

    # ---- what the room contributes to other rooms -------------------------------
    # Two writes, both inside this module's own `mkIf cfg.enable`, so each says
    # exactly "the Focus room exists on this machine". How that is presented is
    # the receiving room's business: bar decides whether the pill is drawn and
    # where, launcher decides which palette rows and cheatsheet entries it makes.
    # Neither reads `config.haus.focus.*` any more — see modules/lib/contrib.nix.
    #
    # The launcher's point carries the scenes as well as the switch, because a
    # scene becomes its own palette command and its own cheatsheet row. It gets
    # the ONE field it renders: `hooks`, `apps`, `audio` and `dnd` never cross,
    # so a rename inside a scene's shape cannot reach the launcher, and the
    # launcher's option surface never grows a copy of this room's.
    haus._contrib = {
      bar.focus.enable = true;
      launcher.focus = {
        enable = true;
        scenes = lib.mapAttrs (_: s: { inherit (s) description; }) cfg.scenes;
      };
    };

    # The reverse reach is still direct, and named rather than left to be found:
    # the watcher below reads `config.haus.bar.enable` / `.bottom.enable` to
    # decide which bars to poke. A room asking "does a bar exist" is the shape
    # `_contrib` exists to replace, and Bar declares no point pointing this way
    # yet. Same class as `page`'s read in modules/bar; its own change.
    #
    # Real-time pill sync for toggles focus didn't make (Control Center, iPhone
    # via Share Across Devices): launchd pokes the bar whenever the Focus DB
    # changes. launchd watches the path itself, so no Full Disk Access is
    # involved here; the pill's own state read is what may fall back. Harmless
    # no-op if sketchybar isn't up yet (cold boot).
    launchd.user.agents.focus-watcher = lib.mkIf config.haus.bar.enable {
      serviceConfig = {
        ProgramArguments = [
          "/bin/bash"
          "-c"
          ''
            /bin/sleep 1
            /run/current-system/sw/bin/sketchybar --trigger focus_change 2>/dev/null || true
            ${lib.optionalString config.haus.bar.bottom.enable "/run/current-system/sw/bin/bar-bottom --trigger focus_change 2>/dev/null || true"}
          ''
        ];
        WatchPaths = [ "/Users/${username}/Library/DoNotDisturb/DB" ];
        RunAtLoad = false;
      };
    };

    # The trigger daemon: one `focus auto` tick every interval, and only on a
    # machine where some scene declared a condition (`wantsTriggers`).
    #
    # RunAtLoad is FALSE on purpose, and it is the launchd GUI race rather than
    # taste: a tick can enter a scene, and entering one can `open -a` an app and
    # talk to System Events — both of which park at cold boot before the Aqua
    # session is up (see modules/lib/gui-wait.nix). Waiting one interval costs at
    # most `triggers.interval` seconds after login and needs none of that
    # machinery. It also loses nothing: the first tick after a fresh state file
    # treats whatever holds as an edge, so logging in at 09:30 inside a 09:00
    # window still lands in the scene.
    #
    # Logs go where every other agent in this repo puts them, and they are the
    # answer to the only question a trigger daemon ever gets asked — "why did my
    # Mac just go quiet?"
    launchd.user.agents.focus-auto = lib.mkIf wantsTriggers {
      serviceConfig = {
        ProgramArguments = [
          "${engine}/bin/focus"
          "auto"
        ];
        StartInterval = cfg.triggers.interval;
        RunAtLoad = false;
        StandardOutPath = "/tmp/focus-auto.out.log";
        StandardErrorPath = "/tmp/focus-auto.err.log";
      };
    };

    # The label the watcher ran under until 2026-08-16, when the room stopped
    # being called `hush`. Not `KeepAlive` like the bar's, so the worst case is an
    # orphan watcher poking a `hush_change` event nothing listens for — still not
    # something to leave running until logout. One-time, idempotent after.
    system.activationScripts.postActivation.text = ''
      /bin/launchctl bootout "gui/$(/usr/bin/id -u ${username})/org.nixos.hush-watcher" 2>/dev/null || true
    '';

    # All home wiring in ONE block (dynamic attr key), as a module function for
    # home-manager's extended lib (lib.hm.dag).
    home-manager.users.${username} =
      { lib, ... }:
      {
        # On PATH, because a room whose whole surface is a verb you type should
        # answer to that verb in a shell. The store path is the same one the
        # stable link below points at, so the two can never be different builds.
        home.packages = [ engine ];

        # A stable path every surface can call without PATH games — the pounce
        # daemon and sketchybar both run with minimal environments, and neither
        # gets the profile's bin dir.
        home.file.".local/bin/focus".source = "${engine}/bin/focus";

        # Bind symbolic hotkey 175 declaratively. -dict-add merges a single key
        # into AppleSymbolicHotKeys — it can never clobber your other hotkeys.
        # Idempotent, so re-asserting every activation is free and self-healing.
        # The `activateSettings -u` that makes it live without a logout used to sit
        # right here; core now runs one at the very end of activation (mkAfter, and
        # home-manager runs inside postActivation), which covers this write too.
        home.activation.focusHotkey = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run /usr/bin/defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys \
            -dict-add 175 '${hotkeyXml}'
        '';
      };
  })
]

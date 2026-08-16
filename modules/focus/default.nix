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

  engine = pkgs.runCommand "focus" { } ''
    mkdir -p $out
    substitute ${./focus.sh} $out/focus \
      --subst-var-by jq ${pkgs.jq}/bin/jq \
      --subst-var-by keyCode ${toString keyCode} \
      --subst-var-by slackEnabled ${if cfg.slack.enable then "1" else "0"} \
      --subst-var-by slackTokenCommand ${shq cfg.slack.tokenCommand} \
      --subst-var-by slackStatusText ${shq cfg.slack.statusText} \
      --subst-var-by slackStatusEmoji ${shq cfg.slack.statusEmoji} \
      --subst-var-by slackSnooze ${if cfg.slack.snooze then "1" else "0"} \
      --subst-var-by hooks ${lib.escapeShellArg hooksStr}
    chmod 555 $out/focus
  '';
in
lib.mkIf cfg.enable {
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
          /opt/homebrew/opt/sketchybar/bin/sketchybar --trigger focus_change 2>/dev/null || true
          ${lib.optionalString config.haus.bar.bottom.enable "/run/current-system/sw/bin/bar-bottom --trigger focus_change 2>/dev/null || true"}
        ''
      ];
      WatchPaths = [ "/Users/${username}/Library/DoNotDisturb/DB" ];
      RunAtLoad = false;
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
      # A stable path every surface can call without PATH games — the pounce
      # daemon and sketchybar both run with minimal environments.
      home.file.".local/bin/focus".source = "${engine}/focus";

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
}

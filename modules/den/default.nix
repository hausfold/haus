# Den — the foundation the rest of the house rests on. macOS system defaults,
# the Homebrew framework, core CLI tools, fonts, and periodic GC.
{
  config,
  options,
  lib,
  pkgs,
  username,
  ...
}:

let
  # `awake` is both an end-user CLI and the program behind its launchd-owned
  # caffeinate assertion. Keeping one derivation here means the optional bar
  # pill is only a view/controller; the wake lock survives bar/shell restarts.
  awake = pkgs.writeShellScriptBin "awake" (builtins.readFile ./awake.sh);

  # `hausax` — the effective appearance + accessibility oracle `haus diff`/`haus
  # plan` shell out to (and modules/theme, for systemAppearance). See
  # hausax.swift for why a plist read isn't enough on macOS 26.
  hausax = pkgs.callPackage ./package-hausax.nix { };

  homeDir = "/Users/${username}";

  # Whichever system.defaults.universalaccess.* keys the host actually set (they
  # all default to null upstream, so this is exactly the opt-ins).
  universalaccessSet = lib.attrNames (
    lib.filterAttrs (_: v: v != null) config.system.defaults.universalaccess
  );

  # The haus.accessibility.* keys the host actually set. Same domain as
  # above, deliberately NOT the same mechanism — see the block that writes them.
  a11ySet = lib.filterAttrs (_: v: v != null) {
    inherit (config.haus.accessibility) increaseContrast differentiateWithoutColor;
  };

  # haus.animations — one predicate, read by the two domains that carry the
  # group (the Dock's four keys and NSGlobalDomain's one). "system" writes
  # neither, which is why this is a mkIf at each key rather than a value.
  fastAnimations = config.haus.animations == "fast";

  devCfg = config.haus.developer;
  fontsCfg = config.haus.fonts;

  # ---- restart map (notes/macos-settings-matrix.md §4) ----------------------
  # See modules/lib/restart-map.nix for what each value means and why. The
  # typed domains here are unconditional because the rice writes every one of
  # them via mkDefault on every rebuild (dock.autohide, the finder block,
  # NSGlobalDomain's key-repeat pair, the trackpad trio, screencapture) —
  # unlike CustomUserPreferences, whose top-level domains genuinely vary by
  # which modules/host are loaded, so those are read out of config instead of
  # hardcoded.
  restartMap = import ../lib/restart-map.nix;
  typedDomainsWritten = [
    "com.apple.dock"
    "com.apple.finder"
    "NSGlobalDomain"
    "com.apple.AppleMultitouchTrackpad"
    "com.apple.screencapture"
    "com.apple.universalaccess"
    "com.apple.screensaver" # haus.lock
    "com.apple.menuExtraClock" # haus.menuBar.clock
    "com.apple.controlcenter" # haus.menuBar.controlCenter
  ];
  customPrefDomainsWritten = lib.attrNames config.system.defaults.CustomUserPreferences;
  domainsWritten = lib.unique (typedDomainsWritten ++ customPrefDomainsWritten);
  undeclaredDomains = builtins.filter (d: !(restartMap ? ${d})) domainsWritten;

  # Every restart action that names an actual process, deduplicated. A restart
  # map value is EITHER a process name or one of these four sentinels, so
  # subtracting the sentinels is what's left — a denylist, not an allowlist of
  # process names. That direction matters: an allowlist has to be edited in
  # lockstep with restart-map.nix, and the day someone adds a domain whose
  # value is a process not on the list, the map would say "restart X" and this
  # would silently drop it — reintroducing the exact hand-maintained gap
  # ../lib/restart-map.nix exists to close.
  #
  #   "Dock"             nix-darwin already restarts Dock itself whenever the
  #                      dock domain is set (which the rice always does), so
  #                      repeating it here just bounces the Dock twice per
  #                      rebuild for no benefit.
  #   "activateSettings" handled by the unconditional activateSettings call below.
  #   "notify:<name>"    a distributed notification, posted below — not a
  #                      process, so it is subtracted here by prefix rather
  #                      than by name (the name varies per domain).
  #   "none" / "logout"  no restart to give (or none this rice can give).
  notProcesses = [
    "Dock"
    "activateSettings"
    "none"
    "logout"
  ];
  # A map value is one verb or a list of them (NSGlobalDomain needs two), so
  # everything downstream reads the flattened action list.
  actionsWritten = lib.unique (lib.concatMap (d: lib.toList (restartMap.${d} or [ ])) domainsWritten);
  processesToRestart = lib.unique (
    builtins.filter (p: !(builtins.elem p notProcesses) && !(lib.hasPrefix "notify:" p)) actionsWritten
  );
  # The third verb (see ../lib/restart-map.nix): domains whose consumers are
  # every running app rather than one daemon. `hausax post-notification` does
  # the posting; nothing else in the rice can reach DistributedNotificationCenter.
  #
  # The map supplies the NAME — the load-bearing half, since a made-up
  # notification does nothing — but not the trigger. NSGlobalDomain is written
  # on every rebuild of every machine (key repeat, the springing pair), so
  # keying the post on domain membership alone would tell every app on every
  # Mac that its locale changed once a rebuild, forever, on configurations with
  # no locale opinion at all. Domain granularity cannot express "when a locale
  # key is declared", so the group names its own trigger here.
  localeDeclared = lib.any (v: v != null) (lib.attrValues localeCfg);
  notificationsToPost = lib.optionals localeDeclared (
    map (lib.removePrefix "notify:") (builtins.filter (lib.hasPrefix "notify:") actionsWritten)
  );

  # ---- hot corners ----------------------------------------------------------
  # The option names an action; com.apple.dock stores an integer. hot-corners.nix
  # is the one table both the enum and this lookup come from, so they cannot
  # disagree — see its header.
  hotCornerValue = lib.listToAttrs (
    map (a: lib.nameValuePair a.name a.value) (import ./hot-corners.nix)
  );
  # haus.hotCorners.<camelCase> → the wvous infix macOS uses.
  hotCornerKeys = {
    topLeft = "tl";
    topRight = "tr";
    bottomLeft = "bl";
    bottomRight = "br";
  };
  hotCornersSet = lib.filterAttrs (n: _: config.haus.hotCorners.${n} != null) hotCornerKeys;

  # ---- sound / locale / power (§5.6, spiked 2026-08-08) ----------------------
  soundCfg = config.haus.sound;
  localeCfg = config.haus.locale;
  powerCfg = config.haus.power;
  # 0–100 → the exponential macOS stores. See ../lib/alert-volume.nix.
  alertVolume = import ../lib/alert-volume.nix { inherit lib; };
  # An absolute path built from the enum, never a path the host typed. The
  # write is still guarded at activation (see the block below): macOS validates
  # nothing here and a path that doesn't resolve makes the alert SILENT rather
  # than falling back — and an eval-time `builtins.pathExists` cannot help,
  # because in pure evaluation it answers `false` for every /System path and
  # would skip the write on every machine.
  alertSoundPath =
    if soundCfg.alertSound == null then null else "/System/Library/Sounds/${soundCfg.alertSound}.aiff";

  # `pmset -b` (battery) / `-c` (charger) writes, as data. Deliberately NOT
  # nix-darwin's typed power.sleep.*: those shell out to `systemsetup`, which
  # takes no power source and — measured on 26.6.1 — wrote the AC profile while
  # the machine was running on battery, with its stderr discarded upstream.
  pmsetArgs =
    let
      timer = v: if v == "never" then "0" else toString v;
      flag = v: if v then "1" else "0";
      rows = [
        {
          key = "displaysleep";
          conv = timer;
          cfg = powerCfg.displaySleep;
        }
        {
          key = "sleep";
          conv = timer;
          cfg = powerCfg.computerSleep;
        }
        {
          key = "disksleep";
          conv = timer;
          cfg = powerCfg.diskSleep;
        }
        {
          key = "lowpowermode";
          conv = flag;
          cfg = powerCfg.lowPowerMode;
        }
      ];
      forSource =
        source: attr:
        lib.concatMap (
          r: lib.optional (r.cfg.${attr} != null) "-${source} ${r.key} ${r.conv r.cfg.${attr}}"
        ) rows;
    in
    forSource "b" "battery" ++ forSource "c" "charger";

  # ---- lock / menu bar / security --------------------------------------------
  lockCfg = config.haus.lock;
  clockCfg = config.haus.menuBar.clock;
  ccCfg = config.haus.menuBar.controlCenter;
  firewallCfg = config.haus.security.firewall;
  clockShowDateValue = {
    "when-space-allows" = 0;
    "always" = 1;
    "never" = 2;
  };

  # ---- screenshots ----------------------------------------------------------
  shotsCfg = config.haus.screenshots;
  # macOS stores `location` verbatim and expands nothing, so a "~/Pictures/…"
  # written literally into the plist is a path that does not exist — and
  # screencapture's response to a missing directory is to quietly use the
  # Desktop, which reads as "the option did nothing".
  shotsLocation =
    if shotsCfg.location == null then
      null
    else if lib.hasPrefix "~/" shotsCfg.location then
      "${homeDir}/${lib.removePrefix "~/" shotsCfg.location}"
    else
      shotsCfg.location;
  # The font package, from whichever of the three ways it was given. It moved to
  # ../lib/mono-font.nix when the wallpaper's debug band started needing the same
  # answer — den installs the family, wallpaper reads a face out of it.
  monoPackage = import ../lib/mono-font.nix {
    inherit lib pkgs;
    fonts = fontsCfg;
  };

  # Naming a family the rice was never given a package for is silent tofu:
  # Ghostty just falls back and the powerline/icon glyphs vanish. Cheap to spot.
  fontFamilyUnprovided =
    fontsCfg.mono.package == null
    && fontsCfg.mono.packageName == null
    && fontsCfg.mono.name != options.haus.fonts.mono.name.default;
in
{
  system.primaryUser = username;

  # ---- warn: system.defaults.universalaccess.* fails loudly without FDA -------
  # `com.apple.universalaccess` is TCC-protected. Writing it requires the app
  # RESPONSIBLE for the rebuild to hold Full Disk Access — nix-darwin runs
  # `defaults write` from the activation script, so the grant that matters is
  # the terminal (or agent) you invoked `darwin-rebuild` from, not root. Without
  # it the write fails with "Could not write domain" and exit 1.
  #
  # That alone would be a papercut. What makes it worth a warning is the blast
  # radius: nix-darwin emits the write UNGUARDED into an activation script that
  # runs under `set -e`, roughly two thirds of the way in. So the non-zero exit
  # ABORTS activation and silently skips everything after it — the Dock restart
  # and every launchd daemon and user agent (awake, aerospace, hush-watcher,
  # pounce, sketchybar). The symptom (services missing) appears nowhere near the
  # cause, which is why upstream reports of this are so confused.
  #
  # Deliberately a warning, NOT an assertion: with FDA granted these options do
  # work, so blocking them would be wrong. We just make the failure legible in
  # advance. Drop this once upstream guards the writes.
  #   https://github.com/nix-darwin/nix-darwin/issues/1049
  warnings =
    lib.optional fontFamilyUnprovided ''
      nebelhaus: fonts.mono.name is "${fontsCfg.mono.name}" but neither
      fonts.mono.package nor fonts.mono.packageName is set.

      The rice only installs the font it's given, so unless that family is already
      on the machine Ghostty will fall back silently — and the fallback won't be a
      Nerd Font, so starship's prompt, lsd's icons and yazi previews render as
      tofu. Name the matching package: fonts.mono.packageName =
      "nerd-fonts.fira-code" (or fonts.mono.package = pkgs.nerd-fonts.fira-code,
      outside a data-only rice).
    ''
    ++ lib.optional (universalaccessSet != [ ]) ''
      nebelhaus: system.defaults.universalaccess is set (${lib.concatStringsSep ", " universalaccessSet}).

      That domain is TCC-protected. It writes only if the app you run the rebuild
      FROM holds Full Disk Access (System Settings ▸ Privacy & Security ▸ Full
      Disk Access) — on macOS 26 a stale grant often needs removing and re-adding
      with the (+) button, then restarting the terminal.

      Without that grant the write exits 1, and because nix-darwin emits it
      unguarded into an activation script running under `set -e`, activation
      ABORTS there and skips the rest — including every launchd service the rice
      installs (awake, aerospace, hush-watcher, pounce, sketchybar). If a rebuild
      ever half-completes, this is the first thing to check.

      haus.accessibility.* reaches the two useful keys in this domain
      (increaseContrast, differentiateWithoutColor) WITHOUT that hazard — it
      guards the write, so a missing grant costs you the setting and nothing else.
    ''
    ++ lib.optional (undeclaredDomains != [ ]) ''
      nebelhaus: these plist domains are written but have no entry in
      modules/lib/restart-map.nix: ${lib.concatStringsSep ", " undeclaredDomains}.

      A domain with no declared restart silently waits for the user to log out
      to take effect. In the rice's own modules this is a bug — add the domain
      to restart-map.nix. If you got here from `haus capture <domain>` on your
      own host file, this is just a heads-up: that domain isn't a plist this
      rice ships a restart for, so if it doesn't take effect right away, log
      out once and it will.
    '';

  # Two ways to say the same thing, and no way to rank them: `package` is a
  # derivation, `packageName` a string that resolves to one, and if they differ
  # whichever the resolver happened to prefer would install silently. Refuse
  # instead — the fix is deleting a line, which is the cheapest kind of error.
  assertions = [
    {
      assertion = !(fontsCfg.mono.package != null && fontsCfg.mono.packageName != null);
      message = ''
        nebelhaus: fonts.mono.package and fonts.mono.packageName are both set.
        They are the same setting written two ways — `package` for a module that
        has `pkgs`, `packageName` for a data-only rice that doesn't. Keep one.
      '';
    }
    {
      # `null` and `[ ]` are worlds apart for this one option, and the type
      # cannot tell them apart: null means "leave my layouts alone", while an
      # empty list literally means "the complete set of keyboard layouts is
      # none" — a Mac you cannot type on. Nothing downstream would look wrong.
      assertion = localeCfg.inputSources != [ ];
      message = ''
        nebelhaus: haus.locale.inputSources is an empty list.

        That option is EXHAUSTIVE — a list is the whole set of keyboard layouts,
        so an empty one asks for a Mac with no way to type. Use `null` (the
        default) to leave your layouts alone, or name at least one id:
        `hausax input-sources --all` lists them.
      '';
    }
  ];

  # ---- haus.accessibility → com.apple.universalaccess -------------------
  # Writes the two keys in that domain measured to write AND take effect on
  # macOS 26 (checked against NSWorkspace, not a plist read-back).
  #
  # NOT via system.defaults.CustomUserPreferences, which would be the obvious
  # route: that funnels through the exact same generator as the typed options
  # warned about above — an UNGUARDED `defaults write` in an activation script
  # running under `set -e`. Without Full Disk Access the write exits 1 and takes
  # the remainder of activation with it, including every launchd service. Since
  # the grant belongs to the app invoking the rebuild, an agent-driven
  # `haus rebuild` would break on a config that works by hand — the worst kind
  # of "works on my machine".
  #
  # So we emit the same command shape ourselves, guarded: on refusal, say why
  # and carry on. Degrading to "the setting didn't apply" is the correct
  # failure; a half-activated Mac is not.
  system.activationScripts.postActivation.text = lib.mkMerge [
    (lib.optionalString (a11ySet != { }) ''
      nebelhausAccessibility() {
        if launchctl asuser "$(id -u -- ${username})" sudo --user=${username} -- \
             defaults write com.apple.universalaccess "$1" -bool "$2" 2>/dev/null; then
          echo "accessibility: $1 = $2" >&2
        else
          echo "warning: accessibility: could not set $1 — com.apple.universalaccess needs Full Disk Access on the app running this rebuild. Setting skipped; nothing else was affected." >&2
        fi
      }
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: "nebelhausAccessibility ${k} ${lib.boolToString v}") a11ySet
      )}
    '')

    # ---- haus.sound.alertSound → com.apple.sound.beep.sound ----------------
    # Guarded rather than declared, and the guard is the whole point: macOS
    # stores an absolute path here and validates nothing, and a path that does
    # not resolve makes the alert beep SILENT — it does not fall back to the
    # default (measured by ear, 2026-08-08). The plist still reads like a
    # working setting, so the failure is invisible from every direction except
    # the machine having stopped beeping. `system.defaults` cannot express
    # "write this only if the file exists", and an eval-time check cannot
    # either: in pure evaluation `builtins.pathExists "/System/…"` is false, so
    # a config that worked by hand would silently skip the write in CI.
    (lib.optionalString (alertSoundPath != null) ''
      if [ -f ${lib.escapeShellArg alertSoundPath} ]; then
        launchctl asuser "$(id -u -- ${username})" sudo --user=${username} -- \
          defaults write -g com.apple.sound.beep.sound -string ${lib.escapeShellArg alertSoundPath} \
          || echo "warning: sound: could not write the alert sound. Setting skipped; nothing else was affected." >&2
      else
        echo "warning: sound: ${alertSoundPath} is missing on this macOS — alert sound left alone (writing it would silence the beep, not fall back)." >&2
      fi
    '')

    # ---- haus.sound.startupChime → nvram StartupMute ------------------------
    # Firmware, not a preference: it survives an OS reinstall and a wiped home
    # directory, and it is the one setting in this group that needs root, which
    # activation already is. `%01` mutes; DELETING the variable is how you get
    # the chime back, since an unset StartupMute is the factory state and a
    # `%00` is not the same thing on every model.
    (lib.optionalString (soundCfg.startupChime != null) (
      if soundCfg.startupChime then
        ''
          nvram -d StartupMute 2>/dev/null || true
        ''
      else
        ''
          nvram StartupMute=%01 || echo "warning: sound: could not mute the startup chime (nvram write refused)." >&2
        ''
    ))

    # ---- haus.locale.inputSources → the Text Input Sources API --------------
    # THE ONE EXHAUSTIVE OPTION in §5.6's groups: a non-null list is the whole
    # set of keyboard layouts, so anything enabled and unnamed gets disabled.
    # "Add and never remove" would make a rice that can only ever accumulate
    # layouts. Non-keyboard input methods (emoji picker, press-and-hold) are
    # not layouts and hausax never touches them.
    #
    # Enable first, then disable, so the machine is never briefly left with no
    # layout at all — and so a selected layout being retired hands over to one
    # that already exists rather than to nothing.
    (lib.optionalString (localeCfg.inputSources != null && localeCfg.inputSources != [ ]) ''
      hausInputSource() {
        if ! launchctl asuser "$(id -u -- ${username})" sudo --user=${username} -- \
             ${lib.getExe hausax} input-source "$1" "$2" 2>/dev/null; then
          echo "warning: locale: could not $1 $2 — is it a real input source id? (\`hausax input-sources --all\`)" >&2
          return 1
        fi
      }
      hausInputSourcesNow() {
        launchctl asuser "$(id -u -- ${username})" sudo --user=${username} -- \
          ${lib.getExe hausax} input-sources 2>/dev/null
      }
      ${lib.concatMapStringsSep "\n" (
        id: "hausInputSource enable ${lib.escapeShellArg id} || true"
      ) localeCfg.inputSources}

      # The disable pass runs ONLY once at least one declared layout is really
      # enabled. Without this check, a list of ids that are all typo'd —
      # "US" instead of "com.apple.keylayout.US" — warns four times and then
      # disables everything that WAS working, and a Mac with no keyboard layout
      # is a Mac you cannot type on. `hausax input-source disable` refuses to
      # remove the last one as a second line of defence; this is the first.
      declared=${lib.escapeShellArg (lib.concatStringsSep "\n" localeCfg.inputSources)}
      landed=0
      for enabled in $(hausInputSourcesNow); do
        if printf '%s\n' "$declared" | grep -qxF "$enabled"; then landed=1; fi
      done
      if [ "$landed" = 0 ]; then
        echo "warning: locale: none of the declared input sources could be enabled, so nothing was disabled either — the machine keeps the layouts it had. Check the ids with \`hausax input-sources --all\`." >&2
      else
        for enabled in $(hausInputSourcesNow); do
          if ! printf '%s\n' "$declared" | grep -qxF "$enabled"; then
            hausInputSource disable "$enabled" || true
          fi
        done
      fi
    '')

    # ---- haus.power.* → pmset ----------------------------------------------
    # Not nix-darwin's typed power.sleep.*: those call `systemsetup`, which has
    # no power-source selector, and on 26.6.1 wrote the AC profile while the
    # machine was on battery — silently, since upstream discards its output.
    # `pmset -b` / `-c` names the source it means. Root, which activation is.
    (lib.optionalString (pmsetArgs != [ ]) ''
      ${lib.concatMapStringsSep "\n" (
        args: "pmset ${args} || echo \"warning: power: pmset ${args} was refused.\" >&2"
      ) pmsetArgs}
    '')

    # ---- restart map (notes/macos-settings-matrix.md §4) --------------------
    # Every process below reads its plist domain once, at LAUNCH — the finder
    # sort order, the view style and the POSIX-path title, the Control Center
    # layout — are baked into the running process the moment it starts.
    # nix-darwin restarts the Dock after writing user defaults and stops
    # there, so without this a rebuild that changed, say, a Finder key looks
    # like it did nothing until the next login. launchd relaunches each
    # process immediately; the cost (same one nix-darwin's own Dock restart
    # already pays) is that its open windows close.
    #
    # `processesToRestart` is generated from modules/lib/restart-map.nix
    # against whatever plist domains this configuration actually writes —
    # not hardcoded to Finder the way rice#181 first shipped this, so a
    # future domain (Control Center, say) restarts correctly the day
    # something starts writing into it, with no second fix needed here.
    (lib.optionalString (processesToRestart != [ ]) ''
      ${lib.concatMapStringsSep "\n" (proc: "killall -qu ${username} ${proc} || true") processesToRestart}
    '')

    # ---- make the preferences we just wrote LIVE, without a logout ----------
    # nix-darwin writes every system.defaults key with `defaults write` and then
    # restarts the Dock — and stops there. So Dock/Finder keys land, but
    # everything the WindowServer, HIToolbox or the input stack caches sits in
    # the plist until the next login: key repeat, the trackpad trio,
    # _HIHideMenuBar and SLSMenuBarUseBlurredAppearance (both of which sill
    # depends on). Changing the rice and being told "log out to see it" is the
    # single most confusing thing a rebuild can do.
    #
    # activateSettings is the private binary System Settings itself calls to
    # broadcast a preference change. Upstream has declined to run it for years
    # (nix-darwin#658, #967, #1475), so the rice does it. It must run AS THE
    # USER — activation is root, and root's preference domain is not the one we
    # just wrote — hence the same launchctl-asuser shape as the block above.
    #
    # mkAfter, so it is the LAST thing in postActivation: after nix-darwin's own
    # defaults writes, after home-manager's activation (which is itself emitted
    # into postActivation, and is where hush's DND hotkey and pounce's Spotlight
    # write land), and after the accessibility block above. One call covers all
    # of them, which is why none of those sites run their own any more.
    #
    # Unconditional and unguarded by an option: it is ~0.2s, idempotent, exits 0,
    # and there is no coherent machine that wants its declared preferences left
    # unapplied. `|| true` because a future macOS may move or drop the binary —
    # losing the refresh is a papercut, aborting activation is not.
    (lib.mkAfter ''
      activateSettings=/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings
      if [ -x "$activateSettings" ]; then
        launchctl asuser "$(id -u -- ${username})" sudo --user=${username} -- \
          "$activateSettings" -u || true
      fi
    '')

    # ---- the restart map's third verb: distributed notifications ------------
    # activateSettings does NOT stand in for these. The locale family's
    # consumers are every running app rather than one daemon, and a
    # `defaults write` there reaches newly launched processes only — measured
    # on 26.6.1, an app already running keeps its old locale indefinitely, even
    # through Locale.autoupdatingCurrent, until
    # AppleDatePreferencesChangedNotification is posted. A made-up name does
    # nothing, so the name in restart-map.nix is load-bearing.
    #
    # As the user, for the same reason activateSettings is: root's session is
    # not the one with the apps in it. mkAfter after the block above so the
    # post is the last thing that happens, once the writes are all in.
    (lib.mkAfter (
      lib.optionalString (notificationsToPost != [ ]) ''
        ${lib.concatMapStringsSep "\n" (n: ''
          launchctl asuser "$(id -u -- ${username})" sudo --user=${username} -- \
            ${lib.getExe hausax} post-notification ${lib.escapeShellArg n} || true
        '') notificationsToPost}
      ''
    ))
  ];

  programs.zsh.enable = true;

  # Core CLI tools. The shell *experience* (aliases, starship, git, yazi, …) is
  # yours to add in your host file; these are the baseline binaries the rice and
  # its commands lean on.
  # Split by the developer pack. What stays unconditional is the PRODUCT — the
  # tools a nebelhaus machine needs to be a nebelhaus machine even if its owner
  # never opens a terminal by choice. Everything else is gated, because
  # "minimal" used to install the whole dev toolbelt regardless.
  environment.systemPackages =
    with pkgs;
    [
      # The everyday end-user CLI: haus rebuild / update / rollback / status /
      # edit / doctor — so a nebelhaus machine never needs raw nix incantations.
      # System-wide (not home-manager) so sudo and non-login shells see it too.
      # (The workshop's developer CLI is `bench` — a different name on purpose,
      # so the two never shadow each other.)
      (writeShellScriptBin "haus" (builtins.readFile ./haus.sh))

      # `haus-activate <system>` — the privileged half of a rebuild, split out
      # so the config is evaluated ONCE. `darwin-rebuild switch --flake` builds
      # again as root, against root's own eval + lazy-trees caches, which is a
      # duplicate of the build `haus` (and `bench try`) just did as you. Ships
      # unconditionally beside `haus` because `haus rebuild` calls it, and it
      # must sit at a stable /run/current-system path for collar's
      # passwordless-sudo rule to match it. See the script's header.
      (writeShellScriptBin "haus-activate" (builtins.readFile ./haus-activate.sh))

      # The oracle `haus diff`/`haus plan` (and modules/theme's appearance block)
      # use to tell a declared setting that actually took effect from one macOS
      # silently ignored — see hausax.swift.
      # Unconditional beside `haus`, for the same reason: both are the product,
      # not the developer toolbelt.
      hausax

      # The annotated host file — every haus.* option at its default, with
      # its description and a docs link, all commented out — installed at
      # share/nebelhaus/host-options.nix. `haus options` copies it beside your
      # host file; nothing reads it at runtime.
      #
      # Shipped in the system profile rather than fetched on demand so `haus
      # options` describes the revision this machine is PINNED to, the same
      # reason the Claude skill is built rather than committed. It also makes
      # the command instant and offline — a fresh Mac's copy comes from
      # bootstrap's `nix build .#host-template`, which is the only path that
      # has no system to read it out of yet.
      #
      # It needs the pathsToLink line below to actually appear: system-path is a
      # buildEnv that links a FIXED list of subdirectories, and share/nebelhaus
      # isn't on it — the package built, went into the closure, and left nothing
      # at /run/current-system/sw/share/nebelhaus.
      (import ../host-template.nix { inherit pkgs; })

      # `awake 3h` / `awake indefinitely` — a durable controller around macOS's
      # built-in caffeinate. Its assertion is launchd-owned below, so callers can
      # exit (or SketchyBar can reload) without accidentally allowing idle sleep.
      awake

      # Installs App Store apps for the roster; nothing to do with writing code.
      mas
    ]
    # The themed CLI toolbelt the rice's shell is built around.
    ++ lib.optionals devCfg.toolbelt.enable [
      bat
      fzf
      glow
      jq
      lsd
      # ripgrep isn't just a nicer grep here: hearth's ⌘F overlay
      # (modules/hearth/zellij/find.sh) shells out to `rg` on every keystroke,
      # off an explicit thin PATH that only sees these profiles. Without it the
      # overlay opens and stays empty forever, with no error anywhere.
      ripgrep
      tree
      ttyd
      fastfetch
    ]
    # Git and its surroundings. gnupg is here rather than in the product set
    # because the only thing the rice uses it for is commit signing.
    ++ lib.optionals devCfg.git.enable [
      delta
      gh
      gnupg
      lazygit
    ]
    ++ lib.optionals devCfg.agents.enable [
      # holt — agent worktrees, its own product now (hausfold/holt, taken as
      # a flake input). Every caller the rice owns is on it: hearth's
      # ⌘A runs `holt new`, pounce's Spawn Agent goes through `holt spawn`, and
      # the Claude Code WorktreeCreate/WorktreeRemove hooks — which hearth
      # DECLARES into ~/.claude/settings.json and re-asserts on every rebuild
      # (see modules/hearth, home.activation.claudeCodeSettings) — point at
      # `holt hook create` / `holt hook remove`. Its bash predecessor `wt.sh`
      # has been retired entirely; there is no fallback to roll back to.
      holt

      # `zscratch` — feel-test a candidate zellij config / layout / plugin.wasm in
      # a throwaway session in its OWN Ghostty window, WITHOUT a rebuild. Renders
      # your edit over a copy of the live ~/.config/zellij into a temp config-dir
      # and boots a fresh scratch session (its own name → its own server →
      # recompiled wasm), so the working `main` session's tabs stay untouched.
      # Moves the iterate-loop off `bench try switch` + restart; you rebuild once,
      # at the end, already knowing it works. Lives here (not hearth) because it's
      # a dev CLI on PATH like `haus`/`holt`, though it drives hearth's zellij dotfiles.
      (writeShellScriptBin "zscratch" (builtins.readFile ./zscratch.sh))

      # `claude-statusline` — the agent-worktree HUD for Claude Code's status bar
      # (hearth's claudeCodeSettings points the `statusLine` key here). Row 1 is
      # THIS session's worktree name + one status token (⏏ purge / N^ commits —
      # blue when unmerged, orange when they landed AFTER the PR merged and no PR
      # covers them / +A -D uncommitted); rows below list sister `holt` worktrees across
      # ALL repos, with GitHub PR state. Cheap local git runs in the render path;
      # the cross-repo + `gh` enumeration is done detached by the companion
      # `claude-statusline-refresh` and cached (stale-while-revalidate), so the bar
      # never blocks. Reads `holt`'s registry — same agent-worktree flow, same home.
      # It doubles as the writer for sill's `claudeUsage` pill: Claude Code hands
      # every render the account's 5-hour + weekly rate-limit percentages, so the
      # render path stashes them to ~/.cache/claude-statusline/usage.tsv — the
      # cheapest possible source, with no keychain read and nothing polling.
      (writeShellScriptBin "claude-statusline" (builtins.readFile ./statusline.sh))
      (writeShellScriptBin "claude-statusline-refresh" (builtins.readFile ./statusline-refresh.sh))

      # `agent-state` — the one writer of agent-pane state, feeding sill's `agents`
      # paw and hearth's zellij tab-bar badge. BYTE-FOR-BYTE the script sill also
      # installs as ~/.config/sketchybar/plugins/agents-hook.sh (read from there,
      # so the two can never drift); this copy exists only to give it a stable
      # name on PATH. Claude Code's hooks point at the sketchybar path because the
      # user's own settings.json wires them, but the Codex and Opencode wirings
      # hearth writes are client config files with no business knowing where a bar
      # keeps its plugins — they call
      # `agent-state <working|waiting|idle|remove> <client>` instead.
      (writeShellScriptBin "agent-state" (builtins.readFile ../sill/sketchybar/plugins/agents-hook.sh))
    ];

  # system-path links a fixed set of subdirectories out of everything in
  # environment.systemPackages — /bin, /share/man, /share/zsh and a handful more.
  # Anything else a package installs is in the closure but reachable at no path,
  # which is exactly what happened to the host template above: it built, it was
  # a dependency of the system, and /run/current-system/sw/share/nebelhaus did
  # not exist. `haus options` reads it from there, so the directory has to be linked.
  environment.pathsToLink = [ "/share/nebelhaus" ];

  # The job is intentionally always present, even when the opt-in Sill pill is
  # hidden: `awake` is a rice-level capability usable from any shell. RunAtLoad
  # resumes an unexpired timed assertion (with only its remaining duration), or
  # an explicit indefinite one, after login/rebuild. With no saved state it
  # exits immediately and launchd does not restart it.
  launchd.user.agents.awake = {
    serviceConfig = {
      Label = "org.nebelhaus.awake";
      ProgramArguments = [
        "${awake}/bin/awake"
        "_run"
      ];
      RunAtLoad = true;
      ProcessType = "Background";
      StandardOutPath = "/tmp/nebelhaus-awake.out.log";
      StandardErrorPath = "/tmp/nebelhaus-awake.err.log";
      EnvironmentVariables.HOME = "/Users/${username}";
    };
  };

  # ---- Homebrew framework ---------------------------------------------------
  # den owns the framework + policy; feature modules (prowl, sill) contribute
  # their own taps/casks/brews, which nix-darwin merges into these lists.
  homebrew = {
    enable = true;
    onActivation = {
      # Policy is host-tunable (see modules/options.nix). Safe defaults: never
      # auto-update/upgrade (keeps rebuilds reproducible) and never delete
      # undeclared casks (cleanup = "none") so the rice can't eat an app you
      # installed yourself. A declarative-minded host can opt into "zap".
      inherit (config.haus.homebrew) autoUpdate upgrade cleanup;
    };

    # No casks here on purpose. den's own (ghostty) is a roster entry below,
    # like every other app on the machine — a host adding a leader key for the
    # terminal shouldn't have to know whether the rice already installed it. A
    # raw `homebrew.casks = [ ... ]` still merges in from anywhere, for the rare
    # cask that isn't an app at all.
  };

  # The terminal the rice is themed for. mkDefault so a host can point the entry
  # at a different build — or null the cask and install ghostty its own way — by
  # app id, without touching this file. prowl adds the leader key and workspace
  # when tiling is on; with prowl off this is just an install.
  haus.roster.ghostty = {
    name = lib.mkDefault "Ghostty";
    cask = lib.mkDefault "ghostty";
  };

  # ---- Fonts ----------------------------------------------------------------
  # The rice's terminal font, from haus.fonts.mono. JetBrains Mono Nerd
  # Font is the default because a Nerd Font is load-bearing here: starship's
  # powerline prompt, lsd's icons, and yazi all draw with patched glyphs that a
  # stock font renders as tofu. hearth points Ghostty at whatever this resolves
  # to — and so does SILL, since the bar stopped naming a family of its own, so
  # this package is now the one the menu bar draws in too. `fonts.packages` is a
  # list option, so it merges with the one font sill still installs for itself:
  # sketchybar-app-font, for the workspace logos.
  fonts.packages = [ monoPackage ];

  # Homebrew's tap-trust check is flaky under sudo-driven activation (the
  # per-user trust store gets bypassed), so third-party taps fail with "Refusing
  # to load cask … from untrusted tap". We curate our taps ourselves; disable the
  # requirement globally via a brew.env that `bin/brew` reads on every call.
  #
  # HOMEBREW_API_AUTO_UPDATE_SECS only bites hosts that set
  # `haus.homebrew.autoUpdate = true` (the rice default is false, which
  # disables the check outright). For those, brew re-downloads its ~15 MB
  # formula/cask JSON API whenever the last check is older than the window —
  # and the stock window is 450 s, so any two rebuilds more than 7½ minutes
  # apart each pay for it. An hour still picks up a same-day cask release on
  # the next rebuild, without re-fetching the catalogue mid-iteration.
  #
  # HOMEBREW_NO_ENV_HINTS silences the "Disable this behaviour by setting
  # HOMEBREW_…" tips brew volunteers after a bundle run. They're advice for a
  # human at a prompt; here they land mid-rebuild log, in a run nobody typed,
  # naming knobs this file already decides. hearth exports the same variable in
  # `home.sessionVariables`, which is why your OWN `brew install` is already
  # quiet — but that never reaches the rebuild, because nix-darwin activates the
  # bundle as `sudo --preserve-env=PATH --user=… env … brew bundle` and every
  # other variable is reset. Only brew.env survives that, because `bin/brew`
  # reads it itself on each call. Hence both, and hence not bench either.
  environment.etc."homebrew/brew.env".text = ''
    HOMEBREW_NO_REQUIRE_TAP_TRUST=1
    HOMEBREW_API_AUTO_UPDATE_SECS=3600
    HOMEBREW_NO_ENV_HINTS=1
  '';

  # ---- macOS defaults -------------------------------------------------------
  # These are the rice's OPINIONS, so every value is lib.mkDefault: a host file
  # can override any of them with a plain value and win, no conflict. That's how
  # the bootstrap's "keep your current settings" capture works — it writes your
  # existing values into the host's system.defaults, overriding these. The
  # exceptions are the two menu-bar keys below (_HIHideMenuBar and
  # SLSMenuBarUseBlurredAppearance): not opinions but functions of Sill (the bar
  # must be hidden for Sill to replace it, and opaque so its hover-reveal covers
  # Sill), so they track sill.enable and stay rice-controlled.
  system.defaults = {
    dock = {
      # The one macOS-side size ui.scale can move honestly. Set ONLY when you've
      # actually asked for scaling: at scale 1.0 the rice writes nothing, so a
      # Dock you sized by hand is left alone rather than snapped back to Apple's
      # 48. Same principle as wallpaper.style = "none" — don't move what wasn't
      # asked about.
      tilesize = lib.mkIf (config.haus.ui.scale != 1.0) (
        lib.mkDefault (builtins.floor (48 * config.haus.ui.scale + 0.5))
      );
      autohide = lib.mkDefault true;
      show-recents = lib.mkDefault false;
      mru-spaces = lib.mkDefault false;
      orientation = lib.mkDefault "bottom";

      # ---- haus.animations ---------------------------------------------------
      # The Dock's four motion timings. mkIf, so `animations = "system"` writes
      # nothing at all and a Dock someone tuned by hand keeps its own numbers —
      # same principle as tilesize above. Live at the end of activation without
      # a logout: nix-darwin restarts the Dock whenever ANY typed key in this
      # domain is set, and autohide directly above guarantees one always is.
      #
      # Note what is NOT here: autohide-DELAY. That's how long the Dock waits
      # before it starts, which is a pointing preference, not motion — and with
      # a bottom Dock, zeroing it means the Dock flies out every time the
      # pointer grazes the bottom edge on its way somewhere else.
      autohide-time-modifier = lib.mkIf fastAnimations (lib.mkDefault 0.15);
      expose-animation-duration = lib.mkIf fastAnimations (lib.mkDefault 0.1);
      launchanim = lib.mkIf fastAnimations (lib.mkDefault false);
      mineffect = lib.mkIf fastAnimations (lib.mkDefault "scale");
    }
    # ---- hot corners -------------------------------------------------------
    # Emitted ONLY for the corners the host actually named. Not mkDefault and
    # not a rice opinion: nebelhaus ships every corner at null, so this block is
    # empty on a stock rice and the corners you set in System Settings years ago
    # survive a rebuild untouched. Naming one is the whole opt-in.
    #
    # Lands in the same com.apple.dock domain the block above writes, which
    # means it inherits nix-darwin's Dock restart for free — that restart fires
    # whenever ANY typed dock option is set, and the rice always sets autohide.
    # So a corner is live the moment activation finishes, no logout.
    // lib.mapAttrs' (
      n: k: lib.nameValuePair "wvous-${k}-corner" hotCornerValue.${config.haus.hotCorners.${n}}
    ) hotCornersSet;
    # The rice's Finder is aimed at someone who thinks in paths: everything
    # visible, sorted the way a Linux file manager sorts, navigable from the
    # keyboard, and never guessing where you meant to look.
    finder = {
      AppleShowAllExtensions = lib.mkDefault true;
      AppleShowAllFiles = lib.mkDefault true;
      FXPreferredViewStyle = lib.mkDefault "Nlsv"; # list view
      ShowPathbar = lib.mkDefault true;
      ShowStatusBar = lib.mkDefault true;

      # Directories before files, the way Nautilus/Dolphin/`ls --group-directories-first`
      # do it. Apple interleaves them, so a project root buries its dirs among
      # dotfiles and READMEs.
      _FXSortFoldersFirst = lib.mkDefault true;
      _FXSortFoldersFirstOnDesktop = lib.mkDefault true;

      # The window title becomes the full POSIX path, so a tiled Finder window
      # says where it is — and ⌘-clicking the title still walks the ancestry.
      _FXShowPosixPathInTitle = lib.mkDefault true;

      # ⌘F searches the folder you're standing in. Apple's default ("This Mac")
      # turns every search into a whole-disk Spotlight crawl you then have to
      # narrow by hand.
      FXDefaultSearchScope = lib.mkDefault "SCcf";

      # ⌘N opens $HOME, not "Recents" — a flat list with no path, no hierarchy
      # and no way to go up. (nix-darwin maps this name to PfHm for you.)
      NewWindowTarget = lib.mkDefault "Home";

      # Renaming notes.txt → notes.md is a normal edit, not a modal-worthy
      # event; extensions are always visible above, so nothing is hidden.
      FXEnableExtensionChangeWarning = lib.mkDefault false;

      # macOS's default: no ⌘Q in Finder. We used to turn it on — Finder does
      # relaunch the instant you open a folder — but the rice's GUI agents key
      # off Finder as the "is the Aqua session up" signal, so a hand-quit Finder
      # is a session state nothing else produces, and it only ever surfaced as
      # something else being broken (pounce's hotkey going dead). Not worth a
      # menu item nobody asked for. Set true in your host if you want it back.
      QuitMenuItem = lib.mkDefault false;

      # Column view sizes columns to the names actually in them.
      _FXEnableColumnAutoSizing = lib.mkDefault true;

      # The desktop is wallpaper (theme draws the wordmark on it), not a mount
      # table — volumes stay one click away in the sidebar, where you can also
      # eject them.
      ShowExternalHardDrivesOnDesktop = lib.mkDefault false;
      ShowHardDrivesOnDesktop = lib.mkDefault false;
      ShowMountedServersOnDesktop = lib.mkDefault false;
      ShowRemovableMediaOnDesktop = lib.mkDefault false;
    };
    NSGlobalDomain = {
      ApplePressAndHoldEnabled = lib.mkDefault false; # key repeat, not the accent picker
      KeyRepeat = lib.mkDefault 2;
      InitialKeyRepeat = lib.mkDefault 15;
      AppleShowAllExtensions = lib.mkDefault true;

      # ---- haus.animations ---------------------------------------------------
      # The one key in the group that isn't the Dock's: AppKit's window
      # open/close animation. Unlike its four Dock siblings this is read by each
      # app AT LAUNCH, so apps already running keep animating until relaunched —
      # activateSettings invalidates the preference cache, it doesn't reach back
      # into a live NSApplication. Worth knowing before you conclude it didn't
      # apply.
      NSAutomaticWindowAnimationsEnabled = lib.mkIf fastAnimations (lib.mkDefault false);

      # ---- the half of Finder that lives in NSGlobalDomain -------------------
      # Tab reaches every control in a dialog, not just text fields and lists —
      # the prerequisite for answering a save/replace sheet without the mouse.
      # 2 is the Sonoma-and-later encoding of "all controls"; 3 is the old one.
      AppleKeyboardUIMode = lib.mkDefault 2;

      # Save/Open panels open EXPANDED: a real file browser with the sidebar and
      # ⌘⇧G path entry, instead of the one-line popup that only offers Recents.
      NSNavPanelExpandedStateForSaveMode = lib.mkDefault true;
      NSNavPanelExpandedStateForSaveMode2 = lib.mkDefault true;

      # New documents default to this disk. iCloud Drive is a choice, not the
      # place an untitled file should land because you didn't look.
      NSDocumentSaveNewDocumentsToCloud = lib.mkDefault false;

      # Spring-loading: hold a dragged file over a folder and it opens, so a
      # drag can cross a whole tree. Apple's ~0.5 s delay is long enough that
      # most people never find out it exists.
      "com.apple.springing.enabled" = lib.mkDefault true;
      "com.apple.springing.delay" = lib.mkDefault 0.15;

      # Small sidebar rows fit noticeably more places in a tiled window. Hosts
      # that scaled the UI up asked for bigger chrome, so leave them Apple's.
      NSTableViewDefaultSizeMode = lib.mkDefault (if config.haus.ui.scale > 1.0 then 3 else 1);

      # Hide the stock menu bar only when Sill draws its own; otherwise keep it.
      # Rice-controlled (not mkDefault): it tracks sill.enable, not user taste.
      _HIHideMenuBar = config.haus.sill.enable;

      # ---- haus.sound → the two typed beep keys --------------------------
      # Not mkDefault: these are host opinions, null for null, same as the
      # §5.6 groups below. The volume conversion is the whole reason the
      # option is 0–100 — see ../lib/alert-volume.nix for the measured curve.
      "com.apple.sound.beep.volume" =
        if soundCfg.alertVolume == null then null else alertVolume.fromPercent soundCfg.alertVolume;
      # Upstream types this one as an INT, not a bool (0/1), unlike almost
      # every other switch in this domain.
      "com.apple.sound.beep.feedback" =
        if soundCfg.volumeFeedback == null then null else (if soundCfg.volumeFeedback then 1 else 0);

      # ---- haus.locale → the four typed region keys ----------------------
      # `metric` writes BOTH unit keys because macOS writes both and only
      # AppleMetricUnits is load-bearing: setting the friendlier-looking
      # AppleMeasurementUnits alone leaves a plist that reads right and a
      # machine that ignores it (measured — the group's "what second key makes
      # the first one a lie").
      AppleMetricUnits = if localeCfg.metric == null then null else (if localeCfg.metric then 1 else 0);
      AppleMeasurementUnits =
        if localeCfg.metric == null then
          null
        else if localeCfg.metric then
          "Centimeters"
        else
          "Inches";
      AppleTemperatureUnit =
        if localeCfg.temperature == null then
          null
        else if localeCfg.temperature == "celsius" then
          "Celsius"
        else
          "Fahrenheit";
      AppleICUForce24HourTime =
        if localeCfg.hourFormat == null then null else localeCfg.hourFormat == "24h";
    };
    trackpad = {
      Clicking = lib.mkDefault true;
      TrackpadRightClick = lib.mkDefault true;
      TrackpadThreeFingerDrag = lib.mkDefault true;
    };
    # ---- haus.screenshots → com.apple.screencapture ---------------------
    # The gentlest domain on the Mac: no TCC grant, no restart (screencapture
    # re-reads its preferences on every capture), every key typed upstream. So
    # unlike Finder or the menu bar there is nothing for the rice to own here —
    # the values simply pass through, null for null.
    #
    # Two renames on the way, both so the option states an intent rather than a
    # plist key: `format` because upstream's `type` says nothing about images,
    # and `shadow` because `disable-shadow` is a double negative — `shadow =
    # false` is the thing people actually want and `disable-shadow = true` is
    # how it has to be spelled.
    screencapture = {
      location = shotsLocation;
      type = shotsCfg.format;
      disable-shadow = if shotsCfg.shadow == null then null else !shotsCfg.shadow;
      show-thumbnail = shotsCfg.thumbnail;
      include-date = shotsCfg.includeDate;
    };

    # ---- haus.lock → com.apple.screensaver -------------------------------
    # Two keys, both null by default like every group in §5.6. No persistent
    # process reads this domain, so restart-map.nix says "none" — same shape as
    # screencapture, unverified against an effective-state oracle this pass (no
    # cheap NSWorkspace-style probe exists for "did the lock delay change").
    screensaver = {
      askForPassword = lockCfg.requirePassword;
      askForPasswordDelay = lockCfg.requirePasswordDelay;
    };

    # ---- haus.menuBar.clock → com.apple.menuExtraClock -------------------
    menuExtraClock = {
      Show24Hour = if clockCfg.format == null then null else clockCfg.format == "24h";
      ShowSeconds = clockCfg.showSeconds;
      ShowDate = if clockCfg.showDate == null then null else clockShowDateValue.${clockCfg.showDate};
      ShowDayOfWeek = clockCfg.showDayOfWeek;
      IsAnalog = clockCfg.analog;
    };

    # ---- haus.menuBar.controlCenter → com.apple.controlcenter ------------
    controlcenter = {
      BatteryShowPercentage = ccCfg.batteryPercentage;
      Sound = ccCfg.sound;
      Bluetooth = ccCfg.bluetooth;
      AirDrop = ccCfg.airdrop;
      Display = ccCfg.displayBrightness;
      FocusModes = ccCfg.focus;
      NowPlaying = ccCfg.nowPlaying;
    };

    CustomUserPreferences = {
      "com.apple.commerce".AutoUpdate = lib.mkDefault true;

      # No .DS_Store on network shares or USB sticks. It's invisible here and
      # litter everywhere else — in a colleague's file listing, in a zip you
      # send, in `git status` on a share. (Local disks still get one; that's
      # where Finder keeps per-folder view state, which we want.)
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = lib.mkDefault true;
        DSDontWriteUSBStores = lib.mkDefault true;
      };

      # Clear the modifier on every corner the rice claims. macOS keeps "hold ⌘
      # for this corner" in a SEPARATE key (wvous-*-modifier, a Carbon modifier
      # mask; 0 means none), and nix-darwin types the corner but not the
      # modifier — so without this a corner set by the rice inherits whatever
      # modifier the machine already had. The failure is silent and reads as the
      # option not working: the corner is correct, you just aren't holding the
      # key nobody mentioned. Corners left at null are untouched here too, so
      # this never erases a modifier the rice didn't ask to own.
      "com.apple.dock" = lib.mapAttrs' (_: k: lib.nameValuePair "wvous-${k}-modifier" 0) hotCornersSet;

      # Two Finder keys nix-darwin has no typed option for.
      "com.apple.finder" = {
        # Emptying the trash IS the confirmation; the items are still on disk
        # until it finishes.
        WarnOnEmptyTrash = lib.mkDefault false;
        # ⌘I opens with the panes you actually read already unfolded. One
        # mkDefault on the whole dict — the module system only discharges
        # override properties down to the domain's keys, not inside them.
        FXInfoPanesExpanded = lib.mkDefault {
          General = true;
          OpenWith = true;
          Privileges = true;
        };
      };
      # Companion to _HIHideMenuBar above (and same rationale: a function of Sill,
      # not user taste). The hidden menu bar still auto-reveals on hover; Tahoe's
      # Liquid Glass made that reveal translucent, so Sill's pills bled through it.
      # This is the "Show menu bar background" toggle (System Settings ▸ Menu Bar) —
      # it restores an opaque bar so the reveal fully covers Sill. Lives in
      # CustomUserPreferences because nix-darwin's typed NSGlobalDomain block has no
      # option for it (and no freeform); `defaults write NSGlobalDomain …` == `-g`.
      # Two more NSGlobalDomain keys nix-darwin has no typed option for, both
      # null-means-absent (an unset host option contributes no key at all
      # rather than a null the plist writer would have to interpret):
      #   haus.sound.uiSounds  — the Trash whoosh, the screenshot shutter
      #   haus.locale.language / .region — AppleLanguages is an ARRAY and
      #     AppleLocale a string; both are untyped upstream.
      NSGlobalDomain = {
        SLSMenuBarUseBlurredAppearance = config.haus.sill.enable;
      }
      // lib.optionalAttrs (soundCfg.uiSounds != null) {
        "com.apple.sound.uiaudio.enabled" = if soundCfg.uiSounds then 1 else 0;
      }
      // lib.optionalAttrs (localeCfg.language != null) {
        AppleLanguages = localeCfg.language;
      }
      // lib.optionalAttrs (localeCfg.region != null) {
        AppleLocale = localeCfg.region;
      };
    };
  };

  # ---- haus.security.firewall → networking.applicationFirewall ---------
  # NOT system.defaults: nix-darwin's own networking module runs
  # `socketfilterfw` directly in its own activation script, unconditionally,
  # every rebuild — a live imperative command, not a plist write waiting on
  # something in modules/lib/restart-map.nix to reread it. No restart, no
  # logout, no Full Disk Access. Same pass-through as screensaver/menuBar
  # above: null stays null, upstream's own type already means "leave alone".
  networking.applicationFirewall = {
    enable = firewallCfg.enable;
    blockAllIncoming = firewallCfg.blockAllIncoming;
    allowSigned = firewallCfg.allowSigned;
    allowSignedApp = firewallCfg.allowSignedApp;
    enableStealthMode = firewallCfg.stealthMode;
  };

  # ---- Nix housekeeping -----------------------------------------------------
  # Determinate owns the daemon + settings (/etc/nix/nix.custom.conf), so
  # nix-darwin's nix module is off. Determinate only GCs reactively under disk
  # pressure — on a big SSD that never fires — so run a weekly cleanup ourselves.
  nix.enable = false;
  launchd.daemons.nix-gc = {
    serviceConfig = {
      ProgramArguments = [
        "/nix/var/nix/profiles/default/bin/nix-collect-garbage"
        "--delete-older-than"
        "30d"
      ];
      StartCalendarInterval = [
        {
          Weekday = 0;
          Hour = 3;
          Minute = 0;
        }
      ];
      StandardOutPath = "/var/log/nix-gc.out.log";
      StandardErrorPath = "/var/log/nix-gc.err.log";
    };
  };

  nixpkgs.config.allowUnfree = true;
  # hostPlatform is set by mkNebelhaus (from its `system` arg) — hardcoding it
  # here silently forced aarch64 on every consumer. Standalone room users set
  # nixpkgs.hostPlatform themselves, as in any nix-darwin config.
  system.stateVersion = 5;

  # Minimal home base so feature modules can layer `home.file` / packages on top.
  # A FUNCTION, not a plain attrset, purely so `lib` here is home-manager's
  # extended lib — `lib.hm.dag` doesn't exist on the darwin lib den is evaluated
  # with, and the failure is an eval error deep inside the submodule.
  home-manager.users.${username} =
    { lib, ... }:
    {
      home.stateVersion = "24.11";

      # The screenshot folder has to EXIST before it means anything:
      # screencapture does not create a missing directory, it falls back to the
      # Desktop without a word — so `location` pointing at a folder you haven't
      # made yet is indistinguishable from the option being ignored. One mkdir
      # closes that.
      #
      # In home-manager's activation rather than the system's because the folder
      # belongs to the user (a root-created ~/Pictures/Screenshots would be
      # unwritable by the process taking the screenshot). Idempotent, so it
      # costs nothing on the rebuilds where it already exists; it never removes
      # or touches a folder after you change `location` away from it, since
      # deleting a directory full of screenshots is not a rebuild's business.
      home.activation = lib.mkIf (shotsLocation != null) {
        nebelhausScreenshotDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run mkdir -p ${lib.escapeShellArg shotsLocation}
        '';
      };
    };
}

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

  # Whichever system.defaults.universalaccess.* keys the host actually set (they
  # all default to null upstream, so this is exactly the opt-ins).
  universalaccessSet = lib.attrNames (
    lib.filterAttrs (_: v: v != null) config.system.defaults.universalaccess
  );

  # The nebelhaus.accessibility.* keys the host actually set. Same domain as
  # above, deliberately NOT the same mechanism — see the block that writes them.
  a11ySet = lib.filterAttrs (_: v: v != null) {
    inherit (config.nebelhaus.accessibility) increaseContrast differentiateWithoutColor;
  };

  devCfg = config.nebelhaus.developer;
  fontsCfg = config.nebelhaus.fonts;
  # Naming a family the rice was never given a package for is silent tofu:
  # Ghostty just falls back and the powerline/icon glyphs vanish. Cheap to spot.
  fontFamilyUnprovided =
    fontsCfg.mono.package == null && fontsCfg.mono.name != options.nebelhaus.fonts.mono.name.default;
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
      nebelhaus: fonts.mono.name is "${fontsCfg.mono.name}" but fonts.mono.package is null.

      The rice only installs the font it's given, so unless that family is already
      on the machine Ghostty will fall back silently — and the fallback won't be a
      Nerd Font, so starship's prompt, lsd's icons and yazi previews render as
      tofu. Set nebelhaus.fonts.mono.package to the matching package
      (e.g. pkgs.nerd-fonts.fira-code).
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

      nebelhaus.accessibility.* reaches the two useful keys in this domain
      (increaseContrast, differentiateWithoutColor) WITHOUT that hazard — it
      guards the write, so a missing grant costs you the setting and nothing else.
    '';

  # ---- nebelhaus.accessibility → com.apple.universalaccess -------------------
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
  system.activationScripts.postActivation.text = lib.optionalString (a11ySet != { }) ''
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
  '';

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
      # `wt` — manages Claude Code agent worktrees: closing a `claude --worktree`
      # pane (hearth's Super-c bind) never loses uncommitted work, and every
      # session stays resumable. Ships here because the rice already provides the
      # worktree keybinds; the WorktreeCreate/WorktreeRemove hooks (wired in your
      # host's settings.json) point at this. Self-contained — no repo/flake/bench.
      (writeShellScriptBin "wt" (builtins.readFile ./wt.sh))

      # `zscratch` — feel-test a candidate zellij config / layout / plugin.wasm in
      # a throwaway session in its OWN Ghostty window, WITHOUT a rebuild. Renders
      # your edit over a copy of the live ~/.config/zellij into a temp config-dir
      # and boots a fresh scratch session (its own name → its own server →
      # recompiled wasm), so the working `main` session's tabs stay untouched.
      # Moves the iterate-loop off `bench try switch` + restart; you rebuild once,
      # at the end, already knowing it works. Lives here (not hearth) because it's
      # a dev CLI on PATH like `haus`/`wt`, though it drives hearth's zellij dotfiles.
      (writeShellScriptBin "zscratch" (builtins.readFile ./zscratch.sh))

      # `claude-statusline` — the agent-worktree HUD for Claude Code's status bar
      # (hearth's claudeCodeSettings points the `statusLine` key here). Row 1 is
      # THIS session's worktree name + one status token (⏏ purge / N^ commits /
      # +A -D uncommitted); rows below list sister `wt` worktrees in flight across
      # ALL repos, with GitHub PR state. Cheap local git runs in the render path;
      # the cross-repo + `gh` enumeration is done detached by the companion
      # `claude-statusline-refresh` and cached (stale-while-revalidate), so the bar
      # never blocks. Reads `wt`'s registry — same agent-worktree flow, same home.
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
      inherit (config.nebelhaus.homebrew) autoUpdate upgrade cleanup;
    };

    # A minimal, opinionated starter set. A host adds its own apps through
    # `nebelhaus.apps` (../apps hands each entry's cask to this list); a raw
    # `homebrew.casks = [ ... ];` still merges in, for the rare cask that
    # isn't an app at all.
    casks = [
      "ghostty" # the terminal the rice is themed for
    ];
  };

  # ---- Fonts ----------------------------------------------------------------
  # The rice's terminal font, from nebelhaus.fonts.mono. JetBrains Mono Nerd
  # Font is the default because a Nerd Font is load-bearing here: starship's
  # powerline prompt, lsd's icons, and yazi all draw with patched glyphs that a
  # stock font renders as tofu. hearth points Ghostty at whatever this resolves
  # to. `fonts.packages` is a list option, so this merges with the fonts sill
  # installs (sketchybar-app-font + Hack, which its bar config names).
  fonts.packages = [
    (if fontsCfg.mono.package != null then fontsCfg.mono.package else pkgs.nerd-fonts.jetbrains-mono)
  ];

  # Homebrew's tap-trust check is flaky under sudo-driven activation (the
  # per-user trust store gets bypassed), so third-party taps fail with "Refusing
  # to load cask … from untrusted tap". We curate our taps ourselves; disable the
  # requirement globally via a brew.env that `bin/brew` reads on every call.
  #
  # HOMEBREW_API_AUTO_UPDATE_SECS only bites hosts that set
  # `nebelhaus.homebrew.autoUpdate = true` (the rice default is false, which
  # disables the check outright). For those, brew re-downloads its ~15 MB
  # formula/cask JSON API whenever the last check is older than the window —
  # and the stock window is 450 s, so any two rebuilds more than 7½ minutes
  # apart each pay for it. An hour still picks up a same-day cask release on
  # the next rebuild, without re-fetching the catalogue mid-iteration.
  environment.etc."homebrew/brew.env".text = ''
    HOMEBREW_NO_REQUIRE_TAP_TRUST=1
    HOMEBREW_API_AUTO_UPDATE_SECS=3600
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
      # 48. Same principle as theme.wallpaper = "none" — don't move what wasn't
      # asked about.
      tilesize = lib.mkIf (config.nebelhaus.ui.scale != 1.0) (
        lib.mkDefault (builtins.floor (48 * config.nebelhaus.ui.scale + 0.5))
      );
      autohide = lib.mkDefault true;
      show-recents = lib.mkDefault false;
      mru-spaces = lib.mkDefault false;
      orientation = lib.mkDefault "bottom";
    };
    finder = {
      AppleShowAllExtensions = lib.mkDefault true;
      AppleShowAllFiles = lib.mkDefault true;
      FXPreferredViewStyle = lib.mkDefault "Nlsv"; # list view
      ShowPathbar = lib.mkDefault true;
      ShowStatusBar = lib.mkDefault true;
    };
    NSGlobalDomain = {
      ApplePressAndHoldEnabled = lib.mkDefault false; # key repeat, not the accent picker
      KeyRepeat = lib.mkDefault 2;
      InitialKeyRepeat = lib.mkDefault 15;
      AppleShowAllExtensions = lib.mkDefault true;
      # Hide the stock menu bar only when Sill draws its own; otherwise keep it.
      # Rice-controlled (not mkDefault): it tracks sill.enable, not user taste.
      _HIHideMenuBar = config.nebelhaus.sill.enable;
    };
    trackpad = {
      Clicking = lib.mkDefault true;
      TrackpadRightClick = lib.mkDefault true;
      TrackpadThreeFingerDrag = lib.mkDefault true;
    };
    CustomUserPreferences = {
      "com.apple.commerce".AutoUpdate = lib.mkDefault true;
      # Companion to _HIHideMenuBar above (and same rationale: a function of Sill,
      # not user taste). The hidden menu bar still auto-reveals on hover; Tahoe's
      # Liquid Glass made that reveal translucent, so Sill's pills bled through it.
      # This is the "Show menu bar background" toggle (System Settings ▸ Menu Bar) —
      # it restores an opaque bar so the reveal fully covers Sill. Lives in
      # CustomUserPreferences because nix-darwin's typed NSGlobalDomain block has no
      # option for it (and no freeform); `defaults write NSGlobalDomain …` == `-g`.
      NSGlobalDomain.SLSMenuBarUseBlurredAppearance = config.nebelhaus.sill.enable;
    };
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
  home-manager.users.${username}.home.stateVersion = "24.11";
}

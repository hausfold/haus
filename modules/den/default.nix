# Den — the foundation the rest of the house rests on. macOS system defaults,
# the Homebrew framework, core CLI tools, fonts, and periodic GC.
{
  config,
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

  # Extra packages appended by the pounce "Install App" command's "just
  # install" lane, kept in a JSON file so they stay machine-editable without
  # hand-patching Nix (the roster's rosterFile counterpart). Shape:
  # { "casks": [ … ], "brews": [ … ], "nixpkgs": [ … ] }. null → nothing.
  installsFile = config.nebelhaus.homebrew.installsFile;
  installs =
    if installsFile != null then
      builtins.fromJSON (builtins.readFile installsFile)
    else
      { };
in
{
  system.primaryUser = username;

  programs.zsh.enable = true;

  # Core CLI tools. The shell *experience* (aliases, starship, git, yazi, …) is
  # yours to add in your host file; these are the baseline binaries the rice and
  # its commands lean on.
  environment.systemPackages = with pkgs; [
    bat
    fzf
    delta
    gh
    glow
    gnupg
    jq
    lazygit
    lsd
    mas
    fastfetch
    tree
    ttyd
    # The everyday end-user CLI: haus rebuild / update / rollback / status /
    # edit / doctor — so a nebelhaus machine never needs raw nix incantations.
    # System-wide (not home-manager) so sudo and non-login shells see it too.
    # (The workshop's developer CLI is `bench` — a different name on purpose,
    # so the two never shadow each other.)
    (writeShellScriptBin "haus" (builtins.readFile ./haus.sh))

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

    # `awake 3h` / `awake indefinitely` — a durable controller around macOS's
    # built-in caffeinate. Its assertion is launchd-owned below, so callers can
    # exit (or SketchyBar can reload) without accidentally allowing idle sleep.
    awake

    # `claude-statusline` — the agent-worktree HUD for Claude Code's status bar
    # (hearth's claudeCodeSettings points the `statusLine` key here). Row 1 is
    # THIS session's worktree name + one status token (⏏ purge / N^ commits /
    # +A -D uncommitted); rows below list sister `wt` worktrees in flight across
    # ALL repos, with GitHub PR state. Cheap local git runs in the render path;
    # the cross-repo + `gh` enumeration is done detached by the companion
    # `claude-statusline-refresh` and cached (stale-while-revalidate), so the bar
    # never blocks. Reads `wt`'s registry — same agent-worktree flow, same home.
    (writeShellScriptBin "claude-statusline" (builtins.readFile ./statusline.sh))
    (writeShellScriptBin "claude-statusline-refresh" (builtins.readFile ./statusline-refresh.sh))
  ] ++ map (attr:
    lib.attrByPath (lib.splitString "." attr)
      (throw "nebelhaus.homebrew.installsFile: nixpkgs package '${attr}' does not exist")
      pkgs
  ) (installs.nixpkgs or [ ]);

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

    # A minimal, opinionated starter set. Edit freely in your host file —
    # `homebrew.casks = [ ... ];` merges with whatever the modules declare.
    # nebelhaus.homebrew.installsFile (the pounce "Install App" command) appends
    # its casks/brews here too, so an app added from the palette is declarative.
    casks = [
      "ghostty" # the terminal the rice is themed for
    ]
    ++ (installs.casks or [ ]);
    brews = installs.brews or [ ];
  };

  # ---- Fonts ----------------------------------------------------------------
  # The rice's terminal font. JetBrains Mono Nerd Font carries the powerline +
  # icon glyphs that starship, lsd, and yazi draw with — without a Nerd Font
  # they render as tofu. hearth points Ghostty at it. `fonts.packages` is a list
  # option, so this merges with the sketchybar-app-font sill installs.
  fonts.packages = [ pkgs.nerd-fonts.jetbrains-mono ];

  # Homebrew's tap-trust check is flaky under sudo-driven activation (the
  # per-user trust store gets bypassed), so third-party taps fail with "Refusing
  # to load cask … from untrusted tap". We curate our taps ourselves; disable the
  # requirement globally via a brew.env that `bin/brew` reads on every call.
  environment.etc."homebrew/brew.env".text = ''
    HOMEBREW_NO_REQUIRE_TAP_TRUST=1
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

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

    # ---- restart Finder ------------------------------------------------------
    # The refresh below broadcasts a preference change, but Finder reads
    # com.apple.finder once, at LAUNCH — the sort order, the view style and the
    # POSIX-path title are baked into the running process. nix-darwin restarts
    # the Dock after writing user defaults and stops there, so without this a
    # rebuild that changed a Finder key looks like it did nothing until the next
    # login. launchd relaunches Finder immediately; the cost is that open Finder
    # windows close, exactly like the Dock restart nix-darwin already does.
    ''
      killall -qu ${username} Finder || true
    ''

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

      # The annotated host file — every nebelhaus.* option at its default, with
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
      # THIS session's worktree name + one status token (⏏ purge / N^ commits —
      # blue when unmerged, orange when they landed AFTER the PR merged and no PR
      # covers them / +A -D uncommitted); rows below list sister `wt` worktrees across
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
      inherit (config.nebelhaus.homebrew) autoUpdate upgrade cleanup;
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
  nebelhaus.roster.ghostty = {
    name = lib.mkDefault "Ghostty";
    cask = lib.mkDefault "ghostty";
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

      # ⌘Q quits Finder like any other app. It relaunches the instant you open a
      # folder, and the desktop comes back with it — but if you keep icons on
      # the desktop and want them always drawn, set this false in your host.
      QuitMenuItem = lib.mkDefault true;

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
      NSTableViewDefaultSizeMode = lib.mkDefault (if config.nebelhaus.ui.scale > 1.0 then 3 else 1);

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

      # No .DS_Store on network shares or USB sticks. It's invisible here and
      # litter everywhere else — in a colleague's file listing, in a zip you
      # send, in `git status` on a share. (Local disks still get one; that's
      # where Finder keeps per-folder view state, which we want.)
      "com.apple.desktopservices" = {
        DSDontWriteNetworkStores = lib.mkDefault true;
        DSDontWriteUSBStores = lib.mkDefault true;
      };

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

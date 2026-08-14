# Part of the nebelhaus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# den's options — macOS defaults, fonts, Homebrew policy, and the two
# accessibility keys that actually apply on macOS 26.
{ lib, config, ... }:

let
  # One table for the enum and for the path den/default.nix writes — see
  # alert-sounds.nix, the same shape hot-corners.nix uses.
  alertSoundNames = import ./alert-sounds.nix;
  alertSoundList = "  ${lib.concatStringsSep "  " alertSoundNames}\n";

  hotCornerActions = import ./hot-corners.nix;
  hotCornerNames = map (a: a.name) hotCornerActions;
  # The value list in the description comes from the same table the enum does,
  # so a new action is one edit and the docs can't describe a value the option
  # rejects. Padded to the longest name so the labels line up in the reference
  # page's <pre> block, the same shape displays.uiScale uses.
  hotCornerWidth = lib.foldl' (m: a: lib.max m (lib.stringLength a.name)) 0 hotCornerActions;
  hotCornerList = lib.concatMapStrings (
    a: "  ${lib.fixedWidthString hotCornerWidth " " a.name}  ${a.label}\n"
  ) hotCornerActions;

  mkHotCorner =
    corner:
    lib.mkOption {
      type = lib.types.nullOr (lib.types.enum hotCornerNames);
      default = null;
      example = "mission-control";
      description = ''
        What happens when the pointer reaches the ${corner} corner of the main
        display.

        ```
        ${hotCornerList}```

        null (the default) writes nothing at all, which is not the same as
        "disabled": corners are a setting people have usually already made by
        hand, and a rice that names one it doesn't care about would silently
        erase it. Use `"disabled"` to explicitly claim a corner and make it inert.

        Setting a corner also clears its MODIFIER key. macOS stores "hold ⌘ for
        this corner" separately (`wvous-*-modifier`), and a leftover modifier from
        an earlier setup makes a corner the rice just declared look broken —
        nothing happens, because you weren't holding the key nobody told you
        about. Corners the rice leaves at null keep whatever modifier they have.

        Worth knowing if you also run tiling: `mission-control` and `desktop` are
        macOS's own window and Space management, which prowl replaces. They still
        work, they just show you a view of the windows prowl is arranging.
      '';
    };
in

{
  options.haus = {
    # ---- accessibility ----
    # Deliberately TWO options, not a family. These are the only keys in
    # com.apple.universalaccess measured to write AND actually take effect on
    # macOS 26 (verified against NSWorkspace, not just a plist read-back — that
    # distinction matters: com.apple.Accessibility accepts writes and changes
    # nothing, and universalaccess's own FontSizeCategory writes without ever
    # notifying a running app). Everything else in that domain stays a System
    # Settings job until it's been measured the same way.
    accessibility =
      let
        mkA11y =
          desc:
          lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            example = true;
            description = ''
              ${desc}

              null (the default) leaves whatever you have alone — this is a
              personal setting, so the rice never picks a value for you.

              REACHABILITY: `com.apple.universalaccess` is TCC-protected. It writes
              only when the app that runs the rebuild holds Full Disk Access
              (System Settings ▸ Privacy & Security ▸ Full Disk Access; on macOS 26
              a stale grant often needs removing and re-adding with (+)). Without
              that grant the rice logs a warning and moves on — it does NOT fail
              the rebuild. Worth knowing: an agent-driven `haus rebuild` runs under
              a different app than your terminal, so it may skip this while your
              own rebuild applies it.
            '';
          };
      in
      {
        increaseContrast = mkA11y ''
          macOS's "Increase contrast" — stronger borders and reduced use of
          colour alone to convey state, across native apps. This is the
          system-level companion to a high-contrast nebelhaus theme: the theme
          restyles the tools nebelhaus colours, this reaches everything else.
        '';
        differentiateWithoutColor = mkA11y ''
          macOS's "Differentiate without colour" — native UI adds shapes and
          text where it would otherwise rely on hue alone. The setting to pair
          with a rice built for colour-blind readability.
        '';
      };

    # ---- animations ----
    # macOS's own motion: five keys that are just numbers and switches in a
    # plist. Deliberately NOT `com.apple.universalaccess reduceMotion`, which is
    # the setting anyone reaches for first and is a much wider blast radius than
    # it looks — the description says why, because that reasoning is the whole
    # point of the group existing separately.
    #
    # Default "system" = write nothing, the same policy every other curated
    # macOS settings group follows ("a group is a place to make an opinion
    # available, not to impose one; a preset is where an opinion belongs" —
    # notes/options-roadmap.md §5.6). It was briefly drafted the other way
    # round, defaulting to "fast", and the argument against that is the one hot
    # corners already made: these keys land on machines that have been running
    # for years, macOS keeps no memory of a prior value, and a rice that speeds
    # up a Dock nobody asked it about can't put it back. Opting in is one line.
    animations = lib.mkOption {
      type = lib.types.enum [
        "fast"
        "system"
      ];
      default = "system";
      example = "fast";
      description = ''
        How much motion macOS spends on its own Dock and windows — how long
        three animations run, and two it plays at all.

        `"system"` (the default) writes NOTHING — not the macOS values, nothing
        at all — so whatever your Dock does today, it keeps doing. Same policy
        as `haus.hotCorners`: the rice doesn't overwrite a setting you didn't
        ask it about.

        `"fast"` writes five keys, all `mkDefault`, so any one of them can be
        overridden by name in your host file:

        ```
          com.apple.dock  autohide-time-modifier         0.15   Dock slide
          com.apple.dock  expose-animation-duration      0.1    Mission Control
          com.apple.dock  launchanim                     false  the bouncing icon
          com.apple.dock  mineffect                      scale  minimise (not genie)
          NSGlobalDomain  NSAutomaticWindowAnimationsEnabled  false  window open/close
        ```

        GOING BACK IS NOT AUTOMATIC, which is the one thing about this group
        that can surprise you and the reason it isn't on by default. Setting
        `"system"` again means STOP WRITING, not RESTORE: a `defaults` write is
        sticky and macOS keeps no memory of what was there before, so once
        you've rebuilt on `"fast"`, the five keys keep the rice's numbers.
        Undoing it means naming the values you want back in your host file
        (they're `mkDefault`, so a plain value wins), or a `defaults delete`.
        Worth knowing before you try `"fast"` on a Dock you tuned by hand.

        WHY THIS ISN'T "REDUCE MOTION". macOS's accessibility switch of that
        name (`com.apple.universalaccess reduceMotion`) would cover all of this
        and more — but it is also the single flag every browser maps to the
        `prefers-reduced-motion: reduce` CSS media query, via
        `NSWorkspace.accessibilityDisplayShouldReduceMotion`. Turning it on
        rewrites the web: mostly for the better, except on sites whose
        scroll-reveal animation is what sets the content visible in the first
        place, which then never appears at all. These five keys are in two
        entirely different domains and move no accessibility flag — `hausax`
        reads that exact `NSWorkspace` property, so `hausax | jq .reduceMotion`
        stays `false` with this set to `"fast"` — that's the whole reason this
        group exists as five curated keys instead of one switch. If you DO want the
        accessibility switch, that's `System Settings ▸ Accessibility ▸
        Display`, deliberately not a rice option.

        WHEN YOU'LL FEEL IT. The four Dock keys are live the moment activation
        finishes — nix-darwin restarts the Dock whenever anything in its domain
        is written, and the rice always writes `autohide`. The NSGlobalDomain
        one is read by each app AT LAUNCH, so apps you already have open keep
        animating their windows until you relaunch them; `activateSettings`
        can't reach back into a running `NSApplication`.

        These are timings, not a state the rice can prove from a plist — unlike
        the `haus.accessibility` keys, there's no oracle for "did the Dock
        slide faster". They're felt, not measured. The one measurable claim
        here is the negative one above.
      '';
    };

    # ---- fonts ----
    # Honest scope: this is the rice's type FAMILY — Ghostty's, and (since the
    # bar stopped hardcoding one of its own) sill's. `size` is the terminal's
    # alone: the bar's sizes come from ui.scale against the menu-bar band's
    # ceiling, because its pill geometry is built around them (../lib/bar.nix).
    fonts.mono = {
      name = lib.mkOption {
        type = lib.types.str;
        # NOT carved out into the desktop, though the inventory lists it as an
        # opinion. Which patched family is taste; being a PATCHED family is a
        # requirement — starship, lsd, yazi and half the bar draw glyphs a stock
        # font renders as tofu (see below). A neutral "Menlo" would make the
        # bare terminal room actively broken rather than merely unopinionated,
        # which is the opposite of "a neutral, useful configuration when
        # enabled". So the layer keeps supplying one that works, and a desktop
        # that wants a different family names it and its package together.
        default = "JetBrainsMono Nerd Font Mono";
        example = "Berkeley Mono";
        description = ''
          The rice's type family, as Ghostty's `font-family` names it.

          It reaches the terminal AND the menu bar: every pill label and icon
          sill draws is in this family, at sizes of its own (see
          `haus.ui.scale`). The workspace-logo glyphs are the one exception
          — those are sketchybar-app-font, which sill installs itself.

          This should be a NERD FONT patched build: starship's prompt, lsd's
          icons, yazi previews and half the bar's icons draw with glyphs a stock
          font renders as tofu. If you change this, set `package` (or
          `packageName`) too — the rice can only install a font it's been given,
          and it warns when you name a family without one.

          The name is taken verbatim, so a "… Nerd Font Mono" family is drawn in
          the bar as well: the bar mixes icon glyphs into its labels, which is
          the same reason the terminal wants a patched font.
        '';
      };
      baseSize = lib.mkOption {
        type = lib.types.ints.positive;
        default = 13;
        example = 19;
        description = ''
          The terminal-font baseline, before `haus.ui.scale` multiplies it.
          The neutral room uses 13pt; nebelhaus selects 19pt in its desktop.

          This exists so a desktop can carry that tuned baseline WITHOUT
          breaking the scale relationship. Setting `size` directly pins an
          absolute number, which would make `haus.ui.scale` (and the
          large-print preset built on it) stop moving the terminal font at
          all — a silent regression, since everything else would still grow.
          Say the baseline here; say the exception with `size`.
        '';
      };
      size = lib.mkOption {
        type = lib.types.ints.positive;
        default = builtins.floor (config.haus.fonts.mono.baseSize * config.haus.ui.scale + 0.5);
        defaultText = lib.literalExpression "round (haus.fonts.mono.baseSize * haus.ui.scale)";
        example = 24;
        description = ''
          Terminal font size in points. The single most useful knob for a
          larger-text machine, since it moves everything the rice actually
          lives in.

          nebelhaus's 19pt baseline exists for a reason worth knowing: the Ghostty window is
          tiled to a fixed pixel height by prowl, and sizes that don't divide
          that height evenly used to leave a gap under zellij's status bar.
          That's since been fixed properly (window-padding-balance +
          `extend-always`), so any size is safe now — 19 is simply the tuned
          starting point.
        '';
      };
      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        example = lib.literalExpression "pkgs.nerd-fonts.fira-code";
        description = ''
          The package providing `name`. null (the default) installs the rice's
          own JetBrains Mono Nerd Font, which is what `name` defaults to.

          Set this whenever you change `name`, or the family simply won't exist
          on the machine and Ghostty will silently fall back — the rice warns if
          it spots that combination.

          A shared rice can't set this one — it needs `pkgs`, and a data-only
          rice has no arguments. Use `packageName` there.
        '';
      };
      packageName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "nerd-fonts.fira-code";
        description = ''
          The same thing as `package`, NAMED rather than evaluated: an
          attribute path into nixpkgs, so "nerd-fonts.fira-code" means
          `pkgs.nerd-fonts.fira-code`.

          This exists so a data-only rice (presets/README.md) can change the
          font FAMILY and not just its size — reaching `pkgs` is precisely what
          that format forbids, which made `fonts.mono.package` unreachable to
          every shared rice. A name is data; a package is code.

          Set one or the other, never both. A name that resolves to nothing, or
          to a set of packages rather than a package, fails at eval with the
          spelling to try instead.
        '';
      };
    };

    homebrew = {
      cleanup = lib.mkOption {
        type = lib.types.enum [
          "none"
          "uninstall"
          "zap"
        ];
        default = "none";
        description = ''
          How `darwin-rebuild switch` treats Homebrew casks/brews that are
          installed but NOT declared anywhere in your config.

          - "none" (default, safe): leave undeclared formulae/casks alone. The
            rice never deletes apps you installed yourself.
          - "uninstall": remove undeclared formulae/casks (keeps their data).
          - "zap": remove undeclared formulae/casks AND their app data. Fully
            declarative, but a stray cask you forgot to list is deleted — with
            no backup — on the very next rebuild. Only choose this once every
            app you keep is declared (bootstrap can adopt your current casks).
        '';
      };
      autoUpdate = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Run `brew update` before activating the Homebrew step on every
          rebuild. Off by default — reproducible rebuilds shouldn't silently
          pull newer formulae. Turn on if you want brew to track upstream.
        '';
      };
      upgrade = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Upgrade outdated Homebrew packages on every rebuild. Off by default
          for the same reproducibility reason as autoUpdate.
        '';
      };
    };

    # ---- hot corners ----
    # Four screen corners, each an action, by name rather than by the integer
    # macOS actually stores. Every value defaults to null (leave alone) because
    # the corners are one of the few macOS settings almost everyone has already
    # touched — see mkHotCorner's description for why that isn't "disabled".
    hotCorners = {
      topLeft = mkHotCorner "top-left";
      topRight = mkHotCorner "top-right";
      bottomLeft = mkHotCorner "bottom-left";
      bottomRight = mkHotCorner "bottom-right";
    };

    # ---- screenshots ----
    # com.apple.screencapture, which is one of the friendliest domains on the
    # Mac: writable without any TCC grant, needs no restart (screencapture reads
    # its preferences per capture), and every key here is typed by nix-darwin.
    # Same null-means-leave-alone rule as the corners above.
    screenshots = {
      location = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "~/Pictures/Screenshots";
        description = ''
          Where ⇧⌘3 / ⇧⌘4 / ⇧⌘5 write their files. null (the default) leaves
          macOS's own choice alone, which is the Desktop.

          Absolute, or starting with `~/` — the rice expands the `~` for you and
          CREATES the directory during activation. Both halves matter: macOS
          stores this string verbatim and expands nothing, and if the path does
          not exist screencapture silently falls back to the Desktop, so a
          typo'd or not-yet-created folder looks exactly like the setting having
          been ignored.
        '';
      };
      format = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "png"
            "jpg"
            "pdf"
            "tiff"
            "heic"
            "gif"
          ]
        );
        default = null;
        example = "png";
        description = ''
          The image format new screenshots are saved in. null (the default)
          leaves macOS's own choice alone, which is png.

          png is lossless and the right default for UI and text — a jpg
          screenshot of a terminal has visible ringing around every glyph. jpg
          is worth choosing only when you screenshot photographs often enough
          for the file sizes to matter.
        '';
      };
      shadow = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = false;
        description = ''
          Whether a window capture (⇧⌘4 then Space) keeps macOS's big soft drop
          shadow. null (the default) leaves macOS's own choice alone, which is
          to include it.

          false is the setting to want if screenshots go into documentation: the
          shadow is transparent padding, so it adds a wide invisible margin that
          every layout then has to fight. Holding ⌥ while you click suppresses
          it for one capture either way.
        '';
      };
      thumbnail = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = false;
        description = ''
          Whether the floating preview thumbnail appears in the bottom-right
          corner after a capture. null (the default) leaves macOS's own choice
          alone, which is to show it.

          false writes the file immediately instead of after the ~5s the
          thumbnail waits around — the setting to want if you screenshot in
          quick succession, or if you script anything that reads the file. The
          cost is losing the markup/drag affordance the thumbnail offers.
        '';
      };
      includeDate = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = true;
        description = ''
          Whether filenames carry the date and time ("Screenshot 2026-08-03 at
          13.37.20.png") or just a counter ("Screenshot 1.png"). null (the
          default) leaves macOS's own choice alone, which is to include it.
        '';
      };
    };

    # ---- lock ----
    # §5.6's "Lock / login / screensaver" group, the LOCK half only. The login
    # half (com.apple.loginwindow — guest account, the text under the password
    # field, hiding Shut Down/Restart) is deliberately not here: loginwindow is
    # read once at boot/login, killing the loginwindow process would force-quit
    # the current session, and there is no live-reload path — exactly the
    # "silent logout" trap this section exists to avoid. It waits until this
    # group has somewhere honest to say "takes effect at next login" out loud,
    # the way `haus.accessibility` says "needs Full Disk Access".
    lock = {
      requirePassword = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = true;
        description = ''
          Require a password to wake this Mac from sleep or the screen saver.
          null (the default) leaves macOS's own choice alone.

          The one setting in this group worth turning on for ANY shared or
          portable machine — a family Mac, a laptop that leaves the house.
        '';
      };
      requirePasswordDelay = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.unsigned;
        default = null;
        example = 5;
        description = ''
          Seconds to wait after sleep/screen-saver starts before
          `requirePassword` actually locks the screen — macOS's "grace period".
          null (the default) leaves macOS's own choice alone.

          0 locks instantly. Has no effect while `requirePassword` is null or
          false.
        '';
      };
    };

    # ---- menu bar & control center ----
    # §5.6's "Menu bar & Control Center" group: the clock (com.apple.menuExtraClock)
    # and which Control Center glyphs sit in the menu bar (com.apple.controlcenter).
    # Both restart via a process kill (SystemUIServer / ControlCenter — see
    # modules/lib/restart-map.nix), the same live-reload shape as Finder, not a
    # TCC-gated or logout-only domain.
    menuBar = {
      clock = {
        format = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.enum [
              "12h"
              "24h"
            ]
          );
          default = null;
          example = "24h";
          description = ''
            12-hour or 24-hour menu bar clock. null (the default) leaves
            macOS's own choice alone (region-dependent, usually 12h in the US).
          '';
        };
        showSeconds = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          example = false;
          description = ''
            Show the clock to second precision instead of minutes. null (the
            default) leaves macOS's own choice alone.
          '';
        };
        showDate = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.enum [
              "when-space-allows"
              "always"
              "never"
            ]
          );
          default = null;
          example = "always";
          description = ''
            Whether the full date appears next to the time. null (the default)
            leaves macOS's own choice alone ("when-space-allows").
          '';
        };
        showDayOfWeek = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          example = true;
          description = ''
            Show the day of the week next to the clock. null (the default)
            leaves macOS's own choice alone.
          '';
        };
        analog = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          example = false;
          description = ''
            Draw an analog clock face instead of a digital readout. null (the
            default) leaves macOS's own choice alone (digital).
          '';
        };
      };
      controlCenter = {
        batteryPercentage = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          example = true;
          description = ''
            Show the battery percentage next to its menu bar icon. null (the
            default) leaves macOS's own choice alone.
          '';
        };
        sound = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          example = true;
          description = "Whether the Sound control has a menu bar icon of its own. null (the default) leaves macOS's own choice alone.";
        };
        bluetooth = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          example = true;
          description = "Whether the Bluetooth control has a menu bar icon of its own. null (the default) leaves macOS's own choice alone.";
        };
        airdrop = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          example = false;
          description = "Whether the AirDrop control has a menu bar icon of its own. null (the default) leaves macOS's own choice alone.";
        };
        displayBrightness = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          example = true;
          description = "Whether the Screen Brightness control has a menu bar icon of its own. null (the default) leaves macOS's own choice alone.";
        };
        focus = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          example = true;
          description = "Whether the Focus control has a menu bar icon of its own. null (the default) leaves macOS's own choice alone.";
        };
        nowPlaying = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          example = false;
          description = "Whether the Now Playing control has a menu bar icon of its own. null (the default) leaves macOS's own choice alone.";
        };
      };
    };

    # ---- security ----
    # §5.6's "Security posture" group, the firewall half only. Guest user lives
    # in the logout-only loginwindow domain (see `lock` above); remote login and
    # AirDrop's OWN on/off (as opposed to its menu bar icon, above) aren't
    # reachable through anything this rice currently wires.
    #
    # NOT a system.defaults domain and NOT in modules/lib/restart-map.nix on
    # purpose: nix-darwin's networking.applicationFirewall runs
    # `/usr/libexec/ApplicationFirewall/socketfilterfw` directly, in its own
    # unconditional activation script, every rebuild — a live command, not a
    # plist write waiting for something to reread it. No restart, no logout,
    # no TCC grant.
    security.firewall = {
      enable = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = true;
        description = ''
          The built-in application firewall. null (the default) leaves
          macOS's own choice alone (off, on a fresh install).

          The "public Wi-Fi" setting: worth true for a laptop that leaves
          home, closer to unnecessary for a desktop that never does.
        '';
      };
      blockAllIncoming = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = false;
        description = ''
          Block ALL incoming connections, including ones apps ask for (AirDrop,
          screen sharing, a dev server on your LAN). null (the default) leaves
          macOS's own choice alone. Has no effect while `enable` is null or
          false.
        '';
      };
      allowSigned = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = true;
        description = ''
          Let built-in, Apple-signed software receive incoming connections
          without asking. null (the default) leaves macOS's own choice alone.
          Has no effect while `enable` is null or false.
        '';
      };
      allowSignedApp = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = true;
        description = ''
          Let downloaded, signed third-party software receive incoming
          connections without asking. null (the default) leaves macOS's own
          choice alone. Has no effect while `enable` is null or false.
        '';
      };
      stealthMode = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = true;
        description = ''
          Don't respond to network probes (ping, closed-port connection
          attempts) at all, instead of replying "connection refused". null
          (the default) leaves macOS's own choice alone. Has no effect while
          `enable` is null or false.
        '';
      };
    };

    # ---- sound ----
    # §5.6's "Sound" group, spiked 2026-08-08 (workshop
    # notes/macos-settings-matrix.md). Everything here writes live: no restart,
    # no logout, no Full Disk Access. Two keys are typed by nix-darwin
    # (beep.volume, beep.feedback), two go through CustomUserPreferences, and
    # the startup chime isn't a plist at all.
    #
    # The reason `alertVolume` is 0–100 rather than the raw float upstream
    # types: macOS stores the alert volume as `e^(fraction − 1)`, so 0.5 is 31%
    # and anything at or below e⁻¹ ≈ 0.368 is silence. A rice that exposed the
    # float would ship a number that reads like a percentage and isn't.
    sound = {
      alertVolume = lib.mkOption {
        type = lib.types.nullOr (lib.types.ints.between 0 100);
        default = null;
        example = 50;
        description = ''
          How loud the alert beep is, 0–100, exactly as the slider in System
          Settings ▸ Sound reads. null (the default) leaves macOS's own choice
          alone.

          The rice converts to the exponential value macOS actually stores
          (`e^(v/100 − 1)`, with 0 meaning silence), because that key is not a
          fraction: writing the obvious `0.5` gets you 31%.

          TWO WRITERS: the volume keys and the Sound pane write this same key.
          Declaring it means every rebuild reasserts your number over anything
          you changed by hand since — which is the point of declaring it, but
          leave it null if you'd rather the slider win.
        '';
      };
      alertSound = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum alertSoundNames);
        default = null;
        example = "Submarine";
        description = ''
          Which sound the alert beep plays, by name:

          ```
          ${alertSoundList}```

          null (the default) leaves macOS's own choice alone.

          An enum rather than a path on purpose. macOS stores an absolute path
          here and validates nothing, and a path that doesn't resolve does not
          fall back to the default beep — it goes SILENT (measured by ear,
          2026-08-08), while the plist still reads like a working setting. The
          rice builds the path from the name and skips the write with a warning
          if that file is missing, so a macOS release retiring a sound can't
          quietly mute you.
        '';
      };
      volumeFeedback = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = true;
        description = ''
          Play a sound when the volume keys change the volume. null (the
          default) leaves macOS's own choice alone.
        '';
      };
      uiSounds = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = false;
        description = ''
          Play user-interface sound effects — the Trash whoosh, the screenshot
          shutter, the Mail whoosh. null (the default) leaves macOS's own
          choice alone.
        '';
      };
      startupChime = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = false;
        description = ''
          The chime a Mac plays at boot. null (the default) leaves it alone.

          The odd one in this group: it is firmware state (`nvram StartupMute`),
          not a preference, so it survives an OS reinstall and a wiped home
          directory — and it is the only setting here that needs the rebuild to
          run as root, which activation already does.
        '';
      };
    };

    # ---- locale ----
    # §5.6's "Locale / input sources" group, spiked 2026-08-08.
    #
    # The finding that shapes this whole block: a `defaults write` here reaches
    # NEWLY LAUNCHED processes only. An app that is already running never sees
    # it — not even through Locale.autoupdatingCurrent, the API documented to
    # track changes — unless AppleDatePreferencesChangedNotification is posted
    # afterwards. That post is a distributed notification, not a killall and
    # not a logout, which is why modules/lib/restart-map.nix grew a third verb
    # (`notify:<name>`) for this group. See den/default.nix.
    #
    # `language` is the exception no notification can rescue: which .lproj a
    # bundle loads is decided when it launches, so the UI language of an app
    # you already have open changes when you relaunch it, and the login window
    # follows at next login.
    locale = {
      language = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        default = null;
        example = [
          "de-DE"
          "en-GB"
        ];
        description = ''
          Preferred languages, best first — the order System Settings ▸ General
          ▸ Language & Region shows. null (the default) leaves macOS's own list
          alone.

          Apps use the first entry they have a translation for, so a list is a
          fallback chain, not a single choice.

          TAKES EFFECT ON RELAUNCH: an app picks its language when it starts.
          Already-open apps keep the old one until you quit and reopen them,
          and the login window follows at next login. Nothing the rice can post
          changes that — it is how bundle resources load.
        '';
      };
      region = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "de_DE";
        description = ''
          The region whose formats macOS uses — dates, number separators, paper
          size, the first day of the week. An ICU locale identifier
          (`de_DE`, `en_GB`, `fr_CA`). null (the default) leaves macOS's own
          choice alone.

          This is the lever with the most reach in the group: it moves the hour
          format, the measurement system and the first weekday together. Set it
          before reaching for the individual overrides below — and note there is
          deliberately no `firstWeekday` option, because macOS's own
          `AppleFirstWeekday` key is stored and then ignored (measured; it is
          the second dict-valued key in this domain found to do that). The
          region's own answer is the only one that applies.
        '';
      };
      metric = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = true;
        description = ''
          Use the metric system, overriding whatever `region` implies. null
          (the default) follows the region.

          Writes BOTH keys macOS keeps for this (`AppleMetricUnits` and
          `AppleMeasurementUnits`), because it writes both itself and only one
          of them is load-bearing — setting the friendlier-looking
          `AppleMeasurementUnits` alone leaves a plist that reads right and a
          machine that ignores it.
        '';
      };
      temperature = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "celsius"
            "fahrenheit"
          ]
        );
        default = null;
        example = "celsius";
        description = ''
          Temperature unit, overriding whatever `region` implies. null (the
          default) follows the region. Separate from `metric` because macOS
          keeps it separate — a metric machine reporting °F is a real
          combination, not a mistake.
        '';
      };
      hourFormat = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "12h"
            "24h"
          ]
        );
        default = null;
        example = "24h";
        description = ''
          Force 12- or 24-hour time everywhere, overriding whatever `region`
          implies. null (the default) follows the region.

          System-wide, unlike `haus.menuBar.clock.format`, which is only the
          menu bar clock's own key. Setting both is fine and normal; setting
          only this one still changes the menu bar, because the clock has no
          opinion of its own until you give it one.
        '';
      };
      inputSources = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        default = null;
        example = [
          "com.apple.keylayout.US"
          "com.apple.keylayout.German"
        ];
        description = ''
          The keyboard layouts available in the input menu, by input-source id
          (`com.apple.keylayout.*`). null (the default) leaves your layouts
          alone. List them with:

          ```
          hausax input-sources --all
          ```

          THIS ONE OWNS THE LIST. Unlike every other option in §5.6's groups, a
          non-null value here is exhaustive: layouts you don't name get
          disabled, because "add these and keep whatever else was there" makes
          a rice that can never remove a layout it once added. Non-keyboard
          input methods (emoji picker, press-and-hold) are never touched.

          Applied through the documented Text Input Sources API rather than by
          writing `com.apple.HIToolbox` directly. The plist route does work, but
          it resolves a layout by an English display name (`Swiss French`, not
          `SwissFrench`) next to a numeric id that is required and never
          validated — a table the rice would have to hardcode and would get
          wrong for exactly the layouts nobody here tests.
        '';
      };
    };

    # ---- power ----
    # §5.6's "Power" group, spiked 2026-08-08 — and deliberately NOT built on
    # nix-darwin's typed `power.sleep.*`, which shells out to `systemsetup`.
    # Measured on macOS 26.6.1: `systemsetup -setcomputersleep 17`, run while
    # the machine was on BATTERY, wrote the AC profile and left battery alone,
    # while nix-darwin discards its stderr. So those options configure a power
    # source the config never named. `pmset -b` / `-c` says which source it
    # means and is what this group uses.
    power =
      let
        mkTimer =
          what: source:
          lib.mkOption {
            type = lib.types.nullOr (lib.types.either lib.types.ints.positive (lib.types.enum [ "never" ]));
            default = null;
            example = 10;
            description = ''
              Minutes of idleness before ${what} while on ${source}, or
              `"never"`. null (the default) leaves macOS's own choice alone.

              A desktop Mac has no battery profile to write, so `pmset` warns
              and the rebuild carries on — set the `charger` half there.
            '';
          };
      in
      {
        displaySleep = {
          battery = mkTimer "the display sleeps" "battery";
          charger = mkTimer "the display sleeps" "the charger";
        };
        computerSleep = {
          battery = mkTimer "the Mac sleeps" "battery";
          charger = mkTimer "the Mac sleeps" "the charger";
        };
        diskSleep = {
          battery = mkTimer "the disk spins down" "battery";
          charger = mkTimer "the disk spins down" "the charger";
        };
        lowPowerMode = {
          battery = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            example = true;
            description = ''
              Low Power Mode while on battery. null (the default) leaves
              macOS's own choice alone.

              The setting with the clearest opinion in this group for a laptop:
              on for battery, off for the charger, is what most people want and
              almost nobody sets.
            '';
          };
          charger = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            example = false;
            description = ''
              Low Power Mode while plugged in. null (the default) leaves
              macOS's own choice alone.
            '';
          };
        };
      };
  };
}

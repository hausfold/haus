# Part of the nebelhaus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# den's options — macOS defaults, fonts, Homebrew policy, and the two
# accessibility keys that actually apply on macOS 26.
{ lib, config, ... }:

let
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
  options.nebelhaus = {
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

    # ---- fonts ----
    # Honest scope: this is the rice's type FAMILY — Ghostty's, and (since the
    # bar stopped hardcoding one of its own) sill's. `size` is the terminal's
    # alone: the bar's sizes come from ui.scale against the menu-bar band's
    # ceiling, because its pill geometry is built around them (../lib/bar.nix).
    fonts.mono = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "JetBrainsMono Nerd Font Mono";
        example = "Berkeley Mono";
        description = ''
          The rice's type family, as Ghostty's `font-family` names it.

          It reaches the terminal AND the menu bar: every pill label and icon
          sill draws is in this family, at sizes of its own (see
          `nebelhaus.ui.scale`). The workspace-logo glyphs are the one exception
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
      size = lib.mkOption {
        type = lib.types.ints.positive;
        default = builtins.floor (19 * config.nebelhaus.ui.scale + 0.5);
        # Prose, so literalMD — see nebelhaus.developer.languages in modules/options.nix.
        defaultText = lib.literalMD "19, scaled by nebelhaus.ui.scale";
        example = 24;
        description = ''
          Terminal font size in points. The single most useful knob for a
          larger-text machine, since it moves everything the rice actually
          lives in.

          19 (at ui.scale = 1.0) is the base for a reason worth knowing: the Ghostty window is
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
    # the way `nebelhaus.accessibility` says "needs Full Disk Access".
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
  };
}

# Part of the nebelhaus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# den's options — macOS defaults, fonts, Homebrew policy, and the two
# accessibility keys that actually apply on macOS 26.
{ lib, ... }:

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
        mkA11y = desc: lib.mkOption {
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
    # Honest scope: this is the TERMINAL font — Ghostty's family and size, and
    # the font package the rice installs for it. The bar (sill) deliberately
    # keeps its own Hack Nerd Font at its own tuned sizes; unifying the two is a
    # separate change, since the bar's pill geometry is built around them.
    fonts.mono = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "JetBrainsMono Nerd Font Mono";
        example = "Berkeley Mono";
        description = ''
          The terminal font family, as Ghostty's `font-family` names it.

          This should be a NERD FONT patched build: starship's prompt, lsd's
          icons, and yazi all draw with glyphs a stock font renders as tofu.
          If you change this, set `package` too — the rice can only install a
          font it's been given.
        '';
      };
      size = lib.mkOption {
        type = lib.types.ints.positive;
        default = 19;
        example = 24;
        description = ''
          Terminal font size in points. The single most useful knob for a
          larger-text machine, since it moves everything the rice actually
          lives in.

          19 is the default for a reason worth knowing: the Ghostty window is
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
  };
}

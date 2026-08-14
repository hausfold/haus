# Part of the nebelhaus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# snippets' options — espanso text expansion.
{ lib, ... }:

{
  options.haus = {
    snippets = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Text expansion via espanso: type a short trigger (say "@@") and it's
          replaced inline with a longer string (your email), in any app —
          browsers, Messages, and the terminal. espanso injects keystrokes, so
          it works where macOS's own text replacement doesn't (terminals,
          many Electron apps).

          Off by default: it installs the Espanso.app cask and needs a one-time
          macOS Accessibility grant (System Settings → Privacy & Security →
          Accessibility → enable Espanso) the first time it runs. haus runs
          the SIGNED app bundle rather than a nix-store binary on purpose, so
          that grant is keyed to a stable identity and survives reboots and
          nixpkgs bumps — you grant it once, not on every rebuild (and so the
          espanso troubleshooting window stops popping up at login, since that
          window only ever meant "the grant went missing").
        '';
      };
      matches = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              trigger = lib.mkOption {
                type = lib.types.str;
                example = "@@";
                description = "What you type.";
              };
              replace = lib.mkOption {
                type = lib.types.str;
                example = "ada@example.com";
                description = "What it expands to.";
              };
            };
          }
        );
        default = [ ];
        example = lib.literalExpression ''
          [
            { trigger = "@@"; replace = "ada@example.com"; }
            { trigger = "##"; replace = "+1 555 0100"; }
          ]
        '';
        description = ''
          The expansion table — one { trigger; replace; } per snippet, written
          to ~/.config/espanso/match/default.yml. Only espanso's plain
          trigger→replace form is exposed here; for dynamic matches (dates,
          shell output, forms) drop a hand-written .yml alongside it in
          ~/.config/espanso/match/ — espanso loads every file in that dir.
        '';
      };
    };
  };
}

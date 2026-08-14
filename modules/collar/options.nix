# Part of the nebelhaus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# collar's options — the auth policy: who you prove you are to, and what you're
# excused from proving it for.
{ lib, ... }:

{
  options.haus = {
    collar.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        The collar room: Touch ID for `sudo`, with `reattach` — the PAM shim
        that keeps the prompt working when sudo runs inside a terminal
        multiplexer (tmux/zellij/screen), where it otherwise beachballs.

        Off means macOS's stock password prompt everywhere, including for the
        rebuild below. Nothing else in haus depends on it.
      '';
    };

    collar.passwordlessRebuild = lib.mkOption {
      type = lib.types.bool;
      # NOT in-room taste, despite reading like it: this is an ungated root
      # grant (modules/collar/default.nix writes the sudoers drop-in whatever
      # `collar.enable` says), so the bare layer must not hand it out. A
      # desktop asks for it explicitly; nebelhaus does.
      default = false;
      description = ''
        Exempt system activation from authenticating at all: a sudoers rule
        granting NOPASSWD to `darwin-rebuild` and `haus-activate` at their
        stable /run/current-system paths. This is what makes `haus rebuild`,
        `haus rollback` and `bench try switch` a single uninterrupted command
        rather than one that stops for a fingerprint you already gave.

        Honest scope: this is a real root grant, and both commands take a path
        or flake ref you choose — so it means "anything I can build, I can
        activate as root, unprompted". That is the whole point (you already
        authenticated to build it), but on a shared or managed machine it's the
        knob to turn off. With it off, activation prompts via Touch ID (or a
        password when `enable` is false) and nothing else changes.
      '';
    };
  };
}

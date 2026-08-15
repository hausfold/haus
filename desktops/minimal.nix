# minimal — just the themed shell.
#
# The desktop `presets/minimal.nix` became. No bar, no tiling, no palette, no
# shelf: nothing that changes how the Mac behaves system-wide. What you get is
# the terminal experience — the prompt, the toolbelt, the colours — on an
# otherwise stock macOS.
#
# Still a DEVELOPER machine. "Minimal" here means few rooms, not few tools; a
# Mac with no developer tooling is `everyday`. Before `haus.developer` existed
# this distinction could not be made, and "minimal" quietly installed the whole
# toolbelt anyway.
#
# Deliberately absent, each for the same reason — it would reach outside the
# terminal, which is the one promise this desktop makes:
#
#   ai              coding agents are a room of their own; say
#                   `haus.ai.enable = true` in your host if you want them here
#   theme.ports     writes theme files into apps this desktop never installed
#   wallpaper       the desktop picture is not the shell
#   apps.videoPlayer  an editorial app pick, and the one thing here you may miss
#                   from haus: `haus.apps.videoPlayer.enable = true` brings
#                   IINA back in one host line
#   hush, tour      a Focus switch and a tutor both teach moves this
#                   selection doesn't ship
{
  haus = {
    collar = {
      enable = true;
      passwordlessRebuild = true;
    };

    developer = {
      enable = true;
      languages = [ "node" ];
    };

    fonts.mono.baseSize = 19;

    hearth.zellijStartLocked = true;

    theme.accent = "mauve";
  };
}

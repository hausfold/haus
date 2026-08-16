# hacker — the developer-focused desktop, the first one this repo shipped, and
# the one `mkHaus` selects when a consumer names none. Data only: every line is
# a desktop-safe public `haus` option, and identity, secrets and hardware stay
# in the host.
#
# What is here, and what deliberately isn't. This file says which ROOMS this
# desktop wants and which machine-wide CLAIMS it makes (the global hotkeys, the
# root grant, the desktop picture, writing themes into other people's apps).
# It does NOT restate the tuned values inside a room it turned on: a bar that
# is drawn is drawn properly by the Bar room itself, and duplicating those here
# would mean every retune had to be made twice and would drift the first time
# it wasn't. The rooms plan's "neutral, useful configuration when enabled" is
# what makes that split hold.
{
  haus = {
    ai = {
      enable = true;
      clients = [
        "claude"
        "opencode"
      ];
      default = "claude";
    };

    apps.videoPlayer.enable = true;

    security.touchId = {
      enable = true;
      passwordlessRebuild = true;
    };

    developer = {
      enable = true;
      languages = [ "node" ];
    };

    # Only the SIZE. The family stays a layer concern: a patched Nerd Font is
    # what makes the terminal render at all, so it is a requirement rather than
    # this desktop's taste (modules/core/options.nix says so at the option).
    fonts.mono.baseSize = 19;

    terminal = {
      floatBorder = "accent";
      rightClickFullscreen = true;
      zellijStartLocked = true;
    };

    focus.enable = true;

    keys = {
      leader = "caps";
      palette = "cmd-space";
      windowNav = "alt";
    };

    shelf.enable = true;

    launcher.enable = true;

    windows.enable = true;

    bar = {
      enable = true;
    };

    theme = {
      accent = "mauve";
      ports.enable = true;
    };

    tour.enable = true;

    wallpaper = {
      style = "minimal";
    };
  };
}

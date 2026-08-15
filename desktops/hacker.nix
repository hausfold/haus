# hacker — the developer-focused desktop, the first one this repo shipped, and
# the one `mkHaus` selects when a consumer names none. Data only: every line is
# a desktop-safe public `haus` option, and identity, secrets and hardware stay
# in the host.
#
# ⚠️ This file was `desktops/nebelhaus.nix` until 2026-08-14 (the rename note's
# §11). Nothing about what it configures changed with the name — it is still the
# opinionated developer machine, and it is still the builder's default. The
# rename put it in the same voice as its peers: `blank`, `minimal`, `everyday`,
# `hacker` all say who they are for.
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

    collar = {
      enable = true;
      passwordlessRebuild = true;
    };

    developer = {
      enable = true;
      languages = [ "node" ];
    };

    # Only the SIZE. The family stays a layer concern: a patched Nerd Font is
    # what makes the terminal render at all, so it is a requirement rather than
    # this desktop's taste (modules/den/options.nix says so at the option).
    fonts.mono.baseSize = 19;

    hearth = {
      floatBorder = "accent";
      rightClickFullscreen = true;
      zellijStartLocked = true;
    };

    hush.enable = true;

    keys = {
      leader = "caps";
      palette = "cmd-space";
      windowNav = "alt";
    };

    perch.enable = true;

    pounce.enable = true;

    prowl.enable = true;

    sill = {
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

# everyday — a Mac for someone who doesn't write code.
#
# The desktop `presets/everyday.nix` became. As a preset it was a LAYER: four
# lines you stacked on top of whichever whole desktop you had selected, which under
# the rooms model is exactly the thing that no longer exists — a host chooses
# exactly one desktop, and a desktop is a complete answer rather than a diff
# against another one. So the selection it implied is written out here.
#
# The judgement calls, which are the interesting part:
#
#   - Windows (windows) OFF. Tiling is good; remapping Caps Lock to a leader key
#     on someone else's Mac is not. They keep the window behaviour they know,
#     which is also why this desktop claims no leader.
#   - Launcher (pounce) ON. A search box that opens things is legible to
#     anyone — the one power feature that needs no explanation.
#   - Bar (bar) ON. A clock, battery and weather is a better menu bar, not a
#     different paradigm.
#   - Development OFF, and AI with it. Before `haus.developer` existed, turning
#     the rooms off still installed bun, fnm, opencode, lazygit and the
#     agent-worktree tooling, so "a haus for my parents" could not be expressed
#     at all. AI follows rather than leads: coding agents on a machine that
#     ships no coding tools is the room enabling itself for nobody.
#
# Where this differs from what the old `presets/everyday.nix` produced when it
# was layered on hacker, stated in full because a consumer moving from that
# preset to this desktop is following an instruction we wrote:
#
#   ai.enable            true → FALSE, on purpose; see above. Say
#                        `haus.ai.enable = true` in your host if you want them.
#   keys.leader          "caps" → unset, and keys.windowNav with it. Both are
#                        the tiler's, and that room is off, so they moved nothing either
#                        way — stated here so the diff isn't mistaken for a loss.
#   developer.languages  ["node"] → empty, which follows from the room being off.
#
# Everything else the preset inherited from hacker is restated below,
# including the two that would otherwise be quiet losses on exactly the machine
# least able to diagnose them: `security.touchId.passwordlessRebuild` (without it every
# `haus rebuild` stops for a sudo password) and `focus` (the Focus switch).
#   - Tour ON, and AUTHORED. The one that needed a second look: the built-in lap
#     is three leader moves plus the palette, so with Windows off it had nothing
#     left to teach and drew no pill at all — a tutor for the person who most
#     needs one, shipping nothing, silently. One step, the launcher, which is
#     the only move an everyday machine has. `{palette}` rather than a typed
#     "⌘ Space" so the hint still names the right key if a host moves it.
{
  haus = {
    security.touchId = {
      enable = true;
      passwordlessRebuild = true;
    };

    fonts.mono.baseSize = 19;

    focus.enable = true;

    keys.palette = "cmd-space";

    shelf.enable = true;

    launcher.enable = true;

    bar.enable = true;

    theme = {
      accent = "mauve";
      ports.enable = true;
    };

    tour = {
      enable = true;
      steps = [
        {
          hint = "press {palette}, type tour, hit ↵ — that's how you open anything";
          detect = "palette";
        }
      ];
    };

    wallpaper.style = "minimal";
  };
}

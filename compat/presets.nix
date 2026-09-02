# The retired `presets` format, kept working for one release.
#
# A preset was a data-only desktop a consumer stacked into `extraModules` beside
# whichever whole desktop they had. The rooms model retires that vocabulary
# (`docs/model.md`, "What a desktop is") for one reason: whole selections
# do not stack. Two presets that disagree about an option stop the build with
# nothing to arbitrate them, and the docs were teaching people to compose
# exactly that. A host now chooses exactly ONE desktop, and a cross-cutting
# concern that is still useful — large print — becomes a room-owned profile.
#
# What each one became:
#
#   presets.full         →  the hacker desktop (the builder's default)
#   presets.minimal      →  desktops/minimal.nix
#   presets.everyday     →  desktops/everyday.nix
#   presets.large-print  →  haus.appearance.largePrint = true
#
# So this file is NOT the new spelling and must never grow a value: it is the
# OLD one, byte-for-byte, so that a consumer already passing
# `extraModules = [ haus.presets.everyday ]` gets the machine they had plus a
# warning naming the replacement. That is why the values are restated here
# rather than read out of the desktop files — a desktop is a complete
# selection at the desktop priority, while these are a layer at normal
# priority, and pointing one at the other would silently change both what a
# consumer gets and who wins.
#
# One shape DID change: `presets.<name>` was a PATH and is a module now, so
# `import haus.presets.everyday` and `haus.lib.checkRice haus.presets.everyday`
# no longer work. Nothing a consumer's machine does depends on that — it was the
# documented way to self-test a preset FILE, and the replacement is
# `lib.checkDesktop` on a desktop file.
#
# The first three are exercised as their new spellings by `nix flake check`'s
# `catalogue`; `large-print` is additionally pinned old-against-new, evaluated
# as whole systems, by `fragment-compat`. Delete
# this directory and the `presets` flake output together, in one commit, once
# the migration window closes.
let
  deprecated =
    replacement: values:
    { ... }:
    {
      _file = "compat/presets.nix";
      warnings = [
        (
          "haus.presets is retired: ${replacement}. The preset format let two whole "
          + "selections stack, which the rooms model replaces with exactly one desktop per "
          + "host — see https://hausfold.co/docs/haus/desktops/creating/. This alias keeps your "
          + "current machine building and will be removed."
        )
      ];
      haus = values;
    };
in
{
  full = deprecated "select the hacker desktop, which `mkHaus` already does when you name none" {
    bar.enable = true;
    windows.enable = true;
    launcher.enable = true;
    tour.enable = true;

    developer.enable = true;
  };

  minimal = deprecated "pass `desktop = haus.desktops.minimal`" {
    bar.enable = false;
    windows.enable = false;
    launcher.enable = false;
    tour.enable = false;

    # `ai.enable = false` sat here from #388 until 2026-08-19, and it was never
    # this preset's value: a preset is applied ON TOP of the default desktop, so
    # hacker's AI room came with it, and terminal asserted that agent lanes
    # needed the tiler this preset turns off. The assertion is a warning now —
    # a lane opens as an ordinary macOS window where there is nothing to tile it
    # onto — so the line is gone and the preset is back to only what it always
    # set.

    developer.enable = true;
  };

  everyday = deprecated "pass `desktop = haus.desktops.everyday`" {
    bar.enable = true;
    launcher.enable = true;
    tour.enable = true;
    tour.steps = [
      {
        hint = "press {palette}, type tour, hit ↵ — that's how you open anything";
        detect = "palette";
      }
    ];

    windows.enable = false;

    # `ai.enable = false` sat here from #388 until 2026-08-19, and it was never
    # this preset's value: a preset is applied ON TOP of the default desktop, so
    # hacker's AI room came with it, and terminal asserted that agent lanes
    # needed the tiler this preset turns off. The assertion is a warning now —
    # a lane opens as an ordinary macOS window where there is nothing to tile it
    # onto — so the line is gone and the preset is back to only what it always
    # set.

    developer.enable = false;
  };

  large-print = deprecated "set `haus.appearance.largePrint = true` in your desktop or your host" {
    ui.scale = 1.4;

    theme.contrast = "high";

    accessibility.increaseContrast = true;

    displays.main.uiScale = "larger-text";
  };
}

# large-print — make everything the rice controls bigger and sharper.
#
# The third reference rice, and the one the option surface was rebuilt to make
# possible. It's deliberately NARROW: it's about seeing, not about who you are, so
# it says nothing about the developer pack, the rooms, or the keymap. Compose it
# with whichever rice describes the person:
#
#   extraModules = [ nebelhaus.presets.everyday nebelhaus.presets.large-print ];
#
# That composition is the actual readiness test from the roadmap, and it's why
# this file sets three options rather than fifteen. A preset that had to restate
# `everyday` to be useful would mean the option surface still couldn't separate
# "a Mac for someone who doesn't write code" from "a Mac you can read".
#
# What it moves, and it is worth knowing exactly:
#
#   ui.scale = 1.4        terminal font 19 → 27 pt, Dock icons 48 → 67, and prowl's
#                         window gaps, all at once. Pin any single one afterwards
#                         (nebelhaus.fonts.mono.size = 24) and it wins — scale sets
#                         defaults, not values.
#   theme.contrast         body text goes from 11.3:1 to 19.9:1 against the
#                         background, across every tool the rice colours. Measured
#                         in nebelung's CI, not eyeballed.
#   accessibility.*        the same contrast lift for NATIVE macOS apps, which the
#                         palette can't reach. FDA-gated (see the option), so it
#                         sharpens the result where it applies and is silently
#                         skipped where it doesn't — never load-bearing.
#
# What it does NOT move, stated here because a large-print rice that quietly
# under-delivers is worse than one that says where it stops:
#
#   - System-wide text size. macOS has no working declarative lever for it — the
#     `universalaccess` FontSizeCategory key stores a value and posts no change
#     notification, so apps never re-read it (notes/macos-settings-matrix.md).
#     The real lever is display resolution, i.e. nebelhaus.displays, not built yet.
#     Until then: System Settings ▸ Displays ▸ "Larger Text".
#   - Third-party apps. Nothing outside the rice follows any of this.
#   - The menu bar (sill) and the palette (pounce). Both are sized by geometry
#     tuned to the macOS menu-bar band and to their own layouts; a multiplier
#     breaks the alignment rather than enlarging it. They need their own sizing
#     pass — the honest version of "ui.scale doesn't reach here yet".
#   - A more legible FONT FAMILY. Not an omission by choice: a data-only rice
#     can't set nebelhaus.fonts.mono.package, because that option takes a package
#     and reaching `pkgs` is exactly what data-only forbids. So this preset makes
#     the existing font bigger and leaves the family alone. That limit is a finding
#     about the option surface, recorded in the roadmap rather than worked around.
#
# Light mode is one line away if it reads better for you — some people find dark
# text on light easier at size, some the reverse:
#
#   nebelhaus.theme.flavor = "latte";
{
  nebelhaus = {
    ui.scale = 1.4;

    theme.contrast = "high";

    accessibility.increaseContrast = true;
  };
}

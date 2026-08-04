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
#   ui.scale = 1.4        terminal font 19 → 27 pt, the whole command palette
#                         (rows, text, icons, and the panels behind it), the menu
#                         bar's type (17 → 21 pt icons, 14 → 18 pt labels — capped,
#                         see below), Dock icons 48 → 67, and prowl's window gaps,
#                         all at once. Pin any single one afterwards
#                         (nebelhaus.fonts.mono.size = 24) and it wins — scale sets
#                         defaults, not values.
#   theme.contrast         body text goes from 11.3:1 to 19.9:1 against the
#                         background, across every tool the rice colours. Measured
#                         in nebelung's CI, not eyeballed.
#   accessibility.*        the same contrast lift for NATIVE macOS apps, which the
#                         palette can't reach. FDA-gated (see the option), so it
#                         sharpens the result where it applies and is silently
#                         skipped where it doesn't — never load-bearing.
#   displays.main          the screen's scaled resolution, one step from the panel's
#                         default toward larger text. This is the only line here
#                         that reaches apps the rice has never heard of, because it
#                         changes what a point *means* rather than what a config
#                         file says — so for someone who actually needs large print
#                         it does more than the other three combined.
#
#                         `main` rather than `internal` on purpose: on a laptop
#                         they are the same panel, but on a Mac mini or a
#                         clamshelled MacBook `internal` matches nothing (skipped
#                         with a note) — so keying on the built-in panel would make
#                         this preset quietly do nothing on the desk setup most
#                         likely to need it. Name a specific monitor by UUID in your
#                         host file for per-display control; `hausdisp list` prints
#                         the UUIDs of whatever is attached.
#
# What it does NOT move, stated here because a large-print rice that quietly
# under-delivers is worse than one that says where it stops:
#
#   - The macOS text-size setting, which is a different thing from the above and
#     still has no working declarative lever: the `universalaccess`
#     FontSizeCategory key stores a value and posts no change notification, so
#     apps never re-read it (notes/macos-settings-matrix.md). Display scaling is
#     the lever that works, and it moves everything at once rather than only the
#     handful of Apple apps that adopted Dynamic Type.
#   - Third-party apps' own font settings. Nothing outside the rice follows
#     ui.scale — they follow the display, which is why the line above matters.
#   - The menu bar's HEIGHT. Its type grows (above), but the bar itself can't:
#     36pt of bar with 28pt pills is what keeps them inside the 32pt band macOS's
#     own hover-reveal covers, and that band is macOS's — fixed, with no setting
#     behind it (measured: safe-area inset 32pt, NSStatusBar thickness 22pt,
#     menu-bar font 13pt, none of them writable). So the bar's type follows
#     ui.scale to 1.25x and then stops, and at 1.4 this preset is already at that
#     ceiling. The lever that DOES make the whole bar bigger is displays.main
#     below — it changes what a point means, which is the only thing the band
#     responds to.
#     (The palette used to be listed here too. It isn't any more: pounce grew a
#     `scale` of its own, and ui.scale drives it — so on a large-print Mac the
#     thing you launch everything with is now among the things that got bigger,
#     which for someone who doesn't open a terminal is most of the desktop they
#     actually touch.)
#   - A more legible FONT FAMILY — but this one is a CHOICE now, not a limit.
#     It used to be the limit: `fonts.mono.package` takes a package, and reaching
#     `pkgs` is exactly what a data-only rice forbids, so the family was
#     unreachable from a preset. `fonts.mono.packageName` (#215) closed that, and
#     this preset still leaves the family alone because a typeface is taste and a
#     legibility LAYER shouldn't decide yours. See the two lines below if it is.
#
# Two things this preset deliberately doesn't decide, both one line away.
#
# A more legible typeface — Atkynson Mono is Atkinson Hyperlegible's monospaced
# sibling, drawn by the Braille Institute for exactly this problem:
#
#   nebelhaus.fonts.mono.packageName = "nerd-fonts.atkynson-mono";
#   nebelhaus.fonts.mono.name        = "AtkynsonMono Nerd Font";
#
# And light mode, if it reads better for you — some people find dark text on
# light easier at size, some the reverse:
#
#   nebelhaus.theme.flavor = "latte";
{
  nebelhaus = {
    ui.scale = 1.4;

    theme.contrast = "high";

    accessibility.increaseContrast = true;

    displays.main.uiScale = "larger-text";
  };
}

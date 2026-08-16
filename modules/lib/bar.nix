# Resolve haus.ui.scale into the menu bar's geometry: how big its type is
# drawn, and how much room the tiling manager has to leave beside it. Imported
# the same way as keys.nix / nebelung.nix — a plain function, no module system.
#
#   bar = import ../lib/bar.nix { inherit lib; scale = config.haus.ui.scale; };
#
# TWO rooms read this, which is why it isn't just a let-binding in bar: bar
# draws the bar (its fonts), and windows reserves the screen edge the bar sits on
# (its gaps). Those two numbers have to move together — a bar whose type grew and
# a window that didn't step back is exactly the cramped look this exists to avoid
# — and the previous arrangement had windows reserving a magic `40` with no link to
# what bar actually drew.
#
# THE CEILING, and why there is one at all. The bar is the one rice surface that
# cannot grow proportionally, and the limit is macOS's rather than ours:
# sketchybarrc pins 36pt of bar with 28pt pills so the pills sit inside the 32pt
# menu-bar band that macOS's own hover-reveal covers (core forces that reveal
# opaque; taller pills poke out below it). Measured on a notched MacBook rather
# than assumed: safe-area inset 32pt, NSStatusBar.thickness 22pt, menu-bar font
# 13pt — and none of the three is a preference. There is no menu-bar-size setting
# on macOS; `NSStatusItemSpacing` / `NSStatusItemSelectionPadding` move the
# spacing between items, not their size. The only lever that makes the whole bar
# bigger is the display's scaled resolution (haus.displays), which changes
# what a point MEANS rather than how many of them the bar gets.
#
# So the bar's HEIGHT never scales, its TYPE scales to the largest that still fits
# a 28pt pill, and a rice past that point silently gets the ceiling. A bar that
# quietly stops growing beats one whose pills clip against a band it doesn't own.
{
  lib,
  scale,
}:

let
  # 1.25 puts the tallest glyph (the 17pt icon font) at 21pt, leaving ~3.5pt of
  # clearance top and bottom inside a 28pt pill. Below 0.8 the labels stop being
  # readable at arm's length, which is the only reason the bar shrinks at all.
  ceiling = 1.25;
  floor' = 0.8;
  round = n: builtins.floor (n + 0.5);
in
rec {
  # What the bar actually scales by — ui.scale, held between the two limits.
  typeScale = lib.min ceiling (lib.max floor' scale);

  # True when the rice asked for more than the band can give. Not currently
  # surfaced as a warning: hitting the ceiling is a fine, quiet outcome, and a
  # large-print rice hits it by design. Exposed so a future `haus doctor` can say
  # "your bar is at its limit; the display is the lever that isn't" rather than
  # leaving someone to wonder why the bar stopped growing with everything else.
  atCeiling = scale > ceiling;

  # Fixed, both of them. See the header: these belong to the menu-bar band.
  barHeight = 36;
  pillHeight = 28;

  # The SECOND bar (haus.bar.bottom.enable) is the one bar that does NOT belong
  # to the band, so it doesn't pay for it. `barHeight`'s 36 is 28pt of pill plus
  # the 4pt of slack above and below that SketchyBar's centring needs to land the
  # pill at y=4..32 — inside the 32pt strip macOS's hover-reveal covers. At the
  # bottom of a display there is no strip and no reveal: macOS reserves nothing
  # there, so every point of this bar is a point windows has to take out of the
  # tiled windows, and 4pt of it was buying clearance from a band that isn't
  # there.
  #
  # So: the same 28pt pill, 2pt of centring slack, and nothing else — a 32pt
  # strip, which is exactly the height of the band the top bar's pills sit in.
  # The two bars read as the same size because their PILLS are the same size;
  # that was always the part anyone could see.
  bottomHeight = pillHeight + 4;

  # Point sizes by role, rendered with the `.0` sketchybar writes everywhere so a
  # generated size is indistinguishable from a hand-tuned one. At typeScale = 1.0
  # these are byte-identical to the values sketchybarrc carried before any of this
  # existed, which is what makes the whole feature a no-op for a rice that doesn't
  # scale.
  fontSize = base: "${toString (round (base * typeScale))}.0";
  sizes = {
    icon = fontSize 17; # bar icons, workspace letters, the leader arrow
    label = fontSize 14; # the default pill label
    small = fontSize 13; # tighter labels (harvest, tour, popup rows)
    tiny = fontSize 12; # the popup's italic note
    appIcon = fontSize 16; # sketchybar-app-font glyphs (workspace app logos)
    # `icon`, for the handful of glyphs that are as WIDE as they are tall.
    #
    # Nerd Font's Mono builds fit every patched glyph into one cell, and the fit
    # is by width — so a tall-and-narrow glyph (a calendar, a bolt) lands at
    # ~0.67em of ink while a square one (the octocat, a logo mark) is squeezed
    # to ~0.59em by its own width. Same point size, visibly smaller pill. Two
    # points back is what makes the two read as one family; it costs nothing
    # vertically, because the ink is what grew and the ink was the short part.
    iconWide = fontSize 19;
  };

  # Extra separation between the bar and the tiled windows beside it, in points,
  # added by windows to whichever outer edge the bar sits on.
  #
  # It exists because of the ceiling rather than in spite of it. The pill cannot
  # get taller, so everything the type gains it gains INSIDE a box the same size:
  # a scaled bar reads as a fuller bar, and a full bar flush against a window edge
  # is the part that looks cramped — the pills stop being a strip of chrome and
  # start being the top of the window. Handing the growth back as space beside the
  # bar is the compensation the pill couldn't take vertically.
  #
  # It is NOT a shadow buffer, and shouldn't be floored above 0 to serve as one.
  # Where a top bar sits flush against the windows — an external's top, the one
  # edge macOS reserves nothing at — it does take their drop shadow onto its
  # strip. That shadow is offset downward, though, and measures flat above a
  # window. The reasoning and the measurement (and its one caveat: the probe is
  # the built-in's strip, not the flush external's) are at `barEdge` in
  # ./gaps.nix, which owns every number in windows's [gaps] block.
  #
  # 0 at scale 1.0 (nothing grew, nothing to compensate) rising to 10pt at the
  # ceiling, which is a third of a pill — enough to read as deliberate, small
  # enough that it never eats a row of a tiled window. Floored at 0 rather than
  # going negative below 1.0: a smaller bar may take less room, but a tiling
  # manager asked for a negative gap does something worse than look tight.
  room = lib.max 0 (round ((typeScale - 1.0) / (ceiling - 1.0) * 10));
}

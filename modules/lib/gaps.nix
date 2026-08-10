# Resolve haus.ui.scale and the bar's position into the tiling gaps: how much
# space AeroSpace leaves between windows, and how much it leaves at each edge of
# each display. Imported the same way as bar.nix / keys.nix — a plain function,
# no module system.
#
#   gaps = import ../lib/gaps.nix {
#     inherit lib;
#     scale = config.haus.ui.scale;
#     sill  = config.haus.sill;
#   };
#
# TWO rooms read this. prowl WRITES the numbers into aerospace.toml, which is
# what makes them true. wallpaper READS them to find the rectangle a tiled window
# will cover, so the debug band it draws in the corner lands exactly under the
# window rather than beside it. Those two have to agree, and the only way they
# can't drift is for one of them not to own the numbers.
#
# Every value here is POINTS, the unit AeroSpace speaks. A wallpaper is pixels,
# so its caller scales — see `outermost` at the bottom.
{
  lib,
  scale,
  sill,
}:

let
  bar = import ./bar.nix { inherit lib scale; };

  # Window gaps follow haus.ui.scale. Base values are the tuned ones: 10 on
  # the built-in display, 20 around an external. One outer edge reserves bar room
  # — whichever edge sill's bar sits on (haus.sill.position) — and that edge is
  # sized from the bar itself (`barEdge` below), not from a base value here.
  gap = base: builtins.floor (base * scale + 0.5);

  # A gap plus the bar's breathing room, for the edge the bar is on. Written as
  # one function so the two can't be added in one branch and forgotten in another.
  #
  # `bar.room` is a scaled bar's growth handed back as space BESIDE the bar: the
  # pill's height belongs to the macOS menu-bar band rather than to us, so
  # everything the type gains it gains inside a box that didn't move, and the bar
  # reads as full rather than as bigger. 0 at ui.scale = 1.0, 10pt at the bar's
  # ceiling. (../lib/bar.nix carries the whole argument.)
  barGap = base: gap base + bar.room;

  # The reservation for an edge the bar actually OCCUPIES: the bar's own height
  # plus the same breathing room, and nothing else. It is a measurement, not a
  # tuned gap, which is why it doesn't go through `gap`/`barGap`:
  #
  # - It must equal what sill draws. This was a hardcoded 40 from back when the
  #   bar was 40pt tall; sill dropped to 36 in the Tahoe menu-bar fix (28pt pills
  #   have to sit inside the 32pt band macOS's hover-reveal covers) and the
  #   reservation never followed, so every bar edge carried 4pt of dead space —
  #   most visibly under haus.sill.bottom.enable, where it was the strip between
  #   the tiled windows and the second bar.
  # - It must NOT scale. `gap 40` multiplies by haus.ui.scale, but the bar's
  #   height is the one rice surface that can't grow (../lib/bar.nix: the height
  #   belongs to the macOS menu-bar band, only the TYPE inside it scales). At
  #   ui.scale = 1.25 the old form reserved 60pt for a bar still drawing 36.
  #
  # Which leaves a top bar's edge FLUSH with the windows at scale 1.0 — on the
  # EXTERNAL, the one display whose top macOS reserves nothing at. That is fine,
  # and it is measured rather than assumed. The open question when the stale 40
  # came out was the 4pt it had been leaving behind: a `top`/`auto` bar is not
  # lifted (bar_topmost() in the generated position.sh lifts only a fixed
  # `bottom` bar), so the tiled window composites its macOS drop shadow straight
  # onto the strip. But that shadow is offset DOWNWARD — the heavy edge is the
  # one UNDER a window, which is the whole reason sill's second bar has to be
  # lifted and this one doesn't. The probe was the built-in's top strip, the
  # same unlifted bar sitting 6pt further off (the notch band plus `barGap 10`):
  # the pixels 1pt above the window read identical to the pixels at the very top
  # of the screen, no gradient at all, and the left outer gap — where a side
  # shadow would show if any edge but the bottom carried one — is just as flat.
  # So the 4pt was buying nothing, and handing it back through `room` would buy
  # nothing either: a 4pt buffer cannot hold off a shadow that blurs well past
  # 4pt. If an external ever does show one, the answer is to lift the bar
  # (topmost) rather than to widen the gap.
  barEdge = bar.barHeight + bar.room;

  # Same rule for sill's SECOND bar, which is shorter (32) because it is the one
  # bar that doesn't sit in the menu-bar band and so doesn't pay the band's
  # clearance — see `bottomHeight` in ./bar.nix. It matters more here than
  # anywhere else that the number is the bar's own: at the bottom of a display
  # macOS reserves nothing, so this gap is the ONLY thing keeping the tiled
  # windows off a bar that draws above them (topmost=window).
  bottomEdge = bar.bottomHeight + bar.room;

  # No sill, no bar, no reservation — `noBar` short-circuits both edge tables
  # below to the tuned gaps. This used to be a `barPos` fallback of `"top"`,
  # which made a rice with `haus.sill.enable = false` reserve `barEdge` at an
  # EXTERNAL's top edge for a bar nobody draws: 36pt of dead wallpaper along the
  # top of every external display. The built-in never showed it — a top bar
  # reserves `barGap 10` there, which is the tuned gap plus `bar.room`, and
  # `room` is 0 on an unscaled rice — so it only ever bit the display that
  # can't be tested without plugging one in.
  noBar = !sill.enable;
  barPos = sill.position;

  # sill's optional SECOND bar (haus.sill.bottom.enable) draws at the bottom of
  # every display, AS WELL AS the main bar rather than instead of it — so when
  # it's on, the bottom edge reserves room whatever `barPos` would have said.
  # macOS is no help here: it excludes the menu-bar strip at the top of a display
  # and excludes NOTHING at the bottom, so without this the second bar simply
  # draws over the tiled windows on both screens. (Both bars on the SAME edge is
  # the one case this can't fix — sill warns about it.)
  bottomBar = sill.enable && sill.bottom.enable;

  pair = builtin: external: { inherit builtin external; };

  # The bar-room reservation follows the bar. A built-in display's TOP is under
  # the notch/menu-bar strip macOS already excludes, so a top bar needs no extra
  # reservation there; the external, and a built-in's bottom, have no such strip,
  # so the room is carved explicitly. `auto` maps cleanly onto the per-monitor
  # keys — it pins the bar to the external's bottom and the built-in's notched top
  # — so statically it reads as "bottom on external, top on built-in". (Caveat:
  # docked with the lid open the bar sits at the bottom on BOTH displays; aerospace
  # gaps can't flip per dock-state, so the built-in keeps its notch-tuned top in
  # `auto`, leaving a small overlap at the built-in's bottom in that one case.)
  #
  # On the built-in with a top bar that means `barGap 10` rather than `barEdge`:
  # the notch strip already excludes the bar's height there, so the reservation
  # stays at its tuned 10 — but the pills still end right where the windows begin,
  # which is the one place the breathing room matters MOST rather than least.
  top =
    if noBar then
      pair (gap 10) (gap 20)
    else
      {
        top = pair (barGap 10) barEdge;
        bottom = pair (gap 10) (gap 20);
        auto = pair (barGap 10) (gap 20);
      }
      .${barPos};

  bottom =
    if bottomBar then
      # `bottomEdge` unless the MAIN bar is parked down here too, where the
      # taller of the two is what has to be cleared. The test is `!= "top"`, not
      # `== "bottom"`: `auto` resolves to the bottom whenever an external display
      # is attached, which is the same overlap, and it's the exact condition
      # sill's own "the two bars share the bottom edge" warning uses.
      let
        edge = if barPos != "top" then barEdge else bottomEdge;
      in
      pair edge edge
    else if noBar then
      pair (gap 10) (gap 20)
    else
      {
        top = pair (gap 10) (gap 20);
        bottom = pair barEdge barEdge;
        auto = pair (gap 10) barEdge;
      }
      .${barPos};

  # Left and right never reserve bar room: sill's bar spans a display's full
  # width, so it is only ever ON a horizontal edge.
  side = pair (gap 10) (gap 20);
in
{
  # Between windows, per monitor class.
  inner = side;

  # At each edge of the screen, per monitor class. prowl writes these straight
  # into aerospace.toml's [gaps] block.
  outer = {
    inherit top bottom;
    left = side;
    right = side;
  };

  # The WIDEST reservation any attached display could be using, per edge — the
  # inset at which a point is inside every monitor class's tiled area rather than
  # only some. This is the number a surface drawing UNDER the windows wants:
  # anything drawn at least this far in is covered on the built-in and on an
  # external alike, where taking the built-in's narrower gap would leave the
  # drawing peeking out of an external's wider one.
  outermost = lib.mapAttrs (_: e: lib.max e.builtin e.external) {
    inherit top bottom;
    left = side;
    right = side;
  };
}

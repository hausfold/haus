# Appearance — the room's own profile, and nothing else.
#
# The room itself is spread across the modules that own each surface (theme,
# wallpaper, fonts in core, the accessibility keys in core, `ui.scale` in
# modules/options.nix). What lives HERE is the one thing none of them owns: a
# named profile that answers a whole-machine question — "make this readable" —
# by setting four of their options at once.
#
# It was `presets/large-print.nix`, a top-level file a consumer stacked into
# `extraModules` beside a whole rice. Under the rooms model whole selections do
# not stack, so a cross-cutting CONCERN that is still useful becomes a
# room-owned profile instead (notes/rooms-desktops.md, step 5). Same four
# values, one address, and it is desktop-safe: a desktop may name it, and a host
# may override any single value it sets with a plain assignment.
#
# Every value is `mkDefault` (1000), which is what makes that ladder work:
#
#   100   the host       haus.ui.scale = 1.0;     ← wins
#   900   the desktop    haus.ui.scale = 1.2;     ← wins over the profile
#   1000  here           haus.ui.scale = 1.4;
#   1500  the option's own default
#
# Adding a value here is therefore additive for a machine that never asked for
# large print, and overridable for one that did.
{ config, lib, ... }:

let
  cfg = config.haus.appearance;
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.largePrint {
      haus = {
        ui.scale = lib.mkDefault 1.4;

        theme.contrast = lib.mkDefault "high";

        accessibility.increaseContrast = lib.mkDefault true;

        # `main`, not `internal` — see the option's description. This CREATES
        # the entry when none exists, so a host naming its own panel by UUID is
        # untouched and a host that also names `main` simply outranks this.
        displays.main.uiScale = lib.mkDefault "larger-text";
      };
    })

    # ---- reduceMotion: the layer's own animations, plus Apple's --------------
    # The second profile in this room, and the same ladder — every value a
    # `mkDefault`, so a host puts any one of them back by name.
    #
    # It COMPOSES with macOS rather than duplicating it, which is the whole
    # design question the option had to answer. Three motion surfaces exist on a
    # haus machine and they are not the same kind of thing:
    #
    #   haus.animations                 five macOS timing keys, curated. NOT set
    #                                   here: "fast" speeds the Dock UP rather
    #                                   than removing motion, and coming back
    #                                   from it only stops writing rather than
    #                                   restores. A legibility switch must not
    #                                   leave a Dock permanently retuned.
    #   haus.accessibility.reduceMotion Apple's own switch. SET here, because a
    #                                   machine that quietened its own pills and
    #                                   left Spaces sliding answered the question
    #                                   halfway — and because it is the one lever
    #                                   that reaches apps haus never heard of.
    #   the five leaves below           haus's own motion. Nothing in macOS
    #                                   reaches these; they are why this option
    #                                   exists at all rather than being an alias.
    #
    # The ORDER of dependence matters and runs one way only: Apple's flag is
    # FDA-gated at its own option, so a machine without the grant loses it with a
    # warning — and every leaf below still applies, because none of them needs a
    # permission. Deriving haus's own half FROM the accessibility key (the
    # tempting factoring: "read NSWorkspace, follow it") would have made the
    # whole feature contingent on TCC, which is §5.2's rule about ui.scale in a
    # different room: a semantic token may only be derived from keys that are
    # reachable unconditionally.
    (lib.mkIf cfg.reduceMotion {
      haus = {
        accessibility.reduceMotion = lib.mkDefault true;

        # The bar's three: two hover marquees and the logo's hover sweep. All
        # three are hover-triggered, which is precisely what makes them worth an
        # option — motion that answers the pointer is motion you meet by
        # accident, on the way somewhere else.
        bar.logo.sweep = lib.mkDefault false;
        bar.media.marquee = lib.mkDefault false;
        bar.calendar.marquee = lib.mkDefault false;

        # The tiler's two unasked moves: the pointer teleporting to whatever
        # took focus, and a whole workspace being replaced when a ⌘Q empties
        # this one. Gravity is the largest single movement haus makes.
        windows.mouseFollowsFocus = lib.mkDefault false;
        windows.gravity = lib.mkDefault false;
      };
    })
  ];
}

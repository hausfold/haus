# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
#
# Appearance's own option — the room-owned PROFILE that used to be a top-level
# preset file (`presets/large-print.nix`). It is not a room switch: the
# Appearance room is always present, and this is one named way to configure it.
{ lib, ... }:

{
  options.haus.appearance.largePrint = lib.mkOption {
    type = lib.types.bool;
    default = false;
    example = true;
    description = ''
      Make everything haus controls bigger and sharper, in one line. Deliberately
      NARROW: it is about seeing, not about who you are, so it says nothing about
      which rooms you run — set it in any desktop, or in your host on top of one.

      It moves four things, each as a DEFAULT, so pinning any single one by hand
      still wins — with one asymmetry worth knowing: a DESKTOP that sets one of
      the four beats this profile even when the profile was switched on in your
      host, because the desktop's values sit above a room's defaults in the
      priority ladder. Set the value itself in your host to settle it:

        haus.ui.scale = 1.4              the terminal font (19 → 27 pt), the whole
                                         command palette, the bar's type (to its
                                         ceiling, see below), Dock icons 48 → 67,
                                         Finder's large sidebar rows, windows's gaps
        haus.theme.contrast = "high"     body text 11.3:1 → 19.9:1 against the
                                         background, across every tool haus
                                         colours. Measured in nebelung's CI.
        haus.accessibility.increaseContrast = true
                                         the same lift for NATIVE macOS apps, which
                                         the palette cannot reach. FDA-gated at the
                                         option, so it sharpens the result where it
                                         applies and is skipped where it doesn't.
        haus.displays.main.uiScale = "larger-text"
                                         one step of the screen's scaled resolution
                                         toward larger text. The only line here that
                                         reaches apps haus has never heard of,
                                         because it changes what a point MEANS.

      `main` rather than `internal` on purpose: on a laptop they are the same
      panel, but on a Mac mini or a clamshelled MacBook `internal` matches
      nothing — so keying on the built-in panel would quietly do nothing on the
      desk setup most likely to need this. Name a specific monitor by UUID in
      your host file for per-display control; `hausdisp list` prints them.

      What it does NOT move, stated here because a large-print machine that
      quietly under-delivers is worse than one that says where it stops:

        - macOS's own text-size setting. `universalaccess`'s FontSizeCategory
          key stores a value and posts no change notification, so apps never
          re-read it. Display scaling is the lever that works.
        - Third-party apps' own font settings. Nothing outside haus follows
          `ui.scale` — they follow the display, which is why the line above
          matters.
        - The perch shelf, which sizes itself from the screen because it hangs
          off the notch. Scaling the display shrinks its width in points by
          exactly the factor that makes a point bigger.
        - The menu bar's HEIGHT. Its type grows to a 1.25x ceiling and stops:
          36pt of bar with 28pt pills is what keeps them inside the 32pt band
          macOS's own hover-reveal covers, and that band is macOS's. The lever
          that does move it is the display scaling above.
        - A more legible FONT FAMILY, which is a choice rather than a limit.
          A typeface is taste and a legibility profile should not decide yours;
          Atkynson Mono is Atkinson Hyperlegible's monospaced sibling, drawn by
          the Braille Institute for exactly this problem:

            haus.fonts.mono.packageName = "nerd-fonts.atkynson-mono";
            haus.fonts.mono.name        = "AtkynsonMono Nerd Font";

        - Light mode, if it reads better for you: `haus.theme.flavor = "latte"`.
    '';
  };

  # The layer's OWN motion, which is what makes this an option rather than a
  # pointer at Apple's. `haus.animations` curates five macOS timing keys and
  # `haus.accessibility.reduceMotion` flips Apple's switch; neither reaches a
  # sweep the bar draws or a workspace the tiler pulls you to. Those are ours,
  # they run with every Apple switch flipped, and this is the one address that
  # turns them off. It COMPOSES with Apple's rather than duplicating it — see
  # the description, and modules/appearance/default.nix for the fan-out.
  options.haus.appearance.reduceMotion = lib.mkOption {
    type = lib.types.bool;
    default = false;
    example = true;
    description = ''
      Stop the things haus itself animates from animating. One switch, for a
      machine whose user is vestibular-sensitive, motion-sick, or simply done
      with movement in the corner of their eye.

      It exists because macOS's own motion is already curated — `haus.animations`
      for the Dock's timings, `haus.accessibility.reduceMotion` for Apple's
      switch — and NEITHER of them reaches the motion haus draws. The bar's
      sweeps and the tiler's automatic moves are the layer's own; they run
      happily on a Mac with every Apple switch flipped, and until this option
      there was no way to quiet them short of turning off the pills that carry
      them.

      What it stops, all of it haus's own:

        the logo pill's hover sweep   six family accents turning through the
                                      mark whenever the pointer crosses it
                                      (`haus.bar.logo.sweep`)
        the media pill's marquee      a long track title sweeping past on hover
                                      (`haus.bar.media.marquee`)
        the calendar pill's marquee   the same, for a long meeting title
                                      (`haus.bar.calendar.marquee`)
        the pointer following focus   `haus.windows.mouseFollowsFocus`: a
                                      pointer teleporting across the desk is
                                      movement you did not make
        workspace gravity             `haus.windows.gravity`: the automatic pull
                                      back to a populated workspace when a ⌘Q
                                      empties this one — a whole screen changing
                                      under you, unasked

      Every one is set as a DEFAULT, so any single one goes back by name:
      this option `true` with `haus.bar.logo.sweep = true` keeps the sweep and
      drops the rest. Nothing loses information — a title too long for its pill
      is clipped rather than swept, and both dropdowns carry it in full.

      IT ALSO ASKS FOR macOS's OWN "Reduce motion"
      (`haus.accessibility.reduceMotion`), again as a default, because a machine
      that quietened its own five surfaces and left Spaces sliding would have
      answered the question halfway. Know that flag's blast radius before you
      take it: it is the single switch every browser reads as
      `prefers-reduced-motion: reduce`, so it rewrites the web too — mostly for
      the better, except on sites whose scroll-reveal animation is what makes
      their content visible at all. `haus.accessibility.reduceMotion = false` in
      your host keeps the local half without the web one.

      That composition is deliberate rather than convenient. Apple's flag is
      FDA-gated at its own option, so on a machine whose rebuilding app lacks
      Full Disk Access it is skipped with a warning — and everything above still
      applies, because haus's own half depends on no permission at all. A
      legibility switch that only worked with a grant would be the wrong shape.

      What it deliberately does NOT set is `haus.animations = "fast"`. That
      group speeds macOS's Dock timings UP rather than removing motion, and
      coming back from it only stops writing rather than restores — a
      motion-sensitivity switch has no business leaving a Dock permanently
      retuned.
    '';
  };
}

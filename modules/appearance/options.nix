# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
#
# Appearance's own option — the room-owned PROFILE that used to be a top-level
# preset file (`presets/large-print.nix`). It is not a room switch: the
# Appearance room is always present, and this is one named way to configure it.
{ lib, ... }:

{
  # It reaches the display through `haus.displays.main.uiScale` rather than
  # `.internal` on purpose: on a laptop they are the same panel, but on a Mac
  # mini or a clamshelled MacBook `internal` matches nothing — so keying on the
  # built-in panel would quietly do nothing on the desk setup most likely to
  # need this.
  options.haus.appearance.largePrint = lib.mkOption {
    type = lib.types.bool;
    default = false;
    example = true;
    description = ''
      Make everything haus controls bigger and sharper, in one line.
      Deliberately narrow: it is about seeing, not about who you are, so it says
      nothing about which rooms you run. Set it in any desktop, or in your host
      on top of one.

      It sets four options, each as a default, so pinning any of them by hand
      still wins. docs/model.md has the priority ladder and the one asymmetry:
      a desktop that names one of the four beats this profile even when your
      host is what switched the profile on.

        haus.ui.scale = 1.4
          the terminal font 19 → 27 pt, Dock icons 48 → 67, and the rest of
          the list on that option
        haus.theme.contrast = "high"
          body text 11.3:1 → 19.9:1 against the background, across every tool
          haus colours. Measured in nebelung's CI
        haus.accessibility.increaseContrast = true
          the same lift for native macOS apps, which the palette cannot reach.
          FDA-gated at the option, so it is skipped where the grant is missing
        haus.displays.main.uiScale = "larger-text"
          one step of the screen's scaled resolution toward larger text, and
          the only line here that reaches apps haus has never heard of, because
          it changes what a point means

      Turning it off is not the mirror image, and the arithmetic is worth
      having straight before you try it. `haus.ui.scale` and
      `haus.theme.contrast` go back to their own values and everything they
      render follows: the terminal drops 27 → 19 pt, the command palette returns
      to 1.0, the normal-contrast colours come back. The other two do not go
      back at all — they land on `null`, which haus reads as *leave whatever you
      have alone*. And `ui.scale` leaves one thing behind on the way down: the
      Dock's icon size, which it writes only while the scale is not 1.0. So two
      of the four return, and three settings stay on the Mac — Increase Contrast
      on, the Dock at 67, the display still a step down the ladder.

      That is what `false` means here rather than an oversight. The line the
      three fall on is whether haus writes that setting at BOTH values of this
      option: it writes the terminal's size, the palette and Finder's sidebar
      rows either way, so those follow, and it writes the other three only while
      the profile is on, so `false` writes nothing for them. Not writing a key
      is not the same as writing the old value back, and leaving a setting alone
      is the right answer for a personal one — nothing in the evaluation can
      tell your Mac apart from one that never asked for large print.

      So say it, in the same host, and one rebuild puts the three back:

        haus.accessibility.increaseContrast = false;
        haus.displays.main.uiScale          = "default";
        system.defaults.dock.tilesize       = 48;

      The third line is nix-darwin's own key rather than a haus one because haus
      has no leaf that says 48 — adding one would snap back every Dock anybody
      ever sized by hand.
      (`defaults delete com.apple.dock tilesize && killall Dock` is the same
      trip by hand, and leaves the key absent rather than pinned at 48.) The
      first line is FDA-gated exactly as its `true` was, so a Mac that has lost
      the grant since you turned this on gets the other two and a warning. All
      three land you on the stock Mac, not on whatever you had before — haus
      never recorded that, so if your display was on `more-space` it is yours to
      name again. Once the rebuild has run your Mac holds those values, so you
      can drop the three lines or keep them and nothing moves either way.

      Each of those four says where it stops, and haus.ui.scale is the one to
      read: the shelf and the menu bar's height follow neither lever. One stop
      belongs here, because it is the lever people expect and it does not
      exist: macOS's own text-size setting. `universalaccess`'s
      FontSizeCategory stores a value and notifies nobody, so apps never
      re-read it (docs/macos-settings.md has the measurement), and the fourth
      line above is how a large-print machine reaches apps outside haus at all.
      To key it on a specific monitor rather than `main`, name that monitor by
      UUID in your host; `hausdisp list` prints them.

      Two things it leaves to you. A more legible font family, because a
      typeface is taste and a legibility profile should not decide yours;
      Atkynson Mono is Atkinson Hyperlegible's monospaced sibling, drawn by the
      Braille Institute for exactly this problem:

        haus.fonts.mono.packageName = "nerd-fonts.atkynson-mono";
        haus.fonts.mono.name        = "AtkynsonMono Nerd Font";

      And light mode, if it reads better for you: `haus.theme.flavor = "latte"`.
    '';
  };

  # The layer's OWN motion, which is what makes this an option rather than a
  # pointer at Apple's. `haus.animations` curates five macOS timing keys and
  # `haus.accessibility.reduceMotion` flips Apple's switch; neither reaches a
  # sweep the bar draws or a workspace the tiler pulls you to. Those are ours,
  # they run with every Apple switch flipped, and this is the one address that
  # turns them off. It COMPOSES with Apple's rather than duplicating it — see
  # modules/appearance/default.nix for the fan-out.
  #
  # Two decisions behind that composition. Asking for Apple's flag as a DEFAULT
  # is deliberate rather than convenient: that flag is FDA-gated at its own
  # option, so haus's own half — which depends on no permission at all — still
  # applies on a machine whose rebuilding app lacks Full Disk Access. A
  # legibility switch that only worked with a grant would be the wrong shape.
  #
  # And it deliberately does NOT set `haus.animations = "fast"`. That group
  # speeds macOS's Dock timings UP rather than removing motion, and coming back
  # from it only stops writing rather than restores, so a motion-sensitivity
  # switch has no business leaving a Dock permanently retuned.
  options.haus.appearance.reduceMotion = lib.mkOption {
    type = lib.types.bool;
    default = false;
    example = true;
    description = ''
      Stop the things haus itself animates from animating. One switch, for a
      machine whose user is vestibular-sensitive, motion-sick, or simply done
      with movement in the corner of their eye.

      It exists because macOS's own switches do not reach the motion haus draws.
      `haus.animations` retunes the Dock's timings and
      `haus.accessibility.reduceMotion` flips Apple's flag; the bar's sweeps and
      the tiler's automatic moves are the layer's own and run happily with both
      of those set.

      What it stops, each as a default, so any single one goes back by name:
      this option `true` with `haus.bar.logo.sweep = true` keeps the sweep and
      drops the rest.

        haus.bar.logo.sweep        six family accents turning through the mark
                                   whenever the pointer crosses it
        haus.bar.media.marquee     a long track title sweeping past on hover
        haus.bar.calendar.marquee  the same, for a long meeting title
        haus.windows.mouseFollowsFocus
                                   a pointer teleporting across the desk is
                                   movement you did not make
        haus.windows.gravity       the automatic pull back to a populated
                                   workspace when a ⌘Q empties this one, a
                                   whole screen changing under you unasked

      Nothing loses information: a title too long for its pill is clipped rather
      than swept, and both dropdowns carry it in full.

      It also asks for macOS's own "Reduce motion"
      (`haus.accessibility.reduceMotion`), again as a default, because a machine
      that quietened its own five surfaces and left Spaces sliding would have
      answered the question halfway. Read that option before you take it: it is
      the single flag every browser reads as `prefers-reduced-motion: reduce`,
      so it rewrites the web as well, and
      `haus.accessibility.reduceMotion = false` in your host keeps haus's half
      without the web one. haus's half needs no permission, so it still applies
      on a machine where Apple's FDA-gated flag is skipped.

      That last line is also the way back. Turning this option off re-renders
      haus's own five and they stop, but Apple's flag is a preference macOS now
      holds rather than a file haus redraws, so it stays on until you say
      `haus.accessibility.reduceMotion = false` yourself — the same asymmetry
      `largePrint` has, one leaf instead of three.
    '';
  };
}

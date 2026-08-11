# The desktop behind everything — `haus.wallpaper.*`.
#
# It used to be one enum on the theme (`haus.theme.wallpaper`), which was the
# right size while every look was a finished PNG somebody had drawn. `minimal` is
# not: it is GENERATED, from this machine's own palette, accent, tiling gaps and
# lock edges, so it needs a room rather than a value — hence the move, and the
# alias in ../renamed.nix that keeps the old name working.
#
# `style` is the one axis every other option here reads as context. Today it has
# exactly one generated look and the four inherited Nebelung ones; the shape is
# what matters — a future desktop kind (a photograph, a plot, something animated)
# arrives as another value here rather than as a second wallpaper namespace.
{ lib, ... }:

let
  # Hex colours are typed rather than left as `str` because every one of them
  # ends up interpolated into an ImageMagick argument or an SVG attribute, where
  # a typo is a build failure a long way from the host file that caused it.
  hex = lib.types.strMatching "#[0-9a-fA-F]{6}";
in
{
  # `haus.theme.wallpaper` was this option until `minimal` landed. The alias
  # lives here rather than in ../renamed.nix, which is GENERATED and covers one
  # rename only (`nebelhaus.*` -> `haus.*`) with a deletion condition of its own
  # — an entry hand-added there would outlive the file. Chaining works: a rice
  # still saying `nebelhaus.theme.wallpaper` lands on `haus.theme.wallpaper`
  # there and arrives here.
  imports = [
    (lib.mkRenamedOptionModule [ "haus" "theme" "wallpaper" ] [ "haus" "wallpaper" "style" ])
  ];

  options.haus = {
    wallpaper.style = lib.mkOption {
      type = lib.types.enum [
        "none"
        "minimal"
        "orbits"
        "constellation"
        "flow"
        "bold"
      ];
      default = "minimal";
      example = "none";
      description = ''
        Which desktop this machine wears, set at each home-manager activation
        (osascript, every desktop on the current Space).

          minimal        GENERATED here — a flat field in your palette, the
                         haus mark ⌂ at its centre, and nothing else. The one
                         haus-themed look, and the one every option below tunes.
          orbits         hand-made Nebelung PNGs, the palette baked into their
          constellation  pixels — they do not follow haus.theme.flavor.
          flow
          bold           generated from haus.theme.accent alone (a diagonal
                         accent→crust sweep), which predates `minimal`.

        The default is `minimal`, so a machine that says nothing about its
        desktop wears the haus one. That is a change of mind: this defaulted to
        "none" while the generated look was new, on the grounds that the desktop
        is visible and personal. It is — but a rice whose own desktop is opt-in
        ships looking like nothing in particular, and `minimal` is drawn from
        the palette, accent and gaps this machine already chose, so it is the
        one look that can't clash with the rest of the install.

        "none" is the way back, and it is a real value rather than an absence:
        set it and nothing here runs, leaving whatever wallpaper you already
        have exactly where it was (the bootstrap interview still offers the
        choice, and writes this line when you take it).
      '';
    };

    wallpaper.size = lib.mkOption {
      type = lib.types.strMatching "[0-9]+x[0-9]+";
      default = "3456x2234";
      example = "3024x1964";
      description = ''
        The pixel size `minimal` is rendered at, `WIDTHxHEIGHT`.

        Set it to your display's NATIVE pixel count and macOS has nothing left
        to do: the picture lands one image pixel per screen pixel, which is the
        only arrangement where the grain that keeps the glow smooth survives at
        the size it was dithered for. Anything else is resampled, and resampling
        is where a gradient that was clean in the file starts to look stepped.

        The default is the 16" MacBook Pro panel — the largest built-in Retina
        display, so a smaller one scales DOWN (soft, harmless) rather than up.
        `system_profiler SPDisplaysDataType` prints yours.

        Aspect matters as much as size: macOS fills the screen and crops the
        overflow, so a picture narrower than the display loses its top and
        bottom — which is where `debug` draws. On a display of a different
        shape, set this to that display's own numbers.
      '';
    };

    # ---- the field --------------------------------------------------------
    wallpaper.depth = lib.mkOption {
      type = lib.types.ints.between 0 5;
      default = 1;
      example = 0;
      description = ''
        How far in from the palette's outermost tone the field sits — the
        answer to "I want it blacker" without anyone having to name a colour.

        Nebelung's background tones are a ladder of six, ordered here from the
        end nearest the polarity's extreme inwards, so the SAME number means the
        same distance from black in a dark rice and from white in a light one:

          depth  dark (mocha)          light (latte)
          0      crust    #121212      base     #f1f1f1
          1      mantle   #191919      mantle   #e9e9e9     ← default
          2      base     #202020      crust    #e0e0e0
          3      surface0 #343434      surface0 #d0d0d0
          4      surface1 #494949      surface1 #c0c0c0
          5      surface2 #5c5c5c      surface2 #b0b0b0

        0 is as far out as the palette goes — our blackest black, our whitest
        white. The default of 1 lands exactly one rung inside that extreme in
        EITHER polarity, which is what keeps the desktop reading as material
        rather than as a hole cut in the screen while still being properly dark
        in a dark rice — a full screen of `base` reads as a big terminal window,
        not as a wall behind one.

        The two columns are NOT symmetric, and the asymmetry is the palette's
        rather than a choice: mocha's canvas (`base`) sits at depth 2 because
        two tones are darker than it, while latte's canvas is the LIGHTEST tone
        it has, so it sits at depth 0. So the ONE number moves the two flavours
        in opposite directions relative to their canvas — the default puts a
        dark rice one step BELOW the colour its terminal draws on (#191919) and
        a light one one step below the canvas too (#e9e9e9), which is the
        agreement worth having, since a full screen of near-white is the one
        field size where latte's canvas stops being comfortable. `depth = 0` is
        the way to match the terminal exactly in a light rice; `depth = 2` is
        the way to match it in a dark one.

        Which flavour's column applies follows haus.theme.flavor, like every
        other themed surface. haus.wallpaper.background overrides the whole
        thing with a literal hex.
      '';
    };

    wallpaper.background = lib.mkOption {
      type = lib.types.nullOr hex;
      default = null;
      example = "#0b0b0e";
      description = ''
        The field colour, as a literal hex — an escape hatch out of the palette
        for a desktop that wants a colour the rice doesn't have.

        Null (the default) resolves it from haus.wallpaper.depth against the
        flavour's ladder, which is the arrangement that keeps following the
        theme. Setting this pins the field and `depth` stops meaning anything.
      '';
    };

    wallpaper.grain = lib.mkOption {
      type = lib.types.numbers.between 0.0 0.1;
      default = 0.01;
      example = 0.0;
      description = ''
        Film grain over the whole field, as a fraction of full scale — and the
        reason the glow doesn't band.

        This is dither, dressed as texture. A soft glow across two thousand
        pixels spends perhaps ten of the 256 levels an 8-bit PNG has, so it
        quantises into visible contour rings — the "steppy gradient" every
        hand-made wallpaper picks up on the way out of an image editor. Noise of
        a couple of levels, added BEFORE the render is reduced to 8 bits, breaks
        those contours into something the eye integrates back to smooth. 0.004
        is enough to hide them; the default is comfortably past that.

        0 turns it off. Do that only with `glow.enable = false` too — a glow on
        an ungrained field is exactly the picture this exists to prevent.

        Measured at the shipped defaults (3456x2234), since the effect is easier
        to state in numbers than to argue about — distinct colours, and what the
        PNG costs, noise being the one thing that doesn't compress:

          grain    colours    size
          0          137      0.1 MB   ← rings, visibly
          0.004      193      1.1 MB   ← the floor worth using
          0.010      329      2.5 MB   ← the default
          0.020      625      4.2 MB
      '';
    };

    wallpaper.glow.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        A single broad bloom behind the mark, so the field reads as lit rather
        than as a fill. Subtle by construction — see `glow.strength`.
      '';
    };

    wallpaper.glow.color = lib.mkOption {
      type = lib.types.nullOr hex;
      default = null;
      example = "#8db4f3";
      description = ''
        The colour the bloom tends towards at its centre. Null takes
        haus.theme.accent's hex, which is what makes the desktop change
        temperature with the accent without anyone wiring a second colour.
      '';
    };

    wallpaper.glow.strength = lib.mkOption {
      type = lib.types.ints.between 0 100;
      default = 3;
      example = 14;
      description = ''
        How much of the bloom is mixed into the field, as a percentage.

        Small numbers on purpose: at 3 the accent is a few levels of lift you'd
        struggle to name and would miss if it went. Past ~25 it stops being
        light on a wall and starts being a coloured wallpaper, which is a
        different desktop than this one. (Was 7 until it turned out to read as
        the field simply not being dark enough, rather than as a glow.)
      '';
    };

    wallpaper.glow.spread = lib.mkOption {
      type = lib.types.numbers.between 0.2 4.0;
      default = 1.15;
      example = 0.6;
      description = ''
        The bloom's diameter, as a multiple of the picture's long edge. Above 1
        its falloff runs off the edges and the field reads as evenly lit from
        the middle; below 1 it closes into a halo around the mark.
      '';
    };

    # ---- the mark ---------------------------------------------------------
    wallpaper.mark.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Draw the haus mark ⌂ at the centre. Off leaves the field, the glow and
        the grain — which is a perfectly good desktop, and the fastest way to
        get one flat colour that still isn't flat.
      '';
    };

    wallpaper.mark.size = lib.mkOption {
      type = lib.types.numbers.between 0.01 0.9;
      default = 0.1;
      example = 0.3;
      description = ''
        The mark's height, as a fraction of the picture's SHORT edge — so it
        keeps its proportion whatever `size` and whatever display.
      '';
    };

    wallpaper.mark.weight = lib.mkOption {
      type = lib.types.numbers.between 0.005 0.25;
      default = 0.09;
      example = 0.055;
      description = ''
        Stroke width, as a fraction of the mark's own height.

        The mark's SHAPE is the real U+2302, traced off the outline hausfold.co
        renders, and the default weight is now the site's too: that glyph's
        stems are a tenth of its height, which is 0.094 here once the miter at
        the apex is counted, and 0.09 is that within a hair. So the desktop and
        the site draw the same mark, which is the agreement worth having when
        the two sit side by side.

        It used to default to 0.055 — a little under 60% of the glyph's own
        weight — on the grounds that a stem which reads right in a line of type
        is heavy drawn a foot wide on a wall. That is true of a mark filling the
        screen; it is not true of one at `mark.size`, where the lighter stroke
        reads as a hairline rather than as the ⌂. Go back to it if you want the
        outline to recede.
      '';
    };

    wallpaper.mark.color = lib.mkOption {
      type = lib.types.enum [
        "muted"
        "ink"
        "accent"
        "spectrum"
      ];
      default = "spectrum";
      example = "muted";
      description = ''
        What the mark is drawn in.

          muted      the palette's overlay1 — present, not loud. The mark as it
                     sits on hausfold.co untouched.
          ink        the palette's text colour, for a mark meant to be read
                     rather than noticed.
          accent     haus.theme.accent's hex, flat.
          spectrum   the whole family at once: a conic sweep through the six
                     product accents — nebelung, holt, perch, trill, pounce,
                     nebelhaus — clipped to the stroke. This is the ⌂ as it
                     looks with a pointer on it on hausfold.co, held still.

        `spectrum` is the default, and follows the flavour like everything
        else: the six are the Nebelung pastels in a dark rice and their darker
        counterparts in a light one, because a pastel sheen on a white wall is
        invisible. It is the loudest of the four on purpose — one small piece of
        colour is the whole of what this desktop says out loud, and it says the
        family rather than any one product. `muted` is the quiet way back, and
        `mark.opacity` turns the sweep down without leaving it.
      '';
    };

    wallpaper.mark.opacity = lib.mkOption {
      type = lib.types.numbers.between 0.0 1.0;
      default = 1.0;
      example = 0.55;
      description = ''
        The mark's opacity over the field. Worth reaching for with `spectrum`
        — the default, and the one colour here loud enough to want turning down.
      '';
    };

    wallpaper.mark.rise = lib.mkOption {
      type = lib.types.numbers.between (-0.5) 0.5;
      default = 0.0;
      example = 0.06;
      description = ''
        How far above centre the mark sits, as a fraction of the picture's
        height. Optical centre is a little above geometric centre, and a bar
        along the top edge moves it further — a small positive number is the
        usual correction.
      '';
    };

    # ---- the debug band ---------------------------------------------------
    wallpaper.debug.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Print this machine's lock edges in the bottom-left corner — which
        revision of each family repo the running system was built from.

        It is a detail rather than a readout. It sits at exactly the inset a
        tiled window covers (see `debug.inset`), so it is invisible the moment
        anything is on screen and only ever surfaces on a bare desktop; it is
        set small, dim and wide-tracked; and it names four repos rather than
        everything the flake pins. Off by default.
      '';
    };

    wallpaper.debug.inputs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "self"
        "nebelung"
        "pounce"
        "perch"
        "holt"
      ];
      # Spelled on ONE line for ../host-template.jq: the annotated host file
      # comments each default with `  # ` and the "is it still legal once
      # uncommented" check un-comments only the line the option name is on, so a
      # default that renders across several lines leaves the rest commented and
      # the file stops parsing. The template's own build catches that loudly —
      # this is the escape hatch it's telling you to use.
      defaultText = lib.literalExpression ''[ "self" "nebelung" "pounce" "perch" "holt" ]'';
      example = [
        "self"
        "nixpkgs"
      ];
      description = ''
        Which flake inputs the band names, in the order it prints them. `self`
        is the rice itself and prints as `haus`; every other entry is an input
        name out of the rice's own flake, and one that isn't there is skipped
        rather than failing the build.

        The default is the family chain, which is the one thing a rev is worth
        knowing on a desktop: it's what `bench status` calls the lock edges, and
        the answer to "is this machine running the branch I just merged".
      '';
    };

    wallpaper.debug.size = lib.mkOption {
      type = lib.types.numbers.between 0.002 0.1;
      default = 0.011;
      example = 0.02;
      description = ''
        The band's type size, as a fraction of the picture's short edge. It is
        set in haus.fonts.mono, so the desktop and the terminal in front of it
        are the same typeface.
      '';
    };

    wallpaper.debug.inset = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.unsigned;
      default = null;
      example = 96;
      description = ''
        How far in from the bottom-left corner the band sits, in PICTURE
        PIXELS.

        Null derives it from the tiling gaps — the widest outer reservation any
        attached display could be using (../lib/gaps.nix, the same numbers prowl
        writes into aerospace.toml), doubled for a Retina display's two pixels
        per point. That lands the band exactly at a tiled window's bottom-left
        corner, which is the whole trick: the text is under the windows, not
        beside them, so a tiled desktop hides it completely and a bare one
        doesn't.

        Set a number if your display isn't 2× — or if you'd rather see it.
      '';
    };
  };
}

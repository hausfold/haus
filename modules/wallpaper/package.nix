# Render the `minimal` desktop: a flat field, a bloom, film grain, the haus mark
# ⌂, and an optional band of lock edges in the corner. A pure derivation — every
# input is a number or a hex out of the module, so the picture rebuilds when the
# palette, the accent or a lock edge moves, and is byte-identical when they don't.
#
# TWO renderers, on purpose, and the split is the whole reason this doesn't band:
#
#   resvg  draws the VECTOR layer (the mark, the text) onto transparency. It is
#          a real SVG renderer with analytic anti-aliasing, so a mitred roof
#          apex comes out clean; it also has no idea what 16-bit means, which is
#          fine for shapes and fatal for gradients.
#   magick composes the FIELD — flat colour, bloom, grain — at 16 bits per
#          channel, composites the vector layer over it, and quantises to 8 bits
#          ONCE, with the grain already in place to dither the reduction.
#
# Doing the bloom in the SVG instead would quantise it to 8 bits inside resvg,
# before any grain exists to break the contours up — which is exactly the
# stepped-gradient wallpaper this look was written to replace. Measured at the
# shipped defaults: 127 distinct colours with `grain = 0` and 291 with the
# default grain, and under a 25x contrast stretch the first is visibly ringed
# and the second is flat.
{
  lib,
  runCommand,
  writeText,
  resvg,
  imagemagick,
  oxipng,
  fontconfig,
}:

{
  # Output name; the accent/palette ride in it so two rices don't share a path.
  name ? "haus-wallpaper",
  width,
  height,
  background, # "#rrggbb"
  # { color = "#rrggbb"; strength = 0..100; spread = float; } | null
  glow ? null,
  grain ? 0.0,
  # { size, weight, rise, opacity, paint } | null
  #   paint = { kind = "solid"; color = "#rrggbb"; }
  #         | { kind = "spectrum"; colors = [ six hexes ]; }
  mark ? null,
  # { rows = [ { key; value; } ]; size; insetX; insetY; keyColor; valueColor;
  #   fontPackage; } | null
  debug ? null,
}:

let
  round = n: builtins.floor (n + 0.5);
  n2s = v: toString v;

  W = width;
  H = height;
  short = lib.min W H;
  long = lib.max W H;

  # ---- the mark ---------------------------------------------------------
  # ⌂ U+2302 HOUSE, drawn rather than set. A font glyph would follow whatever
  # haus.fonts.mono happens to be — a different house on every rice, and tofu on
  # a font without the codepoint — where the mark is meant to be the one thing
  # that looks the same everywhere. Unit box is 100x100.
  #
  # The body's verticals start at y=40 rather than at their own corner: the roof
  # line passes through y≈39.9 at x=17 and x=83, so ending them there tucks the
  # butt caps inside the roof's stroke at ANY weight. Ending them lower leaves a
  # hairline gap that only opens up as the stroke gets thinner.
  roofPath = "M 4 52 L 50 9 L 96 52";
  bodyPath = "M 17 40 L 17 91 L 83 91 L 83 40";

  markSide = mark.size * short;
  markX = (W - markSide) / 2.0;
  markY = (H - markSide) / 2.0 - mark.rise * H;

  markGroup =
    attrs:
    ''
      <g ${attrs} transform="translate(${n2s markX} ${n2s markY}) scale(${n2s (markSide / 100.0)})"
         fill="none" stroke-width="${n2s (100.0 * mark.weight)}"
         stroke-linecap="butt" stroke-linejoin="miter" stroke-miterlimit="6">''
    + ''<path d="${roofPath}"/><path d="${bodyPath}"/></g>'';

  # ---- the spectrum sweep -----------------------------------------------
  # CSS has conic-gradient; SVG does not, and resvg is honest about it. So the
  # ring is fanned: WEDGES flat-coloured triangles, each a rotated copy of one
  # shape, sampled off the six-accent ring at its own bisector. The colour step
  # between neighbours is under two levels, which is below what a 1px-wide stroke
  # can show — and unlike a linear gradient faked across the glyph it stays a
  # genuine ANGULAR sweep right down to the centre, where the mark actually is.
  WEDGES = 240;
  # Half a wedge plus a whiff of overlap, so neighbouring triangles can't leave
  # an anti-aliased hairline between them: cos/sin of 0.95°.
  wedgeCos = 0.9998626;
  wedgeSin = 0.0165806;
  # Any radius past the corner does; W + H is always over the diagonal and needs
  # no square root, which Nix hasn't got.
  wedgeR = (W + H) * 1.0;

  hexDigits = "0123456789abcdef";
  digitVal =
    c:
    (builtins.listToAttrs (lib.imap0 (i: d: lib.nameValuePair d i) (lib.stringToCharacters hexDigits)))
    .${lib.toLower c};
  parseByte = s: 16 * digitVal (builtins.substring 0 1 s) + digitVal (builtins.substring 1 1 s);
  toRgb =
    h:
    let
      s = lib.removePrefix "#" h;
    in
    map (i: parseByte (builtins.substring i 2 s)) [
      0
      2
      4
    ];
  toByte =
    n:
    let
      m = lib.max 0 (lib.min 255 n);
    in
    builtins.substring (m / 16) 1 hexDigits + builtins.substring (m - 16 * (m / 16)) 1 hexDigits;
  toHex = rgb: "#" + lib.concatMapStrings toByte rgb;

  # The ring, sampled at t in [0,1) — six stops, wrapping back to the first.
  ringAt =
    ring: t:
    let
      k = builtins.length ring;
      f = t * k;
      i = builtins.floor f;
      m = f - i;
      a = builtins.elemAt ring (lib.mod i k);
      b = builtins.elemAt ring (lib.mod (i + 1) k);
    in
    toHex (
      map (j: round ((builtins.elemAt a j) * (1.0 - m) + (builtins.elemAt b j) * m)) [
        0
        1
        2
      ]
    );

  spectrumFan =
    hexes:
    let
      ring = map toRgb hexes;
      wedge =
        i:
        let
          # -90° so the ring starts at twelve o'clock and turns clockwise, the
          # way `conic-gradient(from 0deg …)` does on hausfold.co.
          a = 360.0 * i / WEDGES - 90.0;
          c = ringAt ring ((i + 0.5) / WEDGES);
        in
        ''<path transform="rotate(${n2s a})" fill="${c}" d="M 0 0 L ${n2s (wedgeR * wedgeCos)} ${n2s (-wedgeR * wedgeSin)} L ${n2s (wedgeR * wedgeCos)} ${n2s (wedgeR * wedgeSin)} Z"/>'';
    in
    ''<g transform="translate(${n2s (markX + markSide / 2.0)} ${n2s (markY + markSide / 2.0)})">''
    + lib.concatMapStrings wedge (lib.range 0 (WEDGES - 1))
    + "</g>";

  markLayer =
    if mark == null then
      ""
    else if mark.paint.kind == "spectrum" then
      ''<defs><mask id="haus-mark" maskUnits="userSpaceOnUse" x="0" y="0" width="${n2s W}" height="${n2s H}">''
      + markGroup ''stroke="#ffffff"''
      + ''</mask></defs><g mask="url(#haus-mark)" opacity="${n2s mark.opacity}">''
      + spectrumFan mark.paint.colors
      + "</g>"
    else
      markGroup ''stroke="${mark.paint.color}" opacity="${n2s mark.opacity}"'';

  # ---- the debug band ---------------------------------------------------
  # Bottom-left, growing upward, so the LAST row sits on the inset and adding a
  # repo to haus.wallpaper.debug.inputs pushes the column up rather than
  # sliding it off the bottom of the picture.
  debugLayer =
    if debug == null || debug.rows == [ ] then
      ""
    else
      let
        fs = debug.size * short;
        keyw = lib.foldl' (a: r: lib.max a (lib.stringLength r.key)) 0 debug.rows + 2;
        pad = s: s + lib.concatStrings (lib.genList (_: " ") (keyw - lib.stringLength s));
        base = H - debug.insetY - fs * 0.22;
        rows = lib.reverseList debug.rows;
        row = i: r: ''
          <text x="${n2s debug.insetX}" y="${n2s (base - i * fs * 1.75)}" font-family="@MONOFAMILY@"
                font-size="${n2s fs}" letter-spacing="${n2s (fs * 0.09)}" xml:space="preserve"
                fill="${debug.keyColor}">${pad r.key}<tspan fill="${debug.valueColor}">${r.value}</tspan></text>
        '';
      in
      lib.concatStrings (lib.imap0 row rows);

  svg = writeText "${name}.svg" ''
    <svg xmlns="http://www.w3.org/2000/svg" width="${n2s W}" height="${n2s H}" viewBox="0 0 ${n2s W} ${n2s H}">
    ${markLayer}
    ${debugLayer}
    </svg>
  '';

  # ---- the field --------------------------------------------------------
  glowArgs =
    if glow == null || glow.strength == 0 then
      ""
    else
      let
        d = round (glow.spread * long);
      in
      # The bloom is a radial that ALREADY ends on the field colour, extended to
      # the frame on that same colour — so blending it in at N% lifts the middle
      # by N% of the accent and leaves the edges exactly where they were.
      ''\( -size ${n2s d}x${n2s d} radial-gradient:'${glow.color}'-'${background}' ''
      + ''-background '${background}' -gravity center -extent ${n2s W}x${n2s H} \) ''
      + "-define compose:args=${n2s glow.strength} -compose blend -composite ";

  # `-seed` is not optional here, however cosmetic noise sounds. ImageMagick's
  # `+noise` draws from an UNSEEDED RNG by default, so the same command run
  # twice produces different bytes — measured, not assumed. Nix would not notice
  # (a store path is fixed by its inputs, not its output), which is exactly what
  # makes it worth pinning: two machines on the same rice would quietly hold two
  # different pictures, `nix build --check` would report the derivation as
  # non-deterministic, and a content-addressed store would treat every rebuild as
  # a new object. The value is arbitrary — it is U+2302, the mark's codepoint —
  # and only has to be constant.
  grainArgs = lib.optionalString (grain > 0.0) "-seed 2302 -attenuate ${n2s grain} +noise Gaussian ";

  # The vector layer is drawn at 2x and box-averaged down rather than rendered
  # at 1x: it costs one resize and buys a supersampled roof apex, which is the
  # one place a mitre shows its stair steps. Box rather than Lanczos on purpose
  # — a 2:1 box average IS the supersample, where a sharpening filter would ring
  # against the flat field on both sides of a one-pixel stroke.
  SS = 2;

  needFont = debug != null && debug.rows != [ ];
in
runCommand name
  {
    nativeBuildInputs = [
      resvg
      imagemagick
      oxipng
    ]
    ++ lib.optional needFont fontconfig;
    passthru = { inherit width height background; };
  }
  ''
    cp ${svg} vec.svg

    ${lib.optionalString needFont ''
      # resvg matches text by FAMILY name, and a font package's family is not
      # derivable from its attribute path (nerd-fonts.jetbrains-mono ships
      # "JetBrainsMono Nerd Font"), so read it out of the file itself. Prefer an
      # upright Regular face; fall back to whatever the package has.
      fontFile="$(find -L ${debug.fontPackage}/share/fonts \( -name '*.ttf' -o -name '*.otf' \) \
        ! -iname '*italic*' | sort | grep -i -m1 -- '-regular' || true)"
      if [ -z "$fontFile" ]; then
        fontFile="$(find -L ${debug.fontPackage}/share/fonts \( -name '*.ttf' -o -name '*.otf' \) | sort | head -1)"
      fi
      if [ -z "$fontFile" ]; then
        echo "haus.wallpaper: haus.fonts.mono.package ships no .ttf/.otf — the debug band has nothing to set itself in." >&2
        exit 1
      fi
      # fc-scan has no config file here and says so on stderr; the format query
      # doesn't need one.
      family="$(fc-scan --format '%{family[0]}' "$fontFile" 2>/dev/null)"
      [ -n "$family" ] || { echo "haus.wallpaper: could not read a family name out of $fontFile" >&2; exit 1; }
      substituteInPlace vec.svg --replace-fail '@MONOFAMILY@' "$family"
      fontArgs=(--use-font-file "$fontFile" --skip-system-fonts)
    ''}

    resvg --width ${n2s (W * SS)} --height ${n2s (H * SS)} \
      ''${fontArgs[@]+"''${fontArgs[@]}"} vec.svg vec-ss.png
    magick vec-ss.png -filter Box -resize ${n2s W}x${n2s H}! -depth 16 vec.png

    magick -depth 16 -size ${n2s W}x${n2s H} xc:'${background}' \
      ${glowArgs}${grainArgs}vec.png -compose over -composite \
      -depth 8 -strip PNG24:out.png

    # Lossless, and worth it: the flat field compresses to almost nothing once
    # the filter row is chosen well, while the grained region doesn't move.
    oxipng -o 2 -q --strip safe out.png
    mv out.png $out
  ''

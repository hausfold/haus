# Resolve haus.keys.* into the concrete AeroSpace chords, the pounce hotkey
# definition, and the glyphs that describe them. Imported the same way as
# gui-wait.nix / nebelung.nix — a plain function, no module system involved.
#
#   k = import ../lib/keys.nix { inherit lib; keys = config.haus.keys; };
#
# The point of putting the vocabulary in ONE table is that a chord and the caption
# that documents it come from the same row. Before this, "⌥ ⇧ ←↓↑→" was typed as a
# display string next to `alt-shift-left` as a chord, in a table whose whole reason for
# existing was that a binding and its cheatsheet caption must not drift — the
# modifier was the one part of the row still duplicated by hand. Four consumers
# read this: prowl (aerospace.toml), pounce (the cheatsheet + its hotkey), sill
# (the tour's prompts), and the assertions that catch a chord claimed twice.
#
# `null` means "this rice doesn't have that key at all" — a mouse-first or
# one-handed rice, or one that refuses to give up Caps Lock. Callers must handle
# null rather than assume a default; that's the whole point of the option.
{
  lib,
  keys,
}:

let
  # AeroSpace modifier prefix + the glyph that names it. The alternatives exist
  # for a real reason rather than for choice's sake: on many non-US layouts ⌥ is
  # how you type accented characters, so a rice that owns ⌥+letter is unusable
  # there. ⌃⌥ and ⌘⌥ are the escapes.
  navVocab = {
    alt = {
      chord = "alt";
      glyph = "⌥";
    };
    ctrl-alt = {
      chord = "ctrl-alt";
      glyph = "⌃⌥";
    };
    cmd-alt = {
      chord = "cmd-alt";
      glyph = "⌘⌥";
    };
  };

  # The chord that ENTERS launch mode. "caps" is the house default and the only
  # one needing a hidutil remap — AeroSpace can't bind Caps Lock itself, so the
  # rice maps it to F18 and binds that. "alt-space" is for people who want the
  # leader without losing Caps Lock.
  leaderVocab = {
    caps = {
      chord = "f18";
      capsRemap = true;
      glyph = "⇪";
      name = "Caps Lock";
    };
    alt-space = {
      chord = "alt-space";
      capsRemap = false;
      glyph = "⌥␣";
      name = "⌥ Space";
    };
  };

  # The palette hotkey. Registered IN-PROCESS by the pounce daemon (see
  # modules/pounce), so this becomes its config.json `hotkey` block rather than an
  # AeroSpace binding — binding it in AeroSpace too made AeroSpace win the race and
  # spawn the palette under its own TCC identity.
  paletteVocab = {
    cmd-space = {
      key = "space";
      modifiers = [ "cmd" ];
      glyph = "⌘ Space";
      # The only value that needs Spotlight's ⌘Space taken away from it.
      stealsSpotlight = true;
    };
    alt-space = {
      key = "space";
      modifiers = [ "alt" ];
      glyph = "⌥ Space";
      stealsSpotlight = false;
    };
    ctrl-space = {
      key = "space";
      modifiers = [ "ctrl" ];
      glyph = "⌃ Space";
      stealsSpotlight = false;
    };
  };
in
{
  # null when keys.windowNav = "none": no modifier-based window chords at all.
  nav = navVocab.${keys.windowNav} or null;
  # null when keys.leader = "none": Caps Lock stays Caps Lock and launch mode is
  # unreachable. Everything it fronted is still reachable through the palette.
  leader = leaderVocab.${keys.leader} or null;
  # null when keys.palette = "none": the daemon registers nothing and Spotlight
  # keeps ⌘Space.
  palette = paletteVocab.${keys.palette} or null;

  # Two different keys resolving to the same chord is the class of bug this
  # option surface introduces, and it fails silently — whoever registers first
  # wins. Callers assert on this.
  conflicts =
    let
      claimed =
        lib.optional (keys.leader != "none") {
          what = "keys.leader";
          chord = leaderVocab.${keys.leader}.chord;
        }
        ++ lib.optional (keys.palette != "none") {
          what = "keys.palette";
          # Same shape as an AeroSpace chord so the two are comparable at all.
          chord = lib.concatStringsSep "-" (
            paletteVocab.${keys.palette}.modifiers ++ [ paletteVocab.${keys.palette}.key ]
          );
        };
      chords = map (c: c.chord) claimed;
      duplicated = lib.unique (lib.filter (c: lib.count (x: x == c) chords > 1) chords);
    in
    map (
      chord:
      "${chord} is claimed by "
      + lib.concatStringsSep " and " (map (c: c.what) (lib.filter (c: c.chord == chord) claimed))
    ) duplicated;
}

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
# read this: windows (aerospace.toml), pounce (the cheatsheet + its hotkey), bar
# (the tour's prompts), and the assertions that catch a chord claimed twice.
#
# `null` means "this desktop doesn't have that key at all" — a mouse-first or
# one-handed desktop, or one that refuses to give up Caps Lock. Callers must handle
# null rather than assume a default; that's the whole point of the option.
{
  lib,
  keys,
}:

let
  # What a KEY NAME in this config means physically.
  #
  # AeroSpace, pounce and macOS all name a key by where it sits on a US
  # keyboard: `a` is kVK_ANSI_A, the key second from the left on the home row,
  # whatever is printed on it. On AZERTY that key prints Q — so `haus.roster.<a>.key
  # = "a"` binds the key a French keyboard calls Q, and the letter that gave the
  # binding its mnemonic is on a different key entirely. Measured on
  # com.apple.keylayout.French: five of the twenty-six leader letters land on the
  # wrong app that way (a↔q, z↔w, and m on nothing at all), and launch mode's
  # `,` action lands on whatever the roster put on `m`.
  #
  # AeroSpace can be told otherwise. `[key-mapping.key-notation-to-key-code]`
  # maps a NOTATION — the character printed on the key you want to press — to the
  # US-NAMED PHYSICAL KEY that carries it, and `preset` selects one of its two
  # built-in tables (three of them: qwerty, dvorak, colemak). So each entry below
  # reads "when this config says <name>,
  # mean the key US keyboards call <value>".
  #
  # What this cannot do, and why AZERTY still needs its own paragraph in the
  # docs: the mapping is notation → key code, with no room for a MODIFIER. AZERTY
  # puts `.` on ⇧+the `;` key, `/` on ⇧+the `:` key, and every digit behind ⇧,
  # so those bindings have no unshifted key to move to and stay where US
  # keyboards put them. Mapping only what can be mapped is deliberate: a partial
  # table that never collides beats a complete-looking one where two bindings
  # silently claim one key.
  layoutVocab = {
    qwerty = {
      preset = null; # what AeroSpace already does — emit nothing at all
      notationToKeyCode = { };
    };
    # AeroSpace ships no azerty preset, so this is the whole table. Letters
    # first, then the two punctuation keys the letter block displaces: AZERTY's
    # `m` sits where US keyboards put `;`, which pushes `;` onto the US `,` key
    # and `,` onto the US `m` key.
    azerty = {
      preset = "qwerty";
      notationToKeyCode = {
        a = "q";
        q = "a";
        z = "w";
        w = "z";
        m = "semicolon";
        semicolon = "comma";
        comma = "m";
      };
    };
    # These two are AeroSpace's own, and are the reason this option is named for
    # the layout rather than for AZERTY.
    dvorak = {
      preset = "dvorak";
      notationToKeyCode = { };
    };
    colemak = {
      preset = "colemak";
      notationToKeyCode = { };
    };
  };

  # AeroSpace modifier prefix + the glyph that names it. The alternatives exist
  # for a real reason rather than for choice's sake: on a non-US layout ⌥ is a
  # character layer in its own right — on AZERTY it is where `{ } [ ] | \ @ #`
  # live — so a desktop that owns too much of ⌥ makes the keyboard unusable for
  # writing code. ⌃⌥ and ⌘⌥ are the escapes.
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
  # one needing a hidutil remap — AeroSpace can't bind Caps Lock itself, so
  # haus maps it to F18 and binds that. "alt-space" is for people who want the
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
  # modules/launcher), so this becomes its config.json `hotkey` block rather than an
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
  # Never null: every machine has SOME layout, and "qwerty" is the one that
  # emits nothing, so a config that never heard of this option keeps every
  # binding exactly where it was. `or "qwerty"` is for the SYNTHETIC keys
  # attrsets — flake.nix builds two by hand, for the caption golden and for the
  # published binding table — which have no layout to give and would otherwise
  # turn into `attribute 'layout' missing` the first time anything forced this.
  layout = layoutVocab.${keys.layout or "qwerty"};
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

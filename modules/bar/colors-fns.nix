# tone() and mark() as shell text — the two colour vocabularies
# (modules/bar/{tones,marks}.nix) each emitted as the case statement widgets
# resolve them through. The functions land in TWO places, and this file is
# what keeps those identical by construction:
#
#   modules/bar/default.nix   appends both to the generated colors.sh, right
#                             after the TONE_*/MARK_* exports the arms read —
#                             function and data ride one file, so they cannot
#                             skew against each other
#   test/colors-fns.sh        the committed copy for test/barlib.bats, which
#                             runs without Nix (CI and by hand) — `bar-tones`
#                             in flake.nix byte-diffs it against `fixture`
#
# Shared by the module and the check the way sides.nix is shared by
# options.nix and default.nix: one emitter, so the emission and the pin
# cannot disagree.
#
# The emitted shell is sourced by macOS /bin/bash 3.2 (every plugin): case
# arms and printf only — no ${var^^}, no locals, nothing bash 4.
{ lib }:
let
  tones = import ./tones.nix;
  marks = import ./marks.nix;

  # `"$VAR"` for a founding entry, `"${VAR:-$FB}"` when it names a fallback.
  # Concatenated rather than interpolated: `$` directly in front of `{` inside
  # a Nix string is Nix's own escape, and the first version of toneExports
  # shipped the Nix expression itself into everybody's colors.sh that way.
  ref = var: fb: if fb == null then "\"$" + var + "\"" else "\"$" + "{" + var + ":-$" + fb + "}\"";

  # Right-pad `name)` so the printf bodies line up — the emitted text is also
  # the committed test fixture, which people read.
  armWidth = entries: 2 + lib.foldl' lib.max 0 (map (e: builtins.stringLength e.name) entries);
  pad = width: s: s + lib.strings.replicate (width - builtins.stringLength s) " ";

  arms =
    prefix: entries:
    lib.concatMapStringsSep "\n" (
      e:
      "        "
      + pad (armWidth entries) (e.name + ")")
      + "printf '%s' "
      + ref (prefix + lib.toUpper e.name) e.fallback
      + " ;;"
    ) entries;

  vocab = entries: lib.concatMapStringsSep "|" (e: e.name) entries;

  mkFn =
    {
      name,
      prefix,
      entries,
      catchName,
      catchRef,
      comment,
    }:
    comment
    + name
    + "() {\n"
    + "    case \"$1\" in\n"
    + arms prefix entries
    + "\n"
    + "        *)\n"
    + "            echo \"barlib: unknown "
    + name
    + " '$1' ("
    + vocab entries
    + ") — using "
    + catchName
    + "\" >&2\n"
    + "            printf '%s' "
    + catchRef
    + "\n"
    + "            ;;\n"
    + "    esac\n"
    + "}"
    + "\n";

  toneFn = mkFn {
    name = "tone";
    prefix = "TONE_";
    entries = tones;
    catchName = "mute";
    catchRef = "\"$TONE_MUTE\"";
    comment = ''
      # tone(): the ladder as the function widgets resolve it through, generated
      # beside the exports it reads (modules/bar/colors-fns.nix, from tones.nix)
      # so the two cannot skew. Each arm's `:-` is that rung's own `fallback`
      # field — what a shell still carrying an older generation's exports
      # answers. An unknown tone is mute, not an error: a typo must cost a grey
      # pill, never a pill that stops painting; the warning goes to sketchybar's
      # log, and `bar-tones` in flake.nix is what actually catches drift.
    '';
  };

  markFn = mkFn {
    name = "mark";
    prefix = "MARK_";
    entries = marks;
    catchName = "plum";
    catchRef = ref "MARK_PLUM" "TONE_MUTE";
    comment = ''
      # mark(): the identity axis (marks.nix) as its resolver, generated the
      # same way. The catch-all is plum — the set's own catch-all mark — and
      # never grey: grey is what a dead feed is painted, and an unrecognised
      # subject is reporting perfectly well.
    '';
  };
in
{
  inherit toneFn markFn;

  # What test/colors-fns.sh must be, byte for byte.
  fixture = ''
    #!/bin/bash
    # GENERATED — tone() and mark() exactly as the generated colors.sh carries
    # them, emitted by modules/bar/colors-fns.nix from modules/bar/tones.nix
    # and modules/bar/marks.nix. Committed so `bats test/barlib.bats` (which
    # runs without Nix, in CI and by hand) exercises the very functions a real
    # bar resolves colours through: setup() appends this file to the colors.sh
    # stub it writes. Do not edit — `bar-tones` in flake.nix byte-diffs it
    # against the emitter, and when the ladder moves its failure output names
    # the regenerated file to copy over this one.

  ''
  + toneFn
  + "\n"
  + markFn;
}

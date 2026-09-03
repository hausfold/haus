# hausax — the effective appearance + accessibility oracle. `haus diff`/`haus plan`
# call it, and so does modules/theme's systemAppearance activation block.
# See hausax.swift for why a plist read isn't enough.
#
# The one helper that keeps a file of its own rather than three lines in its
# room's default.nix: TWO rooms build it (core, for the system-wide install, and
# theme, which asks for the same derivation instead of depending on core's
# let-block), and inlining it in both would put the name and the src path in two
# places for the sake of deleting one file. Every other one-file Swift helper
# calls ../lib/swift-bin.nix straight from its room — see that file for the
# xcrun rationale, which used to be re-explained in ten headers including this
# one.
{
  callPackage,
}:

(callPackage ../lib/swift-bin.nix { }) {
  name = "hausax";
  src = ./hausax.swift;
  description = "Effective appearance + accessibility state via AppKit, for haus plan/diff and theme.systemAppearance";
}

# swiftBin — the one way this repo builds a one-file Swift helper.
#
# Ten of them exist (barpop, barvitals, hausax, hausdisp, hausocr, hausrect,
# floatring, floatpin, haustabs, haus-github-receiver) and the set grows every
# few weeks — five of the ten landed in five weeks over July and August 2026.
# Before this file each one was a hand copy of a sibling: identical but for
# `pname`, `src` and a description, each re-explaining the same rationale in
# its own words and citing a different sibling as precedent.
#
# The rationale, spelled once: these compile with the SYSTEM Swift through
# `/usr/bin/xcrun`, never a nixpkgs toolchain. The Xcode CLT is already a
# prerequisite of haus — the pounce build shells out the same way — and
# building a Swift toolchain from source to compile a few hundred lines against
# AppKit, CoreGraphics, Vision or CryptoKit would cost hours. It wants the
# macOS build sandbox relaxed, which is Determinate's default.
#
# `src` is the ONE .swift file, never the directory it sits in. A path literal
# becomes its own store entry, so an edit anywhere else in the tree leaves the
# drv path byte-identical and nothing recompiles (measured 2026-09-03: touching
# an unrelated file left `barpop-1.0.drv` at the same hash). Where the CALL
# sits never mattered — the eight rooms that kept a package-*.nix file to stop
# a comment recompiling the binary were protecting something `src` already
# protects, which is why those eight files are gone and the call is three lines
# in the room's own default.nix. Two files survive, each for a reason of its
# own: modules/core/package-hausax.nix, because core and theme both build it,
# and modules/terminal/zen-tabs/package.nix, because it also owns the .xpi.
#
# A helper that needs more than this — another swiftc flag, an explicit
# `-framework`, a second product — grows THIS file rather than starting a fresh
# mkDerivation next door. `nix flake check`'s `swift-bin` fails on any `xcrun
# swiftc` under modules/ outside this file, so a fresh copy is a red build
# rather than an eleventh spelling of the same thirty lines.
{
  lib,
  stdenvNoCC,
}:

# name         the pname, the compiled binary and meta.mainProgram — all ten
#              agree on one string, so it is one argument
# src          the one .swift file
# description  meta.description: what the binary does, as a sentence
#
# `version` is deliberately NOT an argument. All ten are "1.0" and always were:
# these are files in this repo, versioned by the repo, and a per-helper version
# would only ever be noise in a store path.
{
  name,
  src,
  description,
}:

stdenvNoCC.mkDerivation {
  pname = name;
  version = "1.0";

  inherit src;
  dontUnpack = true;

  buildPhase = ''
    runHook preBuild
    /usr/bin/xcrun swiftc -O -o ${name} "$src"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp ${name} $out/bin/${name}
    runHook postInstall
  '';

  meta = {
    inherit description;
    platforms = lib.platforms.darwin;
    mainProgram = name;
  };
}

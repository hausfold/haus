# hausocr — image → text via Apple's Vision framework. See hausocr.swift for
# what it does and the exit-code contract copy-text.sh reads.
#
# Compiled with the system Swift via xcrun, exactly like the pounce package and
# this repo's other one-file helpers (hausax, hausdisp, barpop, floatring,
# hausrect): building a Swift toolchain from source to compile 60 lines against
# Vision would cost hours, and the CLT is already a prerequisite here. Kept out
# of the room's default.nix so a comment change there doesn't recompile the
# binary — `src` is the one .swift file.
{
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "hausocr";
  version = "1.0";

  src = ./hausocr.swift;
  dontUnpack = true;

  buildPhase = ''
    runHook preBuild
    /usr/bin/xcrun swiftc -O -o hausocr "$src"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp hausocr $out/bin/hausocr
    runHook postInstall
  '';

  meta = {
    description = "Recognize text in an image (offline Vision OCR) — the palette's Copy Text command";
    platforms = lib.platforms.darwin;
    mainProgram = "hausocr";
  };
}

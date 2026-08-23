# hausrect — the window-geometry oracle scripts/tiling-mode.sh sizes its grid
# columns from. See hausrect.swift for why AeroSpace can't answer the question
# itself. Compiled with the system Swift via xcrun, the same way
# modules/core/package-hausax.nix and modules/displays/package.nix build theirs
# — building a Swift toolchain from source to compile forty lines against
# CoreGraphics would cost hours, and the CLT is already a prerequisite here.
{
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "hausrect";
  version = "1.0";

  src = ./hausrect.swift;
  dontUnpack = true;

  buildPhase = ''
    runHook preBuild
    /usr/bin/xcrun swiftc -O -o hausrect "$src"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp hausrect $out/bin/hausrect
    runHook postInstall
  '';

  meta = {
    description = "On-screen window rects by window id, for haus's tiling-mode grid";
    platforms = lib.platforms.darwin;
    mainProgram = "hausrect";
  };
}

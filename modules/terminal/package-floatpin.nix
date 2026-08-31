# floatpin — the pin that keeps a float-term popup above the tiled window you
# click next. See floatpin.swift for why the window's LEVEL is the only lever
# that works, and why the request has to be an Apple event addressed by pid.
# Compiled with the system Swift via xcrun, exactly like its sibling
# package-floatring.nix and modules/core's hausax: the CLT is already a
# prerequisite of this rice, and building a Swift toolchain from source to
# compile ~180 lines against AppKit would cost hours. Kept out of default.nix so
# a comment there doesn't recompile the binary — `src` is the one .swift file.
{
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "floatpin";
  version = "1.0";

  src = ./floatpin.swift;
  dontUnpack = true;

  buildPhase = ''
    runHook preBuild
    /usr/bin/xcrun swiftc -O -o floatpin "$src"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp floatpin $out/bin/floatpin
    runHook postInstall
  '';

  meta = {
    description = "Keep a Ghostty float-term popup above every tiled window, by window level";
    platforms = lib.platforms.darwin;
    mainProgram = "floatpin";
  };
}

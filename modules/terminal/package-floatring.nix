# floatring — the outline around the rice's floating Ghostty popups. See
# floatring.swift for why Ghostty, aerospace and JankyBorders each can't do it.
# Compiled with the system Swift via xcrun, exactly like modules/core's hausax and
# modules/bar's barpop: the CLT is already a prerequisite of this rice, and
# building a Swift toolchain from source to compile ~150 lines against AppKit
# would cost hours. Kept out of default.nix so a comment there doesn't recompile
# the binary — `src` is the one .swift file.
{
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "floatring";
  version = "1.0";

  src = ./floatring.swift;
  dontUnpack = true;

  buildPhase = ''
    runHook preBuild
    /usr/bin/xcrun swiftc -O -o floatring "$src"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp floatring $out/bin/floatring
    runHook postInstall
  '';

  meta = {
    description = "Rounded accent/grey outline around another process's window, for the floating Ghostty popups";
    platforms = lib.platforms.darwin;
    mainProgram = "floatring";
  };
}

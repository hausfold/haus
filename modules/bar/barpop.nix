# barpop — the bar's popup dismisser. See barpop.swift for why SketchyBar can't
# do this itself (it only ever hears about clicks on its own items).
#
# Compiled with the system Swift via xcrun, exactly like modules/displays (and the
# pounce package upstream): the CLT is already a prerequisite of haus, and
# building a Swift toolchain from source to compile 180 lines against AppKit would
# cost hours. Kept out of the room's default.nix so a comment there doesn't
# recompile the binary — `src` is the one .swift file.
{
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "barpop";
  version = "1.0";

  src = ./barpop.swift;
  dontUnpack = true;

  buildPhase = ''
    runHook preBuild
    /usr/bin/xcrun swiftc -O -o barpop "$src"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp barpop $out/bin/barpop
    runHook postInstall
  '';

  meta = {
    description = "Close a SketchyBar popup on the first click outside it";
    platforms = lib.platforms.darwin;
    mainProgram = "barpop";
  };
}

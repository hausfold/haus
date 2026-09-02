# hausdisp — haus's display-mode helper. See hausdisp.swift for what it does
# and why the mode ladder is derived rather than tabulated.
#
# Compiled with the system Swift via xcrun, exactly like the pounce package does
# (pkgs/pounce/default.nix in the pounce repo): building the Swift toolchain from
# source to compile 150 lines against CoreGraphics would cost hours, and the CLT
# is already a prerequisite for haus. Kept out of the room's default.nix so a
# comment change there doesn't recompile the binary — `src` is the one .swift file.
{
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "hausdisp";
  version = "1.0";

  src = ./hausdisp.swift;
  dontUnpack = true;

  buildPhase = ''
    runHook preBuild
    /usr/bin/xcrun swiftc -O -o hausdisp "$src"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp hausdisp $out/bin/hausdisp
    runHook postInstall
  '';

  meta = {
    description = "Set a display's scaled resolution by intent (haus.displays)";
    platforms = lib.platforms.darwin;
    mainProgram = "hausdisp";
  };
}

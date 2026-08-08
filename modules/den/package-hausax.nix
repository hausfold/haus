# hausax — the effective appearance + accessibility oracle. `haus diff`/`haus plan`
# call it, and so does modules/theme's systemAppearance activation block.
# See hausax.swift for why a plist read isn't enough. Compiled with the system
# Swift via xcrun, the same way modules/displays/package.nix builds hausdisp —
# building the Swift toolchain from source to compile a few dozen lines against
# AppKit would cost hours, and the CLT is already a prerequisite for this rice.
{
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "hausax";
  version = "1.0";

  src = ./hausax.swift;
  dontUnpack = true;

  buildPhase = ''
    runHook preBuild
    /usr/bin/xcrun swiftc -O -o hausax "$src"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp hausax $out/bin/hausax
    runHook postInstall
  '';

  meta = {
    description = "Effective appearance + accessibility state via AppKit, for haus plan/diff and theme.systemAppearance";
    platforms = lib.platforms.darwin;
    mainProgram = "hausax";
  };
}

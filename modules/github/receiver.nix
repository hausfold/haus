# haus-github-receiver — see receiver.swift for what it does and why the fan-out
# is bytes rather than events.
#
# Compiled with the system Swift via xcrun, exactly like barpop, floatring,
# hausrect, hausax and hausdisp: the Xcode CLT is already a prerequisite of this
# rice, and building a Swift toolchain from source to compile 400 lines against
# Foundation and CryptoKit would cost hours. Kept out of the room's default.nix
# so a comment there doesn't recompile the binary — `src` is the one .swift file.
{
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "haus-github-receiver";
  version = "1.0";

  src = ./receiver.swift;
  dontUnpack = true;

  buildPhase = ''
    runHook preBuild
    /usr/bin/xcrun swiftc -O -o haus-github-receiver "$src"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp haus-github-receiver $out/bin/haus-github-receiver
    runHook postInstall
  '';

  meta = {
    description = "Verify, record and fan out GitHub webhook deliveries on loopback";
    platforms = lib.platforms.darwin;
    mainProgram = "haus-github-receiver";
  };
}

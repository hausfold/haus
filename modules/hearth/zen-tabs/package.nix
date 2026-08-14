# The two build products of the tab bridge: the native-messaging host, and the
# extension packed into an .xpi.
#
# Compiled with the system Swift via xcrun, exactly like sillpop and
# modules/displays — the CLT is already a prerequisite of this rice, and building
# a Swift toolchain from source to compile 150 lines against Foundation would
# cost hours.
{
  lib,
  stdenvNoCC,
  runCommand,
  zip,
}:

rec {
  haustabs = stdenvNoCC.mkDerivation {
    pname = "haustabs";
    version = "1.0";

    src = ./haustabs.swift;
    dontUnpack = true;

    buildPhase = ''
      runHook preBuild
      /usr/bin/xcrun swiftc -O -o haustabs "$src"
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin
      cp haustabs $out/bin/haustabs
      runHook postInstall
    '';

    meta = {
      description = "Native-messaging host publishing Zen's tabs to haus";
      platforms = lib.platforms.darwin;
      mainProgram = "haustabs";
    };
  };

  # An .xpi is a zip with manifest.json at its root. Zen installs an unsigned
  # one only because it is built `MOZ_REQUIRE_SIGNING = false` AND something
  # turns `xpinstall.signatures.required` back off — Zen's own greprefs.js is
  # not that something, Firefox's application prefs re-assert it. hearth's
  # policy plist does it; see default.nix, where the pair is explained.
  #
  # `touch` before zipping is not tidiness: every file in the store is stamped
  # epoch 1, the zip format cannot represent a year before 1980, and `zip`
  # refuses rather than rounding. `-X` drops the extra attributes that would
  # otherwise carry the build's uid/gid into the archive.
  xpi = runCommand "zen-tabs-xpi" { nativeBuildInputs = [ zip ]; } ''
    mkdir -p build $out
    cp ${./manifest.json} build/manifest.json
    cp ${./bridge.js} build/bridge.js
    find build -exec touch -t 198001010000 {} +
    (cd build && zip -q -r -X "$out/zen-tabs.xpi" .)
  '';
}

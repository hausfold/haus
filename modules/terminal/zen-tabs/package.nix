# The two build products of the tab bridge: the native-messaging host, and the
# extension packed into an .xpi.
#
# This file survives the move to ../../lib/swift-bin.nix (which every other
# one-file Swift helper now calls straight from its room) because it is not one
# product but two, and the .xpi below is nobody else's shape.
{
  lib,
  stdenvNoCC,
  runCommand,
  zip,
}:

rec {
  haustabs = (import ../../lib/swift-bin.nix { inherit lib stdenvNoCC; }) {
    name = "haustabs";
    src = ./haustabs.swift;
    description = "Native-messaging host publishing Zen's tabs to haus";
  };

  # An .xpi is a zip with manifest.json at its root. Zen installs an unsigned
  # one only because it is built `MOZ_REQUIRE_SIGNING = false` AND something
  # turns `xpinstall.signatures.required` back off — Zen's own greprefs.js is
  # not that something, Firefox's application prefs re-assert it. terminal's
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

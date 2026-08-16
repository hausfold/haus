# barvitals — the cpu and memory pills' sampler. See barvitals.swift for why
# neither pill can get an honest number out of `ps` or `memory_pressure`, and
# why the alternative that can (`top -l 2`) costs a second of wall clock per
# reading.
#
# Compiled with the system Swift via xcrun, exactly like barpop next door: the
# CLT is already a prerequisite of this rice, and this is one file against
# Darwin with no package to fetch. Kept out of the room's default.nix so a
# comment there doesn't recompile the binary — `src` is the one .swift file.
{
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "barvitals";
  version = "1.0";

  src = ./barvitals.swift;
  dontUnpack = true;

  buildPhase = ''
    runHook preBuild
    /usr/bin/xcrun swiftc -O -o barvitals "$src"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp barvitals $out/bin/barvitals
    runHook postInstall
  '';

  meta = {
    description = "One sample of CPU and memory, for the bar's readout pills";
    platforms = lib.platforms.darwin;
    mainProgram = "barvitals";
  };
}

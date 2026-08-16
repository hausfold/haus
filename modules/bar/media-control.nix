# media-control — the only way left to read macOS's system-wide "now playing".
#
# Apple locked MediaRemote down in macOS 15.4: `mediaremoted` now checks the
# CALLER's entitlement, so any process that dlopens the framework itself is
# refused. That is exactly what SketchyBar's own `media_change` event does, which
# is why the media pill has been permanently dark on 15.4+ (FelixKratz/SketchyBar
# #708, still open) and why this rice has to bring its own reader. There is no
# public API to fall back on and never was: MPNowPlayingInfoCenter only ever let
# an app publish its OWN state, it cannot read the system's.
#
# ungive/media-control gets around it without touching SIP. /usr/bin/perl is an
# Apple-signed binary whose bundle id is com.apple.perl, and it IS entitled — so
# the work happens INSIDE perl: the front-end re-execs the adapter script, which
# dl_load_file()s a small helper framework and prints now-playing JSON (and sends
# transport commands) from a process the daemon is willing to answer. Two
# consequences shape this derivation:
#
#   * The shebang must stay /usr/bin/perl. bin/media-control re-execs through
#     $^X — the CURRENT interpreter — so a shebang rewritten to the nixpkgs perl
#     would hand the framework to an unentitled process and every call would come
#     back empty, silently. `dontPatchShebangs` is load-bearing, not tidiness.
#   * Upstream builds the framework with CMake, but the perl loader only ever
#     dl_load_file()s <name>.framework/<name> — no Info.plist and no Versions
#     symlink farm is ever read. So it is compiled here the way barpop and
#     modules/displays compile theirs, with one `xcrun clang` against the CLT
#     that is already a prerequisite of this rice, which keeps cmake out of the
#     closure for what is really just a dylib in a directory.
#
# The upstream repo vendors the adapter as a git submodule; both halves are
# fetched separately and pinned to the same v0.7.6 revision the submodule points
# at. Bump them together.
#
# This is a private-framework hole and Apple may close it in any point release.
# `media-control test` (which publishes a throwaway now-playing entry through the
# bundled test client and reads it back) is the one-command way to tell whether
# it still works — a non-zero exit means the tool is no longer functional.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:

let
  version = "0.7.6";

  adapter = fetchFromGitHub {
    owner = "ungive";
    repo = "mediaremote-adapter";
    rev = "3ac3d4bdf862c7b5399b4fba4df5689f5c38609a"; # the v0.7.6 submodule pin
    hash = "sha256-+EZy5qdNombUq8knkeUmycIZuPp5G+IrYlrtdF+Y0ZU=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "media-control";
  inherit version;

  src = fetchFromGitHub {
    owner = "ungive";
    repo = "media-control";
    rev = "v${version}";
    hash = "sha256-GqOfZjle2cif69BT72RtaozJ6HtvRO3ktMN6lncCHaA=";
  };

  # See the header — this one is not cosmetic.
  dontPatchShebangs = true;

  buildPhase = ''
    runHook preBuild

    mkdir -p MediaRemoteAdapter.framework
    /usr/bin/xcrun clang -dynamiclib -fobjc-arc -fvisibility=default -O2 \
      -I${adapter}/include -I${adapter}/src \
      -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
      -o MediaRemoteAdapter.framework/MediaRemoteAdapter \
      ${adapter}/src/adapter/*.m ${adapter}/src/private/*.m ${adapter}/src/utility/*.m

    /usr/bin/xcrun clang -fobjc-arc -O2 \
      -I${adapter}/src/test \
      -framework Foundation -framework MediaPlayer \
      -o MediaRemoteAdapterTestClient \
      ${adapter}/src/test/main.m ${adapter}/src/test/NowPlayingTest.m

    # arm64 clang already ad-hoc signs what it links; upstream re-signs anyway
    # and it costs nothing to match, so a toolchain that stops doing it can't
    # quietly produce a framework dyld refuses to map.
    /usr/bin/codesign --force --sign - MediaRemoteAdapter.framework/MediaRemoteAdapter || true

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib/media-control $out/Frameworks
    cp bin/media-control $out/bin/media-control
    cp ${adapter}/bin/mediaremote-adapter.pl $out/lib/media-control/
    cp MediaRemoteAdapterTestClient $out/lib/media-control/
    cp -R MediaRemoteAdapter.framework $out/Frameworks/
    chmod 755 $out/bin/media-control $out/lib/media-control/mediaremote-adapter.pl

    # Upstream locates its three helpers relative to FindBin, which assumes the
    # bin/ it was invoked from is the one it was installed into. Through a nix
    # profile symlink that is /run/current-system/sw/bin, whose ../lib holds no
    # media-control, so every call would die on a missing adapter script. Pinning
    # $FindBin::Bin to the store bin/ is the whole fix and leaves the layout
    # upstream expects intact.
    substituteInPlace $out/bin/media-control \
      --replace-fail "\$FindBin::Bin" "'$out/bin'"

    runHook postInstall
  '';

  meta = {
    description = "Read and control macOS system-wide now-playing media from the command line";
    homepage = "https://github.com/ungive/media-control";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.darwin;
    mainProgram = "media-control";
  };
}

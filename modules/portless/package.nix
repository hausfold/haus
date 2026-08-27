# portless, built from the npm registry tarball — it is not in nixpkgs.
#
# A plain fetchurl + makeWrapper rather than buildNpmPackage: portless ships
# ZERO runtime dependencies (its package.json has no `dependencies` key) and one
# bundled entry point, so there is no dependency tree to lock, no lockfile hash
# to keep in sync, and nothing to build. The published tarball IS the artifact.
#
# The node it runs on is PINNED here, and on this machine that is load-bearing
# rather than tidy: node arrives through fnm, which is per-user and per-DIRECTORY
# (`fnm env --use-on-cd` in the user's zshrc), so the ambient `node` is whatever
# the current checkout's .node-version says — and the root launchd daemon below
# has no fnm at all. A wrapper that resolved node from PATH would be a proxy that
# starts from one directory, fails from another, and never starts at boot.
{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  nodejs_24,
  openssl,
  git,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "portless";
  version = "0.15.6";

  src = fetchurl {
    url = "https://registry.npmjs.org/portless/-/portless-${finalAttrs.version}.tgz";
    hash = "sha256-SPFeXWPEd4RTTdletSAefmWM5D6uG3q5YNNLbWe5VIo=";
  };

  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;

  # `git` (worktree detection) and `openssl` (CA + per-host leaf certs) are
  # shelled out to BY NAME, so they have to be on the wrapper's PATH. `security`
  # and `launchctl` are macOS's own and are called at their absolute system
  # paths, so they need nothing from us.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/portless
    cp -R dist package.json $out/lib/portless/
    makeWrapper ${lib.getExe nodejs_24} $out/bin/portless \
      --add-flags $out/lib/portless/dist/cli.js \
      --prefix PATH : ${
        lib.makeBinPath [
          openssl
          git
        ]
      }
    runHook postInstall
  '';

  meta = {
    description = "Replace port numbers with stable, named .localhost URLs";
    homepage = "https://portless.sh";
    license = lib.licenses.asl20;
    mainProgram = "portless";
    platforms = lib.platforms.unix;
  };
})

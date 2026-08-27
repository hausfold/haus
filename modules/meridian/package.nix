# meridian, built from the npm registry tarball — it is not in nixpkgs.
#
# `buildNpmPackage` rather than portless' fetchurl + makeWrapper, because the two
# packages are opposites on the one axis that decides it: portless' package.json
# has no `dependencies` key at all, and meridian's has four — one of which
# (`libsql`) is a native module that arrives as a per-platform prebuilt `.node`
# through optional dependencies. There is a real tree to lock here, so it gets
# locked.
#
# What is NOT built is the JavaScript. Upstream builds with `bun`, and the
# published tarball already carries the result (`dist/`, and `files` in
# package.json ships nothing else) — so `dontNpmBuild` is set and this
# derivation's whole job is resolving the runtime tree around a bundle that is
# already an artifact. Building from the GitHub source instead would mean
# carrying bun and bun2nix to reproduce a `dist/` the registry hands us.
#
# THE LOCKFILE IS OURS. The npm tarball ships no `package-lock.json` (npm never
# packs one), and `fetchNpmDeps` cannot resolve a tree without one, so
# `package-lock.json` beside this file is generated and committed:
#
#     tar xzf meridian-<version>.tgz && cd package
#     npm install --package-lock-only --omit=dev --ignore-scripts
#     cp package-lock.json <this directory>/
#     prefetch-npm-deps package-lock.json      # → npmDepsHash below
#
# It pins `^`-ranged dependencies to whatever npm resolved on the day it was
# generated, which is the point: a range would make two machines building the
# same meridian version get different trees. Regenerate BOTH files together when
# `version` moves — a stale lock against a new tarball is an `npm ci` failure
# that names the version mismatch, which is the error we want.
#
# The node it runs on is PINNED, for the reason
# modules/portless/package.nix' header spells out at length: node arrives through
# fnm on this machine, which is per-user and per-DIRECTORY, and the launchd agent
# that runs this has no fnm and no login shell. package.json says
# `engines: node >=22`; 22 is what the hand-rolled trial install ran on and is
# what this pins. A wrapper resolving `node` from PATH would be a proxy that
# starts from one directory and not another, and never at login.
{
  lib,
  buildNpmPackage,
  fetchurl,
  makeWrapper,
  nodejs_22,
}:

buildNpmPackage (finalAttrs: {
  pname = "meridian";
  version = "1.62.7";

  src = fetchurl {
    url = "https://registry.npmjs.org/@rynfar/meridian/-/meridian-${finalAttrs.version}.tgz";
    hash = "sha256-LBOanaxg31gr5varijWpTxNGLu05cQUpLGqDE7erqQ0=";
  };

  nodejs = nodejs_22;

  postPatch = ''
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-zGTStDL7Eu/AU0xiCsBUZRlOpzuNWRiCn274Rcx49Lc=";

  # The devDependencies are the build's, and the build already happened upstream:
  # `bun`, `bun2nix`, `typescript` and `glob` produce the `dist/` in the tarball,
  # and `hono` is bundled INTO it (upstream's `bun build` externalises only
  # `@anthropic-ai/claude-agent-sdk` and `jsonc-parser`).
  #
  # The flag reaches `npm ci` (npmConfigHook), and it changes what is UNPACKED
  # rather than what is fetched: the committed lock keeps the dev entries as
  # `"dev": true`, so `npmDepsHash` covers them either way and the offline cache
  # holds them regardless. Worth setting anyway — the install hook's
  # `npm prune --omit=dev`, which runs unconditionally and would drop them in the
  # end, is not the step you want discovering a dev tree it cannot resolve
  # offline. Same closure, one fewer way to fail.
  npmInstallFlags = [ "--omit=dev" ];
  dontNpmBuild = true;

  nativeBuildInputs = [ makeWrapper ];

  # nodejsInstallExecutables leaves `bin/meridian` a symlink onto `dist/cli.js`,
  # whose `#!/usr/bin/env node` shebang is exactly the PATH lookup the header
  # above rules out. Replace both of upstream's names with wrappers that name the
  # pinned node. `claude-max-proxy` is upstream's older alias for the same entry
  # point and is kept because `meridian doctor` and its README both still print
  # it.
  postInstall = ''
    rm -f $out/bin/meridian $out/bin/claude-max-proxy
    for name in meridian claude-max-proxy; do
      makeWrapper ${lib.getExe nodejs_22} $out/bin/$name \
        --add-flags $out/lib/node_modules/@rynfar/meridian/dist/cli.js \
        --prefix PATH : ${lib.makeBinPath [ nodejs_22 ]}
    done
  '';

  meta = {
    description = "Local Anthropic API served from a Claude Max subscription";
    homepage = "https://github.com/rynfar/meridian";
    license = lib.licenses.mit;
    mainProgram = "meridian";
    platforms = lib.platforms.unix;
  };
})

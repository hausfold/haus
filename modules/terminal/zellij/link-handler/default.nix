# Built with `pkgs.pkgsCross.wasi32.callPackage` from terminal — zellij plugins
# are wasm32-wasip1 binaries, and the wasi32 cross set is how nixpkgs itself
# builds its zellijPlugins (see pkgs/by-name/ze/zellij/plugins/rust). The
# explicit lld/wasm-ld pin is lifted from there too ("needed until
# nixpkgs#463720 is resolved").
{ lib, rustPlatform, lld }:

rustPlatform.buildRustPackage {
  pname = "link-handler";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
    ];
  };

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [ lld ];
  env.RUSTFLAGS = "-C linker=wasm-ld";

  # The tests are host tests inherited from the upstream fork; the build
  # targets wasi and can't execute them.
  doCheck = false;
}

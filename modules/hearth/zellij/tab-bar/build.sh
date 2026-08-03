#!/bin/bash
# Builds the zellij-tab-bar WASM plugin (nix cross-build, no rustup needed) and
# prints the .wasm path on stdout — the dev loop for feeling a change without a
# rebuild:
#
#   zscratch --plugin tab-bar="$(./build.sh)"
#
# A REBUILD DOES NOT RUN THIS. hearth builds ./default.nix itself (zellijPlugins
# in modules/hearth/default.nix), so the installed plugin always matches ./src
# and there is no vendored blob to keep in sync. This script exists purely to
# get a candidate .wasm in front of zscratch a few seconds sooner.
#
# (It builds against the registry nixpkgs, not the flake-pinned one, so the
# store hash differs from what a rebuild produces. Same source, different
# toolchain rev — fine for feeling a change, not a substitute for `bench try`.)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "Building zellij-tab-bar WASM plugin (pkgsCross.wasi32)..." >&2
out=$(nix build --impure --no-link --print-out-paths --expr \
  '(builtins.getFlake "nixpkgs").legacyPackages.${builtins.currentSystem}.pkgsCross.wasi32.callPackage ./default.nix {}')

echo "$out/bin/zellij-tab-bar.wasm"

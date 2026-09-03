#!/usr/bin/env bash
# Refresh the vendored Claude Code release manifests that ./claude-code.nix
# pins the package to. No argument takes the newest release; pass a version to
# take that one instead:
#
#     modules/lib/claude-code-update.sh
#     modules/lib/claude-code-update.sh 2.1.259
#
# Both files are fetched together and must stay on the same version — which of
# them gets used depends on the nixpkgs in play, and claude-code.nix throws if
# they ever disagree.
#
# Nothing else to do afterwards: the manifest carries its own version and one
# upstream sha256 per platform, so there is no hash to re-derive by hand.
# `claudeFloor` in modules/ai/default.nix is a separate decision and moves only
# when a new model raises the bar.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

BASE_URL="https://downloads.claude.ai/claude-code-releases"

VERSION="${1:-$(curl -fsSL "$BASE_URL/latest")}"

curl -fsSL "$BASE_URL/$VERSION/manifest.json" --output claude-code-manifest.json
curl -fsSL "$BASE_URL/$VERSION/manifest.zst.json" --output claude-code-manifest.zst.json

echo "claude-code manifests are now $VERSION"

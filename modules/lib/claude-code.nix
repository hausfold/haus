# Claude Code, held AHEAD of nixpkgs. This overlay decides WHICH build of
# `claude-code` exists on a haus machine, so modules/lib/agent-packages.nix can
# go on being a one-line reference to `pkgs.claude-code`.
#
# WHY haus pins at all, when nixpkgs already packages it: Claude Code gates
# MODELS on the client version. Fable 5.1 needs 2.1.255 or later, and below
# that `/model` still lists it and refuses it — "Update to 2.1.255+ to use
# Fable 5.1". nixpkgs' claude-code moves on a hand-run update script, so it
# trails the releases; haus's own nixpkgs pin trails that again; and Claude
# Code ships most days. The result is not a failure anyone reports — nothing
# crashes, a model the user's plan already includes is quietly absent from a
# menu. That invisibility is the argument: pi's floor in agent-packages.nix
# kills the pane outright and gets noticed, this one never would.
#
# An OVERLAY rather than another entry in modules/lib/agent-packages.nix, and
# the difference is composition. That table is `claude = pkgs.claude-code`, and
# its header tells a host that wants a patched build to overlay `claude-code`.
# Pinning in the table would mean calling `.override { manifest = …; }` on
# whatever that host overlay returned — a symlinkJoin wrapper, in the case this
# was written for — which takes no `manifest` argument and fails eval. Pinning
# here puts the version UNDERNEATH every host overlay instead: `prev.claude-code`
# inside a host's own overlay is already this one, patches ride on top, and the
# table keeps its meaning.
#
# The pin is Anthropic's own release manifest, vendored — the same file nixpkgs
# vendors, and the whole input a version bump needs: a version and one sha256
# per platform, published upstream rather than re-derived here. Refresh it with
# ./claude-code-update.sh. `claudeFloor` in modules/ai/default.nix is the
# separate question of which version haus REFUSES to go below, and only moves
# when a new model raises the bar.
#
# Two manifests, because nixpkgs changed the package's shape mid-flight: the
# older one fetches an uncompressed binary described by `manifest.json`, the
# newer one a zstd-compressed `claude.zst` described by `manifest.zst.json`.
# They are not interchangeable — hand over the wrong one and the build dies
# inside `unzstd` with nothing pointing back here. Which one this nixpkgs
# parses is legible from the src it would otherwise have fetched, so the choice
# is read off that rather than pinned to a nixpkgs generation.
_final: prev:
let
  inherit (prev) lib;

  plain = lib.importJSON ./claude-code-manifest.json;
  zst = lib.importJSON ./claude-code-manifest.zst.json;

  # `claude` vs `claude.zst` — the basename of the URL this nixpkgs' package
  # would fetch, and the one honest signal of which manifest it expects.
  # Evaluating `.src` builds no fetcher; it only names one.
  pinned = if lib.hasSuffix ".zst" (prev.claude-code.src.name or "") then zst else plain;
in
{
  # Never a DOWNGRADE. A vendored pin goes stale by doing nothing, and the day
  # nixpkgs passes it this overlay would start dragging every haus machine
  # backwards — the exact failure it exists to prevent, wearing the other face.
  # So it steps aside instead, which is also what makes "delete this when
  # nixpkgs catches up" a tidy-up rather than a deadline.
  claude-code =
    lib.throwIf (plain.version != zst.version)
      ''
        haus's two vendored claude-code manifests disagree: claude-code-manifest.json
        is ${plain.version} and claude-code-manifest.zst.json is ${zst.version}. They
        must describe the same release, because which one gets used depends on the
        nixpkgs in play. Re-run modules/lib/claude-code-update.sh, which fetches
        both for one version.
      ''
      (
        if lib.versionAtLeast prev.claude-code.version pinned.version then
          prev.claude-code
        else
          prev.claude-code.override { manifest = pinned; }
      );
}

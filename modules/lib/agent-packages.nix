# One coding-agent client id → the one derivation that installs it, or `null`
# for a client nixpkgs has no derivation for.
#
# Nothing else in the rice may name these derivations: a host that wants a
# patched build overlays `claude-code` (or `codex`, or `opencode`) so this
# reference picks the patched one up. Adding a second derivation of the same
# client beside this one puts two `bin/claude` in one profile, which is a
# collision, not an override.
#
# It sits in modules/lib rather than in the room that installs them because two
# rooms need it and the rule above only holds while there is exactly one table:
# the AI room asserts every named client is BUILDABLE here, and terminal is where
# a home profile can actually install one. The keys are modules/lib/agents.nix's
# client ids, which is the list the options are typed against.
#
# `null` means "not from nixpkgs" — the AI room installs that client from
# Homebrew instead (a roster entry it contributes, see modules/ai/default.nix),
# and every consumer here skips the null rather than trying to build it. It is
# a null and not an absent key on purpose: the tables keyed by client id fail
# eval with `attribute '<id>' missing` when a client is added to
# modules/lib/agents.nix and forgotten here, and that is the error we want.
pkgs: {
  claude = pkgs.claude-code;
  codex = pkgs.codex;
  opencode = pkgs.opencode;
  # jcode (jcode.sh) ships a Homebrew tap and release binaries; there is no
  # nixpkgs derivation, and its own tree carries no flake. A third-party wrapper
  # exists (github:hypervideo/jcode-nix) and would be a flake input rather than
  # an entry here — deliberately not taken: jcode cuts releases most days, so
  # the input would put a lock bump on that cadence in front of every consumer.
  jcode = null;
}

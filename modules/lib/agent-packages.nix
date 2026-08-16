# One coding-agent client id → the one derivation that installs it.
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
pkgs: {
  claude = pkgs.claude-code;
  codex = pkgs.codex;
  opencode = pkgs.opencode;
}

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
#
# Every key in modules/lib/agents.nix must appear here: the tables keyed by
# client id fail eval with `attribute '<id>' missing` when a client is added
# there and forgotten here, and that is the error we want.
#
# One entry is not a bare nixpkgs reference, and says why beside itself.
pkgs: {
  claude = pkgs.claude-code;
  codex = pkgs.codex;
  opencode = pkgs.opencode;

  # pi, held one release AHEAD of nixpkgs (0.84.1 at this pin), and this is a
  # correctness floor rather than a taste for new versions.
  #
  # `--` — end-of-options — reached pi in 0.84.3. Every earlier version rejects
  # it outright:
  #
  #     $ pi -- "hello"
  #     Error: Unknown option: --
  #
  # and scruff's pi spec ends option parsing with `--` before the prompt, because
  # a first-turn brief typed into Pounce's Spawn Agent box is very often a
  # markdown list whose first character is a dash — a FLAG to pi's parser, and a
  # pane that dies before the agent draws anything. So on 0.84.1 every prompted
  # pi lane is dead on arrival. That is the dead-pane failure `ai.clients`
  # exists to end, arriving through the package instead of the option.
  #
  # Structured as an override of the nixpkgs derivation rather than a copy of
  # it: the build recipe is upstream's and stays upstream's, and only the three
  # values that move with a version are named here. When nixpkgs reaches 0.84.3
  # or later, DELETE this whole block and leave `pi = pkgs.pi-coding-agent;` —
  # the assertion in modules/ai/default.nix is what will tell you it is safe,
  # because it fails the rebuild if the floor is ever unmet again.
  #
  # `npmDeps` is replaced rather than `npmDepsHash` because buildNpmPackage
  # turns the hash into a fetcher inside its own `finalAttrs`, so an
  # overrideAttrs that set the hash alone would be silently ignored and the
  # 0.84.1 dependency set would be built against the 0.84.3 source.
  pi = pkgs.pi-coding-agent.overrideAttrs (
    final: _prev: {
      version = "0.84.3";
      src = pkgs.fetchFromGitHub {
        owner = "earendil-works";
        repo = "pi";
        tag = "v${final.version}";
        hash = "sha256-fC9pKgP2qD61ae5d7iOqP8anl88J1N1Bq8X8+aAjA2A=";
      };
      # The provider model catalogue is gitignored upstream and restored from the
      # matching npm tarball — nixpkgs' own comment explains it. It is version-
      # locked to the source, so it moves with it.
      modelData = pkgs.fetchurl {
        url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${final.version}.tgz";
        hash = "sha256-nECvL0OVD46U57vNDBs1SPAAly2gDE+5wNBSnU19VDE=";
      };
      npmDeps = pkgs.fetchNpmDeps {
        inherit (final) src;
        name = "pi-coding-agent-${final.version}-npm-deps";
        hash = "sha256-cDx28+c4bwtQpiy5+BCvZhZezoZb4WRqfZj2eoEeMbw=";
      };
    }
  );
}

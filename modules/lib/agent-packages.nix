# One coding-agent client id → the one derivation that installs it.
#
# Nothing else in haus may name these derivations: a host that wants a
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
pkgs:
let
  # pi resolves the packages `haus.ai.pi.packages` declares by spawning `npm`
  # at STARTUP, and haus ships no node toolchain — so on a machine that never
  # had npm, the four packages the AI room declares by default make pi die on
  # an uncaught `Error: spawn npm ENOENT` before it draws anything. It does not
  # warn and continue: `resolvePackageSources` lets the spawn failure escape,
  # so a client haus installed is dead on arrival on its own defaults.
  #
  # The npm handed in here is pi's OWN node — `pkgs.nodejs` is the interpreter
  # nixpkgs already exec's pi with, so this adds no closure and cannot skew a
  # version against the runtime. `pi install` starts working as a consequence,
  # and that is a consequence rather than a blessing — it is still imperative,
  # unpinned and outside nix, and nothing here points anyone at it.
  #
  # 🚨 `--suffix`, NOT `--prefix`, and the difference is the whole safety of
  # this. pi is a coding agent with a shell tool, so every command a pi lane
  # runs — `npm test`, `npx`, anything resolving `node` — inherits pi's PATH.
  # Prefixed, `${pkgs.nodejs}/bin` would put node, npm, npx and corepack AHEAD
  # of whatever the machine has, and an agent in a repo pinned to node 22 would
  # silently get this one, on a machine whose owner never asked for a node at
  # all. Suffixed, it is a FLOOR: it answers `spawn npm` where nothing else
  # would, and loses to a homebrew/fnm/volta toolchain wherever one exists —
  # which is also exactly the behaviour a machine that already had npm has
  # today, so this changes nothing for those and fixes the ones with none.
  #
  # Upstream prefixes ripgrep and fd for the opposite reason and correctly: a
  # tool pi calls for ITSELF wants to be the one pi built against. A language
  # runtime is not that — projects pin it, and the agent's shell is the user's.
  #
  # Building the declared set in nix instead was the other candidate and does
  # not fit the option: `ai.pi.packages` is a free-form list of npm and git
  # sources a host may add to, and nix cannot fetch an arbitrary one without a
  # hash per entry. That fix would cover four literal values rather than the
  # option, and every entry a host added would crash pi exactly as before.
  #
  # Appended to upstream's `postFixup` rather than replacing it, so a change to
  # what nixpkgs puts on pi's PATH (ripgrep and fd today) rides through instead
  # of being silently pinned to the copy that was true when this was written.
  # The second wrapper costs one exec.
  withNpm =
    drv:
    drv.overrideAttrs (
      _final: prev: {
        postFixup = (prev.postFixup or "") + ''
          wrapProgram $out/bin/pi --suffix PATH : ${pkgs.lib.makeBinPath [ pkgs.nodejs ]}
        '';
      }
    );
in
{
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
  # or later, DELETE this whole block and leave `pi = withNpm pkgs.pi-coding-agent;`
  # — the assertion in modules/ai/default.nix is what will tell you it is safe,
  # because it fails the rebuild if the floor is ever unmet again. Keep the
  # `withNpm`: it is not part of the floor and nixpkgs catching up does not
  # give pi a package manager.
  #
  # `npmDeps` is replaced rather than `npmDepsHash` because buildNpmPackage
  # turns the hash into a fetcher inside its own `finalAttrs`, so an
  # overrideAttrs that set the hash alone would be silently ignored and the
  # 0.84.1 dependency set would be built against the 0.84.3 source.
  pi = withNpm (
    pkgs.pi-coding-agent.overrideAttrs (
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
    )
  );
}

# pi. The record modules/ai/clients/default.nix describes; the AI room renders
# it.
{
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
  # or later, DELETE the override and leave `withNpm pkgs.pi-coding-agent`
  # — `floor` below is what will tell you it is safe,
  # because it fails the rebuild if the floor is ever unmet again. Keep the
  # `withNpm`: it is not part of the floor and nixpkgs catching up does not
  # give pi a package manager.
  #
  # `npmDeps` is replaced rather than `npmDepsHash` because buildNpmPackage
  # turns the hash into a fetcher inside its own `finalAttrs`, so an
  # overrideAttrs that set the hash alone would be silently ignored and the
  # 0.84.1 dependency set would be built against the 0.84.3 source.
  package =
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
    withNpm (
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

  # The pi release that first accepted `--`; `package` above is the pin that
  # satisfies it. scruff's pi spec puts a `--` before the first-turn prompt, so
  # an older pi turns every PROMPTED lane into a pane that dies before the agent
  # draws. A lane opened with no prompt would keep working, which is what makes
  # this worth asserting instead of leaving to be discovered: the failure is
  # intermittent by workflow. Quiet once nixpkgs has caught up; the named
  # refusal instead of the dead pane when it has not.
  floor = {
    version = "0.84.3";
    message =
      built:
      "haus.ai.clients names pi, but this pkgs builds pi ${built} and "
      + "scruff needs 0.84.3 or later: `--` (end-of-options) landed in 0.84.3, and "
      + "without it every lane spawned WITH a prompt dies on `Error: Unknown option: --` "
      + "before the agent draws. Restore the version pin in "
      + "modules/ai/clients/pi/default.nix, or drop pi from ai.clients.";
  };

  # pi keeps everything under one agent directory, `~/.pi/agent`, and reads
  # `AGENTS.md` there as its global context file. `CLAUDE.md` works too — pi
  # accepts either name — but AGENTS.md is the one the family standardises on
  # and the one pi's own docs name first. `pi --verbose` names the context
  # files and skills it loaded.
  #
  # Besides `~/.pi/agent/skills` it reads `~/.agents/skills` unconditionally,
  # and it implements the Agent Skills standard, so it would find a haus skill
  # written anywhere in that set. Its own directory is still the one named here,
  # because that is the one this room can promise is haus's — `~/.agents/skills`
  # is a shared address several clients read and the user's own hand-wired
  # skills live in.
  home = {
    instructions = ".pi/agent/AGENTS.md";
    skills = ".pi/agent/skills";
  };

  # No bypass flag: pi's built-in tools carry no permission gate at all, so
  # there is nothing here to open. Its tools just run — which is why haus wires
  # a desktop guard extension into it (`files` below), and `haus-fix` sets
  # HAUS_DESKTOP_OK=1 for every client instead. Verified against pi 0.84.3's
  # `--help`, which lists `--` as an option, 2026-08-31.
  oneshot = [
    "pi"
    "--print"
    "--"
  ];

  scopeNote = "`settings.json`, `models.json` and `trust.json` are pi's own — haus merges a few keys into the first at rebuild and owns none of the three — and a host may wire individual skills or extensions as out-of-store symlinks";

  files = {
    # pi's half of the same thing — and of the LANE BANNERS, which is where
    # it stops resembling opencode's plugin (../opencode). pi has one seam, not two: no
    # hook file to append a second command to, so the one extension reports
    # state to `agent-state` AND hands `scruff hook notify` the same
    # Claude-shaped payload the Claude Code merge (../claude) wires four events
    # of. Everything downstream of those four event names — the lane
    # lookup, the fin key, the "Go to lane" action, the resolve — is
    # client-agnostic, so a pi lane's trill fin is the Claude path's, not a
    # second copy of it. The file's own header carries the event map and
    # the two pi-only banners (a failed compaction, a provider refusing the
    # session) that go through `haus-notify` instead, having nothing to
    # resolve them.
    #
    # NOT gated on pi being in `ai.clients`, unlike the settings merge
    # below: this file is inert without pi, so it costs a machine without
    # one nothing and hands a hand-installed pi a working pill and working
    # banners — the same reasoning as the Claude Code block, and the
    # opposite of `piSettings`, which seeds a list of npm sources to fetch
    # and so must not be written for a client that is not here.
    #
    # A `.ts` FILE and not a directory: pi discovers `extensions/*.ts`
    # (symlinks included — this one is a home-manager link into the store)
    # one level deep, so a bare file is the smallest thing that works and
    # cannot collide with a host that wires its own extension DIRECTORY
    # beside it. Three absolute /run/current-system paths, for the reason
    # the opencode plugin gives: an extension runs inside pi's own process,
    # which is given no PATH guarantees.
    ".pi/agent/extensions/haus-agent-state.ts".text =
      builtins.replaceStrings
        [ "@AGENT_STATE@" "@SCRUFF@" "@HAUS_NOTIFY@" ]
        [
          "/run/current-system/sw/bin/agent-state"
          "/run/current-system/sw/bin/scruff"
          "/run/current-system/sw/bin/haus-notify"
        ]
        (builtins.readFile ./agent-state.ts);

    # pi's half of the desktop guard — the thing that keeps an agent from
    # foregrounding an app, moving a window or redrawing the desktop while
    # somebody is typing into something else. Claude Code panes have had it
    # as a PreToolUse hook (the `agent-desktop-guard` merge in ../claude); pi had
    # NOTHING, because pi has no permission modes, no permission prompt and
    # no sandbox at all. `tool_call` is its seam: it fires before the tool,
    # it can block, and the handler may be async — so it can hold the turn
    # open while a human answers.
    #
    # It does NOT carry a second copy of the ruleset: it shells out to the
    # very same `agent-desktop-guard` binary, with the same hook-shaped JSON
    # on stdin and the same verdict back out, so the line falls in one place
    # for both clients and test/desktop-guard.bats pins it for both. That
    # matters more here than the indirection costs — the guard's whole value
    # is WHERE the line is, and both sides of it fail silently.
    #
    # The question goes up as a `trill ask`, racing pi's own in-pane dialog,
    # first definite answer wins. A Claude prompt can only be answered by
    # finding the pane; the reason a lane has its own window is that nobody
    # is watching it. Direct `trill`, not `haus-notify`, because haus-notify
    # is send-only and its no-trill fallback is Apple's banner, which has no
    # buttons — an ask has no such fallback, so the pane IS the fallback.
    #
    # Unconditional for the same reason the file above it is: inert without
    # pi, so a hand-installed pi gets the guard with nothing to configure —
    # PROVIDED the ai room is on, because `agent-desktop-guard` ships under
    # its `mkIf`. With `haus.ai.enable = false` the binary is absent, the
    # spawn fails, and the extension does what every other failure here does
    # and returns no opinion. That is the right direction (a machine that
    # asked for no AI room gets no gate rather than a broken one), and it is
    # the same shape agent-state.ts has with `agent-state`.
    # `HAUS_DESKTOP_OK=1` turns it off for a pane, exactly as it does for
    # Claude Code — one variable, both clients.
    ".pi/agent/extensions/haus-desktop-guard.ts".text =
      builtins.replaceStrings
        [ "@DESKTOP_GUARD@" "@TRILL@" ]
        [
          "/run/current-system/sw/bin/agent-desktop-guard"
          "/run/current-system/sw/bin/trill"
        ]
        (builtins.readFile ./desktop-guard.ts);
  };

  # pi — the same idea in pi's own settings file, and the same split every
  # merge here makes between "what makes this a haus lane" and "what is
  # yours". Two keys are RE-ASSERTED every rebuild, two are only SEEDED when
  # the file has no opinion yet, and the package list is UNIONED.
  #
  # Re-asserted, because they are how a lane looks rather than what you
  # think about it:
  #   tuiMode = "fullscreen"  — the alt-screen renderer, the same choice
  #     `.tui = "fullscreen"` makes for Claude Code (../claude), so two panes side
  #     by side are the same shape. Ghostty's ⇧-drag selection still reaches
  #     the alt-screen, so it costs nothing.
  #   quietStartup = true     — drop pi's startup header. A lane pane opens
  #     already knowing what it is; the statusline carries the rest.
  #
  # Seeded once, because they are taste and pi lets you change them from
  # `/settings` mid-session — a rebuild that reverted what you just chose
  # would be haus arguing with you:
  #   hideThinkingBlock       — thinking folded away by default.
  #   modelThinkingLevels     — think hard on the Anthropic models by
  #     default.
  #
  # Both are guarded on `has()` rather than merged, and the object one is
  # the reason why: `{ours} + (.yours // {})` looks like seed-once and
  # isn't. A level you CHANGED wins, but one you DELETED in `/settings`
  # comes back at the next rebuild — which is precisely the arguing this
  # split exists to avoid. `has()` asks the only question that separates
  # "never had an opinion" from "had one and dropped it".
  #
  # And `packages` is a union, never a set: `ai.pi.packages` is added beside
  # whatever `pi install` put there, so the file stays yours. The corollary
  # is in that option's docs — dropping an entry from the Nix list does not
  # uninstall it, because haus does not own this array and must not delete
  # from it.
  #
  # Gated on pi actually being installed (`onlyWhenInstalled`), unlike
  # ../claude's, which follows the room alone. The difference is what the two write: a
  # statusline path and some hooks help a hand-installed Claude Code and
  # cost a machine without one nothing, while this seeds a list of npm
  # sources — a settings file naming code to fetch, for a client that isn't
  # here, is litter with a sharp edge.
  settings = {
    name = "piSettings";
    onlyWhenInstalled = true;
    activation =
      {
        pkgs,
        lib,
        cfg,
      }:
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run sh -c '
          settings="$0"
          packages="$1"
          mkdir -p "''${settings%/*}"
          tmp="$settings.hm-seed"
          if [ -s "$settings" ]; then base="$settings"; else base="$tmp.base"; printf "{}" > "$base"; fi
          ${pkgs.jq}/bin/jq --argjson add "$packages" ".tuiMode = \"fullscreen\"
            | .quietStartup = true
            | (if has(\"hideThinkingBlock\") then . else .hideThinkingBlock = true end)
            | (if has(\"modelThinkingLevels\") then . else .modelThinkingLevels = {\"anthropic/claude-opus-5\": \"high\", \"anthropic/claude-fable-5\": \"high\", \"anthropic/claude-sonnet-5\": \"high\"} end)
            | .packages = ((.packages // []) + (\$add - (.packages // [])))" \
            "$base" > "$tmp" && mv "$tmp" "$settings"
          # Both, not just the base: when jq fails the `&& mv` short-circuits
          # and a half-written "$tmp" would otherwise sit beside the real
          # settings file forever, looking like something pi should read.
          #
          # 🚨 NO APOSTROPHE ANYWHERE IN THIS BLOCK, comments included. The
          # whole script is ONE single-quoted `sh -c` argument, so a lone
          # apostrophe in a COMMENT ends that argument early and every word
          # after it re-parses. Not a style nit — it is how this activation
          # died on 2026-08-27. The comment above used to read "beside pi"
          # plus an apostrophe plus "s real": the quote ended at pi, the two
          # arguments on the closing line were swallowed into the wreckage,
          # `$1` arrived empty, and `jq --argjson add` got an empty string.
          # jq exits 2 with "invalid JSON text passed to --argjson", which
          # aborts activation BEFORE /run/current-system moves — so the Mac
          # silently keeps its old generation and every later step never
          # runs. A comment written to explain a safety measure is what
          # broke the thing it explained.
          #
          # It built fine, too: the stray apostrophe happened to pair with
          # the one on the closing line, so the script stayed syntactically
          # valid while meaning something else entirely. Nothing catches
          # that but running it. Say "the real settings file", never
          # possessives, and keep every quoted word double-quoted.
          rm -f "$tmp" "$tmp.base"
        ' "$HOME/.pi/agent/settings.json" ${lib.escapeShellArg (builtins.toJSON cfg.pi.packages)}
      '';
  };
}

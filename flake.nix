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

    # The silver-mist theme (Catppuccin Mocha, whiskered). Rendered in a pure
    # derivation so themes rebuild with `darwin-rebuild`.
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
    # main branch. Gated off by default until perch's first release exists.
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

      # `nix run github:nebelhaus/nebelhaus#pounce`
      packages = nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-darwin" ] (system: {
        pounce = pounce.packages.${system}.default;
        trill = trill.packages.${system}.default;
        perch = perch.packages.${system}.default;
      });

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

# Zen's extensions, and the one theme that can only live inside one.
#
# Split out of hearth/default.nix rather than folded into it for the same reason
# theme/ports.nix is split out of theme: it's gated on its own option, and what
# it does is a different job from dropping a stylesheet. hearth themes Zen's
# CHROME (userChrome.css / userContent.css, per accent, in default.nix). This
# room is about what's installed in the browser and the one Nebelung port that
# has no file to drop.
#
# Deploying an extension goes through Firefox's ENTERPRISE POLICY file —
# `Zen/distribution/policies.json` — which is how an IT department reaches
# Firefox and the only mechanism that works without hand-editing a
# randomly-named profile. haus.roster deliberately cannot do this: its four
# sources are a cask, a brew, a nixpkgs package and the App Store, and a browser
# add-on is none of them.
#
# ---- the Stylus problem, which is the reason this file exists ----------------
#
# Zen's accent follows haus.theme.accent and always has. But that covers
# the browser's own UI: userContent.css is entirely `@-moz-document
# url-prefix("about:")` rules, so github.com and youtube.com are not in it. Real
# sites are styled by the Catppuccin userstyles, which are LESS compiled in the
# browser and therefore cannot be injected as CSS at all — they live inside the
# Stylus extension's storage, where each style carries its own `accentColor`
# select var, defaulting to mauve.
#
# So the accent could not reach the web, silently, no matter how many times you
# rebuilt. What CAN be done is stamp those vars in the bundle before you import
# it: nebelung ships the full matrix and leaves the choosing to the consumer, so
# a rebuild rewrites the accent AND the flavor to the ones you actually picked,
# out of the bundle rendered for your contrast. Importing is still a click —
# Stylus has no file interface, which is exactly why nebelung classes this port
# `manual` — but the file you import is now correct on all three axes, and the
# rice tells you when it changed instead of leaving you to notice a mauve
# YouTube months later.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  cfg = config.haus.zen;
  wanted = lib.filterAttrs (_: e: e.enable) cfg.extensions;
  stylusWanted = wanted ? stylus;
in
{
  # The roster pass places ports for roster apps the rice hasn't wired properly.
  # Once we stamp and announce the Stylus bundle we HAVE wired it, so claim it —
  # otherwise a `stylus` roster entry gets reported as an unhandled manual port
  # pointing at nebelung's accent-blind copy, which is now the wrong file.
  haus.theme.ports.handled = lib.optional stylusWanted "stylus";

  assertions = lib.mapAttrsToList (name: e: {
    assertion = e.id != null && e.url != "";
    message = ''
      haus.zen.extensions.${name} needs an `id` (and a `slug` or `url`).
      Firefox's policy engine matches the extension's OWN id, not its AMO slug,
      and a wrong or missing one installs nothing without an error — so the rice
      refuses to write a policy it can't tell you is correct. Read the id off
      about:debugging ▸ This Firefox with the add-on installed.
    '';
  }) wanted;

  home-manager.users.${username} =
    {
      lib,
      pkgs,
      osConfig,
      nebelung,
      ...
    }:
    let
      nb = import ../lib/nebelung.nix {
        inherit lib nebelung;
        theme = osConfig.haus.theme;
      };
      accent = osConfig.haus.theme.accent;
      flavor = osConfig.haus.theme.flavor;

      # The variant root, like every other port — nebelung renders one bundle
      # per CONTRAST now, and the flavor dirs symlink at their contrast twin,
      # so `<variant>/stylus/` resolves whichever variant you're on (nebelung#22).
      # It used to read the package root because that was the only copy there
      # was, which is what made contrast unable to reach the web at all.
      bundle = "${nb.root}/stylus/nebelung-stylus.json";

      # Both remaining axes are per-style SELECT VARS living in Stylus's own
      # storage — the bundle ships the full matrix and the consumer picks — so
      # stamping is choosing, not recolouring: set the var each style already
      # offers.
      #
      #   accentColor              theme.accent
      #   lightFlavor/darkFlavor   theme.flavor, BOTH set to the same value
      #
      # Both flavor vars deliberately get the same answer. A style picks between
      # them by the browser's colour scheme, and the rice has already decided
      # which one this machine is — a latte rice that still went dark whenever
      # the browser did would be following the browser, not theme.flavor.
      #
      # Guarded per var: entries with no vars at all (the bundle carries a
      # `settings` object beside the 134 styles) and values a style doesn't list
      # are passed through untouched rather than given something that resolves
      # to nothing.
      stylusBundle =
        # Named for the variant AND the accent, because the announcement below
        # compares store paths: every axis that changes what you'd import has to
        # change this name, or the nudge silently stops firing.
        pkgs.runCommand "${nb.variant}-stylus-${accent}.json"
          { nativeBuildInputs = [ pkgs.jq ]; }
          ''
            jq -c \
              --arg accent ${lib.escapeShellArg accent} \
              --arg flavor ${lib.escapeShellArg flavor} '
              def choose($var; $want):
                if (.usercssData.vars[$var].options // [] | map(.name) | index($want))
                then .usercssData.vars[$var].value = $want
                else .
                end;
              map(choose("accentColor"; $accent)
                  | choose("lightFlavor"; $flavor)
                  | choose("darkFlavor"; $flavor))
            ' ${bundle} > "$out"
          '';
    in
    {
      home.file =
        # The rice owns this file. `extraPolicies` last so a host can set the
        # rest of the policy surface — or override ExtensionSettings wholesale —
        # without taking the file back by hand.
        lib.optionalAttrs (wanted != { }) {
          "Library/Application Support/Zen/distribution/policies.json".text = builtins.toJSON {
            policies = {
              ExtensionSettings = lib.mapAttrs' (
                _: e:
                lib.nameValuePair e.id {
                  installation_mode = e.mode;
                  install_url = e.url;
                }
              ) wanted;
            }
            // osConfig.haus.zen.extraPolicies;
          };
        }
        # Placed under a FIXED name so the Stylus import dialog always points at
        # the same path, while the symlink underneath moves with the accent, the
        # flavor and the contrast — which is what the announcement below compares.
        // lib.optionalAttrs stylusWanted {
          ".config/nebelhaus/nebelung-stylus.json".source = stylusBundle;
        };

      # A one-time instruction, announced only when there's genuinely something
      # new to import — the stamped bundle's store path changes exactly when one
      # of the three axes or the palette does, so the last path we announced is
      # the whole state this needs. Printing it every rebuild is how a real
      # instruction turns into wallpaper.
      home.activation.stylusNebelung = lib.mkIf stylusWanted (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          stylusStamp="$HOME/.local/state/nebelhaus/stylus-announced"
          if [ "$(cat "$stylusStamp" 2>/dev/null || true)" != "${stylusBundle}" ]; then
            echo "→ Stylus (Zen): your userstyles are one import behind (${nb.variant}, ${accent})."
            echo "   Stylus ▸ Manage ▸ Import:  $HOME/.config/nebelhaus/nebelung-stylus.json"
            $DRY_RUN_CMD mkdir -p "$(dirname "$stylusStamp")"
            printf '%s\n' "${stylusBundle}" | $DRY_RUN_CMD tee "$stylusStamp" >/dev/null
          fi
        ''
      );
    };
}

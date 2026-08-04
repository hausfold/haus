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
# randomly-named profile. nebelhaus.roster deliberately cannot do this: its four
# sources are a cask, a brew, a nixpkgs package and the App Store, and a browser
# add-on is none of them.
#
# ---- the Stylus problem, which is the reason this file exists ----------------
#
# Zen's accent follows nebelhaus.theme.accent and always has. But that covers
# the browser's own UI: userContent.css is entirely `@-moz-document
# url-prefix("about:")` rules, so github.com and youtube.com are not in it. Real
# sites are styled by the Catppuccin userstyles, which are LESS compiled in the
# browser and therefore cannot be injected as CSS at all — they live inside the
# Stylus extension's storage, where each style carries its own `accentColor`
# select var, defaulting to mauve.
#
# So the accent could not reach the web, silently, no matter how many times you
# rebuilt. What CAN be done is stamp that var in the bundle before you import
# it: nebelung ships one accent-blind JSON, and a rebuild rewrites it to the
# accent you actually chose. Importing is still a click — Stylus has no file
# interface, which is exactly why nebelung classes this port `manual` — but the
# file you import is now correct, and the rice tells you when it changed
# instead of leaving you to notice a mauve YouTube months later.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  cfg = config.nebelhaus.zen;
  wanted = lib.filterAttrs (_: e: e.enable) cfg.extensions;
  stylusWanted = wanted ? stylus;
in
{
  # The roster pass places ports for roster apps the rice hasn't wired properly.
  # Once we stamp and announce the Stylus bundle we HAVE wired it, so claim it —
  # otherwise a `stylus` roster entry gets reported as an unhandled manual port
  # pointing at nebelung's accent-blind copy, which is now the wrong file.
  nebelhaus.theme.ports.handled = lib.optional stylusWanted "stylus";

  assertions = lib.mapAttrsToList (name: e: {
    assertion = e.id != null && e.url != "";
    message = ''
      nebelhaus.zen.extensions.${name} needs an `id` (and a `slug` or `url`).
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
      accent = osConfig.nebelhaus.theme.accent;

      # nebelung renders the Stylus bundle ONCE, at the package root — there is
      # no copy under high-contrast/ or latte/ the way every file-based port
      # has. So this follows theme.accent but NOT theme.flavor or
      # theme.contrast; a latte machine still imports mocha-derived styles.
      # Reading the root rather than modules/lib/nebelung.nix's variant root is
      # deliberate and load-bearing: the variant path simply doesn't exist here.
      bundle = "${nebelung.themes}/stylus/nebelung-stylus.json";

      # Every style keeps its full accent matrix, so stamping is choosing, not
      # recolouring: set the var each style already offers. Guarded twice —
      # entries with no accentColor at all (the bundle carries a `settings`
      # object beside the 134 styles) and accents a style doesn't list are
      # passed through untouched rather than given a value that resolves to
      # nothing.
      stylusBundle =
        pkgs.runCommand "nebelung-stylus-${accent}.json" { nativeBuildInputs = [ pkgs.jq ]; }
          ''
            jq -c --arg accent ${lib.escapeShellArg accent} '
              map(
                if (.usercssData.vars.accentColor.options // [] | map(.name) | index($accent))
                then .usercssData.vars.accentColor.value = $accent
                else .
                end
              )
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
            // osConfig.nebelhaus.zen.extraPolicies;
          };
        }
        # Placed under a FIXED name so the Stylus import dialog always points at
        # the same path, while the symlink underneath moves with the accent —
        # which is what the announcement below compares.
        // lib.optionalAttrs stylusWanted {
          ".config/nebelhaus/nebelung-stylus.json".source = stylusBundle;
        };

      # A one-time instruction, announced only when there's genuinely something
      # new to import — the stamped bundle's store path changes exactly when the
      # accent or the palette does, so the last path we announced is the whole
      # state this needs. Printing it every rebuild is how a real instruction
      # turns into wallpaper.
      home.activation.stylusNebelung = lib.mkIf stylusWanted (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          stylusStamp="$HOME/.local/state/nebelhaus/stylus-announced"
          if [ "$(cat "$stylusStamp" 2>/dev/null || true)" != "${stylusBundle}" ]; then
            echo "→ Stylus (Zen): your userstyles are a ${accent} import behind."
            echo "   Stylus ▸ Manage ▸ Import:  $HOME/.config/nebelhaus/nebelung-stylus.json"
            $DRY_RUN_CMD mkdir -p "$(dirname "$stylusStamp")"
            printf '%s\n' "${stylusBundle}" | $DRY_RUN_CMD tee "$stylusStamp" >/dev/null
          fi
        ''
      );
    };
}

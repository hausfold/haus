# Zen's extensions, and the one theme that can only live inside one.
#
# Split out of hearth/default.nix rather than folded into it for the same reason
# theme/ports.nix is split out of theme: it's gated on its own option, and what
# it does is a different job from dropping a stylesheet. hearth themes Zen's
# CHROME (userChrome.css / userContent.css, per accent, in default.nix). This
# room is about what's installed in the browser and the one Nebelung port that
# has no file to drop.
#
# Deploying an extension goes through Firefox's ENTERPRISE POLICIES, which is
# how an IT department reaches Firefox and the only mechanism that works without
# hand-editing a randomly-named profile. haus.roster deliberately cannot do
# this: its four sources are a cask, a brew, a nixpkgs package and the App
# Store, and a browser add-on is none of them.
#
# ---- why a root plist and not policies.json, which is the obvious file -------
#
# Firefox reads policies from THREE places, and only two of them are reachable
# here. `policies.json` is one of them — but the parent process resolves it
# under `XREAppDist`, which on macOS is `Zen.app/Contents/Resources/distribution/`
# and nowhere else (EnterprisePoliciesParent.sys.mjs, `readPoliciesFile`). The
# `~/Library/Application Support/Zen/distribution/policies.json` this room used
# to write was never read by anything: measured on a live profile,
# `browser.policies.applied` is absent from prefs.js and every row in
# extensions.json is `location=app-profile, source=amo`. Stylus only looked like
# it worked because it had been installed from AMO by hand.
#
# Writing INSIDE the bundle is the other reachable path and it is a trap twice
# over: it breaks Zen's code signature, and a cask upgrade replaces the app
# wholesale and takes the file with it.
#
# So: the third path, macOS managed preferences. Firefox's `macOSPoliciesParser`
# reads the app's own preference domain through NSUserDefaults, whose search
# list includes `/Library/Preferences/<bundle-id>.plist` — root-owned, outside
# the bundle, and the location Mozilla documents for a non-MDM deploy. Policy
# names sit at the TOP level of that plist beside `EnterprisePoliciesEnabled`,
# as real nested dicts (the parser also accepts `__`-flattened keys; we don't
# need them). The visible cost is that Zen then says "managed by your
# organization" in its menu, which is the honest description of what a rice
# doing this actually is.
#
# Root ownership is why this half of the room is a nix-darwin activation script
# and not a home-manager `home.file`: /Library/Preferences is not the user's to
# write. The Stylus bundle below stays in home-manager, where it belongs.
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

  # An extension the rice BUILT — the tab bridge — installs from a store path,
  # and nothing in /nix/store has ever been near Mozilla's signing service. An
  # `install_url` starting `file://` is exactly that case and the only case,
  # which is why the signing escape below is keyed on it rather than on any
  # particular extension: an AMO `https://` url is signed by definition.
  localInstall = lib.any (e: lib.hasPrefix "file://" e.url) (lib.attrValues wanted);

  # The rice owns this file. `extraPolicies` last so a host can set the rest of
  # the policy surface — or override ExtensionSettings wholesale — without
  # taking the file back by hand.
  policies =
    lib.optionalAttrs (wanted != { }) {
      ExtensionSettings = lib.mapAttrs' (
        _: e:
        lib.nameValuePair e.id {
          installation_mode = e.mode;
          install_url = e.url;
        }
      ) wanted;
    }
    // lib.optionalAttrs localInstall {
      # ---- the one pref that makes a self-built .xpi installable ------------
      #
      # Zen's own greprefs.js does ship `xpinstall.signatures.required = false`
      # — and it is NOT the last word, which is the trap. Application prefs load
      # after GRE prefs, and Zen carries Firefox's
      # `browser/defaults/preferences/firefox.js` unmodified, which sets the
      # same pref back to `true` (twice). Measured, not assumed: a policy
      # install of the bridge .xpi fails with
      #
      #   Policies: Download failed - ERROR_SIGNEDSTATE_REQUIRED - file:///nix/store/…
      #
      # while Stylus, coming from AMO signed, installs beside it. So the browser
      # ends up refusing precisely the add-on the rice is in a position to build.
      #
      # What makes this fixable rather than an AMO account is that Zen is built
      # with `MOZ_REQUIRE_SIGNING = false` (read out of its AppConstants). That
      # flag does two things at once: it makes `AddonSettings.REQUIRE_SIGNING`
      # follow the pref instead of being a compile-time constant, AND it is the
      # exact condition under which Firefox's Preferences policy adds
      # `xpinstall.signatures.required` to its allowlist. On a build where the
      # flag is on, this policy is silently dropped and the bridge simply
      # doesn't install — which is the honest outcome, since on such a build
      # nothing could have made it install.
      #
      # Locked, because a rice that installs an unsigned add-on and leaves the
      # switch flippable is telling the user a story about a state it does not
      # maintain. The narrowing is at the other end: this only appears at all
      # when something is being installed from the store, i.e. when
      # `haus.zen.tabBridge.enable` is on, which is off by default and documents
      # this as its cost.
      Preferences = {
        "xpinstall.signatures.required" = {
          Value = false;
          Status = "locked";
        };
      };
    }
    // cfg.extraPolicies;

  # A whole plist rather than a pile of `defaults write` calls: the policy
  # surface is nested dicts, `defaults` expresses those about as well as it
  # sounds, and rendering the file means activation can be a content compare.
  policyPlist = pkgs.writeText "zen-policies.plist" (
    lib.generators.toPlist { escape = true; } (
      {
        # The gate on the whole mechanism — without it Firefox never looks at
        # the domain at all, however many policies are in it.
        EnterprisePoliciesEnabled = true;
      }
      // policies
    )
  );

  policyPath = "/Library/Preferences/app.zen-browser.zen.plist";

  # Records that the plist at that path is OURS, so turning every policy off can
  # remove it again without a rice ever deleting a file it didn't write. Under
  # the held `nebelhaus` state dir, like perch's install marker beside it.
  policyMarker = "/Library/Application Support/nebelhaus/zen-policies.source";
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

  # ---- the policy file itself ------------------------------------------------
  #
  # Guarded rather than declared, in the same spirit as den's accessibility
  # writes: a rebuild that can't reach /Library/Preferences should degrade to
  # "the extension didn't arrive", not take the rest of activation — and every
  # launchd service after it — down with it.
  #
  # The cfprefsd nudge is the part not to remove. cfprefsd caches a parsed
  # domain in memory and does NOT reliably notice a plist edited underneath it,
  # so without this a freshly launched Zen can be served the previous policy
  # set for the rest of the login session. It fires only when the file actually
  # changed, so a no-op rebuild doesn't restart a system daemon, and it lands in
  # postActivation — after nix-darwin's own `defaults`/`userDefaults` blocks —
  # so it can't drop a write those made earlier in the same activation.
  system.activationScripts.postActivation.text =
    if policies == { } then
      ''
        # --- Zen: no policies left; take our plist back down ------------------
        if [ -e ${lib.escapeShellArg policyMarker} ]; then
          /bin/rm -f ${lib.escapeShellArg policyPath} ${lib.escapeShellArg policyMarker}
          /usr/bin/killall cfprefsd >/dev/null 2>&1 || true
          echo "zen: removed ${policyPath} (no haus.zen policies left) — restart Zen" >&2
        fi
      ''
    else
      ''
        # --- Zen: enterprise policies as a managed preference ------------------
        if ! /usr/bin/cmp -s ${policyPlist} ${lib.escapeShellArg policyPath}; then
          if /usr/bin/install -m 644 ${policyPlist} ${lib.escapeShellArg policyPath}; then
            /bin/mkdir -p "$(/usr/bin/dirname ${lib.escapeShellArg policyMarker})"
            /usr/bin/printf '%s' ${policyPlist} > ${lib.escapeShellArg policyMarker}
            /usr/bin/killall cfprefsd >/dev/null 2>&1 || true
            echo "zen: policies written to ${policyPath} — quit and reopen Zen to apply" >&2
          else
            echo "warning: zen: could not write ${policyPath}; extensions and policies were NOT deployed. Nothing else was affected." >&2
          fi
        fi
      '';

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
      # The policy file used to live here too, as
      # `Library/Application Support/Zen/distribution/policies.json`, where Zen
      # never read it (see the header). It's a root plist now; home-manager
      # removes the file it used to own on the next generation, so there's
      # nothing to clean up by hand.
      #
      # Placed under a FIXED name so the Stylus import dialog always points at
      # the same path, while the symlink underneath moves with the accent, the
      # flavor and the contrast — which is what the announcement below compares.
      home.file = lib.optionalAttrs stylusWanted {
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

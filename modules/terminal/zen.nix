# Zen's extensions, and the one theme that can only live inside one.
#
# Split out of terminal/default.nix rather than folded into it for the same reason
# theme/ports.nix is split out of theme: it's gated on its own option, and what
# it does is a different job from dropping a stylesheet. terminal themes Zen's
# CHROME (userChrome.css / userContent.css, per accent, in default.nix). This
# room is about what's installed in the browser.
#
# Deploying an extension goes through Firefox's ENTERPRISE POLICIES, which is
# how an IT department reaches Firefox and the only mechanism that works without
# hand-editing a randomly-named profile. haus.roster deliberately cannot do
# this: its four sources are a cask, a brew, a nixpkgs package and the App
# Store, and a browser add-on is none of them.
#
# ---- why a root plist and not policies.json, which is the obvious file -------
#
# On macOS Firefox reads policies from TWO places, and the obvious one is not
# the one you can write. `policies.json` is read from `XREAppDist` —
# `Zen.app/Contents/Resources/distribution/` and nowhere else
# (EnterprisePoliciesParent.sys.mjs, `readPoliciesFile`). So the
# `~/Library/Application Support/Zen/distribution/policies.json` this room used
# to write was never read by anything: measured on a live profile,
# `browser.policies.applied` is absent from prefs.js and every row in
# extensions.json is `location=app-profile, source=amo`. The add-on we were
# testing with only looked like it worked because it had been installed from
# AMO by hand. And writing the file
# where Firefox WOULD read it means writing inside the bundle, a trap twice
# over: it breaks Zen's code signature, and a cask upgrade replaces the app
# wholesale and takes the file with it.
#
# So: the other place, macOS managed preferences. Firefox's `macOSPoliciesParser`
# reads the app's own preference domain through NSUserDefaults, whose search
# list includes `/Library/Preferences/<bundle-id>.plist` — root-owned, outside
# the bundle, and the location Mozilla documents for a non-MDM deploy. Policy
# names sit at the TOP level of that plist beside `EnterprisePoliciesEnabled`,
# as real nested dicts (the parser also accepts `__`-flattened keys; we don't
# need them). The visible cost is that Zen then says "managed by your
# organization" in its menu, which is the honest description of what a rice
# doing this actually is.
#
# Root ownership is why this room is a nix-darwin activation script and not a
# home-manager `home.file`: /Library/Preferences is not the user's to write.
#
# ---- the web, which this room used to reach and no longer does --------------
#
# Zen's accent follows haus.theme.accent and always has, but that covers the
# browser's own UI: userContent.css is entirely `@-moz-document
# url-prefix("about:")` rules, so github.com and youtube.com are not in it. Real
# sites are styled by the Catppuccin userstyles, which are LESS source — they
# have to be compiled, which is why no palette file haus writes ever reached
# them on its own.
#
# This room used to answer that by stamping the accent, the flavor and the
# contrast into nebelung's bundle and telling you to import it into Stylus by
# hand. That path is retired (2026-08-20): `haus.zen.userStyles` compiles the
# styles you name straight into the profile's userContent.css instead — same
# three axes, no extension, no click, nothing to re-import on the next machine.
# It lives in terminal/default.nix and package-userstyles.nix. Stylus itself is
# still installable like any other add-on by naming its `id` and `slug` under
# `haus.zen.extensions`; haus just no longer ships a stamped bundle for it.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.haus.zen;
  wanted = lib.filterAttrs (_: e: e.enable) cfg.extensions;

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
      # while an AMO-signed add-on installs beside it. So the browser
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
      # maintain. The narrowing is at the other end: it appears only when
      # something is actually being installed from a local file. Today that is
      # `haus.zen.tabBridge.enable`, which is off by default and documents this
      # as its cost — but a host that points any `haus.zen.extensions.*.url` at
      # a `file://` path gets it too, which is why that option says so.
      Preferences = {
        "xpinstall.signatures.required" = {
          Value = false;
          Status = "locked";
        };
      };
    }
    # Shallow, deliberately: `extraPolicies` is the escape hatch, so a host
    # naming a top-level policy takes that policy over WHOLE — `ExtensionSettings`
    # and, now, `Preferences`. A host that wants its own prefs alongside the
    # signing escape has to restate it; the option says so, because the failure
    # is otherwise invisible (the bridge just stops installing).
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
  # the held `haus` state dir, like perch's install marker beside it.
  policyMarker = "/Library/Application Support/haus/zen-policies.source";
in
{
  assertions = lib.mapAttrsToList (name: e: {
    assertion = e.id != null && e.url != "";
    message = ''
      haus.zen.extensions.${name} needs an `id` (and a `slug` or `url`).
      Firefox's policy engine matches the extension's OWN id, not its AMO slug,
      and a wrong or missing one installs nothing without an error — so haus
      refuses to write a policy it can't tell you is correct. Read the id off
      about:debugging ▸ This Firefox with the add-on installed.
    '';
  }) wanted;

  # ---- the policy file itself ------------------------------------------------
  #
  # Guarded rather than declared, in the same spirit as core's accessibility
  # writes: a rebuild that can't reach /Library/Preferences should degrade to
  # "the extension didn't arrive" rather than abort activation. The whole block
  # is guarded, not just the install — a failed marker write would otherwise
  # take out everything postActivation still has to do, which by this point is
  # the /run/current-system symlink that makes the generation current.
  #
  # The cfprefsd nudge is the part not to remove. cfprefsd caches a parsed
  # domain in memory and does NOT reliably notice a plist edited underneath it,
  # so without this a freshly launched Zen can be served the previous policy set
  # for the rest of the login session. It fires only when the file actually
  # changed, so a no-op rebuild doesn't restart a system daemon.
  #
  # It is unscoped (every user's cfprefsd, not root's), and it runs LATE: by
  # postActivation, nix-darwin's `defaults`/`userDefaults` blocks and
  # home-manager's user activation — which sits at the very top of
  # postActivation — have already written their prefs. cfprefsd flushes on
  # SIGTERM, which is what makes that safe rather than lossy; don't swap this
  # for a SIGKILL, and don't "fix" the ordering by moving it earlier, which
  # would only mean re-caching the stale domain again straight afterwards.
  #
  # The marker is rewritten on the matched path too, not only after an install.
  # It is the sole record that the file is ours, so a marker lost to a restore
  # or a hand-`rm` would otherwise never come back — and the removal branch
  # below, which reads it, could then never fire.
  system.activationScripts.postActivation.text =
    if policies == { } then
      ''
        # --- Zen: no policies left; take our plist back down ------------------
        if [ -e ${lib.escapeShellArg policyMarker} ]; then
          if /bin/rm -f ${lib.escapeShellArg policyPath} ${lib.escapeShellArg policyMarker}; then
            /usr/bin/killall cfprefsd >/dev/null 2>&1 || true
            echo "zen: removed ${policyPath} (no haus.zen policies left) — restart Zen" >&2
          else
            echo "warning: zen: could not remove ${policyPath}; Zen stays managed until it goes. Nothing else was affected." >&2
          fi
        fi
      ''
    else
      ''
        # --- Zen: enterprise policies as a managed preference ------------------
        zenPolicyMark() {
          /bin/mkdir -p "$(/usr/bin/dirname ${lib.escapeShellArg policyMarker})" \
            && /usr/bin/printf '%s' ${lib.escapeShellArg policyPlist} > ${lib.escapeShellArg policyMarker}
        }
        if /usr/bin/cmp -s ${lib.escapeShellArg policyPlist} ${lib.escapeShellArg policyPath}; then
          zenPolicyMark || echo "warning: zen: could not record ${policyMarker}; turning every zen policy off will not remove ${policyPath}." >&2
        elif /usr/bin/install -m 644 ${lib.escapeShellArg policyPlist} ${lib.escapeShellArg policyPath}; then
          zenPolicyMark || echo "warning: zen: could not record ${policyMarker}; turning every zen policy off will not remove ${policyPath}." >&2
          /usr/bin/killall cfprefsd >/dev/null 2>&1 || true
          echo "zen: policies written to ${policyPath} — quit and reopen Zen to apply" >&2
        else
          echo "warning: zen: could not write ${policyPath}; extensions and policies were NOT deployed. Nothing else was affected." >&2
        fi
      '';
}

# The Zen tab bridge — the answer to "something is making noise and I can't find
# the tab" for the one browser family that refuses to be asked.
#
# ---- why an extension at all -------------------------------------------------
#
# macOS's now-playing session carries a title, an artist and a bundle id. It does
# not carry a URL, a tab, or a window. Safari and the Chromium browsers make up
# the difference by handing their tab list to AppleScript, so the media pill can
# look the tab up and switch to it. Firefox and its forks hand out nothing:
#
#   * no AppleScript dictionary at all;
#   * no accessibility tree either — measured against a live Zen, the tab strip
#     is absent even after forcing Firefox's a11y engine on with
#     AXEnhancedUserInterface, which leaves only the window title, and a window
#     title is only ever the FOREGROUND tab.
#
# What the pill did instead was drive Firefox's own address-bar `%` open-tab
# search with synthetic keystrokes. It works, and it is exactly as pleasant as it
# sounds. The only thing that can answer the question honestly is code running
# INSIDE the browser, so the rice ships some.
#
# ---- why this can be unsigned, which is the whole reason it's cheap ----------
#
# Release Firefox will not load an extension Mozilla hasn't signed, and no pref
# and no policy overrides that — shipping this for Firefox would mean an AMO
# account, unlisted self-distribution signing in CI, and a hosted .xpi. Zen is
# built the other way: `MOZ_REQUIRE_SIGNING = false` in its AppConstants, which
# is what demotes signature enforcement from a compile-time constant to a live
# pref. THAT flag is what makes this Zen-only, and the first thing to re-check
# if a Zen release ever behaves differently.
#
# It is NOT enough on its own, and the trap is worth stating because Zen looks
# like it already agrees: its greprefs.js does ship
# `xpinstall.signatures.required = false`. Application prefs load after GRE
# prefs, though, and Zen carries Firefox's own
# `browser/defaults/preferences/firefox.js`, which sets it back to `true`. So a
# policy install of this .xpi fails with `ERROR_SIGNEDSTATE_REQUIRED` unless
# something turns the pref off again — which is exactly what hearth/zen.nix
# does, via the Preferences policy, keyed on the `file://` install url this
# module asks for below. Read that file's `localInstall` comment before
# touching either half; they only work as a pair.
#
# ---- the two files, and why they land in different places -------------------
#
#   policies       /Library/Preferences/app.zen-browser.zen.plist  (root-owned)
#   host manifest  ~/Library/Application Support/Mozilla/NativeMessagingHosts/
#
# That asymmetry is real and worth not re-deriving: the policy domain is keyed
# on the APP's bundle id (Zen, Firefox, …), while native-messaging manifests are
# keyed on the VENDOR — and Zen's application.ini says `Vendor=Mozilla`. So one
# host manifest already serves Zen and stock Firefox both, and only the policy
# half would need a second copy if this ever grew past Zen.
#
# The policy half is a managed preference rather than the `policies.json` you'd
# expect, because Firefox only ever resolves that file INSIDE the app bundle —
# hearth/zen.nix's header carries the measurement and the reasoning.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  cfg = config.haus.zen.tabBridge;
  pkg = pkgs.callPackage ./package.nix { };

  # Fixed, because both ends hardcode them: the extension asks for the host by
  # name, and the host manifest names the extension back. They are a matched
  # pair — changing either alone silently produces a bridge that never connects.
  hostName = "co.hausfold.zentabs";
  extensionId = "zen-tabs@hausfold.co";
in
{
  config = lib.mkIf cfg.enable {
    # Deployed through the same policy file every other Zen extension goes
    # through, rather than a second mechanism beside it: haus.zen.extensions IS
    # the ExtensionSettings renderer, and an entry set here merges with whatever
    # the host asked for. `file://` is a documented install_url scheme, and the
    # store path changing on a rebuild is what makes Zen pick up a new build.
    haus.zen.extensions.tab-bridge = {
      id = extensionId;
      url = "file://${pkg.xpi}/zen-tabs.xpi";
      mode = "force_installed";
    };

    home-manager.users.${username} = {
      # `allowed_extensions` is the access control on the whole bridge: any
      # other add-on asking for this host by name is refused by the browser
      # before a single byte reaches the binary.
      home.file."Library/Application Support/Mozilla/NativeMessagingHosts/${hostName}.json".text =
        builtins.toJSON {
          name = hostName;
          description = "haus — publishes Zen's tabs to the bar";
          path = lib.getExe pkg.haustabs;
          type = "stdio";
          allowed_extensions = [ extensionId ];
        };
    };
  };
}

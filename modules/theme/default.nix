# Theme — the whole-desktop surface the per-tool palette wiring doesn't touch.
# The accent (haus.theme.accent) lives in options.nix and is consumed per-tool
# by terminal/bar/pounce; this room owns macOS's own Light/Dark appearance.
#
# The desktop picture used to live here too, as `haus.theme.wallpaper`. It moved
# to a room of its own (../wallpaper) when the generated `minimal` look landed:
# that desktop reads the palette, the accent, the tiling gaps and the flake's own
# lock edges, which is more than one enum on the theme can carry.
# ../renamed.nix keeps the old name working.
#
# haus.theme.systemAppearance defaults to "unmanaged" — nothing moves unless a
# host (or the bootstrap interview) opts in — and is applied with osascript for
# the reason spelled out in the block that applies it.
{
  config,
  lib,
  username,
  ...
}:

let
  panes = import ../lib/settings-panes.nix;
  # ---- macOS Light/Dark (haus.theme.systemAppearance) ------------------
  appearanceChoice = config.haus.theme.systemAppearance;
  # "flavor" resolves here rather than in the activation script so the built
  # system carries the ANSWER, not the rule — one less thing to be wrong at 3am
  # in a shell fragment.
  appearanceWanted =
    if appearanceChoice == "flavor" then
      (if config.haus.theme.flavor == "latte" then "light" else "dark")
    else
      appearanceChoice;
in
{
  config = lib.mkMerge [
    # The nebelung ports that a file on disk cannot finish. A theme file only
    # makes a theme ACTIVE for an app that reads a fixed path; the rest need
    # picking in the app's own preferences once, and that is invisible — it
    # looks like the theme simply did not work.
    #
    # One card for all of them rather than one each, because the list is a
    # runtime fact: `ports.nix` writes it into the report as it places files,
    # and `detail` is what lets a build-time card name a runtime list.
    (lib.mkIf config.haus.theme.ports.enable {
      haus._contrib.permissions.theme-nebelung-ports = {
        order = 80;
        title = "Theme — the ports that need a click";
        why = ''
          Some apps only read their theme from their own settings, so haus put
          the file where they look and cannot choose it for them. One pick each,
          once.
        '';
        cost = "those apps stay on their stock colours while everything around them is themed";
        applies = ''grep -qE '^(step|manual)' "$HOME/.config/haus/nebelung-ports.tsv" 2>/dev/null'';
        # Nothing measures this: the answer lives inside each app's own
        # preferences, in as many formats as there are apps.
        detail = ''
          awk -F'\t' '$1 == "step" || $1 == "manual" { print $2 " — " $3 }' \
            "$HOME/.config/haus/nebelung-ports.tsv" 2>/dev/null
        '';
      };
    })

    # The appearance switch's card in core's manual-click deck. Contributed only
    # when this machine actually drives System Events — Automation is the one
    # grant with no readable state at all, so a card offered speculatively could
    # never go green and would sit in the deck forever.
    (lib.mkIf (appearanceChoice != "unmanaged") {
      haus._contrib.permissions.theme-automation = {
        order = 70;
        title = "Automation — System Events";
        why = ''
          Light and Dark is the one macOS setting with no writable key: the
          preference domain behind it is a mirror, not a lever, so a rebuild
          flips it by asking System Events to. macOS calls one app driving
          another Automation.
        '';
        cost = "the rebuild still succeeds and your Mac silently stays the appearance it was";
        # No check, and deliberately none: every API that reports an Automation
        # grant asks for it first, and a permission dialog fired by `haus
        # doctor` is how people learn to stop running `haus doctor`.
        pane = panes.automation;
        steps = [
          "Find the app you rebuild from, then turn on System Events beneath it"
          "The row only exists once something has asked — if it is not there, rebuild once and come back"
        ];
      };
    })

    (lib.mkIf (appearanceChoice != "unmanaged") {
      home-manager.users.${username} =
        { lib, pkgs, ... }:
        let
          # Same derivation core installs system-wide; asking for it again is
          # free (identical inputs → identical store path) and keeps this room
          # from depending on core's let-block.
          hausax = pkgs.callPackage ../core/package-hausax.nix { };
        in
        {
          # macOS appearance is NOT a `defaults` key you can write, however much
          # it looks like one. Measured on macOS 26.6, 2026-08-08:
          # `defaults write -g AppleInterfaceStyle Dark` from a light session and
          # `defaults delete -g AppleInterfaceStyle` from a dark one BOTH change
          # nothing — before or after `activateSettings -u`, and not even for a
          # process launched fresh afterwards, with no
          # AppleInterfaceThemeChangedNotification posted either time. The key is
          # a mirror the appearance system writes on its way past, not a lever.
          # That is why this is an activation script and not a
          # `system.defaults.NSGlobalDomain` entry — and why
          # modules/lib/restart-map.nix has no restart to offer for it: there is
          # no write to make live. (`haus diff` warns if a host declares that key
          # by hand, the same way it warns about com.apple.Accessibility.)
          #
          # System Events flips it live in ~0.3s and posts the notification, so
          # running apps repaint. Two guards:
          #
          #   - Read hausax FIRST and skip when it already matches. Without this
          #     every rebuild re-posts the appearance-changed notification and
          #     every running app repaints for nothing.
          #   - Driving System Events needs an Automation grant for whichever app
          #     runs the rebuild. Refusal must degrade to "the appearance didn't
          #     move", never abort activation and take every launchd service with
          #     it — the same failure shape core's FDA-guarded accessibility block
          #     exists to avoid.
          home.activation.hausSystemAppearance = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            appearanceHave="$(${hausax}/bin/hausax 2>/dev/null | ${pkgs.jq}/bin/jq -r '.appearance // empty' || true)"
            if [ "$appearanceHave" = "${appearanceWanted}" ]; then
              verboseEcho "system appearance: already ${appearanceWanted}"
            elif run /usr/bin/osascript -e \
                 'tell application "System Events" to tell appearance preferences to set dark mode to ${
                   lib.boolToString (appearanceWanted == "dark")
                 }'; then
              echo "system appearance: ${appearanceWanted}" >&2
            else
              echo "warning: could not set macOS appearance to ${appearanceWanted} — System Events needs an Automation grant for the app running this rebuild (System Settings ▸ Privacy & Security ▸ Automation). Appearance left as-is; nothing else was affected." >&2
            fi
          '';
        };
    })
  ];
}

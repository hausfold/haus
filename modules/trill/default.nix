# trill — the nebelhaus Messages client, installed through Nix (the `trill` flake
# input's overlay puts `pkgs.trill` in scope) instead of a Homebrew cask, so it
# rides the same flake-lock chain as the rest of the family. The flake wraps
# trill's CI-built, Developer-ID-signed, notarized release .app (macOS 26 blocks a
# from-source Nix build — see the trill repo), so `pkgs.trill` is that exact
# bundle in the store.
#
# trill is a normal windowed app, not a daemon like pounce, so there's no launch
# agent — it just needs to exist somewhere Spotlight/Launchpad can find it. But a
# Nix store path is not that place: Full Disk Access (trill reads
# ~/Library/Messages/chat.db, always read-only) is granted per app *path*, and a
# store path changes on every version bump, which would drop the grant. So copy
# the bundle to a FIXED /Applications/Trill.app on activation (the same path the
# old cask used, so an existing grant carries over), re-copying only when the
# store path actually changes. No re-sign dance: the release .app is already
# Developer-ID signed, and an FDA grant keyed to that stable identity + path
# survives rebuilds. `ditto` preserves the signature + notarization staple.
#
# Theming rides trill's RUNTIME palettes (trill's DesignSystem/RicePalette.swift):
# every rendered nebelung variant is dropped in ~/.config/trill/themes/, and
# ~/.config/trill/config.json names the dark/light pair theme.{flavor,contrast}
# selects. trill's own settings live in UserDefaults, which Nix has no business
# writing — the config file exists exactly so this module can set a default the
# app's Settings ▸ Theme can still override.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

lib.mkIf config.nebelhaus.trill.enable {
  # All home-manager wiring in ONE block — a dynamic attr key (${username}) can't
  # be merged across multiple statements. Passed as a module FUNCTION so it gets
  # the overlaid `pkgs` and the `nebelung` input.
  home-manager.users.${username} =
    { nebelung, ... }:
    let
      # theme.{flavor,contrast} resolved to the selected nebelung variant, the
      # same way hearth/sill/theme/pounce do it.
      nb = import ../lib/nebelung.nix {
        inherit lib nebelung;
        theme = config.nebelhaus.theme;
      };
      followAppearance = config.nebelhaus.trill.followSystemAppearance;
      # Every rendered variant, not just the selected one, so a palette picked in
      # trill's Settings can be any of them without a rebuild — and because a
      # file SHADOWS trill's compiled-in variant of the same name, this is also
      # how a nebelung palette bump reaches an installed trill.app that hasn't
      # been rebuilt. `or { }` on an older nebelung lock that predates the
      # output: no files, and trill falls back to its compiled-in nebelung.
      themeFiles = lib.mapAttrs' (
        variant: palette:
        lib.nameValuePair "trill/themes/${variant}.json" {
          text = builtins.toJSON palette;
        }
      ) (nebelung.palettes or { });
    in
    {
      xdg.configFile = themeFiles // {
        # The default palette per polarity. trill's appearance preference
        # (Follow macOS / Dark / Light) picks which one applies, so PINNING a
        # flavor is expressed by writing the same variant to both keys — then
        # whichever polarity the app resolves, the palette is the same. An older
        # trill that predates runtime palettes ignores this file entirely.
        "trill/config.json".text = builtins.toJSON {
          themeDark = if followAppearance then nb.darkVariant else nb.variant;
          themeLight = if followAppearance then nb.lightVariant else nb.variant;
        };
      };
    };

  system.activationScripts.postActivation.text = ''
    # --- trill: install the notarized app at a fixed /Applications path -------
    trillStore="${pkgs.trill}/Applications/Trill.app"
    trillDest="/Applications/Trill.app"
    trillMarker="/Library/Application Support/nebelhaus/trill.installed-from"
    if [ "$(/bin/cat "$trillMarker" 2>/dev/null)" != "${pkgs.trill}" ]; then
      echo "trill: installing ${pkgs.trill} → $trillDest" >&2
      if /usr/bin/ditto "$trillStore" "$trillDest.new"; then
        /bin/rm -rf "$trillDest"
        /bin/mv "$trillDest.new" "$trillDest"
        /bin/mkdir -p "$(/usr/bin/dirname "$trillMarker")"
        /usr/bin/printf '%s' "${pkgs.trill}" > "$trillMarker"
      else
        echo "trill: ditto failed; leaving any existing $trillDest in place" >&2
        /bin/rm -rf "$trillDest.new"
      fi
    fi
  '';
}

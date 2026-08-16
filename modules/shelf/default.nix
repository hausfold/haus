# Shelf — Perch, the haus notch file shelf, installed through Nix (the `perch` flake
# input's overlay puts `pkgs.perch` in scope) instead of a Homebrew cask, so it
# rides the same flake-lock chain as the rest of the family. The flake wraps
# perch's CI-built, Developer-ID-signed, notarized release .app (macOS 26 blocks a
# from-source Nix build — see the perch repo), so `pkgs.perch` is that exact
# bundle in the store.
#
# perch is a normal windowed app, not a daemon like pounce, so there's no launch
# agent — it just needs to exist somewhere Spotlight/Launchpad can find it. But a
# Nix store path is not that place: any permissions the shelf is granted are keyed
# per app *path*, and a store path changes on every version bump, which would drop
# the grant. So copy the bundle to a FIXED /Applications/Perch.app on activation
# (the same path a cask would use, so an existing grant carries over), re-copying
# only when the store path actually changes. No re-sign dance: the release .app is
# already Developer-ID signed, and a grant keyed to that stable identity + path
# survives rebuilds. `ditto` preserves the signature + notarization staple.
#
# On by default: nix/release.nix in the perch repo pins a real notarized
# release, so `pkgs.perch` is a shipping app rather than a placeholder.
#
# Theming rides perch's RUNTIME palettes (perch's UI/Theme/RicePalette.swift):
# every rendered nebelung variant is dropped in ~/.config/perch/themes/, and
# ~/.config/perch/config.json names the dark/light pair theme.{flavor,contrast}
# selects, plus the theme.accent perch emphasises with. perch has no theme or
# accent picker of its own, so this file is the whole story for its colors.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

lib.mkIf config.haus.shelf.enable {
  # The bundle is copied to a fixed /Applications path by this module's
  # activation step (see the header on why the path must be fixed), so
  # `installedBy` is the only honest source field.
  haus.roster.perch = {
    name = lib.mkDefault "Perch";
    installedBy = lib.mkDefault "haus.shelf";
  };

  # All home-manager wiring in ONE block — a dynamic attr key (${username}) can't
  # be merged across multiple statements. Passed as a module FUNCTION so it gets
  # the overlaid `pkgs`, the `nebelung` input, and home-manager's extended lib
  # (`lib.hm.dag` — the outer nix-darwin `lib` has no `hm`).
  home-manager.users.${username} =
    {
      lib,
      nebelung,
      pkgs,
      ...
    }:
    let
      # theme.{flavor,contrast} resolved to the selected nebelung variant, the
      # same way terminal/bar/theme/pounce do it.
      nb = import ../lib/nebelung.nix {
        inherit lib nebelung;
        theme = config.haus.theme;
      };
      followAppearance = config.haus.shelf.followSystemAppearance;

      # The palette per polarity. Perch picks between them by the macOS
      # appearance, so PINNING a flavor is expressed by writing the same variant
      # to both keys. An older perch that predates theming ignores this file.
      #
      # `accent` is a catppuccin ROLE NAME, not a hex: perch resolves it against
      # whichever half of the pair is in force, so one key is the right hue in
      # both polarities and follows a flavor change on its own. A perch that
      # predates the key ignores it and keeps accenting with its mark green.
      configJSON = pkgs.writeText "perch-config.json" (
        builtins.toJSON {
          themeDark = if followAppearance then nb.darkVariant else nb.variant;
          themeLight = if followAppearance then nb.lightVariant else nb.variant;
          accent = config.haus.theme.accent;
        }
      );

      # Every rendered variant, not just the selected one — a file SHADOWS
      # perch's compiled-in variant of the same name, so this is how a nebelung
      # palette bump reaches an installed Perch.app that hasn't been rebuilt.
      # Perch reads seven of the twenty-three roles and ignores the rest, so the
      # files go out verbatim. `or { }` on an older nebelung lock that predates
      # the output: no files, and perch falls back to its compiled-in nebelung.
      themeDrop = pkgs.runCommand "perch-theme" { } ''
        mkdir -p $out/themes
        cp ${configJSON} $out/config.json
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            variant: palette:
            "cp ${pkgs.writeText "perch-${variant}.json" (builtins.toJSON palette)} $out/themes/${variant}.json"
          ) (nebelung.palettes or { })
        )}
      '';
    in
    {
      # REAL FILES, not the xdg.configFile symlinks every other room here uses:
      # perch is app-sandboxed and reaches ~/.config/perch through a read-only
      # home-relative temporary exception. The sandbox resolves a symlink before
      # it checks the path, so a link into /nix/store reads as a store access and
      # is denied — the shelf would silently sit on compiled-in nebelung and the
      # rice's theme would never show. A few KB of copies keeps perch's sandbox
      # exception at exactly one directory, which is the point of the exception.
      home.activation.perchTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run /bin/mkdir -p "$HOME/.config/perch/themes"
        run /usr/bin/install -m 0644 ${themeDrop}/config.json "$HOME/.config/perch/config.json"
        # Replace the drop wholesale so a variant nebelung stopped rendering
        # doesn't linger as a stale palette a config.json could still name.
        run /bin/rm -f "$HOME"/.config/perch/themes/*.json
        for palette in ${themeDrop}/themes/*.json; do
          [ -e "$palette" ] || continue
          run /usr/bin/install -m 0644 "$palette" "$HOME/.config/perch/themes/"
        done
      '';
    };

  # ---- give the shelf the top edge back --------------------------------------
  # The Dock arms a top-screen-edge trigger for the whole duration of ANY drag
  # session — files included, not just windows despite the key's name — and
  # entering that band throws you into Mission Control. That band is precisely
  # where perch's notch catch zone lives, so overshooting the notch by a few
  # points hands the drag to the Dock and the shelf never sees a draggingEntered.
  # Perch cannot defend itself here: the Dock's edge monitor sits above every
  # window level, and intercepting it would need a CGEventTap (Accessibility
  # permission), which perch deliberately refuses to ask for.
  #
  # So the shelf only works if this is off. Not an opinion and therefore not
  # mkDefault — same footing as _HIHideMenuBar tracking bar.enable in core: it's
  # a function of running perch, and it comes back the moment perch is disabled.
  # This is the "Drag windows to top of screen to enter Mission Control" toggle
  # in System Settings ▸ Desktop & Dock; CustomUserPreferences because
  # nix-darwin's typed dock block has no option for it. The Dock restart at the
  # end of activation (core sets system.defaults.dock.*) picks it up.
  system.defaults.CustomUserPreferences."com.apple.dock".enterMissionControlByTopWindowDrag = false;

  system.activationScripts.postActivation.text = ''
    # --- perch: install the notarized app at a fixed /Applications path -------
    perchStore="${pkgs.perch}/Applications/Perch.app"
    perchDest="/Applications/Perch.app"
    perchMarker="/Library/Application Support/haus/perch.installed-from"
    if [ "$(/bin/cat "$perchMarker" 2>/dev/null)" != "${pkgs.perch}" ]; then
      echo "perch: installing ${pkgs.perch} → $perchDest" >&2
      if /usr/bin/ditto "$perchStore" "$perchDest.new"; then
        /bin/rm -rf "$perchDest"
        /bin/mv "$perchDest.new" "$perchDest"
        /bin/mkdir -p "$(/usr/bin/dirname "$perchMarker")"
        /usr/bin/printf '%s' "${pkgs.perch}" > "$perchMarker"
      else
        echo "perch: ditto failed; leaving any existing $perchDest in place" >&2
        /bin/rm -rf "$perchDest.new"
      fi
    fi
  '';
}

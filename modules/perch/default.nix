# perch — the nebelhaus notch file shelf, installed through Nix (the `perch` flake
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
# Off by default until perch's first release exists (nix/release.nix is a
# bootstrap placeholder until then); flip nebelhaus.perch.enable = true once
# `bench release perch` has cut a real v<date> tag.
{
  config,
  lib,
  pkgs,
  ...
}:

lib.mkIf config.nebelhaus.perch.enable {
  system.activationScripts.postActivation.text = ''
    # --- perch: install the notarized app at a fixed /Applications path -------
    perchStore="${pkgs.perch}/Applications/Perch.app"
    perchDest="/Applications/Perch.app"
    perchMarker="/Library/Application Support/nebelhaus/perch.installed-from"
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

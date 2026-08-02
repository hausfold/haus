# Apps — the one list of what this machine has.
#
# `nebelhaus.apps` is a keyed, composable roster (declared in ../options.nix
# next to the other cross-room options). This module does the two things that
# turn it from a description into the machine:
#
#   1. NORMALIZE — resolve the attrset into `nebelhaus._apps` (enabled entries,
#      in `order`) and `nebelhaus._launchers` (the subset with a leader key).
#      prowl renders the keymap from those, sill the pills, pounce the
#      cheatsheet; one resolution, so the three can't disagree.
#   2. INSTALL — hand each entry's `cask` / `brew` / `package` / `appStoreId` to
#      the right package manager.
#
# Why installing lives HERE and not in prowl, where it started: a roster entry
# that only wants to exist on disk — a font, a CLI tool, an app you never launch
# by keyboard — has nothing to do with tiling, and gating its install on
# `prowl.enable` meant turning the window manager off silently uninstalled
# things. Normalization moved along with it for the same reason: sill and pounce
# read the resolved list too, and neither should need the tiler evaluated to get
# it. prowl keeps exactly what is prowl's: aerospace.toml.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  namedEntries = lib.mapAttrsToList (id: app: { inherit id app; }) (
    lib.filterAttrs (_: app: app.enable) config.nebelhaus.apps
  );
  orderedNamedEntries = lib.sort (
    a: b: a.app.order < b.app.order || (a.app.order == b.app.order && a.id < b.id)
  ) namedEntries;
  apps = map (entry: entry.app) orderedNamedEntries;

  launchers = lib.filter (a: a.key != null) apps;
  launcherKeys = map (a: a.key) launchers;
  duplicateKeys = lib.unique (
    lib.filter (key: lib.count (candidate: candidate == key) launcherKeys > 1) launcherKeys
  );

  # A leader key with nothing to open. `open -a` needs the macOS application
  # name, and there is no sane fallback: the roster id is the user's to choose
  # and is routinely not the app's name (`notion-calendar` → "Notion Calendar").
  # Caught here rather than at launch time, where it's a keypress that silently
  # does nothing.
  keyedWithoutName = map (e: e.id) (
    lib.filter (e: e.app.key != null && e.app.name == null) orderedNamedEntries
  );

  # Entries whose only content is metadata — no source, nothing to launch, no
  # key. Almost always a typo'd field rather than an intention, and the entry
  # does nothing at all, so say so once instead of leaving it inert.
  emptyEntries = map (e: e.id) (
    lib.filter (
      e:
      e.app.key == null
      && e.app.workspace == null
      && e.app.cask == null
      && e.app.brew == null
      && e.app.package == null
      && e.app.appStoreId == null
    ) orderedNamedEntries
  );

  rosterCasks = lib.filter (c: c != null) (map (a: a.cask) apps);
  rosterBrews = lib.filter (b: b != null) (map (a: a.brew) apps);
  packagesFor = scope: map (a: a.package) (lib.filter (a: a.package != null && a.scope == scope) apps);

  # App Store entries, as "<id> <name>" pairs for the activation loop. `mas` is
  # den's (it installs it unconditionally); this just drives it.
  appStoreEntries = lib.filter (e: e.app.appStoreId != null) orderedNamedEntries;
  appStoreCmds = lib.concatMapStrings (
    e:
    let
      id = toString e.app.appStoreId;
      label = if e.app.name != null then e.app.name else e.id;
    in
    ''
      if ! ${pkgs.mas}/bin/mas list 2>/dev/null | /usr/bin/grep -qE "^ *${id} "; then
        echo "apps: fetching ${label} (${id}) from the Mac App Store…" >&2
        ${pkgs.mas}/bin/mas get ${id} >&2 || \
          echo "apps: could NOT install ${label} (${id}). If it is a paid app, buy it once in App Store.app (mas cannot purchase); if you are signed out, sign in there too. Skipping." >&2
      fi
    ''
  ) appStoreEntries;
in
{
  # One resolved view for prowl, sill, pounce and the theme ports.
  nebelhaus._apps = apps;
  nebelhaus._launchers = launchers;

  assertions = [
    {
      assertion = duplicateKeys == [ ];
      message = "nebelhaus app leader keys must be unique; duplicated: ${lib.concatStringsSep ", " duplicateKeys}";
    }
    {
      assertion = keyedWithoutName == [ ];
      message =
        "nebelhaus.apps entries with a leader `key` must also set `name` (the macOS "
        + "application name `open -a` is given); missing on: "
        + lib.concatStringsSep ", " keyedWithoutName;
    }
  ];

  warnings = lib.optional (emptyEntries != [ ]) (
    "nebelhaus.apps entries declare nothing to install and nothing to launch (no key, "
    + "workspace, cask, brew, package or appStoreId), so they have no effect: "
    + lib.concatStringsSep ", " emptyEntries
  );

  # Declaring an app is what installs it. These merge with whatever den, prowl
  # and sill declare and with the plain `homebrew.*` lists a host still has.
  homebrew.casks = rosterCasks;
  homebrew.brews = rosterBrews;

  environment.systemPackages = packagesFor "system";
  home-manager.users.${username}.home.packages = packagesFor "user";

  # The App Store, at last declaratively — for the half of it that can be.
  # Deliberately not `homebrew.masApps`: that path runs `mas install` under
  # `brew bundle` as the invoking user, and since macOS 13 App Store installs
  # require root, so mas stops for a password prompt with no terminal to draw it
  # in and the rebuild hangs. postActivation is ALREADY root, so `mas get`
  # neither prompts nor wedges. Failures are reported and stepped over — an app
  # you haven't bought must not be able to fail a rebuild.
  system.activationScripts.postActivation.text =
    lib.optionalString (config.nebelhaus.appStore.install && appStoreEntries != [ ]) ''
      # --- apps: Mac App Store (nebelhaus.appStore.install) --------------------
      ${appStoreCmds}
    '';
}

# Roster — the one list of what this machine has.
#
# `nebelhaus.roster` is a keyed, composable map (declared in ../options.nix
# next to the other cross-room options). This module does the two things that
# turn it from a description into the machine:
#
#   1. NORMALIZE — resolve the attrset into `nebelhaus._roster` (enabled entries,
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
#
# The rice's OWN apps are entries too — den declares ghostty's cask here, prowl
# aerospace's, sill sketchybar's, trill/pounce/perch their bundles. That's what
# makes this list complete rather than "the apps the host happened to add", and
# it's what removes the trap it replaces: a host used to have to KNOW that the
# rice already installs Ghostty and Trill, and write `cask = null` plus a comment
# saying so. Now the field is already filled in by whoever installs it, the host
# just adds a key, and `installedBy` answers "who put this here" in the data
# instead of in a comment.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  namedEntries = lib.mapAttrsToList (id: app: { inherit id app; }) (
    lib.filterAttrs (_: app: app.enable) config.nebelhaus.roster
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
      && e.app.installedBy == null
    ) orderedNamedEntries
  );

  rosterCasks = lib.filter (c: c != null) (map (a: a.cask) apps);
  rosterBrews = lib.filter (b: b != null) (map (a: a.brew) apps);
  packagesFor = scope: map (a: a.package) (lib.filter (a: a.package != null && a.scope == scope) apps);

  # ---- installed twice, silently ------------------------------------------
  # Homebrew list options concatenate and `brew bundle` is idempotent, so naming
  # the same cask from two places has never produced an error — it produces two
  # copies of the truth and no warning. (Real case that motivated this: a pounce
  # -generated `homebrew.casks = [ "iina" ]` alongside hearth's `pkgs.iina`, so
  # IINA sat in BOTH /Applications and ~/Applications/Home Manager Apps.)
  #
  # Reading the FINAL merged lists is what makes this catch the interesting
  # case: not just two roster entries naming one cask, but a roster entry and a
  # raw `homebrew.casks` line somewhere else in the config. A roster id can never
  # collide with itself — same id merges — so anything counted twice here is two
  # different declarations of one thing.
  #
  # Read `.name`, not the element: nix-darwin's homebrew.casks/brews are
  # `coercedTo str` submodules, so by the time they're merged a plain "slack" has
  # become { name = "slack"; args = null; … } and comparing elements directly
  # both fails to coerce and would miss `{ name = "slack"; greedy = true; }` as a
  # duplicate of the bare string.
  nameOf = x: if lib.isAttrs x then x.name else x;
  duplicatesIn =
    what: xs:
    let
      names = map nameOf xs;
    in
    map (x: "${what} `${x}`") (
      lib.unique (lib.filter (x: lib.count (y: y == x) names > 1) names)
    );
  duplicateSources = duplicatesIn "cask" config.homebrew.casks ++ duplicatesIn "formula" config.homebrew.brews;

  # The same app from two DIFFERENT package managers — a cask and a nixpkgs
  # build of the same thing. Undetectable by name (`iina` the cask vs
  # `pkgs.iina`), so this only catches it within one entry, where it's
  # unambiguous: two sources on one roster line is always a mistake.
  multiSourceEntries = map (e: e.id) (
    lib.filter (
      e:
      lib.count (x: x) [
        (e.app.cask != null)
        (e.app.brew != null)
        (e.app.package != null)
        (e.app.appStoreId != null)
      ] > 1
    ) orderedNamedEntries
  );

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
  nebelhaus._roster = apps;
  nebelhaus._launchers = launchers;

  assertions = [
    {
      assertion = duplicateKeys == [ ];
      message = "nebelhaus app leader keys must be unique; duplicated: ${lib.concatStringsSep ", " duplicateKeys}";
    }
    {
      assertion = keyedWithoutName == [ ];
      message =
        "nebelhaus.roster entries with a leader `key` must also set `name` (the macOS "
        + "application name `open -a` is given); missing on: "
        + lib.concatStringsSep ", " keyedWithoutName;
    }
    {
      # An error, not a warning: unlike two declarations of one cask (which
      # Homebrew survives), two sources on ONE entry has no defensible reading —
      # it would install the same app twice, from two package managers, into two
      # places, and there is no way to guess which one was meant.
      assertion = multiSourceEntries == [ ];
      message =
        "nebelhaus.roster entries name more than one install source (cask / brew / "
        + "package / appStoreId); pick one per entry: "
        + lib.concatStringsSep ", " multiSourceEntries;
    }
  ];

  warnings =
    lib.optional (emptyEntries != [ ]) (
      "nebelhaus.roster entries declare nothing to install and nothing to launch (no key, "
      + "workspace, cask, brew, package, appStoreId or installedBy), so they have no effect: "
      + lib.concatStringsSep ", " emptyEntries
    )
    ++ lib.optional (duplicateSources != [ ]) (
      "declared twice, so it installs twice and nothing errors: "
      + lib.concatStringsSep ", " duplicateSources
      + ". Something names these outside nebelhaus.roster — a raw homebrew.casks/brews line, "
      + "or an old pounce-generated module under hosts/<host>/packages/. Move it into the "
      + "roster (one entry, one source) and delete the other."
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

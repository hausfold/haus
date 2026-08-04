# writing — a pack for a Mac that reads and writes rather than compiles.
#
# A PACK, not a preset. Same data-only rule (`checkRice` runs over this file too),
# but it deliberately touches ONE option family: `nebelhaus.roster`. A preset
# answers "what kind of machine is this"; a pack answers "what's on it". So a
# pack composes with any preset and with any other pack, and none of them have to
# know about each other:
#
#   extraModules = [
#     nebelhaus.presets.everyday      # a Mac for someone who doesn't write code
#     nebelhaus.presets.large-print   # …that you can read
#     nebelhaus.packs.writing         # …with these four apps on it
#   ];
#
# Declaring an app in the roster is what installs it, so this file is both the
# app list and the install instruction. Nothing here is nebelhaus-specific
# beyond the option names — it's four casks and the keys to reach them.
#
# ---- what's deliberately missing, and why -----------------------------------
#
# `appId` is null on every entry. It is the bundle id AeroSpace matches on to
# herd a window to its workspace, and there is no way to know one without the
# app in front of you: it isn't in the Homebrew cask metadata, and guessing
# ("md.obsidian") produces a rule that silently never matches — the worst
# failure this repo keeps finding. So the pack ships what it can verify and
# leaves the one field it can't.
#
# What null costs you is ONLY auto-assignment. The leader key opens the app, the
# workspace exists, its pill is drawn, the cheatsheet lists it — the window just
# opens where you are instead of being moved. To close the gap once the app is
# installed, in your own host file:
#
#   nebelhaus.roster.obsidian.appId = "…";   # osascript -e 'id of app "Obsidian"'
#
# A plain assignment — and it stays plain for the fields this file DOES set, too.
# `packs.writing` reaches you through `nebelhaus.lib.pack`, which lowers every
# field here to `mkDefault` on the way in, so your host outranks it per field
# while the rest of the entry survives. Import order still carries no priority in
# the module system; the SEAM does. This same file imported as a bare path gets
# none of that and conflicts the old way.
#
# So a letter of yours that clashes with one below is one line, no `mkForce`:
#
#   nebelhaus.roster.zotero.key = "y";   # or null, for ⌘Space only
#
# See bite 2 in packs/README.md for the whole rule, including the two cases that
# still stop the build: two PACKS naming one app, and two roster entries in the
# same layer claiming one letter.
#
# ---- all four sources, including the one that used to be missing -------------
#
# A pack can install from Homebrew (`cask`, `brew`), the App Store
# (`appStoreId`) and Nixpkgs — that last one by NAMING the package instead of
# evaluating it:
#
#   ripgrep = { packageName = "ripgrep"; };   # pkgs.ripgrep, with no `pkgs` here
#
# `roster.*.package` itself stays out of reach and always will: it takes a
# derivation, and a data-only file has no arguments to get one from. That gap
# was real while this pack was written — all four apps below are casks, which is
# the right source for these four anyway — and `packageName` is what a pack of
# Nixpkgs command-line tools would be written with today.
{
  nebelhaus.roster = {
    # The notes app, and the one that earns a workspace: it's the thing you leave
    # open all day and come back to, which is what a workspace is for.
    obsidian = {
      key = "o"; # leader, then o
      name = "Obsidian";
      workspace = "O";
      barIcon = ":obsidian:";
      cask = "obsidian";
    };

    # Reference manager. A workspace of its own because a PDF you're reading and
    # the note you're writing about it want to be two places you switch between,
    # not two windows you hunt for.
    #
    # "l" for library. Both better letters were already taken, which is the
    # honest experience of writing a pack and worth recording rather than hiding:
    #   "z" — a BUILT-IN leader action (reopen the last closed app). The rice used
    #         to accept this collision and emit two `z =` bindings into one
    #         AeroSpace table, keeping whichever it parsed last; it refuses at
    #         eval now, which is the assertion this pack paid for.
    #   "b" — Zen, a roster entry the rice already ships. That one always failed
    #         loudly (roster keys must be unique), which is how it should feel.
    zotero = {
      key = "l";
      name = "Zotero";
      workspace = "L";
      barIcon = ":zotero:";
      cask = "zotero";
    };

    # Launcher key but no workspace: you open it, do a session, and close it. A
    # workspace would be an empty pill in the bar most of the day.
    anki = {
      key = "k";
      name = "Anki";
      barIcon = ":anki:";
      cask = "anki";
    };

    # Install-only: no key, no workspace. It's a library you visit occasionally,
    # and the roster is happy to hold something it merely installs — that's what
    # `key = null` is for.
    calibre = {
      name = "calibre";
      cask = "calibre";
    };
  };
}

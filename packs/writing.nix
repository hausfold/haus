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
# installed, in your own host file (which is imported after this and wins):
#
#   nebelhaus.roster.obsidian.appId = "…";   # osascript -e 'id of app "Obsidian"'
#
# The same override is how you resolve a KEY collision. If a letter here is one
# your own roster already uses, the build fails loudly (roster keys must be
# unique) — which is the right outcome, and the fix is one line:
#
#   nebelhaus.roster.zotero.key = "y";       # or null, to reach it from ⌘Space
#
# ---- and one real limit of the format ---------------------------------------
#
# A pack can install from Homebrew (`cask`, `brew`) and the App Store
# (`appStoreId`) but NOT from Nixpkgs, because `roster.*.package` is typed as a
# package and reaching `pkgs` is exactly what data-only forbids. Same limit the
# rice already hit on `fonts.mono.package`. It doesn't bite here — all four of
# these are casks — but a pack of Nixpkgs tools is not expressible today, and
# that's worth knowing before you plan one.
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

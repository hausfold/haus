# writing — a saved app collection for a Mac that reads and writes rather than
# compiles. The Apps room owns it, and one line turns it on:
#
#   haus.apps.packs.writing.enable = true;
#
# A COLLECTION is a data-only file that touches ONE option family,
# `haus.roster`. It used to be a top-level concept stacked beside a whole rice;
# it is something the Apps room OFFERS now (`docs/model.md`, "What a desktop
# is"), because "what's on this machine" is the
# question that room already answers, and a saved collection is not a peer of a
# room or a desktop.
#
# The FORMAT is no longer public. `haus.lib.pack` imported this same shape from
# a stranger and was retired on 2026-08-17, along with `checkPack`, `checkRice`
# and `haus.packFiles`: a stranger's app collection is a ROOM now, which leaves
# exactly two shareable formats — a desktop (data haus can prove is inert) and a
# room (code it cannot). So this file is the Apps room's own data, and the rules
# below are the room's, not a published contract.
#
# Declaring an app in the roster is what installs it, so this file is both the
# app list and the install instruction. Nothing here is desktop-specific
# beyond the option names — it's four casks and the keys to reach them.
#
# ---- what's deliberately missing, and why -----------------------------------
#
# `appId` is null on every entry. It is the bundle id AeroSpace matches on to
# herd a window to its workspace, and there is no way to know one without the
# app in front of you: it isn't in the Homebrew cask metadata, and guessing
# ("md.obsidian") produces a rule that silently never matches — the worst
# failure this repo keeps finding. So the collection ships what it can verify
# and leaves the one field it can't.
#
# What null costs you is ONLY auto-assignment. The leader key opens the app, the
# workspace exists, its pill is drawn, the cheatsheet lists it — the window just
# opens where you are instead of being moved. To close the gap once the app is
# installed, in your own host file:
#
#   haus.roster.obsidian.appId = "…";   # osascript -e 'id of app "Obsidian"'
#
# A plain assignment — and it stays plain for the fields this file DOES set, too.
# Every field here arrives at `mkDefault`, so your host outranks it PER FIELD
# while the rest of the entry survives. Import order still carries no priority in
# the module system; the switch does.
#
# So a letter of yours that clashes with one below is one line, no `mkForce`:
#
#   haus.roster.zotero.key = "y";   # or null, for ⌘Space only
#
# One thing still stops the build, and should: two roster entries in the same
# layer claiming one letter. (Two COLLECTIONS naming one app used to be the
# other, back when a stranger could publish one; both files are this repo's now,
# so that collision is a code review rather than a build failure.)
#
# ---- all four sources, including the one that used to be missing -------------
#
# A collection can install from Homebrew (`cask`, `brew`), the App Store
# (`appStoreId`) and Nixpkgs — that last one by NAMING the package instead of
# evaluating it:
#
#   ripgrep = { packageName = "ripgrep"; };   # pkgs.ripgrep, with no `pkgs` here
#
# `roster.*.package` itself stays out of reach and always will: it takes a
# derivation, and a data-only file has no arguments to get one from. That gap
# was real while this file was written — all four apps below are casks, which is
# the right source for these four anyway — and `packageName` is what a collection
# of Nixpkgs command-line tools would be written with today.
{
  haus.roster = {
    # The notes app, and the one that earns a workspace: it's the thing you leave
    # open all day and come back to, which is what a workspace is for.
    obsidian = {
      key = "o"; # leader, then o
      name = "Obsidian";
      cask = "obsidian";
    };

    # Reference manager. A workspace of its own because a PDF you're reading and
    # the note you're writing about it want to be two places you switch between,
    # not two windows you hunt for.
    #
    # "l" for library. Both better letters were already taken, which is the
    # honest experience of writing a collection and worth recording rather than
    # hiding:
    #   "z" — a BUILT-IN leader action (reopen the last closed app). The rice used
    #         to accept this collision and emit two `z =` bindings into one
    #         AeroSpace table, keeping whichever it parsed last; it refuses at
    #         eval now, which is the assertion this collection paid for.
    #   "b" — Zen, a roster entry the rice already ships. That one always failed
    #         loudly (roster keys must be unique), which is how it should feel.
    zotero = {
      key = "l";
      name = "Zotero";
      cask = "zotero";
    };

    # Launcher key but no workspace: you open it, do a session, and close it. A
    # workspace would be an empty pill in the bar most of the day.
    anki = {
      key = "k";
      name = "Anki";
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

  # ---- what's ALSO deliberately missing ------------------------------------
  #
  # WORKSPACE ownership moved off the roster entry entirely (a workspace names
  # its own members now, not the other way round), so this file can no longer
  # give Obsidian or Zotero one — the room only carries `haus.roster` through,
  # lowered to `mkDefault` on the way in. Give them one in your own host file
  # instead:
  #
  #   haus.workspaces.O = { key = "o"; icon = ":obsidian:"; apps = [ "obsidian" ]; };
  #   haus.workspaces.L = { key = "l"; icon = ":zotero:"; apps = [ "zotero" ]; };
  #
  # Letting a collection claim a workspace id the way it claims a roster id is a
  # real gap this migration surfaced, not a design choice — `packEntries` would
  # need to grow the same per-leaf-mkDefault treatment for `haus.workspaces` that
  # `haus.roster` already gets, and `apps` specifically would need list-merge
  # rather than mkDefault (see that option's own docs for why). Left for a
  # follow-up.
}

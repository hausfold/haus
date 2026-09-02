# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# apps' options — the picks haus makes for you. One knob per pick: turn it
# off and haus installs nothing, leaving that job to you (or to a roster
# entry of your own).
{ lib, ... }:

{
  options.haus.apps = {
    # ---- GUI editors ------------------------------------------------------
    # A GUI editor pick is a roster cask, same shape as the writing pack's
    # apps — not `haus.terminal.editorName`, which is the CLOSED set haus
    # actually installs itself with no cask involved (helix/neovim/vim/nano).
    # A cask here is what lets `haus.homebrew.adopt` do its job: pick VS Code
    # when you already have it some other way, and activation adopts the
    # existing app instead of installing a second copy.
    #
    # Turning one of these on installs the app; it does NOT touch
    # `haus.terminal.editor` ($EDITOR/$VISUAL and every "open in an editor"
    # action) — set that yourself, or let the installer's GUI-editor prompt
    # set both together.
    vscode = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Install Visual Studio Code as the roster entry `vscode` (cask
          `visual-studio-code`). Already have it installed some other way?
          `haus.homebrew.adopt` (on by default) adopts it instead of
          installing a second copy.
        '';
      };
    };

    cursor = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Install Cursor as the roster entry `cursor` (cask `cursor`).
          Already have it installed some other way? `haus.homebrew.adopt`
          (on by default) adopts it instead of installing a second copy.
        '';
      };
    };

    zed = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Install Zed as the roster entry `zed` (cask `zed`). Already have it
          installed some other way? `haus.homebrew.adopt` (on by default)
          adopts it instead of installing a second copy.
        '';
      };
    };

    # ---- packs ----------------------------------------------------------
    # A saved app collection, named. `pack` used to be a top-level concept a
    # consumer stacked beside a whole desktop; it is something this room offers
    # now, because "what's on this machine" is the question the Apps room
    # already answers (`docs/model.md`).
    #
    # One switch per shipped pack rather than a list of names: the switch is
    # then an ordinary desktop-safe boolean the registry can classify, the
    # options reference documents each collection where a person will look for
    # it, and a typo is an unknown-option error instead of a silently ignored
    # string. It is also the only route: `haus.lib.pack` let a stranger publish
    # the same shape and was retired on 2026-08-17, leaving a desktop and a room
    # as the two shareable formats.
    packs.writing.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Install the **writing** collection: Obsidian, Zotero, Anki and calibre —
        a Mac that reads and writes rather than compiles.

        These arrive as ordinary roster entries at `mkDefault`, so anything you
        say about one of them in your own host file wins per FIELD and the rest
        of the entry survives:

          haus.roster.zotero.key = "y";      # a letter of your own
          haus.roster.obsidian.appId = "…";  # osascript -e 'id of app "Obsidian"'

        Two of them claim a leader letter (`o`, `l`, `k`) and none claims a
        workspace — a workspace names its own members, so give one to Obsidian
        in your host with `haus.workspaces`. The file is
        `modules/apps/packs/writing.nix`, and it is readable data: four casks
        and the keys to reach them.
      '';
    };
  };
}

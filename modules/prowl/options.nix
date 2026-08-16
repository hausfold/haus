# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# prowl's options — tiling + the leader launcher. WHICH keys drive them is
# haus.keys.* in modules/options.nix: cross-cutting, because `leader` and
# `windowNav` are prowl's while `palette` is pounce's, and one table has to resolve
# all three so a chord and the caption documenting it can't drift.
{ lib, ... }:

{
  options.haus = {
    # den + hearth are the floor and have no switch (system, shell). Of the
    # rooms you can SEE, all six have one — prowl, sill, pounce, perch, hush,
    # collar — and turning one off drops its packages, agents and config
    # entirely. (The cross-cutting modules — apps, displays, roster, secrets,
    # theme, wallpaper, workspaces — have no room switch either; they aren't
    # rooms. And `full`/bootstrap deliberately expose only sill+prowl+pounce+
    # tour as the install-time choice, which is a narrower surface than this,
    # not a different list.)
    #
    # collar is NOT always on: haus.collar.enable is real and documented
    # (modules/collar/options.nix). This comment used to say it was, and that is
    # where "Touch ID for sudo can't be removed" got into the docs — caught by
    # hausfold.co#23's fact-check pass. Don't put it back.
    prowl.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        AeroSpace tiling window management + the leader-key launcher.

        This is the room switch: off drops AeroSpace, its launch agent, the
        wake-time window re-sort and the key remap entirely. To keep the tiler but
        leave the keyboard alone, use haus.keys.leader = "none" and
        haus.keys.windowNav = "none" instead of turning the room off.
      '';
    };

    prowl.numberedWorkspaces = lib.mkOption {
      type = lib.types.ints.between 0 10;
      default = 4;
      example = 6;
      description = ''
        How many numbered workspaces exist, on top of whatever
        haus.workspaces names. Four is the house default; the ceiling is ten
        because the leader reaches them by DIGIT and there are only ten
        digits: 1-9 in order, then `0` for the tenth, the same wrap a
        browser's tab shortcuts use.

        Each one gets three leader bindings (the digit focuses it, ⇧+the digit
        throws the focused window there and follows, ⌥⇧+the digit throws
        without following), a bar pill, and a `persistent-workspace` entry, so
        the workspace exists whether or not a window is on it.

        `0` is legal and means no numbered workspaces at all: a machine where
        every workspace is a NAMED one out of haus.workspaces. Raising the
        count never renames an existing workspace, so windows stay where they
        are. Lowering it takes the digit AND the bar pill, so whatever was on
        the workspaces that went is reachable only through the launcher's ⌘⇥
        window switcher until you raise the count again.

        The digits are reserved in launch mode, so a haus.workspaces key or a
        haus.keys.leaderExtras key that collides with one is refused at eval.
        This count decides which digits that means.

        Only meaningful with haus.prowl.enable.
      '';
    };

    prowl.defaultLayout = lib.mkOption {
      type = lib.types.enum [
        "tiles"
        "accordion"
      ];
      default = "tiles";
      description = ''
        What a fresh workspace does with the windows on it.

        "tiles" divides the space between them, which is what most people mean
        by a tiling window manager. "accordion" stacks them and gives the
        focused one the room, leaving a sliver of its neighbours showing:
        closer to how a browser's tabs behave, and easier on a laptop display
        where a third split stops being readable.

        A default, not a lock. The layout chords still switch the current
        workspace either way, whichever modifier haus.keys.windowNav puts them
        on.

        Only meaningful with haus.prowl.enable.
      '';
    };

    prowl.defaultOrientation = lib.mkOption {
      type = lib.types.enum [
        "auto"
        "horizontal"
        "vertical"
      ];
      default = "auto";
      description = ''
        Which way a fresh workspace's first split runs.

        "auto" decides per monitor from its shape — side by side on a wide
        screen, stacked on a tall one — which is right almost always and is
        why it is the default. The other two are for a machine that should
        split the same way whatever display it wakes up on.

        Only meaningful with haus.prowl.enable.
      '';
    };

    prowl.accordionPadding = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 80;
      example = 30;
      description = ''
        How much room an accordion layout leaves for the windows either side
        of the focused one, in points. Bigger means a narrower focused window
        with more of the stack peeking out; `0` hides the neighbours
        completely, which makes an accordion workspace look like a fullscreen
        one.

        Only read while a workspace is in the accordion layout, whether it got
        there from haus.prowl.defaultLayout or from the layout chord.

        Only meaningful with haus.prowl.enable.
      '';
    };

    prowl.mouseFollowsFocus = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Move the pointer to whatever keyboard focus just landed on.

        Off by default, because it moves something you did not move. On a
        multi-monitor desk it is the setting that answers "I focused that
        window and my cursor is still on the other screen".

        Both halves are lazy: the pointer is left alone whenever it is already
        inside the window (or on the monitor) that took focus, so it moves on
        the jumps that lose it and not on the ones that don't.

        Only meaningful with haus.prowl.enable.
      '';
    };
  };
}

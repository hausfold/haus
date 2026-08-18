# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# windows's options — tiling + the leader launcher. WHICH keys drive them is
# haus.keys.* in modules/options.nix: cross-cutting, because `leader` and
# `windowNav` are windows's while `palette` is pounce's, and one table has to resolve
# all three so a chord and the caption documenting it can't drift.
{ lib, ... }:

{
  options.haus = {
    # core + terminal are the floor and have no switch (system, shell). Of the
    # rooms you can SEE, all six have one — windows, bar, pounce, perch, focus,
    # security — and turning one off drops its packages, agents and config
    # entirely. (The cross-cutting modules — apps, displays, roster, secrets,
    # theme, wallpaper, workspaces — have no room switch either; they aren't
    # rooms. And `full`/bootstrap deliberately expose only bar+windows+pounce+
    # tour as the install-time choice, which is a narrower surface than this,
    # not a different list.)
    #
    # security is NOT always on: haus.security.touchId.enable is real and documented
    # (modules/security/options.nix). This comment used to say it was, and that is
    # where "Touch ID for sudo can't be removed" got into the docs — caught by
    # hausfold.co#23's fact-check pass. Don't put it back.
    windows.enable = lib.mkOption {
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

    windows.numberedWorkspaces = lib.mkOption {
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

        Only meaningful with haus.windows.enable.
      '';
    };

    windows.defaultLayout = lib.mkOption {
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

        Only meaningful with haus.windows.enable.
      '';
    };

    windows.mouseFullscreen = lib.mkOption {
      type = lib.types.enum [
        "right"
        "left"
        "none"
      ];
      default = "none";
      example = "right";
      description = ''
        Zoom the window **under the pointer** with a modifier + a click.

        The keyboard's `<mod>f` can only ever reach the window you are already
        in; this is its pointer twin, so zooming a window on the other monitor
        is one gesture rather than focus-then-zoom. It is the same AeroSpace
        `fullscreen` either way — a toggle, so the same click puts it back —
        and the click focuses the window on its way in.

        The modifier is NOT separately settable: it follows
        `haus.keys.windowNav`, so `<mod>f` and `<mod>`+click are one
        vocabulary and a machine that moved the modifier for its keyboard
        layout moves the mouse chord with it. `windowNav = "none"` therefore
        leaves nothing to hold, and an assertion refuses the pair rather than
        letting a bare click be bound — a modifier-less chord would swallow
        every click on the machine.

        Which button, and why the default is the right one: **the click is
        consumed over every app**, so this spends a gesture machine-wide.
        `"right"` is ⌥ + right-click, the quietest of the three rather than a
        free one: macOS uses ⌥ as the ALTERNATE-contextual-menu modifier, so
        inside a Finder window it is what turns "Copy X" into "Copy X as
        Pathname", and an app that reads ⌥ + right-DRAG (a 3D viewport zoom)
        loses that too, since the mouse-down is swallowed before the drag
        starts. The desktop passes through, so only in-window menus are
        affected. `"left"`
        is ⌥ + left-click, which costs considerably more — multi-cursor in GUI editors,
        ⌥-click-a-link to download, ⌥-click on a menu extra, and every ⌥-drag
        (the mouse-down is swallowed, so the drag never begins) — offered
        because on some mice the right button is the awkward one, not because
        it is a peer of `"right"`. There is deliberately no ctrl option:
        ctrl+click IS macOS's secondary click, so binding it would cost
        context menus everywhere.

        Clicking the desktop passes through untouched, and anything drawn
        above ordinary windows — the menu bar, the Dock, the bar — is
        transparent to the chord rather than being "clicked".

        Carried by pounce's event tap (AeroSpace has no mouse bindings at all,
        and Ghostty's keybind triggers are keys), so it needs
        haus.launcher.enable and the Accessibility grant pounce already asks
        for; an assertion catches the first, and without the second the click
        simply keeps its stock meaning.

        Only meaningful with haus.windows.enable.
      '';
    };

    windows.defaultOrientation = lib.mkOption {
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

        Only meaningful with haus.windows.enable.
      '';
    };

    windows.accordionPadding = lib.mkOption {
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
        there from haus.windows.defaultLayout or from the layout chord.

        Only meaningful with haus.windows.enable.
      '';
    };

    windows.mouseFollowsFocus = lib.mkOption {
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

        Only meaningful with haus.windows.enable.
      '';
    };
  };
}

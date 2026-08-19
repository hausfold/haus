# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# windows's options — tiling + the leader launcher. WHICH keys drive them is
# haus.keys.* in modules/options.nix: cross-cutting, because `leader` and
# `windowNav` are windows's while `palette` is pounce's, and one table has to resolve
# all three so a chord and the caption documenting it can't drift.
{ lib, ... }:

let
  # ---- the logout note, and where it comes from ------------------------------
  # `haus.windows.stageManager.*`, `.nativeTiling.*` and `.desktop.*` all write
  # `com.apple.WindowManager`, which macOS reads at login and offers no way to
  # re-read. That fact lives in ../lib/restart-map.nix as the `logout` verb, and
  # the SENTENCE about it lives in ../lib/login-map.nix — one paragraph per
  # domain, interpolated below rather than written twelve times.
  #
  # This is the whole reason the group is shippable. §5.6 refused it while the
  # only place the wait was stated was the machine (activation's announcement,
  # `haus plan`); saying it at the option, before anyone builds anything, is what
  # turns "it silently didn't work" into "it lands next login", and generating it
  # from the verb is what stops the twelve copies from drifting apart.
  loginMap = import ../lib/login-map.nix { inherit lib; };
  windowManagerDomain = "com.apple.WindowManager";
  windowManagerKeys = import ./window-manager-keys.nix;

  # Every option in the group has the same shape — nullOr bool, null means write
  # nothing — so the only per-option content is its prose and which plist key it
  # is FOR. Taking the key here is what lets ./window-manager-keys.nix be checked
  # in both directions: an option naming a key the table doesn't have is refused
  # right here, and a table entry with no option is caught in ./default.nix.
  mkWindowManagerOption =
    {
      key,
      description,
    }:
    if !(windowManagerKeys ? ${key}) then
      throw ''
        haus.windows: an option declares the plist key `${key}`, which
        ./window-manager-keys.nix does not carry — so nothing would ever write it.

        That table is what ./default.nix walks to build the
        system.defaults.WindowManager block. Add the key there (with the option
        path) and the write follows.
      ''
    else
      lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = true;
        description = ''
          ${description}

          null (the default) writes nothing at all, which is not the same as
          "off": these are settings people have usually already made by hand,
          and a rebuild that named one it didn't care about would silently
          overwrite a choice. Turning an option back to null STOPS writing, it
          does not restore — macOS keeps no memory of what the value was.

          ${loginMap.note windowManagerDomain}
        '';
      };
in

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

    # ---- macOS's OWN window features (com.apple.WindowManager) ---------------
    # §5.6's "Windows" row, and the last of its ten groups to be built. It was
    # deliberately unbuilt for a year on one ground: this domain has no
    # live-reload path on macOS 26, so every option here lands in the plist and
    # changes nothing until the next login, and "a curated group that silently
    # needs a logout is worse than no group". `../lib/login-map.nix` is what
    # removed the word SILENTLY — every description below carries its paragraph,
    # generated from the same `logout` verb in `../lib/restart-map.nix` that
    # makes activation announce it and `haus plan` report it. One fact, three
    # renderings, no hand copy.
    #
    # It lives in the windows room and NOT in core with the other macOS-settings
    # groups, because this is the one settings group that interlocks with what
    # the room does: Stage Manager and native edge-drag tiling are macOS's own
    # answer to the question AeroSpace answers, so a machine that runs both has
    # two window managers fighting over the same windows. That is the whole
    # reason the roadmap wrote "must interlock with windows" beside this row.
    # Every option is null-by-default like every other §5.6 group, so the room
    # still imposes nothing; what it adds is one warning when the two collide
    # (see ./default.nix), which core could not have written.
    #
    # Independent of `windows.enable` on purpose. Turning the TILER off is a
    # perfectly good reason to want macOS's own tiling turned on, and gating
    # these behind the room switch would make the two mutually exclusive in
    # exactly the case where you want the other one.
    windows.stageManager = {
      enable = mkWindowManagerOption {
        key = "GloballyEnabled";
        description = ''
          macOS's Stage Manager: recent windows are swept into a strip down the
          side of the screen, one app in the middle at a time.

          Turning this on while `haus.windows.enable` is also on gives you two
          window managers with different ideas about where a window belongs —
          AeroSpace tiles it, Stage Manager pulls it back to the strip. haus
          warns about the pair rather than refusing it, because "Stage Manager
          on the laptop display, tiling on the external" is a real way to work,
          but if windows will not stay where the tiler puts them this is the
          first thing to turn off.
        '';
      };
      autoHideStrip = mkWindowManagerOption {
        key = "AutoHide";
        description = ''
          Hide the strip of recent apps until the pointer goes near it, instead
          of keeping it on screen. Only does anything while Stage Manager is on.

          The setting that buys back the width Stage Manager costs you on a
          laptop display.
        '';
      };
      groupWindows = mkWindowManagerOption {
        key = "AppWindowGroupingBehavior";
        description = ''
          When you click an app in the strip, whether Stage Manager brings ALL
          of that app's windows forward together (true) or one at a time
          (false). macOS spells these "All at once" and "One at a time".

          True is what you want for an app you keep several windows of and read
          side by side; false keeps the middle of the screen to a single window,
          which is the point of Stage Manager for most people.
        '';
      };
      hideDesktopIcons = mkWindowManagerOption {
        key = "HideDesktop";
        description = ''
          Hide the icons on your desktop while Stage Manager is on. The
          Stage-Manager-only twin of `haus.windows.desktop.hideIcons`, which
          hides them always.
        '';
      };
      hideWidgets = mkWindowManagerOption {
        key = "StageManagerHideWidgets";
        description = ''
          Hide desktop widgets while Stage Manager is on. The
          Stage-Manager-only twin of `haus.windows.desktop.hideWidgets`.
        '';
      };
    };

    windows.nativeTiling = {
      edgeDrag = mkWindowManagerOption {
        key = "EnableTilingByEdgeDrag";
        description = ''
          Drag a window to the side of the screen and macOS tiles it there.
          On (macOS's own default) unless you say otherwise.

          THE ONE TO TURN OFF IF YOU TILE. With `haus.windows.enable` on,
          AeroSpace already owns where windows go, and this is the setting that
          makes a window you were merely dragging past the edge of the screen
          snap to half of it — which then fights the tiler for the same space.
          Setting it false is the single most useful key in this group for a
          tiling machine, and haus warns about the combination.
        '';
      };
      topEdgeFullscreen = mkWindowManagerOption {
        key = "EnableTopTilingByEdgeDrag";
        description = ''
          Drag a window up to the menu bar and macOS fills the screen with it.
          The same bargain as `edgeDrag`, at the top edge, and worth turning off
          for the same reason if you tile: the menu bar is somewhere a window
          gets dragged PAST, on the way to somewhere else.
        '';
      };
      optionAccelerator = mkWindowManagerOption {
        key = "EnableTilingOptionAccelerator";
        description = ''
          Hold ⌥ while dragging to tile, instead of tiling whenever a drag
          reaches an edge.

          The middle setting between the two extremes, and the one to reach for
          before turning `edgeDrag` off entirely: native tiling stays available
          on the machine and stops happening by accident, because it now takes a
          modifier you have to mean. On a tiling machine that still costs a
          modifier AeroSpace may want — check `haus.keys.windowNav` before
          relying on it.
        '';
      };
      margins = mkWindowManagerOption {
        key = "EnableTiledWindowMargins";
        description = ''
          Leave a gap between natively tiled windows and the screen edges.
          macOS's own gaps setting, and nothing to do with
          `haus.windows.accordionPadding` or AeroSpace's gaps, which apply to
          windows the TILER placed.
        '';
      };
    };

    windows.desktop = {
      clickToReveal = mkWindowManagerOption {
        key = "EnableStandardClickToShowDesktop";
        description = ''
          Click the wallpaper to push every window aside and reveal the desktop.
          macOS 14 turned this on for everybody and it is the change most people
          want back: true is "always", false is "only in Stage Manager".

          Worth knowing before you leave it on with a tiler: a click on the
          wallpaper is easy to make by accident on a workspace whose windows do
          not cover the screen, and it moves every window on it.
        '';
      };
      hideIcons = mkWindowManagerOption {
        key = "StandardHideDesktopIcons";
        description = ''
          Hide the icons on your desktop, always — the files are still in
          `~/Desktop`, Finder still shows them, they just stop being drawn on
          the wallpaper.

          The natural companion to a generated `haus.wallpaper`, which you chose
          to look at rather than to be a filing cabinet.
        '';
      };
      hideWidgets = mkWindowManagerOption {
        key = "StandardHideWidgets";
        description = ''
          Hide desktop widgets, always. Same idea as `hideIcons`, for the
          clock/calendar/weather widgets macOS 14 let you park on the desktop.
        '';
      };
    };
  };
}

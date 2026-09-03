# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# windows's options — tiling + the leader launcher. WHICH keys drive them is
# haus.keys.* in modules/options.nix: cross-cutting, because `leader` and
# `windowNav` are windows's while `palette` is the launcher's, and one table has to
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

  # ---- the settable gaps ----------------------------------------------------
  # Every gap in aerospace.toml is a per-monitor pair — one number for the
  # built-in display, one for anything external — so the option is that pair and
  # not a single figure. `../lib/gaps.nix` owns what the numbers MEAN (it scales
  # them by haus.ui.scale and adds the bar's reservation where one is due);
  # this is only their shape, spelled once so three edges can't describe
  # themselves three different ways.
  #
  # The paragraph every leaf carries is the same one, which is the whole reason
  # for the function: the difference between a settable edge and the two that
  # are not is a thing a person meets at whichever leaf they happen to read.
  mkGapPair =
    {
      what,
      builtin,
      external,
    }:
    let
      leaf =
        monitor: default:
        lib.mkOption {
          type = lib.types.ints.unsigned;
          inherit default;
          example = 0;
          description = ''
            ${what} on ${monitor}, in points.

            Two numbers rather than one because AeroSpace takes a gap per
            monitor and the two displays want different ones: haus ships 10 on
            the built-in and 20 around an external, which is the same gap
            reading the same size on panels of very different pitch.

            This is the gap at `haus.ui.scale = 1.0`, not the finished number —
            it is multiplied by the scale like every other tuned measurement, so
            a bigger desktop keeps its proportions. `0` is `0` at every scale,
            which is what to set for a desktop with no gaps at all.

            `inner`, `outer.left` and `outer.right` are the settable gaps.
            `outer.top` and `outer.bottom` are not, and deliberately: those two
            carry the bar's reservation
            (`modules/lib/gaps.nix`), which is the only thing keeping tiled
            windows out from under it — a `0` there would not be a tighter
            desktop, it would be windows drawn beneath the bar. With
            `haus.bar.enable = false` they fall back to the shipped 10/20.

            Only meaningful with haus.windows.enable.
          '';
        };
    in
    {
      builtin = leaf "the built-in display" builtin;
      external = leaf "an external display" external;
    };

  contrib = import ../lib/contrib.nix { inherit lib; };
in

{
  options.haus = {
    # ---- the Windows room's extension points ----------------------------------
    # See modules/lib/contrib.nix for the contract. AeroSpace is the only thing
    # on this Mac that sees focus move between two windows of ONE app, so a room
    # with something to do on that event has nowhere else to hang it — and the
    # alternative, this room reading `config.haus.ai.*` to decide, is exactly
    # what the contract exists to stop.
    _contrib.windows.laneSeen = contrib.mkExtensionPoint {
      description = ''
        A script AeroSpace runs, detached, after focus changes.

        Today's one writer is the terminal room's agent lanes: a lane blocked on
        you parks a trill fin, and going to its window is the earliest honest
        signal that you have seen it — earlier than the answer scruff's own hooks
        wait for. Off, or with this room off, the fin still comes down when the
        session moves; what is lost is the moment, not the behaviour.

        It runs on EVERY focus change, so whatever is named here has to reach
        its own "nothing to do" answer in a stat or two.
      '';
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether AeroSpace should run the script below on focus changes.";
        };
        script = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            Absolute path to the executable. A path under `~`, not a store path:
            AeroSpace re-reads its config on rebuild but a callback captured at a
            store path from a rebuild ago is one nothing can heal.
          '';
        };
      };
    };

    # core + terminal are the floor and have no switch (system, shell). Of the
    # rooms you can SEE, all six have one — windows, bar, launcher, shelf, focus,
    # security — and turning one off drops its packages, agents and config
    # entirely. (The cross-cutting modules — apps, displays, roster, secrets,
    # theme, wallpaper, workspaces — have no room switch either; they aren't
    # rooms. And `full`/bootstrap deliberately expose only bar+windows+launcher+
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

        To pin them to a display — 1-4 on one screen, 5-8 on another — see
        haus.windows.workspaceMonitors below, which takes these ids and
        haus.workspaces names alike.

        Only meaningful with haus.windows.enable.
      '';
    };

    # Which SCREEN a workspace lives on. The numbered workspaces are a count
    # rather than an attrset, so a `monitor` field on haus.workspaces.<id> could
    # only ever have covered the named half — and pinning 1-4 to one display and
    # 5-8 to another is the shape people actually write. So it is one table,
    # keyed by workspace id, covering both kinds at once.
    windows.workspaceMonitors = lib.mkOption {
      type = lib.types.attrsOf (lib.types.either lib.types.str (lib.types.listOf lib.types.str));
      default = { };
      example = {
        "1" = "main";
        "2" = "main";
        "5" = "secondary";
        "6" = "secondary";
        comms = [
          "Dell U2720Q"
          "main"
        ];
      };
      description = ''
        Pin a workspace to a display, so it always opens on the same screen.
        AeroSpace's `workspace-to-monitor-force-assignment`, keyed by the
        workspace id: a numbered one (`"1"`, `"2"` — how many exist is
        haus.windows.numberedWorkspaces) or a haus.workspaces name.

        A value is either one pattern or a list of them tried in order, which
        is how a workspace survives the monitor it wants being unplugged. Each
        pattern is one of:

        - `main`, `secondary`, `built-in` — the position, true on any desk;
        - a number — the display's position left to right, `1` being leftmost;
        - part of the display's name, matched case-insensitively (`Dell`);
        - a regex, when it is wrapped in `^` and `$` (`^built-in retina display$`).

        The last two name one physical panel, so they are a fact about your desk
        rather than a taste: a shared desktop may only use the first two, and the
        seam refuses the others (`modules/lib/desktop.nix`). Your own host file
        can say any of them.

        Naming a workspace that does not exist is refused at eval rather than
        ignored: AeroSpace drops an assignment for an unknown workspace in
        silence, which reads exactly like the option not working.

        Empty (the default) assigns nothing, and AeroSpace puts a workspace on
        whichever display it was last used on.

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

        Carried by the launcher's event tap (AeroSpace has no mouse bindings at all,
        and Ghostty's keybind triggers are keys), so it needs
        haus.launcher.enable and Pounce's Accessibility grant, which it already asks
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

        Only read while a workspace is in the accordion layout — whether it
        got there from haus.windows.defaultLayout, from the layout chord, or
        from the leader-key tiling dial, which carries accordion as one of its
        three stops.

        Only meaningful with haus.windows.enable.
      '';
    };

    # The tiling gaps themselves. They were derived and only derived until this
    # option existed — ../lib/gaps.nix read haus.ui.scale and the bar's position
    # and that was the whole input — which made a perfectly ordinary AeroSpace
    # config (every gap at 0) unsayable in haus. The derivation stays: this
    # names the BASE it works from, so the bar reservation, the scale and the
    # per-monitor pair all keep doing what they did.
    windows.gaps = {
      inner = mkGapPair {
        what = "How much space AeroSpace leaves BETWEEN two tiled windows";
        builtin = 10;
        external = 20;
      };
      outer.left = mkGapPair {
        what = "How much space AeroSpace leaves at the LEFT edge of the screen";
        builtin = 10;
        external = 20;
      };
      outer.right = mkGapPair {
        what = "How much space AeroSpace leaves at the RIGHT edge of the screen";
        builtin = 10;
        external = 20;
      };
    };

    # Gravity: the tiler's one UNASKED move, which is what puts it in reach of
    # haus.appearance.reduceMotion. Everything else windows does happens because
    # a key was pressed; this happens because an app quit.
    #
    # The option is windows's because the behaviour is (it moves you between
    # AeroSpace workspaces), but the code that implements it is a non-drawing
    # SketchyBar item — the bar's event stream is the only place either tell
    # exists (front_app_switched for a ⌘Q, space_windows_change for the last
    # window on a page closing), and aerospace.toml has no hook for either. So
    # bar READS this option the same
    # way it already reads windows.enable, and with the bar off there is nothing
    # to switch off: gravity was never running.
    windows.gravity = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = ''
        When the focused workspace loses its last window, pull back to the most
        recently populated one instead of leaving you on a blank screen.

        Both ways a workspace empties count: a ⌘Q that takes every window of an
        app at once, and the close of the LAST window on a page — a ⌘W on a lane,
        a ⌃D that ends a shell — while that app carries on in windows elsewhere.
        The second matters most on the `T/<repo>` lane pages, which are not
        persistent: without it you were left standing on a page that no longer
        appears in any list, with nothing on it.

        It fires only for a workspace you EMPTIED — never for one you
        deliberately navigated to that happens to be empty — so in ordinary use
        it is the difference between closing the last thing on a space and then
        having to find your way off it.

        A workspace and its pages are one family, and gravity prefers it:
        emptying `T/<repo>` lands on the most recent populated member of the T
        family — another page, even one never visited, or T itself — and only
        when the whole family is empty does it fall back to the most recently
        populated workspace anywhere.

        Turn it off if a screen that changes without you touching it is worse
        than a blank one. That is what `haus.appearance.reduceMotion` decides on
        your behalf: it is the largest movement haus makes that you did not ask
        for, and one whole display's worth of content replaced in a blink is
        exactly what a vestibular trigger looks like.

        Needs both `haus.windows.enable` and `haus.bar.enable`: the emptying is
        detected from the bar's own event stream (see
        modules/bar/sketchybar/plugins/empty_workspace.sh for why there is no
        AeroSpace hook for it), so with no bar there is no gravity either way.
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
          Hold ⌥ while dragging to tile a window.

          READ THIS WITH `edgeDrag`, not instead of it. These are two
          independent keys and macOS ships both on, so turning this on does NOT
          stop a bare drag from tiling — that is `edgeDrag = false`, and what
          this adds is a second, deliberate way in. The pair people usually
          want is `edgeDrag = false` here and `optionAccelerator = true`:
          native tiling stays available on the machine and stops happening by
          accident, which on a tiling machine is the whole complaint.

          On a tiling machine it also spends a modifier AeroSpace may want —
          check `haus.keys.windowNav` before relying on it.
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

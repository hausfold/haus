# The static AeroSpace bindings — the tiling/workspace/service chords that are
# the SAME on every install (the per-app launcher chords live in the roster,
# nebelhaus._apps). Declared ONCE here, then rendered two ways:
#
#   modules/prowl/default.nix   → the `binds` become aerospace.toml lines
#                                 (@MAIN_STATIC@ / @SERVICE_STATIC@ tokens).
#   modules/pounce/default.nix  → the `keys`/`action` become cheatsheet rows.
#
# Because both artifacts come from this one table, a binding and its cheatsheet
# caption can't disagree — editing the chord here moves both in lockstep. This
# is what killed the class of drift that commit 9abf899 had to fix by hand.
#
# Each item:
#   keys    display string for the cheatsheet (human-friendly, may fold several
#           chords into one row like "⌥ hjkl"). Omit for a toml-only binding.
#   action  cheatsheet caption. Omit alongside keys for a toml-only binding.
#   binds   attrset of aerospace chord → command. The command is a string, or a
#           list of strings for a multi-command binding (e.g. ["join-with left"
#           "mode main"]). Omit for a display-only row (e.g. the app-workspace
#           throws, whose chords are generated from the roster). @HOME@/@BIN@
#           tokens are substituted by modules/prowl at build time.
#
# Each section: title (cheatsheet heading), optional mode ("main" default, or
# "service" → rendered under [mode.service.binding]).
[
  {
    title = "Window Management";
    items = [
      {
        keys = "⌥ hjkl";
        action = "Focus direction";
        binds = {
          alt-h = "focus left";
          alt-j = "focus down";
          alt-k = "focus up";
          alt-l = "focus right";
        };
      }
      {
        keys = "⌥ /";
        action = "Tiles layout";
        binds.alt-slash = "layout tiles horizontal vertical";
      }
      {
        keys = "⌥ ,";
        action = "Accordion layout";
        binds.alt-comma = "layout accordion horizontal vertical";
      }
      {
        keys = "⌥ f";
        action = "Fullscreen toggle";
        binds.alt-f = "fullscreen";
      }
      {
        keys = "⌥ ⇥";
        action = "Back and forth";
        binds.alt-tab = "workspace-back-and-forth";
      }
      {
        keys = "⌥ ⇧ ⇥";
        action = "Move workspace to next monitor";
        binds.alt-shift-tab = "move-workspace-to-monitor --wrap-around next";
      }
    ];
  }
  {
    title = "Workspaces";
    items = [
      # Focusing workspaces 1-4 is a caps-leader action now (tap caps, then a
      # digit — same as tapping caps then a letter for an app). That binding
      # lives in [mode.launch.binding] in aerospace.toml and on the Launch Mode
      # cheatsheet page, so there's no main-mode focus chord here. Moving a
      # window to one stays ⌥⇧1-4 below, mirroring the app-workspace throws.
      {
        keys = "⌥ ⇧ 1-4";
        action = "Move to workspace 1-4";
        binds = {
          alt-shift-1 = "move-node-to-workspace 1";
          alt-shift-2 = "move-node-to-workspace 2";
          alt-shift-3 = "move-node-to-workspace 3";
          alt-shift-4 = "move-node-to-workspace 4";
        };
      }
      # ⌥⇧<letter> throws a window to an app's workspace — those chords are
      # generated from nebelhaus._apps (@MAIN_MOVES@), so this row is
      # display-only: it documents the pattern, it doesn't bind anything.
      {
        keys = "⌥ ⇧ [Letter]";
        action = "Move to app workspace";
      }
    ];
  }
  {
    title = "Service Mode [⌥ ⇧ ;]";
    mode = "service";
    items = [
      {
        keys = "r";
        action = "Flatten tree";
        binds.r = [ "flatten-workspace-tree" "mode main" ];
      }
      {
        keys = "f";
        action = "Toggle floating";
        binds.f = [ "layout floating tiling" "mode main" ];
      }
      {
        keys = "⌫";
        action = "Close others";
        binds.backspace = [ "close-all-windows-but-current" "mode main" ];
      }
      {
        keys = "⌥ ⇧ hjkl";
        action = "Join with";
        binds = {
          alt-shift-h = [ "join-with left" "mode main" ];
          alt-shift-j = [ "join-with down" "mode main" ];
          alt-shift-k = [ "join-with up" "mode main" ];
          alt-shift-l = [ "join-with right" "mode main" ];
        };
      }
      {
        keys = "↑ / ↓";
        action = "Volume up / down";
        binds = {
          up = "volume up";
          down = "volume down";
        };
      }
      {
        keys = "⇧ ↓";
        action = "Mute volume";
        binds.shift-down = [ "volume set 0" "mode main" ];
      }
      {
        keys = "⎋";
        action = "Reload config + exit";
        binds.esc = [ "reload-config" "mode main" ];
      }
    ];
  }
  {
    title = "System";
    items = [
      {
        # Display-only: the pounce daemon registers ⌘Space itself (in-process
        # Carbon hotkey, see modules/pounce). Binding it here too made AeroSpace
        # win the race and spawn the palette — so every palette command ran
        # under AEROSPACE's TCC identity, where e.g. CoreBluetooth aborts
        # (AeroSpace.app has no Bluetooth usage description). Commands must
        # spawn from the daemon so grants land on the signed Pounce.app.
        keys = "⌘ Space";
        action = "Command Palette";
      }
    ];
  }
]

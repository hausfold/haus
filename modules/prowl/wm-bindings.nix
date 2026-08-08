# The static AeroSpace bindings — the tiling/workspace/service chords that are
# the SAME on every install (the per-app launcher chords live in the roster,
# haus._roster). Declared ONCE here, then rendered two ways:
#
#   modules/prowl/default.nix   → the `binds` become aerospace.toml lines
#                                 (@MAIN_STATIC@ / @SERVICE_STATIC@ tokens).
#   modules/pounce/default.nix  → the `keys`/`action` become cheatsheet rows.
#
# Because both artifacts come from this one table, a binding and its cheatsheet
# caption can't disagree — editing the chord here moves both in lockstep. This
# is what killed the class of drift that commit 9abf899 had to fix by hand.
#
# A FUNCTION of the resolved keymap (modules/lib/keys.nix), because the modifier
# was the last part of a row still written twice: "⌥ hjkl" as a caption beside
# `alt-h` as a chord. Both now come from `k.nav`, so haus.keys.windowNav
# moves the chord and its caption together — and `k.nav == null` (windowNav =
# "none") returns no window sections at all, rather than a cheatsheet advertising
# keys that aren't bound.
#
# Each item:
#   keys    display string for the cheatsheet (human-friendly, may fold several
#           chords into one row like "⌥ hjkl"). Omit for a toml-only binding.
#   action  cheatsheet caption. Omit alongside keys for a toml-only binding.
#   binds   attrset of aerospace chord → command. The command is a string, or a
#           list of strings for a multi-command binding (e.g. ["join-with left"
#           "mode main"]). Omit for a display-only row (e.g. the palette, which
#           the pounce daemon registers in-process). @HOME@/@BIN@ tokens are
#           substituted by modules/prowl at build time.
#
# Each section: title (cheatsheet heading), optional mode ("main" default, or
# "service" → rendered under [mode.service.binding]).
{
  lib,
  k,
}:

let
  hasNav = k.nav != null;
  # Chord + caption from the same source. `m` is <mod>+key, `ms` is <mod>⇧+key.
  m = key: "${k.nav.chord}-${key}";
  ms = key: "${k.nav.chord}-shift-${key}";
  g = rest: "${k.nav.glyph} ${rest}";
  gs = rest: "${k.nav.glyph} ⇧ ${rest}";
in

lib.optionals hasNav [
  {
    title = "Window Management";
    items = [
      {
        keys = g "hjkl";
        action = "Focus direction";
        binds = {
          ${m "h"} = "focus left";
          ${m "j"} = "focus down";
          ${m "k"} = "focus up";
          ${m "l"} = "focus right";
        };
      }
      {
        keys = g "/";
        action = "Tiles layout";
        binds.${m "slash"} = "layout tiles horizontal vertical";
      }
      {
        keys = g ",";
        action = "Accordion layout";
        binds.${m "comma"} = "layout accordion horizontal vertical";
      }
      {
        keys = g "f";
        action = "Fullscreen toggle";
        binds.${m "f"} = "fullscreen";
      }
      # No <mod>⇥ row: workspace back-and-forth is retired. pounce's ⌘⇥ switcher
      # is already cross-workspace (rows carry the window's workspace, and
      # focusing goes through `aerospace focus --window-id`), so "get me back to
      # where I was" is ONE switcher instead of two that disagree — and
      # back-and-forth's single previous-workspace pointer was the thing that
      # kept landing you on a workspace you'd just emptied. <mod>⇥ is left
      # deliberately UNBOUND rather than refilled: what it should become is a
      # question for whatever a few days without it turn out to miss.
      {
        keys = gs "⇥";
        action = "Move workspace to next monitor";
        binds.${ms "tab"} = "move-workspace-to-monitor --wrap-around next";
      }
    ];
  }
  # No "Workspaces" section: BOTH halves of it are leader actions now. Focusing
  # workspace 1-4 is the leader then a digit (same shape as leader then a letter
  # for an app), and THROWING the focused window there is the leader then ⇧+the
  # digit — or ⇧+an app's roster letter for its workspace. Those live in
  # [mode.launch.binding] in aerospace.toml (the roster half generated from
  # haus._roster) and on the Launch Mode cheatsheet page, so no main-mode
  # chord here carries a workspace. The window chords that remain are the ones
  # that act on the CURRENT workspace, above, plus service mode below.
  {
    title = "Service Mode [${gs ";"}]";
    mode = "service";
    items = [
      {
        keys = "r";
        action = "Flatten tree";
        binds.r = [
          "flatten-workspace-tree"
          "mode main"
        ];
      }
      {
        keys = "f";
        action = "Toggle floating";
        binds.f = [
          "layout floating tiling"
          "mode main"
        ];
      }
      {
        keys = "⌫";
        action = "Close others";
        binds.backspace = [
          "close-all-windows-but-current"
          "mode main"
        ];
      }
      {
        keys = gs "hjkl";
        action = "Join with";
        binds = {
          ${ms "h"} = [
            "join-with left"
            "mode main"
          ];
          ${ms "j"} = [
            "join-with down"
            "mode main"
          ];
          ${ms "k"} = [
            "join-with up"
            "mode main"
          ];
          ${ms "l"} = [
            "join-with right"
            "mode main"
          ];
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
        binds.shift-down = [
          "volume set 0"
          "mode main"
        ];
      }
      {
        keys = "⎋";
        action = "Reload config + exit";
        binds.esc = [
          "reload-config"
          "mode main"
        ];
      }
    ];
  }
]
++
  lib.optionals (k.palette != null) [
    {
      title = "System";
      items = [
        {
          # Display-only: the pounce daemon registers this hotkey itself (in-process
          # Carbon hotkey, see modules/pounce). Binding it here too made AeroSpace
          # win the race and spawn the palette — so every palette command ran
          # under AEROSPACE's TCC identity, where e.g. CoreBluetooth aborts
          # (AeroSpace.app has no Bluetooth usage description). Commands must
          # spawn from the daemon so grants land on the signed Pounce.app.
          keys = k.palette.glyph;
          action = "Command Palette";
        }
      ];
    }
  ]

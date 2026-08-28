# The static AeroSpace bindings — the tiling/workspace/service chords that are
# the SAME on every install (the per-app launcher chords live in the roster,
# haus._roster). Declared ONCE here, then rendered two ways:
#
#   modules/windows/default.nix   → the `binds` become aerospace.toml lines
#                                 (@MAIN_STATIC@ / @SERVICE_STATIC@ tokens).
#   modules/launcher/default.nix  → the `keys`/`action` become cheatsheet rows.
#
# Because both artifacts come from this one table, a binding and its cheatsheet
# caption can't disagree — editing the chord here moves both in lockstep. This
# is what killed the class of drift that commit 9abf899 had to fix by hand.
#
# A FUNCTION of the resolved keymap (modules/lib/keys.nix), because the modifier
# was the last part of a row still written twice: "⌥ ⇧ ←↓↑→" as a caption beside
# `alt-shift-left` as a chord. Both now come from `k.nav`, so haus.keys.windowNav
# moves the chord and its caption together — and `k.nav == null` (windowNav =
# "none") returns no window sections at all, rather than a cheatsheet advertising
# keys that aren't bound.
#
# Each item:
#   keys    display string for the cheatsheet (human-friendly, may fold several
#           chords into one row like "⌥ ⇧ ←↓↑→"). Omit for a toml-only binding.
#   action  cheatsheet caption. Omit alongside keys for a toml-only binding.
#   binds   attrset of aerospace chord → command. The command is a string, or a
#           list of strings for a multi-command binding (e.g. ["join-with left"
#           "mode main"]). Omit for a display-only row (e.g. the palette, which
#           the pounce daemon registers in-process). @HOME@/@BIN@ tokens are
#           substituted by modules/windows at build time.
#
# Each section: title (cheatsheet heading), optional mode ("main" default, or
# "service" → rendered under [mode.service.binding]).
# There is no agent-spawn chord in this table, and there hasn't been since
# 2026-08-18. It was ⌃⌘A here — the one layer that sees every window — until the
# chord became ⌘↵, which cannot be global (it is *send* in half the Mac) and so
# rides pounce's Ghostty-scoped tap instead: modules/launcher's appHotkeys,
# targeting `cmd:lane-here`. The extension point windows declared for it
# (`haus._contrib.windows.agents`) went with it; the terminal room still owns
# the script, and lanes still need this room for `aerospace
# move-node-to-workspace` (see terminal's own assertion).
{
  lib,
  k,
  # haus.windows.mouseFullscreen — "right", "left" or "none". A display-only row:
  # the chord is pounce's event tap, not an AeroSpace bind (AeroSpace has no
  # mouse bindings at all), so this table carries the caption and nothing else.
  # It still belongs here rather than in the launcher's own cards, because the
  # thing it does is <mod>f's and it should read beside it — and unlike the
  # agent chord that just left, it is a WINDOW action, so it stays.
  mouseFullscreen ? "none",
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
      # No focus row here, and nothing replaced it. <mod>hjkl used to focus by
      # direction; focusing by direction is a LEADER action now — tap the
      # leader, then an arrow, which drops into navigate mode so the next arrow
      # keeps moving without re-tapping. That is the better motion of the two
      # (one chord for a sequence of moves rather than one chord per move), and
      # the chord it replaced was this layer's last Vim-key default. haus binds
      # no h/j/k/l direction anywhere now, deliberately: a Vim-handed person can
      # add their own four lines, and everyone else stops reading a vocabulary
      # they don't use. <mod>hjkl is left UNBOUND rather than refilled — those
      # four chords go back to whatever owned them inside a terminal.
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
        # One exec-and-forget rather than `fullscreen` + notify, because the
        # toggle is guarded: fullscreen is the one tiling state with no tell of
        # its own (the window fills the workspace, its siblings vanish, nothing
        # says they still exist), and arming it on a SOLO window is a no-op
        # whose only effect lands later — the next window to open on this
        # workspace is hidden behind it, with the bar painting the fullscreen
        # glyph the whole time. The script (fullscreen-toggle.sh) allows the
        # OFF take unconditionally and the ON take only when a sibling shares
        # the workspace, and fires the bar's aerospace-notify.sh — which
        # paints the glyph on the front-app pill and turns the focused
        # workspace pill peach (modules/bar/sketchybar/plugins/
        # aerospace_lib.sh) — only when the state actually changed. The
        # watcher polls too, so the notify is latency, not correctness.
        binds.${m "f"} = "exec-and-forget @HOME@/.config/aerospace/fullscreen-toggle.sh";
      }
    ]
    ++ lib.optional (mouseFullscreen != "none") {
      # The same toggle, on the window under the POINTER rather than the focused
      # one — which is the whole reason it exists, since <mod>f can only ever
      # reach the window you are already in. No `binds`: pounce carries it.
      keys = g (if mouseFullscreen == "right" then "right-click" else "click");
      action = "Fullscreen the window under the pointer";
    }
    ++ [
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
  # No "Workspaces" section: ALL THREE parts of it are leader actions now.
  # Focusing a numbered workspace is the leader then its digit (same shape as
  # leader then a letter for an app), THROWING the focused window there and
  # following is the leader then ⇧+that digit, and throwing WITHOUT following is
  # ⌥⇧+it — or ⇧ / ⌥⇧ + an app's roster letter for its workspace. Those live in
  # [mode.launch.binding] in aerospace.toml (generated from haus._roster and
  # haus.windows.numberedWorkspaces) and on the Launch Mode cheatsheet page, so no
  # main-mode chord here carries a workspace. The window chords that remain are
  # the ones that act on the CURRENT workspace, above, plus service mode below.
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
      # Arrows rather than hjkl, for the same reason the focus row went: no Vim
      # direction is bound by default anywhere in haus. Still on <mod>⇧ rather
      # than bare, because service mode's bare ↑/↓ are volume and its ⇧↓ is
      # mute — the modifier is what keeps "join a neighbour" out of their way.
      {
        keys = gs "←↓↑→";
        action = "Join with";
        binds = {
          ${ms "left"} = [
            "join-with left"
            "mode main"
          ];
          ${ms "down"} = [
            "join-with down"
            "mode main"
          ];
          ${ms "up"} = [
            "join-with up"
            "mode main"
          ];
          ${ms "right"} = [
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
++ lib.optionals (k.palette != null) [
  {
    title = "System";
    items = [
      {
        # Display-only: the pounce daemon registers this hotkey itself (in-process
        # Carbon hotkey, see modules/launcher). Binding it here too made AeroSpace
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

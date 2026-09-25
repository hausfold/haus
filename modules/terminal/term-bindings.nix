# The terminal's own hotkeys — every Ghostty-scoped chord this desktop claims —
# declared ONCE here, one row per cheatsheet line. Everything else a chord needs
# is DERIVED from its row, so the four spellings of ⌘↵ that used to live in four
# files (the glyph "⌘ ↵", the reservation `cmd+return`, Ghostty's
# `cmd+enter=unbind`, pounce's `{ key; modifiers; }`) cannot drift apart:
#
#   appHotkeys    → modules/launcher: pounce's Ghostty-scoped event tap, the
#                   layer every chord that RUNS something rides on — none of
#                   `ghostty +list-actions`' 85 actions on 1.3.1 runs a command
#   pagesTap      → modules/launcher: the ⌃⇥ lane-page walk, armed through
#                   pounce's `pages` block rather than appHotkeys
#   chords        → modules/launcher: reserved against haus.launcher.items,
#                   whose hotkeys pounce registers GLOBALLY and which would
#                   otherwise take the chord away inside Ghostty alone
#   ghosttyBinds  → modules/terminal: the @CHORD_LAYER@ block of
#                   ./ghostty/config, a `keybind =` line per chord
#   pages         → modules/launcher: the Terminal cards on the cheatsheet
#
# It used to be a table of zellij KDL chords, cross-checked against config.kdl
# by an assertion in ./default.nix. When zellij went, the chords became entries
# in another room's generated JSON, the assertion went with the kdl, and for a
# while only proximity kept this table, appHotkeys and Ghostty's unbinds honest.
# Deriving them is what replaced that assertion: there is nothing left to check
# because there is nothing written twice.
#
# ⌘⇧R is the one row Ghostty ARMS rather than releases (`reset` is a native
# action, so it has somewhere to live without shelling out). It stays in the
# table because its reservation matters more, not less: a haus.launcher.items
# hotkey on it would be registered globally by pounce and swallow the chord
# before Ghostty ever saw it.
#
# What is NOT here: the deliberate holes in ./ghostty/config (⌘⇧T, ⌘R, ⌘D, ⌘⇧D)
# and ⌘C's explicit copy. Nothing arms them and nothing teaches them, so there
# is no second spelling to drift from; they stay hand-written beside the block.
#
# Each section: title (card heading), optional page ("Keys" default, "Tips" for
# the workflow half), items.
#
# Each item:
#   binds   the chords the row folds, e.g. ⌘Y and ⌘⇧Y. Each is
#             mods     written order, which is the order pounce receives them in
#             key      pounce's key name ("return", "tab", "f")
#             target   the pounce command appHotkeys runs, or
#             tap      "pages" — pounce's lane-page walk arms it instead
#             ghostty  Ghostty's action on this chord; default "unbind", which
#                      is passthrough, not `ignore`: a chord the tap consumes
#                      never arrives, one it doesn't consume reaches the shell
#                      rather than doing something Ghostty made up
#           Omit `binds` for a display-only row (the mouse gestures, `reset`
#           the shell function), which claims nothing because it is not a key.
#   enable  whether the chord DOES something on this machine (default true).
#           false → not armed and not taught, but still reserved and still
#           released in Ghostty, so turning the feature on can't surface a
#           clash that was hidden while it was off, and the key is dead rather
#           than Ghostty's own idea of it. A feature that doesn't exist here at
#           all (⌘G, ⌘B) is `lib.optional`-ed out instead: claims nothing.
#   action  the cheatsheet caption.
#   key     the display glyphs — only for a display-only row; a row with binds
#           derives them ("⌘ Y / ⌘ ⇧ Y").
{
  lib,
  # haus.ai.default — what the agent rows name as the client this host starts.
  agentDefault,
  # Whether any agent client is installed at all (haus.ai.clients). Gates
  # every lane chord: lane-spawn.sh and the lane-aware cwd behind ⌘N are the
  # AI room's, so with no client ⌘↵ would open a window that dies on
  # `command not found` and ⌘N would have no "here" to spawn beside.
  agentsEnabled,
  # haus.terminal.ghDash.enable — the chord is armed only when the dashboard
  # itself is installed, so neither the cheatsheet nor Ghostty advertises a
  # dead ⌘G on machines that do not want it.
  ghDashEnabled,
  # haus.developer.enable — ⌘B shells out to the hausfold workshop's own
  # `bench` CLI at a hardcoded `~/code/workshop` path, which only exists on
  # the family developer's own machines. Gate it the same way ghDash is
  # gated, so an end-user install neither advertises nor renders a chord that
  # would exec a binary it doesn't have.
  benchLaneEnabled,
}:

let
  cmd = [ "cmd" ];
  cmdShift = [
    "cmd"
    "shift"
  ];

  # Glyph order ⌃ ⌥ ⌘ ⇧: not Apple's menu order (⌃ ⌥ ⇧ ⌘), but what the
  # cheatsheet has always printed ("⌘ ⇧ Y", "⌃ ⇧ ⇥").
  modGlyph = {
    ctrl = "⌃";
    alt = "⌥";
    cmd = "⌘";
    shift = "⇧";
  };
  modOrder = [
    "ctrl"
    "alt"
    "cmd"
    "shift"
  ];
  keyGlyph = {
    return = "↵";
    tab = "⇥";
  };
  # pounce's HotKeyParser takes "return"; Ghostty's trigger names are W3C's,
  # and 1.3.1 spells the same key "enter".
  ghosttyKey = {
    return = "enter";
  };

  glyphsOf =
    b:
    lib.concatStringsSep " " (
      map (m: modGlyph.${m}) (lib.filter (m: lib.elem m b.mods) modOrder)
      ++ [ (keyGlyph.${b.key} or (lib.toUpper b.key)) ]
    );
  plusSpelling = keyNames: b: lib.concatStringsSep "+" (b.mods ++ [ (keyNames.${b.key} or b.key) ]);

  keyOf = it: if it ? binds then lib.concatMapStringsSep " / " glyphsOf it.binds else it.key;
  bindsOf = it: it.binds or [ ];
  armedBinds = lib.concatMap (it: lib.optionals (it.enable or true) (bindsOf it));
  allItems = lib.concatMap (s: s.items) sections;

  sections = [
    {
      title = "Terminal · Agents";
      items = [
        {
          # ⌘↵ — a new agent lane in the focused window's repo (cmd:lane-here →
          # the terminal room's lane-spawn.sh). ⌃⌘A in AeroSpace until
          # 2026-08-18; ⌘↵ is the guessable chord, and exactly why it cannot be
          # global — it means *send* in Slack, Claude and Linear. Ghostty 1.3.1
          # binds it to toggle_fullscreen, so the unbind is load-bearing.
          binds = [
            {
              mods = cmd;
              key = "return";
              target = "cmd:lane-here";
            }
          ];
          enable = agentsEnabled;
          action = "New agent lane in this page's repo";
        }
      ];
    }
    {
      title = "Terminal · Windows";
      # A window IS a pane now (windows/AeroSpace tiles them), so the rows that
      # used to describe zellij's pane and tab model are gone rather than
      # reworded: ⌘⇧T ("new tab at this pane's cwd") is what ⌘N means, ⌘W is
      # Ghostty's own close_window, and ⌥[ / ⌥] cycled zellij swap layouts,
      # which windows has its own chords for.
      items = [
        {
          # ⌘N / ⌘⇧N — a shell WINDOW in the focused window's directory,
          # hopping out of an agent worktree unless shift says stay. ⌘P/⌘⇧P
          # until 2026-08-18; ⌘P is Ghostty's again. Released even with lanes
          # off, so that machine gets a dead key rather than Ghostty's
          # new_window, which knows nothing about "here".
          binds = [
            {
              mods = cmd;
              key = "n";
              target = "cmd:shell-here";
            }
            {
              mods = cmdShift;
              key = "n";
              target = "cmd:shell-here-stay";
            }
          ];
          enable = agentsEnabled;
          action = "New shell window in this page's repo — hop out of a worktree / stay";
        }
        {
          # ⌘T — a NEUTRAL terminal: home directory, no repo, on the base of
          # whatever workspace you are on (commands/shell-plain.sh). The escape
          # hatch from the page ownership ⌘N and ⌘↵ obey, and the only spawn
          # chord left alive with the agent clients off. Free because this
          # desktop has no tabs: a Ghostty tab would nest a second layout model
          # inside one tile.
          binds = [
            {
              mods = cmd;
              key = "t";
              target = "cmd:shell-plain";
            }
          ];
          action = "New terminal window — home directory, off any repo's page";
        }
        {
          # ⌃⇥ / ⌃⇧⇥ — the MRU walk over the non-empty T/* lane pages. Ghostty
          # binds these to next_tab/previous_tab, and even unbound AppKit
          # swallows ctrl+tab for focus navigation before the terminal core
          # sees it — which is why the walk lives in pounce's tap, not in
          # AeroSpace. Ghostty sends the kitty-keyboard encoding (CSI 9;5u /
          # 9;6u) instead, which is what a TUI wants whenever the tap doesn't
          # consume the chord. Only ⌃⇥ is named to pounce's `pages` block; it
          # derives the shifted walk itself.
          binds = [
            {
              mods = [ "ctrl" ];
              key = "tab";
              tap = "pages";
              ghostty = "text:\\x1b[9;5u";
            }
            {
              mods = [
                "ctrl"
                "shift"
              ];
              key = "tab";
              ghostty = "text:\\x1b[9;6u";
            }
          ];
          enable = agentsEnabled;
          action = "Walk lane pages by recency, back / forward";
        }
      ];
    }
    {
      title = "Terminal · Find & Files";
      items = [
        {
          # Full-text search over the focused window's zmx scrollback, or over
          # every session at once (scripts/find.sh; agent windows through their
          # stored transcript, since an alt-screen TUI has no scrollback).
          # Ghostty 1.3.1 binds these to start_search / end_search.
          binds = [
            {
              mods = cmd;
              key = "f";
              target = "cmd:find";
            }
            {
              mods = cmdShift;
              key = "f";
              target = "cmd:find-all";
            }
          ];
          action = "Find in this window / across every window";
        }
        {
          # The floating yazi peek, hopping out of an agent worktree to the
          # repo's main checkout unless shift says stay.
          binds = [
            {
              mods = cmd;
              key = "y";
              target = "cmd:peek";
            }
            {
              mods = cmdShift;
              key = "y";
              target = "cmd:peek-stay";
            }
          ];
          action = "Peek files — hop out of a worktree / stay in it";
        }
        {
          # Every URL this window's scrollback has seen, newest first.
          binds = [
            {
              mods = cmd;
              key = "l";
              target = "cmd:links";
            }
          ];
          action = "Open a link from this window's scrollback";
        }
      ]
      ++ lib.optional ghDashEnabled {
        # gh-dash in a near-fullscreen floating window. Ghostty 1.3.1 binds ⌘G
        # to navigate_search:next.
        binds = [
          {
            mods = cmd;
            key = "g";
            target = "cmd:gh-dash";
          }
        ];
        action = "GitHub dashboard, fullscreen overlay";
      }
      ++ lib.optional benchLaneEnabled {
        # `bench try lane switch` — this worktree plus every `scruff child`
        # worktree spawned from it, in one rebuild ("b" for bench, since ⌘L is
        # Links). Ghostty binds nothing here; released defensively.
        binds = [
          {
            mods = cmd;
            key = "b";
            target = "cmd:bench-lane";
          }
        ];
        action = "Build+activate this window's whole scruff lane";
      };
    }
    # Unbreaking a terminal: two rows because the breakage has two halves and
    # neither tool fixes both. The chord resets the EMULATOR (Ghostty's own
    # `reset` action — alt screen, charset, mouse reporting), which is the half
    # that works when the shell is too wedged to take a command; `reset` itself
    # is the shell function in ../terminal/default.nix's zshrc, which repairs
    # the pty's termios as well and costs ~8 ms against the stock binary's
    # ~1000. Taught here rather than on Keys because the thing that is hard to
    # remember is not the chord, it's that the two are complementary.
    {
      title = "Terminal · When it breaks";
      page = "Tips";
      items = [
        {
          # On ⇧ + the released ⌘R deliberately: ⌘R reads as "reload" and stays
          # the program's, and every browser on this Mac spells "reload harder,
          # from scratch" ⌘⇧R. Catching ⇧ by accident costs a redraw of the
          # surface and nothing else — the scrollback is zmx's. Free everywhere:
          # no Ghostty default (its only `r` is ⌘0 reset_font_size), nothing in
          # modules/lib/keys.nix, AeroSpace or any macOS symbolic hotkey.
          binds = [
            {
              mods = cmdShift;
              key = "r";
              ghostty = "reset";
            }
          ];
          action = "Reset the display — works when typing doesn't";
        }
        {
          key = "reset";
          action = "Repairs the tty too — 8 ms, not the stock 1 s";
        }
      ];
    }
    # The mouse half: real terminal behaviour, no chord to check, and workflow
    # rather than key reference — so it lives on Tips beside the other
    # "things that are hard to remember" cards.
    #
    # Three rows shorter than it was, and every one of them left with a zellij
    # patch: a BARE click no longer opens a link (inside a mouse-tracking
    # program the click belongs to the program, and ⌘ is what asks Ghostty for
    # the link instead), ⌃click and right-click no longer zoom (a window is the
    # pane; windows owns fullscreen), and a clicked path no longer opens in the
    # editor. See modules/terminal/default.nix's patch epitaph for the per-patch
    # verdicts.
    #
    # ⌘, not ⌘⇧: these two rows carried a phantom ⇧ until 2026-08-20 — Ghostty
    # consumes a cmd-click as a link click before any mouse report is forwarded,
    # so shift adds nothing. ⇧ belongs to the drag row below and nowhere else.
    {
      title = "Terminal · Mouse";
      page = "Tips";
      items = [
        {
          key = "⌘ Click link";
          action = "Ghostty's own opener — and the only one";
        }
        {
          key = "⌘ Hover link";
          action = "Previews the target before you commit";
        }
        {
          key = "⇧ Drag";
          action = "Ghostty's selection, over any TUI's mouse grab";
        }
      ];
    }
  ];
in
{
  inherit sections;

  # pounce's appHotkeys `keys`, for the Ghostty scope.
  appHotkeys = map (b: {
    inherit (b) key target;
    modifiers = b.mods;
  }) (lib.filter (b: b ? target) (armedBinds allItems));

  # The chord pounce's `pages` block walks on. Not gated on `enable`: that
  # block is also written for a workspace-scoped haus.launcher.items row with
  # the walk itself off, and its `enabled` follows the same flag as this row.
  pagesTap = lib.findFirst (b: (b.tap or null) == "pages") null (lib.concatMap bindsOf allItems);

  # Every chord this table claims, in a spelling modules/launcher can
  # normalize, for the haus.launcher.items collision check. `enable = false`
  # rows included, on purpose (see the header).
  chords = map (plusSpelling { }) (lib.concatMap bindsOf allItems);

  # ./ghostty/config's chord-layer block: one `keybind =` per chord, each row
  # captioned so the rendered file still says what the key is for.
  ghosttyBinds = lib.concatMapStrings (
    it:
    "# ${keyOf it} — ${it.action}\n"
    + lib.concatMapStrings (
      b: "keybind = ${plusSpelling ghosttyKey b}=${b.ghostty or "unbind"}\n"
    ) it.binds
  ) (lib.filter (it: it ? binds) allItems);

  # The cheatsheet's view: rows that do nothing here dropped, then any section
  # they emptied.
  pages = lib.filter (s: s.items != [ ]) (
    map (
      s:
      {
        title = s.title;
        items = map (it: {
          key = keyOf it;
          inherit (it) action;
        }) (lib.filter (it: it.enable or true) s.items);
      }
      # Absent `page` is what pounce reads as the default "Keys" page, so only
      # emit the key when a section asks for another one.
      // lib.optionalAttrs (s ? page) { inherit (s) page; }
    ) sections
  );
}

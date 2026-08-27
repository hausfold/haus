# The terminal's own hotkeys — mostly the Ghostty-scoped chords pounce's event
# tap consumes (modules/launcher's appHotkeys) — declared ONCE here and read by
# modules/launcher/default.nix, which renders the Terminal cards on the
# cheatsheet's Keys page (and the mouse rows on Tips).
#
# "Mostly": ⌘⇧R is bound by GHOSTTY, in ghostty/config, because `reset` is one
# of the 85 native actions and so does not need to shell out. It belongs in
# this table anyway, and its `chords` entry matters MORE rather than less — a
# haus.launcher.items hotkey on it would be registered globally by pounce and
# would swallow the chord before Ghostty ever saw it, which is the same silent
# theft the reservation exists to stop.
#
# Same shape, and the same reason, as ../windows/wm-bindings.nix: a working key
# that appears on no page, or a page teaching a key that moved, are both drift
# — and the cheatsheet's whole job is to be the one place those can't happen.
# This table is what caught the last round of it: the Tips page still taught
# ⌘C for agents months after that chord had moved, because those rows were
# hand-typed prose sitting a repo away from the binds they described.
#
# ── what this table stopped being, when zellij went ──────────────────────────
# It used to be a table of KDL chords, cross-checked against zellij's config.kdl
# by an assertion in ./default.nix in both directions: every bind taught, every
# taught chord bound. There is no kdl to read now — the chords are entries in
# another room's generated JSON, which a Nix assertion cannot see into — so the
# `chords` / `modeOnly` machinery and the assertion are gone, and every row
# carries its display glyphs directly.
#
# `chords` survives as an export because modules/launcher still reads it for a
# DIFFERENT job: reserving these keys against haus.launcher.items, so a
# user-bound palette item can't quietly take ⌘F away inside Ghostty alone.
#
# Each item:
#   key     the display glyphs, e.g. "⌘ Y / ⌘ ⇧ Y". Typed, since there is no
#           bind spelling left to derive them from.
#   chords  EVERY normalizable spelling the row folds — a two-chord row reserves
#           both. Listing one while displaying two is a real bug rather than an
#           untidiness: the unlisted half stays armed with nothing reserving it,
#           so a `haus.launcher.items` hotkey on it builds green and then
#           silently steals that key inside Ghostty alone. Omit for a
#           display-only row (the mouse gestures), which reserves nothing
#           because it is not a key.
#   action  the cheatsheet caption.
#
# Each section: title (card heading), optional page ("Keys" default, "Tips" for
# the workflow half), optional show (false → the keys exist but this machine
# has nothing behind them, so the card stays off).
{
  lib,
  # haus.ai.default — what the agent rows name as the client this host starts.
  agentDefault,
  # Whether any agent client is installed at all (haus.ai.clients).
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

rec {
  sections = [
    {
      title = "Terminal · Agents";
      # With no client installed these would open a window that dies on
      # `command not found`, so the card goes quiet rather than teaching a dead
      # key.
      show = agentsEnabled;
      items = [
        {
          key = "⌘ ↵";
          chords = [ "cmd+return" ];
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
          key = "⌘ N / ⌘ ⇧ N";
          chords = [
            "cmd+n"
            "cmd+shift+n"
          ];
          action = "New shell window in this page's repo — hop out of a worktree / stay";
        }
        {
          key = "⌘ T";
          chords = [ "cmd+t" ];
          action = "New terminal window — home directory, off any repo's page";
        }
        {
          key = "⌃ ⇥ / ⌃ ⇧ ⇥";
          chords = [
            "ctrl+tab"
            "ctrl+shift+tab"
          ];
          action = "Walk lane pages by recency, back / forward";
        }
      ];
    }
    {
      title = "Terminal · Find & Files";
      items = [
        {
          key = "⌘ F / ⌘ ⇧ F";
          chords = [
            "cmd+f"
            "cmd+shift+f"
          ];
          action = "Find in this window / across every window";
        }
        {
          key = "⌘ Y / ⌘ ⇧ Y";
          chords = [
            "cmd+y"
            "cmd+shift+y"
          ];
          action = "Peek files — hop out of a worktree / stay in it";
        }
        {
          key = "⌘ L";
          chords = [ "cmd+l" ];
          action = "Open a link from this window's scrollback";
        }
      ]
      ++ lib.optional ghDashEnabled {
        key = "⌘ G";
        chords = [ "cmd+g" ];
        action = "GitHub dashboard, fullscreen overlay";
      }
      ++ lib.optional benchLaneEnabled {
        key = "⌘ B";
        chords = [ "cmd+b" ];
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
          key = "⌘ ⇧ R";
          chords = [ "cmd+shift+r" ];
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

  # Every chord this table claims, in a spelling modules/launcher can normalize,
  # for the haus.launcher.items collision check. Includes sections whose `show`
  # is false: the chord is reserved regardless, because turning the feature on
  # must not surface a clash that was hidden while it was off.
  chords = lib.concatMap (s: lib.concatMap (it: it.chords or [ ]) s.items) sections;

  # The cheatsheet's view of the same table: hidden sections dropped.
  pages = map (
    s:
    {
      title = s.title;
      items = map (it: {
        inherit (it) key action;
      }) s.items;
    }
    # Absent `page` is what pounce reads as the default "Keys" page, so only
    # emit the key when a section asks for another one.
    // lib.optionalAttrs (s ? page) { inherit (s) page; }
  ) (lib.filter (s: s.show or true) sections);
}

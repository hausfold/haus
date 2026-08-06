# The terminal's own hotkeys — the zellij binds hearth renders into
# config.kdl's `shared` and `locked` blocks — declared ONCE here, then read two
# ways:
#
#   modules/hearth/default.nix  → an assertion that this table and
#                                 ./zellij/config.kdl name the SAME chords, in
#                                 both directions.
#   modules/pounce/default.nix  → the Terminal cards on the cheatsheet's Keys
#                                 page (and the mouse rows on Tips).
#
# Same shape, and the same reason, as ../prowl/wm-bindings.nix: a working key
# that appears on no page, or a page teaching a key that moved, are both drift
# — and the cheatsheet's whole job is to be the one place those can't happen.
# This table is what caught the last round of it: the Tips page still taught
# ⌘C/⌃⌥⇧C for agents months after they became ⌘A/⌃⌥⇧A, because those rows were
# hand-typed prose sitting a repo away from the binds they described.
#
# The kdl itself is NOT generated from here. Those bind bodies carry `Run`
# options, floating geometry and the long comments that explain why each one is
# shaped the way it is; rendering them from Nix would move that reasoning into
# a string and buy nothing the assertion doesn't already buy. What can't drift
# is the pair that matters — the chord and its caption.
#
# Each item:
#   chords  the kdl chord(s), spelled EXACTLY as `bind "…"` spells them. Several
#           means one row folds them ("⌘ Y / ⌘ ⇧ Y"); the glyph is derived, never
#           typed. Omit for a display-only row (the mouse gestures), which then
#           needs its own `key`.
#   key     display override, for rows with no chord to derive from.
#   action  the cheatsheet caption.
#
# Each section: title (card heading), optional page ("Keys" default, "Tips" for
# the workflow half), optional show (false → the keys exist but this machine
# has nothing behind them, so the card stays off).
{
  lib,
  # nebelhaus.agents.default — what @AGENT_NEW@/@AGENT_HERE@ resolve to, so the
  # agent rows name the client this host actually starts.
  agentDefault,
  # Whether any agent client is installed at all (nebelhaus.agents.clients).
  agentsEnabled,
}:

let
  # kdl modifier word → glyph. zellij spells ⌘ as `Super` (ghostty passes cmd
  # through unbound), which is the one spelling nobody would guess from the key
  # cap — the reason this map exists rather than a hand-typed caption.
  modGlyphs = {
    Super = "⌘";
    Ctrl = "⌃";
    Alt = "⌥";
    Shift = "⇧";
  };
  keyGlyphs = {
    Enter = "↵";
    Tab = "⇥";
    Space = "␣";
    Esc = "⎋";
  };
  # "Super Shift y" → "⌘ ⇧ Y". Bare letters uppercase (a key cap reads as one);
  # punctuation like [ or ] passes through untouched.
  chordGlyph =
    chord:
    lib.concatMapStringsSep " " (
      word:
      modGlyphs.${word}
        or (keyGlyphs.${word} or (if builtins.stringLength word == 1 then lib.toUpper word else word))
    ) (lib.splitString " " chord);
in
rec {
  sections = [
    {
      title = "Terminal · Agents";
      # The binds stay in config.kdl either way — they're static — but with no
      # client installed they'd open a pane that dies on `command not found`,
      # so the card goes quiet rather than teaching a dead key.
      show = agentsEnabled;
      items = [
        {
          chords = [ "Super a" ];
          action = "New agent in its own worktree (${agentDefault})";
        }
        {
          chords = [ "Super Shift a" ];
          action = "Same, replacing this pane (it comes back)";
        }
        {
          chords = [ "Ctrl Alt Shift a" ];
          action = "Agent in THIS checkout — one per tab";
        }
      ];
    }
    {
      title = "Terminal · Panes & Tabs";
      items = [
        {
          chords = [
            "Super p"
            "Super Shift p"
          ];
          action = "New pane — hop out of a worktree / stay in it";
        }
        {
          chords = [ "Super w" ];
          action = "Close this pane (the tab too, if it's the last)";
        }
        {
          chords = [
            "Super t"
            "Super Shift t"
          ];
          action = "New tab at ~ / at this pane's cwd";
        }
        {
          chords = [
            "Ctrl Tab"
            "Ctrl Shift Tab"
          ];
          action = "Walk tabs by recency, back / forward";
        }
        {
          chords = [ "Super Enter" ];
          action = "Fullscreen this pane, again to drop back";
        }
        {
          chords = [
            "Alt ["
            "Alt ]"
          ];
          action = "Cycle swap layouts (grid → spiral → columns)";
        }
      ];
    }
    {
      title = "Terminal · Find & Files";
      items = [
        {
          chords = [
            "Super f"
            "Super Shift f"
          ];
          action = "Find in this pane / across the session";
        }
        {
          chords = [
            "Super y"
            "Super Shift y"
          ];
          action = "Peek files — hop out of a worktree / stay in it";
        }
        {
          chords = [ "Super l" ];
          action = "Open a link from this pane's scrollback";
        }
      ];
    }
    # The mouse half: real terminal behaviour, no chord to check, and workflow
    # rather than key reference — so it lives on Tips beside the other
    # "things that are hard to remember" cards.
    {
      title = "Terminal · Mouse";
      page = "Tips";
      items = [
        {
          key = "⌥ Click path";
          action = "Opens a repo-named tab cwd'd there";
        }
        {
          key = "⌥ Click url";
          action = "Opens a visible link or bare domain";
        }
        {
          key = "⌘ Click link";
          action = "Opens embedded links too (hidden URLs)";
        }
        {
          key = "Click image";
          action = "Near-fullscreen chafa preview";
        }
        {
          key = "Drag past edge";
          action = "Selection keeps autoscrolling";
        }
      ];
    }
  ];

  # Chords config.kdl binds that are deliberately NOT cheatsheet rows: the
  # mode-internal ones (scroll / search / tab submodes), which only exist once
  # you've already unlocked into that mode and which zellij's own status bar
  # spells out while you're there. Listed rather than ignored so the coverage
  # assertion still fails on a NEW bind nobody thought about.
  modeOnly = [
    "/" # scroll → search
    "Ctrl c" # exit search / scroll
    "Esc" # ditto
    "n" # tab mode → new tab
  ];

  # Every chord this table claims, for the config.kdl coverage check. Includes
  # sections whose `show` is false: the bind exists in the file regardless.
  chords = lib.concatMap (s: lib.concatMap (it: it.chords or [ ]) s.items) sections;

  # The cheatsheet's view of the same table: display glyphs resolved, hidden
  # sections dropped. Consumed by modules/pounce.
  pages = map (
    s:
    {
      title = s.title;
      items = map (it: {
        key = if it ? key then it.key else lib.concatMapStringsSep " / " chordGlyph it.chords;
        action = it.action;
      }) s.items;
    }
    # Absent `page` is what pounce reads as the default "Keys" page, so only
    # emit the key when a section asks for another one.
    // lib.optionalAttrs (s ? page) { inherit (s) page; }
  ) (lib.filter (s: s.show or true) sections);
}

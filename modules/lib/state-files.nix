# Files under `~/.local/state/haus` that ONE room writes and ANOTHER reads.
#
# A room's own state is not in here and should not be — `awake` is the model of
# the good case: core owns the directory, core's `awake` CLI is the only thing
# that touches it, and the bar's caffeinate pill asks by running that CLI rather
# than by stat-ing its file. Nothing can drift because there is only one
# spelling. This file is for the pairs where that wasn't available: a hook that
# must not fork, a daemon reading a path a user-side script writes, a header
# field pounce stats on the ⌘Space keystroke.
#
# What goes wrong without it is silent in BOTH directions and looks like nothing:
# rename `any-page` in the writer and the Pages row is listed forever (the reader
# stats a path that will never exist, and a missing whenFile file is a yes);
# rename it in the reader and the row is hidden forever. No log, no failed
# build, no error — the same shape §5.9 of the workshop's options-roadmap opened
# on, where the two files were joined by a prose cross-reference each way and by
# nothing mechanical.
#
# `name` is the token that actually renames; `dir` is the shared convention.
#
# `literals` maps each file that spells the path ITSELF to the exact substring
# it must contain, and is what `nix flake check`'s `state-files` pins. `null`
# means the default `<dir>/<name>` — right wherever the file writes the path
# out whole. **Where the file ASSEMBLES it, the operative line has to be named
# instead**, and that is not fussiness: an earlier draft grepped for the bare
# token, and renaming `mru="$state_dir/workspace-mru"` in the writer left the
# check green, because the same word survives in the script's own header
# comment and usage line. A check that a file's NAME can satisfy is a check
# that cannot see the rename it exists to catch.
#
# Nix consumers are deliberately NOT listed: they import this attrset, so there
# is nothing there to drift. The same check refuses a `.nix` file under
# `modules/` that hand-spells a registered path, which is what keeps that
# true.
{
  any-page = {
    dir = ".local/state/haus";
    name = "any-page";
    # windows writes it on every workspace change (the one hook that already
    # runs without the bar being on); the launcher's Pages row declares it as a
    # `whenFile`, which pounce stats on the summon keystroke.
    literals = {
      # Assembled from `$state_dir`, so the write itself is the operative line.
      "modules/windows/scripts/workspace-mru.sh" = "\"$state_dir/any-page\"";
      # A `# pounce:` header, which pounce stats on the ⌘Space keystroke.
      "modules/launcher/commands/pages.sh" = "whenFile = ~/.local/state/haus/any-page";
    };
  };

  workspace-mru = {
    dir = ".local/state/haus";
    name = "workspace-mru";
    # Written by the same windows hook; read by pounce's ⌃⇥ page walk, which the
    # launcher room points at the file through `pages.mruFile`. That side is
    # Nix and takes the path from here.
    literals = {
      "modules/windows/scripts/workspace-mru.sh" = "mru=\"$state_dir/workspace-mru\"";
    };
  };

  aerospace-tiling-mode = {
    dir = ".local/state/haus";
    name = "aerospace-tiling-mode";
    # windows writes `<workspace>\t<mode>` when you cycle the layout; the bar's
    # aerospace pill reads the same two columns with the same awk to draw
    # Grid vs Columns. Two copies of one format, so the name is the cheap half.
    literals = {
      "modules/windows/scripts/tiling-mode.sh" = null;
      "modules/bar/sketchybar/plugins/aerospace_lib.sh" = null;
    };
  };

  zen-tabs = {
    dir = ".local/state/haus";
    name = "zen-tabs";
    # terminal's `haustabs` helper writes the browser's tab state; the bar's
    # media pill reads it to name a playing tab.
    literals = {
      "modules/terminal/zen-tabs/haustabs.swift" = null;
      "modules/bar/sketchybar/plugins/media_lib.sh" = null;
    };
  };

  lidawake-holds = {
    dir = ".local/state/haus";
    name = "lidawake/holds";
    # The one that crosses a privilege boundary as well as a room: the bar's
    # agent hook creates a hold file as the user, and core's root daemon reads
    # the directory (never the other way round). core takes the path from here
    # and hands it to launchd as `LIDAWAKE_HOLD_DIR`, so only the bar side is a
    # literal — and a rename there ends keep-awake with no symptom but a lid
    # that sleeps mid-run.
    literals = {
      "modules/bar/sketchybar/plugins/agents-hook.sh" = null;
    };
  };
}

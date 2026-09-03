# A desktop, as one should look: values only, all of them desktop-safe.
{
  haus = {
    ui.scale = 1.35;
    # Switched ON, against a room default that is now `false`. It used to be
    # `false` here, which stopped proving anything the moment step 4 made that
    # the default too — a row that reads the same whether or not the desktop
    # was applied is a row that cannot fail. This is the "a desktop selects a
    # room" half of the seam; the host-override row below is the other half.
    bar.enable = true;
    # A SEMANTIC display selector — "the built-in panel", true on any Mac.
    displays.internal.uiScale = "larger-text";
    # A choice about what gets INSTALLED, and the only leaf of the editor pair
    # a desktop may touch — `terminal.editor` is a command this layer executes
    # and is host-only forever. The readback prints both, so this row also
    # pins that the command followed the name across the seam.
    terminal.editorName = "neovim";
    # A DYNAMIC container whose payload a named validator admits — the happy
    # path of the rule `scene-name.nix` fails. A scene is a state a shared
    # desktop may legitimately ship; only its `hooks` (arbitrary shell) are
    # host-only, and this one sets none.
    focus.scenes.presenting = {
      description = "no interruptions, no screensaver";
      preventSleep = true;
    };
    # The bar's OPEN form, on its desktop-safe side. A desktop may arrange the
    # pills haus ships — where they sit, how often they run, whether they are
    # drawn — which is the whole point of §5.9 for anyone publishing a desktop.
    # The one thing it may not do is bring a pill that runs code, and
    # `host-only-widget-command.nix` is that half.
    bar.widgets.cpu = {
      enable = true;
      interval = 10;
    };
    # A palette row, keyed by pounce's own address space — the happy path of
    # the rule `launcher-item-key.nix` and `launcher-item-shortcut.nix` fail
    # from either side. A desktop may re-label, alias and key a row the
    # palette already has; the two things it may not do are invent an address
    # shape (there is nothing behind it) and name a Shortcuts UUID.
    launcher.items."mode:filesearch".alias = "ff";
    # A workspace pinned to a display BY POSITION — the happy path of the rule
    # `host-only-monitor.nix` and `monitor-ordinal-zero.nix` fail. "The second
    # screen" is a shape any desk can have, so a desktop may hold an opinion
    # about it; the panel's own name is a purchase, and stays a host's.
    #
    # A LIST rather than one string on purpose: it is the fallback chain, and
    # the validator walks a list element by element while a scalar goes through
    # one call. The two bad fixtures take the scalar and the list in turn, so
    # between the three every branch of that decision is exercised.
    windows.workspaceMonitors."2" = [
      "secondary"
      "main"
    ];
    # A list, so the check can read back what a host override does to one.
    launcher.autoQuit.exclude = [
      "from-desktop-a"
      "from-desktop-b"
    ];
  };
}

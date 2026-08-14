# A desktop, as one should look: values only, all of them desktop-safe.
{
  haus = {
    ui.scale = 1.35;
    # Switched ON, against a room default that is now `false`. It used to be
    # `false` here, which stopped proving anything the moment step 4 made that
    # the default too — a row that reads the same whether or not the desktop
    # was applied is a row that cannot fail. This is the "a desktop selects a
    # room" half of the seam; the host-override row below is the other half.
    sill.enable = true;
    # A SEMANTIC display selector — "the built-in panel", true on any Mac.
    displays.internal.uiScale = "larger-text";
    # A choice about what gets INSTALLED, and the only leaf of the editor pair
    # a desktop may touch — `hearth.editor` is a command this layer executes
    # and is host-only forever. The readback prints both, so this row also
    # pins that the command followed the name across the seam.
    hearth.editorName = "neovim";
    # A list, so the check can read back what a host override does to one.
    pounce.autoQuit.exclude = [
      "from-desktop-a"
      "from-desktop-b"
    ];
  };
}

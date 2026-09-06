# The editors the Development room knows how to INSTALL, and what each one is
# called once it is on the machine. Imported the same way as mono-font.nix and
# bar.nix — a plain attrset, no module system.
#
#   editors = import ../lib/editors.nix;
#
# Why a table instead of a free string. `haus.terminal.editor` is a shell command
# that this layer executes ($EDITOR, the palette's "Nix Config", the bar's
# nix-open item, the file-association opener), so it is host-only and always
# will be. That left a real gap: a DESKTOP could not say "this Mac is a neovim
# Mac", because the layer installed helix unconditionally and every other value
# of `editor` named a binary nothing had put on PATH — a broken $EDITOR dressed
# as a choice (`docs/model.md`).
#
# So the choice is over a closed set the room can actually deliver, and it is
# the enum — not the command — that a desktop sets. `editor` still exists and
# still wins: it now DEFAULTS to whatever the chosen editor answers to, and a
# host that wants "subl -w" or an editor the layer never heard of writes it
# there, exactly as before.
#
# GUI editors sit in this table beside the terminal ones, on purpose. zed is
# the default (since 2026-09-06 — it was helix, and a distro whose users edit
# in a window should say so), and vscode/cursor ride along so the installer
# asks ONE editor question. What differs per row is how the editor arrives —
# `package` from nixpkgs, or `cask` as a roster entry, which is what lets
# `haus.homebrew.adopt` claim a copy already on the Mac — and how it opens:
# `editor-open-pane.sh` spawns a terminal window for a terminal editor and
# none for a GUI one, keyed on the command's basename rather than on a flag
# here, so a host's own `haus.terminal.editor = "subl -w"` is treated the same.
#
# `port` is the Nebelung port name, or null for "we install it, we do not theme
# it". zed and helix have one (nebelung's ports.conf themes zed, helix and
# emacs; vscode is a settings snippet there rather than a port, and neither
# vim nor neovim is one), and terminal reads this rather than claiming the port
# unconditionally — the same trap gh-dash's entry in `haus.theme.ports.handled`
# documents, where claiming a port nothing wires tells `haus doctor` "handled"
# on a machine where it is not.
#
# `package` is the nixpkgs attribute, or null when something else installs the
# editor: the `cask` beside it (the roster entry terminal writes, named after
# the enum value so the Apps room's own `haus.apps.<name>.enable` lands on the
# SAME entry), or a home-manager `programs.*` module (helix, which also carries
# the settings and the rendered Nebelung theme). `name` is the roster entry's
# display name, and only the cask rows have one.
{
  zed = {
    command = "zed --wait";
    package = null;
    cask = "zed";
    name = "Zed";
    port = "zed";
  };
  vscode = {
    command = "code -w";
    package = null;
    cask = "visual-studio-code";
    name = "Visual Studio Code";
    port = null;
  };
  cursor = {
    command = "cursor -w";
    package = null;
    cask = "cursor";
    name = "Cursor";
    port = null;
  };
  helix = {
    command = "hx";
    package = null;
    cask = null;
    name = null;
    port = "helix";
  };
  neovim = {
    command = "nvim";
    package = "neovim";
    cask = null;
    name = null;
    port = null;
  };
  vim = {
    command = "vim";
    package = "vim";
    cask = null;
    name = null;
    port = null;
  };
  nano = {
    command = "nano";
    package = "nano";
    cask = null;
    name = null;
    port = null;
  };
}

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
# as a choice (workshop's notes/rooms-desktops.md, carried out of step 4).
#
# So the choice is over a closed set the room can actually deliver, and it is
# the enum — not the command — that a desktop sets. `editor` still exists and
# still wins: it now DEFAULTS to whatever the chosen editor answers to, and a
# host that wants "code -w" or an editor the layer never heard of writes it
# there, exactly as before.
#
# `port` is the Nebelung port name, or null for "we install it, we do not theme
# it". Only helix has one today (nebelung's ports.conf themes helix and emacs;
# neither vim nor neovim is a port at all), and terminal reads this rather than
# claiming the port unconditionally — the same trap gh-dash's entry in
# `haus.theme.ports.handled` documents, where claiming a port nothing wires
# tells `haus doctor` "handled" on a machine where it is not.
#
# `package` is the nixpkgs attribute, or null when a home-manager `programs.*`
# module installs the editor itself (helix, which also carries the settings and
# the rendered Nebelung theme).
{
  helix = {
    command = "hx";
    package = null;
    port = "helix";
  };
  neovim = {
    command = "nvim";
    package = "neovim";
    port = null;
  };
  vim = {
    command = "vim";
    package = "vim";
    port = null;
  };
  nano = {
    command = "nano";
    package = "nano";
    port = null;
  };
}

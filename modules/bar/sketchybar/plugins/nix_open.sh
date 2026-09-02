#!/bin/bash
# Open the nix config in haus's editor (haus.terminal.editor), landing on
# this host's own file — via terminal's shared opener, which resolves the host
# file and cwd's the window at the flake root (see terminal/scripts/nix-config-open.sh).
exec "$HOME/.config/haus/term/nix-config-open.sh"

#!/bin/bash
# pounce: name = Nix Config
# pounce: description = Open in editor
# pounce: icon = snowflake
# Open the nix config in the rice editor (haus.terminal.editor), landing on
# this host's own file — via terminal's shared opener, which resolves the host
# file and cwd's the pane at the flake root (see terminal/zellij/nix-config-open.sh).
exec "$HOME/.config/zellij/nix-config-open.sh"

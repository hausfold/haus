#!/bin/bash
# Open the nix config in the rice editor (haus.hearth.editor), landing on
# this host's own file — via hearth's shared opener, which resolves the host
# file and cwd's the pane at the flake root (see hearth/zellij/nix-config-open.sh).
exec "$HOME/.config/zellij/nix-config-open.sh"

#!/bin/zsh

# The one "open the nix config" opener, shared by the "Nix Config" palette
# command (pounce) and the bar's nix pill (sill). Lands the editor on this
# host's own file — hosts/@hostname@/default.nix — with the pane cwd'd at the
# flake root, so every other file is still one picker away. @hostname@ is baked
# from mkHaus's hostname at build time, for the same reason as pounce's
# rebuild.sh: the flake's host attr name can't be guessed at runtime. Configs
# that don't follow the hosts/<name> convention fall back to opening the flake
# root itself (in helix, that's the file picker).
NIX_CONFIG_DIR="${HAUS_FLAKE:-$HOME/.config/nix}"
TARGET="$NIX_CONFIG_DIR"
HOST_FILE="$NIX_CONFIG_DIR/hosts/@hostname@/default.nix"
[ -f "$HOST_FILE" ] && TARGET="$HOST_FILE"
exec "$HOME/.config/zellij/editor-open-pane.sh" "$TARGET" "$NIX_CONFIG_DIR"

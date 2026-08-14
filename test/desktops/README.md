# Desktop fixtures

One file per rule the desktop seam enforces, because a rule with no fixture is
a comment. `nix flake check`'s `desktop-seam` reads every file in here: the
valid ones through a real builder, and each of the rest through
`lib.desktopFailures`, diffing the exact diagnostic against the table in
`flake.nix`. That is what keeps the messages — and the filename inside them —
from rotting.

The names say what a file is: `valid-*` is a desktop, and everything else is
named for the one thing it does wrong.

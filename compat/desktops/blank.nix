# RETIRED — kept building for one release, then deleted with the two beside it.
#
# haus ships one desktop, hacker, and the installer selects none: the
# foundation, `desktop = null;`. This file is the `blank` desktop exactly as it
# last shipped, so a machine that selected it (`desktop = haus.desktops.blank;`,
# which is what hausfold.co/blank.sh once wrote) keeps building unchanged.
# modules/desktop/default.nix warns on every rebuild with the host lines that
# replace it; hausfold.co/docs/haus/desktops/choosing/#retired-names is the same
# table for a reader. It is not in modules/desktop-names.nix, so `haus desktop`
# does not list it, and nothing here may change: an alias that drifts from what
# it aliased is a different machine arriving as an "update".
#
# Blank — the from-scratch desktop. The room catalogue's neutral defaults do
# all the work: no optional room is selected and no global shortcut is claimed.
{
  haus = { };
}

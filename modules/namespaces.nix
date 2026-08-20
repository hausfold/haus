# The namespace seam: which `haus.<name>`s on this machine are haus's.
#
# Sibling of ./desktop, and here for the same reason — it is a rule about the
# whole option tree rather than about any room's values, so it can only be asked
# on the evaluated machine, where every module the person actually has is
# present. haus's own flake check cannot see a private module, and that is the
# only place this ever fires.
#
# It WARNS. It does not refuse, and the difference is the whole design: a
# person's own module on their own Mac is allowed to be wrong about a name haus
# might take in a year — they just get told, once, before the day it starts
# mattering. The rule, the reasoning and the measurement are in
# ./lib/namespaces.nix.
{ lib, options, ... }:
let
  namespaces = import ./lib/namespaces.nix {
    inherit lib;
    registry = import ./options-groups.nix;
  };
in
{
  warnings = namespaces.warningsFor options.haus;
}

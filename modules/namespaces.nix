# The namespace seam: which `haus.<name>`s on this machine are haus's, and
# which a claim (`haus._rooms.claimed`) says are a specific stranger's.
#
# Sibling of ./desktop, and here for the same reason — it is a rule about the
# whole option tree rather than about any room's values, so it can only be asked
# on the evaluated machine, where every module the person actually has is
# present. haus's own flake check cannot see a private module, and that is the
# only place this ever fires.
#
# Two different answers for two different hazards. An UNCLAIMED namespace
# WARNS — a person's own module on their own Mac is allowed to be wrong about a
# name haus might take in a year, they just get told once. A CLAIMED namespace
# whose declarations don't agree with the claim, or a namespace haus now ships
# that this machine had already claimed for someone else, REFUSES — that is
# silent co-ownership, one room's switch steering another's, and it is not a
# maybe. The rule, the reasoning and the measurement are in ./lib/namespaces.nix.
{ config, lib, options, ... }:
let
  namespaces = import ./lib/namespaces.nix {
    inherit lib;
    registry = import ./options-groups.nix;
  };
  claimed = config.haus._rooms.claimed;
  # Read from here, not from ./lib/namespaces.nix: that file is also staged
  # flat into modules/desktop-check.nix's flake-less copy, where a relative
  # path to the repo root resolves to nothing. This module only ever runs
  # from inside the repo tree, same as modules/desktop-check.nix's own read of
  # the same file.
  hausVersion = lib.fileContents ../VERSION;
in
{
  options.haus._rooms.claimed = lib.mkOption {
    internal = true;
    visible = false;
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = ''
      Which input claims each third-party namespace on this machine, keyed by
      namespace and valued by origin as typed (`haus add --room` will write
      this once that exists — acquisition step F; until then it's set by
      hand). Read by the namespace seam to tell a published room nothing
      warns about from a private one that should move under `haus.my.`, and
      to catch two different inputs' code sharing one namespace.
    '';
  };

  # A module that declares `options` has to put every other top-level
  # attribute under `config` too — `warnings`/`assertions` sitting bare
  # beside it is the "unsupported attribute" error, not a style choice.
  config = {
    warnings = namespaces.warningsFor options.haus claimed;
    assertions = namespaces.assertionsFor options.haus claimed hausVersion;
  };
}

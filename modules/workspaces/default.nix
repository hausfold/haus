# Workspaces — the one list of named AeroSpace workspaces this machine
# declares, and which roster apps live on each.
#
# `haus.workspaces` is a keyed, composable map (declared in ../options.nix
# next to the app roster it pairs with). This module does what ../roster does
# for the app list: NORMALIZE it into `haus._workspaces` (sorted, each
# entry carrying its id) and `haus._appWorkspace` (the reverse lookup,
# roster app id -> workspace id) that prowl, sill and the doc generator all
# read instead of each re-deriving membership from `haus.workspaces`
# themselves.
#
# It resolves the NUMBERED half here too (`haus._numberedWorkspaces`), even
# though the count that drives it is prowl's option. The digits were a literal
# ["1" "2" "3" "4"] in five places across two rooms while there was no option to
# read; one resolution is what makes the count changeable without a sixth copy
# appearing the next time something needs the list.
#
# Ungated on purpose, same reasoning as ../roster: a workspace's pill and
# persistent-workspace declaration shouldn't need the tiler evaluated to
# exist, since sill reads the resolved output too.
{ config, lib, ... }:

let
  named = lib.mapAttrsToList (id: ws: ws // { inherit id; }) config.haus.workspaces;
  sorted = lib.sort (a: b: a.id < b.id) named;

  # The numbered workspaces, from the count rather than from a literal list.
  # The arithmetic (and the id-vs-key note that goes with it) is in
  # ../lib/numbered.nix, because flake.nix resolves the same list for the
  # default count with no darwin config in reach.
  numbered = import ../lib/numbered.nix { inherit lib; } config.haus.prowl.numberedWorkspaces;

  # A named workspace whose id is already a numbered one is not a second
  # workspace: AeroSpace has one workspace per name, so the two declarations are
  # the same place described twice, and it gets two pills in the bar. Nobody
  # writes this at four; it is reachable the moment someone raises the count
  # past an id they were already using.
  numberedIds = map (n: n.id) numbered;
  shadowedNumbers = lib.filter (id: lib.elem id numberedIds) (map (ws: ws.id) sorted);

  allMemberships = lib.concatMap (
    ws: map (appId: { inherit appId; wsId = ws.id; }) ws.apps
  ) sorted;
  appWorkspace = lib.listToAttrs (map (m: lib.nameValuePair m.appId m.wsId) allMemberships);

  # An app id claimed by two workspaces has no defensible reading — its
  # window can only ever auto-move to ONE of them, and whichever
  # on-window-detected rule prowl renders last would silently win.
  duplicateMembers = lib.unique (
    let
      appIds = map (m: m.appId) allMemberships;
    in
    lib.filter (id: lib.count (x: x == id) appIds > 1) appIds
  );

  # A typo'd app id in `apps` (or one that's since been removed from the
  # roster) would otherwise fail silently: the workspace still gets declared,
  # its pill still renders, and the ONE thing that's supposed to happen — that
  # app's windows herding here — just never fires, with nothing to say why.
  knownAppIds = lib.attrNames config.haus.roster;
  unknownMembers = lib.unique (
    lib.filter (id: !lib.elem id knownAppIds) (map (m: m.appId) allMemberships)
  );

  # A workspace with no leader key and no members is declared but reachable
  # by nothing — almost always a typo'd `apps` entry (see unknownMembers)
  # rather than an intentional empty workspace.
  emptyWorkspaces = map (ws: ws.id) (
    lib.filter (ws: ws.key == null && ws.apps == [ ]) sorted
  );
in
{
  haus._workspaces = sorted;
  haus._appWorkspace = appWorkspace;
  haus._numberedWorkspaces = numbered;

  assertions = [
    {
      assertion = duplicateMembers == [ ];
      message =
        "haus.workspaces lists the same roster app in more than one "
        + "workspace's `apps` (its window can only ever herd to one): "
        + lib.concatStringsSep ", " duplicateMembers;
    }
  ];

  warnings =
    lib.optional (unknownMembers != [ ]) (
      "haus.workspaces names roster app ids that don't exist in "
      + "haus.roster, so nothing will ever herd there: "
      + lib.concatStringsSep ", " unknownMembers
    )
    ++ lib.optional (emptyWorkspaces != [ ]) (
      "haus.workspaces entries declare no leader `key` and no member "
      + "`apps`, so they have no effect: " + lib.concatStringsSep ", " emptyWorkspaces
    )
    ++ lib.optional (shadowedNumbers != [ ]) (
      "haus.workspaces names workspaces that haus.prowl.numberedWorkspaces "
      + "(${toString config.haus.prowl.numberedWorkspaces}) already declares, so each is "
      + "one workspace with two bar pills: "
      + lib.concatStringsSep ", " shadowedNumbers
      + ". Rename them, or lower the count."
    );
}

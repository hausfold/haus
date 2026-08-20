# Who owns `haus.<name>` on THIS machine.
#
# haus ships 35 namespaces and the registry (options-groups.nix) is the list of
# them. Nothing stops a person declaring a 36th in their own config — and
# `/docs/haus/rooms/creating` sends exactly that person away with "write a plain
# module in your own config", after teaching the `options.haus.<name>` shape a
# room uses. The names it draws from are the same well haus draws from (`kettle`,
# beside our `sound`, `power`, `lock`, `zen`, `tour`), so the collision that is
# live today is with a FUTURE haus release, on a machine that installed nothing
# from anyone.
#
# What that collision looks like was measured, not guessed
# (`notes/probes/namespace-collision.nix` in the workshop):
#
#   same leaf, both fully described   throws, naming two store paths and no author
#   same leaf, one of them bare       merges, silently
#   different leaves, one namespace   merges, silently — and this is the ordinary
#                                     shape of two rooms written independently
#
# The third row is the one to fear: it evaluates clean, the namespace holds both
# sets of leaves, and one author's `config` line steers the other's switch while
# `declarations` still names only its declarer. The loud error is the lucky case.
#
# So haus reserves a prefix it promises never to ship a room under — `haus.my.*`
# — and this file finds the namespaces that are neither haus's nor reserved, so
# the seam module can say so BEFORE a release makes it hurt. It warns; it never
# refuses. A person's own module on their own Mac is allowed to be wrong about a
# name haus might take in a year.
#
# Two rules this file exists to keep, both learned the expensive way:
#
# 1. **Reuse the surface derivation, never a paraphrase of it.** The first draft
#    of this check derived its namespace list as "`attrNames options.haus`, minus
#    the `_`-prefixed internals", which reads exactly like the rule
#    `room-registry` uses and is not it: that one filters on `internal`/`visible`,
#    and `mkRenamedOptionModule` (modules/moved.nix) leaves a hidden `haus.claude`
#    behind. The shorthand accuses a stock machine, and can't even name a file,
#    because the leaves it would name are invisible. A check that fires on a
#    stock machine is worse than no check.
# 2. **Name the file by walking every leaf**, not `<ns>.enable.declarations`:
#    only 9 of haus's 35 namespaces have an `enable` leaf at all, so keying on it
#    would name a file for a quarter of them and print `?` for the rest.
#
# The cheap-then-correct split below is this file's own: rule 1 says the
# shorthand is not the ANSWER, and it is still a perfectly good pre-FILTER,
# because whatever it lets through is re-decided by the real derivation. That
# matters because the real one costs a `optionAttrSetToDocList` walk: scoped to
# the handful of attribute names that could possibly be at issue, a stock machine
# pays for one subtree (`claude`, the rename shim) instead of all 311 options.
#
# ⚠️ That argument covers false POSITIVES only — nothing re-decides what the
# pre-filter drops — so two silences are deliberate and worth knowing before
# anyone treats this as complete cover:
#
#   haus._mine.thing        `_` is haus's own internal space (`_contrib`,
#                           `_desktop`, `_roster`), so a private room hiding in
#                           it is not reported. Nothing warns; nothing breaks
#                           either, since haus's internals are already off the
#                           public surface.
#   haus.terminal.myLeaf    a leaf added inside a namespace haus DOES ship. This
#                           is the same silent merge in the present tense rather
#                           than the future one, and it is out of scope here on
#                           purpose: catching it means comparing `declarations`
#                           per leaf and asserting one store root, which is E1's
#                           walk. E0 is about the name, not the leaf.
{
  lib,
  registry,
}:
let
  known = builtins.attrNames registry.namespaces;

  # The one promise. Anything under here is the person's own, forever.
  reserved = "my";

  # Cheap: attribute names only, nothing forced. What survives is every
  # namespace that MIGHT be unregistered — the expensive walk below decides.
  candidates =
    hausOptions:
    builtins.filter (n: !(lib.hasPrefix "_" n) && n != reserved && !(builtins.elem n known)) (
      builtins.attrNames hausOptions
    );

  # Expensive, and scoped to the candidates. `optionAttrSetToDocList` reads each
  # option's own `loc`, so a sub-attrset still renders full `haus.<ns>.<leaf>`
  # names — which is what lets this be scoped at all.
  #
  # It renders `default` and `example` too, and on a real machine those can be
  # functions of `config` — which is why this only ever reads `declarations`,
  # `internal` and `visible`. Those three are cheap and total; the other two are
  # lazy attribute values that nothing here forces. Don't "simplify" this into a
  # strict walk that reads the whole doc entry: it would evaluate a stranger's
  # option defaults from inside `warnings`, which is a config value.
  publicLeaves =
    hausOptions: ns:
    builtins.filter (o: !(o.internal or false) && (o.visible or true)) (
      lib.optionAttrSetToDocList { ${ns} = hausOptions.${ns}; }
    );

  unregistered =
    hausOptions:
    let
      row = ns: {
        namespace = ns;
        declaredBy = lib.unique (
          builtins.concatMap (o: o.declarations or [ ]) (publicLeaves hausOptions ns)
        );
      };
    in
    # A candidate with no PUBLIC leaf is a rename shim or an internal, not a
    # room: no leaf, nothing to name, nothing to say.
    builtins.filter (u: u.declaredBy != [ ]) (map row (candidates hausOptions));

  # Two readers meet this, and an earlier draft only served one of them.
  #
  # The private case is the one E0 is for: a room somebody wrote for their own
  # Mac, which should move under the reserved prefix. But a room somebody
  # PUBLISHED is supposed to claim a plain `haus.<name>` — that is what makes it
  # read like a room, and `/docs/haus/desktops/sharing` says so — and a message
  # telling that person to move it under `haus.my.` would be wrong advice at
  # every rebuild. What is actually missing there is the machine's record of
  # which input claimed the namespace, and haus cannot write one yet: that is the
  # claim table, step E1, and it is deliberately sequenced after this because a
  # format is hard to change once anyone has published into it.
  #
  # So the message names the risk, which both readers share, and splits only on
  # what to DO about it. When E1 lands, the claimed case stops reaching here at
  # all and this text loses its middle sentence.
  message =
    u:
    "haus: `haus.${u.namespace}` is not a room haus ships, and nothing here records who it "
    + "belongs to.\n"
    + "  declared by ${builtins.concatStringsSep " and " u.declaredBy}\n"
    + "Yours alone? Move it under `haus.${reserved}.` — `haus.${reserved}.${u.namespace}` — "
    + "which haus promises never to ship a room under. Somebody else's published room? Then a "
    + "plain name is correct, and what is missing is this machine's record of the claim, which "
    + "haus cannot write yet. Either way the risk is the same: a haus release that takes this "
    + "name meets the declaration above, and the likely outcome is not an error — two modules "
    + "declaring different leaves under one namespace merge in silence, one room's switch "
    + "steering the other's.";
in
{
  inherit
    reserved
    candidates
    unregistered
    message
    ;

  # Every message this machine has, ready for `warnings`.
  warningsFor = hausOptions: map message (unregistered hausOptions);
}

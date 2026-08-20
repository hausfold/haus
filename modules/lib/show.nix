# What `haus show <file>` reports about one local file, as DATA.
#
# The command is the publisher's pre-share check (the workshop's
# notes/rooms-desktops.md, Acquisition step A): read a file, say what class it
# is, run the desktop checker over it, and list what it would set and what it
# leaves alone. It writes nothing and fetches nothing.
#
# This file is only the report. The RULES are ./desktop.nix's, read off the room
# registry, so "may a desktop set this?" still has exactly one answer in one
# place — the seam, the flake check, the generated host file and this command
# all ask the same function.
#
# ---- the one inference, and why it only runs in one direction ---------------
#
# The class of a source is properly a fact about how it ARRIVES: a desktop comes
# in as a `flake = false` input and a room as an ordinary flake input, which is
# why `haus add` will require an explicit `--room` and never guess. A local file
# has no arrival, so `show` has to say something about the file in front of it,
# and the safe rule is asymmetric:
#
#   code, inferred   — a function is a module. Saying so costs nothing: it
#                      cannot make the gentle data prompt appear over a source
#                      that runs as root, which is the failure that matters.
#   data, PROVED     — nothing is called a desktop because it looks like one.
#                      `failures == [ ]` is the claim, and it is the checker's.
#
# So an attrset with `imports` is not quietly reclassified as a room; it is a
# desktop that failed, and the diagnostic says which rule it broke. That reads
# better for the case it actually is — a typo in a desktop — and it keeps the
# only path to "this is safe data" running through the checker.
{ lib, registry }:
let
  desktopLib = import ./desktop.nix { inherit lib registry; };

  # The registry keys its namespaces BARE — `bar`, not `haus.bar` — while every
  # option path under them carries the prefix. Getting that wrong is silent
  # rather than loud: every leaf simply matches nothing, every room comes back
  # `null`, and the report renders as a desktop that sets a lot of options in no
  # rooms at all. It cost a build to notice, so the prefix is applied once, here.
  namespaceNames = map (n: "haus.${n}") (builtins.attrNames registry.namespaces);

  # The registry namespace a leaf belongs to: the longest declared prefix. A
  # dynamic key (`haus.roster.slack.key`) has no namespace of its own, so it
  # resolves to its container's — which is the room a person would name it in.
  namespaceOf =
    path:
    let
      hits = builtins.filter (n: n == path || lib.hasPrefix "${n}." path) namespaceNames;
    in
    if hits == [ ] then
      null
    else
      builtins.foldl' (a: b: if builtins.stringLength b > builtins.stringLength a then b else a) "" hits;

  roomOf =
    path:
    let
      ns = namespaceOf path;
    in
    if ns == null then null else registry.namespaces.${lib.removePrefix "haus." ns}.owner;

  titleOf = room: registry.rooms.${room}.title or room;
  orderOf = room: registry.rooms.${room}.order or 9999;

  # Every room a person can be sold, in the order the catalogue meets them.
  # `kind` is what tells the twelve apart from the two entries that are not
  # rooms at all (the shared surfaces and the host's own facts) — the same
  # distinction the docs renderer makes, made the same way.
  productRooms = lib.sort (a: b: orderOf a < orderOf b) (
    builtins.filter (r: (registry.rooms.${r}.kind or "room") == "room") (
      builtins.attrNames registry.rooms
    )
  );

  # A value is a branch to walk into unless it is a leaf a person set. `_type`
  # means a merge or priority instruction, which the checker refuses outright —
  # walking into one here would report its internals as settings.
  isBranch = v: builtins.isAttrs v && !(v ? _type);

  flatten =
    prefix: value:
    if isBranch value then
      lib.concatMap (k: flatten "${prefix}.${k}" value.${k}) (builtins.attrNames value)
    else
      [
        {
          path = prefix;
          value = lib.generators.toPretty { multiline = false; } value;
          room = roomOf prefix;
          namespace = namespaceOf prefix;
        }
      ];
in
{
  # `read "/abs/path.nix"` — the whole report, or the reason there isn't one.
  read =
    source:
    let
      # `deepSeq` rather than a shallow force, so a `throw` buried in a value —
      # the one error a data file can still contain — is caught HERE, with the
      # filename, rather than surfacing as a raw Nix trace out of whichever
      # consumer touched it first. `deepSeq` of a function is a no-op, which is
      # correct: a room's body is not ours to force.
      #
      # It does NOT make this total, and the difference bit once. `tryEval`
      # catches `throw` and `assert`; it does NOT catch a TYPE error, so nothing
      # below may do anything type-dependent to a value whose type it has not
      # tested. That is why each branch asks `isFunction`/`isAttrs` before it
      # touches a key, and why a list-valued file goes to the checker rather
      # than being caught up here: its diagnostic is already written, and it is
      # a better answer than "unreadable".
      attempt = builtins.tryEval (builtins.deepSeq (import source) true);
      readable = attempt.success;
      value = if readable then import source else null;

      isCode = readable && builtins.isFunction value;
      failures = if readable && !isCode then desktopLib.failures { inherit source value; } else [ ];

      sets =
        if readable && builtins.isAttrs value && value ? haus && builtins.isAttrs value.haus then
          flatten "haus" value.haus
        else
          [ ];
      touched = lib.unique (builtins.filter (r: r != null) (map (s: s.room) sets));
      touchedInOrder = lib.sort (a: b: orderOf a < orderOf b) touched;
    in
    if !readable then
      {
        file = source;
        class = "unreadable";
        ok = false;
        failures = [
          "${source}: could not be read — it does not parse, or evaluating one of its values raised an error (a `throw`, or an `assert` that did not hold)"
        ];
        sets = [ ];
        rooms = [ ];
        silent = [ ];
      }
    else if isCode then
      {
        file = source;
        class = "room";
        ok = true;
        failures = [ ];
        sets = [ ];
        rooms = [ ];
        silent = [ ];
      }
    else
      {
        file = source;
        class = "desktop";
        ok = failures == [ ];
        inherit failures sets;
        rooms = map (r: {
          room = r;
          title = titleOf r;
          count = builtins.length (builtins.filter (s: s.room == r) sets);
        }) touchedInOrder;
        # What stays the reader's. Only the product rooms: a desktop saying
        # nothing about the shared surfaces or the host bucket is not news.
        silent = map (r: {
          room = r;
          title = titleOf r;
        }) (builtins.filter (r: !(builtins.elem r touched)) productRooms);
      };
}

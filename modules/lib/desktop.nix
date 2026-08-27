# The desktop seam's structural validator.
#
# A DESKTOP is a complete, data-only answer to "what should this Mac feel
# like?" (`docs/model.md`). One host selects exactly one,
# and its whole trust story is that a person can read the file and know what it
# can do. That only holds if the shape is CLOSED — checked here, before a single
# module is evaluated:
#
#   1. it is data, not a module function — no pkgs, no lib, no config;
#   2. its only top-level key is `haus` — so it can't add a package, import a
#      module, run an activation script or reach `home-manager.*`;
#   3. every leaf it sets is a public `haus.*` option the room registry has
#      already marked desktop-safe.
#
# Rule 3 is the one that needs this file rather than a one-line attribute check.
# Safety is TRANSITIVE: `haus.roster` is desktop-safe as a container and
# `haus.roster.<name>.package` is not, so the answer depends on the whole path,
# and a dynamic key (`roster.<app>`, `displays.<uuid>`) has to be walked into
# rather than trusted because its parent was. modules/options-groups.nix marks
# each container that admits dynamic children with a NAMED validator; this file
# is where those names mean something — including the rule that separates a
# semantic display selector (`main`) from a physical panel UUID, which is the
# textbook case of one namespace holding both a desktop value and a host fact.
#
# What this is NOT: an escaping story. It stops a desktop from DECLARING code —
# no function, no activation script, no `imports` — and it keeps the leaves that
# are later executed as commands host-only. It does not sanitise every string on
# its way into a generated config. TWO desktop-safe containers take keys that
# are not a closed set, and `shellSafe` is what narrows both: `attrs-of-string`
# for the values a room writes out as shell assignments, and `launcher-items`
# for the free text after a palette address's prefix. Neither inherits that
# from being a container — each names the validator that applies it, and an
# option that later grows either shape has to do the same. There is no default
# and no third answer.
#
# Everything here returns a LIST OF FAILURES rather than throwing. The seam in
# flake.nix (`lib.checkDesktop`) is what throws; a list is what lets
# `nix flake check` diff the exact diagnostics a bad desktop produces, filename
# included, instead of proving only that something somewhere refused.
{ lib, registry }:
let
  # Every classified public option, flattened out of the registry's namespaces:
  # "haus.theme.accent" -> { desktopSafe = true; }
  options = builtins.foldl' (acc: namespace: acc // registry.namespaces.${namespace}.options) { } (
    builtins.attrNames registry.namespaces
  );
  names = builtins.attrNames options;

  metaOf = path: options.${path} or null;
  # Is this path an interior node — a group of options rather than one option?
  # `haus.bar` is, `haus.bar.enable` is not.
  hasChildren = path: builtins.any (n: lib.hasPrefix "${path}." n) names;
  # The registry spells a dynamic segment `<name>` under an attrset-valued
  # container and `*` under a list-valued one. Which one a container uses is its
  # business; a desktop just has a key here, so try both.
  wildcardOf =
    path:
    let
      found = builtins.filter (w: builtins.elem "${path}.${w}" names || hasChildren "${path}.${w}") [
        "<name>"
        "*"
      ];
    in
    if found == [ ] then null else builtins.head found;

  # A value is a leaf unless it is a plain attrset. `_type` means it already
  # carries a priority or a merge instruction, which a data-only file cannot
  # produce — but a desktop can be handed an attrset from elsewhere, so the
  # guard is cheap and the alternative is walking into `mkForce`'s internals.
  isBranch = v: builtins.isAttrs v && !(v ? _type);

  said = path: what: "${path} ${what}";

  # WHY this leaf is a host's, in the registry's own words. The generic clause
  # this replaced ("it belongs to a person or a machine") was true of the
  # identity rows and wrong about most of the rest — a `pkgs` value, a command
  # the machine runs, a region, a laptop's power behaviour — and a desktop
  # author meeting it here is at the exact moment the difference decides what
  # they do next: reach for the `…Name` half of a pair, or move the line into
  # their own host file for good.
  #
  # Same rule as a validator's: the sentence lives in the registry beside the
  # classification, and every renderer of that classification says the same
  # thing. Defaulted rather than indexed, because this file is also imported by
  # consumers pinning an older registry, and a desktop author is owed the
  # general answer rather than an evaluation error.
  hostOnlyWhy =
    meta:
    let
      why = registry.hostOnlyReasons.${meta.reason or ""}.why or "";
    in
    if (lib.trim why) == "" then "It belongs to a person or a machine." else why;

  # The prefix haus promises never to ship a room under, from the one file that
  # says so — imported rather than spelled again, because a promise with two
  # copies is a promise that can be half kept.
  reservedPath = "haus.${(import ./namespaces.nix { inherit lib registry; }).reserved}";

  # ---- the walk --------------------------------------------------------------
  # One value at one option path. Everything below is a case of this.
  walk =
    path: value:
    let
      meta = metaOf path;
    in
    if builtins.isAttrs value && value ? _type then
      # `mkForce`, `mkIf`, `mkMerge` — hand-rolled, since a data file has no
      # `lib`. Refused before anything else looks at the path: the payload of
      # one of these is an attrset the walk below would step straight over, and
      # a desktop that could raise its own priority would not lose to the host
      # that chose it.
      [
        (said path "may not carry a merge or priority instruction — a desktop states values, and the host is what outranks them")
      ]
    else if meta == null then
      if hasChildren path then
        if isBranch value then
          descend path null value
        else
          [ (said path "is a group of options, not an option — name one of the settings under it") ]
      else if lib.hasPrefix "haus._" path then
        [ (said path "is internal wiring between rooms, not a setting a desktop may write") ]
      else if path == reservedPath || lib.hasPrefix "${reservedPath}." path then
        # The reserved prefix is the one unknown namespace haus knows the
        # meaning of, so it gets the real answer rather than "no such option".
        # Saying that here would be false in the way that costs a reader an
        # afternoon: `haus.my.*` is not a name haus forgot to declare, it is the
        # name a private room is SUPPOSED to use — and a desktop is the one place
        # it cannot appear, because a desktop is read and run by people who do
        # not have that room.
        [
          (said path "names a private room, and a desktop is a file other people run. `${reservedPath}.*` is reserved for rooms that live on one Mac and nowhere else, so nothing shared may name one — publish the room and it claims a plain `haus.<name>` like any other.")
        ]
      else
        [ (said path "is not a haus option") ]
    else if meta.desktopSafe == false then
      [
        (said path "is host-only, so a shared desktop may not set it. ${hostOnlyWhy meta}")
      ]
    else if meta.desktopSafe == "recursive" then
      validate meta.validator path value
    else if isBranch value && hasChildren path then
      descend path meta value
    else
      [ ];

  # Each key of an attrset, resolved against the registry: a named child, a
  # dynamic one, or nothing at all.
  descend =
    path: meta: attrs:
    lib.concatMap (
      key:
      let
        child = "${path}.${key}";
        wildcard = wildcardOf path;
      in
      if builtins.elem child names || hasChildren child then
        walk child attrs.${key}
      else if wildcard != null then
        # A dynamic key under a container the registry never marked recursive.
        # Fail closed: the payload could be anything, and "the parent was safe"
        # is exactly the inheritance the registry refuses to grant.
        if meta == null || meta.desktopSafe != "recursive" then
          [
            (said path "takes dynamic keys but has no recursive validator, so its payload cannot be trusted")
          ]
        else
          walk "${path}.${wildcard}" attrs.${key}
      else
        # Not a child the registry knows and not a dynamic one either. `walk`
        # rather than a message from here, so an unknown path gets the same
        # wording wherever it is reached from — including the one that says
        # `haus._contrib` is wiring rather than a typo.
        walk child attrs.${key}
    ) (builtins.attrNames attrs);

  # ---- the named validators --------------------------------------------------
  # `recursive` in modules/options-groups.nix names one of these per container.
  # A validator owns the KEY rule; the payload goes back through `walk`, so a
  # host-only leaf inside a dynamic entry is caught by the same code that
  # catches a static one.
  entries =
    { keyOk, keySaid }:
    path: value:
    if !(builtins.isAttrs value) then
      [ (said path "takes a set of entries") ]
    else
      let
        wildcard = wildcardOf path;
      in
      lib.concatMap (
        key:
        if !(keyOk key) then
          [ (said "${path}.${key}" (keySaid key)) ]
        else if wildcard == null then
          [ (said path "has no declared entry shape") ]
        else
          walk "${path}.${wildcard}" value.${key}
      ) (builtins.attrNames value);

  # An id a person picked for an app, a workspace or a focus scene. Not a fact
  # about the machine, so any ordinary name is fine — the rule exists to keep a
  # key that is really a path or a shell fragment out of a generated file. It
  # covered palette rows too until 2026-08-23, which is the bug `launcher-items`
  # below now explains: a container inherits this predicate because its keys ARE
  # plain names, never because the three beside it have plain names. A
  # LEADING DIGIT is ordinary here and the first version of this refused it:
  # `workspaces."1"` is AeroSpace's most common naming, and `1password` is a
  # real app id.
  plainId = key: builtins.match "[A-Za-z0-9][A-Za-z0-9_-]*" key != null;

  # The palette's address space, READ from the launcher room's own mirror of
  # pounce rather than restated here. `modules/launcher/item-grammar.nix` is
  # data only — no `lib`, no `config` — precisely so more than one caller can
  # import it, and a fourth hand-written copy of the grammar is the exact
  # failure its own header is about.
  itemGrammar = import ../launcher/item-grammar.nix;
  # The `assert` is item-grammar.nix's own reason for existing, pointed back at
  # this file. That list DRIFTS — pounce added `shortcut:` once already, and the
  # mirror went on calling a valid key invalid until someone noticed — and both
  # filters below key off the literal prefix. Renamed or dropped upstream, they
  # become silent no-ops and this seam starts admitting Shortcuts UUIDs into
  # shared desktops, while `pounce-item-grammar` stays green throughout: that
  # check compares the mirror to pounce and knows nothing about who reads it. So
  # the exclusion fails loudly the moment it stops excluding anything.
  #
  # Every shape a DESKTOP may name: all of pounce's but `shortcut:`. The
  # launcher-items validator below says why, and both the accept list and the
  # sentence a rejected key gets are derived from this one filter, so a prefix
  # pounce adds arrives here already admitted.
  shortcutShapes = builtins.filter (s: lib.hasPrefix "shortcut:" s) itemGrammar.shapes;
  desktopItemShapes =
    assert shortcutShapes != [ ];
    builtins.filter (s: !(lib.hasPrefix "shortcut:" s)) itemGrammar.shapes;
  # The guard goes on BOTH, and this is the one that matters: Nix is lazy, and
  # `desktopItemShapes` is forced only to build a REJECTION sentence. An assert
  # there alone is decorative — measured, on the drift it is meant to catch —
  # because the accept path never reaches it. `desktopItemPrefixes` is what
  # `keyOk` forces for every item key a desktop writes, so that is where a
  # renamed prefix has to stop being silent.
  desktopItemPrefixes =
    assert shortcutShapes != [ ];
    builtins.filter (p: p != "shortcut:") itemGrammar.prefixes;
  hasItemPrefix = key: builtins.any (p: lib.hasPrefix p key) desktopItemPrefixes;
  desktopItemExpected =
    let
      n = builtins.length desktopItemShapes;
      init = builtins.genList (i: builtins.elemAt desktopItemShapes i) (n - 1);
    in
    "(expected "
    + builtins.concatStringsSep ", " init
    + " or "
    + builtins.elemAt desktopItemShapes (n - 1)
    + ")";

  # No quote, backslash, dollar, backtick, newline or tab. Not a general
  # escaping story — a desktop's strings reach generated shell and JSON in
  # several rooms — but the characters that turn a value into syntax wherever
  # it lands.
  shellSafe = s: builtins.match "[^\"'\\$`\n\t]*" s != null;

  validators = {
    roster-entries = entries {
      keyOk = plainId;
      keySaid = _: "is not a plain app id";
    };
    workspace-entries = entries {
      keyOk = plainId;
      keySaid = _: "is not a plain workspace name";
    };
    # A row of the palette, keyed by the ADDRESS pounce dispatches on rather
    # than by a bare word. This was `plainId` until 2026-08-23 and could not
    # match a single real key: every address carries a colon
    # (`mode:filesearch`, `cmd:emoji`, `app:/Applications/Ghostty.app`), so no
    # desktop could set an item at all — and the diagnostic told its author
    # their key "is not a plain item id", a rule the option's own examples all
    # break. Three containers next to each other legitimately want plain ids;
    # this one never did, and inheriting their predicate is how it got one.
    #
    # What the seam decides is which KINDS of address a shared file may name.
    # Whether a well-formed one exists on the machine is the launcher room's
    # own assertion (`itemKeyProblem`), which runs on the MERGED config and so
    # covers a desktop's keys and a host's identically — `mode:nonsense` from
    # either fails the same build with the same sentence. Splitting it the
    # other way would put a second, weaker copy of the grammar here and leave
    # the room's message unreachable for exactly the files that need it most.
    #
    # `shortcut:<uuid>` is the one shape refused, and it is the display-UUID
    # argument again: it names one entry in one Mac's Shortcuts library, which
    # is a fact about that machine rather than a taste anyone can share, and it
    # is unreadable to every reader but its author — the property that makes a
    # desktop worth reading. The other four are tastes ("the file search
    # window", "the emoji row", "the Appearance pane", "the app in
    # /Applications"), and each is simply inert when the thing it names is
    # absent, the same way `cmd:` naming a command this machine hasn't got is.
    #
    # The shape rule does not replace `shellSafe`, it sits beside it. Every
    # sibling container here keeps a syntax character out of its key —
    # `plainId` does it for the three that take plain names, and free-form
    # values go through `shellSafe` — and a desktop is precisely the untrusted
    # file that rule exists for. A prefix test alone would admit
    # `mode:"; $(…); "`, which pounce's own JSON survives and the sentence a
    # renderer writes beside it does not. Cheap, and the seam says the
    # constraint rather than relying on today's one consumer escaping properly.
    launcher-items = entries {
      keyOk = key: hasItemPrefix key && shellSafe key;
      keySaid =
        key:
        if lib.hasPrefix "shortcut:" key then
          "names one entry in one Mac's Shortcuts library, which is a fact about that machine rather than a taste a desktop can share"
        else if !(hasItemPrefix key) then
          "is not an item key ${desktopItemExpected}"
        else
          "may not contain quotes, backslashes, `$`, backticks, newlines or tabs";
    };
    # A scene's key is what a person types after `focus scene`, so it has to
    # survive a shell word as-is. `quiet` is refused separately, by the focus
    # room's own assertion — it is a real name that means something else, not a
    # malformed one, and it has to fail the same way for a host as for a
    # desktop.
    scene-entries = entries {
      keyOk = plainId;
      keySaid = _: "is not a plain scene name";
    };
    # A pill on the bar, keyed by the name it is drawn under — the bundled ones
    # a desktop wants to move or retune, and, in the shape of the option though
    # not in what a desktop can reach, a new one. The KEY has to be a plain id
    # because it becomes a SketchyBar item name, which is a bare word in every
    # generated `--add item <name> <side>` line.
    #
    # The payload goes back through `walk` like every other validator, which is
    # what makes `widgets.<name>.command` host-only mean something here rather
    # than in a second rule: a desktop may say where a pill sits, how often it
    # runs and whether it is drawn at all, and the one leaf it cannot write is
    # the script the bar executes. So a shared desktop can turn the whole bar
    # into its own arrangement of the pills haus ships and still cannot add a
    # timer that runs code — which is the same line `keys.leaderExtras.*.command`
    # and `focus.scenes.<name>.hooks` already draw, in the room that finally
    # made the surface open.
    widget-entries = entries {
      keyOk = plainId;
      keySaid = _: "is not a plain widget name";
    };
    # The whole desktop/host split in one option. `internal` and `main` say
    # WHICH SCREEN YOU MEAN in words that are true on any Mac; a UUID names one
    # physical panel on one desk, which is a hardware fact and belongs to a host
    # (`docs/model.md`). So a desktop may say "make the built-in panel
    # larger" and may not mention the monitor at the office.
    display-selectors = entries {
      keyOk =
        key:
        builtins.elem key [
          "internal"
          "main"
        ];
      keySaid =
        _:
        "names a physical display, which is a fact about one machine — a desktop may only use the `internal` and `main` selectors";
    };
    # A list of submodules (leader extras, snippets, tour steps). The list is
    # ONE value as far as this walk is concerned — the fields inside its
    # elements are what get checked. (What a HOST then does to that list is
    # `prioritize`'s business, and it replaces rather than appends; see there.)
    submodule-list =
      path: value:
      if !(builtins.isList value) then
        [ (said path "takes a list") ]
      else
        lib.concatMap (
          element:
          if !(builtins.isAttrs element) then
            [ (said path "takes a list of settings") ]
          else
            lib.concatMap (field: walk "${path}.*.${field}" element.${field}) (builtins.attrNames element)
        ) value;
    # A free attrset of strings: no options underneath, so BOTH halves are
    # checked here or not at all — and the keys are the half that is easy to
    # forget. `haus.bar.media.icons` is written out as a double-quoted shell
    # assignment in a generated file the bar's plugins source, so a key holding
    # a quote or a `$( )` would be code, arriving from a file whose whole
    # promise is that it holds none. Nothing else in the desktop-safe surface
    # takes free-form keys today; when something does, it inherits this rule by
    # naming this validator.
    attrs-of-string =
      path: value:
      if !(builtins.isAttrs value) then
        [ (said path "takes a set of strings") ]
      else
        lib.concatMap (
          key:
          if !(shellSafe key) then
            [ (said "${path}.${key}" "may not contain quotes, backslashes, `$`, backticks, newlines or tabs") ]
          else if !(builtins.isString value.${key}) then
            [ (said "${path}.${key}" "must be a string") ]
          else if !(shellSafe value.${key}) then
            [
              (said "${path}.${key}" "may not contain quotes, backslashes, `$`, backticks, newlines or tabs")
            ]
          else
            [ ]
        ) (builtins.attrNames value);
  };

  validate =
    name: path: value:
    if validators ? ${name} then
      validators.${name} path value
    else
      # The registry named a validator this file does not implement. Refusing is
      # the only safe answer: the alternative is a container that reads as
      # checked and is not.
      [ (said path "names the unknown validator `${name}`, so its payload cannot be admitted") ];

  # ---- the closed shape ------------------------------------------------------
  # Named separately from "some other key", because these are the four a person
  # reaches for when they are trying to make a desktop do more than a desktop
  # does, and a message that says what to do instead is worth four lines.
  bannedKeys = {
    imports = "may not import modules — a desktop is one file's worth of values, and what it can reach has to be readable from that file alone";
    _module = "may not set module-system internals";
    _file = "may not claim another file's name";
    system = "may not set `system.*` (activation scripts, macOS defaults nothing declares) — those are a host's, or a room's";
    home-manager = "may not set `home-manager.*` — a desktop configures rooms, and rooms configure home";
    environment = "may not set `environment.*` — installing something is a room's job, and `haus.roster` is how a desktop asks for one";
    nixpkgs = "may not set `nixpkgs.*`";
  };
in
{
  # The named validators this file implements, for the check that holds the
  # three lists in step: what the registry NAMES (`recursive`), what it
  # EXPLAINS (`validators`), and what is actually here. `validate` already fails
  # closed on a name it doesn't know, so the missing direction is caught at
  # evaluation — but only on a desktop that happens to set that container, and
  # only on the consumer's machine. Exporting the names lets `nix flake check`
  # answer it for every container at once, in haus's own tree, which is where a
  # registry mistake is cheap to fix.
  validatorNames = builtins.attrNames validators;

  # Every reason this value is not a desktop, most structural first. Empty means
  # it is one.
  failures =
    {
      source,
      value,
    }:
    let
      at = message: "${source}: ${message}";
    in
    if builtins.isFunction value then
      [
        (at "is a function, so it is not a desktop. A desktop takes no arguments — no pkgs, no lib, no config — and evaluates to { haus = { … }; }. Something that genuinely needs pkgs is a room, with the trust that implies.")
      ]
    else if !(builtins.isAttrs value) then
      [ (at "does not evaluate to a set of settings — a desktop is { haus = { … }; }") ]
    else
      let
        stray = builtins.filter (k: k != "haus") (builtins.attrNames value);
        strayFailures = map (
          k: at "${bannedKeys.${k} or "sets `${k}` outside `haus`, and a desktop may set nothing else"}"
        ) stray;
        missingHausFailures = lib.optional (!(value ? haus)) (
          at "has no `haus` settings — a desktop is { haus = { … }; }"
        );
        body = value.haus or { };
        bodyFailures =
          if !(builtins.isAttrs body) then
            [ (at "`haus` must be a set of settings") ]
          else
            map at (descend "haus" null body);
      in
      strayFailures ++ missingHausFailures ++ bodyFailures;

  # The desktop's values, each leaf carried in at `priority`. Per LEAF, which is
  # the same trick the Apps room's `packEntries` turns on a saved app
  # collection, and for the same reason: a priority applied at or above an option
  # REPLACES the definition, so one normal-priority line in a host would outrank
  # the desktop's whole `roster` rather than its one field. Below the leaf you
  # set a priority; at or above it you set a value.
  #
  # A LIST is one leaf, and that is a decision rather than an accident. Two
  # definitions of a list-valued option normally CONCATENATE — so an untouched
  # desktop list would be un-removable, and a host that wanted three of the
  # desktop's four leader extras would have no way to say so. Priced against
  # each other, "the host restates the list it wants" beats "the host cannot
  # drop an entry", and it is the same rule as every other option here: the host
  # says something, the host's value is what you get. So a host that names
  # `keys.leaderExtras` at all REPLACES the desktop's, rather than appending to
  # it — worth knowing before step 4 moves real lists into a desktop, and
  # pinned by a row in `desktop-seam`.
  prioritize =
    priority: body:
    let
      go =
        value: if isBranch value then builtins.mapAttrs (_: go) value else lib.mkOverride priority value;
    in
    if builtins.isAttrs body then builtins.mapAttrs (_: go) body else body;
}

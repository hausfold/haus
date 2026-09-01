# Extension points — how one room contributes a feature to another.
#
# The contract (`docs/model.md`, "Rooms cooperate"): rooms may talk to
# other rooms, but never by reaching into each other's config and never by
# switching each other on. The RECEIVING room declares an extension point; the
# SOURCE room writes to it; the receiver renders whatever it finds there inside
# its own enable gate. So a missing receiver removes the presentation without
# disabling the source, and a source that is off leaves the receiver's own
# feature set untouched.
#
# The seam is `haus._contrib.<receiving room>.<feature>`. Leading underscore on
# the top-level segment because that is haus's convention for an internal
# tree (modules/options-doc.nix prunes them before anything is rendered) — these
# are wiring between rooms, not settings a host or a desktop may write. Setting
# one by hand is a config error, not a supported address.
#
# Why an option and not a plain `config.haus.<source>` read: the read makes the
# receiver depend on the source's option surface, so every renamed source option
# breaks every receiver, and nothing in the tree records that a contribution
# exists at all. A declared point is a named, typed promise with one writer and
# one reader, and it survives the source moving house — which is exactly what
# the AI room is doing.
{ lib }:
{
  # One extension point. `options` are its fields (the facts the source hands
  # over), `description` says what the receiver does with them.
  mkExtensionPoint =
    {
      description,
      options,
    }:
    lib.mkOption {
      internal = true;
      visible = false;
      default = { };
      type = lib.types.submodule { inherit options; };
      inherit description;
    };

  # The same contract, for a receiver that renders a DECK rather than one
  # feature: many rooms each write one keyed entry, and the receiver draws
  # whatever it finds without knowing who wrote it.
  #
  # `mkExtensionPoint` is the right shape when the answer is "does this room
  # want the thing at all" — one writer, one boolean, one pill. It is the wrong
  # shape the moment two rooms have something to say, because they would be
  # writing the same leaves over each other. `_contrib.permissions` is exactly
  # that case: a dozen rooms each know about one manual click a fresh machine
  # needs, and none of them knows about the others.
  #
  # The key is the SOURCE room's to choose, so make it name the room and the
  # thing ("launcher-accessibility"), never just the grant — two rooms wanting
  # Accessibility for two different apps is the normal case, and a bare
  # "accessibility" key would silently let the second one win.
  mkExtensionRegistry =
    {
      description,
      options,
    }:
    lib.mkOption {
      internal = true;
      visible = false;
      default = { };
      type = lib.types.attrsOf (lib.types.submodule { inherit options; });
      inherit description;
    };
}

# The haus agent skill, as a derivation.
#
# ONE skill, installed into whichever clients this machine runs — Claude Code,
# Codex and OpenCode all read a `<dir>/<name>/SKILL.md` of exactly this shape,
# and terminal (agentHomes) knows each one's directory. It lived under
# terminal/claude/ and was called the Claude skill until 2026-08-11; nothing in
# its content ever was.
#
# WHY THIS IS GENERATED, NOT COMMITTED
# ------------------------------------
# The obvious shape for "teach an agent about haus" is a SKILL.md someone
# writes and keeps up to date. That file is stale the first time an option is
# added, and a confidently-wrong option name costs the user a failed rebuild and
# a rollback. So the half that can drift — every `haus.*` name, type,
# default and description — is RENDERED from the module system, the same source
# the hausfold.co reference is rendered from.
#
# Because it's a derivation, it's built from the haus revision the machine has
# actually pinned. The skill on disk therefore describes the options that exist
# HERE, not the ones on upstream main — which is the whole point: an agent that
# reads latest-main docs will offer a user options their pin doesn't have.
#
# The hand-written half (SKILL.md, recipes, the consumer starter pair) is the part
# that DOESN'T drift: the edit → rebuild → rollback loop, the boundaries, the
# traps. Keep it that way — if you find yourself listing option names in prose
# here, that belongs in the generated half.
{
  pkgs,
  lib ? pkgs.lib,
}:

let
  version = lib.fileContents ../../../VERSION;

  # The same option metadata hausfold.co's reference is rendered from — one
  # evaluation, so the page and the skill can't disagree about what an option is.
  optionsJSON = import ../../options-doc.nix { inherit pkgs lib; };

  # ---- references/rooms.md: the routing layer above options.md --------------
  # `options.md` is a flat list of every leaf, and it is authoritative — but it
  # answers "what can I set" rather than "where does THIS SENTENCE go". An agent
  # handed "make my mac quiet" and 267 leaves has to reconstruct that focus is
  # a room and that the room exists at all; and nothing in the option tree says
  # the room's *behaviour* is reached through `pounce focus` rather than through
  # a setting. Both gaps are editorial, so both are answered from the registry
  # (modules/options-groups.nix) rather than from the module system, and both
  # are required there — `room-registry` fails the build on a room with no
  # `agent` block, so this page can never quietly go stale by omission.
  registry = import ../../options-groups.nix;

  roomsByOrder = lib.sort (a: b: a.order < b.order) (
    lib.mapAttrsToList (name: room: room // { inherit name; }) registry.rooms
  );

  roomSection =
    room:
    let
      ns = lib.concatMapStringsSep " · " (n: "`haus.${n}`") room.namespaces;
    in
    ''
      ## ${room.title}${lib.optionalString (room.kind != "room") " (${room.kind})"}

      ${room.blurb}

      - **Says:** ${lib.concatMapStringsSep " · " (a: "“${a}”") room.agent.asks}
      - **Options:** ${if room.namespaces == [ ] then "none" else ns} — grep `references/options.md`
      - **Runtime:** ${
        if room.agent.cli == null then
          "none — this room is configuration only, so every change is an option plus `haus rebuild`"
        else
          "`${room.agent.cli}`"
      }
    '';

  roomsMD = pkgs.writeText "haus-rooms.md" ''
    # The rooms, and which sentence goes where

    haus is a set of **rooms** — one capability each, with its own `haus.<room>.*`
    options. Route the user's request to a room FIRST, then grep
    `references/options.md` for the leaf inside it. Going straight to a flat
    option search is how an agent ends up inventing a plausible name.

    **An option changes what the machine does from the next rebuild. A runtime
    verb changes what it is doing right now.** They are not interchangeable, and
    the focus room is the clearest case: `haus set haus.focus.enable true`
    installs the switch and quiets nothing, while `focus on` quiets the Mac
    immediately and only works because the room is already enabled. Read the
    room's **Options** and **Runtime** lines and pick the one the user asked
    for.

    Where a room has a runtime verb, **prefer it over the tool it wraps.** haus's
    `focus` presses the Do Not Disturb chord *and* writes the state file, sets
    the user's Slack status, runs their hooks and repaints both bars; the
    `pounce focus` underneath it does only the press. Reaching past the room's
    verb makes you a surface that disagrees with the other three.

    ${lib.concatMapStringsSep "\n" roomSection roomsByOrder}
  '';
in
pkgs.runCommand "haus-agent-skill-${version}"
  {
    nativeBuildInputs = [ pkgs.jq ];
    meta = {
      description = "Agent skill teaching a coding agent to change a haus machine's config";
      inherit version;
    };
  }
  ''
    mkdir -p "$out/references"

    substitute ${./SKILL.md} "$out/SKILL.md" --subst-var-by hausVersion ${lib.escapeShellArg version}
    cp ${./recipes.md}          "$out/references/recipes.md"

    # The starter pair for a consumer repo: the rules in AGENTS.md, which every
    # client reads, plus the CLAUDE.md that is nothing but an @AGENTS.md import
    # (Claude Code reads only that name). Both are copied so a user who takes
    # them lands with the same one-body-many-pointers shape the family repos
    # use — a lone CLAUDE.md would be invisible to a Codex or OpenCode pane.
    cp ${./consumer-AGENTS.md}  "$out/consumer-AGENTS.md"
    cp ${./consumer-CLAUDE.md}  "$out/consumer-CLAUDE.md"

    cp ${roomsMD} "$out/references/rooms.md"

    jq -r -f ${./options-md.jq} \
      ${optionsJSON}/share/doc/nixos/options.json \
      > "$out/references/options.md"

    # A skill whose option reference silently rendered empty would be worse than
    # no skill: the agent would conclude haus has no options rather than
    # that the render broke. Fail the build instead.
    grep -q '^haus\.' "$out/references/options.md" \
      || { echo "options.md rendered no haus.* options — the render is broken" >&2; exit 1; }

    # Same rule for the routing page, and it needs its own check: rooms.md is
    # rendered from a different source (the registry, not the module system), so
    # options.md can be perfect while this one is empty. A rooms page with no
    # rooms would send every request straight back to the flat option search
    # this file exists to stop.
    grep -q '^## Focus$' "$out/references/rooms.md" \
      || { echo "rooms.md rendered no Focus room — the render is broken" >&2; exit 1; }
    # Both of these must assert something DERIVED from the registry. An earlier
    # version grepped for `pounce focus`, which the hand-written preamble also
    # contained — so it passed with every `agent.cli` set to null, proving
    # nothing about the field it was there to protect.
    #
    # 🚨 Anchored at the START of the value and deliberately NOT at its end.
    # Pinning the whole string made this a spelling test for one room's CLI
    # rather than a wiring test: haus#376 appended `· focus scene <name>|off|list`
    # to that same `agent.cli` and turned a correct change into a red build,
    # under a message saying the field isn't reaching the page when it plainly
    # is. The PREFIX is what proves the wiring — `- **Runtime:** ` followed by a
    # backtick is emitted by `roomSection` alone, and everything after it comes
    # from the registry — so a room may extend its verb list without editing
    # this file, and a room that lost its `agent.cli` still fails here.
    grep -q '^- \*\*Runtime:\*\* `focus on|off|toggle|status' "$out/references/rooms.md" \
      || { echo "rooms.md rendered no room's agent.cli — the field is not reaching the page" >&2; exit 1; }
    grep -q '^- \*\*Says:\*\* .*make my mac quiet' "$out/references/rooms.md" \
      || { echo "rooms.md rendered no room's agent.asks — the routing half is missing" >&2; exit 1; }
  ''

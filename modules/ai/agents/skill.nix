# The haus agent skill, as a derivation.
#
# ONE skill, installed into whichever clients this machine runs — Claude Code,
# Codex and OpenCode all read a `<dir>/<name>/SKILL.md` of exactly this shape,
# and this room (agentHomes, ./homes.nix) knows each one's directory. It lived under
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
# The hand-written half (SKILL.md, recipes, the VM loop, the consumer starter
# pair) is the part that DOESN'T drift: the edit → rebuild → rollback loop, the
# boundaries, the traps. Keep it that way — if you find yourself listing option
# names or a flag inventory in prose here, that belongs in the generated half or
# behind `haus --help`.
#
# THE SHAPE GUARD, AND WHY IT IS A BUILD FAILURE
# ----------------------------------------------
# A4 of the family agent-surface standard (the workshop's docs/agent-surface.md)
# fixes the shape: frontmatter that parses, a `name:` matching the directory the
# skill installs into, a description long enough to route on, and a 150-line cap
# because past that a routing document has become a man page. Every one of those
# failures is INVISIBLE at runtime — a skill with broken frontmatter installs
# fine, lists fine, and is simply never loaded, which from the user's side is
# indistinguishable from the agent not knowing haus exists. So it is a build
# failure here rather than a lint somewhere, exactly as scruff's
# script/check-skills.sh and nebelung's nix/skill.nix are.
#
# It runs on the RENDERED copy in $out, never on ./SKILL.md beside it, and that
# is haus-specific: this file is a TEMPLATE whose version line is the literal
# `@hausVersion@` and whose references/ pages do not exist next to the source.
# Checking the source would measure a file no one ever reads and would have no
# way to catch the one failure only haus can have — a substitution that silently
# stopped matching, putting `@hausVersion@` in front of a user.
#
# haus gets inline guards rather than its own script/check-skills.sh because the
# reason scruff extracted one does not hold here: scruff's CI installs Go and
# bats and no Nix at all, so a guard living in a derivation would run on a
# developer's machine and nowhere else. haus's CI runs `nix flake check`, whose
# `agent-skill` check builds this derivation, so these fire there already.
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

    # The one page an agent is told to read INSTEAD of driving this desktop. It
    # is hand-written like recipes.md — the VM loop, `screencapture -x` and the
    # TCC behaviour are measured facts about macOS, not anything the module
    # system can render — and it lives here rather than in SKILL.md because a
    # routing document that carries sixty lines of ssh has stopped routing.
    cp ${./vm.md}               "$out/references/vm.md"

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

    # ---- A4: the shape of the skill itself ----------------------------------
    # See the header for why this is a build failure and why it reads $out.
    skill="$out/SKILL.md"

    # The frontmatter, and ONLY the frontmatter. Every client routes on `name`
    # and `description`; the same words further down the body are prose.
    #
    # The close is found by LINE NUMBER inside a bounded window rather than with
    # `sed '1,/^---$/p'`, which runs to EOF when the block is never closed and
    # then hands the greps below the whole body to search. That is not
    # hypothetical here: a markdown thematic break is spelt `---` too, so an
    # unclosed block plus one horizontal rule anywhere in the prose would pass a
    # "never closed" check and let `name:`/`description:` match a sentence. Real
    # frontmatter is two keys; 12 lines is generous and still nowhere near the
    # body.
    # ⚠️ Every check from here down reads a FILE, never a pipeline, and that is
    # load-bearing rather than a style. `grep -q` and `grep -m1` exit the moment
    # they match, so `head`/`tail`/`printf` feeding one can be killed by SIGPIPE
    # mid-write; nixpkgs' setup.sh sets `-o pipefail`, so the derivation then
    # dies **exit 141 with nothing on either stream** — no guard message, no
    # clue which line. It is a race, so it passes local rebuilds and loses on a
    # loaded runner: measured 2026-09-03 on #650, twelve clean local rebuilds
    # against one red Actions run on a diff that touched no shell at all. The
    # widest window was `tail -n +2 "$skill" | head -n "$close"`, where the
    # reader wants four lines and the writer has the whole file to push. Keep
    # new guards file-fed; a pipe here is a flake nobody can debug from the log.
    [ "$(head -1 "$skill")" = '---' ] \
      || { echo "SKILL.md does not open with YAML frontmatter — no client will load it" >&2; exit 1; }
    close=$(awk 'NR > 1 && NR <= 13 && $0 == "---" { print NR; exit }' "$skill")
    [ -n "$close" ] \
      || { echo "SKILL.md frontmatter block is never closed in its first 12 lines" >&2; exit 1; }
    front=frontmatter.txt
    sed -n "2,''${close}p" "$skill" > "$front"

    # The `name:` key and the directory this installs into are two identifiers
    # for one skill — the path a client scans and the string it routes on. haus
    # writes `<client skills dir>/haus/SKILL.md` (modules/ai's agentHomes, and
    # `haus skill install` says it again in bash), so this name is not a free
    # choice: rename it and the skill installs under a name nothing asks for.
    grep -qx 'name: haus' "$front" \
      || { echo "SKILL.md has no 'name: haus' line — it must match the directory it installs into" >&2; exit 1; }

    # One PHYSICAL line, by design, and it is the most important line in the
    # file: it is what a client matches the user's words against to decide
    # whether to load the skill at all. A YAML folded scalar (`>-` plus an
    # indented body) is valid YAML that these greps would silently stop
    # checking, so the family standard says one line.
    grep -qE '^description: .{80,}' "$front" \
      || { echo "SKILL.md description is missing, too short to route on, or wrapped onto a second line" >&2; exit 1; }

    # A routing document that grew into a manual stops being read as one. haus's
    # was 286 lines when this guard was written; the detail went to references/
    # and to `haus --help`, which is where the next overflow goes too.
    lines=$(wc -l < "$skill" | tr -d ' ')
    [ "$lines" -le 150 ] \
      || { echo "SKILL.md is $lines lines; the standard caps a routing document at 150 — push detail into references/ or behind 'haus --help'" >&2; exit 1; }

    # The template trap, and the one guard here no other repo in the family
    # needs. `substitute` above fails silently in the direction that matters: a
    # renamed hole is not an error, it is a placeholder shipped to a user. Any
    # surviving `@name@` means the substitution stopped matching.
    if grep -n '@[A-Za-z][A-Za-z0-9_]*@' "$skill"; then
      echo "SKILL.md still holds an unsubstituted @placeholder@ — the substitute call above no longer matches it" >&2
      exit 1
    fi

    # Every reference page the prose sends a reader to has to be one this skill
    # ships. A dangling pointer in a routing document is the failure the whole
    # document exists to prevent, and it is invisible: the agent reads the name,
    # cannot open the file, and falls back to guessing. `this-machine.md` is the
    # deliberate exception — modules/ai renders it per HOST out of the evaluated
    # config, so it is never in this store copy (`haus skill this-machine` finds
    # the installed one).
    for ref in $(grep -o 'references/[A-Za-z0-9._-]*\.md' "$skill" | sort -u || true); do
      if [ "$ref" != references/this-machine.md ] && [ ! -f "$out/$ref" ]; then
        echo "SKILL.md points at $ref, which this skill does not ship" >&2
        exit 1
      fi
    done
  ''

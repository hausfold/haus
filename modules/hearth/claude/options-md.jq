# Renders nixosOptionsDoc's options.json into the agent-facing option reference
# that ships inside the nebelhaus Claude skill.
#
# Deliberately NOT the same rendering as nebelhaus.com's options page (which is
# rendered from the same JSON by the workshop's web/scripts/gen-options.mjs).
# That page is for a person reading top-to-bottom: prose blurbs per room, links
# into the repo, Starlight components. This one is for a model that will `grep`
# it — so it leads with a flat name index (the whole namespace in one screen,
# which is what stops an agent inventing an option that doesn't exist), then one
# uniform stanza per option with the fields on their own lines.
#
# Same source of truth either way: a description edit lands in the room's
# options.nix and both surfaces follow.

def lit:
  if type == "object" and has("_type") then (.text // (.value | tojson))
  elif type == "object" or type == "array" then tojson
  else tojson
  end;

# A value on its own line, or fenced when it spans lines — an attrset default
# rendered inline turns into an unreadable single-line blob.
def field($label; $t):
  if ($t | test("\n")) then "\($label):\n\n```nix\n\($t)\n```\n"
  else "\($label): `\($t)`\n"
  end;

def room: .key | split(".") | .[1];

# Drop the rice's internal options. nixosOptionsDoc filters an `internal = true`
# option itself but NOT the submodule children underneath it, and it strips the
# `internal` flag from its JSON — so `nebelhaus._apps.*.cask` and friends arrive
# here looking exactly like settable options. They are the resolved app roster
# the modules pass among themselves; an agent that tried to set one would write
# a host file that doesn't evaluate. The rice's convention is a leading
# underscore on the room segment, so that's what we filter on.
[
  to_entries[]
  | select(.key | startswith("nebelhaus."))
  | select((.value.loc[1] // "") | startswith("_") | not)
]
| sort_by(.key) as $opts

| "# nebelhaus.* — every option on this machine's rice\n\n"

+ "Generated from the rice's own module system at build time, so this file "
+ "describes the EXACT revision this machine is pinned to — not the latest "
+ "upstream. If an option you expect isn't here, it landed after this pin: say "
+ "so and offer `haus update`. Never set an option that isn't listed below.\n\n"

+ "Set these in `~/.config/nix/hosts/<hostname>/default.nix`, then apply with "
+ "`haus rebuild`.\n\n"

+ "## The whole namespace\n\n```\n"
+ ([ $opts[].key ] | join("\n"))
+ "\n```\n\n"

+ "## Details\n\n"

+ ( $opts
    | group_by(room)
    | map(
        "### nebelhaus.\(.[0] | room)\n\n"
        + ( map(
              "#### `\(.key)`\n\n"
              + field("type"; .value.type)
              + (if (.value | has("default"))
                 then field("default"; (.value.default | lit))
                 else "default: *none — this option must be set*\n" end)
              + (if .value.readOnly then "read-only: `true`\n" else "" end)
              + field("declared in"; ((.value.declarations // []) | join(", ")))
              + "\n"
              + ((.value.description // "*(undocumented)*") | sub("\n+$"; ""))
              + "\n"
              + (if (.value | has("example"))
                 then "\nexample:\n\n```nix\n\(.value.example | lit)\n```\n"
                 else "" end)
            )
            | join("\n")
          )
      )
    | join("\n")
  )

# Renders nixosOptionsDoc's options.json into an ANNOTATED HOST FILE — every
# `haus.*` option, at its default, with its description and a docs link,
# all commented out.
#
# The shape is stolen from AeroSpace's default config, which ships every setting
# at its default with a comment above it: you learn the surface by reading your
# own config, and you make it minimal by deleting the lines you never touched.
# No doc site round-trip to find out what exists.
#
# WHY EVERY LINE IS COMMENTED OUT — the one place this DIFFERS from AeroSpace,
# and it is load-bearing. A file that spelled out every option at its default
# would cost you both of the things a host file is for:
#
#   - It would OVERRIDE your whole desktop, silently. A host's plain assignment
#     outranks the desktop it selected (that is the point of the ladder), so a
#     file restating every default would beat every choice the desktop made —
#     `haus.appearance.largePrint = true` would still leave `ui.scale` at the
#     1.0 this file spelled out, on an option you never meant to set.
#   - It would FREEZE the defaults it states. The rice's own defaults are
#     `lib.mkDefault`s, so a plain restatement wins over them permanently: a
#     later rice that retunes that default can never reach you, and nothing
#     says so.
#
# Commented out, the same file is inert until you uncomment a line, which is
# exactly the "delete what you didn't change" ergonomics without either cost.
#
# Two renderings of the same JSON exist beside this one and are deliberately
# different: nebelhaus.com's page (workshop's gen-options.mjs, for reading
# top-to-bottom) and the agent skill's reference (hearth/agents/options-md.jq,
# for grepping). This one is for a file you EDIT.
#
# Inputs:
#   options.json          on stdin / as the file argument
#   --slurpfile groups    groups.json (options-groups.nix registry)
#   --arg riceVersion     the rice VERSION, stamped into the header

def lit:
  if type == "object" and has("_type") then (.text // (.value | tojson))
  elif type == "object" or type == "array" then tojson
  else tojson
  end;

# Greedy word wrap to $w columns, as an array of lines. Descriptions arrive
# already hard-wrapped by hand in the .nix sources and are passed through
# untouched; this is for the machine-generated strings (a `one of "a", "b", …`
# type runs past 200 characters and would otherwise be one unreadable line).
def wrap($w):
  [splits("[ \t\n]+")]
  | map(select(length > 0))
  | reduce .[] as $word (
      [];
      if length == 0 then [ $word ]
      elif ((.[-1] | length) + 1 + ($word | length)) <= $w then (.[0:-1] + [ .[-1] + " " + $word ])
      else . + [ $word ]
      end
    )
  | if length == 0 then [ "" ] else . end;

# Re-wrap only prose that needs it. Most descriptions are hand-wrapped in their
# .nix source at a sensible width and some of them lay out lists or tables that
# a blind re-wrap would destroy; a few (the sill pills) are authored as one
# 800-character line. So: leave a paragraph alone unless it has a line that's
# actually too long, and only then reflow the whole thing.
def softwrap($w):
  if ([ splits("\n") ] | map(length) | max // 0) > $w
  then (wrap($w) | join("\n"))
  else .
  end;

# Comment a block of text at a given indent. Blank lines become a bare "#" so a
# stanza reads as one comment block rather than as fragments separated by voids.
def commented($indent):
  split("\n")
  | map(if (. | test("^[ \t]*$")) then ($indent + "#") else ($indent + "# " + .) end);

# Starlight slugifies `### \`haus.theme.accent\`` by lowercasing and
# dropping everything that isn't alphanumeric — so the dots and the backticks
# vanish. Verified against the links already in the docs site
# (/reference/options/#nebelhauspouncewindowswitcher).
def slug: ascii_downcase | gsub("[^a-z0-9]"; "");

def room: .key | split(".")[1];

# Room blurbs are markdown, because the docs page renders them as-is. A Nix
# comment can't click a link, so `[your host file](/internals/flakes/#…)` becomes
# `your host file` — the sentence survives, the URL noise doesn't.
def demarkdown: gsub("\\[(?<t>[^\\]]*)\\]\\([^)]*\\)"; .t);

# A default that teaches nothing about the option's shape. For those — and only
# those — the example is worth the extra lines, because `haus.apps = { }`
# on its own tells you nothing about what goes inside.
def uninformative($d): ($d | ltrimstr(" ") | rtrimstr(" ")) as $t
  | ($t == "{ }") or ($t == "[ ]") or ($t == "null") or ($t == "\"\"") or ($t == "{}") or ($t == "[]");

# Submodule children (`haus.apps.<name>.key`, `haus.tour.steps.*.hint`)
# are documentation for what goes INSIDE an attrset option — you cannot write
# `haus.apps.<name>.key = "s";` in a host file. The parent (`haus.apps`)
# is in the list with an example that shows the whole shape, so the children are
# dropped here rather than rendered as lines that can't be uncommented.
[ to_entries[]
  | select(.key | startswith("haus."))
  | select(.key | test("<|\\*") | not)
] | sort_by(.key) as $opts

| ($groups[0].namespaces // {}) as $g

# Every namespace is registry-backed; `room-registry` rejects an unclassified
# option before this renderer runs.
| ($opts | group_by(room) | sort_by([ $g[.[0] | room].order, (.[0] | room) ])) as $rooms

| "# Every haus.* option on this machine's rice, at its default.\n"
+ "#\n"
+ "# GENERATED at install time from rice \($riceVersion)'s own module system, so it\n"
+ "# describes the options that exist at the revision you pinned — not upstream's\n"
+ "# latest. Regenerate it after `haus update` with:  haus options\n"
+ "#\n"
+ "# HOW TO USE IT. Everything below is commented out and the file does nothing as\n"
+ "# shipped. Uncomment a line to change that option; delete every line you never\n"
+ "# touched and you are left with a minimal host config that says only what you\n"
+ "# meant. Apply with `haus rebuild`; undo with `haus rollback`.\n"
+ "#\n"
+ "# WHY COMMENTED OUT rather than spelled out like AeroSpace's default config: a\n"
+ "# file that stated every default explicitly would silently override your whole\n"
+ "# desktop and freeze every default. A line here outranks the desktop you\n"
+ "# selected — uncomment `ui.scale` and `haus.appearance.largePrint = true` stops\n"
+ "# reaching it. And a plain value outranks the rice's own `lib.mkDefault`s for\n"
+ "# good, so a later rice that retunes that default could never reach you.\n"
+ "#\n"
+ "# Overriding your desktop is a PLAIN assignment, no `lib.mkForce` needed —\n"
+ "# that is what the priority ladder is for. Uncomment the one line you mean.\n"
+ "#\n"
+ "# Your identity, apps and secrets live NEXT DOOR in default.nix, which imports\n"
+ "# this file. Both are yours to edit; only this one is safe to regenerate.\n"
+ "#\n"
+ "# Full reference: https://nebelhaus.com/reference/options/\n"
+ "{ ... }:\n"
+ "\n"
+ "{\n"

+ ( $rooms
    | map(
        (.[0] | room) as $r
        | $g[$r] as $meta
        # 64 = 78 columns minus the "  # ═══ haus." + " " that precedes it.
        | "\n  # ═══ haus.\($r) " + ("═" * (if (64 - ($r | length)) > 3 then (64 - ($r | length)) else 3 end)) + "\n"
        + (if ($meta.blurb // "") != ""
           then (($meta.blurb | demarkdown | wrap(74) | join("\n")) | commented("  ") | join("\n")) + "\n"
           else "" end)
        + "\n"

        + ( map(
              . as $o
              | $meta.options[$o.key] as $safety
              | ($o.value.default) as $dv
              | (if $dv == null then null else ($dv | lit) end) as $default
              # Whether the rendered default can go on the right-hand side of an
              # assignment in a HOST FILE — the one question this renderer asks
              # that the other two don't. Two ways it can't:
              #
              #   literalMD      a sentence describing the default, not Nix
              #                  ("19, scaled by haus.ui.scale")
              #   mentions config.  a real expression, but one that reads the
              #                  evaluated config — a `{ ... }:` host module has
              #                  no `config` in scope, so it fails at eval.
              #
              # Both get the default as a comment and a `…` placeholder instead.
              # `…` is not valid Nix on purpose: uncommenting without filling it
              # in fails at parse, which `haus rebuild` catches before it
              # switches — loud and early beats a value that quietly means
              # something else.
              | (if $default == null then false
                 elif (($dv | type) == "object") and (($dv._type // "literalExpression") != "literalExpression") then false
                 elif ($default | test("\\bconfig\\.")) then false
                 else true end) as $pasteable
              # Descriptions run to several paragraphs; the first one says what
              # the option IS, and the rest is caveat that belongs on the docs
              # page. Carrying all of it would turn 84 options into a 2000-line
              # file nobody scrolls to the bottom of.
              | (($o.value.description // "") | split("\n\n")[0] | rtrimstr("\n") | softwrap(74)) as $desc
              | (if $desc != "" then ($desc | commented("  ") | join("\n")) + "\n" else "" end)
              + "  #\n"
              + (($o.value.type | wrap(66))
                 | to_entries
                 | map(if .key == 0 then "  # type: " + .value else "  #       " + .value end)
                 | join("\n")) + "\n"
              + "  # docs: https://nebelhaus.com/reference/options/#\($o.key | slug)\n"
              + "  # desktop data: "
              + (if $safety.desktopSafe == true then "safe"
                 elif $safety.desktopSafe == false then "host-only"
                 else "recursive (\($safety.validator))" end)
              + "\n"
              + (if ($o.value | has("example")) and ($default != null) and (uninformative($default))
                 then "  #\n"
                      + "  # example:\n"
                      + (("\($o.key) = " + ($o.value.example | lit | rtrimstr("\n")) + ";")
                         | split("\n") | map("  #   " + .) | join("\n")) + "\n"
                      + "  #\n"
                 else "" end)
              + (if $default == null
                 then "  # \($o.key) = …;   # REQUIRED — this option has no default\n"
                 elif ($pasteable | not)
                 then (("default (not a literal you can paste): " + ($default | rtrimstr("\n")))
                       | softwrap(72) | commented("  ") | join("\n")) + "\n"
                      + "  # \($o.key) = …;\n"
                 else (("\($o.key) = " + ($default | rtrimstr("\n")) + ";") | commented("  ") | join("\n")) + "\n"
                 end)
            )
            | join("\n")
          )
      )
    | join("")
  )

+ "}\n"

# Renders nixosOptionsDoc's options.json into the OFFLINE OPTIONS CATALOGUE —
# every settable `haus.*` path with the three facts an interactive picker or a
# shell completion needs, and nothing else.
#
# WHY IT EXISTS. The only other way to ask "what options are there, and what
# shape does this one take?" on a running machine is to evaluate the darwin
# config (`settings_option_exists` does exactly that, and pays seconds for it).
# That is the right authority for ACCEPTING a value and a terrible one for
# drawing a menu or answering a Tab. So the same derivation that renders the
# annotated host file drops this beside it: static, ~40 KB, read with one jq
# call, describing the revision this machine is PINNED to.
#
# It is deliberately NOT a fourth rendering of the prose (host-options.nix,
# hausfold.co and the agent skill are the three). Nothing here is meant to be
# read top-to-bottom — it's a lookup table.
#
# Shape, keyed by the full dotted path so a lookup is `.[$path]`:
#
#   "haus.theme.flavor": {
#     "type":    "one of \"mocha\", \"latte\"",   # the picker's value prompt reads this
#     "default": "\"mocha\"",                     # defaultText, as it would be written
#     "literal": true,                            # is `default` Nix you could paste?
#     "summary": "Light or dark. …"               # first line of the description
#   }
#
# Same two filters as host-template.jq's list, for the same reasons: `haus.*`
# only, and no submodule children (`haus.apps.<name>.key` documents what goes
# INSIDE an attrset — you cannot name it on a `haus set` command line).

# The default as TEXT. literalExpression carries it in `.text`; a plain value
# arrives as itself and is JSON-encoded, which is what host-template.jq's `lit`
# does too.
def defaultText:
  if . == null then null
  elif type == "object" and has("_type") then (.text // (.value | tojson))
  else tojson
  end;

# Can that text go on the right-hand side of an assignment? Two ways it can't,
# and they are host-template.jq's `$pasteable` exactly: a `literalMD` default is
# a SENTENCE describing the value ("19, scaled by haus.ui.scale"), and one that
# reads `config.` is an expression with no `config` in scope where a value gets
# typed. Both are still worth SHOWING; neither may be prefilled into a prompt as
# if the user had typed it.
def pasteable:
  if . == null then false
  elif (type == "object") and ((._type // "literalExpression") != "literalExpression") then false
  elif (defaultText | test("\\bconfig\\.")) then false
  else true
  end;

# One SHORT line, because this ends up in a menu row next to the path, and a row
# that wraps stops being a row. The first paragraph is what host-template.jq
# keeps; the first line is less than that, and even that is not always short —
# several descriptions (the bar pills) are authored as one 800-character line,
# so the hard cut is doing the real work here, not the split. Cut on a word
# boundary at 78, which leaves a 38-column path and a row inside 120.
def summary:
  (. // "")
  | split("\n")[0]
  | gsub("^\\s+|\\s+$"; "")
  | if length > 78 then ((.[0:78] | sub(" [^ ]*$"; "")) + "…") else . end;

[ to_entries[]
  | select(.key | startswith("haus."))
  | select(.key | test("<|\\*") | not)
]
| sort_by(.key)
| map({
    key: .key,
    value: {
      type: .value.type,
      default: (.value.default | defaultText),
      literal: (.value.default | pasteable),
      summary: (.value.description | summary),
    },
  })
| from_entries

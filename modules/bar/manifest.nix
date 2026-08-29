# The `# widget:` header parser (docs/bar-framework.md). A framework widget
# declares its wiring — interval, event subscriptions — in its own file, and
# this is the one reader: default.nix emits the item's block from what it
# returns, so there is no parallel table to edit and no key that can be set
# in one place and ignored in the other.
#
# Parsed at EVAL, so a bad header is a build failure that names the file and
# the key — the lesson `pounce-command-keys` teaches one repo over, enforced
# a layer earlier because here the parser and the scripts share a repo. An
# unknown key is an error, never a silent ignore: a silently-dropped
# `subscribes` is a pill that stops updating with nothing on any stream.
#
# knownKeys is exactly the set frameworkBlock CONSUMES, grown only in the
# same change that implements a key. `popup`, `permissions` and `movable`
# are planned (docs/bar-framework.md) but deliberately absent until then:
# a key that parses green and wires nothing — a `popup = menu` producing no
# popup — is the silent ignore this file's whole job is to refuse.
{ lib }:
let
  knownKeys = [
    "interval"
    "subscribes"
  ];

  splitList = s: lib.filter (x: x != "") (map lib.trim (lib.splitString "," s));
in
{
  # parse <path> -> { interval : int|null, subscribes : [str] }
  # Defaults are the manifest's, not the option system's: a widget with no
  # header at all is legal (event-driven, system_woke only).
  parse =
    path:
    let
      pathStr = toString path;
      lines = lib.splitString "\n" (builtins.readFile path);
      kvs = lib.concatMap (
        line:
        let
          m = builtins.match "#[[:space:]]*widget:[[:space:]]*([A-Za-z]+)[[:space:]]*=[[:space:]]*(.*)" line;
        in
        if m == null then
          [ ]
        else
          [
            {
              key = builtins.head m;
              value = lib.trim (builtins.elemAt m 1);
            }
          ]
      ) lines;
      unknown = lib.filter (kv: !(builtins.elem kv.key knownKeys)) kvs;
      names = map (kv: kv.key) kvs;
      dupes = lib.filter (k: lib.count (n: n == k) names > 1) (lib.unique names);
      get = key: default: (lib.findFirst (kv: kv.key == key) { value = default; } kvs).value;
      checked =
        v:
        if unknown != [ ] then
          throw "bar widget manifest ${pathStr}: unknown key '${(builtins.head unknown).key}' (known: ${lib.concatStringsSep ", " knownKeys})"
        else if dupes != [ ] then
          throw "bar widget manifest ${pathStr}: key '${builtins.head dupes}' given twice"
        else
          v;
      interval = get "interval" null;
    in
    checked {
      interval =
        if interval == null then
          null
        else if builtins.match "[0-9]+" interval != null then
          lib.toInt interval
        else
          throw "bar widget manifest ${pathStr}: interval = ${interval} (want whole seconds)";
      # system_woke is always in: every pill haus ships resubscribes to it, a
      # readout that sleeps through wake is stale by exactly how long the lid
      # was down, and no widget has yet wanted to opt out.
      subscribes = lib.unique ([ "system_woke" ] ++ splitList (get "subscribes" ""));
    };
}

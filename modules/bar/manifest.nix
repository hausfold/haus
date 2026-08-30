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
# same change that implements a key. `permissions` and `movable` are planned
# (docs/bar-framework.md) but deliberately absent until then: a key that
# parses green and wires nothing is the silent ignore this file's whole job
# is to refuse.
{ lib }:
let
  knownKeys = [
    "interval"
    "popup"
    "subscribes"
  ];

  splitList = s: lib.filter (x: x != "") (map lib.trim (lib.splitString "," s));
in
{
  # SketchyBar's OWN events — the ones its process fires. Everything else a
  # widget subscribes to is a custom event, which has to be `--add event`'d
  # before anything can subscribe to it; frameworkBlock takes the difference.
  #
  # A list rather than a prefix rule (`haus.` was the first attempt) because
  # the prefix is a naming CONVENTION and this is a correctness question: the
  # first widget converted subscribes to `github_update`, a custom event that
  # predates the convention and is fired from two places, and under a prefix
  # rule it went unadded — subscribing to an event that does not exist is
  # silent, so the pill simply never heard its own fetch land.
  #
  # Wrong in the other direction is worse and is why this is a list of names
  # rather than "anything with an underscore": `--add event volume_change`
  # would SHADOW the built-in of that name, and the pill would then only ever
  # hear the triggers it sent itself.
  builtinEvents = [
    "brightness_change"
    "display_added"
    "display_change"
    "display_removed"
    "front_app_switched"
    "media_change"
    "mouse.clicked"
    "mouse.entered"
    "mouse.exited"
    "mouse.exited.global"
    "mouse.scrolled"
    "mouse.scrolled.global"
    "power_source_change"
    "space_change"
    "space_windows_change"
    "system_will_sleep"
    "system_woke"
    "volume_change"
    "wifi_change"
  ];

  # parse <path> -> { interval : int|null, popup : bool, subscribes : [str] }
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
      popup = get "popup" "false";
    in
    checked {
      # A boolean spelled as a word, because the header is read by a person
      # before it is read by Nix. Anything else is an error rather than a
      # falsy default: `popup = yes` silently drawing no popup is the exact
      # failure this parser exists to make impossible.
      popup =
        if popup == "true" then
          true
        else if popup == "false" then
          false
        else
          throw "bar widget manifest ${pathStr}: popup = ${popup} (want true or false)";
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

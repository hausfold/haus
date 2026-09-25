# The coding-agent clients haus knows about: one directory per client, and the
# directory IS the registry. `ai.clients`, `ai.default` and bar's
# `aiUsage.provider` are typed against these names, so adding a client is a new
# `<id>/default.nix` here and dropping one is `git rm -r <id>`.
#
#   clients = import ../ai/clients;       # { claude = { package = …; … }; … }
#   ids     = builtins.attrNames clients; # sorted, which is the enum order
#
# PURE DATA, taking nothing, and that is load-bearing: modules/core imports it
# to render each client's skills directory into the `haus` wrapper
# (HAUS_AGENT_SKILL_DIRS), and core may import data, never read
# `config.haus.ai.*`. So a record is a plain attrset, and every field that needs
# `pkgs` or the room's config is a FUNCTION the AI room calls. Core reads
# `.home` and nothing else; laziness keeps the rest unevaluated there.
#
# What a record carries:
#
#   package     pkgs → the one derivation that installs it. Nothing else in haus
#               may name that derivation: a host that wants a patched build
#               overlays the nixpkgs attribute, and a second derivation of the
#               same client beside this one is two `bin/<x>` in one profile.
#   home        { instructions; skills; } — where the client keeps its
#               always-on instructions file and its skills directory, relative
#               to ~. Verified against the client, never its docs: a file
#               written where nothing reads it looks exactly like a working
#               install.
#   oneshot     the argv that runs it ONCE, headless, permission gate open,
#               `--` last; the prompt is appended. What `haus fix` runs. The
#               three rules every entry obeys are below.
#   scopeNote   which of its own files haus does NOT own, for the "this file is
#               generated" preamble of its instructions file.
#
#   floor       optional { version; message = built: "…"; } — the oldest build
#               haus will hand anyone, asserted while the client is installed.
#               A build carrying no `version` (a host's wrapper) stands down.
#   files       optional home.file entries, written whenever the AI room is on,
#               installed or not: each is inert without its client and hands
#               a hand-installed one a working pill.
#   settings    optional { name; onlyWhenInstalled; activation; } — a merge into
#               the client's OWN user-editable JSON, as `home.activation.<name>`.
#               `activation` is `{ pkgs, lib, cfg } → dag entry`, where `lib`
#               is home-manager's (it has `lib.hm`) and `cfg` is `haus.ai`.
#
# ── the one-shot argv, and the three things every entry has to get right ─────
#
# 1. NON-INTERACTIVE. A TUI in a process with no terminal is a hang, and
#    `haus-fix` is called from a trill pill and from a detached holder —
#    neither has one. scruff's own specs are the INTERACTIVE shape (a lane, a
#    window, a person), so they are not this and cannot be reused for it.
#
# 2. PERMISSIONS BYPASSED. `haus-fix` runs the agent to EDIT the config that
#    just failed to build, in a checkout it was handed; a client that stops to
#    ask about its first `Edit` is a one-shot that never finishes and nobody is
#    watching it. The boundary is the cwd plus the git commit it makes, and the
#    undo is `git -C ~/.config/nix revert HEAD` — see modules/ai/fix.sh's
#    header for why that is the boundary rather than a permission prompt.
#
# 3. `--` LAST. End-of-options, so a prompt that ever begins with a dash is a
#    prompt rather than a flag. pi is the one where this has already bitten —
#    ./pi pins ≥0.84.3 for exactly this.
#
# ── what is NOT here ────────────────────────────────────────────────────────
#
# `specFor()` in scruff (hausfold/scruff, internal/commands/agent.go) is the one
# copy that CANNOT be folded in: a Go binary can't read Nix. scruff is a flake
# input, so a new id has to land THERE first and ripple down, or every lane
# spawned with it dies on `unknown agent`.
#
# Three bash tables also branch on the id, and each falls back rather than
# failing, so a new client WORKS without them and only looks anonymous:
# modules/bar/sketchybar/plugins/ai-provider.sh (the mark: an unknown client
# gets the generic one), agents-hook.sh (env detection: the hook names its
# client explicitly anyway) and modules/launcher/commands/spawn-agent.sh (the
# namer). Worth an arm each; none is a dead pane.
let
  dir = builtins.readDir ./.;
  ids = builtins.filter (n: dir.${n} == "directory") (builtins.attrNames dir);

  required = [
    "package"
    "home"
    "oneshot"
    "scopeNote"
  ];
  known = required ++ [
    "floor"
    "files"
    "settings"
  ];

  # A record missing a field used to surface as `attribute '<id>' missing` from
  # whichever table was consulted first, naming neither file. Now it is refused
  # here, by path, the first time anything reads the record — and core reads
  # every record's `home` on every machine, so that is every eval.
  check =
    id:
    let
      record = import (./. + "/${id}");
      where = "modules/ai/clients/${id}/default.nix";
      missing = builtins.filter (f: !(record ? ${f})) required;
      unknown = builtins.filter (f: !(builtins.elem f known)) (builtins.attrNames record);
    in
    if missing != [ ] then
      throw "${where} has no ${builtins.concatStringsSep ", " missing} — modules/ai/clients/default.nix lists what every client record carries."
    else if unknown != [ ] then
      throw "${where} carries ${builtins.concatStringsSep ", " unknown}, which no room reads — a typo, or a field modules/ai/clients/default.nix does not know yet."
    else
      record;
in
builtins.listToAttrs (
  map (id: {
    name = id;
    value = check id;
  }) ids
)

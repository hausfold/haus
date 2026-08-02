# Machine-readable metadata for every `nebelhaus.*` option: type, default,
# example, description, and the file that declares it.
#
# Evaluates ONLY the per-room options files (see options-modules.nix) — not a
# darwin system — so it needs no host, no username, and no macOS. That's what
# lets nebelhaus.com's Linux CI render the options reference from it, and it
# works only because those files are pure `{ lib, ... }` modules with no
# config/pkgs dependencies. Keep them that way.
#
# Three consumers build on this: the flake's `options-json` output (which the
# docs site renders), the Claude skill's option reference (hearth/claude/skill.nix,
# which every machine installs), and the annotated host template a fresh install
# is scaffolded with (host-template.nix). One evaluation, one normalisation, so
# they can't disagree about what an option is.
#
# The output carries a SECOND file beside `options.json`: `groups.json`, the
# per-room reading order and blurbs from options-groups.nix. Those can't be
# derived from the module system (it has no notion of "identity first, policy
# last"), and shipping them in the same derivation means a renderer that already
# fetches this one needs nothing else to lay a page out.
{
  pkgs,
  lib ? pkgs.lib,
}:

let
  # Store paths mean nothing to a reader; keep the repo-relative path so each
  # rendered option can point at its source.
  #
  # Two passes, because the prefix to strip isn't the same in both callers. The
  # flake output evaluates against the flake's own source, where `toString ../.`
  # is exactly the prefix; a darwin system evaluating this same file lands on a
  # different copy of it, and the first strip is then a no-op — leaving a raw
  # /nix/store path in the rendered "declared in" line. Peeling a generic store
  # prefix afterwards makes both callers render "modules/theme/options.nix"
  # alike, which is also what makes the skill they build byte-identical.
  #
  # unsafeDiscardStringContext because a declaration is a label to print, not a
  # store reference — carrying context here only invites nix to treat the
  # rendered docs as depending on the source tree.
  #
  # The store-peeling pattern is anchored WITHOUT a leading slash on purpose:
  # `removePrefix "/"` has already run by then, so a `/nix/store/…` pattern can
  # never match — the second pass was dead code, and any declaration the first
  # strip missed would have rendered as `nix/store/<hash>-source/…`. Nothing
  # hits that today (nixpkgs' own `_module.*` options carry a plain relative
  # `_file`), which is why it went unnoticed; the anchor is fixed so the
  # documented fallback works the day something does.
  selfPrefix = toString ../.;

  relative =
    decl:
    let
      stripped = lib.removePrefix "/" (lib.removePrefix selfPrefix (toString decl));
      inStore = builtins.match "nix/store/[^/]+/(.*)" stripped;
    in
    builtins.unsafeDiscardStringContext (if inStore != null then builtins.head inStore else stripped);

  optionsEval = lib.evalModules {
    specialArgs = { inherit lib; };
    modules = import ./options-modules.nix;
  };

  # Prune the internal option trees before rendering anything.
  #
  # `internal = true` is not enough on its own: nixosOptionsDoc drops the marked
  # option but NOT the submodule children underneath it, and it strips the
  # `internal` flag from the JSON on the way out — so `nebelhaus._apps.*.cask`
  # and friends arrived downstream looking exactly like settable options, and
  # rendered onto the public reference as if they were. They aren't: `_apps` is
  # the resolved app roster the modules pass among themselves, and setting one
  # produces a host file that doesn't evaluate.
  #
  # Pruning here rather than in each renderer means every consumer — the docs
  # page, the agent skill, anything added later — is fed the same public
  # surface. The rice's convention is a leading underscore on the room segment.
  visible = optionsEval.options // {
    nebelhaus = lib.filterAttrs (name: _: !(lib.hasPrefix "_" name)) optionsEval.options.nebelhaus;
  };
  optionsJSON =
    (pkgs.nixosOptionsDoc {
      options = visible;
      warningsAreErrors = false;
      transformOptions =
        opt:
        opt
        // {
          declarations = map relative opt.declarations;
        };
    }).optionsJSON;
in
# Copied rather than symlinked so `groups.json` lands in the SAME directory as
# `options.json` — every consumer already knows that path, and a renderer that
# has one file has the other without a second store path to plumb through.
pkgs.runCommand "nebelhaus-options-json"
  {
    groupsJSON = builtins.toJSON (import ./options-groups.nix);
    passAsFile = [ "groupsJSON" ];
  }
  ''
    cp -r ${optionsJSON} "$out"
    chmod -R u+w "$out"
    cp "$groupsJSONPath" "$out/share/doc/nixos/groups.json"
  ''

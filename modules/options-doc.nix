# Machine-readable metadata for every `nebelhaus.*` option: type, default,
# example, description, and the file that declares it.
#
# Evaluates ONLY the per-room options files (see options-modules.nix) — not a
# darwin system — so it needs no host, no username, and no macOS. That's what
# lets nebelhaus.com's Linux CI render the options reference from it, and it
# works only because those files are pure `{ lib, ... }` modules with no
# config/pkgs dependencies. Keep them that way.
#
# Two consumers build on this: the flake's `options-json` output (which the docs
# site renders) and the Claude skill's option reference (hearth/claude/skill.nix,
# which every machine installs). One evaluation, one normalisation, so the two
# can't disagree about what an option is.
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
  selfPrefix = toString ../.;

  relative =
    decl:
    let
      stripped = lib.removePrefix "/" (lib.removePrefix selfPrefix (toString decl));
      inStore = builtins.match "/nix/store/[^/]+/(.*)" stripped;
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
in
(pkgs.nixosOptionsDoc {
  options = visible;
  warningsAreErrors = false;
  transformOptions =
    opt:
    opt
    // {
      declarations = map relative opt.declarations;
    };
}).optionsJSON

# The rice's public surface, as flat JSON a docs site can read without Nix.
#
# `options-json` and `wm-bindings-json` already exist and are already what the
# docs render from — but reading them means running `nix build`, which means the
# site's CI needs Nix, a flake pin and a fetch of nixpkgs just to check its own
# reference page. That was tolerable while the site lived in a repo that had Nix
# anyway; it stops being tolerable when the site moves to its own repo (the
# workshop's notes/hausfold-rename.md §5.1).
#
# The family's rule for this shape is in the workshop's notes/options-roadmap.md
# §7: *mirror only what fits in one expression and can be pinned by a golden
# test; anything table-shaped becomes an output of the repo that owns it.*
# This derivation is the output; `docs/site-data/` in this repo is the committed
# copy of it, and the `site-data-current` flake check is the pin. The site then
# reads three plain files out of a checkout, and the drift check stays here,
# next to the derivation that defines the truth.
#
# Two deliberate differences from the raw derivations:
#
#   * the option set is filtered to `haus.*`. nixosOptionsDoc also emits
#     nixpkgs' own `_module.args`, whose description text churns on every
#     nixpkgs bump — noise in a committed artifact, and never rendered anyway.
#   * everything is `jq -S`'d: sorted keys, two-space indent. The raw
#     options.json is one 148 KB line, which is unreviewable as a diff. The
#     whole point of committing it is that a human can read what moved.
{
  pkgs,
  optionsJson,
  wmBindingsJson,
}:

pkgs.runCommand "nebelhaus-site-data"
  {
    nativeBuildInputs = [ pkgs.jq ];
  }
  ''
    mkdir -p "$out"

    jq -S 'with_entries(select(.key | startswith("haus.")))' \
      ${optionsJson}/share/doc/nixos/options.json > "$out/options.json"

    # A generated cross-repo artifact fails by EMPTYING, not by erroring — the
    # lesson workshop#266 paid for, when a renderer filtering on the old
    # namespace produced a reference page with a title, an intro and zero
    # options, and the weekly cron would have opened it as a routine-looking PR.
    # If the namespace ever moves again, this is where it stops.
    #
    # The floor is zero rather than some larger round number on purpose: a
    # hardcoded "at least 150" is a second copy of the option count, and it goes
    # stale in the direction that makes it fire on an honest deletion. Zero is
    # the only threshold that means "the filter no longer matches anything".
    if [ "$(jq -r 'length' "$out/options.json")" -eq 0 ]; then
      echo "site-data: options.json has no \`haus.*\` keys." >&2
      echo "That is a broken filter, not a rice with no options — most likely the" >&2
      echo "option namespace moved and modules/site-data.nix still says \`haus.\`." >&2
      exit 1
    fi

    jq -S . ${optionsJson}/share/doc/nixos/groups.json > "$out/groups.json"
    jq -S . ${wmBindingsJson} > "$out/wm-bindings.json"
  ''

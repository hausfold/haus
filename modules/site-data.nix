# haus's public surface, as flat JSON a docs site can read without Nix.
#
# `options-json` and `wm-bindings-json` already exist and are already what the
# docs render from — but reading them means running `nix build`, which means the
# site's CI needs Nix, a flake pin and a fetch of nixpkgs just to check its own
# reference page. That was tolerable while the site lived in a repo that had Nix
# anyway; it stopped being tolerable when the site moved to its own repo
# (`hausfold/hausfold.co`, 2026-08-08).
#
# The family's rule for this shape: *mirror only what fits in one expression
# and can be pinned by a golden test; anything table-shaped becomes an output
# of the repo that owns it.*
# This derivation is the output; `docs/site-data/` in this repo is the committed
# copy of it, and the `site-data-current` flake check is the pin. The site then
# reads five plain files out of a checkout, and the drift check stays here,
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
#
# The two bar tables are the newest members and arrive a third way: not a
# derivation to filter, but the plain Nix VALUES `modules/bar/{tones,marks}.nix`
# already are, serialised straight out. They are here because the tables on
# hausfold.co's bar-widgets page were hand-copied and nothing checked them —
# the arm that used to diff `meaning` pointed at `docs/bar-framework.md`, which
# left for hausfold/ops. Publishing the list is what lets the site check its
# own page against it, which is the same trade the option reference made.
{
  pkgs,
  optionsJson,
  wmBindingsJson,
  launchKeysJson,
  barTones,
  barMarks,
}:

pkgs.runCommand "haus-site-data"
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
      echo "That is a broken filter, not haus with no options — most likely the" >&2
      echo "option namespace moved and modules/site-data.nix still says \`haus.\`." >&2
      exit 1
    fi

    jq -S . ${optionsJson}/share/doc/nixos/groups.json > "$out/groups.json"
    jq -S . ${wmBindingsJson} > "$out/wm-bindings.json"
    # NOT -S: this one is a list, and its order is the order the keys are bound
    # in. Sorting it would be sorting the answer.
    jq . ${launchKeysJson} > "$out/launch-keys.json"

    # The bar's two colour vocabularies. `-S` is safe on both despite each
    # being an ordered list — it sorts an object's KEYS, never an array's
    # elements, so the ladder's own sequence (quietest first, which the site's
    # table is meant to read top-to-bottom in) survives it. The site pins that
    # order; see modules/bar/tones.nix on why order is part of the answer.
    #
    # `stub` rides along even though it is a `test/barlib.bats` fixture and no
    # page will ever render it. Filtering here would make this file an EDITED
    # view of the ladder rather than the ladder, and the next field added to
    # tones.nix would silently not be published — the site can select the
    # columns it draws, which is a thing a reader of its snapshot can see.
    jq -S . ${pkgs.writeText "bar-tones.json" (builtins.toJSON barTones)} > "$out/bar-tones.json"
    jq -S . ${pkgs.writeText "bar-marks.json" (builtins.toJSON barMarks)} > "$out/bar-marks.json"
  ''

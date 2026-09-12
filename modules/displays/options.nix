# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
#
# displays' options — the scaled resolution of each screen, by intent.
{ lib, ... }:

{
  options.haus.displays = lib.mkOption {
    default = { };
    example = {
      internal.uiScale = "larger-text";
      "37D8832A-2D66-02CA-B9F7-8F30A301B230".uiScale = "more-space";
    };
    description = ''
      Per-display settings, keyed by which screen you mean:

        internal   the built-in panel
        main       whichever display is currently main
        <uuid>     a persistent display UUID, for a specific external monitor —
                   run `hausdisp list` to print the UUIDs of what's attached

      Default is the empty set, and then nothing about your displays is touched.
      A key naming a display that isn't plugged in right now is skipped with a
      note, not an error, so a `displays.<uuid>` entry for the monitor at the
      office can't fail a rebuild on the train.

      Why this option exists at all: display scaling is the only lever macOS 26
      gives us for "make EVERYTHING bigger", system-wide, including apps haus
      knows nothing about. macOS's own text-size setting writes a value no running
      app re-reads, while the accessibility scalars that do work affect contrast
      or motion rather than system-wide size — measured, not assumed (haus's
      `docs/macos-settings.md` records the sweep). So
      `haus.ui.scale` and `haus.fonts` make *haus's own tools* bigger, and
      this makes the *Mac* bigger.
    '';
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.uiScale = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.enum [
              "more-space"
              "default"
              "slightly-larger-text"
              "larger-text"
              "largest-text"
            ]
          );
          default = null;
          example = "larger-text";
          description = ''
            The scaled resolution, as an intent rather than a pixel count —
            the positions System Settings ▸ Displays offers, named:

              more-space            the largest resolution the panel offers
                                    (smallest UI)
              default               the panel's own default mode
              slightly-larger-text  between the default and larger-text
              larger-text           between the default and the smallest
                                    resolution
              largest-text          the smallest resolution the panel offers
                                    (biggest UI)

            Resolved per panel from the modes that panel actually reports, so the
            same value means the same *thing* on a 14" laptop and a 27" monitor
            rather than the same number of pixels. On the 14" MacBook Pro this was
            developed on that resolves to 1800x1169 · 1512x982 · 1352x878 ·
            1147x745 · 1024x665 — one name per position, matching that panel's
            five.

            `slightly-larger-text` earns its place on a big external panel, where
            the ladder is long and the jumps are not evenly spaced: a 27" 5K
            reports nine rungs, so `larger-text` lands four of them below the
            default (2560x1440 → 1440x810, a wall of pixels) while
            `slightly-larger-text` lands on 1920x1080. On a short ladder, where
            `larger-text` is already the very next rung down, the two names agree
            rather than inventing a rung that isn't there.

            Applied at each home-manager activation and set permanently, so it
            survives a reboot; re-applying an already-current mode is a no-op, so
            a rebuild doesn't flash your screen. null (the default) leaves the
            display alone.

            When more than one selector names the same attached panel, the more
            specific setting wins: UUID over internal over main. This lets a
            host-specific display setting refine a broad profile such as
            `haus.appearance.largePrint` without depending on activation order.

            Honest scope: this is a real, system-wide size change — every app gets
            bigger, not just haus's own tools — and the cost is desk space,
            because a larger UI means less of it. It also can't run from a rebuild
            with no GUI session attached (over SSH, say); the setting applies at
            the next activation you run while logged in.
          '';
        };
        options.arrangement = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.submodule {
              options = {
                side = lib.mkOption {
                  type = lib.types.enum [
                    "right-of"
                    "left-of"
                    "above"
                    "below"
                  ];
                  example = "right-of";
                  description = ''
                    Which side of the other display this one sits on.
                  '';
                };
                of = lib.mkOption {
                  type = lib.types.str;
                  example = "internal";
                  description = ''
                    Which display this one is placed beside — `internal`, `main`,
                    or a persistent display UUID, the same selectors
                    `haus.displays` is keyed by. May not name this display itself.
                  '';
                };
                align = lib.mkOption {
                  type = lib.types.nullOr (
                    lib.types.enum [
                      "top"
                      "center"
                      "bottom"
                      "left"
                      "right"
                    ]
                  );
                  default = null;
                  example = "top";
                  description = ''
                    Along the other axis: `top`/`center`/`bottom` for
                    `right-of`/`left-of`, `left`/`center`/`right` for
                    `above`/`below`. null (the default) pins the shared edge —
                    the top edge for a horizontal side, the left edge for a
                    vertical one.
                  '';
                };
              };
            }
          );
          default = null;
          example = {
            side = "right-of";
            of = "internal";
            align = "top";
          };
          description = ''
            Where this display sits relative to another, as a relation rather
            than a pixel origin — macOS's own arrangement editor, said in a way
            a desktop can write. The origin is COMPUTED at each activation from
            both panels' current point sizes, the same derived-not-tabulated
            taste as `uiScale`, so the same relation follows a scaling change
            automatically.

            Order is load-bearing: origins are in points, and a `uiScale` change
            moves every origin, so this room applies every `uiScale` entry
            before any `arrangement` entry and a profile never computes against
            a stale point size. Where two displays each carry an `arrangement`,
            the one named in `of` is placed first, so a desk can be built in
            relations; a cycle is refused at eval.

            `main` is part of what this asserts, not a separate setting:
            macOS makes a display main by putting it at the origin (0, 0), and
            a relation can put one there. When it does, that display becomes
            main. `hausdisp arrange … --dry-run` prints the origin a relation
            resolves to before you write it into the host file, and `hausdisp
            list` prints the `at x,y` to compare it against.

            An arrangement is about a desk, so it applies only while BOTH
            displays are attached: an absent one is skipped with a note, like
            an absent `uiScale`, and re-asserted at the next activation after
            the dock returns. Between activations macOS keeps its own
            remembered arrangement.
          '';
        };
      }
    );
  };
}

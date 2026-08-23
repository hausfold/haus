# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# The shelf room's options — the file shelf under the notch.
{ lib, config, ... }:

{
  options.haus = {
    shelf.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        The perch notch file shelf, installed from its own flake (copied to
        /Applications, with its `perch` command line tool linked onto PATH).
      '';
    };

    # Tracks the room, the same way developer.{git,toolbelt}.enable track
    # developer.enable. It reads `true` only where it can DO anything: every
    # line of ../shelf/default.nix sits inside `mkIf shelf.enable`, so with the
    # shelf off this switch was already inert — it just used to say `true`
    # about it, on `minimal` and `blank` alike, so `haus get`, the `haus set`
    # picker and the annotated host file all offered a knob with nothing behind
    # it. The gate is not new; only its honesty is. (Not `haus show`: it reports
    # the leaves a desktop FILE names, and no file names the leaf that argument
    # was about — it does read resolved values for the ones it reports. The
    # claim was in ../shelf/default.nix TWICE, twelve lines apart; the first
    # correction reached one of them and stated a reason wider than the fact.)
    shelf.watchScreenshots = lib.mkOption {
      type = lib.types.bool;
      default = config.haus.shelf.enable;
      defaultText = lib.literalExpression "config.haus.shelf.enable";
      description = ''
        Set this Mac up so new screenshots reach the shelf on their own.
        On with the shelf, off without it — and nothing here happens at all
        unless `haus.shelf.enable` is on, whatever this says.

        It does NOT hand perch the folder — it cannot. A watched folder is a
        security-scoped bookmark, and only perch itself can mint one, out of a
        panel you clicked; nothing written from outside the sandbox is a grant.
        What this removes is every OTHER obstacle between a capture and the
        shelf:

        - The floating preview thumbnail goes away
          (`haus.screenshots.thumbnail`, at `mkDefault`, so naming that option
          in your host puts it back). The thumbnail is not a preview of a saved
          file: macOS HOLDS the capture in the corner and writes it out only
          when the thumbnail expires (about five seconds) or you dismiss it, so
          a watched folder catches every screenshot five seconds after you took
          it.

        - Where your screenshots go is written into
          `~/.config/perch/config.json`, so perch can offer to watch that
          folder by name instead of asking you to find it — macOS will not tell
          a sandboxed app where captures are saved, and this machine already
          knows. Only when `haus.screenshots.location` says where that is: with
          it unset, haus would be guessing, and perch falls back to the Desktop
          (macOS's own answer) by itself. A perch too old to know the key
          ignores it.

        Turn it off if you would rather keep the thumbnail's markup and drag
        affordances than have screenshots shelved.
      '';
    };

    shelf.followSystemAppearance = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Let the shelf's palette follow macOS Light/Dark Mode instead of pinning
        one polarity: the shelf gets the nebelung variant AND its latte counterpart
        at your haus.theme.contrast, and picks between them itself — no
        rebuild, no relaunch.

        Same honest scope as the launcher option of the same name: with
        this on, the shelf does NOT follow haus.theme.flavor, because asking to
        follow the system says the polarity is macOS's call. The contrast axis
        still applies to both halves. Set it false to pin the shelf to
        theme.flavor like every other themed tool.

        The shelf has no theme picker of its own — it is a five-second
        surface with nowhere to put one — so this is the only word on its
        colors.
      '';
    };
  };
}

# Nebelung ports for roster apps — the other half of theming.
#
# terminal themes the tools haus INSTALLS: it knows those tools intimately, owns
# their config files, and wires each rendered theme by hand. That covers the shell,
# the terminal, the git stack, Zen, Obsidian. It cannot cover an app YOU added to
# `haus.roster`, because haus has never heard of it.
#
# This room closes that gap from the other side. nebelung publishes, per port,
# where its rendered theme has to land and what makes it active (its `ports`
# output — see nebelung's docs/ports.md). So for any roster app whose id matches a
# port, its theme files can be put where that app looks for them, in the selected
# flavor and contrast, following them on every rebuild — no per-app wiring here.
# Files, plural, for the handful of ports whose install is more than one:
# nebelung spells those `alsoPlace`, and an app handed only half of them drops
# the theme without logging anything.
#
# What it deliberately does NOT do is pretend the job is finished when it isn't.
# Dropping a file only makes a theme ACTIVE for ports whose select is "path"
# (the destination is the activation). Everything else needs one more move that
# belongs to the app or to you: a config key in a file haus doesn't own, a
# click in a Settings pane with no file interface at all. Those are placed and
# then REPORTED, via a small file `haus doctor` reads — the difference between
# "themed" and "waiting on one click" stays visible instead of turning into a
# thing you discover months later wondering why the app looks stock.
#
# Ports whose install is a merge into an existing config, or that need a compile
# step first, aren't written at all: half-applying someone's config file silently
# is worse than telling them what to do.
{
  config,
  lib,
  username,
  ...
}:

{
  config = lib.mkIf config.haus.theme.ports.enable {
    home-manager.users.${username} =
      {
        lib,
        pkgs,
        osConfig,
        nebelung,
        ...
      }:
      let
        nb = import ../lib/nebelung.nix {
          inherit lib nebelung;
          theme = osConfig.haus.theme;
        };

        # Asserting a path spelled INTO a store output, so a port the pinned
        # nebelung doesn't render stops the build instead of landing a dangling
        # symlink in ~/. This room is where that class was first fixed; the
        # helper is that fix, moved somewhere the next room can find it —
        # ../lib/checked-ref.nix has the why.
        checkedRef = import ../lib/checked-ref.nix { inherit lib pkgs; };

        # Empty on a nebelung lock that predates the `ports` output. Every use
        # below degrades to "nothing to offer" rather than failing, so being
        # pinned behind it costs the report, not the build.
        handled = osConfig.haus.theme.ports.handled;

        # Several ports render the whole accent matrix and leave the choice to
        # the consumer — nebelung spells that `<accent>` in the path (`<Accent>`
        # where the port title-cases the directory, as Zen does). hacker HAS
        # an answer: haus.theme.accent. Filling it in here is what keeps Zed
        # and friends installable instead of falling through to "do it yourself"
        # over a placeholder we could resolve. Anything still holding a
        # placeholder after this (Telegram's brace expansion) genuinely has no
        # single right answer, and stays a reported manual step.
        accent = osConfig.haus.theme.accent;
        Accent = lib.toUpper (lib.substring 0 1 accent) + lib.substring 1 (lib.stringLength accent) accent;
        resolveAccent = builtins.replaceStrings [ "<accent>" "<Accent>" ] [ accent Accent ];
        ports = lib.mapAttrs (
          _: p:
          let
            resolved = resolveAccent p.path;
          in
          p
          // {
            path = resolved;
            file = "${nb.root}/${resolved}";
            # A port's companion files get the same substitution as `path`, for
            # the same reason ../lib/nebelung.nix gives them the same flavor
            # one: a placeholder resolved on one file and left on the other is
            # a port placed half-right, which is worse than not placed at all.
            alsoPlace = map resolveAccent p.alsoPlace;
          }
        ) nb.ports;

        # Roster apps that Nebelung has a macOS port for and that no room has
        # already wired properly. Matching is by roster id == port id: the roster
        # key is the user's to choose, and naming it after the tool is what opts
        # the app in.
        chosen = lib.mapAttrs (id: _: ports.${id}) (
          lib.filterAttrs (
            id: app: app.enable && ports ? ${id} && !(builtins.elem id handled)
          ) osConfig.haus.roster
        );

        # Every file a port's install needs, `path` first. Nearly every port is
        # one file; `alsoPlace` is the handful that need a companion beside it
        # (OBS's base `.obt`, JetBrains's `.theme.json`), and placing `path`
        # alone for one of those is an app that drops the theme and logs
        # nothing — nebelung#54, which is why this list exists at all.
        files = p: [ p.path ] ++ p.alsoPlace;

        # A port this module can place unattended: a straight file copy into a
        # fixed ~/-rooted destination, with a concrete filename. Accent matrices
        # (`<accent>`) and brace expansions have no single right answer to pick,
        # and a merge/compile install isn't a copy at all.
        placeable =
          p:
          p.install == "copy"
          && p.dest != null
          && lib.hasPrefix "~/" p.dest
          # A `dest` that IS the target filename (lsd's colors.yaml, gitui's
          # theme.ron) has nowhere to put a second file — two files, one name.
          # A port with companions therefore needs a DIRECTORY dest, or it
          # falls through to the reported manual path: telling someone the
          # install is theirs beats placing one of its two halves and writing
          # "done" next to it.
          && (p.alsoPlace == [ ] || lib.hasSuffix "/" p.dest)
          # Every file, not just `path`: a placeholder left in a companion
          # would be spelled into a store path that nothing renders, and the
          # `checked` guard below would then fail the BUILD over a port that
          # should simply have been reported as manual.
          && lib.all (f: builtins.match ".*[<>{}].*" f == null) (files p);

        placed = lib.filterAttrs (_: placeable) chosen;

        # "~/.config/rio/themes/" -> ".config/rio/themes". A dest ending in "/" is
        # a directory to drop the rendered file into; anything else IS the target
        # filename (lsd's colors.yaml, gitui's theme.ron).
        relative = d: lib.removeSuffix "/" (lib.removePrefix "~/" d);
        # Trailing-slash safe, because some port paths are DIRECTORIES spelled
        # with one (qbittorrent's `themes/icons/`) and `lib.last` on those is
        # the empty string — a `home.file` name and an install path that both
        # look like a bug in this file rather than in the metadata.
        basename = p: lib.last (lib.splitString "/" (lib.removeSuffix "/" p));
        target =
          p: f: if lib.hasSuffix "/" p.dest then "${relative p.dest}/${basename f}" else relative p.dest;

        # Where the report says a port landed. One with companions names its
        # primary file and counts the rest, so the tsv can't describe a
        # two-file theme as a one-file install.
        where =
          p:
          "~/${target p p.path}"
          + lib.optionalString (p.alsoPlace != [ ]) " (+ ${toString (builtins.length p.alsoPlace)} more)";

        # What's left for a human after the file is in place. `select` is
        # nebelung's answer to "what makes this the active theme":
        #   path     nothing — being there is the activation
        #   gui      a click we have no file interface to make
        #   *        a setting in a config file haus doesn't own for this app
        remaining =
          p:
          let
            set =
              if p ? setting && p.setting ? value then
                "set ${p.setting.key} = ${p.setting.value} in its config"
              else if p ? setting then
                "set ${p.setting.key} in its config"
              else
                p.howto;
            after = lib.optionalString (p ? requires) " (then: ${lib.head p.requires})";
          in
          if p.select == "path" then
            null
          else if p.select == "gui" then
            "pick it in the app's settings${after}"
          else
            "${set}${after}";

        line =
          id: p:
          let
            left = remaining p;
            # Every rendered file, not just the first. A port that falls
            # through to manual WITH companions is one whose "copy this" means
            # two files, and naming one of them is the correct-file-beside-
            # instructions-that-name-something-else outcome
            # ../lib/nebelung.nix's own comment warns about.
            rendered = lib.concatStringsSep " and " (map (f: "${nb.root}/${f}") (files p));
          in
          if !(placeable p) then
            "manual\t${p.title}\tnot installed — ${p.howto} (rendered at ${rendered})"
          else if left == null then
            "done\t${p.title}\t${where p}"
          else
            "step\t${p.title}\tplaced at ${where p} — ${left}";

        report = lib.concatStringsSep "\n" (lib.mapAttrsToList line chosen);

        # A port whose file the pinned nebelung doesn't actually render would
        # land in ~/ as a DANGLING SYMLINK, with no error at build or
        # activation — you find it months later wondering why the app looks
        # stock, which is the exact outcome this room's header says it refuses
        # to produce. ../lib/checked-ref.nix is the whole mechanism and the
        # reason it works; what belongs HERE is why this room is the riskiest
        # place in the repo for it.
        #
        # `path` is re-spelled twice before it means anything — once for the
        # flavor (../lib/nebelung.nix, whose own comment already notes "a mocha
        # path under a latte root silently resolves to nothing") and once for
        # `<accent>` — so two substitutions neither side validates stand
        # between another repo's metadata and a real file. One ref per FILE,
        # companions included: a companion nebelung stopped rendering is the
        # same dangling symlink as a missing `path`, and the app it belongs to
        # is the half that goes quiet.
        checked = checkedRef.collect {
          name = "nebelung-ports";
          refs = lib.concatLists (
            lib.mapAttrsToList (
              id: p:
              map (f: {
                path = "${nb.root}/${f}";
                install = "${id}/${basename f}";
                problem = [
                  "haus.theme.ports: the pinned nebelung renders no port file at"
                  "  ${nb.root}/${f}"
                  "for ${p.title} (haus.roster.${id}) at flavor ${nb.flavor}, accent ${accent}."
                ];
                # Three remedies, because they belong to three different
                # people. The desktop AUTHOR bumps the pin; a CONSUMER of a
                # desktop can't — they hold the flake input transitively — so
                # name the two levers that are theirs. The haus#249 question:
                # who can this check fail on?
                remedies = [
                  "drop haus.roster.${id}, if you don't need the app themed"
                  "haus.theme.ports.enable = false, to turn the whole pass off"
                  "(haus authors) nix flake update nebelung — the port's metadata path may have moved upstream"
                ];
              }) (files p)
            ) placed
          );
        };
      in
      {
        # Every id a room claims to handle must be a port nebelung still ships,
        # or the roster pass silently starts double-wiring a tool terminal already
        # integrated properly. Skipped wholesale on an old lock, where `ports` is
        # empty and nothing is being decided from it anyway.
        assertions = lib.optional (ports != { }) {
          assertion = lib.all (id: ports ? ${id}) handled;
          message =
            let
              missing = lib.filter (id: !(ports ? ${id})) handled;
            in
            ''
              haus.theme.ports.handled names ${toString (builtins.length missing)} port(s)
              the pinned nebelung doesn't ship on macOS: ${lib.concatStringsSep ", " missing}.
              Either the port was renamed upstream (fix the name where the room
              declares it) or the room stopped wiring it (drop it from the list, so
              the roster pass picks it up again).
            '';
        };

        # One entry per FILE, so a port whose theme is two files installs whole
        # instead of landing the half the app can't use on its own. Two of a
        # port's files claiming one name can't quietly lose one here: `checked`
        # above refuses a second referent at the same install path and fails
        # the build saying so, where `listToAttrs` would take the first and
        # drop the rest in silence.
        home.file =
          lib.listToAttrs (
            lib.concatLists (
              lib.mapAttrsToList (
                id: p:
                map (f: lib.nameValuePair (target p f) { source = "${checked}/${id}/${basename f}"; }) (files p)
              ) placed
            )
          )
          # Read by `haus doctor`. Written even when empty so doctor can tell
          # "nothing in your roster has a port" apart from "this machine's haus predates the
          # feature" and say the right thing for each.
          // {
            ".config/haus/nebelung-ports.tsv".text = lib.optionalString (report != "") (report + "\n");
          };
      };
  };
}

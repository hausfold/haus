# Nebelung ports for roster apps — the other half of theming.
#
# hearth themes the tools the rice INSTALLS: it knows those tools intimately, owns
# their config files, and wires each rendered theme by hand. That covers the shell,
# the terminal, the git stack, Zen, Obsidian. It cannot cover an app YOU added to
# `nebelhaus.roster`, because the rice has never heard of it.
#
# This room closes that gap from the other side. nebelung publishes, per port,
# where its rendered theme has to land and what makes it active (its `ports`
# output — see nebelung's docs/ports.md). So for any roster app whose id matches a
# port, the theme file can be put where that app looks for it, in the selected
# flavor and contrast, following them on every rebuild — no per-app wiring here.
#
# What it deliberately does NOT do is pretend the job is finished when it isn't.
# Dropping a file only makes a theme ACTIVE for ports whose select is "path"
# (the destination is the activation). Everything else needs one more move that
# belongs to the app or to you: a config key in a file the rice doesn't own, a
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
  config = lib.mkIf config.nebelhaus.theme.ports.enable {
    home-manager.users.${username} =
      {
        lib,
        osConfig,
        nebelung,
        ...
      }:
      let
        nb = import ../lib/nebelung.nix {
          inherit lib nebelung;
          theme = osConfig.nebelhaus.theme;
        };

        # Empty on a nebelung lock that predates the `ports` output. Every use
        # below degrades to "nothing to offer" rather than failing, so being
        # pinned behind it costs the report, not the build.
        handled = osConfig.nebelhaus.theme.ports.handled;

        # Several ports render the whole accent matrix and leave the choice to
        # the consumer — nebelung spells that `<accent>` in the path (`<Accent>`
        # where the port title-cases the directory, as Zen does). nebelhaus HAS
        # an answer: nebelhaus.theme.accent. Filling it in here is what keeps Zed
        # and friends installable instead of falling through to "do it yourself"
        # over a placeholder we could resolve. Anything still holding a
        # placeholder after this (Telegram's brace expansion) genuinely has no
        # single right answer, and stays a reported manual step.
        accent = osConfig.nebelhaus.theme.accent;
        Accent = lib.toUpper (lib.substring 0 1 accent) + lib.substring 1 (lib.stringLength accent) accent;
        ports = lib.mapAttrs (
          _: p:
          let
            resolved = builtins.replaceStrings [ "<accent>" "<Accent>" ] [ accent Accent ] p.path;
          in
          p
          // {
            path = resolved;
            file = "${nb.root}/${resolved}";
          }
        ) nb.ports;

        # Roster apps that Nebelung has a macOS port for and that no room has
        # already wired properly. Matching is by roster id == port id: the roster
        # key is the user's to choose, and naming it after the tool is what opts
        # the app in.
        chosen = lib.mapAttrs (id: _: ports.${id}) (
          lib.filterAttrs (
            id: app: app.enable && ports ? ${id} && !(builtins.elem id handled)
          ) osConfig.nebelhaus.roster
        );

        # A port this module can place unattended: a straight file copy into a
        # fixed ~/-rooted destination, with a concrete filename. Accent matrices
        # (`<accent>`) and brace expansions have no single right answer to pick,
        # and a merge/compile install isn't a copy at all.
        placeable =
          p:
          p.install == "copy"
          && p.dest != null
          && lib.hasPrefix "~/" p.dest
          && builtins.match ".*[<>{}].*" p.path == null;

        placed = lib.filterAttrs (_: placeable) chosen;

        # "~/.config/rio/themes/" -> ".config/rio/themes". A dest ending in "/" is
        # a directory to drop the rendered file into; anything else IS the target
        # filename (lsd's colors.yaml, gitui's theme.ron).
        relative = d: lib.removeSuffix "/" (lib.removePrefix "~/" d);
        basename = p: lib.last (lib.splitString "/" p);
        target =
          p: if lib.hasSuffix "/" p.dest then "${relative p.dest}/${basename p.path}" else relative p.dest;

        # What's left for a human after the file is in place. `select` is
        # nebelung's answer to "what makes this the active theme":
        #   path     nothing — being there is the activation
        #   gui      a click we have no file interface to make
        #   *        a setting in a config file the rice doesn't own for this app
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
          in
          if !(placeable p) then
            "manual\t${p.title}\tnot installed — ${p.howto} (rendered at ${p.file})"
          else if left == null then
            "done\t${p.title}\t~/${target p}"
          else
            "step\t${p.title}\tplaced at ~/${target p} — ${left}";

        report = lib.concatStringsSep "\n" (lib.mapAttrsToList line chosen);
      in
      {
        # Every id a room claims to handle must be a port nebelung still ships,
        # or the roster pass silently starts double-wiring a tool hearth already
        # integrated properly. Skipped wholesale on an old lock, where `ports` is
        # empty and nothing is being decided from it anyway.
        assertions = lib.optional (ports != { }) {
          assertion = lib.all (id: ports ? ${id}) handled;
          message =
            let
              missing = lib.filter (id: !(ports ? ${id})) handled;
            in
            ''
              nebelhaus.theme.ports.handled names ${toString (builtins.length missing)} port(s)
              the pinned nebelung doesn't ship on macOS: ${lib.concatStringsSep ", " missing}.
              Either the port was renamed upstream (fix the name where the room
              declares it) or the room stopped wiring it (drop it from the list, so
              the roster pass picks it up again).
            '';
        };

        home.file =
          lib.mapAttrs' (_: p: lib.nameValuePair (target p) { source = "${p.file}"; }) placed
          # Read by `haus doctor`. Written even when empty so doctor can tell
          # "nothing in your roster has a port" apart from "this rice predates the
          # feature" and say the right thing for each.
          // {
            ".config/nebelhaus/nebelung-ports.tsv".text =
              lib.optionalString (report != "") (report + "\n");
          };
      };
  };
}

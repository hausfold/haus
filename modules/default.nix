# The whole house. `flake.nix` also wraps each named implementation partial with
# the shared declaration/data foundation so it can be imported on its own.
{
  # Options first, one file per room, each living next to the code that
  # implements it. They're listed separately from the rooms rather than
  # imported by them because several rooms wrap their whole body in
  # `lib.mkIf <room>.enable` — an option declared inside that would vanish
  # exactly when it's needed to decide the condition. modules/options.nix
  # keeps only what no single room owns: the shared app roster.
  #
  # The list itself lives in ./options-modules.nix, which is also what the
  # pure-lib option-surface evaluations import (options-json, the claude skill,
  # flake.nix's app-collections and compat checks). It used to be written out again here, and a
  # module added to one copy and not the other fails in a way that names
  # neither file: absent from this one, a real system loses the option; absent
  # from that one, only the option-surface evals do.
  imports = (import ./options-modules.nix) ++ [
    # The desktop seam: exactly one desktop per host. Nothing but an assertion
    # over what `lib.desktop` recorded — first because it is about the whole
    # selection rather than about any room's values.
    ./desktop
    # The namespace seam: a `haus.<name>` this machine declares that haus does
    # not ship and the reserved prefix does not cover. Beside ./desktop because
    # it asks the same KIND of question — one about the whole tree rather than
    # about a room — and because both can only be answered here.
    ./namespaces.nix
    # Named workspaces: resolves haus.workspaces into the internal lookup
    # ./roster folds into each app's resolved workspace membership. Comes
    # first because roster depends on it, though the module system's laziness
    # means the two could import in either order without changing anything.
    ./workspaces
    # The app roster: resolves haus.roster into the internal lists the rooms
    # below read, and installs whatever each entry names. Ungated on purpose —
    # an entry that only wants to BE installed shouldn't need the tiler on.
    ./roster
    # The editorial picks (a video player, and what opens a video), as roster
    # entries. Right after ./roster because that's all it is — a room whose
    # output is entries in the list above, plus the file types they claim.
    ./apps
    # The AI room. Pure wiring — its assertions, and the contributions it makes
    # to the terminal, the bar and the launcher through the extension points
    # those rooms declare (modules/lib/contrib.nix). Its payload is still
    # installed by ./core and ./terminal, gated on its switch; see modules/ai.
    # Early, like ./roster, because rooms below read what it publishes.
    ./ai
    # Appearance's own profile, and nothing else — it sets four other rooms'
    # options at once (`largePrint`). BEFORE them, though the module system's
    # laziness means the order changes nothing: every value it writes is a
    # `mkDefault`, so a room that sets its own, a desktop and a host all still
    # outrank it. It was presets/large-print.nix.
    ./appearance
    ./core
    ./displays
    ./theme
    # Split out of ./theme rather than folded into it: it's gated on its own
    # option and reads the app roster, not the theme's own keys.
    ./theme/ports.nix
    # The desktop picture. Its own room rather than a value on ./theme because
    # `minimal` is generated from four other rooms at once — the palette, the
    # accent, windows's gaps and the flake's lock edges.
    ./wallpaper
    ./terminal
    # Split out of ./terminal for the same reason ./theme/ports.nix is split out
    # of ./theme: it's gated on its own option, and what's INSTALLED in the
    # browser is a different job from theming the browser's chrome.
    ./terminal/zen.nix
    # And split out of THAT, one level further down: zen.nix deploys add-ons
    # other people wrote, this one BUILDS the rice's own — a Swift host, an .xpi
    # and a native-messaging manifest — and is gated on its own option again.
    ./terminal/zen-tabs
    ./windows
    ./bar
    ./security
    ./launcher
    ./shelf
    # The notification compositor. After ./shelf because it is the same shape —
    # a family app placed at a fixed /Applications path so its permission grant
    # survives a version bump — and before ./focus because quiet hours are
    # trill's, not focus's, and a reader meeting them in that order is not
    # surprised twice.
    ./notifications
    ./focus
    # The GitHub room: the machine's webhook endpoint, and the signal the bar's
    # octocat pill and the AI room's lane cache both read instead of polling.
    # After ./bar and ./ai because both write to the extension point it
    # declares, though the module system's laziness means the order is
    # editorial rather than load-bearing.
    ./github
    ./secrets
    ./snippets
    # Named .localhost URLs for dev servers. Last among the rooms because it is
    # the newest and depends on none of them: it reads haus.ai.enable only to
    # assert against a lane shim with no lanes to shim.
    ./portless
    # The local Anthropic proxy. Its options are `haus.ai.meridian.*` — the AI
    # room's address, this room's files; modules/meridian/options.nix says why.
    # After ./portless because it is the same shape one room over: an npm-only
    # service under launchd, differing only in which side of the user boundary
    # it has to run on.
    ./meridian
  ];
}

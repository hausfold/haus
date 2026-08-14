# Registry for every public `haus.*` namespace and `darwinModules` export.
#
# Everything else about an option — type, default, example, description, the
# file that declares it — comes out of the module system itself (options-doc.nix)
# and must never be restated by hand. Two things can't: the order a person should
# meet the rooms in, and what a room IS in one sentence. The module system has no
# notion of "identity first, policy last", and no place to hang a sentence that
# describes a whole namespace rather than a leaf.
#
# The editorial metadata, ownership and desktop trust boundary live here once,
# as data read by every renderer and checked against the evaluated option tree:
#
#   host-template.jq            the annotated host file a fresh install gets
#   web/scripts/gen-options.mjs nebelhaus.com's options reference (via groups.json)
#
# It used to live inside the web renderer alone, where it covered 16 of the 23
# rooms — the other seven (agents, collar, developer, displays, keys, perch, ui)
# silently fell off the end of the page in alphabetical order with no blurb.
#
# A namespace or export missing from this file IS an error. `room-registry`
# compares the exact lists below with the evaluated option tree and flake output;
# a new public leaf gets no accidental safety inheritance from its namespace.
# `order` values are spaced by ten so a room can be slotted between two others
# without renumbering the file.
#
# Blurbs are MARKDOWN — the docs page renders them as-is, and host-template.jq
# flattens `[text](link)` down to `text` on its way into a Nix comment. Written
# the other way round (plain text plus a separate link field) the page would
# have lost sentences it already had, for a link the comment can't click anyway.
let
  # Exact relative paths in the generated public surface. `""` names the
  # namespace option itself (for example `haus.displays`). Keeping these as an
  # inventory, rather than glob rules, is what makes an added leaf fail closed.
  optionPaths = {
    accessibility = [
      "differentiateWithoutColor"
      "increaseContrast"
    ];
    ai = [
      "clients"
      "default"
      "enable"
      "instructions"
      "skill"
    ];
    animations = [ "" ];
    appearance = [ "largePrint" ];
    appStore = [ "install" ];
    apps = [
      "packs.writing.enable"
      "videoPlayer.claimFileTypes"
      "videoPlayer.enable"
    ];
    collar = [
      "enable"
      "passwordlessRebuild"
    ];
    developer = [
      "enable"
      "git.enable"
      "languages"
      "toolbelt.enable"
    ];
    displays = [
      ""
      "<name>.uiScale"
    ];
    fonts = [
      "mono.baseSize"
      "mono.name"
      "mono.package"
      "mono.packageName"
      "mono.size"
    ];
    git = [
      "email"
      "name"
      "org"
      "shellAliases"
      "signingKey"
    ];
    hearth = [
      "editor"
      "floatBorder"
      "ghDash.enable"
      "hijackFileAssociations"
      "obsidianVaults"
      "rightClickFullscreen"
      "zellijStartLocked"
    ];
    homebrew = [
      "autoUpdate"
      "cleanup"
      "upgrade"
    ];
    hotCorners = [
      "bottomLeft"
      "bottomRight"
      "topLeft"
      "topRight"
    ];
    hush = [
      "enable"
      "hooks"
      "slack.enable"
      "slack.snooze"
      "slack.statusEmoji"
      "slack.statusText"
      "slack.tokenCommand"
    ];
    keys = [
      "leader"
      "leaderExtras"
      "leaderExtras.*.caption"
      "leaderExtras.*.command"
      "leaderExtras.*.key"
      "palette"
      "windowNav"
    ];
    locale = [
      "hourFormat"
      "inputSources"
      "language"
      "metric"
      "region"
      "temperature"
    ];
    lock = [
      "requirePassword"
      "requirePasswordDelay"
    ];
    menuBar = [
      "clock.analog"
      "clock.format"
      "clock.showDate"
      "clock.showDayOfWeek"
      "clock.showSeconds"
      "controlCenter.airdrop"
      "controlCenter.batteryPercentage"
      "controlCenter.bluetooth"
      "controlCenter.displayBrightness"
      "controlCenter.focus"
      "controlCenter.nowPlaying"
      "controlCenter.sound"
    ];
    perch = [
      "enable"
      "followSystemAppearance"
    ];
    pounce = [
      "autoQuit.delay"
      "autoQuit.enable"
      "autoQuit.exclude"
      "enable"
      "followSystemAppearance"
      "items"
      "items.<name>.alias"
      "items.<name>.caption"
      "items.<name>.hotkey"
      "items.<name>.listed"
      "scale"
      "signingIdentity"
      "windowMode"
      "windowSwitcher"
    ];
    power = [
      "computerSleep.battery"
      "computerSleep.charger"
      "diskSleep.battery"
      "diskSleep.charger"
      "displaySleep.battery"
      "displaySleep.charger"
      "lowPowerMode.battery"
      "lowPowerMode.charger"
    ];
    prowl = [ "enable" ];
    roster = [
      ""
      "<name>.appId"
      "<name>.appStoreId"
      "<name>.brew"
      "<name>.cask"
      "<name>.enable"
      "<name>.float"
      "<name>.installedBy"
      "<name>.key"
      "<name>.label"
      "<name>.name"
      "<name>.order"
      "<name>.package"
      "<name>.packageName"
      "<name>.scope"
      "<name>.titleRegex"
    ];
    screenshots = [
      "format"
      "includeDate"
      "location"
      "shadow"
      "thumbnail"
    ];
    secrets = [ "provider" ];
    security = [
      "firewall.allowSigned"
      "firewall.allowSignedApp"
      "firewall.blockAllIncoming"
      "firewall.enable"
      "firewall.stealthMode"
    ];
    sill = [
      "aiUsage.provider"
      "battery.hideOver"
      "bottom.enable"
      "bottom.items"
      "bottom.items.agents"
      "bottom.items.aiUsage"
      "bottom.items.battery"
      "bottom.items.caffeinate"
      "bottom.items.calendar"
      "bottom.items.clock"
      "bottom.items.cpu"
      "bottom.items.elgato"
      "bottom.items.harvest"
      "bottom.items.hush"
      "bottom.items.media"
      "bottom.items.memory"
      "bottom.items.volume"
      "bottom.items.weather"
      "bottom.items.wifi"
      "calendar.horizon"
      "calendar.imminent"
      "calendar.joinHosts"
      "calendar.me"
      "calendar.past"
      "calendar.preciseUnder"
      "calendar.refresh"
      "calendar.upcoming"
      "calendar.width"
      "clock.mode"
      "clock.monoFont"
      "elgato.host"
      "enable"
      "items"
      "items.agents"
      "items.aiUsage"
      "items.battery"
      "items.caffeinate"
      "items.calendar"
      "items.claudeUsage"
      "items.clock"
      "items.cpu"
      "items.elgato"
      "items.harvest"
      "items.media"
      "items.memory"
      "items.volume"
      "items.weather"
      "items.wifi"
      "logo.color"
      "logo.gestures"
      "logo.icon"
      "logo.size"
      "logo.status"
      "logo.sweep"
      "logo.updateCheck"
      "media.artworkTint"
      "media.collapse"
      "media.icons"
      "media.width"
      "position"
    ];
    snippets = [
      "enable"
      "matches"
      "matches.*.replace"
      "matches.*.trigger"
    ];
    sound = [
      "alertSound"
      "alertVolume"
      "startupChime"
      "uiSounds"
      "volumeFeedback"
    ];
    theme = [
      "accent"
      "contrast"
      "flavor"
      "ports.enable"
      "systemAppearance"
    ];
    tour = [
      "enable"
      "steps"
      "steps.*.detect"
      "steps.*.hint"
    ];
    ui = [ "scale" ];
    wallpaper = [
      "background"
      "debug.enable"
      "debug.inputs"
      "debug.inset"
      "debug.size"
      "depth"
      "glow.color"
      "glow.enable"
      "glow.spread"
      "glow.strength"
      "grain"
      "mark.color"
      "mark.enable"
      "mark.opacity"
      "mark.rise"
      "mark.size"
      "mark.weight"
      "size"
      "style"
    ];
    workspaces = [
      ""
      "<name>.apps"
      "<name>.icon"
      "<name>.key"
    ];
    zen = [
      "extensions"
      "extensions.<name>.enable"
      "extensions.<name>.id"
      "extensions.<name>.mode"
      "extensions.<name>.slug"
      "extensions.<name>.url"
      "extraPolicies"
      "tabBridge.enable"
    ];
  };

  # These are the exceptions to the fail-closed default for an INVENTORIED
  # option. Every other exact path above is desktop-safe. An uninventoried path
  # never reaches this decision: the registry check rejects it first.
  hostOnly = {
    ai = [ "instructions" ];
    fonts = [ "mono.package" ];
    git = optionPaths.git;
    hearth = [
      "editor"
      "obsidianVaults"
    ];
    hush = [
      "hooks"
      "slack.tokenCommand"
    ];
    keys = [ "leaderExtras.*.command" ];
    locale = optionPaths.locale;
    pounce = [ "signingIdentity" ];
    power = optionPaths.power;
    roster = [
      "<name>.installedBy"
      "<name>.package"
    ];
    screenshots = [ "location" ];
    secrets = [ "provider" ];
    sill = [
      "calendar.me"
      "elgato.host"
    ];
    zen = [
      "extensions"
      "extensions.<name>.enable"
      "extensions.<name>.id"
      "extensions.<name>.mode"
      "extensions.<name>.slug"
      "extensions.<name>.url"
      "extraPolicies"
    ];
  };

  # Containers whose payload is admitted only after a named recursive
  # validator walks it. Host-only containers need no validator because desktop
  # data cannot reach them at all.
  recursive = {
    displays."" = "display-selectors";
    keys.leaderExtras = "submodule-list";
    pounce.items = "pounce-items";
    roster."" = "roster-entries";
    sill."media.icons" = "attrs-of-string";
    snippets.matches = "submodule-list";
    tour.steps = "submodule-list";
    workspaces."" = "workspace-entries";
  };

  roomOwners = {
    accessibility = "appearance";
    ai = "ai";
    animations = "appearance";
    appearance = "appearance";
    appStore = "apps";
    apps = "apps";
    collar = "security";
    developer = "development";
    displays = "displays";
    fonts = "appearance";
    hearth = "development";
    homebrew = "apps";
    hotCorners = "windows";
    hush = "focus";
    lock = "security";
    menuBar = "bar";
    perch = "shelf";
    pounce = "launcher";
    prowl = "windows";
    screenshots = "appearance";
    secrets = "security";
    security = "security";
    sill = "bar";
    snippets = "text-expansion";
    sound = "appearance";
    theme = "appearance";
    wallpaper = "appearance";
    zen = "development";
  };
  shared = [
    "keys"
    "roster"
    "tour"
    "ui"
    "workspaces"
  ];
  host = [
    "git"
    "locale"
    "power"
  ];

  optionName = namespace: path: "haus.${namespace}" + (if path == "" then "" else ".${path}");
  optionMeta =
    namespace: path:
    if builtins.elem path (hostOnly.${namespace} or [ ]) then
      { desktopSafe = false; }
    else if (recursive.${namespace} or { }) ? ${path} then
      {
        desktopSafe = "recursive";
        validator = recursive.${namespace}.${path};
      }
    else
      { desktopSafe = true; };
  optionsFor =
    namespace:
    builtins.listToAttrs (
      map (path: {
        name = optionName namespace path;
        value = optionMeta namespace path;
      }) optionPaths.${namespace}
    );
  kindOf =
    namespace:
    if builtins.elem namespace shared then
      "shared"
    else if builtins.elem namespace host then
      "host"
    else
      "room";
  ownerOf =
    namespace: roomOwners.${namespace} or (if builtins.elem namespace host then "host" else "haus");

  groups = {
    # ---- who you are ----------------------------------------------------------
    git = {
      order = 10;
      blurb = "Your commit identity, plus the GitHub owner this machine's work lives under — set your own. It stays in [your host file](/internals/flakes/#your-config-is-a-thin-consumer).";
    };
    roster = {
      order = 20;
      blurb = "One list of everything this machine has — apps, fonts, command-line tools. Each entry drives its launcher key, cheatsheet row, and installs it from whichever source it names: a Homebrew cask or formula, a Nixpkgs package, or the Mac App Store.";
    };
    workspaces = {
      order = 21;
      blurb = "The named AeroSpace workspaces this machine declares, and which roster apps live on each. A workspace, not an app, owns its bar pill and leader throw — so several apps (a whole \"comms\" role) can share one.";
    };
    appStore = {
      order = 22;
      blurb = "Whether a rebuild may install the roster's `appStoreId` entries. Off by default: it reaches the network and acts on your Apple Account, and it can never be complete — `mas` cannot sign in, and cannot buy a paid app.";
    };
    apps = {
      order = 23;
      blurb = "The apps the rice picks for you, the saved collections you can switch on in one line, and the file types they claim — the ones a finished machine has rather than the ones a room needs to work. Each is one switch you can turn off; what it installs is a roster entry like any other, so you can retune or replace it by app id.";
    };

    # ---- how it looks ---------------------------------------------------------
    appearance = {
      order = 25;
      blurb = "The Appearance room's own profile — one named answer to a whole-machine question, where the groups below are the individual dials. `largePrint` sets the interface scale, the high-contrast palette, macOS's own contrast lift and the screen's scaled resolution together, each as a default you can still pin by hand.";
    };
    theme = {
      order = 30;
      blurb = "Colour: the palette's flavour and contrast, the accent every themed tool spends, and whether macOS's own Light/Dark follows it.";
    };
    wallpaper = {
      order = 35;
      blurb = "The desktop behind everything. `minimal` is generated on this machine — a flat field at whatever depth you pick out of the palette, the haus mark ⌂ at its centre, a bloom in your accent, and enough grain that none of it bands. The other looks are the hand-made Nebelung ones.";
    };
    fonts = {
      order = 40;
      blurb = "The terminal font. The bar keeps its own font at its own tuned sizes.";
    };
    ui = {
      order = 50;
      blurb = "One number for \"make the interface bigger\", applied across the rice's own surfaces.";
    };
    displays = {
      order = 60;
      blurb = "Per-display overrides, keyed by which screen you mean.";
    };

    # ---- the terminal, and who else drives this machine -----------------------
    hearth = {
      order = 70;
      blurb = "The shell and terminal experience.";
    };
    zen = {
      order = 75;
      blurb = "Zen browser policy, extensions and the optional native tab bridge.";
    };
    ai = {
      order = 80;
      blurb = "The AI room: whether this machine runs coding agents at all, which clients it installs, which one the agent keybinding spawns, and the two files the rice ships into every one of their homes — your instructions, and the `haus` skill. Spelled `haus.agents.*` before 2026-08-13, with the switch under `haus.developer.agents`; both are gone rather than aliased.";
    };
    # 90 was `claude`, folded into `agents` on 2026-08-11: both of its options
    # describe a file EVERY client reads, at its own path. Left free rather than
    # backfilled — the gap is cheap and renumbering the groups below isn't.

    # ---- reach ----------------------------------------------------------------
    accessibility = {
      order = 100;
      blurb = "macOS accessibility keys the rice can actually apply. These write to a TCC-protected domain, so they take effect only when the app you run the rebuild from holds Full Disk Access — otherwise the rice warns and moves on.";
    };
    keys = {
      order = 110;
      blurb = "The keys the rice owns — the leader, the palette, the window-chord modifier — and anything extra you hang off the leader.";
    };
    # ---- macOS settings groups (options-roadmap §5.6) -------------------------
    # Dense on purpose: this block ran out of the file's usual ten-wide spacing
    # when the last three groups landed, and `prowl` at 120 is the next fixed
    # point. `animations` then took 111 — the last free slot, and the last
    # squeeze available: the block is now 111–119 with no gaps, so the NEXT group added
    # here has to renumber it, from `prowl` at 120 downwards.
    animations = {
      order = 111;
      blurb = "How much motion macOS spends on its own Dock and windows: the slide, the launch bounce, minimise, Mission Control, window open/close. Unset by default like the rest of this block — `\"fast\"` opts in, and going back only stops writing rather than restoring. Deliberately not the Accessibility \"Reduce motion\" switch, which every browser also reads as `prefers-reduced-motion`.";
    };
    hotCorners = {
      order = 112;
      blurb = "What each corner of the screen does when the pointer reaches it. Every corner is unset by default, so the rice never overwrites one you set yourself.";
    };
    screenshots = {
      order = 113;
      blurb = "Where ⇧⌘4 puts its files, in what format, and whether it draws a window shadow or a preview thumbnail. Unset by default, so macOS's own choices stand.";
    };
    lock = {
      order = 114;
      blurb = "Whether waking this Mac needs a password, and how long the grace period is. Worth setting on any laptop that leaves the house.";
    };
    menuBar = {
      order = 115;
      blurb = "The stock menu bar: what the clock shows, and which Control Center glyphs sit beside it. (The nebelhaus bar itself is `sill`.)";
    };
    security = {
      order = 116;
      blurb = "Security posture: the built-in application firewall and how strict it is. Off on a fresh Mac; the setting to turn on for a laptop that joins networks you don't own.";
    };
    sound = {
      order = 117;
      blurb = "Alert volume and sound, interface sound effects, and the boot chime. Volume is 0–100 the way the slider reads it — macOS stores a curve, and the rice does the conversion.";
    };
    locale = {
      order = 118;
      blurb = "Language, region, units and keyboard layouts. What a rice in any language other than English needs — and the one room whose settings reach apps you already have open, because the rice posts the change notification macOS itself posts.";
    };
    power = {
      order = 119;
      blurb = "Sleep timers and Low Power Mode, said separately for battery and charger — which is the whole point, and why this is built on `pmset` rather than on nix-darwin's own power options.";
    };

    # ---- the rooms ------------------------------------------------------------
    prowl = {
      order = 120;
      blurb = "Tiling window management and the Caps-Lock leader launcher.";
    };
    sill = {
      order = 130;
      blurb = "The menu bar, and which pills it draws.";
    };
    pounce = {
      order = 140;
      blurb = "The ⌘Space command palette.";
    };
    perch = {
      order = 160;
      blurb = "The notch file shelf.";
    };
    hush = {
      order = 170;
      blurb = "One quiet switch: Do Not Disturb, optional Slack status, and your hooks.";
    };
    snippets = {
      order = 180;
      blurb = "Text expansion via espanso.";
    };
    tour = {
      order = 190;
      blurb = "The first-run tutor.";
    };

    # ---- policy ---------------------------------------------------------------
    developer = {
      order = 200;
      blurb = "The developer pack: the CLI toolbelt, Git tooling and language runtimes. Coding agents left this pack on 2026-08-13 and are their own room now (`haus.ai.*`). Off is a nebelhaus machine for someone who never opens a terminal by choice.";
    };
    collar = {
      order = 210;
      blurb = "Touch ID for sudo — including inside a terminal multiplexer — and the passwordless-rebuild rule.";
    };
    secrets = {
      order = 220;
      blurb = "Where secret values come from on this machine.";
    };
    homebrew = {
      order = 230;
      blurb = "How rebuilds treat Homebrew packages you did not declare.";
    };
  };
in
{
  schemaVersion = 1;

  exports = {
    default = {
      kind = "aggregate";
      owner = "haus";
      source = "modules";
    };
    den = {
      kind = "foundation";
      owner = "haus";
      source = "modules/den";
    };
    hearth = {
      kind = "room";
      owner = "development";
      source = "modules/hearth";
    };
    prowl = {
      kind = "room";
      owner = "windows";
      source = "modules/prowl";
    };
    sill = {
      kind = "room";
      owner = "bar";
      source = "modules/sill";
    };
    collar = {
      kind = "room";
      owner = "security";
      source = "modules/collar";
    };
    pounce = {
      kind = "room";
      owner = "launcher";
      source = "modules/pounce";
    };
    hush = {
      kind = "room";
      owner = "focus";
      source = "modules/hush";
    };
    secrets = {
      kind = "room";
      owner = "security";
      source = "modules/secrets";
    };
  };

  namespaces = builtins.mapAttrs (
    namespace: editorial:
    editorial
    // {
      kind = kindOf namespace;
      owner = ownerOf namespace;
      optionCount = builtins.length optionPaths.${namespace};
      options = optionsFor namespace;
    }
  ) groups;
}

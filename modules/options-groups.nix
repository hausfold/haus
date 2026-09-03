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
#   hausfold.co's gen-options.mjs   the options reference, laid out BY ROOM,
#                               read out of the committed docs/site-data/
#
# It used to live inside the web renderer alone, where it covered 16 of the 23
# rooms — the other seven (agents, security, developer, displays, keys, shelf, ui)
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
#
# `agent` is a fourth renderer's worth of editorial, added 2026-08-16 to the
# ROOMS (not the namespaces): the haus skill's `references/rooms.md`. Two
# fields, and both answer a question the option tree can't:
#
#   cli   the room's RUNTIME verb — what you run to make it *do* something now,
#         as opposed to `haus set`, which changes what it does next rebuild.
#         `null` for a room that is configuration only. Nothing else in this
#         repo connects a room to a command: the focus room's behaviour lives in
#         `pounce focus`, the shelf's in `perch`, and an agent reading option
#         names alone would never find either.
#   asks  the sentences a PERSON says that should land in this room. Not option
#         names and not a feature summary — the words someone actually uses, in
#         their spelling ("make my mac quiet", not "toggle Do Not Disturb").
#         This is the routing half: an agent handed "make my mac quiet" and a
#         flat list of option leaves has no way to reach `haus.focus.*`.
#
# The family standard these serve is the workshop's `docs/agent-surface.md`.
# `room-registry` requires both on every room, for the same reason it already
# requires a title and a blurb: a room that shipped without them is a room the
# agent silently can't route to, which reads to the user as haus not supporting
# the thing at all.
let
  # Exact relative paths in the generated public surface. `""` names the
  # namespace option itself (for example `haus.displays`). Keeping these as an
  # inventory, rather than glob rules, is what makes an added leaf fail closed.
  optionPaths = {
    accessibility = [
      "closeViewScrollWheelToggle"
      "closeViewZoomFollowsFocus"
      "differentiateWithoutColor"
      "increaseContrast"
      "mouseDriverCursorSize"
      "reduceMotion"
      "reduceTransparency"
    ];
    ai = [
      "clients"
      "default"
      "enable"
      "instructions"
      "keepAwake"
      "meridian.enable"
      "meridian.port"
      # Desktop-safe for the same reason `default` is: both name a program by
      # id rather than by path, and neither can make a machine run something it
      # doesn't already have — an id with no adapter file falls back to a
      # random lane name, exactly as `default` falls back to what is installed.
      "namer"
      # Host-only (below): it is the one leaf in this room that puts
      # third-party code on the machine.
      "pi.packages"
      "repoRoots"
      "skill"
    ];
    animations = [ "" ];
    appearance = [
      "largePrint"
      "reduceMotion"
    ];
    apps = [
      "cursor.enable"
      "packs.writing.enable"
      "vscode.enable"
      "zed.enable"
    ];
    appStore = [ "install" ];
    bar = [
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
      "bottom.items.focus"
      "bottom.items.github"
      "bottom.items.harvest"
      "bottom.items.media"
      "bottom.items.memory"
      "bottom.items.trill"
      "bottom.items.volume"
      "bottom.items.weather"
      "bottom.items.wifi"
      "calendar.horizon"
      "calendar.imminent"
      "calendar.joinHosts"
      "calendar.marquee"
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
      "github.refresh"
      "github.sources"
      "github.sources.*.ci"
      "github.sources.*.command"
      "github.sources.*.icon"
      "github.sources.*.limit"
      "github.sources.*.org"
      "github.sources.*.search"
      "github.sources.*.severity"
      "github.sources.*.title"
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
      "items.github"
      "items.harvest"
      "items.media"
      "items.memory"
      "items.trill"
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
      "media.marquee"
      "media.icons"
      "media.width"
      "position"
      "widgets"
      "widgets.<name>.command"
      "widgets.<name>.enable"
      "widgets.<name>.icon"
      "widgets.<name>.interval"
      "widgets.<name>.permissions"
      "widgets.<name>.placement"
      "widgets.<name>.script"
      "widgets.<name>.style"
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
    focus = [
      "enable"
      "hooks"
      "scenes"
      "scenes.<name>.apps.closeOnExit"
      "scenes.<name>.apps.open"
      "scenes.<name>.audio.input"
      "scenes.<name>.description"
      "scenes.<name>.dnd"
      "scenes.<name>.hooks"
      "scenes.<name>.preventSleep"
      "scenes.<name>.restorePreviousState"
      "scenes.<name>.when.days"
      "scenes.<name>.when.displays"
      "scenes.<name>.when.power"
      "scenes.<name>.when.time"
      "scenes.<name>.when.wifi"
      "slack.enable"
      "slack.snooze"
      "slack.statusEmoji"
      "slack.statusText"
      "slack.tokenCommand"
      "triggers.interval"
    ];
    fonts = [
      "mono.baseSize"
      "mono.name"
      "mono.package"
      "mono.packageName"
      "mono.size"
      "sans.name"
      "sans.package"
      "sans.packageName"
    ];
    git = [
      "email"
      "name"
      "org"
      "shellAliases"
      "signingKey"
    ];
    github = [
      "backstop"
      "coverageRefresh"
      "enable"
      "forwardTo"
      "hooks"
      "hooks.*.events"
      "hooks.*.scope"
      "port"
      "secretCommand"
      "tunnel.credentialsFile"
      "tunnel.enable"
      "tunnel.hostname"
      "tunnel.id"
    ];
    homebrew = [
      "adopt"
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
    keys = [
      "layout"
      "leader"
      "leaderExtras"
      "leaderExtras.*.caption"
      "leaderExtras.*.command"
      "leaderExtras.*.key"
      "palette"
      "windowNav"
    ];
    launcher = [
      "autoQuit.delay"
      "autoQuit.enable"
      "autoQuit.exclude"
      "enable"
      "fnKey"
      "followSystemAppearance"
      "items"
      "items.<name>.alias"
      "items.<name>.bundleIds"
      "items.<name>.caption"
      "items.<name>.hotkey"
      "items.<name>.listed"
      "items.<name>.workspaces"
      "plugins"
      "scale"
      "signingIdentity"
      "windowMode"
      "windowSwitcher"
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
      "login.hideRestart"
      "login.hideShutDown"
      "login.hideSleep"
      "login.message"
      "login.showNameField"
      "requirePassword"
      "requirePasswordDelay"
    ];
    mail = [
      "address"
      "enable"
      "host"
      "mailboxes"
      "port"
      "secretCommand"
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
    power = [
      "computerSleep.battery"
      "computerSleep.charger"
      "diskSleep.battery"
      "diskSleep.charger"
      "displaySleep.battery"
      "displaySleep.charger"
      "lidAwake.enable"
      "lidAwake.linger"
      "lidAwake.maxHold"
      "lidAwake.requirePower"
      "lidAwake.while"
      "lowPowerMode.battery"
      "lowPowerMode.charger"
    ];
    roster = [
      ""
      "<name>.appId"
      "<name>.appStoreId"
      "<name>.bin"
      "<name>.binPath"
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
    secrets = [
      "project"
      "provider"
    ];
    security = [
      "firewall.allowSigned"
      "firewall.allowSignedApp"
      "firewall.blockAllIncoming"
      "firewall.enable"
      "firewall.stealthMode"
      "guestAccount"
      "touchId.enable"
      "touchId.passwordlessRebuild"
    ];
    shelf = [
      "enable"
      "followSystemAppearance"
      "watchScreenshots"
    ];
    notifications = [
      "compositor"
    ];
    portless = [
      "enable"
      "https"
      "lanes.enable"
      "port"
      "trustCA"
      "tlds"
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
    terminal = [
      "editor"
      "editorName"
      "floatBorder"
      "floatOnTop"
      "ghDash.enable"
      "hijackFileAssociations"
      "obsidianVaults"
      "restoreWindows"
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
    windows = [
      "accordionPadding"
      "defaultLayout"
      "defaultOrientation"
      "desktop.clickToReveal"
      "desktop.hideIcons"
      "desktop.hideWidgets"
      "enable"
      "gaps.inner.builtin"
      "gaps.inner.external"
      "gaps.outer.left.builtin"
      "gaps.outer.left.external"
      "gaps.outer.right.builtin"
      "gaps.outer.right.external"
      "gravity"
      "mouseFollowsFocus"
      "mouseFullscreen"
      "nativeTiling.edgeDrag"
      "nativeTiling.margins"
      "nativeTiling.optionAccelerator"
      "nativeTiling.topEdgeFullscreen"
      "numberedWorkspaces"
      "stageManager.autoHideStrip"
      "stageManager.enable"
      "stageManager.groupWindows"
      "stageManager.hideDesktopIcons"
      "stageManager.hideWidgets"
      "workspaceMonitors"
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
      "userStyles"
    ];
  };

  # A whole namespace on one reason, for the three that are host-only entire
  # (`git`, `locale`, `power`). Derived from the inventory above rather than
  # restated, so a leaf added to one of them is host-only the moment it exists
  # instead of falling through to desktop-safe.
  wholeNamespace =
    namespace: reason:
    builtins.listToAttrs (
      map (path: {
        name = path;
        value = reason;
      }) optionPaths.${namespace}
    );

  # These are the exceptions to the fail-closed default for an INVENTORIED
  # option. Every other exact path above is desktop-safe. An uninventoried path
  # never reaches this decision: the registry check rejects it first.
  #
  # Each one names WHY, out of `hostOnlyReasons` below, for the same reason a
  # `recursive` container names a validator: the classification alone tells a
  # reader they may not set the leaf and nothing about what would go wrong if
  # they could. The name is the option's; the sentence is the table's.
  hostOnly = {
    ai.instructions = "agent-context";
    # The one AI leaf that reaches OUT of its own namespace: `keepAwake =
    # "lid"` turns on `haus.power.lidAwake`, and `power` is host-only entire
    # (below) for a reason that does not stop applying just because the
    # request arrives from another room. A desktop that could set this would be
    # setting `haus.power.*` through a side door -- and starting a root daemon
    # while it was there. `this-hardware` is that namespace's own sentence, and
    # it is the true one here too.
    ai.keepAwake = "this-hardware";
    # Not a command this machine runs on a timer, but the same sentence's
    # concern one step earlier: every entry is npm or git source pi fetches and
    # then executes in its own process. A desktop is a file you read to know
    # what it does, and a leaf that names code to run is what stops that being
    # true — whether the running is a shell or a client's plugin loader.
    ai."pi.packages" = "runs-a-command";
    bar = {
      "calendar.me" = "identity";
      "elgato.host" = "one-network";
      # Arbitrary shell, not data: a desktop is a file you can read to know what
      # it can do, and a source that runs a command is exactly the leaf that
      # would stop being true of. `search` and `ci` beside it stay desktop-safe.
      "github.sources.*.command" = "runs-a-command";
      # The same rule, one room's open form later. A widget's `command` is the
      # script the bar EXECUTES every interval — the single most powerful leaf
      # in the whole desktop-safe surface if it were admitted, and the one that
      # would turn "a desktop is data you can read" into "a desktop is data
      # plus whatever it runs on a timer, forever, in your session". So a
      # shared desktop may place, retune and switch off any pill, and may not
      # bring a new one that runs code. That asymmetry is the point rather than
      # a limitation: everything else about a widget stays desktop data.
      "widgets.<name>.command" = "runs-a-command";
      # The other tier, the same rule. A `script` is a barlib framework widget
      # — a file the bar executes every tick, with click handlers and a
      # dropdown of its own — so it is the `command` leaf above with MORE
      # reach, not less, and the fact that it arrives as a path rather than a
      # string changes nothing about what runs.
      "widgets.<name>.script" = "runs-a-command";
      # And the leaf that only exists to decorate one. `style` values are
      # written into the bar's generated item file unquoted, so that a palette
      # name (`$TEAL`) resolves and a font can carry its own quotes — which
      # makes every one of them a shell fragment rather than data, and
      # `"$(…)"` among them. It is also unreadable on its own: a desktop that
      # could set it could never set the widget it styles.
      "widgets.<name>.style" = "runs-a-command";
    };
    focus = {
      hooks = "runs-a-command";
      # Same rule one level down: a scene may say "be quiet, stay awake, use
      # this mic" and a shared desktop may ship it, but the arbitrary script a
      # scene runs is a person's, not a published desktop's.
      "scenes.<name>.hooks" = "runs-a-command";
      # A trigger condition is a taste — "quiet in the evening", "docked means
      # two screens" — with exactly one exception, and the asymmetry is the
      # point: an SSID names one router in one building, which is why
      # `when.displays` is a COUNT. The docked trigger stays shareable and the
      # network one stays yours.
      "scenes.<name>.when.wifi" = "your-network";
      "slack.tokenCommand" = "secret";
    };
    fonts."mono.package" = "needs-pkgs";
    fonts."sans.package" = "needs-pkgs";
    # `git` is the one namespace `wholeNamespace` cannot answer alone: four of
    # its five leaves name you, and `shellAliases` is a set of shell command
    # strings that names nobody. Overriding the one member is the point of
    # writing the reasons down — a sweep that put "it names you rather than a
    # machine" over a command surface would be the exact wrong sentence this
    # table exists to stop.
    git = wholeNamespace "git" "identity" // {
      shellAliases = "runs-a-command";
    };
    # The room's own split, and it is the whole shape of the room in one table:
    # the INTERVALS and the switch are opinions anyone can hold, and everything
    # that names a hostname you own, an organisation you belong to, a secret, a
    # file on this disk or a port on your network is yours alone.
    github = {
      forwardTo = "one-network";
      hooks = "your-account";
      "hooks.*.events" = "your-account";
      "hooks.*.scope" = "your-account";
      secretCommand = "secret";
      "tunnel.credentialsFile" = "local-path";
      "tunnel.hostname" = "your-account";
      "tunnel.id" = "your-account";
    };
    # The watcher's two: one names the mailbox that is yours, the other names
    # the store its password is kept in. `host`, `port` and `mailboxes` beside
    # them stay desktop-safe — a provider's server name and IMAP's own spelling
    # of a folder are facts about a service anyone can use.
    mail = {
      address = "identity";
      secretCommand = "secret";
    };
    keys."leaderExtras.*.command" = "runs-a-command";
    # Which keyboard is physically in front of you, which is the same class of
    # fact as `locale.inputSources` beside it and gets the same sentence.
    keys.layout = "your-region";
    launcher.signingIdentity = "keychain";
    locale = wholeNamespace "locale" "your-region";
    power = wholeNamespace "power" "this-hardware";
    roster = {
      # Not merely host-only: `binPath` is `readOnly` with a definition from
      # the submodule's own `config`, so a desktop OR a host writing it dies in
      # the module system ("read-only, but it's set multiple times") instead of
      # getting the seam's own diagnostic. `haus-writes-it` is the nearest true
      # reason and the exact precedent — `installedBy` is the same shape.
      "<name>.binPath" = "haus-writes-it";
      "<name>.installedBy" = "haus-writes-it";
      "<name>.package" = "needs-pkgs";
    };
    screenshots.location = "local-path";
    secrets = {
      project = "secret";
      provider = "secret";
    };
    # `editor` is a shell command this layer executes, so it stays here
    # forever; `editorName` is the desktop-safe half of that pair — a closed
    # enum over the editors the room installs, which is how a desktop says
    # "this is a neovim Mac" without ever naming a command.
    terminal = {
      editor = "runs-a-command";
      obsidianVaults = "local-path";
    };
    zen = {
      extensions = "browser-code";
      "extensions.<name>.enable" = "browser-code";
      "extensions.<name>.id" = "browser-code";
      "extensions.<name>.mode" = "browser-code";
      "extensions.<name>.slug" = "browser-code";
      "extensions.<name>.url" = "browser-code";
      extraPolicies = "browser-code";
    };
  };

  # What each of those names MEANS, in one sentence, for the person who meets
  # it rendered — under `# desktop data: host-only` in their own host file, and
  # on the options reference.
  #
  # This is the validator table's rule one classification over, and it exists
  # because the site tried the other thing first: one sentence written into the
  # renderer for all 43 host-only rows ("names a person, a secret or a piece of
  # hardware"), which is false on about thirty of them — every `haus.locale.*`
  # and `haus.power.*` leaf, and every one that is host-only for taking a
  # `pkgs` value or running a command. A reason that is wrong more often than
  # right teaches a reader to stop reading the line, so the reasons live here,
  # per option, where the classification they explain is decided.
  #
  # Names rather than sentences at the option, so that eleven rationales are
  # written once instead of forty-three times and the rows that share one
  # provably share it. A name used exactly once is fine and normal.
  hostOnlyReasons = {
    agent-context.why = "Your own always-on instructions to coding agents: the private working context you write for your own machine, not something a stranger's file should arrive holding.";
    browser-code.why = "It installs browser extensions, or writes raw enterprise policy into a file haus owns as root: code reaching your browser through what is supposed to be readable data.";
    haus-writes-it.why = "haus sets this itself, so the roster can still say which module put an app on disk. It is a generated fact about this machine rather than an input anyone writes.";
    identity.why = "It names you rather than a machine: your commit identity, the addresses that are yours, the account whose repositories this Mac works on. A desktop that set it would put its author's details on your work.";
    keychain.why = "It names a code-signing identity in one login keychain, which exists on exactly one Mac and cannot be meaningfully published.";
    local-path.why = "It names a path on this disk, so it is a fact about one filesystem rather than an opinion a shared desktop can hold about every machine.";
    needs-pkgs.why = "It takes a `pkgs` value, and desktop data is evaluated with no module arguments to take one from. The `…Name` leaf beside it is the desktop-safe half of the pair.";
    one-network.why = "It names a device on your own network by host or IP, which is a fact about your desk. Left empty, the pill discovers the device itself, and that is what a shared desktop should leave it doing.";
    runs-a-command.why = "It is a shell command this machine runs, and a desktop is a file you can read to know what it does. A leaf carrying a command is exactly what stops that being true.";
    secret.why = "It points at a secret, or at the store this machine keeps its secrets in, so it belongs to one person on one Mac.";
    this-hardware.why = "Sleep and power behaviour depends on the machine underneath it: whether it has a battery at all, and how this particular one is carried around.";
    your-account.why = "It names something inside one person's GitHub or Cloudflare account — an organisation whose repositories this Mac watches, a hostname you own, the tunnel that carries traffic to your desk. A desktop that set it would point a stranger's machine at your account, and in the webhook's case would tell them where to send deliveries.";
    your-network.why = "It names a Wi-Fi network you join, which is a fact about a place rather than a taste anyone can share. It is why the trigger beside it counts SCREENS instead of naming one: a count is a shape every desk can have, and an SSID exists in exactly one building.";
    your-region.why = "Language, region, units and keyboard layout are facts about the person at the keyboard; a desktop that set them would change what your Mac speaks.";
  };

  # Containers whose payload is admitted only after a named recursive
  # validator walks it. Host-only containers need no validator because desktop
  # data cannot reach them at all.
  recursive = {
    displays."" = "display-selectors";
    focus.scenes = "scene-entries";
    keys.leaderExtras = "submodule-list";
    launcher.items = "launcher-items";
    roster."" = "roster-entries";
    bar."github.sources" = "submodule-list";
    bar."media.icons" = "attrs-of-string";
    bar.widgets = "widget-entries";
    snippets.matches = "submodule-list";
    tour.steps = "submodule-list";
    windows.workspaceMonitors = "monitor-selectors";
    workspaces."" = "workspace-entries";
  };

  # What each of those names MEANS, in one sentence, for the reader who meets it
  # rendered rather than in `modules/lib/desktop.nix`.
  #
  # The name alone is a bare identifier that answers nothing, and it is
  # generated into the `# desktop data: recursive (display-selectors)` line of
  # every host file `haus options` writes. The rule it stands for was written
  # down as hand-written prose on hausfold.co's guide to writing a desktop — a
  # different file, in a different repo, that nothing checks against this one.
  # So the sentence lives here, beside the name it explains, and renders
  # wherever that name is: one generated statement rather than two that can
  # drift apart. A companion PR on hausfold.co is the other half: it renders
  # this table on the options reference and stops the guide restating it.
  #
  # These are DESCRIPTIONS of the rule, not the diagnostics — `desktop.nix`'s
  # `keySaid` messages say what a bad key did wrong and are phrased to complete
  # "…`haus.displays.ABC-123` names a physical display". Folding the two into
  # one string would make either the error clumsy or this sentence so, which is
  # why the check below requires both to EXIST rather than requiring them to be
  # the same words.
  validators = {
    roster-entries.rule = "Keys are plain app ids — letters, digits, `_` and `-` — because each one becomes a launcher row and an argument to an installer.";
    workspace-entries.rule = "Keys are plain workspace names, which is what AeroSpace and the bar's page pill both spell them as.";
    launcher-items.rule = "Keys are palette addresses — `cmd:<id>`, `app:<path>`, `setting:<pane>[?<anchor>]` or `mode:<name>`, spelled as `modules/launcher/item-grammar.nix` spells them — because each one names a row pounce already has, and carrying no quote, backslash, `$`, backtick, newline or tab, because the key is written out beside the values it configures. `shortcut:<uuid>` is the one shape a desktop may not name: it identifies one entry in one Mac's Shortcuts library, the same reason a display UUID is host-only.";
    scene-entries.rule = "Keys are plain scene names — what you type after `focus scene`, so a key has to survive as one shell word.";
    widget-entries.rule = "Keys are plain widget names, because each becomes a SketchyBar item name; a desktop may place and retune a pill, but `command` stays host-only so it can never add one that runs code.";
    display-selectors.rule = "Only the `internal` and `main` selectors: a display UUID names one physical panel on one desk, which is a fact about a machine rather than a taste a desktop can share.";
    monitor-selectors.rule = "Keys are plain workspace names, and each value pins one to a display by POSITION — `main`, `secondary`, or a number from 1 counting left to right — because a monitor's name or a regex over it identifies one physical panel on one desk, the same reason a display UUID is host-only. `built-in` is a name too, and a localized one. A list of positions is a fallback chain, tried in order.";
    submodule-list.rule = "A list of settings, checked field by field inside each element — and a host that names the list at all REPLACES it rather than appending to it.";
    attrs-of-string.rule = "Keys and values are strings carrying no quote, backslash, `$`, backtick, newline or tab, because they are written into a generated file as shell assignments.";
  };

  roomOwners = {
    accessibility = "appearance";
    ai = "ai";
    animations = "appearance";
    appearance = "appearance";
    appStore = "apps";
    apps = "apps";
    bar = "bar";
    developer = "development";
    displays = "displays";
    focus = "focus";
    fonts = "appearance";
    github = "development";
    homebrew = "apps";
    hotCorners = "windows";
    launcher = "launcher";
    lock = "security";
    mail = "notifications";
    menuBar = "bar";
    notifications = "notifications";
    portless = "development";
    screenshots = "appearance";
    secrets = "security";
    security = "security";
    shelf = "shelf";
    snippets = "text-expansion";
    sound = "appearance";
    terminal = "development";
    theme = "appearance";
    wallpaper = "appearance";
    windows = "windows";
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
    if (hostOnly.${namespace} or { }) ? ${path} then
      {
        desktopSafe = false;
        reason = hostOnly.${namespace}.${path};
      }
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
      blurb = "The apps haus picks for you and the saved collections you can switch on in one line — the ones a finished machine has rather than the ones a room needs to work. Each is one switch you can turn off; what it installs is a roster entry like any other, so you can retune or replace it by app id.";
    };

    # ---- how it looks ---------------------------------------------------------
    appearance = {
      order = 25;
      blurb = "The Appearance room's own profiles — named answers to whole-machine questions, where the groups below are the individual dials. `largePrint` sets the interface scale, the high-contrast palette, macOS's own contrast lift and the screen's scaled resolution together. `reduceMotion` stops the motion haus itself draws — the bar's hover sweeps, the pointer following focus, the pull back off an emptied workspace — and asks for macOS's own Reduce Motion alongside it. Both set every value as a default you can still pin by hand.";
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
      blurb = "The machine's type. One mono family drives the terminal AND the bar — the bar stopped keeping a hardcoded font of its own, though it keeps its own tuned sizes. One proportional family drives everything else haus draws: the clock pill when it opts out of mono, and the text in pounce, perch and trill.";
    };
    ui = {
      order = 50;
      blurb = "One number for \"make the interface bigger\", applied across haus's own surfaces.";
    };
    displays = {
      order = 60;
      blurb = "Per-display overrides, keyed by which screen you mean.";
    };

    # ---- the terminal, and who else drives this machine -----------------------
    terminal = {
      order = 70;
      blurb = "The shell and terminal experience.";
    };
    zen = {
      order = 75;
      blurb = "Zen browser policy, extensions and the optional native tab bridge.";
    };
    ai = {
      order = 80;
      blurb = "The AI room: whether this machine runs coding agents at all, which clients it installs, which one the agent keybinding spawns, where the palette looks for a repo to spawn one on, and the two files haus ships into every one of their homes — your instructions, and the `haus` skill. Spelled `haus.agents.*` before 2026-08-13, with the switch under `haus.developer.agents`; both are gone rather than aliased.";
    };
    # 90 was `claude`, folded into `agents` on 2026-08-11: both of its options
    # describe a file EVERY client reads, at its own path. Left free rather than
    # backfilled — the gap is cheap and renumbering the groups below isn't.

    # ---- reach ----------------------------------------------------------------
    accessibility = {
      order = 100;
      blurb = "macOS accessibility keys haus can actually apply. These write to a TCC-protected domain, so they take effect only when the app you run the rebuild from holds Full Disk Access — otherwise haus warns and moves on.";
    };
    keys = {
      order = 110;
      blurb = "The keys haus owns — the leader, the palette, the window-chord modifier — and anything extra you hang off the leader.";
    };
    # ---- macOS settings groups (options-roadmap §5.6) -------------------------
    # Dense on purpose: this block ran out of the file's usual ten-wide spacing
    # when the last three groups landed, and `windows` at 120 is the next fixed
    # point. `animations` then took 111 — the last free slot, and the last
    # squeeze available: the block is now 111–119 with no gaps, so the NEXT group added
    # here has to renumber it, from `windows` at 120 downwards.
    animations = {
      order = 111;
      blurb = "How much motion macOS spends on its own Dock and windows: the slide, the launch bounce, minimise, Mission Control, window open/close. Unset by default like the rest of this block — `\"fast\"` opts in, and going back only stops writing rather than restoring. Deliberately not the Accessibility \"Reduce motion\" switch, which every browser also reads as `prefers-reduced-motion`.";
    };
    hotCorners = {
      order = 112;
      blurb = "What each corner of the screen does when the pointer reaches it. Every corner is unset by default, so haus never overwrites one you set yourself.";
    };
    screenshots = {
      order = 113;
      blurb = "Where ⇧⌘4 puts its files, in what format, and whether it draws a window shadow or a preview thumbnail. Unset by default, so macOS's own choices stand.";
    };
    lock = {
      order = 114;
      blurb = "Whether waking this Mac needs a password and how long the grace period is, plus the login window itself — name-and-password instead of a list of faces, a message for whoever finds a lost laptop, and which of Shut Down / Restart / Sleep it offers. The login half lands at your next login, which each option says.";
    };
    menuBar = {
      order = 115;
      blurb = "The stock menu bar: what the clock shows, and which Control Center glyphs sit beside it. (The hacker bar itself is `bar`.)";
    };
    # One namespace since 2026-08-16, when the Touch ID half stopped being its
    # own `collar` and folded in here. It sits in the macOS-settings block
    # rather than down in policy because the firewall half is a macOS setting
    # and the ordering follows the bigger half.
    security = {
      order = 116;
      blurb = "Security posture: the built-in application firewall and how strict it is (off on a fresh Mac — the setting to turn on for a laptop that joins networks you don't own), whether the passwordless Guest account can log in (on out of the box, and the one genuine boundary in this group), plus Touch ID for `sudo`, including inside a terminal multiplexer, and the passwordless-rebuild rule.";
    };
    sound = {
      order = 117;
      blurb = "Alert volume and sound, interface sound effects, and the boot chime. Volume is 0–100 the way the slider reads it — macOS stores a curve, and haus does the conversion.";
    };
    locale = {
      order = 118;
      blurb = "Language, region, units and keyboard layouts. What a machine in any language other than English needs — and the one room whose settings reach apps you already have open, because haus posts the change notification macOS itself posts.";
    };
    power = {
      order = 119;
      blurb = "Sleep timers and Low Power Mode, said separately for battery and charger — which is the whole point, and why this is built on `pmset` rather than on nix-darwin's own power options. Plus the lid: whether closing this Mac is allowed to end a run that agents are still in the middle of.";
    };

    # ---- the rooms ------------------------------------------------------------
    windows = {
      order = 120;
      blurb = "Tiling window management and the Caps-Lock leader launcher — plus macOS's OWN window features (Stage Manager, edge-drag tiling, the desktop's icons and widgets), which live here rather than with the other macOS settings because they decide the same thing the tiler does and haus warns when both are on.";
    };
    bar = {
      order = 130;
      blurb = "The menu bar, and which pills it draws.";
    };
    launcher = {
      order = 140;
      blurb = "The ⌘Space command palette. Pounce is the app behind it.";
    };
    shelf = {
      order = 160;
      blurb = "The notch file shelf. Perch is the app behind it.";
    };
    notifications = {
      order = 165;
      blurb = "The notification compositor haus already draws through. Trill is the app behind it; this switch is whether haus owns the bundle. It is NOT where a banner's routing lives — that is `~/.config/trill/rules.json`, and haus deliberately puts no second dial in front of it.";
    };
    mail = {
      order = 167;
      blurb = "Watch a mailbox over IMAP and draw a card per new message, pushed rather than polled. Beside `notifications` because a card is all it produces — and like that switch, it holds no filter of its own: your account's filters decide what arrives, `~/.config/trill/rules.json` decides what a `haus.mail` card then does.";
    };
    focus = {
      order = 170;
      blurb = "One quiet switch: Do Not Disturb, optional Slack status, and your hooks — plus the named scenes around it.";
    };
    snippets = {
      order = 180;
      blurb = "Text expansion via espanso.";
    };
    portless = {
      order = 185;
      blurb = "Named .localhost URLs for dev servers, with real HTTPS: `https://myapp.localhost` instead of `http://localhost:3000`. One proxy on :443 owns the machine's ports, which is what stops N agent lanes of one repo fighting over the same one.";
    };
    tour = {
      order = 190;
      blurb = "The first-run tutor.";
    };

    # ---- policy ---------------------------------------------------------------
    developer = {
      order = 200;
      blurb = "The developer pack: the CLI toolbelt, Git tooling and language runtimes. Coding agents left this pack on 2026-08-13 and are their own room now (`haus.ai.*`). Off is a hacker machine for someone who never opens a terminal by choice.";
    };
    # 210 was `collar` — Touch ID for sudo — until 2026-08-16. It is part of
    # `security` above now, and the slot is left free rather than backfilled.
    github = {
      order = 205;
      blurb = "This machine's GitHub webhook endpoint: the tunnel, the receiver, and the hooks it wants to exist. Rooms that watch GitHub read its signal and poll on a long backstop instead of a short one. haus never writes to GitHub — it holds no token, and `haus doctor` prints the `gh` command that closes a gap rather than running it.";
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

  # ---- the rooms a PERSON meets ----------------------------------------------
  # `roomOwners` above says which product room owns a namespace; this says what
  # that room is, in the order someone should meet the thirteen of them. Both
  # halves are needed and neither implies the other: a room is a page, a
  # namespace is an address, and `haus.bar` plus `haus.menuBar` are one room
  # with two addresses.
  #
  # Without this table every renderer had to invent the room's name and
  # sentence for itself, which is how the docs ended up describing "35 rooms" —
  # one per namespace, with module names (`core`, `terminal`, `windows`) where a
  # product name belongs. Rooms are the unit the product model names
  # (`docs/model.md`); namespaces are how they are spelled
  # in a host file.
  #
  # The last two entries are not product rooms — they are the owners
  # `ownerOf` produces for a namespace that belongs to no single room. They
  # carry a title and a blurb for exactly the same reason the rooms do: a
  # renderer lays out every bucket, and the editorial belongs here rather than
  # in each renderer. `kind` is what separates them, so a page that wants only
  # the catalogue filters on `kind == "room"`.
  #
  # `order` is spaced by ten, like the namespace orders, and follows the
  # catalogue rather than the alphabet.
  rooms = {
    apps = {
      title = "Apps";
      order = 10;
      blurb = "The apps a finished machine has: the curated picks, the packs that switch a whole set on in one line, App Store policy, and what a rebuild does to anything you installed by hand. The list they all land in is `haus.roster`, a shared surface below.";
      agent = {
        cli = null;
        # Deliberately NOT "install an app" / "add slack": those are
        # `haus.roster.<name>`, and roster belongs to the shared bucket below.
        # An ask routed to the room that owns none of the options points the
        # agent away from the answer, which is worse than no routing at all.
        asks = [
          "turn on the writing pack"
          "install the apps haus picks for me"
          "open markdown files with something else"
          "stop homebrew auto-updating"
        ];
      };
    };
    appearance = {
      title = "Appearance";
      order = 20;
      blurb = "How the machine looks: the palette and its accent, the wallpaper, the fonts, and the macOS surfaces that follow them — motion, screenshots, sound and the accessibility keys. The interface scale every room reads is `haus.ui`, a shared surface below.";
      agent = {
        cli = null;
        asks = [
          "change my theme"
          "switch to light mode"
          "make the text bigger"
          "change my font"
          "set my wallpaper"
          "change the accent colour"
        ];
      };
    };
    displays = {
      title = "Displays";
      order = 30;
      blurb = "Resolution and per-display behaviour, addressed by which screen you mean rather than by a panel's serial number.";
      agent = {
        cli = null;
        asks = [
          "change my resolution"
          "make my external monitor bigger"
          "scale my second screen"
        ];
      };
    };
    development = {
      title = "Development";
      order = 40;
      blurb = "The terminal stack — terminal, shell, multiplexer, editor — plus the browser, the CLI toolbelt, Git tooling and language runtimes. Your commit identity itself is a fact about you rather than this room's, and stays in your host. The terminal lives here because a terminal with no tools in it is not a separate thing anyone wants.";
      agent = {
        cli = null;
        asks = [
          "install a language runtime"
          "change my editor"
          "configure my terminal"
          "add a command-line tool"
        ];
      };
    };
    windows = {
      title = "Windows";
      order = 50;
      blurb = "Tiling, window navigation, hot corners, and the leader key that launches an app or throws it somewhere — plus macOS's own Stage Manager, edge-drag tiling and desktop clutter, which answer the same question the tiler does. The workspaces themselves (`haus.workspaces`) and the keys haus claims (`haus.keys`) are shared surfaces below, because the bar and the launcher read them too.";
      agent = {
        cli = "aerospace";
        asks = [
          "tile my windows"
          "change my window keybindings"
          "move this window to another workspace"
          "set up hot corners"
          "what does my leader key do"
          "turn off stage manager"
          "stop windows snapping when i drag them to the edge"
          "hide the icons on my desktop"
        ];
      };
    };
    bar = {
      title = "Bar";
      order = 60;
      blurb = "The menu bar: where it draws, which pills it carries, and what each one reads.";
      agent = {
        cli = "sketchybar (top bar) · bar-bottom (the second one, same binary)";
        asks = [
          "change my menu bar"
          "add a pill to the bar"
          "show battery in the bar"
          "hide the bar"
        ];
      };
    };
    launcher = {
      title = "Launcher";
      order = 70;
      blurb = "The command palette: its daemon, its commands, and every Pounce setting haus exposes.";
      agent = {
        cli = "pounce";
        asks = [
          "change what cmd-space opens"
          "add a command to my palette"
          "what opens when I hit cmd-space"
        ];
      };
    };
    shelf = {
      title = "Shelf";
      order = 80;
      blurb = "The file shelf that grows out of the notch to catch what you drag at it.";
      agent = {
        # NOT `perch`. This room dittos Perch.app into /Applications and puts no
        # binary on PATH — its roster entry has no `package`, so `packagesFor`
        # skips it. `perch add` exists in perch's own repo and reaches a machine
        # through perch's cask, not through here.
        cli = null;
        asks = [
          "turn the notch shelf on"
          "turn perch off"
          "stop the shelf appearing in the notch"
        ];
      };
    };
    notifications = {
      title = "Notifications";
      order = 85;
      blurb = "How this desktop's own banners get drawn. haus has *drawn through* trill since `haus-notify` landed — finding it at runtime and falling back to Apple's banner when it isn't there — and that is unconditional, in ../core, whatever this room says. What lives HERE is the narrower question of whether haus installs and pins the bundle, at a fixed path its Full Disk Access grant can survive. Named for the subject rather than the app, like every other room since the 2026-08-16 sweep (../moved.nix). It also owns the one source haus itself feeds those banners from: `haus.mail`, an IMAP IDLE watcher that draws a card per new message.";
      agent = {
        # `trill`, unlike the shelf's `null`: the room installs no binary, but
        # the runtime verb is real and already on PATH here (../core/trill.sh
        # answers it whether or not this room is on). Pointing an agent at
        # `haus.notifications.compositor` for "silence this app" would be the
        # wrong half — routing lives in ~/.config/trill/rules.json and nothing
        # in the option tree says so.
        cli = "trill send|ask|resolve|ping · trill doctor (exit 5 = can't tell) · haus-mail-announce --mailbox INBOX … --test (draw a card for the newest message, watermark untouched)";
        asks = [
          "install trill"
          "let haus manage my notification banners"
          "stop haus notifications falling back to Apple's banner"
          "tell me when I get an email"
          "notify me about new mail in my inbox"
          "stop announcing my mail"
        ];
      };
    };
    focus = {
      title = "Focus";
      order = 90;
      blurb = "One quiet switch: Do Not Disturb, an optional status somewhere else, and your own hooks on both edges — plus the named states (`scenes`) around it, of which quiet is the built-in one. A scene can carry a `when` (a daily window, a network, the power source, the screens) and be entered for you, on a rule that never overrides a state you chose.";
      agent = {
        cli = "focus on|off|toggle|status · focus scene <name>|off|list · focus auto --probe";
        asks = [
          "make my mac quiet"
          "turn on do not disturb"
          "hush"
          "am I in do not disturb"
          "set my mac up for recording"
          "stop the screen sleeping while I present"
          "go quiet automatically in the evening"
          "how do I make a scene start on its own"
        ];
      };
    };
    ai = {
      title = "AI";
      order = 100;
      blurb = "Coding agents: which clients this machine installs, the worktree lifecycle around them, and the instructions and `haus` skill every client reads.";
      agent = {
        cli = "scruff";
        asks = [
          "install claude code"
          "install codex"
          "which agent does the agent key spawn"
          "change my agent instructions"
          "add my work repos to the spawn agent list"
          "what worktrees are open"
        ];
      };
    };
    text-expansion = {
      title = "Text expansion";
      order = 110;
      blurb = "Snippets, and the engine that types them out for you.";
      agent = {
        cli = "espanso";
        asks = [
          "add a snippet"
          "set up text expansion"
          "type my email automatically"
        ];
      };
    };
    security = {
      title = "Security";
      order = 120;
      blurb = "Touch ID for sudo, lock and login-window behaviour, the guest account, the firewall, and where secret values come from.";
      agent = {
        cli = null;
        asks = [
          "touch id for sudo"
          "turn on the firewall"
          "lock my screen faster"
          "turn off the guest account"
          "put my phone number on the login screen"
          "stop showing a list of users when i log in"
          "where does haus get my secrets"
        ];
      };
    };

    haus = {
      title = "Shared surfaces";
      kind = "shared";
      order = 200;
      blurb = "Surfaces more than one room reads: the app roster, the workspaces, the keys haus owns, the interface scale, the first-run tour. They belong to no single room because moving one into a room would make the others depend on it.";
      agent = {
        # `haus set` is not a runtime verb by this field's own definition — it
        # writes the host file and still needs a rebuild — and it is available
        # for every room, so hanging it on this one implies the other thirteen
        # lack it.
        cli = null;
        asks = [
          "install an app"
          "add slack"
          "remove an app"
          "what apps are on this machine"
          "rename a workspace"
          "make the whole interface bigger"
        ];
      };
    };
    host = {
      title = "Your machine";
      kind = "host";
      order = 210;
      blurb = "The facts that are about you or this Mac rather than about a room — your commit identity, your region, this laptop's power behaviour. A shared desktop may not set them.";
      agent = {
        cli = null;
        asks = [
          "change my git identity"
          "change my timezone"
          "set my region"
          "stop my laptop sleeping so fast"
          "keep working with the lid closed"
        ];
      };
    };
  };

  # Every `darwinModules` export, and the room it belongs to. `kind` says what
  # kind of export it is; `owner` is a key of `rooms` above.
  exportsMeta = {
    default = {
      kind = "aggregate";
      owner = "haus";
      source = "modules";
    };
    core = {
      kind = "foundation";
      owner = "haus";
      source = "modules/core";
    };
    terminal = {
      kind = "room";
      owner = "development";
      source = "modules/terminal";
    };
    windows = {
      kind = "room";
      owner = "windows";
      source = "modules/windows";
    };
    bar = {
      kind = "room";
      owner = "bar";
      source = "modules/bar";
    };
    security = {
      kind = "room";
      owner = "security";
      source = "modules/security";
    };
    launcher = {
      kind = "room";
      owner = "launcher";
      source = "modules/launcher";
    };
    focus = {
      kind = "room";
      owner = "focus";
      source = "modules/focus";
    };
    secrets = {
      kind = "room";
      owner = "security";
      source = "modules/secrets";
    };
  };

  publishedNamespaces = builtins.mapAttrs (
    namespace: editorial:
    editorial
    // {
      kind = kindOf namespace;
      owner = ownerOf namespace;
      optionCount = builtins.length optionPaths.${namespace};
      options = optionsFor namespace;
    }
  ) groups;

  # A room's membership is DERIVED, never restated. `roomOwners` is the one
  # place a namespace names its room, so a namespace added there joins its room
  # everywhere — page, host template, catalogue — without a second list to keep
  # in step. The members come out in the namespaces' own reading order.
  byOrder = names: builtins.sort (a: b: groups.${a}.order < groups.${b}.order) names;
  membersOf =
    room: byOrder (builtins.filter (namespace: ownerOf namespace == room) (builtins.attrNames groups));
  exportsOf =
    room: builtins.filter (name: exportsMeta.${name}.owner == room) (builtins.attrNames exportsMeta);
  publishedRooms = builtins.mapAttrs (
    room: editorial:
    {
      kind = "room";
    }
    // editorial
    // rec {
      namespaces = membersOf room;
      exports = exportsOf room;
      optionCount = builtins.foldl' (
        total: namespace: total + publishedNamespaces.${namespace}.optionCount
      ) 0 namespaces;
    }
  ) rooms;
in
{
  schemaVersion = 1;

  exports = exportsMeta;
  rooms = publishedRooms;
  namespaces = publishedNamespaces;
  inherit validators hostOnlyReasons;
}

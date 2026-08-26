# Bar — the pills along your menu bar. SketchyBar (from nixpkgs), launched via
# nix-darwin, with the stray-agent eviction that keeps a rogue `brew services`
# instance — the shape the Homebrew formula this room used to install left
# behind — from stealing the lock file.
#
# The workspace pills are data-driven: WORKSPACES / ws_icon are generated from
# haus._workspaces, LAUNCHER_KEYS from haus._launchers (the resolved
# shared app roster) — so the bar can't drift from AeroSpace's launcher. Every
# right-side pill is individually
# toggleable via haus.bar.items (one bool per pill): the core
# clock/weather/media/battery/wifi default on, the extras cpu/memory/volume/
# calendar/caffeinate plus the personal agents/elgato/harvest default off.
#
# haus.bar.bottom.enable adds a SECOND bar along the bottom of the screen,
# running at the same time as this one, with the extras named in
# haus.bar.bottom.items moved down onto it. Down there each pill also names its
# GROUP — left, center or right, SketchyBar's own three regions — because that
# bar has no workspace pills, no front-app slot and no notch competing for the
# other two; up here every movable pill is on the right and always was. It is a
# second launchd agent running the same binary under a second name — see
# `barBottom` below for why there is no other way, and `barSh` for how a shared
# plugin knows which of the two it is talking to.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  guiWait = import ../lib/gui-wait.nix;
  withGUIWait = guiWait.wrap;
  userPath = "/run/current-system/sw/bin:/etc/profiles/per-user/${username}/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin";

  cfg = config.haus.bar;

  barpop = pkgs.callPackage ./barpop.nix { };

  # What the cpu and memory pills read their numbers from — the Mach calls and
  # the delta arithmetic neither `ps` nor `memory_pressure` can do honestly.
  # See barvitals.swift; installed conditionally at systemPackages below.
  barvitals = pkgs.callPackage ./barvitals.nix { };

  # ---- the second bar, and why it is a symlink -------------------------------
  # SketchyBar has no two-bars-in-one-process mode. An instance names itself
  # after `basename(argv[0])` (src/sketchybar.c) and keys BOTH its lock file
  # (/tmp/<name>_<user>.lock) and its mach service (git.felix.<name>) on that
  # name — so two bars means the SAME binary invoked under two names, and the
  # name has to reach it through argv[0]. There is no flag and no environment
  # variable for it: BAR_NAME is EXPORTED to plugins, never read, so setting it
  # on the way in does nothing at all.
  #
  # Hence a symlink rather than a wrapper script: `exec -a` would work too, but a
  # link is the whole mechanism in one line, and it is what the client half needs
  # anyway. `bar-bottom --set cpu label=…` addresses the bottom bar exactly the
  # way `sketchybar --set` addresses the top one — same binary, second name,
  # second mach service — which is why this lands on PATH and not just in the
  # launchd agent. It points at the PROFILE path, not at `${pkgs.sketchybar}`,
  # for the same reason `barTopPath` does one binding down: the roster entry
  # below is an `mkDefault`, so a host may install a different SketchyBar, and a
  # store path baked in here would leave the bottom bar running a build the top
  # one isn't — two mach services, two versions, no warning. Resolving through
  # the profile means the second NAME follows whatever the roster installed. It
  # dangles at build time, as it always has, and resolves at run time, same as
  # the agent's own ProgramArguments.
  barBottom = pkgs.runCommand "bar-bottom" { } ''
    mkdir -p "$out/bin"
    ln -s ${barTopPath} "$out/bin/bar-bottom"
  '';

  # How each bar is addressed from a config file or a plugin. BOTH are absolute:
  # a misdirected --set is silent (it targets the other bar's instance and says
  # nothing), so neither is left to whatever `sketchybar` a PATH happens to
  # resolve — and barpop takes the same string as its SKETCHYBAR_BIN, which has
  # to be a path it can stat. The plugins have always spelled the top one out
  # this way; this is the generated blocks catching up.
  #
  # It is the profile path, not the store path: sketchybar's own rc, its plugins
  # and the reload at the bottom of this file all name it, and a store path would
  # freeze whichever build wrote each of those — the running bar and a plugin
  # deployed a generation later would then be talking to two different binaries.
  # It comes from the ROSTER rather than being spelled here, and that is the
  # point: `scope = "system"` is what puts sketchybar in
  # /run/current-system/sw/bin at all, so the profile half of this path is the
  # roster's answer rather than this room's guess. Before `binPath` existed the
  # string was hand-written at sixteen call sites in nine files across three
  # rooms, and moving the entry between install sources was a sixteen-spelling
  # sweep no check could see — see options-roadmap.md §5.4.
  #
  # null only when the entry installs nothing, which the assertion further down
  # is the real message for; the placeholder keeps eval alive long enough to
  # print it and is deliberately not mistakable for a real path.
  barTopPath =
    let
      p = config.haus.roster.sketchybar.binPath;
    in
    if p != null then p else "/nonexistent/haus-bar-has-no-sketchybar";
  barBottomPath = "/run/current-system/sw/bin/bar-bottom";

  # Where each bar's rc LIVES, as the deployed ~/.config path rather than the
  # store path it links to. Both the launchd agent and the reload below name it,
  # and it has to be this spelling in both: home.file deploys a symlink into
  # /nix/store, SketchyBar resolves the config path ONCE at startup, and a
  # `--reload` with no argument then re-runs whatever realpath it resolved back
  # then — the store file from the generation the process booted on, forever.
  # See the reload's own comment at the bottom of this file for what that cost.
  barTopRc = "/Users/${username}/.config/sketchybar/sketchybarrc";
  barBottomRc = "/Users/${username}/.config/sketchybar/bar-bottomrc";

  # What feeds the media pill now that SketchyBar's own media_change event is
  # dead on macOS 15.4+. Reached by absolute store path from media_config.sh
  # rather than put on PATH, and only when the pill is actually on, so a rice
  # with `bar.items.media = false` doesn't carry it in its closure.
  mediaControl = pkgs.callPackage ./media-control.nix { };

  # What a pill with a dropdown uses instead of a bare `popup.drawing=toggle`, so
  # the dropdown also closes on a click anywhere else — sketchybar alone only ever
  # sees clicks on its own items (see barpop.swift).
  #
  # The toggle stays FIRST and unchanged, so opening a dropdown costs exactly what
  # it always did; the guard is armed after it, backgrounded, and nothing waits on
  # it. That ordering is the whole latency story — armed inline, it added ~200 ms
  # to every open. `&` also means no fallback is needed: if the binary is missing
  # the popup has already opened, and only the dismissal is lost.
  #
  # SKETCHYBAR_BIN is how barpop is told WHICH bar's popup it is guarding: it
  # resolves its own client from that variable first (barpop.swift), and unset
  # it queries the top bar — so on a pill moved to the bottom bar it would find
  # no such item and exit before arming, leaving a dropdown that only a second
  # click on the pill can close. Which is the whole thing barpop exists to fix.
  # `sb` is an absolute path on both bars precisely so it can serve as both.
  popToggle =
    sb: item:
    "${sb} --set ${item} popup.drawing=toggle; SKETCHYBAR_BIN=${sb} /run/current-system/sw/bin/barpop arm ${item} 2>/dev/null &";

  # Every dropdown carries this, aligned to the GROUP its pill sits in.
  # SketchyBar's popup.align defaults to `left`, i.e. the popup's left edge is
  # pinned to the pill's left edge and the rows grow rightward — fine under the
  # haus logo at the far left, but on the right half of the bar a wide row (an
  # agent's repo/branch, a usage gauge) runs straight off the screen edge.
  # `right` pins the popup's RIGHT edge to the pill instead, so it opens
  # leftward, into the bar; `center` grows both ways from the pill's middle.
  #
  # Taking the side as an argument is what keeps that true on the bottom bar's
  # left and center groups: a pill moved there would otherwise still carry
  # `align=right` and open away from the screen edge it is now nowhere near.
  # The hand-written left-side items in sketchybarrc (haus.logo) never come
  # through here and keep the default.
  popupAlign = side: "popup.align=${side}";

  # haus.workspaces drives the pills now (workspace membership earns
  # one, not an app field — see notes/options-roadmap.md §5.4); the keyed
  # roster subset still drives the leader picker.
  launchers = config.haus._launchers;
  workspaces = config.haus._workspaces;
  # The numbered workspaces, resolved from haus.windows.numberedWorkspaces by
  # ../workspaces. `id` is what AeroSpace calls the workspace, `key` is the
  # digit the leader reaches it by — the same at every number except ten, which
  # is id "10" on the `0` key. The bar needs both: the pill is named by id, the
  # leader picker's bubble by key.
  numbered = config.haus._numberedWorkspaces;
  appWorkspaceId = a: config.haus._appWorkspace.${a.id} or null;

  # ---- type sizes: ui.scale, up to the menu bar's own ceiling -----------------
  # Resolved in ../lib/bar.nix, not here, because WINDOWS reads the same resolution
  # to decide how much room to leave beside the bar — the bar's type and the gap
  # next to it have to move together, and a rule mirrored in two rooms is exactly
  # what modules/lib exists to prevent. See that file for why there's a ceiling at
  # all (short version: the bar's height belongs to the macOS menu-bar band, which
  # was measured to have no setting behind it).
  bar = import ../lib/bar.nix {
    inherit lib;
    scale = config.haus.ui.scale;
  };
  inherit (bar) sizes;

  # ---- the side edges: where the outermost pill stops -------------------------
  # The bar's left and right padding is NOT a tuned number. It IS the window gap
  # windows leaves at those same edges (../lib/gaps.nix, the one owner of every
  # number in aerospace.toml's [gaps] block), and the pill at each edge gives up
  # its own outer padding so the two land on the same line — at every
  # haus.ui.scale, and through any later change to the gaps.
  #
  # It was a hardcoded 10 in both rcs, and where that landed was an accident of
  # whichever pill happened to be outermost: the menu bar's logo edge sat at 14
  # (10 + its own 4) and its clock edge at 18 (10 + the clock's 8), against a
  # 20pt window gap on an external display and a 10pt one on the built-in. So
  # every edge was wrong, each by a different amount, and in opposite directions
  # on the two displays — which is what a constant with no relationship to the
  # edge it is drawn against buys.
  #
  # `outermost` rather than a per-monitor pair, because SketchyBar has no
  # per-display padding: an instance draws one bar across every screen with one
  # padding, so this has to be a single number for a machine whose displays want
  # 10 and 20. The widest is the safe direction and it is the same reason
  # wallpaper takes `outermost` — inset further than the windows on the narrower
  # display reads as deliberate, where the other choice puts pills outboard of
  # the window edge on the wider one, which is the thing that looks broken.
  # (Exact on an external, then, and up to 10pt inset on the built-in alone.)
  gaps = import ../lib/gaps.nix {
    inherit lib;
    scale = config.haus.ui.scale;
    bar = cfg;
  };

  # The inset itself: the bar's padding IS the window gap, in full, and the pill
  # at each edge gives up its own outer padding to make that true (`edgePad`).
  barPadX = gaps.outermost.left;

  # The outermost pill's outer padding is spent on nothing — there is no
  # neighbour out there, only the screen, and the bar's padding is already the
  # whole gap. Zeroing it is what keeps the identity exact for pills that carry
  # their own separation (the clock and the graph pills use 8 where the default
  # is 4), and it is the ONLY form that also works for the bracket pills: a
  # bracket's members draw their padding INSIDE the pill (see the `agents.pill`
  # comment below), so setting one to 4 widens the pill by 4 rather than pushing
  # it in, while 0 is what those members already carry. So the rule is "the
  # outer edge belongs to the bar", said once, with no per-pill table to drift.
  #
  # `head` is the outermost one in both directions — SketchyBar packs a group
  # outward from its own edge, so a `right` group reads outside-in and a `left`
  # group inside-out from the first item added. `center` has no screen edge and
  # is skipped.
  #
  # A multi-item pill is the one place `head` names a member rather than the
  # edge itself: `agents` is four items under a bracket, and on the RIGHT its
  # segments are reversed, so the member at the screen edge is `agents.done`
  # while this addresses `agents`. It comes out exact anyway — every member of
  # that pill carries 0 already and the bracket's own padding moves nothing — so
  # this is a note rather than a hole. A future bracket pill whose members
  # carried real padding would want the whole SET zeroed on the edge side.
  edgePad =
    sb: side: names:
    lib.optionalString (names != [ ] && (side == "left" || side == "right")) ''
      ${sb} --set ${itemId (builtins.head names)} background.padding_${side}=0
    '';

  # ---- the bar's type FAMILY, from the same option as the terminal's ----------
  # Everything in the bar except the workspace logos is drawn in this. It used to
  # be the literal "Hack Nerd Font", written into the rc, four plugins and six
  # generated blocks — so a rice that changed haus.fonts.mono.name got a
  # machine with two type families and no way to say otherwise, which is a
  # promise the option never made and a limit nothing wrote down.
  #
  # It is the MONO family on purpose: the bar draws Nerd Font icon glyphs
  # (nf-md-*) in the same runs as its labels, so it needs the same patched font
  # the terminal does, and `fonts.mono` is where a rice names one (with the
  # package, and the warning when the two disagree). Taken verbatim rather than
  # transformed — a "Nerd Font Mono" family name is what the option holds, and
  # deriving the propositional variant by trimming " Mono" would silently
  # invent a family for anything not following Nerd Font's naming (Berkeley
  # Mono → "Berkeley", which does not exist).
  barFont = config.haus.fonts.mono.name;
  # The one proportional string the layer draws, and both of its values are now
  # NAMED. `clock.monoFont = false` used to weld ".AppleSystemUIFont" in right
  # here, which made this line a family switch whose second family no option
  # could reach and no check could see — font-reach evaluates two systems that
  # differ in fonts.mono.name and both of them leave clock.monoFont at `true`,
  # so this branch was never taken in either.
  clockLabelFont = if cfg.clock.monoFont then barFont else config.haus.fonts.sans.name;

  bashArray = xs: lib.concatMapStringsSep " " (x: ''"${x}"'') xs;
  appWorkspaces = map (ws: ws.id) workspaces;
  iconFont =
    icon:
    if lib.hasPrefix ":" icon then
      "sketchybar-app-font:Regular:${sizes.appIcon}"
    else
      "${barFont}:Bold:${sizes.icon}";
  wsIconCases = lib.concatMapStrings (
    ws:
    lib.optionalString (ws.icon != null) (
      "    ${ws.id}) ICON=${lib.escapeShellArg ws.icon} ; IFONT=${lib.escapeShellArg (iconFont ws.icon)} ;;\n"
    )
  ) workspaces;
  # Leader-key -> workspace map for launch_mode.sh, same colon-joined shape it
  # used to hardcode. A digit focuses its numbered workspace; each app key maps
  # to the workspace it belongs to (haus._appWorkspace, populated from
  # haus.workspaces.*.apps); no membership renders as "<key>:" (always
  # closed/grey). The digit half is where key and id can differ — `0:10`.
  launchersStr = lib.concatStringsSep " " (
    map (n: "${n.key}:${n.id}") numbered
    ++ map (a: "${a.key}:${lib.optionalString (appWorkspaceId a != null) (appWorkspaceId a)}") launchers
  );

  # Sourced by sketchybarrc: the workspace roster + a per-workspace icon lookup.
  # bash 3.2 (macOS /bin/bash) has no associative arrays, hence the case in a fn.
  workspacesSh = ''
    #!/bin/bash
    # GENERATED from haus._roster by modules/bar/default.nix — do not edit.
    WORKSPACES=(${bashArray (map (n: n.id) numbered ++ appWorkspaces)})
    # Leader picker bubbles: one digit per numbered workspace (focus it) plus one
    # per app key (jump to its workspace) — mirrors [mode.launch.binding]. Keys,
    # not ids, which is why ten's bubble reads `0`.
    LAUNCHER_KEYS=(${bashArray (map (n: n.key) numbered ++ map (a: a.key) launchers)})
    # Just the numbered half of the line above. The tour needs to tell a
    # workspace digit from an app letter, and testing for "is it a digit" is
    # wrong twice over: a roster app may legitimately claim a digit the numbered
    # workspaces don't, and ten's key is `0` rather than `10`.
    NUMBERED_KEYS=(${bashArray (map (n: n.key) numbered)})
    # Leader hotkey -> assigned workspace, parsed by launch_mode.sh (bash 3.2 has
    # no associative arrays, so a plain space-separated "<key>:<ws>" string). An
    # empty <ws> means no assigned space (always shown closed/grey).
    LAUNCHERS="${launchersStr}"

    # ws_icon <workspace>: sets ICON + IFONT. Default is the workspace's own
    # letter in the bar's Nerd Font; app-workspaces override to their logo glyph.
    ws_icon() {
      ICON="$1"
      IFONT="${barFont}:Bold:${sizes.icon}"
      case "$1" in
    ${wsIconCases}  esac
    }
  '';

  # ---- the github pill's sources ---------------------------------------------
  # A source names exactly one KIND, and the plugin owns the query for it (see
  # the option's own description, and plugins/github.sh's header, for why this
  # is typed rather than one query string). These four resolvers are the only
  # place a kind's defaults are decided, so the config file, the assertions and
  # the dropdown can't disagree about what an entry meant.
  gitOrg = config.haus.git.org;
  ghSources = cfg.github.sources;
  ghKindsSet =
    s:
    lib.optional s.ci "ci"
    ++ lib.optional (s.search != null) "search"
    ++ lib.optional (s.command != null) "command";
  ghKind = s: lib.head (ghKindsSet s ++ [ "command" ]);
  ghPayload =
    s:
    if s.search != null then
      s.search
    else if s.command != null then
      s.command
    else
      "";
  # An owner named per-source, else the machine's one. Falling back rather than
  # requiring it is what keeps a rename a single word: `haus.git.org` moves and
  # every ci source follows, without this list being touched.
  ghOrg = s: if s.org != "" then s.org else gitOrg;
  # Glyph defaults by kind: a bolt for a workflow, a pull-request mark for a
  # search (which is nearly always PRs), a cog for whatever a command does.
  ghIcon =
    s:
    if s.icon != "" then
      s.icon
    else
      {
        ci = "";
        search = "";
        command = "";
      }
      .${ghKind s};
  # `bad` for ci and `info` for everything else: a count of red default branches
  # is an alarm by construction, while a search is a work queue until its author
  # says otherwise. Resolved here because a submodule option can't take a
  # default that depends on a sibling.
  ghSeverity = s: if s.severity != null then s.severity else (if s.ci then "bad" else "info");

  # ASCII 0x1f, the unit separator, and deliberately NOT a tab. Tab is an IFS
  # *whitespace* character, so `IFS=$'\t' read` folds a run of tabs into one
  # delimiter and drops empty fields entirely — a source that set no title would
  # hand the plugin its severity in the title column and parse without a murmur.
  # The unit separator is not whitespace, so every field arrives, empty or not.
  ghUS = builtins.fromJSON "\"\\u001f\"";

  # One line per source, in the configured order — the order the pill also
  # breaks severity ties by. escapeShellArg rather than a double-quoted bash
  # string: a search filter is user text and may hold quotes, backslashes or a
  # `$`, and a `command` source is arbitrary shell by definition.
  ghSourcesTsv = lib.concatMapStrings (
    s:
    lib.concatStringsSep ghUS [
      (ghKind s)
      (ghPayload s)
      (ghOrg s)
      s.title
      (ghIcon s)
      (ghSeverity s)
      (toString s.limit)
    ]
    + "\n"
  ) ghSources;

  githubConfigSh = ''
    #!/bin/bash
    # GENERATED from haus.bar.github.* + haus.git.org by
    # modules/bar/default.nix — do not edit. One line per source, fields
    # separated by ASCII 0x1f (see ghUS there, and github.sh's header, for why
    # a tab would silently eat the empty ones):
    # <kind><US><payload><US><org><US><title><US><icon><US><severity><US><limit>
    BAR_GITHUB_REFRESH="${toString cfg.github.refresh}"
    BAR_GITHUB_ICON=""
    BAR_GITHUB_SOURCES=${lib.escapeShellArg ghSourcesTsv}
  '';

  # The focus pill — generic (no personal hardware/service), so unlike the
  # bar.items extras below it rides the Focus room's contribution
  # (`_contrib.bar.focus`, which `haus.focus.enable` is the user's address for),
  # not an opt-in list. focus_change is fired by the focus engine after its own toggles and by
  # the focus-watcher agent (modules/focus) when the Focus DB changes; the
  # update_freq poll is only a backstop for missed events.
  focusBlock = sb: side: ''
    ${sb} --add event focus_change
    ${sb} --add item focus ${side} \
        --set focus \
            update_freq=30 \
            script="$HOME/.config/sketchybar/plugins/focus.sh" \
            background.color=$SURFACE0 \
            icon.padding_left=10 \
            icon.padding_right=10 \
            label.drawing=off \
        --subscribe focus mouse.clicked focus_change system_woke
  '';

  # Every movable pill, emitted only for the bar that owns it. The definitions
  # live once and take TWO arguments: the target bar client, and the group the
  # pill is being added to (`left`, `center` or `right` — SketchyBar's own three
  # regions). Nix renders the selected blocks into the top and bottom item
  # files. The menu bar always passes `right`, because its left and center are
  # spoken for; the bottom bar passes whatever haus.bar.bottom.items said. They
  # reference $SURFACE0 (from colors.sh) and $HOME, both live when either rc
  # sources its generated item file.
  mkPluginBlocks = sb: side: {
    focus = focusBlock sb side;
    # The clock can opt out of the rice's mono face when its dotted zero reads
    # as an 8 at a glance. Its Nerd Font icon remains in the bar default either
    # way; only the dense date/time label follows clock.monoFont.
    clock = ''
      ${sb} --add item clock ${side} \
          --set clock \
              update_freq=10 \
              icon= \
              icon.color=$PINK \
              label.font="${clockLabelFont}:Bold:${sizes.label}" \
              background.color=$MANTLE \
              background.padding_left=8 \
              background.padding_right=8 \
              script="$HOME/.config/sketchybar/plugins/clock.sh" \
              click_script="open -a 'Notion Calendar'"
    '';
    # Right-click opens Weather; left-click goes through popToggle so barpop
    # guards the popup on the same bar instance that owns the pill.
    weather = ''
      ${sb} --add item weather ${side} \
          --set weather \
              update_freq=600 \
              icon="󰖐" \
              icon.color=$SKY \
              background.color=$SURFACE0 \
              popup.background.border_width=2 \
              popup.background.corner_radius=10 \
              popup.background.border_color=$SURFACE0 \
              popup.background.color=$MANTLE \
              ${popupAlign side} \
              script="$HOME/.config/sketchybar/plugins/weather.sh" \
              click_script="if [ \"\$BUTTON\" = \"right\" ]; then open -a Weather; else ${popToggle sb "weather"} fi" \
          --subscribe weather system_woke mouse.clicked

      WEATHER_POPUP_ITEM=(
          icon.padding_left=10
          label.padding_right=10
          background.height=30
          background.padding_left=0
          background.padding_right=0
          background.color=0x00000000
          background.drawing=off
          icon.font="${barFont}:Bold:${sizes.appIcon}"
          label.font="${barFont}:Regular:${sizes.label}"
      )

      ${sb} --add item weather.location popup.weather \
          --set weather.location "''${WEATHER_POPUP_ITEM[@]}" \
              icon.color=$BLUE label.color=$TEXT
      ${sb} --add item weather.condition popup.weather \
          --set weather.condition "''${WEATHER_POPUP_ITEM[@]}" \
              icon.color=$SKY label.color=$SUBTEXT0
      ${sb} --add item weather.temp popup.weather \
          --set weather.temp "''${WEATHER_POPUP_ITEM[@]}" \
              icon.color=$PEACH label.color=$TEXT
      ${sb} --add item weather.highlow popup.weather \
          --set weather.highlow "''${WEATHER_POPUP_ITEM[@]}" \
              icon.color=$RED label.color=$SUBTEXT0
      ${sb} --add item weather.sun popup.weather \
          --set weather.sun "''${WEATHER_POPUP_ITEM[@]}" \
              icon.color=$YELLOW label.color=$TEXT
      ${sb} --add item weather.wind popup.weather \
          --set weather.wind "''${WEATHER_POPUP_ITEM[@]}" \
              icon.color=$TEAL label.color=$TEXT
      ${sb} --add item weather.humidity popup.weather \
          --set weather.humidity "''${WEATHER_POPUP_ITEM[@]}" \
              icon.color=$SAPPHIRE label.color=$TEXT
      ${sb} --add item weather.uv popup.weather \
          --set weather.uv "''${WEATHER_POPUP_ITEM[@]}" \
              icon.color=$YELLOW label.color=$TEXT
      ${sb} --add item weather.precip popup.weather \
          --set weather.precip "''${WEATHER_POPUP_ITEM[@]}" \
              icon.color=$BLUE label.color=$TEXT

      for i in 0 1 2 3; do
          ${sb} --add item weather.hour.$i popup.weather \
              --set weather.hour.$i "''${WEATHER_POPUP_ITEM[@]}" \
                  icon.color=$LAVENDER label.color=$SUBTEXT0
      done
      for i in 1 2 3; do
          ${sb} --add item weather.forecast.$i popup.weather \
              --set weather.forecast.$i "''${WEATHER_POPUP_ITEM[@]}" \
                  icon.color=$MAUVE label.color=$TEXT
      done
    '';
    # SketchyBar's media_change event is dead on macOS 15.4+, so a detached
    # media-control stream owns repainting. updates=on lets a hidden media pill
    # keep running its watchdog tick and recover a dead stream — and the tick is
    # also what advances a long-form countdown, which no payload announces (see
    # plugins/media.sh), hence 30s rather than the old 60.
    #
    # scroll_texts is deliberately NOT set on here: a long title never scrolls
    # on its own, not even right after a track changes. Hover is the only thing
    # that starts a sweep, and once started it's a one-shot that runs to
    # completion regardless of hover — see media.sh's start_marquee.
    media = ''
      ${sb} --add item media ${side} \
          --set media \
              icon= \
              icon.color=$PINK \
              updates=on \
              update_freq=30 \
              background.color=$SURFACE0 \
              background.padding_left=8 \
              background.padding_right=8 \
              label.max_chars=${toString cfg.media.width} \
              drawing=off \
              popup.background.border_width=2 \
              popup.background.corner_radius=10 \
              popup.background.border_color=$SURFACE0 \
              popup.background.color=$MANTLE \
              ${popupAlign side} \
              popup.horizontal=off \
              script="$HOME/.config/sketchybar/plugins/media.sh" \
              click_script="$HOME/.config/sketchybar/plugins/media.sh click" \
          --subscribe media mouse.clicked mouse.entered mouse.exited mouse.exited.global mouse.scrolled system_woke
      # Exec'd rather than sourced, with its output on /dev/null — so
      # media_stream.sh has to carry the +x bit in git (home.file copies the
      # source mode verbatim). Without it both this launch and media.sh's
      # watchdog restart fail silently and the pill simply never lights up.
      # media_art.sh is launched the same way, from the streamer, and needs it
      # for the same reason; media_lib.sh is sourced, so it stays 644.
      ("$HOME/.config/sketchybar/plugins/media_stream.sh" >/dev/null 2>&1 &)
    '';
    # updates=on is load-bearing: battery.sh hides the pill over the configured
    # threshold, and a when_shown item could never notice charge later dropped.
    battery = ''
      ${sb} --add item battery ${side} \
          --set battery \
              icon.color=$GREEN \
              update_freq=30 \
              updates=on \
              background.color=$SURFACE0 \
              script="$HOME/.config/sketchybar/plugins/battery.sh" \
              click_script="open -a 'System Settings' 'x-apple.systempreferences:com.apple.preference.battery'" \
          --subscribe battery system_woke power_source_change
    '';
    wifi = ''
      ${sb} --add item wifi ${side} \
          --set wifi \
              icon=󰖩 \
              label.drawing=off \
              icon.color=$TEAL \
              background.color=$SURFACE0 \
              icon.padding_left=10 \
              icon.padding_right=10 \
              script="$HOME/.config/sketchybar/plugins/wifi.sh" \
              click_script="open -a 'System Settings' 'x-apple.systempreferences:com.apple.wifi-settings-extension'" \
              update_freq=10
    '';
    # Agent-pane status, for whichever client the pane runs (Claude Code, Codex,
    # Opencode). The refresh is push, not poll: agents-hook.sh invokes
    # agents.sh directly on every agent state change, so the pill updates even
    # while hidden (a drawing=off item's own update_freq never ticks, and custom
    # --trigger events are delivered inconsistently across --reload — neither can
    # revive a hidden pill). update_freq is only a while-visible backstop to reap
    # stale files. Starts hidden; agents.sh flips it on when a pane is live.
    # Popup styling mirrors the apple-logo menu.
    agents =
      let
        # The pill is FOUR items — the bot, then one segment per state — and
        # they have to be ADDED in the order the group packs, not the order
        # they read. A `right` group fills outward from the right edge (the
        # menu bar's clock is furthest right because it is emitted first), so
        # on that side the same four added left-to-right would draw
        # `done working ready bot`: the urgency ladder backwards with the bot
        # on the trailing edge. Adding them reversed there puts the bot at the
        # pill's leading edge and the marks in ready → working → done order on
        # every side. The per-item paddings below are physical left/right and
        # need no mirroring once the order is right.
        pillItems = [
          "agents"
          "agents.ready"
          "agents.working"
          "agents.done"
        ];
        addOrder = if side == "right" then lib.reverseList pillItems else pillItems;
      in
      ''
        ${lib.concatMapStringsSep "\n" (n: "${sb} --add item ${n} ${side}") addOrder}

        ${sb} --set agents \
              update_freq=10 \
              drawing=off \
              label.drawing=off \
              background.drawing=off \
              background.padding_left=0 \
              background.padding_right=0 \
              icon.padding_left=10 \
              icon.padding_right=8 \
              script="$HOME/.config/sketchybar/plugins/agents.sh" \
              click_script="$HOME/.config/sketchybar/plugins/agents.sh" \
          --subscribe agents mouse.clicked system_woke

        # One segment per state — ready, working, done — each a mark and a
        # count in that state's colour, and agents.sh hides the ones sitting at
        # zero. Three items rather than one label because SketchyBar colours a
        # label once, and three colours is the whole point (see agents.sh's
        # "the pill" comment). They carry no background and no background
        # padding: the bracket below draws the single pill behind all four, and
        # a segment with its own would both double the background and space the
        # marks apart like separate items. Only the LAST visible one wants the
        # pill's right padding, but every segment carries it: with the same
        # number on both sides of a gap the eye reads the run as one field
        # either way, and a trailing-padding fixup would have to run on every
        # repaint.
        #
        # `agents.sh click`, not a bare invocation: a click_script does NOT
        # arrive with SENDER=mouse.clicked (that is what the subscription on
        # `agents` above buys), and the plugin's popup branch keys on it. The
        # argument is the same shape the calendar, github and media pills use
        # for exactly this. Subscribing instead would work too and cost a
        # second run of the plugin per click.
        for seg in ready working done; do
          ${sb} --set "agents.$seg" \
                  drawing=off \
                  background.drawing=off \
                  background.padding_left=0 \
                  background.padding_right=0 \
                  icon.padding_left=0 \
                  icon.padding_right=3 \
                  label.padding_left=0 \
                  label.padding_right=10 \
                  label.font="${barFont}:Bold:${sizes.label}" \
                  click_script="$HOME/.config/sketchybar/plugins/agents.sh click"
        done

        # The pill itself. A bracket is the only way to put one background behind
        # items that must colour themselves independently; it is also what keeps
        # the bot and the counts reading as one control rather than four pills
        # that happen to be adjacent. drawing=off to match the members — an
        # all-hidden bracket still paints, so agents.sh turns this off too.
        # It also carries the POPUP, which the bot used to. A popup aligns to the
        # item holding it, and the bot is now a third of this pill's width — a
        # right-aligned dropdown (which is every pill on the menu bar) would hang
        # off to the left of its own pill by however many segments were drawn.
        # The bracket's rect is the whole pill at whatever width it currently is,
        # so the dropdown lines up on either side. agents.sh's $POPUP and the
        # barpop hand-off both name this item.
        #
        # background.padding 0 explicitly, and it is the one place this pill
        # cannot match the others: a member's padding is drawn INSIDE the
        # bracket (it widens the pill rather than the gap) and a bracket's own
        # padding moves nothing at all, so the gutter to the neighbouring pill
        # is whatever THAT pill contributes — 4pt, where every other pair on the
        # bar has 8. 0 here at least keeps the pill's own 10pt inner padding
        # honest; anything else spends it on invisible spacer items.
        ${sb} --add bracket agents.pill agents agents.ready agents.working agents.done \
            --set agents.pill \
                drawing=off \
                background.color=$SURFACE0 \
                background.corner_radius=12 \
                background.height=28 \
                background.padding_left=0 \
                background.padding_right=0 \
                popup.background.border_width=2 \
                popup.background.corner_radius=10 \
                popup.background.border_color=$SURFACE0 \
                popup.background.color=$MANTLE \
                ${popupAlign side} \
                popup.horizontal=off
      '';
    # AI rate-limit gauges (5-hour session + 7-day weekly) and API spend, one row
    # per reporting client. Two feed shapes, both ending in
    # ~/.cache/claude-statusline/usage-*.tsv:
    #   • pushed — modules/ai/statusline.sh stashes the percentages Claude Code
    #     hands every statusline render, then invokes ai_usage.sh when one moves.
    #   • pulled — Codex and Claude (account API calls) and Opencode (a sqlite
    #     read), fetched by claude-statusline-refresh --usage-only. The plugin
    #     kicks that itself on a TTL, which is what keeps this pill honest on a
    #     machine driving a client that pushes nothing — including Claude Code's
    #     own macOS app, which renders no statusline and so pushes nothing either.
    # Each row carries TWO stamps, and the difference is the pill's whole model of
    # itself: column 5 is when the row was WRITTEN (what greys it) and column 9 is
    # when quota was last USED (what `latest` picks on). One column doing both
    # meant a feed's poll rate decided which provider the pill showed.
    # update_freq is the while-visible backstop that rolls a window over to 0% at
    # its reset. Starts hidden until the first row lands.
    aiUsage = ''
      ${sb} --add item ai_usage ${side} \
          --set ai_usage \
              update_freq=15 \
              drawing=off \
              icon.padding_left=10 \
              icon.padding_right=4 \
              label.padding_right=10 \
              label.font="${barFont}:Bold:${sizes.label}" \
              popup.background.border_width=2 \
              popup.background.corner_radius=10 \
              popup.background.border_color=$SURFACE0 \
              popup.background.color=$MANTLE \
              ${popupAlign side} \
              popup.horizontal=off \
              script="$HOME/.config/sketchybar/plugins/ai_usage.sh" \
              click_script="$HOME/.config/sketchybar/plugins/ai_usage.sh" \
          --subscribe ai_usage mouse.clicked system_woke
      # One kick at bar start, backgrounded. The item is drawing=off until a first
      # row exists and a hidden item's update_freq never ticks — so on a machine
      # driving Codex or Opencode this is what pulls the first row and reveals the
      # pill at all. After that the plugin's own TTL keeps the feeds warm.
      ("$HOME/.config/sketchybar/plugins/ai_usage.sh" >/dev/null 2>&1 &)
    '';
    # System readouts. Each pill's colour comes from the --set here (the palette
    # vars are live via colors.sh, sourced by sketchybarrc before this file); the
    # plugin script only refreshes icon+label on its update_freq tick.
    #
    # ── why these two are `--add graph` and not `--add item` ────────────────────
    # A percentage in a bar answers "how busy, right now" and nothing else: it
    # cannot tell you whether 60% is a spike settling or a climb that started
    # five minutes ago, which is the actual question you glance up to ask. A
    # graph item is a normal pill in every other respect — icon, label, popup,
    # click_script all behave — plus a rolling window of the last GRAPH_WIDTH
    # pushed values drawn behind the text. The plugins `--push` one point per
    # tick, so the window is `width × update_freq` seconds wide: about two
    # minutes of CPU, six of memory.
    #
    # The history lives in the RUNNING item, so a bar reload starts the line
    # empty and it fills in over the next window. That is worth naming because
    # it looks like a bug the first time you reload the bar and the graph is a
    # flat line for two minutes: it is drawing exactly what it knows.
    #
    # graph.color is fixed per pill and never touched by the plugins. The line
    # is IDENTITY (which readout is this) and the label is STATE (is it bad) —
    # the same rule the AI-usage dropdown follows, and the reason a pill under
    # load doesn't turn into two things flashing different colours at once.
    # fill_color is the same hue at 0x33 alpha: enough to read the area under
    # the line at a glance, not enough to compete with the pills either side.
    # It is derived from the colors.sh variable rather than written as a hex —
    # `0x33''${PEACH#0xff}` is that palette entry with its opacity swapped — so a
    # nebelung change reaches the fill in the same rebuild it reaches the line.
    cpu = ''
      ${sb} --add graph cpu ${side} 48 \
          --set cpu \
              update_freq=2 \
              icon.color=$PEACH \
              graph.color=$PEACH \
              graph.fill_color=0x33''${PEACH#0xff} \
              graph.line_width=2 \
              background.color=$SURFACE0 \
              background.padding_left=8 \
              background.padding_right=8 \
              popup.background.border_width=2 \
              popup.background.corner_radius=10 \
              popup.background.border_color=$SURFACE0 \
              popup.background.color=$MANTLE \
              ${popupAlign side} \
              popup.horizontal=off \
              script="$HOME/.config/sketchybar/plugins/cpu.sh" \
          --subscribe cpu mouse.clicked system_woke
    '';
    memory = ''
      ${sb} --add graph memory ${side} 48 \
          --set memory \
              update_freq=5 \
              icon.color=$GREEN \
              graph.color=$GREEN \
              graph.fill_color=0x33''${GREEN#0xff} \
              graph.line_width=2 \
              background.color=$SURFACE0 \
              background.padding_left=8 \
              background.padding_right=8 \
              popup.background.border_width=2 \
              popup.background.corner_radius=10 \
              popup.background.border_color=$SURFACE0 \
              popup.background.color=$MANTLE \
              ${popupAlign side} \
              popup.horizontal=off \
              script="$HOME/.config/sketchybar/plugins/memory.sh" \
          --subscribe memory mouse.clicked system_woke
    '';
    volume = ''
      ${sb} --add item volume ${side} \
          --set volume \
              update_freq=5 \
              icon.color=$SKY \
              background.color=$SURFACE0 \
              background.padding_left=8 \
              background.padding_right=8 \
              script="$HOME/.config/sketchybar/plugins/volume.sh" \
              click_script="open -a 'System Settings' 'x-apple.systempreferences:com.apple.Sound-Settings.extension'"
    '';
    # The one meeting you have to be at next, with a click-dropdown that lays the
    # day out as a timeline (done · now · next). No popup children are declared
    # here any more: this pill used to add a fixed `calendar.event.1..5` and hide
    # the unused ones, which is why the dropdown could only ever be five identical
    # one-line rows. calendar.sh now builds `calendar.row.N` per open, the way the
    # AI-usage pill does, so a row can be a section rule, a title or a dim meta
    # line and the popup is exactly as tall as the day is full.
    #
    # click_script rather than a mouse.clicked subscription, and NOT popToggle:
    # the plugin has to see $BUTTON (right-click joins the meeting) and it has to
    # rebuild the rows before revealing them, so it owns the whole gesture and
    # arms barpop itself once the popup is up. `mouse.clicked` is deliberately
    # absent from the subscribe list — with click_script set, subscribing would
    # run this plugin twice per click.
    #
    # label.max_chars is the settled width; scroll_texts is NOT set on here. The
    # plugin turns it on only while the pointer is on the pill — a marquee that
    # armed itself whenever the next event changed is what this replaced, because
    # a bar that moves on its own is a bar you stop reading. That also retired the
    # hover flag file this block used to clear at every bar start; there is no
    # timer left to strand. The `rm` below is what became of that clear — the two
    # files the old marquee kept are dead state now, and nothing else would ever
    # reap them off a machine that has been drawing this pill for months.
    calendar = ''
      rm -f "$HOME/.local/state/haus/calendar/hover" \
            "$HOME/.local/state/haus/calendar/last-event" 2>/dev/null || true
      ${sb} --add item calendar ${side} \
          --set calendar \
              update_freq=${toString cfg.calendar.refresh} \
              icon="󰃭" \
              icon.color=$MAUVE \
              background.color=$SURFACE0 \
              label.max_chars=${toString cfg.calendar.width} \
              popup.background.border_width=2 \
              popup.background.corner_radius=10 \
              popup.background.border_color=$SURFACE0 \
              popup.background.color=$MANTLE \
              ${popupAlign side} \
              script="$HOME/.config/sketchybar/plugins/calendar.sh" \
              click_script="$HOME/.config/sketchybar/plugins/calendar.sh click" \
          --subscribe calendar mouse.entered mouse.exited mouse.exited.global system_woke
    '';
    # Keep-awake controller. The rice-level `awake` CLI + launchd job own the
    # assertion; this popup only chooses a duration and renders state. A bar
    # reload therefore cannot accidentally release an active assertion.
    caffeinate = ''
      ${sb} --add event caffeinate_change
      ${sb} --add item caffeinate ${side} \
          --set caffeinate \
              update_freq=30 \
              icon="󰅶" \
              icon.padding_left=10 \
              icon.padding_right=10 \
              label.padding_right=10 \
              label.font="${barFont}:Bold:${sizes.small}" \
              background.color=$SURFACE0 \
              popup.background.border_width=2 \
              popup.background.corner_radius=10 \
              popup.background.border_color=$SURFACE0 \
              popup.background.color=$MANTLE \
              ${popupAlign side} \
              script="$HOME/.config/sketchybar/plugins/caffeinate.sh" \
          --subscribe caffeinate mouse.clicked caffeinate_change system_woke

      CAFFEINATE_POPUP=(
          icon.padding_left=10
          label.padding_right=10
          background.height=30
          background.padding_left=0
          background.padding_right=0
          background.color=0x00000000
          background.drawing=off
      )
      ${sb} --add item caffeinate.1h popup.caffeinate \
          --set caffeinate.1h "''${CAFFEINATE_POPUP[@]}" icon="1" label="1 hour" \
              click_script="/run/current-system/sw/bin/awake 1h >/dev/null; ${sb} --set caffeinate popup.drawing=off"
      ${sb} --add item caffeinate.2h popup.caffeinate \
          --set caffeinate.2h "''${CAFFEINATE_POPUP[@]}" icon="2" label="2 hours" \
              click_script="/run/current-system/sw/bin/awake 2h >/dev/null; ${sb} --set caffeinate popup.drawing=off"
      ${sb} --add item caffeinate.4h popup.caffeinate \
          --set caffeinate.4h "''${CAFFEINATE_POPUP[@]}" icon="4" label="4 hours" \
              click_script="/run/current-system/sw/bin/awake 4h >/dev/null; ${sb} --set caffeinate popup.drawing=off"
      ${sb} --add item caffeinate.8h popup.caffeinate \
          --set caffeinate.8h "''${CAFFEINATE_POPUP[@]}" icon="8" label="8 hours" \
              click_script="/run/current-system/sw/bin/awake 8h >/dev/null; ${sb} --set caffeinate popup.drawing=off"
      ${sb} --add item caffeinate.custom popup.caffeinate \
          --set caffeinate.custom "''${CAFFEINATE_POPUP[@]}" icon="󰅐" label="Custom hours…" \
              click_script="$HOME/.config/sketchybar/plugins/caffeinate.sh custom"
      ${sb} --add item caffeinate.indefinite popup.caffeinate \
          --set caffeinate.indefinite "''${CAFFEINATE_POPUP[@]}" icon="∞" label="Until stopped" \
              click_script="/run/current-system/sw/bin/awake indefinitely >/dev/null; ${sb} --set caffeinate popup.drawing=off"
      ${sb} --add item caffeinate.stop popup.caffeinate \
          --set caffeinate.stop "''${CAFFEINATE_POPUP[@]}" icon="󰅖" icon.color=$RED label="Allow sleep" \
              click_script="/run/current-system/sw/bin/awake off >/dev/null; ${sb} --set caffeinate popup.drawing=off"
    '';
    elgato = ''
      ${sb} --add item elgato ${side} \
          --set elgato \
              update_freq=5 \
              script="$HOME/.config/sketchybar/plugins/elgato.sh" \
              background.color=$SURFACE0 \
              icon.padding_left=10 \
              icon.padding_right=10 \
              click_script="$HOME/.config/sketchybar/plugins/elgato.sh" \
          --subscribe elgato mouse.clicked
    '';
    # The one pill in the bar that crosses the network, and the only one whose
    # tick deliberately does NOT do its own work: github.sh renders a cache and
    # detaches the `gh` call, then --triggers github_update to repaint. So
    # update_freq here is not a poll interval — that is
    # haus.bar.github.refresh — it is only how often the pill looks at how old
    # its cache is. A minute is far below any legal refresh and costs a cache
    # read.
    #
    # click_script rather than a mouse.clicked subscription, and NOT popToggle:
    # the plugin has to see $BUTTON (right-click refreshes) and it rebuilds the
    # rows before revealing them, so it owns the whole gesture and arms barpop
    # itself once the popup is up. Subscribing to mouse.clicked as well would
    # run the plugin twice per click.
    #
    # `iconWide` rather than `icon`, and symmetric padding rather than the bar's
    # 8/4 default, because this is the rice's one SQUARE glyph and its one pill
    # that spends most of its life with no label. See lib/bar.nix for the first
    # (Nerd Font Mono fits by width, so a square mark comes out ~12% shorter
    # than the tall glyphs beside it at the same point size) and github.sh's
    # render() for the second — the plugin re-sets the padding on every paint,
    # since the label appears and disappears with the count, and these two lines
    # are what the pill looks like before the first one lands.
    github = ''
      ${sb} --add event github_update
      ${sb} --add item github ${side} \
          --set github \
              update_freq=60 \
              icon="" \
              icon.color=$TEXT \
              icon.font="${barFont}:Bold:${sizes.iconWide}" \
              icon.padding_left=10 \
              icon.padding_right=10 \
              background.color=$SURFACE0 \
              popup.background.border_width=2 \
              popup.background.corner_radius=10 \
              popup.background.border_color=$SURFACE0 \
              popup.background.color=$MANTLE \
              ${popupAlign side} \
              script="$HOME/.config/sketchybar/plugins/github.sh" \
              click_script="$HOME/.config/sketchybar/plugins/github.sh click" \
          --subscribe github github_update system_woke

      # First paint without waiting up to a minute for the tick — and, on a
      # machine with no cache yet, the fetch that fills it. Backgrounded: a bar
      # start must never block on GitHub.
      ("$HOME/.config/sketchybar/plugins/github.sh" >/dev/null 2>&1 &)
    '';
    harvest = ''
      ${sb} --add event harvest_update
      ${sb} --add item harvest ${side} \
          --set harvest \
              update_freq=3 \
              script="$HOME/.config/sketchybar/plugins/harvest.sh" \
          --subscribe harvest mouse.clicked harvest_update system_woke
    '';
    # The bell that opens trill's inbox. It is drawn with an icon and no label
    # because it has no count to carry (see widgets.nix), and the plugin turns
    # its own drawing off on a Mac with no Trill.app — which is most of them,
    # since trill is deliberately not a haus flake input.
    #
    # `updates=on` is what makes that reversible, and it is load-bearing rather
    # than tidy: BOTH bars default to `updates=when_shown`, which SketchyBar
    # applies to EVENT DELIVERY and not only to the tick, so a pill that hid
    # itself is never dispatched to again and the script that would unhide it
    # never runs. Installing Trill.app would otherwise leave the bell invisible
    # until the next rebuild. See AGENTS.md's box on exactly this trap.
    trill = ''
      ${sb} --add item trill ${side} \
          --set trill \
              update_freq=30 \
              updates=on \
              icon="󰂚" \
              icon.color=$TEXT \
              icon.padding_left=10 \
              icon.padding_right=10 \
              background.color=$SURFACE0 \
              label.drawing=off \
              script="$HOME/.config/sketchybar/plugins/trill.sh" \
          --subscribe trill mouse.clicked system_woke
    '';
  };
  # Item blocks sit in an attrset (no inherent order), so emission follows these
  # fixed left-to-right orders — only the ones each bar owns are drawn.
  coreOrder = [
    "clock"
    "weather"
    "media"
    "battery"
    "wifi"
  ];
  extraOrder = [
    # Beside the Focus pill, which `itemOrder` slots in just before this list:
    # the bell and the moon are the two halves of one question — what is
    # reaching me, and is anything allowed to — so they read as a pair.
    "trill"
    "agents"
    "aiUsage"
    "github"
    "cpu"
    "memory"
    "volume"
    "calendar"
    "caffeinate"
    "elgato"
    "harvest"
  ];
  itemOrder = coreOrder ++ [ "focus" ] ++ extraOrder;

  # ---- widgets: the open form, and the sugar over it --------------------------
  # `haus.bar.widgets.<name>` is what a pill IS now; `bar.items` and
  # `bar.bottom.items` are two closed submodules that write into it. The bundled
  # sixteen are PRE-DECLARED below, so nothing about the old surface changes
  # meaning — every leaf keeps its default, its description and its effect — and
  # a rice that isn't this one can finally add a seventeenth pill.
  #
  # The direction of the sugar is deliberate: the tables write into `widgets`
  # rather than `widgets` being read back out of them. That is what makes the
  # open form the single source the emission reads, so a bundled pill and a
  # stranger's arrive at the bar down the same path.
  widgetTable = import ./widgets.nix;
  panes = import ../lib/settings-panes.nix;
  bundledNames = builtins.attrNames widgetTable;
  # The one entry in that table which draws no pill: a deprecated alias, folded
  # into the widget it names rather than pre-declared as one of its own.
  aliasOf = name: widgetTable.${name}.alias or null;
  drawnBundled = builtins.filter (name: aliasOf name == null) bundledNames;
  widgets = cfg.widgets;
  # A pill this repo ships, as opposed to one a rice declared. The distinction
  # is only ever used to REFUSE something (a `command` on a bundled pill, a
  # stranger's widget claiming a bundled name), never to give the bundled ones a
  # capability — see the assertions below.
  isBundled = name: builtins.elem name drawnBundled;
  userWidgetNames = builtins.filter (name: !(isBundled name)) (builtins.attrNames widgets);

  # Where a widget sits, normalised to the one spelling the emission uses:
  # "menu-bar", or "bottom-<side>". `bar.bottom.items` writes the bare side
  # names — which is the spelling that option always took — so both are accepted
  # and mean the bottom bar, exactly as that option's values always did.
  placementOf =
    name:
    let
      p = widgets.${name}.placement or null;
    in
    if p == null then
      "menu-bar"
    else if builtins.elem p bottomSides then
      "bottom-${p}"
    else
      p;
  onBottom = name: lib.hasPrefix "bottom-" (placementOf name);

  # Every widget that should be drawn at all: switched on, and with the room
  # behind it actually present. One list for both bars, split by placement
  # below — so "is this pill live" is answered once.
  liveWidgets = builtins.filter (name: (widgets.${name}.enable or false) && contributed name) (
    lib.unique (itemOrder ++ userWidgetNames)
  );

  # ---- the bar's cards in core's manual-click deck ---------------------------
  # `widgets.<n>.permissions` has always declared what a pill will ask macOS
  # for; until now it was a declaration nobody read, which is how the calendar
  # pill shipped without a word about Calendar access and the media pill's
  # Automation note lived only inside one line of `haus doctor`. Generating the
  # deck FROM that table is what stops the two drifting: a pill that gains a
  # grant gains a card, in one edit, in the file that already had to know.
  #
  # One card per (live pill × grant), so a person is asked only about pills
  # actually on their bar — and asked once per pill rather than once per
  # service, because two pills wanting Automation are two different sentences
  # about why.
  permissionCopy = {
    accessibility = {
      label = "Accessibility";
      pane = panes.accessibility;
      needs = "reads or drives another app's interface";
    };
    automation = {
      label = "Automation";
      pane = panes.automation;
      needs = "asks another app a question through AppleScript";
    };
    calendar = {
      label = "Calendar";
      pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars";
      needs = "reads your events";
    };
    contacts = {
      label = "Contacts";
      pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts";
      needs = "reads your contacts";
    };
    full-disk-access = {
      label = "Full Disk Access";
      pane = panes.fullDiskAccess;
      needs = "reads a file macOS keeps behind Full Disk Access";
    };
    location = {
      label = "Location";
      pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices";
      needs = "needs to know where you are";
    };
    microphone = {
      label = "Microphone";
      pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone";
      needs = "listens";
    };
    photos = {
      label = "Photos";
      pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos";
      needs = "reads your photo library";
    };
    reminders = {
      label = "Reminders";
      pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders";
      needs = "reads your reminders";
    };
    screen-recording = {
      label = "Screen Recording";
      pane = panes.screenRecording;
      needs = "captures the screen";
    };
    # `network` is in the enum and is deliberately NOT here: nothing on macOS
    # gates outbound network access behind a grant somebody clicks, so a card
    # for it would be a step nobody can take. The enum records what a pill
    # reaches for; the deck only ever carries what a person can actually do.
  };

  permissionCards = lib.listToAttrs (
    lib.concatMap (
      name:
      map (
        perm:
        let
          copy = permissionCopy.${perm};
        in
        {
          name = "bar-${name}-${perm}";
          value = {
            order = 50;
            title = "${copy.label} — the ${name} pill";
            why = "The ${name} pill ${copy.needs}. macOS asks for this the first time the pill runs; every one of them degrades rather than breaking if you say no.";
            cost = "the pill still draws, and the part of it that needs this stays empty";
            # No `check` on any of these, and none is possible: macOS exposes
            # no way to ask whether ANOTHER app holds a grant, and every API
            # that reports one asks for it first — which a health check must
            # never do. So these are taken on your word or not at all, and the
            # wizard says so on each of them.
            pane = copy.pane;
            steps = [ "Turn sketchybar on in the list — the bar is what asks, whichever pill wanted it" ];
          };
        }
      ) (lib.filter (perm: permissionCopy ? ${perm}) (widgets.${name}.permissions or [ ]))
    ) liveWidgets
  );

  # A widget a rice declared, rendered as a SketchyBar block. Deliberately
  # small: one item, one script, one interval, and the same background and
  # padding every bundled pill wears, so a stranger's widget looks like it
  # belongs on this bar rather than like a patch on it. Anything richer — a
  # dropdown, click gestures, a colour that says something — is what writing a
  # room is for, and this is the line between the two.
  #
  # `icon.drawing` follows whether an icon was given: SketchyBar reserves the
  # icon's padding even for an empty string, so a widget with no glyph would
  # otherwise draw a pill with a blank gap where one would go.
  userWidgetBlock =
    sb: side: name:
    let
      w = widgets.${name};
      freq = if w.interval != null then w.interval else 60;
    in
    ''
      ${sb} --add item ${name} ${side} \
          --set ${name} \
              update_freq=${toString freq} \
              icon=${lib.escapeShellArg w.icon} \
              icon.drawing=${if w.icon == "" then "off" else "on"} \
              icon.color=$TEAL \
              background.color=$SURFACE0 \
              label.font="${barFont}:Bold:${sizes.label}" \
              script=${lib.escapeShellArg w.command} \
          --subscribe ${name} system_woke
    '';

  # The interval override, for a BUNDLED pill whose block already wrote an
  # update_freq of its own. Emitted after that block rather than woven into it:
  # the blocks are hand-written SketchyBar runs, several of them interpolating
  # their rate from an older option (`haus.bar.calendar.refresh`), and a `--set`
  # that lands after the `--add` wins with no ambiguity about which. Nothing at
  # all is emitted when the rice said nothing, so a bar that never mentions
  # `interval` renders byte-identically to before this existed.
  intervalOverride =
    sb: name:
    let
      chosen = widgets.${name}.interval or null;
      shipped = widgetTable.${name}.interval or null;
    in
    lib.optionalString (chosen != null && chosen != shipped) ''
      ${sb} --set ${itemId name} update_freq=${toString chosen}
    '';

  # One pill's block, whichever kind it is. This is the whole reason the open
  # form is worth having: past this point the emission never asks again whether
  # a pill is haus's or yours.
  widgetBlock =
    sb: side: name:
    if isBundled name then
      (mkPluginBlocks sb side).${name} + intervalOverride sb name
    else
      userWidgetBlock sb side name;

  # ---- what a widget may be called -------------------------------------------
  # The item ids the bar draws WITHOUT going through the widget table, so a
  # widget may not claim one. They come from three places, none of which the
  # emission above can see: the hand-written left side of sketchybarrc (the
  # logo, the front app, the workspace and launcher pill prefixes, the position
  # and aerospace watchers), the tour's own pill, and `ai_usage` — which is
  # `aiUsage` renamed by `itemId`, so the collision is with a name that never
  # appears in the widget table at all.
  #
  # A prefix rather than a name for `space.` and `launcher.`: those are emitted
  # one per workspace (`space.T`, `launcher.g`), so the reserved thing is the
  # namespace. A widget name may not contain a dot in any case, which is what
  # makes checking the prefix alone enough.
  reservedItemIds = [
    "haus"
    "front_app"
    "page"
    "empty_workspace"
    "last_closed_app"
    "aerospace_watcher"
    "bar_position"
    "tour"
    "space"
    "launcher"
    "ai_usage"
  ];
  # A SketchyBar item id as it has to survive being written into a generated
  # shell script as a bare word: no space (which would split into item + group),
  # no dot (which is how SketchyBar spells a popup child and how the bar spells
  # its per-workspace pills), nothing that could be shell syntax.
  validWidgetName =
    name:
    builtins.match "[A-Za-z0-9][A-Za-z0-9_-]*" name != null && !(builtins.elem name reservedItemIds);

  # Is the room BEHIND this pill actually here? A pill the bar draws for another
  # room is that room's feature (modules/lib/contrib.nix): the bar owns where it
  # sits and how it looks, the source room owns whether there is anything to
  # show. Asking for one whose room is off used to draw a permanently dormant
  # pill — silent, and indistinguishable from a broken one — so the bar leaves it
  # out and the source room warns by name (see modules/ai).
  #
  # Read by BOTH bars: a contribution that vanished from the menu bar and stayed
  # on the bottom one would be the same dead pill, one edge down.
  # `aiUsage` is deliberately NOT here, though it sits beside `agents` in the
  # extras and reads the same client list: it renders usage numbers a client
  # wrote to disk, and a client this rice never installed still writes them. The
  # `agents` pill is different — its writer is `agent-state`, which the AI room
  # ships or does not.
  # `focus` is the second, and it is the one that was gated by NAME before the
  # widget table existed — twice, once per bar. `bar.items` has no switch for it
  # (it rides the Focus room), so under the old shape there was no way to ask
  # for it without the room. The open form removes that accident:
  # `widgets.focus.enable = true` is now a thing a desktop can write, and with
  # the room off it would draw a moon whose click_script is a
  # `~/.local/bin/focus` only that room installs — a pill that does nothing,
  # forever. Same gate, said once now instead of per bar.
  #
  # `page` was a third entry here and is not a widget at all any more: a page is
  # a property of the WORKSPACE you are on, so its readout belongs beside the
  # workspace pills in the menu bar's hand-written left group rather than in a
  # table of movable readouts. See `windowsConfigSh` and sketchybarrc.
  contributed =
    name:
    if name == "agents" then
      config.haus._contrib.bar.agents.enable
    else if name == "focus" then
      config.haus._contrib.bar.focus.enable
    else
      true;

  # ---- the second bar's three groups -----------------------------------------
  # The three groups themselves. Which pill is in which is `placementOf`'s
  # answer now — `haus.bar.bottom.items.<pill>` writes that field rather than
  # being read here — but the LIST still lives in one file shared with
  # options.nix, for the reason sides.nix gives.
  bottomSides = import ./sides.nix;

  # The order pills are emitted in: the bundled ones in the fixed left-to-right
  # order above, then whatever a rice declared, alphabetically. A stranger's
  # widget lands outboard of haus's own rather than interleaved, which is the
  # only stable answer available — `itemOrder` is an editorial sequence, and
  # there is no field on a widget that could name a position in it without
  # inventing an ordering surface nobody asked for yet.
  emissionOrder = itemOrder ++ userWidgetNames;

  # The pills each group claims, in that order. SketchyBar packs a group outward
  # from its own edge, so `right` still reads outside-in (clock furthest right,
  # exactly as on the menu bar) while `left` fills rightward from the left edge —
  # the two are mirrors of one list, not two lists.
  bottomGroup =
    side:
    lib.optionals cfg.bottom.enable (
      lib.filter (name: placementOf name == "bottom-${side}") (
        lib.filter (name: builtins.elem name liveWidgets) emissionOrder
      )
    );

  # Every pill on the SECOND bar, whichever group it sits in, and then the ones
  # left for the menu bar. A pill MOVES rather than duplicating: a bottom
  # placement takes it off the top, so there is one switch per pill per bar and
  # never two live copies of a readout racing each other's update_freq. This
  # flattened list is what the "is it down there?" questions read — the top bar's
  # exclusion, the bar.sh routing table, the media/calendar closure — none of
  # which care about the group.
  bottomItems = lib.concatMap bottomGroup bottomSides;
  topItems = lib.filter (
    name: builtins.elem name liveWidgets && !(builtins.elem name bottomItems)
  ) emissionOrder;

  # nix name -> the item name SketchyBar knows it by. Identity for all but the
  # camel-cased one, and the plugins' own $NAME is the sketchybar side — so this
  # is what the routing list in bar.sh has to be written in.
  itemId = name: if name == "aiUsage" then "ai_usage" else name;

  topItemsSh = ''
    #!/bin/bash
    # GENERATED from haus.bar.widgets (which haus.bar.items, and the rooms that
    # contribute a pill, write into) by modules/bar/default.nix — do not edit.
  ''
  + lib.concatMapStrings (widgetBlock barTopPath "right") topItems
  # The menu bar's only edge group is `right`; its left edge is the hand-written
  # logo, which zeroes its own padding_left in sketchybarrc for the same reason.
  + edgePad barTopPath "right" topItems;

  # The same blocks again, emitted against the OTHER bar and grouped by side.
  # $SB is set by bar.sh, which bar-bottomrc sources before this file — an
  # absolute path to the `bar-bottom` symlink, so both the `--add`s here and
  # every click_script string they carry address the bottom instance. Emitting
  # `sketchybar` down here would silently build the whole strip on the top bar
  # instead.
  bottomItemsSh = ''
    #!/bin/bash
    # GENERATED from haus.bar.widgets' placements (which haus.bar.bottom.items
    # writes into) by modules/bar/default.nix — do not edit. One
    # `# --- <side>` run per group, in left/center/right order.
  ''
  + lib.concatMapStrings (
    side:
    let
      names = bottomGroup side;
    in
    lib.optionalString (names != [ ]) (
      "\n# --- ${side} ---\n"
      + lib.concatMapStrings (widgetBlock "$SB" side) names
      # Both of the bottom bar's outer groups get the same treatment as the menu
      # bar's.
      + edgePad "$SB" side names
    )
  ) bottomSides;

  # Which bar a plugin should talk to. Sourced by every plugin that can end up on
  # either one, and the answer is nearly always $BAR_NAME: SketchyBar exports it
  # into every script and click_script it runs, so a pill's own update knows the
  # instance that asked for it without anything being generated at all.
  #
  # The list is the fallback for the OTHER caller — a plugin invoked by a HOOK
  # rather than by a bar (agents-hook.sh on an agent state change, the
  # statusline's ai_usage push). Those have no bar, hence no $BAR_NAME, so they
  # fall back to the item they are updating: $NAME when the caller set one, else
  # the BAR_ITEM the plugin declares about itself.
  barSh = ''
    #!/bin/bash
    # GENERATED from haus.bar.bottom.items by modules/bar/default.nix — do not
    # edit. Sets $SB to the SketchyBar instance this invocation belongs to.
    BAR_TOP="${barTopPath}"
    BAR_BOTTOM="${barBottomPath}"
    BAR_BOTTOM_ITEMS="${lib.concatMapStringsSep " " itemId bottomItems}"

    case "''${BAR_NAME:-}" in
      bar-bottom) SB="$BAR_BOTTOM" ;;
      ?*) SB="$BAR_TOP" ;;
      *)
        SB="$BAR_TOP"
        bar_item="''${BAR_ITEM:-''${NAME:-}}"
        if [ -n "$bar_item" ]; then
          case " $BAR_BOTTOM_ITEMS " in
            *" $bar_item "*) SB="$BAR_BOTTOM" ;;
          esac
        fi
        ;;
    esac
  '';

  # The one windows behaviour the BAR implements: gravity (haus.windows.gravity).
  # It lives here because front_app_switched is the only cheap signal a ⌘Q gives
  # and aerospace.toml has no hook for it — see plugins/empty_workspace.sh. The
  # rc gates the item's very existence on this rather than letting the plugin
  # exit early: the item is subscribed to an event that fires on every app
  # switch, so "off" should cost no process at all, not a cheap one.
  #
  # $BAR_PAGES rides along because it asks the same question of the same room: a
  # PAGE is an AeroSpace workspace with a `/` in its name (`T/<repo>`, the page
  # lanes/lane-open.sh tiles onto), so with no tiler there is no page to name and
  # no workspace-change event to hear about one. The pill it gates sits in the
  # hand-written LEFT group beside the front app, not in the widget table: it
  # qualifies which workspace you are on, so it belongs with the workspace pills
  # and not among the movable readouts. It was `haus.bar.items.page` — a movable
  # pill, drawn only on `T/*` — until 2026-08-19.
  #
  # $BAR_TILING is the same question a third time: which SHAPE leader→. last
  # dealt the focused workspace into (windows/scripts/tiling-mode.sh). Separate
  # from $BAR_PAGES despite reading the same option today, because they gate two
  # different pills whose reasons to exist are unrelated — a machine could
  # plausibly want one and not the other, and one name meaning two things is how
  # that becomes impossible to express.
  windowsConfigSh = ''
    #!/bin/bash
    # GENERATED from haus.windows.* by modules/bar/default.nix — do not edit.
    BAR_GRAVITY="${if config.haus.windows.enable && config.haus.windows.gravity then "1" else "0"}"
    BAR_PAGES="${if config.haus.windows.enable then "1" else "0"}"
    BAR_TILING="${if config.haus.windows.enable then "1" else "0"}"
  '';

  # Bar position (haus.bar.position). Sourced by sketchybarrc — which sets
  # `position=` / `topmost=` on --bar from these two — and, in auto mode, re-run
  # by plugins/position.sh on every display_change. bar_position() echoes the
  # position to hand sketchybar. In auto mode "docked" means any non-built-in
  # display is attached: system_profiler is the only guaranteed source of a
  # display's connection type, so it (not a bare display count) is what tells a
  # clamshell external apart from the built-in. It's slow (~1s) but
  # display_change fires rarely, so the cost is only paid on dock/undock/boot.
  #
  # bar_topmost() answers from BAR_POSITION_MODE alone and so costs nothing —
  # only the fixed `bottom` mode is lifted, for the reasons in its own comment.
  positionSh = ''
    #!/bin/bash
    # GENERATED from haus.bar.position by modules/bar/default.nix — do not edit.
    BAR_POSITION_MODE="${config.haus.bar.position}"

    bar_position() {
      case "$BAR_POSITION_MODE" in
        top | bottom) echo "$BAR_POSITION_MODE" ;;
        auto)
          local info total internal
          info="$(system_profiler SPDisplaysDataType 2>/dev/null)"
          total="$(grep -c 'Resolution:' <<<"$info")"
          internal="$(grep -c 'Connection Type: Internal' <<<"$info")"
          if [ "$(( total - internal ))" -gt 0 ]; then echo bottom; else echo top; fi
          ;;
      esac
    }

    # Which window level the bar draws at. Keyed on the MODE, not on the
    # resolved position — see the `auto` carve-out below — so the answer is
    # fixed for the life of the process and plugins/position.sh never re-sends
    # it (bar_manager_set_topmost has no unchanged-guard: it calls
    # bar_manager_reset() every time, tearing down and rebuilding every bar and
    # item window, where re-sending the same `position=` is a real no-op).
    #
    # SketchyBar draws at kCGBackstopMenuLevel (-20), BELOW normal windows. At
    # the top that costs nothing: macOS reserves the menu-bar strip, so nothing
    # tiles into it and nothing is there to shadow it. (Fullscreen is not the
    # reason to stay low — a bar leaves a fullscreen space by space TYPE, not by
    # level: SLSSpaceGetType == 4, with show_in_fullscreen off.)
    #
    # At the bottom macOS reserves nothing, so windows carves the room out of its
    # own outer-bottom gap — and the tiled window directly above then drops its
    # macOS shadow straight down into that gap. At -20 the shadow composites
    # OVER the bar, darkening the strip and making it read as recessed. Not a
    # transparency problem: an opaque `color=` is painted over just the same.
    # `topmost=window` (kCGFloatingWindowLevel, 3) lifts the bar above the
    # window — and so above its shadow — with the floating-pill look intact.
    #
    # `auto` deliberately does NOT get the lift, even though it resolves to
    # `bottom` while docked. Lifting is only safe where the room underneath is
    # actually reserved, and in auto mode it isn't: windows's outerBottom is
    # `monLine (gap 10) barEdge` (modules/windows/default.nix), because
    # AeroSpace gaps can't flip per dock-state and the built-in has to keep a
    # bottom gap sized for the undocked case, when the bar is up at the top.
    # Docked with the lid open the bar draws along the BOTTOM of both displays,
    # so on the built-in it already overlaps the tiled windows — windows's comment
    # calls that out. Today the window covers the bar there; at level 3 the bar
    # would cover the bottom ~26pt of every window on the laptop screen instead,
    # which is a good deal worse than a shadow. Fixed `position = "bottom"`
    # reserves barEdge — this bar's own height — on both displays and is safe, as
    # is the dedicated second bar (haus.bar.bottom.enable), which reserves its
    # own shorter bottomEdge unconditionally.
    bar_topmost() {
      case "$BAR_POSITION_MODE" in
        bottom) echo window ;;
        *) echo off ;;
      esac
    }
  '';

  # The haus-tour pill (plugins/tour.sh) — the first-run tutor. It must live on
  # the RIGHT (launch mode replaces the LEFT side of the bar exactly when the
  # user is mid-step), but --move'd next to the clock at the far right: added
  # last it would land nearest the center, which a MacBook notch covers. It is
  # still sourced by sketchybarrc AFTER the other right-side items so `init`
  # sees them all — mid-tour it hides them (tour.sh mute) to make room.
  # Empty when the tour isn't wired. The built-in tour needs windows because its
  # first three moves teach the leader; a custom tour can consist entirely of
  # other existing signals (for example Pounce), so it needs only Bar itself.
  # `init` repaints whatever state the last session left: mid-tour step, done
  # (hidden), or the dormant hint.
  customTourSteps = config.haus.tour.steps;
  customTour = customTourSteps != null;
  tourWired = config.haus.tour.enable && (customTour || config.haus.windows.enable);
  topRightItems = topItems;
  tourAnchor = if topRightItems == [ ] then null else itemId (builtins.head topRightItems);
  tourItemSh = ''
    #!/bin/bash
    # GENERATED from haus.tour.* by modules/bar/default.nix — do not edit.
  ''
  + lib.optionalString tourWired ''
    sketchybar --add item tour right \
        --set tour \
            drawing=off \
            icon.padding_left=10 \
            icon.padding_right=4 \
            label.padding_right=10 \
            label.font="${barFont}:Bold:${sizes.small}" \
            background.color=$MANTLE \
            click_script="$HOME/.config/sketchybar/plugins/tour.sh click"
    ${lib.optionalString (tourAnchor != null) "sketchybar --move tour after ${tourAnchor}"}
    "$HOME/.config/sketchybar/plugins/tour.sh" init
  '';
  # The resolved keymap (../lib/keys.nix). The tour's prompts must name the keys
  # THIS machine is bound to — a tutor telling you to tap Caps Lock on a rice where
  # keys.leader = "alt-space" teaches a chord that does nothing.
  k = import ../lib/keys.nix {
    inherit lib;
    keys = config.haus.keys;
  };

  # Placeholders an authored hint may use; tour.sh expands them at render time
  # from the same values the built-in lap interpolates (see `expand_keys`).
  knownPlaceholders = [
    "palette"
    "leader"
    "leaderName"
  ];
  badPlaceholders = lib.unique (
    lib.filter (name: !(builtins.elem name knownPlaceholders)) (
      lib.concatMap (
        step:
        map (m: builtins.elemAt m 0) (
          lib.filter builtins.isList (builtins.split "\\{([A-Za-z]+)\\}" step.hint)
        )
      ) (if customTour then customTourSteps else [ ])
    )
  );

  customStepCases =
    field:
    lib.concatStringsSep "\n" (
      lib.imap0 (
        index: step: "      ${toString (index + 1)}) printf '%s\\n' ${lib.escapeShellArg step.${field}} ;;"
      ) (if customTour then customTourSteps else [ ])
    );

  tourConfigSh = ''
        #!/bin/bash
        # GENERATED from haus.tour.steps + launcher.enable + keys.* by
        # modules/bar/default.nix — do not edit. TOUR_CUSTOM switches from the
        # built-in four-move lap to the authored list below. TOUR_HAS_PALETTE decides
        # whether the built-in lap has a step 4 (it needs pounce); the glyphs name the
        # leader and palette chords this rice actually binds.
        TOUR_CUSTOM=${if customTour then "1" else "0"}
        TOUR_CUSTOM_COUNT=${toString (if customTour then builtins.length customTourSteps else 0)}
        TOUR_HAS_PALETTE=${if config.haus.launcher.enable && k.palette != null then "1" else "0"}
        TOUR_LEADER=${lib.escapeShellArg (if k.leader != null then k.leader.glyph else "⇪")}
        TOUR_LEADER_NAME=${lib.escapeShellArg (if k.leader != null then k.leader.name else "Caps Lock")}
        TOUR_PALETTE=${lib.escapeShellArg (if k.palette != null then k.palette.glyph else "⌘ Space")}

        tour_custom_hint() {
          case "$1" in
    ${customStepCases "hint"}
            *) return 1 ;;
          esac
        }

        tour_custom_detect() {
          case "$1" in
    ${customStepCases "detect"}
            *) return 1 ;;
          esac
        }
  '';
in
lib.mkIf config.haus.bar.enable {
  # One card per pill × grant, generated above from `widgets.<n>.permissions`.
  # Core renders them; this room never learns what a wizard looks like.
  haus._contrib.permissions = permissionCards;

  # The octocat pill's push door. It TRIGGERS rather than fetches: github.sh
  # already knows when it should cross the network (and now asks the bridge as
  # part of deciding), so all a delivery has to do is wake it. Doing the fetch
  # here instead would be a second copy of that decision, in a room that cannot
  # see the pill's sources.
  #
  # No event filter: every event this machine subscribes to can change what the
  # pill counts, and the tick it wakes is the thing that decides whether the
  # cache is actually stale.
  haus._contrib.github.subscribers.bar-github-pill =
    lib.mkIf (builtins.elem "github" (topItems ++ bottomItems))
      {
        command = ''
          # $SB routes to whichever bar carries the pill — BAR_ITEM is the
          # fallback bar.sh reads when there is no $BAR_NAME, which is exactly
          # the case here: a subscriber has no bar, it has a delivery.
          BAR_ITEM=github
          source "$HOME/.config/sketchybar/bar.sh"
          "$SB" --trigger github_update
        '';
      };

  warnings =
    lib.optional
      (
        customTour
        && !config.haus.windows.enable
        && lib.any (
          step:
          builtins.elem step.detect [
            "launch"
            "workspace"
            "navigate"
            "resize"
          ]
        ) customTourSteps
      )
      "haus.tour.steps uses a windows detector while haus.windows.enable is false; that step can only be skipped."
    ++
      lib.optional
        (
          customTour
          && (!config.haus.launcher.enable || k.palette == null)
          && lib.any (step: step.detect == "palette") customTourSteps
        )
        "haus.tour.steps uses the palette detector while Pounce or its palette binding is disabled; that step can only be skipped."
    ++
      # A misspelled placeholder renders literally — `{palete}` sits in the bar
      # of whoever IMPORTED the rice, and the author, whose own hints they never
      # re-read, is the last person to find out. Same asymmetry as a pack's
      # leader key: check the thing the author can't see.
      lib.optional (customTour && badPlaceholders != [ ]) (
        "haus.tour.steps names unknown placeholders: "
        + lib.concatStringsSep ", " badPlaceholders
        + ". Known: {palette}, {leader}, {leaderName}; anything else renders as typed."
      )
    ++
      # A bar with nothing on it still costs a launchd job and, via windows, a
      # 32pt strip of every display — and it draws no pill to explain either.
      lib.optional (cfg.bottom.enable && bottomItems == [ ]) (
        "haus.bar.bottom.enable is on but no pill lands on the second bar — nothing in haus.bar.bottom.items, or the rooms behind the pills it names are off — so it draws an empty strip and still reserves room at the bottom of every display."
      )
    ++
      # Both bars on the same edge overlap: SketchyBar pins each instance to the
      # edge it was told, and neither knows the other is there.
      lib.optional (cfg.bottom.enable && cfg.position != "top") (
        "haus.bar.bottom.enable is on while haus.bar.position = \"${cfg.position}\"; the two bars share the bottom edge and will draw on top of each other (position = \"auto\" only when an external display is attached)."
      )
    ++
      # A github pill with nothing to count. It hides itself rather than drawing
      # a permanent zero (github.sh's first exit), so without this the symptom
      # is a pill you asked for that never appears — and the cause is one option
      # away, in an owner nobody set.
      lib.optional (builtins.elem "github" (topItems ++ bottomItems) && ghSources == [ ]) (
        "haus.bar.items.github is on but haus.bar.github.sources is empty, so the pill draws nothing at all."
        +
          lib.optionalString (gitOrg == "")
            " The default sources are the owner's red default branches and its open PRs, and they are empty because haus.git.org names no owner."
      );

  # ---- the github pill's hard requirements -----------------------------------
  # Assertions rather than warnings: each of these is a pill that cannot work,
  # as opposed to one that merely won't draw. A mixed-kind source in particular
  # would be silently interpreted as one of the kinds it named, which is the
  # class of bug this whole option shape exists to avoid.
  assertions =
    let
      indexed = lib.imap0 (i: s: { inherit i s; }) ghSources;
      wrongKinds = lib.filter (e: builtins.length (ghKindsSet e.s) != 1) indexed;
      orgless = lib.filter (e: e.s.ci && ghOrg e.s == "") indexed;
      # The source table is LINE-delimited, so a newline inside any field is not
      # a formatting quirk — it ends the record. A `command` written as a Nix
      # `''\'''\''…''\'''\''` block is the way this happens: the payload truncates at its
      # first line and every line after it is parsed as a whole extra source,
      # taking that entry's title for its org and its icon for its severity. It
      # evaluates, it builds, and the pill grows a phantom row.
      multiline = lib.filter (
        e:
        lib.any (f: lib.hasInfix "\n" f) [
          (ghPayload e.s)
          (ghOrg e.s)
          e.s.title
          (ghIcon e.s)
        ]
      ) indexed;
      drawn = builtins.elem "github" (topItems ++ bottomItems);
    in
    map (e: {
      assertion = false;
      message = "haus.bar.github.sources[${toString e.i}] names ${toString (builtins.length (ghKindsSet e.s))} kinds (${lib.concatStringsSep ", " (ghKindsSet e.s)}); each source sets exactly one of search, ci or command.";
    }) wrongKinds
    ++ map (e: {
      assertion = false;
      message = "haus.bar.github.sources[${toString e.i}] is a ci source with no owner to ask about: set haus.git.org, or that source's own `org`.";
    }) orgless
    ++ map (e: {
      assertion = false;
      message = "haus.bar.github.sources[${toString e.i}] holds a newline. The pill reads one source per line, so a multi-line command (a Nix ''…'' block) would be truncated at its first line and the rest parsed as extra sources. Write it as one line, or put it in a script and name that.";
    }) multiline
    ++ [
      {
        assertion = !(drawn && !config.haus.developer.git.enable);
        message = "haus.bar.items.github is on but haus.developer.git.enable is off. The pill queries GitHub through `gh`, which that pack is what installs.";
      }
    ]
    # ---- what a widget may not do ------------------------------------------
    # The open form's three refusals. All assertions rather than warnings,
    # because each names a configuration whose only two readings are "you meant
    # something we can't do" and "you meant something we would do WRONG" — and
    # the wrong half is silent in every case: a bundled pill quietly keeping
    # haus's script, a stranger's widget quietly inheriting a bundled pill's
    # gestures, a pill quietly drawn on a bar that isn't there.
    ++
      map
        (name: {
          assertion = false;
          message = "haus.bar.widgets.${name}.command is set, but `${name}` is a pill haus ships: its behaviour is haus's own plugin, and its dropdown, click gestures and colour rules are written against that script. Setting a command here would replace only half of it. Declare your own widget under a different name instead — `haus.bar.widgets.my${
            lib.toUpper (builtins.substring 0 1 name)
          }${
            builtins.substring 1 (builtins.stringLength name) name
          }`, say — and turn this one off with `haus.bar.items.${name} = false`.";
        })
        (
          builtins.filter (name: isBundled name && (widgets.${name}.command or null) != null) (
            builtins.attrNames widgets
          )
        )
    ++
      map
        (name: {
          assertion = false;
          message = "haus.bar.widgets.${name} is enabled but sets no command, and `${name}` is not a pill haus ships — so there is nothing for the bar to run and the pill would draw an empty box forever. Give it a `command`, or drop the widget.";
        })
        (
          builtins.filter (
            name: widgets.${name}.enable && (widgets.${name}.command or null) == null
          ) userWidgetNames
        )
    ++
      # A pill placed on a bar that isn't drawn. The bottom bar is off by
      # default, so this is the likeliest way to lose a widget entirely — and it
      # is invisible from the option alone, because the placement is perfectly
      # valid and the bar it names simply doesn't exist.
      map
        (name: {
          assertion = false;
          message = "haus.bar.widgets.${name}.placement puts it on the bottom bar, but haus.bar.bottom.enable is off, so that bar is never drawn and this pill would appear nowhere at all. Switch the second bar on, or place this on \"menu-bar\".";
        })
        (
          builtins.filter (name: onBottom name && !cfg.bottom.enable && widgets.${name}.enable) (
            builtins.attrNames widgets
          )
        )
    ++
      # A name SketchyBar cannot address, or one already spoken for.
      #
      # A widget's name is not a label: it is the item id in every generated
      # `--add item <name> <side>` line, and those are bare words in a shell
      # script. `widgets."my widget"` emits `--add item my widget right`, which
      # SketchyBar reads as the item `my` in the group `widget` — no error, no
      # log line, just a pill that never appears and a `right` that silently
      # became something else. The desktop seam already refuses this shape
      # (`plainId`, in modules/lib/desktop.nix) but only for a DESKTOP; a host
      # reaches the same option down a path that had no check at all.
      #
      # The reserved half is the same failure by a different route. The bar's
      # own rc hand-writes the left side (the logo, the front app, the workspace
      # and launcher pills) and the tour, and `aiUsage` is drawn under the id
      # `ai_usage` — none of which is a widget, so nothing above would notice a
      # widget claiming one of those names and quietly colliding with it.
      map (name: {
        assertion = false;
        message =
          if builtins.elem name reservedItemIds then
            "haus.bar.widgets.${name} claims an item id the bar already draws for itself (${lib.concatStringsSep ", " reservedItemIds}) — the logo, the front app, the workspace and launcher pills, the tour, and the id the aiUsage pill is drawn under. Two items of one name on one bar collide silently. Pick another name."
          else
            "haus.bar.widgets.\"${name}\" is not a usable pill name. A widget's name becomes the SketchyBar item id in `--add item <name> <side>`, which is a bare word in a generated shell script — a space or a dot there silently changes which item and which group the bar hears. Use letters, digits, `_` and `-`, starting with a letter or digit.";
      }) (builtins.filter (name: !(validWidgetName name)) userWidgetNames)
    ++
      # ---- the one roster entry this room addresses by PATH -------------------
      # `scope` reads as a question about REACH — which profile the package
      # lands in — and for every other roster entry that is all it is. For
      # sketchybar it is a filesystem contract: the launchd agent's
      # ProgramArguments, `barpop`, `bar-bottom`, `aerospace-notify.sh` and the
      # plugins all address the binary as `barTopPath` above, which is
      # `binPath` — the profile this `scope` chooses.
      #
      # `scope = "user"` used to be refused here, on two reasons in turn and
      # neither of them measured: first "only the system profile puts a package
      # where launchd can reach it", which `binPath` retired by making every
      # address follow `scope`; then "no bar has ever been run out of the
      # per-user profile", which was true and is no longer. It has now been run.
      # Measured 2026-08-24 on a full `bench try switch` of this repo's own
      # consumer, with the whole hacker desktop on:
      #
      #   the agent            ~/Library/LaunchAgents/org.nixos.sketchybar.plist
      #                        exec'd /etc/profiles/per-user/<you>/bin/sketchybar
      #                        and stayed `state = running`. That is the answer
      #                        to the reach worry, and it is structural rather
      #                        than lucky: this room writes `launchd.user.agents`
      #                        — a LaunchAgent in the user's own home, loaded
      #                        into their Aqua session as their uid. There is no
      #                        daemon anywhere in the bar, so there is no context
      #                        that cannot read that user's profile.
      #   both bars drew       CGWindowListCopyWindowInfo showed the menu bar's
      #                        1512×36 backdrop at y=0 with its pill windows
      #                        beside it, and `bar-bottom`'s 1512×32 at the
      #                        bottom — the second name resolving through the
      #                        system-profile symlink to the per-user binary.
      #   the pills ticked     cpu 27% → 18% and the clock 3:06 → 3:07 over 70 s,
      #                        weather, github and ai_usage all populated, the
      #                        workspace pills carrying their app icons — which
      #                        is `aerospace-notify.sh` and every plugin writing
      #                        successfully through the generated bar.sh.
      #   `--reload` worked    on both bars, each naming its own rc, silent and
      #                        exit 0, `configuration loaded..` in both logs.
      #   barpop resolved      armed and exited clean both with `SKETCHYBAR_BIN`
      #                        set (how every click_script calls it) and with it
      #                        unset, where its fallback chain skips the system
      #                        profile's now absent copy and lands on PATH.
      #   the palette's own    `reload-bar.sh` run under a BARE launchd PATH, the
      #                        way pounce spawns it, still reloaded both bars —
      #                        it exports the per-user bin dir itself.
      #
      # So the arm below refuses two things, and `scope` is not one of them:
      #
      #   no source at all      `package = lib.mkForce null` with no
      #                         `packageName` and no `brew` — read as a TRIPLE
      #                         now, via `binPath`, and the third one is why:
      #                         a brew entry has a binPath (/opt/homebrew/bin)
      #                         and the room follows it there, which is the
      #                         arrangement this repo shipped until 2026-08-22.
      #                         Testing only the nixpkgs pair refused it. This
      #                         room sets `package` at mkDefault, so merely
      #                         ADDING a brew does nothing either way (you get
      #                         the tool twice and a working bar); the
      #                         migration reaches this check only through
      #                         `lib.mkForce null`. `packageName` is in the
      #                         group because it is the only nixpkgs source a
      #                         data-only desktop can name.
      #   enable = false        the documented way to drop a roster entry. It
      #                         filters out before `packagesFor` ever sees it,
      #                         so `package` and `scope` still read fine and
      #                         nothing is installed at all.
      #
      # Both are the same fact — `binPath == null`, a bar with no address — and
      # the split exists only so the message can name the cause you actually
      # wrote. What `scope` costs at "user" is real but is not this room's to
      # refuse: the system profile stops carrying a `sketchybar` at all, so
      # anything OUTSIDE haus that hardcodes the system spelling of `binPath`
      # breaks. Inside haus nothing may hardcode it — flake check
      # `roster-bin-paths` is what keeps that true, and it caught this very
      # comment doing it — so the room's own default stays "system" for two
      # reasons that are preference rather than requirement: it is the felt-in
      # arrangement, and it leaves that spelling on disk for everyone else's
      # scripts.
      #
      # The general shape — a roster entry another module names by path has a
      # scope precondition, and the roster has no way to express it — is
      # options-roadmap.md §5.4's open box. It closed here by measurement rather
      # than by machinery: the precondition turned out not to exist.
      (
        let
          entry = config.haus.roster.sketchybar;
          # "Is there a sketchybar to address" is one question with one answer,
          # and it is not the same question as "which nixpkgs source". A `brew`
          # entry has a binPath — /opt/homebrew/bin — and the bar follows it
          # there, which is the arrangement this room shipped until 2026-08-22
          # and is therefore the best-tested one in the file. The earlier
          # `package == null && packageName == null` refused it.
          sourceless = entry.binPath == null;
        in
        lib.optional (!entry.enable || sourceless) {
          assertion = false;
          message =
            "haus.bar.enable is on, but haus.roster.sketchybar "
            + (
              if !entry.enable then
                "is disabled (enable = false), so it is filtered out of the roster before anything installs it, and haus.roster.sketchybar.binPath is null"
              else
                "installs nothing that leaves a binary at a path haus can name — `package`, `packageName` and `brew` are all null (a `cask` or an `appStoreId` would be a bundle, not a binary), so haus.roster.sketchybar.binPath is null"
            )
            + ". The launchd agent, barpop, bar-bottom, aerospace-notify.sh and every plugin address the binary as haus.roster.sketchybar.binPath, so a null one is a bar that never draws with nothing anywhere saying why. Give haus.roster.sketchybar a source — `package = pkgs.sketchybar`, `packageName = \"sketchybar\"` from a data-only desktop, or a `brew` — or turn the bar off with haus.bar.enable = false. `scope` is free: both \"system\" and \"user\" were measured drawing a working bar on 2026-08-24, and every address in the room follows whichever you pick.";
        }
      );

  # ---- the bundled pills, pre-declared as widgets -----------------------------
  # Every pill this repo ships exists in `haus.bar.widgets` on every machine,
  # whether anyone named it or not, and this is where. Three things arrive here
  # and each is a different kind of answer:
  #
  #   enable      what `bar.items` says, or — for `focus`, which has no switch in
  #               that table — what the Focus room says. mkDefault, so a rice
  #               that reaches for the open form directly
  #               (`widgets.cpu.enable = true`) wins over the sugar's default
  #               without having to know the sugar exists.
  #   placement   what `bar.bottom.items` says, and null (the menu bar) when it
  #               says nothing.
  #   interval /  the widget table's own values, so reading
  #   permissions `haus.bar.widgets.weather` answers "how often does this run,
  #               and what will it ask me for" without a second lookup — which
  #               is the whole reason those two fields are on the open form
  #               rather than in a comment.
  #
  # `claudeUsage` never becomes a widget: it is a deprecated ALIAS, so it is
  # OR-ed into the widget it names. That fold lived in `wantsItem` before and is
  # the same one line, one layer earlier — which is the shape of this whole
  # change, and the reason the emission below never mentions it again.
  haus.bar.widgets = lib.mkMerge (
    map (
      name:
      let
        w = widgetTable.${name};
        side = cfg.bottom.items.${name} or false;
        # The sugar's answer for this pill, and it is TWO questions folded into
        # one field, exactly as the old tables folded them. `focus` is the
        # first asymmetry: it rides its room's contribution, and `bar.items`
        # never offered a bool for it.
        #
        # The second is `bar.bottom.items`, and it is the one worth writing
        # down. Naming a pill there has ALWAYS drawn it — the bottom table won
        # outright, so `bottom.items.calendar = "center"` put the calendar on
        # the second bar with `items.calendar` left at its default false, which
        # is the documented way to do it and what the roster's ical-buddy gate
        # keys off. Placement therefore implies enablement, and a first cut of
        # this that read `items` alone silently emptied the bottom bar of every
        # default-off pill — caught by `bar-bottom-groups`, which is exactly
        # the fixture that exists to catch it.
        wanted =
          if name == "focus" then
            config.haus._contrib.bar.focus.enable
          else
            side != false
            || (cfg.items.${name} or w.default)
            || lib.any (a: aliasOf a == name && (cfg.items.${a} or false)) bundledNames;
      in
      {
        ${name} = {
          enable = lib.mkDefault wanted;
          placement = lib.mkDefault (
            if side == false then
              null
            else if lib.isString side then
              side
            else
              # The bool form `bar.bottom.items.<pill> = true`, which is what
              # that option shipped as and still means the right group.
              "right"
          );
          interval = lib.mkDefault w.interval;
          permissions = lib.mkDefault w.permissions;
        };
      }
    ) drawnBundled
  );

  # The pill's default sources, set here rather than in options.nix because they
  # are built from haus.git.org and an option's `default` cannot read config.
  # mkDefault so naming any source replaces the pair wholesale — there is no
  # merge of two source lists that isn't a guess about order, and order is what
  # breaks a severity tie.
  haus.bar.github.sources = lib.mkDefault (
    lib.optionals (gitOrg != "") [
      # Red default branches first: it is the only entry here that can be an
      # emergency, and the pill speaks for the highest severity it has.
      { ci = true; }
      {
        search = "org:${gitOrg} is:pr is:open";
        title = "open PRs";
      }
    ]
  );

  # SketchyBar, from nixpkgs. sketchybar-app-font renders the workspace pill
  # glyphs (an icon ligature font: `:ghostty:` → that app's logo).
  #
  # NOT the FelixKratz tap it used to be, and the reason is a fresh Tahoe Mac:
  # that formula has no bottle for macOS 26, so the first `darwin-rebuild switch`
  # on a clean install built SketchyBar from source — and its parallel make races
  # on a `bin/` dir another job is still creating (`unable to open output file
  # 'bin/background.o'`), which fails the rebuild outright. Nixpkgs ships the same
  # 2.24.0, prebuilt in the binary cache, so nothing is compiled on install.
  #
  # Roster entries, not raw brews — a formula with no .app is still something the
  # machine has, and keeping it in the one list is what lets `haus` and the agent
  # skill answer "what's installed here?" completely. ical-buddy backs the opt-in
  # `calendar` pill (plugins/calendar.sh shells out to it); pulled in only when
  # that plugin is enabled so a default bar stays lean. If a host ALSO declares
  # ical-buddy, the two definitions merge on the shared id rather than
  # double-installing — which is the difference between a keyed roster and a list.
  #
  # Keyed off "is the pill drawn ANYWHERE", not off bar.items: the documented
  # way to put the pill on the bottom bar is `bar.bottom.items.calendar = true`
  # with `bar.items.calendar` left at its default false, and reading only the
  # top table there would draw the pill with no icalBuddy behind it — which
  # calendar.sh reports as a permanent, silent "No events".
  haus.roster = {
    sketchybar = {
      package = lib.mkDefault pkgs.sketchybar;
      # System scope, not the default user one — a PREFERENCE now, not a
      # requirement. `scope = "user"` was measured drawing a working bar on
      # 2026-08-24 (the assertion above carries what was measured, and no
      # longer refuses it), because this room's agent is a `launchd.user.agent`
      # running as the user, not a daemon. "system" stays the default for the
      # two reasons that survived: it is the arrangement the whole room is
      # written and felt against, and it keeps a `sketchybar` in the system
      # profile for anything OUTSIDE haus that hardcodes it there — a
      # hand-written script, a stale dotfile, another tool. A host that would
      # rather have the bar in its own profile may say so.
      scope = lib.mkDefault "system";
    };
  }
  // lib.optionalAttrs (builtins.elem "calendar" (topItems ++ bottomItems)) {
    ical-buddy.brew = lib.mkDefault "ical-buddy";
  };
  # sketchybar-app-font draws the workspace-pill logos, and nothing else does —
  # so this is the one font bar still installs for itself. Everything else in
  # the bar is drawn in `barFont`, i.e. haus.fonts.mono.name, whose package
  # core installs (and warns about when a rice names a family it wasn't given).
  #
  # The rule that keeps this honest is the one that put Hack here in the first
  # place: DECLARE WHAT WE NAME. The bar used to name "Hack Nerd Font" while
  # core shipped JetBrains Mono, so a fresh machine drew tofu across the whole
  # bar and only a hand-installed Hack hid it. The fix then was to install the
  # font we named; the fix now is to name the font we install.
  fonts.packages = [ pkgs.sketchybar-app-font ];

  # The dropdown dismisser the pills' click_scripts call by its
  # /run/current-system/sw/bin path. On PATH as well because it's the one honest
  # way to open a bar popup by hand (`barpop toggle calendar`) — a raw
  # `popup.drawing=on` leaves a dropdown nothing will close.
  # barpop, plus — when the second bar is on — the `bar-bottom` name that IS
  # that bar. On PATH for the same reason `sketchybar` is: it's the CLI half,
  # the only way to poke the bottom bar by hand or from a script.
  #
  # barvitals rides along only when one of the two readouts it feeds is
  # actually drawn — a rice with neither pill on shouldn't carry a Swift build
  # in its closure for a sampler nothing calls. Both plugins reach it by its
  # /run/current-system/sw/bin path — an absolute one because a plugin's PATH is
  # whatever the agent was given (`userPath` above, not a login shell's), and
  # spelling it beats depending on that. It is `barpop`'s situation, not
  # `sketchybar`'s: barvitals is this room's own systemPackages entry and has no
  # roster `scope` to follow.
  environment.systemPackages = [
    barpop
  ]
  ++ lib.optional cfg.bottom.enable barBottom
  ++ lib.optional (lib.any (name: builtins.elem name (topItems ++ bottomItems)) [
    "cpu"
    "memory"
  ]) barvitals;

  launchd.user.agents = {
    sketchybar = {
      serviceConfig = {
        ProgramArguments = withGUIWait barTopPath;
        KeepAlive = true;
        RunAtLoad = true;
        ProcessType = "Interactive";
        StandardOutPath = "/tmp/sketchybar.out.log";
        StandardErrorPath = "/tmp/sketchybar.err.log";
        EnvironmentVariables = {
          LANG = "en_US.UTF-8";
          PATH = userPath;
        };
      };
    };
  }
  // lib.optionalAttrs cfg.bottom.enable {
    # The second bar: the same agent, the same binary, launched under the second
    # NAME (see `barBottom` above — argv[0] is the whole mechanism) and pointed
    # at its own config. --config is not optional here: SketchyBar's default is
    # ~/.config/sketchybar/sketchybarrc for every instance, so without it both
    # jobs would build the menu bar and the second would just lose the race for
    # its own lock.
    bar-bottom = {
      serviceConfig = {
        ProgramArguments = guiWait.wrapArgs barBottomPath [
          "--config"
          barBottomRc
        ];
        KeepAlive = true;
        RunAtLoad = true;
        ProcessType = "Interactive";
        StandardOutPath = "/tmp/bar-bottom.out.log";
        StandardErrorPath = "/tmp/bar-bottom.err.log";
        EnvironmentVariables = {
          LANG = "en_US.UTF-8";
          PATH = userPath;
        };
      };
    };
  };

  # SketchyBar is launched solely by the agent above — never by `brew services`.
  # If a stray `brew services` plist is left behind, that second instance grabs
  # the lock file and our agent silently fails to draw (symptom: empty menu bar,
  # "could not acquire lock-file … already running?" in the err log). Boot it out
  # and delete its plist on every rebuild. Idempotent no-op when clean.
  system.activationScripts.postActivation.text = ''
    uid=$(/usr/bin/id -u ${username})
    strayPlist="/Users/${username}/Library/LaunchAgents/homebrew.mxcl.sketchybar.plist"
    if [ -e "$strayPlist" ]; then
      echo "[activation] evicting stray homebrew.mxcl.sketchybar agent" >&2
      /bin/launchctl bootout "gui/$uid/homebrew.mxcl.sketchybar" 2>/dev/null || true
      rm -f "$strayPlist"
    fi

    # The label this room's second bar ran under until 2026-08-16, when the room
    # stopped being called `sill`. Same reason the launcher boots out its own
    # pre-hausfold label explicitly: this job is `KeepAlive`, so a stale copy
    # that outlives its plist keeps drawing a second bottom bar beside the
    # canonical one until logout. One-time migration, idempotent no-op after.
    /bin/launchctl bootout "gui/$uid/org.nixos.sill-bottom" 2>/dev/null || true

    # The Homebrew SketchyBar this room installed until 2026-08-22. Nothing
    # points at it any more — the agent, the rc, the plugins and `bar-bottom`
    # all resolve through `barTopPath` — so it is inert, and
    # `haus.homebrew.cleanup` defaults to "none", which means it sits there
    # forever. Said rather than done: `brew uninstall` wants to run as the
    # user, not as the root this script is, and haus does not delete things
    # behind your back. It matters because the next `brew upgrade` would try
    # to BUILD that formula on macOS 26 (no bottle) and fail — which is the
    # whole reason this room moved to nixpkgs.
    if [ -x /opt/homebrew/opt/sketchybar/bin/sketchybar ]; then
      echo "[activation] bar: SketchyBar now comes from nixpkgs; the old formula is unused. Remove it with: brew uninstall sketchybar && brew untap FelixKratz/formulae" >&2
      # And the half a user would otherwise discover as a pill that stopped
      # working. TCC keys a grant to the BINARY, and sketchybar is a new one at
      # a new path, so every grant the old one held — Accessibility for the
      # focus pill's keypress, Automation for the front-app and media pills —
      # is asked for again on first use. Said here rather than left to a
      # silent no-op, because that is what an orphaned grant looks like: the
      # pill draws, the click does nothing. (Homebrew moved the binary per
      # `brew upgrade` for the same reason; this moves it per nixpkgs bump.)
      echo "[activation] bar: it is a different binary, so macOS asks for SketchyBar's Accessibility and Automation grants again — approve them on first use, or run 'focus doctor'" >&2
    fi
  '';

  home-manager.users.${username} =
    {
      lib,
      osConfig,
      nebelung,
      ...
    }:
    let
      # haus.theme.{flavor,contrast} select which rendered variant everything
      # below reads — ../lib/nebelung.nix owns that resolution for terminal, bar and
      # theme alike, so the flavor axis landed in one place rather than three.
      #
      # The bar needs only the palette, never a rendered file: every colour it
      # draws comes from the generated colors.sh below, so light mode reaches the
      # bar with no path change at all. (The previous `nebelungRoot` binding here
      # was never used — dropped rather than extended.)
      nebelungPalette =
        (import ../lib/nebelung.nix {
          inherit lib nebelung;
          theme = osConfig.haus.theme;
        }).palette;
      # Type sizes, resolved from haus.ui.scale against the menu bar's own
      # ceiling (see ../lib/bar.nix). Sourced by sketchybarrc and by the plugins
      # that set a font, exactly like colors.sh — so the bar's sizes are
      # single-sourced the same way its colours are, and neither the rc nor a
      # plugin carries a tuned number of its own.
      sizesSh = ''
        #!/bin/bash
        # GENERATED from haus.ui.scale by modules/bar/default.nix — do not
        # edit by hand.
        #
        # Neither bar's HEIGHT scales: 36pt of menu bar with 28pt pills is what
        # keeps the pills inside the 32pt band the hidden bar's hover-reveal
        # covers, and the second bar is 32 because it sits in no band at all.
        # Only the type inside the pills follows ui.scale, and only up to the
        # largest that still fits one. See modules/lib/bar.nix.
        BAR_SCALE="${toString bar.typeScale}"
        # The two bars' heights, from that same file. Generated rather than
        # written in each rc because windows reserves exactly these numbers as
        # window gaps (modules/windows/default.nix) — an rc that drifted from them
        # would leave a strip of dead wallpaper or put windows under the pills,
        # and the drift would be invisible in either file on its own. The second
        # bar is shorter on purpose: it doesn't sit in the menu-bar band, so it
        # doesn't pay the band's 4pt of clearance.
        BAR_HEIGHT="${toString bar.barHeight}"
        BAR_BOTTOM_HEIGHT="${toString bar.bottomHeight}"
        # The bar's left/right padding, which is windows's outer SIDE gap
        # (../lib/gaps.nix) verbatim — so the outermost pill's edge lands on the
        # tiled window's edge below it, at every haus.ui.scale and through any
        # later change to the gaps. Unlike the heights above it DOES scale: a
        # window gap is a tuned gap, not a measurement of a band macOS owns.
        # The pill at each edge gives up its own outer padding to make the sum
        # come out (`edgePad` in ../default.nix, and the logo in sketchybarrc).
        BAR_PAD_X="${toString barPadX}"
        # The family every pill draws in, from haus.fonts.mono.name — the
        # same one Ghostty uses. Here rather than in the rc for the reason the
        # sizes are: the rc and four plugins all name it, and a font written in
        # five places is a font that ends up being two.
        BAR_FONT="${barFont}"
        FS_ICON="${sizes.icon}"
        # The square Material Design marks render short at FS_ICON. The widget
        # table interpolates the same value straight into its blocks (`github`);
        # this exists for the pills sketchybarrc writes by hand, where there is
        # no Nix to interpolate from — today the `page` pill alone.
        FS_ICON_WIDE="${sizes.iconWide}"
        FS_LABEL="${sizes.label}"
        FS_SMALL="${sizes.small}"
        FS_TINY="${sizes.tiny}"
        FS_APP_ICON="${sizes.appIcon}"
      '';

      # The Nebelung palette (name -> "#rrggbb") rendered as sketchybar's
      # 0xAARRGGBB colour literals, fully opaque. Generated so the palette stays
      # single-sourced from the nebelung input — sketchybarrc and every plugin
      # `source` this instead of hardcoding Catppuccin hexes. Var names are the
      # UPPER-cased palette keys (BASE, SURFACE0, MAUVE, …).
      colorsSh = ''
        #!/bin/bash
        # GENERATED from the `nebelung` flake input (nebelungPalette). Do not edit
        # by hand — change colours in ~/code/workshop/nebelung and rebuild.
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            name: hex: "export ${lib.toUpper name}=0xff${lib.removePrefix "#" hex}"
          ) nebelungPalette
        )}
      '';
      # The far-left logo pill. BAR_LOGO_COLOR is resolved to a colors.sh
      # VARIABLE REFERENCE rather than a hex: the accent name is a palette key,
      # colors.sh exports every key UPPER-cased, and both files are sourced by
      # the same shell — so `$MAUVE` here picks up whatever the nebelung input
      # says mauve is today, and a palette change reaches the logo without this
      # file knowing a single hex. `haus.bar.logo.color` left null follows
      # haus.theme.accent, which is the case worth optimising for: the pill is
      # the rice's own mark, so it wears the rice's own accent.
      #
      # BAR_LOGO_SWEEP_COLORS is the six hausfold accents in the order the
      # conic gradient on hausfold.co runs them (nebelung → holt → perch →
      # trill → pounce → hacker, i.e. mauve → teal → green → yellow → peach
      # → pink). Those are dark-mode's `--a-*` tokens, and every one of them
      # resolves to a nebelung palette key, which is the whole reason the bar
      # can reproduce the site's mark without an asset.
      logoConfigSh = ''
        #!/bin/bash
        # GENERATED from haus.bar.logo.* by modules/bar/default.nix — do not edit.
        BAR_LOGO_ICON=${lib.escapeShellArg cfg.logo.icon}
        BAR_LOGO_SIZE="${toString cfg.logo.size}"
        BAR_LOGO_COLOR="''$${
          lib.toUpper (if cfg.logo.color != null then cfg.logo.color else config.haus.theme.accent)
        }"
        BAR_LOGO_STATUS="${if cfg.logo.status then "1" else "0"}"
        BAR_LOGO_UPDATE_CHECK="${if cfg.logo.updateCheck then "1" else "0"}"
        BAR_LOGO_SWEEP="${if cfg.logo.sweep then "1" else "0"}"
        # Off when the room that draws all three menus isn't enabled, as well as
        # when the option says so: with no pounce there is nothing for a click to
        # open, and a pill that swallows clicks silently is worse than one that
        # is plainly not a button.
        BAR_LOGO_GESTURES="${if cfg.logo.gestures && config.haus.launcher.enable then "1" else "0"}"
        BAR_LOGO_SWEEP_COLORS="$MAUVE $TEAL $GREEN $YELLOW $PEACH $PINK"
        # This rice's pounce commands, so the menu's rows can RUN rebuild.sh and
        # reload-bar.sh rather than carry a second implementation of either.
        # Empty when haus.launcher.enable is off, which is also when the pill's
        # click gestures have nothing to open — haus_menu.sh checks for that.
        BAR_LOGO_COMMANDS="${config.haus._pounceCommands}"
      '';
      # Every file the two bars read. Bound here rather than assigned straight
      # to home.file so the reload stamp below can hash it — see there for why
      # the reload hangs off one derived file rather than off each of these.
      barFiles = {
        ".config/sketchybar/colors.sh".text = colorsSh;
        ".config/sketchybar/logo_config.sh".text = logoConfigSh;
        ".config/sketchybar/sizes.sh".text = sizesSh;
        ".config/sketchybar/workspaces.sh".text = workspacesSh;
        ".config/sketchybar/top_items.sh".text = topItemsSh;
        ".config/sketchybar/bar.sh".text = barSh;
        ".config/sketchybar/position.sh".text = positionSh;
        ".config/sketchybar/windows_config.sh".text = windowsConfigSh;
        ".config/sketchybar/tour_item.sh".text = tourItemSh;
        ".config/sketchybar/tour_config.sh".text = tourConfigSh;
        ".config/sketchybar/battery_config.sh".text = ''
          #!/bin/bash
          # GENERATED from haus.bar.battery.* by modules/bar/default.nix — do not edit.
          BAR_BATTERY_HIDE_OVER="${
            if config.haus.bar.battery.hideOver != null then toString config.haus.bar.battery.hideOver else ""
          }"
        '';
        ".config/sketchybar/clock_config.sh".text = ''
          #!/bin/bash
          # GENERATED from haus.bar.clock.* by modules/bar/default.nix — do not edit.
          BAR_CLOCK_MODE="${config.haus.bar.clock.mode}"
        '';
        # Empty when the pill is off, which is what keeps media-control out of a
        # rice that doesn't draw it — plugins/media.sh, media_stream.sh and
        # media_art.sh all exit 0 on an empty value rather than assuming the
        # binary is there.
        #
        # BAR_MEDIA_ICONS is the glyph override table, one "key<TAB>glyph" per
        # line. Real tabs and newlines rather than \t/\n escapes because the
        # consumer is a plain double-quoted bash string, where a backslash-t is
        # two characters and nothing would ever match.
        ".config/sketchybar/media_config.sh".text = ''
          #!/bin/bash
          # GENERATED from haus.bar{,.bottom}.items.media + haus.bar.media.* by
          # modules/bar/default.nix — do not edit.
          BAR_MEDIA_CONTROL="${
            lib.optionalString (builtins.elem "media" (topItems ++ bottomItems)) (lib.getExe mediaControl)
          }"
          BAR_MEDIA_COLLAPSE="${if cfg.media.collapse then "1" else "0"}"
          BAR_MEDIA_ARTWORK_TINT="${if cfg.media.artworkTint then "1" else "0"}"
          # The pill's only motion — off when the machine asked for less of it
          # (haus.appearance.reduceMotion sets this leaf, it does not reach the
          # plugin). "0" clips a long title instead of sweeping it.
          BAR_MEDIA_MARQUEE="${if cfg.media.marquee then "1" else "0"}"
          BAR_MEDIA_ICONS="${
            lib.concatStringsSep "\n" (lib.mapAttrsToList (key: glyph: "${key}\t${glyph}") cfg.media.icons)
          }"
        '';
        # Empty by default: plugins/elgato.sh then discovers the light over
        # mDNS rather than the rice shipping somebody's device hostname.
        ".config/sketchybar/elgato_config.sh".text = ''
          #!/bin/bash
          # GENERATED from haus.bar.elgato.* by modules/bar/default.nix — do not edit.
          BAR_ELGATO_HOST="${config.haus.bar.elgato.host}"
        '';
        # The calendar pill's knobs. COMMA-joined, not newline-joined, for the two
        # list options: calendar.sh hands both straight to awk as `-v` values, and
        # awk's lexer refuses a literal newline inside one — it dies with "newline
        # in string" on stderr nothing reads, i.e. as a pill that silently forgets
        # who you are meeting.
        ".config/sketchybar/calendar_config.sh".text = ''
          #!/bin/bash
          # GENERATED from haus.bar.calendar.* by modules/bar/default.nix — do not edit.
          BAR_CALENDAR_HORIZON="${toString cfg.calendar.horizon}"
          BAR_CALENDAR_PRECISE_UNDER="${toString cfg.calendar.preciseUnder}"
          BAR_CALENDAR_IMMINENT="${toString cfg.calendar.imminent}"
          BAR_CALENDAR_PAST="${toString cfg.calendar.past}"
          BAR_CALENDAR_UPCOMING="${toString cfg.calendar.upcoming}"
          BAR_CALENDAR_ME="${lib.concatStringsSep "," cfg.calendar.me}"
          BAR_CALENDAR_JOIN_HOSTS="${lib.concatStringsSep "," cfg.calendar.joinHosts}"
          # Same as the media pill's: hover-sweep the full title, or clip it.
          BAR_CALENDAR_MARQUEE="${if cfg.calendar.marquee then "1" else "0"}"
        '';
        ".config/sketchybar/github_config.sh".text = githubConfigSh;
        ".config/sketchybar/ai_usage_config.sh".text = ''
          #!/bin/bash
          # GENERATED from haus.bar.aiUsage.* by modules/bar/default.nix — do not edit.
          BAR_AI_USAGE_PROVIDER="${config.haus.bar.aiUsage.provider}"
        '';
        ".config/sketchybar/sketchybarrc".source = ./sketchybar/sketchybarrc;
      }
      // lib.optionalAttrs cfg.bottom.enable {
        # The second bar's rc + its item list. Deployed only when the bar is on,
        # so a rice without it carries neither file and `bar-bottomrc` can't be
        # run by hand against a `bar-bottom` that isn't installed.
        ".config/sketchybar/bar-bottomrc".source = ./sketchybar/bar-bottomrc;
        ".config/sketchybar/bottom_items.sh".text = bottomItemsSh;
      }
      // {
        # No image asset for the logo pill any more. It carried the hacker
        # ears here as a PINK-tinted PNG until the pill became a glyph
        # (haus.bar.logo.icon): SketchyBar's background.image takes no tint, so
        # every colour the pill now says something with — the accent, the state,
        # the hover sweep, leader mode — was unreachable while it was a picture.
        ".config/sketchybar/aerospace-notify.sh".source = ./sketchybar/aerospace-notify.sh;
        ".config/sketchybar/plugins".source = ./sketchybar/plugins;
      };
    in
    {
      # A rebuild rewrites every file above, but SketchyBar is a KeepAlive
      # launchd agent that read its config once at boot: it keeps the old items
      # in memory until something tells it to re-read. So a pill added, a colour
      # changed or a `bar.items` reorder all land on disk and change nothing
      # anybody can see, until the next reboot or a hand-run `sketchybar
      # --reload`. This is the same trap windows's aerospace.toml onChange fixes
      # for AeroSpace (modules/windows/default.nix), for the same reason.
      #
      # Why ONE derived file instead of an onChange on each of the ~20 above:
      # onChange fires per file, so a colour change that touches colors.sh,
      # sizes.sh and both item lists would reload the bar four times over. The
      # stamp is a content hash of the whole set, so it changes exactly once
      # when anything the bar reads changes, and not at all when nothing does —
      # which is the "only when their config changes" half of this. Hashing
      # barFiles itself rather than a hand-listed set is what keeps that true:
      # a pill added next month is covered without anyone remembering to extend
      # a list, and a forgotten entry here would fail silently, as staleness.
      # toJSON of each entry rather than its `.text or .source` for the same
      # reason — it also covers whatever attrs an entry grows later, so a file
      # that gains `executable = true` reloads the bar on the mode flip alone.
      #
      # The plugins directory is deliberately in the hash. Most plugins are
      # re-exec'd per tick and would take a change without any reload, so
      # including them costs a bar flash on rebuilds that didn't strictly need
      # one — but several (tour.sh init, media_stream.sh, ai_usage.sh) only ever
      # run from the rc at init, and a bar silently stale after a plugin edit is
      # the exact failure this exists to end. A visible flash beats invisible
      # staleness.
      #
      # Absolute paths for both bars, from the same constants every generated
      # block uses: a misdirected client call is silent (see barTopPath above).
      # Guarded so first-boot activation, where no bar is running yet, doesn't
      # fail the rebuild — launchd's RunAtLoad then starts each bar on the fresh
      # config anyway, and a plist change restarts the agent outright, so the
      # two mechanisms cover between them everything a rebuild can move.
      #
      # EACH RELOAD NAMES ITS RC. A bare `--reload` does not mean "re-read your
      # config file", it means "re-run the path you resolved at startup" — and
      # SketchyBar resolves that path once, through the symlink, to a file in
      # /nix/store. home.file rewrites the symlink every rebuild but the old
      # store path is still there and still readable, so an instance launched
      # with `--config ~/.config/sketchybar/bar-bottomrc` re-runs the rc from
      # the generation it BOOTED on, every reload, for the life of the process.
      # It reports success and logs `configuration loaded..` while doing it.
      #
      # That is not theoretical: the second bar spent a day pinned to a
      # pre-#279 rc, so `topmost=window` — the lift that keeps the tiled
      # window's drop-shadow off the strip — was on disk, in every reload, and
      # never once applied. It only surfaced when #283 took windows's bottom
      # reservation from 40 down to the bar's real 32 while the live bar was
      # still drawing the old 36: the windows came down flush onto pills that
      # were still sitting under them, and the shadow landed on the pills.
      #
      # Naming the ~/.config path re-resolves the symlink at reload time, which
      # is the whole fix. The menu bar is passed its rc for the same reason even
      # though it survives a bare reload today — it survives only because it is
      # launched with NO --config, so it falls back to the same ~/.config path
      # on every reload by accident rather than by intent. One spelling, one
      # behaviour, and no second bar-shaped trap for whoever adds the third.
      home.file = barFiles // {
        ".config/sketchybar/.haus-stamp" = {
          text = ''
            # GENERATED by modules/bar/default.nix — do not edit, and do not
            # source: this file exists only so its content hash changes when the
            # bar's config does. Nothing reads it.
            ${builtins.hashString "sha256" (
              lib.concatStrings (lib.mapAttrsToList (name: f: name + builtins.toJSON f) barFiles)
            )}
          '';
          onChange = lib.concatLines (
            [ "${barTopPath} --reload ${barTopRc} 2>/dev/null || true" ]
            ++ lib.optional cfg.bottom.enable "${barBottomPath} --reload ${barBottomRc} 2>/dev/null || true"
          );
        };
      };
    };
}

# Part of the nebelhaus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# sill's options — the bar(s): whether one is drawn, which pills go on it, the
# optional second bar along the bottom of the screen, and the first-run tour
# that rides in the top one.
{ lib, ... }:

let
  agentClients = import ../lib/agents.nix;
  accentNames = import ../lib/accents.nix;

  # Per-pill on/off for the whole right side of the bar. One bool per item in a
  # submodule (not attrsOf) so unknown keys are rejected and each item carries
  # its own default: the core pills default true, the extras default false. The
  # descriptions here are the single source for the options reference.
  #
  # Up here rather than inside `sill.items` because `sill.bottom.items` reads the
  # same tables — a pill's description is written once and both bars'
  # option pages render it.
  core = {
    clock = "The clock pill, pinned to the far right.";
    weather = "The weather pill and its click-to-open forecast popover.";
    media = "The now-playing track — auto-hides when nothing plays, dims when paused, and counts DOWN instead of scrolling a title once the thing playing is longer than twenty minutes (a podcast or a video is one you already know the name of; what you keep glancing at the bar for is how much is left). The title scrolls for a few seconds after a track changes and then settles, so nothing moves in the corner of your eye forever; hovering brings the full title back. Gestures: left click the dropdown, RIGHT click play/pause, ⌥ next, ⇧ previous, ⌘ jump to whatever is making the noise, scroll to seek ±10s. That ⌘ click reaches the browser TAB, not just the browser: the track's title is matched against the open tabs through Safari's and Chromium's AppleScript tab APIs, and on a Firefox fork (Zen among them) — which expose no tab list at all, neither to AppleScript nor to accessibility — through Firefox's own open-tab search in the address bar. Both routes ask for a permission the first time they run, Automation for the scriptable browsers and Accessibility for the Firefox forks, and both quietly fall back to just fronting the app if you say no. The dropdown carries the cover when the source published one, a scrubbable position slider, and transport rows — plus, for a source with no cover, a small app-icon badge floating in its bottom-right corner. It reads the same system-wide session Control Center does, so it follows a browser tab as readily as Apple Music or Spotify, and its icon says what KIND of thing is playing: an app it recognises gets that app's glyph, a browser gets video or music depending on whether an album was published. It cannot say which SITE — no URL reaches the now-playing session and none of window titles, artwork shape or the session's pid can recover one, so a wrong YouTube glyph on a Netflix tab is a guess this deliberately doesn't make; `haus.sill.media.icons` is the override for a machine that knows better. SketchyBar's own `media_change` event has been dead since macOS 15.4, where Apple started requiring an entitlement to talk to `mediaremoted`; the pill is fed instead by `media-control`, which does the read from inside the entitled `/usr/bin/perl`. That is a private-framework route Apple could close in any point release — `media-control test` exits non-zero once it has.";
    battery = "The battery pill.";
    wifi = "The Wi-Fi status pill.";
  };
  extra = {
    cpu = "Total CPU load, drawn as a graph pill: the last two minutes of it behind the number, because a percentage on its own can't tell a spike settling from a climb that started five minutes ago. The reading is a DELTA between samples — the `ps` sum this used to print is each process's average over its whole lifetime, which on a machine that has been up a week barely moves while every core is pinned. LEFT-CLICK opens a dropdown: the user/system split, the load average, then what's responsible, biggest first and aggregated per app so a browser's twenty helpers are one row; clicking a row focuses that app's window. RIGHT-CLICK opens Activity Monitor on its CPU tab. The rows can only cover processes you own, so anything root runs — `kernel_task`, `WindowServer` — lands in `everything else` rather than going quietly missing from the sum.";
    memory = "Memory in use, drawn as a graph pill. It counts what Activity Monitor counts — app memory + wired + compressed — and deliberately NOT the file cache: macOS fills idle RAM with cache on purpose, and the old reading counted that as used, which is why it sat near 90% on a machine doing nothing. The pill's COLOUR is the kernel's own pressure level (green normal, amber warning, red critical) rather than the percentage, because 60% of RAM in use is a Mac working correctly and a pill that goes amber for it is a pill you learn to ignore. LEFT-CLICK opens a dropdown with used/total, the cache, compressed and swap figures and then the biggest footprints per app, each row clicking through to that app's window. RIGHT-CLICK opens Activity Monitor on its Memory tab.";
    volume = "Output volume / mute state.";
    calendar = "The one meeting you have to be at next, and one gesture to join it. It reads \"in 12m · Design review\" — countdown first, because a label is clipped from the END and the number is the part you must never lose; below `haus.sill.calendar.preciseUnder` hours it carries minutes, above it just \"in 14h\" or \"in 2d\", and while an event is running it says \"now · …\" instead of going blank. For `haus.sill.calendar.imminent` minutes either side of the start the whole pill FILLS with the accent — a shape change rather than a colour change, so it catches the eye you aren't pointing at it. RIGHT-CLICK joins: it opens the event's conferencing link, found in the invite's url, location or notes (Meet, Zoom, Teams, Webex, Jitsi, Whereby and friends out of the box; `haus.sill.calendar.joinHosts` adds your own). LEFT-CLICK opens the day as a timeline — what's DONE in the last `haus.sill.calendar.past` hours, what's on NOW, and what's NEXT — each event carrying its day, clock time, length and who it's with, the next one boxed, and a `Join` affordance on every row that has a link. Your own address is dropped from the \"with\" line automatically: a CalDAV calendar is named for the account it syncs, so the pill can work out which attendee is you with no configuration (`haus.sill.calendar.me` for the cases where it can't). A name too long for the pill sweeps past only while you HOVER it — nothing here starts a marquee on its own — and `haus.sill.calendar.width` sets how much room it gets before that applies. Pulls in `ical-buddy` automatically and reads Calendar, so macOS prompts for Calendar access on first run.";
    caffeinate = "A coffee pill that prevents idle system sleep for 1/2/4/8 hours, a custom whole-hour duration, or indefinitely. The display may still turn off; closing a MacBook lid still sleeps it. Uses macOS's built-in `caffeinate`, so there is no extra package.";
    agents = "A paw pill tracking your agent-worktree panes. The label always names the state worth interrupting you for — \"2 ready\" outranks \"5 working\", which outranks \"1 done\" — never a bare count you'd have to click to decode. Click for the per-agent breakdown, sorted the same way (waiting first, then working, then idle, longest-elapsed first within each), each block showing the client, how long it's sat in that state, and — when the pane's checkout is a `holt` lane — its repo and PR status: merged, `+N unshipped` (exactly what `holt reship` fixes), not yet landed, or a dirty-tree footnote. A summary header totals the counts once more than one agent is running. Left-click a row to jump to that pane, ⌥/right-click for a live `zellij subscribe` peek. Fed by each client's own lifecycle hooks, which all call `agent-state` (also installed as ~/.config/sketchybar/plugins/agents-hook.sh): Opencode's plugin and Codex's ~/.codex/hooks.json are written for you (Codex asks you to trust its hooks the first time it sees them), while Claude Code's four agent-state hooks stay yours to point at it in ~/.claude/settings.json — Claude owns that file and rewrites it, so the rice merges in only the keys it must and never touches those four. (The two worktree hooks ARE declared, in hearth: they point at a rice-controlled path and self-heal on rebuild.) A row whose zellij pane is gone drops off by itself, which is what stands in for the session-end event Codex doesn't have. Dormant until a client fires.";
    aiUsage = "A gauge pill showing AI usage (Claude Code/Codex subscription rate limits as %, or Opencode API token cost as daily $). Automatically shows whichever provider reported most recently. Click for expanded session/weekly limits and daily/monthly API costs with model breakdowns. Claude and Opencode are read off disk; Codex has no local usage data, so its row is polled from your ChatGPT account with the OAuth token in ~/.codex/auth.json (refreshed and rewritten in place) — no Codex login on the machine, no call is made. Claude's row is pushed by its statusline; the Codex and Opencode rows are pulled by the pill itself on a 3-minute TTL, so they stay current on a machine that never opens Claude at all. Claude and Opencode also get a `tokens` block in the dropdown — raw tokens moved today, this week, this month and all time (cache reads and all), two periods to a line so a full set reads as a 2×2, purely for the fun of watching the number climb. A period with nothing in it is left out rather than printed as a zero, so the block simply gets smaller, and a closing `∑ Everything` adds every provider up when more than one is reporting. It is a score, not a limit: nothing acts on it, and it never reaches the pill's own label. Claude's is summed from your transcripts on a 15-minute TTL behind an index, so only sessions that grew since the last pass are re-read; Codex has no row because it keeps no local history to count.";
    claudeUsage = "Deprecated alias for `aiUsage`.";
    elgato = "Toggles an Elgato Key Light on the local network. The light is found over mDNS (or pinned with `haus.sill.elgato.host`), and the pill draws dim when it can't be reached at all — a light that dropped off the wifi is not the same thing as a light that's switched off.";
    harvest = "A Harvest time-tracking pill; needs a ~/.config/sketchybar/harvest_secrets.sh you provide.";
  };
  mkItem =
    default: desc:
    lib.mkOption {
      type = lib.types.bool;
      inherit default;
      description = desc;
    };

  # Which pills the SECOND bar can host. The whole right side is emitted from
  # one parameterized block table, so core and extra pills can move without a
  # second source copy. `claudeUsage` is left out because it is only a
  # deprecated alias for `aiUsage`.
  movable =
    core
    // builtins.removeAttrs extra [ "claudeUsage" ]
    // {
      hush = "The Hush (Do-Not-Disturb) pill. Needs `haus.hush.enable`; setting this moves the pill but does not enable the Hush room by itself.";
    };

  # The bottom bar's three groups. Shared with default.nix, which emits one run
  # per group in this order — see sides.nix for why it is one list and not two.
  sides = import ./sides.nix;

  # A pill on the SECOND bar. Same table as `sill.items`, but each value also
  # answers WHERE: `false` keeps it off this bar, a side name puts it in that
  # group, and `true` means `right` — which is what this option shipped as
  # while it was bool-only, so a rice written against that keeps working
  # unchanged rather than being renamed out from under it.
  #
  # No per-item `example`: the type line already reads
  # `boolean or one of "left", "center", "right"`, and fifteen identical
  # "Example: center" blocks would be fifteen new sections of noise in the
  # options reference. The worked example lives on the parent option, once.
  mkBottomItem =
    desc:
    lib.mkOption {
      type = lib.types.either lib.types.bool (lib.types.enum sides);
      default = false;
      description = desc;
    };

  contrib = import ../lib/contrib.nix { inherit lib; };
in
{
  options.haus = {
    # ---- the Bar room's extension points --------------------------------------
    # See modules/lib/contrib.nix for the contract, and modules/ai for today's
    # only writer. The bar decides how a contributed pill is drawn and where; the
    # source room decides whether it has anything to draw at all.
    _contrib.bar.agents = contrib.mkExtensionPoint {
      description = ''
        The AI room's `agents` pill: the paw tracking agent-worktree panes.

        Off, `haus.sill.items.agents` draws nothing — a machine with no agent
        clients has no pane state for the pill to report, and a permanently
        dormant pill is worse than an absent one. Asking for the pill with the
        AI room off is warned about by name rather than silently ignored.
      '';
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether the bar may draw the agents pill.";
        };
      };
    };

    sill.enable = lib.mkOption {
      type = lib.types.bool;
      # Rooms are opt-in: the neutral catalogue selects none, and a desktop
      # (or a host) turns this one on. Everything BELOW this switch keeps its
      # tuned value — a bar that is drawn is drawn properly, which is the
      # "neutral, useful configuration when enabled" half of the room contract.
      default = false;
      description = ''
        The SketchyBar menu bar. When off, the native macOS menu bar is kept
        (nebelhaus stops hiding it) and no bar is drawn.
      '';
    };

    sill.position = lib.mkOption {
      type = lib.types.enum [
        "top"
        "bottom"
        "auto"
      ];
      default = "top";
      example = "auto";
      description = ''
        Where the bar sits. `top` and `bottom` pin it there. `auto` flips it
        at runtime — `bottom` whenever an external display is attached (docked
        with the lid open, or clamshell), `top` on the built-in display alone —
        driven by a `display_change` hook, so the bar moves the moment you dock
        or undock, without a rebuild.

        The bar's height/pill offsets are tuned for the notch, which only
        exists at the top of the built-in display; at `bottom` there's no notch
        to tuck under, so `auto` conveniently keeps the notch case (`top`) on
        the notched screen and the plain case (`bottom`) on the external.
      '';
    };

    sill.logo.icon = lib.mkOption {
      type = lib.types.str;
      # The glyph, not a name: `haus.workspaces.<id>.icon` and
      # `haus.sill.media.icons` already take one, so this is the surface the
      # rice has. Write it as the character itself — paste the glyph.
      #
      # The DEFAULT is spelled as a codepoint rather than pasted here on
      # purpose. nf-fa-home lives in the Private Use Area, and PUA characters
      # are silently dropped by a surprising amount of tooling on the way into
      # a file — an editor without the font, a patch pipeline, an agent's write
      # tool (which is how this comment came to be written). A default that
      # quietly became "" is a bar with a blank pill where its logo was, and
      # nothing that evaluates or builds would have said so. The table below
      # can afford to lose one; this line cannot.
      default = builtins.fromJSON ''"\uf015"''; # nf-fa-home, U+F015
      example = "⌂";
      description = ''
        The glyph in the far-left logo pill — the one that was an Apple menu
        until it was the nebelhaus cat-ears mark. Any single character your bar
        font can draw; the default is Nerd Font's `nf-fa-home` (`U+F015`), a
        solid house.

        It has to hold up at 28pt with a pill's padding around it, which rules
        out more glyphs than you would expect. In particular **`⌂` (`U+2302`),
        the hausfold mark itself, is drawn hairline-thin in JetBrains Mono and
        does not gain weight at Bold or ExtraBold** — it is in the font, it is
        on the list below, and beside the workspace pills it reads as a much
        lighter object than everything around it. A taste call, not a bug: if
        you want the literal mark, take it and raise `haus.sill.logo.size`.

        Six that hold up at bar size, most to least solid:

        | glyph | codepoint | what it is |
        |---|---|---|
        | `` | `U+F015` | `nf-fa-home` — solid house (the default) |
        | `` | `U+F46D` | `nf-oct-home` — outlined house at icon weight |
        | `` | `U+EB06` | `nf-cod-home` — the same, slightly rounder |
        | `⌂` | `U+2302` | the hausfold mark, hairline |
        | `` | `U+F302` | `nf-fa-apple` — the logo this pill replaced |
        | `` | `U+F313` | `nf-linux-nixos` — the snowflake |

        There is deliberately no way to point this at an image file. SketchyBar
        draws a `background.image` left-anchored, at a scale you have to
        hand-tune per asset, and applies no tint to it — so a picture here can
        follow neither `haus.theme.accent` nor the state colours below, and
        cannot sweep on hover. The rice drew this pill as a PNG for a while and
        every one of those was a real limitation of it.
      '';
    };

    # Documented once, here, because three of the four gestures below are
    # pounce's and the option page is where someone finds that out.
    sill.logo.gestures = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        What the logo pill does when clicked:

        | gesture | what it opens |
        |---|---|
        | left click | the **haus menu** — System Settings, Activity Monitor, Lock Screen, Nix Config, Haus Settings, Rebuild System, Reload SketchyBar |
        | ⌘ left click | `haus rebuild`, straight into a floating terminal |
        | right click | the full pounce palette (⌘Space), which is what a bare click on this pill used to do |

        All three are drawn by **pounce**, so all three need
        `haus.pounce.enable` (which the nebelhaus desktop turns on). With pounce
        off they are silent no-ops and this option is the switch that says so out
        loud — turn it off and the pill stops responding to clicks entirely,
        rather than looking like an affordance that does nothing.

        The menu's rows are not reimplemented here: each one runs the palette
        command of the same name, so fixing one fixes both places. That is the
        whole reason the popup dropdown this replaces is gone — it was a second
        copy of five of these rows, and (having never been openable at all) a
        second copy nobody could check.
      '';
    };

    sill.logo.size = lib.mkOption {
      type = lib.types.ints.positive;
      default = 20;
      example = 25;
      description = ''
        Point size of the logo glyph. Its own knob rather than the bar's
        `FS_ICON`, because the glyphs worth putting here have wildly different
        optical sizes: the default solid house wants 20, `⌂` needs 25 before it
        stops looking like a typo, and a Nerd Font apple wants 17.
      '';
    };

    sill.logo.color = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum accentNames);
      default = null;
      example = "teal";
      description = ''
        The logo's resting colour, by Catppuccin name. `null` (the default)
        follows `haus.theme.accent`, which is almost always what you want — the
        pill is the rice's own mark, so it wearing the rice's own accent is the
        point.

        This is only the RESTING colour. `haus.sill.logo.status` paints over it
        while something needs attention, and the hover sweep runs from it and
        returns to it.
      '';
    };

    sill.logo.status = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Let the logo's colour report the health of the machine, so the pill says
        something without being clicked:

        | colour | meaning |
        |---|---|
        | accent | everything the rice runs is up |
        | `yellow` | a newer rice is pinned upstream (needs `haus.sill.logo.updateCheck`) |
        | `red` | something the rice runs is enabled but not running |

        Red is the one that matters. It is the same check `haus doctor` opens
        with — `nix-daemon`, plus each of AeroSpace / SketchyBar / pounce whose
        launchd job exists on this machine — and its whole point is that a
        wedged agent is otherwise invisible: the bar keeps drawing the last
        frame it painted, so a dead SketchyBar and a quiet one look identical.
        All of it is local, costs four `pgrep`s on a five-minute tick, and
        makes no network call.

        Yellow ranks below red and both outrank the accent, so the pill always
        shows the worst thing true about the machine.
      '';
    };

    sill.logo.updateCheck = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Add the yellow "a newer rice is available" state to the logo pill. Off
        by default because it is the one part of the pill that leaves the
        machine: it asks GitHub for the rice's current head (the same
        `git ls-remote` behind `haus status`) once every half hour, and a bar
        that phones home should be something you turned on.

        No effect unless `haus.sill.logo.status` is on.
      '';
    };

    sill.logo.sweep = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Sweep the logo through the six hausfold accents — mauve, teal, green,
        yellow, peach, pink, the order the site runs them (nebelung → holt →
        perch → trill → pounce → nebelhaus) — while the pointer is over it,
        then settle back.
        It is the bar's copy of the mark on hausfold.co, where hovering the `⌂`
        turns a conic gradient of those same six through the glyph. SketchyBar
        cannot put a gradient inside a glyph, so the sweep IS the gradient: one
        colour at a time, animated.

        It only runs from the resting accent. A pill sitting at yellow or red
        has something to say, and a rainbow running over that is a pill saying
        two things at once — so hover does nothing until the state clears.
        Leader mode suppresses it for the same reason.
      '';
    };

    sill.battery.hideOver = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 80;
      description = ''
        Hide the battery pill when charge percentage is above this threshold
        (e.g., set to 80 to show the battery pill only when charge is at or below 80%).
      '';
    };

    sill.clock.mode = lib.mkOption {
      type = lib.types.enum [
        "full"
        "compact"
      ];
      default = "full";
      example = "compact";
      description = ''
        The display mode for the clock pill: `full` (default, e.g. "Fri Jul 31  09:41 AM" with calendar icon)
        or `compact` (e.g. "Fri 31/7 9:41" without icon and trimmed spacing).
      '';
    };

    sill.clock.monoFont = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = ''
        Whether the clock pill's date and time use `haus.fonts.mono.name`, like
        the rest of Sill. Disable this to use macOS's system UI font, whose zero
        has no dot and is easier to distinguish from an 8 at a glance. The
        calendar icon remains in the Nerd Font either way.
      '';
    };

    sill.aiUsage.provider = lib.mkOption {
      # The clients come from modules/lib/agents.nix — the same list
      # haus.ai.clients and .default read, so a fourth client is one
      # edit rather than one per room. `latest` is sill's own extra: it is a
      # selection rule, not a client, which is why it is prepended here.
      type = lib.types.enum ([ "latest" ] ++ agentClients);
      default = "latest";
      example = "claude";
      description = ''
        Which AI provider to display in the main pill: `latest` (default, automatically
        shows whichever provider reported most recently), or one of
        ${lib.concatMapStringsSep ", " (c: "`${c}`") agentClients}.
        Clicking the pill always displays the full dropdown with all reporting providers.

        Note this is about *usage readouts*, not about which client `holt` can
        spawn: a provider reports here whenever it has data for your account —
        Codex notably does so from a ChatGPT login alone, with no CLI installed
        — so it is deliberately not tied to `haus.ai.clients`.
      '';
    };

    sill.media.collapse = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Draw the media pill as its glyph alone, and reveal the title only while
        the pointer is on it.

        Worth having on a MacBook: the bar's centre span is under the notch, so
        every character of scrolling track title is rent paid out of the room
        the workspace pills and the front-app name need. The pill still hides
        itself entirely when nothing is playing — this is about the case where
        something is.
      '';
    };

    sill.media.width = lib.mkOption {
      type = lib.types.ints.positive;
      default = 32;
      example = 16;
      description = ''
        How wide the media pill's title is allowed to get, in CHARACTERS — not
        pixels. Anything longer is clipped to this and swept past instead, so
        this is the knob for how much of the bar the now-playing title may rent.

        Narrow it on a MacBook, where the bar's centre span sits under the notch
        and every character of title is paid for out of the room the workspace
        pills and the front-app name need. `haus.sill.media.collapse` is the
        harder version of the same trade: no title at all until you hover.

        It is a MAXIMUM, not a fixed size — the pill still shrinks to fit a
        short title, so a wide setting costs nothing until something long plays.
      '';
    };

    sill.media.artworkTint = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Colour the media pill's glyph from the current cover art instead of from
        what kind of thing is playing.

        The colour is the cover's average, SNAPPED to the nearest member of the
        rice's palette — so the pill picks up the mood of a record without ever
        drawing a colour that isn't in the theme. Off by default because it
        trades a stable meaning (pink is Music, green is Spotify, red is video)
        for a colour that changes every three minutes.

        Only sources that publish artwork can drive it, which is fewer than you
        would think: every Firefox-family browser publishes none at all, and the
        pill falls back to the kind colour for those.
      '';
    };

    sill.media.icons = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        "browser.video" = "󰗃";
        "com.apple.podcasts" = "󰦔";
      };
      description = ''
        Override the media pill's glyph, keyed by bundle id
        (`com.spotify.client`) or by KIND — one of `music`, `spotify`,
        `podcast`, `video`, `vlc`, `browser.video`, `browser.music`, `other`.
        A bundle id wins over a kind.

        This exists because of one hard limit: **nothing on the machine can tell
        you which site a browser tab is playing.** macOS's now-playing session
        carries no URL, window titles only ever name the FOREGROUND tab (the one
        playing audio is usually behind), Firefox-family browsers publish no
        artwork to shape-check, and the session's pid is the browser's parent
        process rather than the tab's. So the pill draws a neutral video glyph
        for a browser rather than guessing YouTube and being wrong on Netflix.

        If you know that on YOUR machine browser video means YouTube, say so:

          haus.sill.media.icons."browser.video" = "󰗃";
      '';
    };

    sill.calendar.width = lib.mkOption {
      type = lib.types.ints.positive;
      default = 32;
      example = 16;
      description = ''
        How wide the `calendar` pill's label is allowed to get, in CHARACTERS —
        not pixels. The label reads "in 12m · <event>"; anything longer is
        clipped to this, and sweeps past in full while you hover the pill.

        The countdown leads deliberately: the clip eats the END of a label, so
        the number the pill exists for has to sit in front of the part that can
        run long.

        It is a MAXIMUM, not a fixed size — a short event name still draws a
        short pill.
      '';
    };

    sill.calendar.refresh = lib.mkOption {
      type = lib.types.ints.positive;
      default = 15;
      example = 60;
      description = ''
        How often the `calendar` pill re-reads your calendar, in SECONDS.

        This was 60, which is the worst possible number for a pill whose whole
        job is a countdown in minutes: the displayed number was up to a minute
        stale, so "in 1m" could mean the meeting started fifty seconds ago, and
        an event you had just accepted took a minute to appear at all. One read
        costs about 50ms of `icalBuddy`, so paying it four times a minute is
        cheaper than being wrong.

        Hovering the pill forces a read regardless of this, which is the case
        that actually matters — looking at it is the moment it has to be right.
      '';
    };

    sill.calendar.horizon = lib.mkOption {
      type = lib.types.ints.positive;
      default = 24;
      example = 12;
      description = ''
        How far ahead the `calendar` pill looks, in HOURS. Nothing starting
        later than this makes it say anything but "No events".

        It is a limit on the PILL, not on the dropdown: the timeline still lists
        what's coming past the horizon, because a list you opened on purpose is
        allowed to tell you about Thursday.
      '';
    };

    sill.calendar.preciseUnder = lib.mkOption {
      type = lib.types.ints.positive;
      default = 12;
      example = 3;
      description = ''
        Below how many HOURS the countdown carries minutes.

        Under it the pill reads "in 3h20m"; at or above it, "in 14h", "in 2d".
        A number you are reading as "not yet" doesn't need its minutes, and the
        digits it drops are the ones a long meeting name would have eaten.
      '';
    };

    sill.calendar.imminent = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      example = 2;
      description = ''
        How many MINUTES either side of an event's start the `calendar` pill
        fills solid — accent background, dark type — for a window of twice this
        in total.

        Deliberately tied to the START and not to the whole meeting: five
        minutes before is "go now" and five after is "you're late", and they are
        the same fact. A pill that stayed filled for the event's full hour would
        just be a pill that is a different colour.
      '';
    };

    sill.calendar.past = lib.mkOption {
      type = lib.types.ints.positive;
      default = 24;
      example = 8;
      description = ''
        How many HOURS of finished events the dropdown's `Done` band keeps.

        The band exists so the timeline has a floor to read up from — "what have
        I already been in today" is the context that makes "next" mean anything.
        The pill itself never looks backwards.
      '';
    };

    sill.calendar.upcoming = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      example = 3;
      description = ''
        How many future events the dropdown's `Next` band lists, at most. The
        first of them is the one the pill is about, and the one drawn in a box.
      '';
    };

    sill.calendar.me = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "you@work.example" ];
      description = ''
        Addresses (or display names) that are YOU, dropped from the "with …"
        line in the dropdown. An attendee list that includes you is a list that
        tells you nothing — every meeting is "with you and Ana".

        Usually unnecessary: a CalDAV account's calendar is named for the
        address it syncs, so the pill takes the calendar names that look like
        email addresses as its answer and re-checks them every six hours. Set
        this when that guess misses — a local calendar, an alias you're invited
        under, or a second address on the same account. It ADDS to what was
        found rather than replacing it.
      '';
    };

    sill.calendar.joinHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "meet.mycorp.example" ];
      description = ''
        Extra hostnames to treat as conferencing links, on top of the built-in
        set (Google Meet, Zoom, Teams, Webex, Jitsi, Whereby, Chime, BlueJeans,
        GoTo, Around, Discord). Right-clicking the pill — or clicking a dropdown
        row — opens the first link in the invite whose host matches.

        Matching is on the HOST, and a bare registrable name also covers its
        subdomains (`zoom.us` catches `us02web.zoom.us`). That is why it isn't a
        substring search: every Google Meet invite also carries a `tel.meet`
        dial-in and a `support.google.com` footer, and looking for "meet"
        anywhere in the notes opens the phone-number page.
      '';
    };

    sill.elgato.host = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "elgato-key-light-mini-57a3.local";
      description = ''
        Which Elgato Key Light the `elgato` pill toggles — a hostname or IP,
        optionally with a `:port` (the light's HTTP API is on 9123).

        Empty (the default) means discover it: the pill browses mDNS for
        `_elg._tcp`, caches what it found in
        `~/.local/state/nebelhaus/elgato-host`, and re-browses at most once a
        minute whenever the light stops answering — so a light that took a new
        DHCP address comes back on its own, without a rebuild. Pin this when
        you have more than one light, when the light has a static lease, or
        when mDNS is unreliable on your network.
      '';
    };

    tour.enable = lib.mkOption {
      type = lib.types.bool;
      # A first-run tutor is an opinion about how a machine introduces itself,
      # not a property of the bar — nebelhaus selects it in its desktop.
      default = false;
      description = ''
        The haus tour — a first-run tutor that walks the four moves (launch /
        navigate / resize / palette) as ONE quiet pill in the bar, advancing
        live as each move is detected. It never opens a window or steals
        focus: a fresh machine just shows a dormant "new here?" hint, clicking
        it (or `haus tour`, or ⌘Space → tour) starts the lap, right-click
        hides it forever. Detection reuses signals the rice already fires (the
        leader-mode scripts) — no key logging, no Accessibility.

        Needs prowl + sill (it silently stays out of the bar without them);
        the ⌘Space step is dropped when pounce is off. Progress lives in
        ~/.local/state/nebelhaus — `haus tour reset` re-arms a finished tour.
      '';
    };

    tour.steps = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.nonEmptyListOf (
          lib.types.submodule {
            options = {
              hint = lib.mkOption {
                type = lib.types.str;
                example = "Press {palette}, type calendar, then hit ↵";
                description = ''
                  The instruction shown in the tour pill for this step.

                  Name keys with the placeholders `{palette}`, `{leader}` and
                  `{leaderName}` rather than typing a chord: they expand to what
                  THIS machine resolved, so a tour written once still teaches the
                  right keys on a rice that moved `keys.palette` or `keys.leader`.
                  A hardcoded "⌘Space" is wrong on that machine and the author
                  never sees it — the consumer does.
                '';
              };

              detect = lib.mkOption {
                type = lib.types.enum [
                  "launch"
                  "workspace"
                  "navigate"
                  "resize"
                  "palette"
                ];
                example = "palette";
                description = ''
                  The existing rice signal that completes this step: entering launch,
                  navigate or resize mode; changing workspace; or running the Haus Tour
                  command from Pounce (`palette`). The tour observes outcomes, never
                  keystrokes. Clicking the pill still skips a step that cannot be
                  detected in the current setup.
                '';
              };
            };
          }
        )
      );
      default = null;
      example = [
        {
          hint = "Press {palette}, type tour, then hit ↵";
          detect = "palette";
        }
      ];
      description = ''
        A community-authored tour, in order. null keeps the built-in four-move
        nebelhaus tour unchanged; supplying a list replaces it, so a shared rice can
        teach its own workflow without shipping scripts or reaching outside the
        `haus.*` option surface.

        Detection reuses signals the rice already emits. `launch`, `workspace`,
        `navigate` and `resize` need prowl; `palette` needs Pounce and its palette
        binding. The module warns when a chosen detector's room is disabled.

        Authoring a tour is also the ONLY way to have one without prowl: the
        built-in lap is three leader moves plus the palette, so `tour.enable` on a
        machine with `prowl.enable = false` draws nothing at all.
        `desktops/everyday.nix` is the worked example — one step, the launcher.
      '';
    };

    sill.items = lib.mkOption {
      type = lib.types.submodule {
        options = lib.mapAttrs (_: mkItem true) core // lib.mapAttrs (_: mkItem false) extra;
      };
      default = { };
      example = {
        weather = false;
        cpu = true;
      };
      description = ''
        Which SketchyBar pills to draw, one bool each. The core pills —
        `clock`, `weather`, `media`, `battery`, `wifi` — default true; the extras
        — the readouts `cpu`, `memory`, `volume`, `calendar`, `caffeinate`
        and the personal `agents`, `aiUsage`, `elgato`, `harvest` —
        default false. Set
        only what you want to change:

          haus.sill.items = {
            weather = false;   # drop a default-on core pill
            cpu = true;        # add an off-by-default readout
            caffeinate = true; # add the keep-awake controller
          };

        A pill set false is never created (its update script doesn't run either).
        The hush (Do-Not-Disturb) pill is separate — it rides
        haus.hush.enable, not this set. It can still be moved to the second bar
        with `haus.sill.bottom.items.hush`.

        This is the MENU BAR's set, and it is one group: the movable pills all
        sit on the right, because its left is the workspace pills, the front app
        and the leader picker, and its center is kept clear — that is the one
        span a MacBook's notch covers when the bar is at the top, which is where
        it is by default. `haus.sill.bottom.items` mirrors these pills
        for the optional second bar, also accepts `hush`, and takes a side
        (`"left"` / `"center"` / `"right"`) rather than a bare bool; a pill named
        there moves down rather than being drawn twice.
      '';
    };

    sill.bottom.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Draw a SECOND bar along the bottom of the screen, at the same time as
        the menu bar one. `haus.sill.bottom.items` picks what goes on it and
        which of its three groups — left, center, right — each pill lands in; an
        empty set draws an empty strip, which the module warns about.

        SketchyBar has no two-bars-in-one-process mode — an instance is named
        after `basename(argv[0])` and keys both its lock file and its mach
        service on that name — so this is a second launchd agent running the
        SAME binary under a second name, `sill-bottom`. That name is also the
        CLI for it: `sill-bottom --set cpu label=…` talks to the bottom bar the
        way `sketchybar --set` talks to the menu bar one.

        Two things macOS does not do for you here. It reserves the top strip of
        every display for the menu bar but reserves NOTHING at the bottom, so
        windows would sit under this bar: prowl carves the room out of its
        outer-bottom gap whenever this is on (with `haus.prowl.enable = false`,
        nothing reserves it and your windows will run underneath). And the Dock,
        if you keep it at the bottom, shares that edge — move it to a side, or
        leave it hidden.
      '';
    };

    sill.bottom.items = lib.mkOption {
      type = lib.types.submodule { options = lib.mapAttrs (_: mkBottomItem) movable; };
      default = { };
      example = {
        agents = "left";
        media = "center";
        clock = "right";
      };
      description = ''
        Which pills the bottom bar draws, and WHERE along it — one value each,
        all default false. A pill named here MOVES: it is drawn on the bottom
        bar and not on the menu bar, whatever `haus.sill.items` says about it —
        so there is one switch per pill per bar and never two copies of the
        same readout.

        Each value is `false` (not on this bar), one of `"left"`, `"center"`,
        `"right"` — the bar's three groups — or `true`, which is `"right"`:

          haus.sill.bottom.items = {
            agents = "left";
            media = "center";
            clock = "right";
            cpu = true;       # same as "right"
          };

        Within a group the order is fixed (the same order the menu bar uses),
        and each group packs outward from its own edge: on the `right` the
        first pill sits furthest right, exactly as `clock` does up top, while
        `left` fills rightward from the left edge and `center` grows around the
        middle of the screen. All three are offered here and only `right` is
        offered on the menu bar, because this strip has nothing else on it:
        no workspace pills, no front-app slot, and no notch across its middle.

        The set is the five core pills (`clock`, `weather`, `media`, `battery`,
        `wifi`) plus the `haus.sill.items` extras (`cpu`, `memory`, `volume`,
        `calendar`, `caffeinate`, `agents`, `aiUsage`, `elgato`, `harvest`), plus
        the Hush pill when `haus.hush.enable` is on. The whole left side
        (workspace pills, front app, the leader picker) and the tour stay on the
        menu bar.

        Needs `haus.sill.bottom.enable`; without it nothing here is drawn.
      '';
    };
  };
}

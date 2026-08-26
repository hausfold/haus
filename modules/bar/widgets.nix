# The bundled pills, as DATA — one entry per widget, imported by both
# options.nix (which renders each entry's description into the option
# reference, and builds the `bar.items` / `bar.bottom.items` tables from the
# same list) and default.nix (which emits the blocks and pre-declares each of
# them into `haus.bar.widgets`).
#
# It exists because `haus.bar.items` was a CLOSED submodule of bools that grew
# by one every time a pill shipped: sixteen leaves, sixteen more in
# `bar.bottom.items`, and no way at all for a rice that isn't this one to add a
# seventeenth. `haus.bar.widgets.<name>` is the open form (the workshop's
# notes/options-roadmap.md §5.9), and the rule that keeps the old surface
# meaning exactly what it meant is here: EVERY bundled pill is pre-declared as a
# widget, and `bar.items.<name>` is sugar that sets that widget's `enable`.
#
# So this table is the list of names the sugar covers, and nothing else may
# claim one of them — a stranger's `haus.bar.widgets.clock` is a collision, not
# an override, and modules/bar/default.nix says so by name.
#
# Fields
#   description  the single source for BOTH options' reference entries. Written
#                once; `bar.items.<name>`, `bar.bottom.items.<name>` and
#                `bar.widgets.<name>.enable` all render it.
#   default      whether the pill is drawn on a rice that says nothing. The five
#                core pills are true, the extras false — the same split the
#                closed submodule shipped with, preserved leaf for leaf.
#   movable      whether the pill may be moved to the second bar. `claudeUsage`
#                is the one false: it is a deprecated ALIAS for `aiUsage`, so it
#                names no pill of its own and `bar.bottom.items` never carried
#                it.
#   permissions  the macOS grants the pill actually needs to do its job, from
#                the enum in options.nix. Declared rather than documented so a
#                reader can answer "what on this bar is going to ask me for
#                something" without a second hand-written list —
#                which is the half of §5.9's last box that the ports metadata
#                in nebelung already proved out. A pill that needs nothing
#                carries `[ ]` rather than being left out, so the table stays
#                readable as a complete answer.
#   interval     the pill's own update_freq, in seconds, where it has one that a
#                person might reasonably want to change; null where the pill is
#                push-driven or its tick is load-bearing in a way a number
#                cannot express. It is the DEFAULT of
#                `haus.bar.widgets.<name>.interval`, and setting that option
#                emits a trailing `--set <item> update_freq=N` after the pill's
#                own block — which is why this can be honest about a pill whose
#                block hardcodes everything else.
{
  clock = {
    default = true;
    movable = true;
    permissions = [ ];
    interval = 10;
    description = "The clock pill, pinned to the far right.";
  };
  weather = {
    default = true;
    movable = true;
    permissions = [ "network" ];
    interval = 600;
    description = "The weather pill and its click-to-open forecast popover.";
  };
  media = {
    default = true;
    movable = true;
    # Automation for the scriptable browsers' tab APIs, Accessibility for the
    # Firefox forks that expose no tab list at all — both asked for by the ⌘
    # click, and both declined gracefully (the pill just fronts the app).
    permissions = [
      "automation"
      "accessibility"
    ];
    interval = 30;
    description = "The now-playing track — auto-hides when nothing plays, dims when paused, and counts DOWN instead of scrolling a title once the thing playing is longer than twenty minutes (a podcast or a video is one you already know the name of; what you keep glancing at the bar for is how much is left). The title scrolls for a few seconds after a track changes and then settles, so nothing moves in the corner of your eye forever; hovering brings the full title back. Gestures: left click the dropdown, RIGHT click play/pause, ⌥ next, ⇧ previous, ⌘ jump to whatever is making the noise, scroll to seek ±10s. That ⌘ click reaches the browser TAB, not just the browser: the track's title is matched against the open tabs through Safari's and Chromium's AppleScript tab APIs, and on a Firefox fork (Zen among them) — which expose no tab list at all, neither to AppleScript nor to accessibility — through Firefox's own open-tab search in the address bar. Both routes ask for a permission the first time they run, Automation for the scriptable browsers and Accessibility for the Firefox forks, and both quietly fall back to just fronting the app if you say no. The dropdown carries the cover when the source published one, a scrubbable position slider, and transport rows — plus, for a source with no cover, a small app-icon badge floating in its bottom-right corner. It reads the same system-wide session Control Center does, so it follows a browser tab as readily as Apple Music or Spotify, and its icon says what KIND of thing is playing: an app it recognises gets that app's glyph, a browser gets video or music depending on whether an album was published. It cannot say which SITE — no URL reaches the now-playing session and none of window titles, artwork shape or the session's pid can recover one, so a wrong YouTube glyph on a Netflix tab is a guess this deliberately doesn't make; `haus.bar.media.icons` is the override for a machine that knows better. SketchyBar's own `media_change` event has been dead since macOS 15.4, where Apple started requiring an entitlement to talk to `mediaremoted`; the pill is fed instead by `media-control`, which does the read from inside the entitled `/usr/bin/perl`. That is a private-framework route Apple could close in any point release — `media-control test` exits non-zero once it has.";
  };
  battery = {
    default = true;
    movable = true;
    permissions = [ ];
    interval = 30;
    description = "The battery pill.";
  };
  wifi = {
    default = true;
    movable = true;
    permissions = [ ];
    interval = 10;
    description = "The Wi-Fi status pill.";
  };

  cpu = {
    default = false;
    movable = true;
    permissions = [ ];
    interval = 2;
    description = "Total CPU load, drawn as a graph pill: the last two minutes of it behind the number, because a percentage on its own can't tell a spike settling from a climb that started five minutes ago. The reading is a DELTA between samples — the `ps` sum this used to print is each process's average over its whole lifetime, which on a machine that has been up a week barely moves while every core is pinned. LEFT-CLICK opens a dropdown: the user/system split, the load average, then what's responsible, biggest first and aggregated per app so a browser's twenty helpers are one row; clicking a row focuses that app's window. RIGHT-CLICK opens Activity Monitor on its CPU tab. The rows can only cover processes you own, so anything root runs — `kernel_task`, `WindowServer` — lands in `everything else` rather than going quietly missing from the sum.";
  };
  memory = {
    default = false;
    movable = true;
    permissions = [ ];
    interval = 5;
    description = "Memory in use, drawn as a graph pill. It counts what Activity Monitor counts — app memory + wired + compressed — and deliberately NOT the file cache: macOS fills idle RAM with cache on purpose, and the old reading counted that as used, which is why it sat near 90% on a machine doing nothing. The pill's COLOUR is the kernel's own pressure level (green normal, amber warning, red critical) rather than the percentage, because 60% of RAM in use is a Mac working correctly and a pill that goes amber for it is a pill you learn to ignore. LEFT-CLICK opens a dropdown with used/total, the cache, compressed and swap figures and then the biggest footprints per app, each row clicking through to that app's window. RIGHT-CLICK opens Activity Monitor on its Memory tab.";
  };
  volume = {
    default = false;
    movable = true;
    permissions = [ ];
    interval = 5;
    description = "Output volume / mute state.";
  };
  calendar = {
    default = false;
    movable = true;
    permissions = [ "calendar" ];
    # Owned by `haus.bar.calendar.refresh`, which shipped first and is the
    # option a person already found. Two settings for one update_freq is the
    # drift this table exists to end, so this one declares none.
    interval = null;
    description = "The one meeting you have to be at next, and one gesture to join it. It reads \"in 12m · Design review\" — countdown first, because a label is clipped from the END and the number is the part you must never lose; below `haus.bar.calendar.preciseUnder` hours it carries minutes, above it just \"in 14h\" or \"in 2d\", and while an event is running it says \"now · …\" instead of going blank. For `haus.bar.calendar.imminent` minutes either side of the start the whole pill FILLS with the accent — a shape change rather than a colour change, so it catches the eye you aren't pointing at it. RIGHT-CLICK joins: it opens the event's conferencing link, found in the invite's url, location or notes (Meet, Zoom, Teams, Webex, Jitsi, Whereby and friends out of the box; `haus.bar.calendar.joinHosts` adds your own). LEFT-CLICK opens the day as a timeline — what's DONE in the last `haus.bar.calendar.past` hours, what's on NOW, and what's NEXT — each event carrying its day, clock time, length and who it's with, the next one boxed, and a `Join` affordance on every row that has a link. Your own address is dropped from the \"with\" line automatically: a CalDAV calendar is named for the account it syncs, so the pill can work out which attendee is you with no configuration (`haus.bar.calendar.me` for the cases where it can't). A name too long for the pill sweeps past only while you HOVER it — nothing here starts a marquee on its own — and `haus.bar.calendar.width` sets how much room it gets before that applies. Pulls in `ical-buddy` automatically and reads Calendar, so macOS prompts for Calendar access on first run.";
  };
  caffeinate = {
    default = false;
    movable = true;
    permissions = [ ];
    interval = 30;
    description = "A coffee pill that prevents idle system sleep for 1/2/4/8 hours, a custom whole-hour duration, or indefinitely. The display may still turn off; closing a MacBook lid still sleeps it. Uses macOS's built-in `caffeinate`, so there is no extra package.";
  };
  agents = {
    default = false;
    movable = true;
    permissions = [ ];
    interval = 10;
    description = "A pill tracking your agent windows, marked with a robot, one mark and a count per state: a filled `?` for the ones ready for your turn, an open ring for the ones working, a tick for the ones done. They sit in that order — urgency, left to right — a state with nothing in it draws nothing at all, and the robot takes the most urgent live state's colour, so the pill answers \"is anything waiting on me\" and \"what else is running\" in one glance rather than naming only the winner. Click for the per-agent breakdown, sorted the same way (waiting first, then working, then idle, longest-elapsed first within each), each block showing the client, how long it's sat in that state, and — when the window's checkout is a `holt` lane — its repo and PR status: merged, `+N unshipped` (exactly what `holt reship` fixes), not yet landed, or a dirty-tree footnote. A summary header totals the counts once more than one agent is running. Left-click a row to jump to that window, ⌥/right-click for a live peek at what it is saying (`zmx tail`) — except a desktop session, whose transcript is not readable from outside the app, so that row raises the app on either click. Fed by each client's own lifecycle hooks, which all call `agent-state` (also installed as ~/.config/sketchybar/plugins/agents-hook.sh): Opencode's plugin and Codex's ~/.codex/hooks.json are written for you (Codex asks you to trust its hooks the first time it sees them), while Claude Code's four agent-state hooks stay yours to point at it in ~/.claude/settings.json — Claude owns that file and rewrites it, so haus merges in only the keys it must and never touches those four. (The two worktree hooks — and a `holt hook notify` entry appended beside yours on four events: Notification/Stop raise a trill banner when a lane blocks on you or finishes, UserPromptSubmit/PostToolUse take that banner back down once you have answered — ARE declared, in terminal: they point at a haus-controlled path and self-heal on rebuild.) A row lives as labels on the window's own zmx session, so it disappears the moment that session does — which is what stands in for the session-end event Codex doesn't have. A session in Claude Code's DESKTOP app has no window of its own, so it is tracked by its conversation id instead and a click raises the app — every conversation there is a tab of the one window. Its row drops off when the session ends, and, since a force-quit fires no such event, whenever the app itself is not running. Subagents are deliberately not rows: they sit inside a session that already has one. Dormant until a client fires.";
  };
  aiUsage = {
    default = false;
    movable = true;
    permissions = [ "network" ];
    interval = 15;
    description = "A gauge pill showing AI usage (Claude Code/Codex subscription rate limits as %, or Opencode API token cost as daily $). Automatically shows whichever provider reported most recently. Click for expanded session/weekly limits and daily/monthly API costs with model breakdowns. Claude and Opencode are read off disk; Codex has no local usage data, so its row is polled from your ChatGPT account with the OAuth token in ~/.codex/auth.json (refreshed and rewritten in place) — no Codex login on the machine, no call is made. Claude's row is pushed by its statusline; the Codex and Opencode rows are pulled by the pill itself on a 3-minute TTL, so they stay current on a machine that never opens Claude at all. Claude and Opencode also get a `tokens` block in the dropdown — raw tokens moved today, this week, this month and all time (cache reads and all), two periods to a line so a full set reads as a 2×2, purely for the fun of watching the number climb. A period with nothing in it is left out rather than printed as a zero, so the block simply gets smaller, and a closing `∑ Everything` adds every provider up when more than one is reporting. It is a score, not a limit: nothing acts on it, and it never reaches the pill's own label. Claude's is summed from your transcripts on a 15-minute TTL behind an index, so only sessions that grew since the last pass are re-read; Codex has no row because it keeps no local history to count.";
  };
  # The one non-pill in the table. It is a deprecated ALIAS for `aiUsage` and
  # draws nothing of its own, which is why it is not `movable` and why
  # modules/bar/default.nix folds it into that widget's `enable` rather than
  # pre-declaring a widget for it.
  claudeUsage = {
    default = false;
    movable = false;
    alias = "aiUsage";
    permissions = [ ];
    interval = null;
    description = "Deprecated alias for `aiUsage`.";
  };
  github = {
    default = false;
    movable = true;
    permissions = [ "network" ];
    interval = 60;
    description = "One number from GitHub, and the rows behind it. The pill is configured as a list of typed SOURCES (`haus.bar.github.sources`) — a `search` filter, the `ci` board, or your own `command` — and its label is whichever source is worth interrupting you for: the highest-severity one with a nonzero count, earliest in the list on a tie. With nothing to report it draws no number at all rather than a zero, because a number you never act on is a number you stop seeing. The pill is TWO-TONE: the number is how many, coloured by the source it counts, and the octocat beside it is how bad, coloured by the worst single row anywhere — so five open PRs of which one conflicts reads as a neutral `5` under a peach logo, rather than as five bad things or as nothing wrong. The tones are one ladder: grey is no verdict (a draft, an issue), green is fine (and, approved-and-green, ready to press the button), sky is in flight (checks still running — the machine's turn), peach wants a human on one pull request (it conflicts, its checks came back red, or a reviewer asked for changes), and RED is reserved for a red DEFAULT BRANCH. Nothing one of your PRs can do turns the pill red, because a red that fires for every work-in-progress is a red you stop reading; the only other way to reach it is a source you declared `bad` yourself. Green is not a resting state: with nothing open there are no rows at all and the logo keeps the number's own grey, so a green octocat means \"there is a queue, and every row in it is fine\". LEFT-CLICK opens the dropdown, one section per source, each row clicking through to the PR or repo on github.com; RIGHT-CLICK refreshes now, as does the `Refresh` row at the bottom of the dropdown, which also says how old the numbers are. The `ci` source is the one thing gh-dash cannot show you: GitHub's search index carries no workflow runs, so \"did main's last run pass\" is only reachable as the check rollup of the default branch's head commit, in GraphQL — which is exactly what that source asks for, in one query for the whole owner. Needs `haus.developer.git.enable` (an assertion enforces it) for the `gh` it queries through, and a `gh auth login` you have run: not logged in, the pill says `auth` and its dropdown hands you that command rather than drawing a silent zero. Never fetches on the bar's tick — the tick renders a cache and detaches the network call — so a slow GitHub costs a stale number, never a stalled bar.";
  };
  elgato = {
    default = false;
    movable = true;
    permissions = [ "network" ];
    interval = 5;
    description = "Toggles an Elgato Key Light on the local network. The light is found over mDNS (or pinned with `haus.bar.elgato.host`), and the pill draws dim when it can't be reached at all — a light that dropped off the wifi is not the same thing as a light that's switched off.";
  };
  harvest = {
    default = false;
    movable = true;
    permissions = [ "network" ];
    interval = 3;
    description = "A Harvest time-tracking pill; needs a ~/.config/sketchybar/harvest_secrets.sh you provide. Click to stop the running timer or restart the last one. Like the Elgato pill it draws dim when Harvest can't be reached, keeping the label that names what was running — an API it can't ask is not the same thing as a timer that isn't running, and the two used to look identical.";
  };

  # trill IS a haus flake input now, and `haus.trill.enable` installs the bundle
  # — but that room is off by default and Trill.app is just as often the user's
  # own install, so this pill still cannot assume its subject is there. That is
  # the same shape terminal's `holt hook notify` already has: wired here,
  # silently absent on a Mac without Trill.app, never a broken bar.
  trill = {
    default = false;
    movable = true;
    permissions = [ ];
    interval = 30;
    description = "Opens trill's inbox — the notification compositor's history window — in one click, from a bar that is always on screen. It exists because the alternative doesn't work here: trill's own menu-bar item lives in macOS's menu bar, which `haus.bar.enable` hides (`_HIHideMenuBar`), so on a Mac running this desktop the inbox is only reachable by hover-revealing a bar that is meant to stay out of the way. LEFT-CLICK opens the inbox, RIGHT-CLICK (or ⌥-click) opens it filtered to the asks — the questions parked on trill's ledge that are still waiting on you. The pill draws nothing at all when Trill.app isn't installed, because a control for an app you don't have is noise rather than an invitation; with the app installed but its daemon down it draws dim, which is the same distinction the elgato and harvest pills already make between \"switched off\" and \"can't be reached\". It carries no count yet: trill's inbox grew unread state in hausfold/trill#25, but no CLI verb reads it back out, and a badge computed by reading another app's SQLite behind its back is exactly the kind of claim that rots when the schema moves.";
  };

  # The Focus pill is bundled and movable but is NOT in `bar.items`: it rides
  # the Focus room's contribution rather than an opt-in bool, which is the one asymmetry
  # the old tables carried and this one keeps. `default = null` says exactly
  # that — "another room decides" — and modules/bar/default.nix is where the
  # room is named, so a widget the bar cannot switch on by itself can still be
  # MOVED like any other.
  focus = {
    default = null;
    movable = true;
    # The bell TOGGLES quiet, and modules/focus does that by pressing a hidden
    # symbolic hotkey synthetically — which macOS lets an app do only with
    # Accessibility. Declared `[ ]` until the manual-click deck started reading
    # this table and the omission became visible: a palette-run scene inherits
    # pounce's grant, so nothing ever asked on sketchybar's behalf.
    permissions = [ "accessibility" ];
    interval = 30;
    description = "The Focus (Do-Not-Disturb) pill, drawn as a moon: a plain crescent while notifications are getting through, a crescent-and-stars on mauve while the Mac is quiet. It wore a bell until the `trill` pill above wanted one — a bell is what a notification IS, and two bells side by side (one struck) made the bar ask you to remember which was which, where every operating system that has ever shipped a Do-Not-Disturb switch has drawn it as a moon. Needs `haus.focus.enable`; setting this moves the pill but does not enable the Focus room by itself.";
  };
}

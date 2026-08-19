# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# bar's options — the bar(s): whether one is drawn, which pills go on it, the
# optional second bar along the bottom of the screen, and the first-run tour
# that rides in the top one.
{ lib, ... }:

let
  agentClients = import ../lib/agents.nix;
  accentNames = import ../lib/accents.nix;

  # ---- the bundled pills -----------------------------------------------------
  # The names, defaults and descriptions all come out of ./widgets.nix, which
  # is the ONE table both this file and default.nix read. It used to be two
  # hand-written attrsets right here (`core` and `extra`), which is exactly the
  # shape §5.9 of the workshop's notes/options-roadmap.md was written about: a
  # closed submodule that grew a leaf every time a pill shipped, in three places
  # each time (here, `bar.bottom.items`, and the block table in default.nix).
  #
  # `bar.items` and `bar.bottom.items` are unchanged as a SURFACE — same leaves,
  # same types, same defaults, same prose — but they are now sugar over
  # `haus.bar.widgets.<name>`, the open form a rice that isn't this one can add
  # a seventeenth pill to. Anything a bundled pill needs to say about itself is
  # said in widgets.nix; nothing about a pill is written twice.
  widgets = import ./widgets.nix;

  # Which of them `bar.items` offers, and what each defaults to. `focus` carries
  # `default = null` — it rides `haus.focus.enable` rather than a bool of its
  # own — so it is in neither table's ON/OFF surface, and is filtered out here
  # by that null rather than by name.
  switchable = lib.filterAttrs (_: w: w.default != null) widgets;
  # The five that draw on a rice which says nothing, and the rest. Split only to
  # keep the parent option's prose able to name them; both halves are the same
  # table's `default` field.
  coreNames = lib.attrNames (lib.filterAttrs (_: w: w.default == true) switchable);
  extraNames = lib.attrNames (lib.filterAttrs (_: w: w.default == false) switchable);

  mkItem =
    w:
    lib.mkOption {
      type = lib.types.bool;
      inherit (w) default;
      description = w.description;
    };

  # Which pills the SECOND bar can host. The whole right side is emitted from
  # one parameterized block table, so core and extra pills can move without a
  # second source copy. `claudeUsage` is left out because it is only a
  # deprecated alias for `aiUsage`.
  # A widget marked `movable = false` names no pill of its own: `claudeUsage` is
  # a deprecated ALIAS for `aiUsage`, so there was never a second thing to move
  # and this table never carried it. `focus` IS here, though `bar.items` has no
  # switch for it — moving a pill and switching it on are different questions,
  # and the Focus room answers the second.
  movable = lib.filterAttrs (_: w: w.movable) widgets;

  # The bottom bar's three groups. Shared with default.nix, which emits one run
  # per group in this order — see sides.nix for why it is one list and not two.
  sides = import ./sides.nix;

  # ---- one widget ------------------------------------------------------------
  # The open form. Everything a pill IS, for the bundled sixteen and a
  # stranger's seventeenth alike — which is the point: a rice that adds a pill
  # writes the same fields haus's own pills carry, so there is no second-class
  # widget and no private field a bundled pill gets and a new one doesn't.
  #
  # `bundled` is the exception that proves it. A bundled widget's BLOCK is a
  # hand-written SketchyBar run in default.nix — dropdown rows, click gestures,
  # popup alignment, colour rules — and none of that is expressible here, so
  # `command` on one of them is refused rather than half-honoured (the
  # assertion is in default.nix, which is the only file that knows which is
  # which). What a bundled widget DOES admit is the two fields that mean the
  # same thing for every pill on the bar: where it sits, and how often it runs.
  widgetModule =
    { name, config, ... }:
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether to draw this pill. A widget you declared is on by default —
            you wrote it down to get it — while the bundled pills keep the
            defaults they always had, which `haus.bar.items` is the sugar for.

            Off is not "hidden": the pill is never created and its command
            never runs, so a widget switched off costs nothing at all.
          '';
        };

        command = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "/etc/haus/backup-status.sh";
          description = ''
            The script whose output is this pill's label, run every
            `interval` seconds. One line on stdout is the label; nothing at all
            hides the pill for that tick, which is how a widget says "no news"
            without drawing an empty box.

            It runs as you, with SketchyBar's own variables in the
            environment (`$NAME` is this widget's item id, `$BUTTON` and
            `$SENDER` on a click). Reach the bar back through `$SB` after
            sourcing `~/.config/sketchybar/bar.sh` rather than by naming
            `sketchybar`, so a widget moved to the bottom bar keeps talking to
            the bar it is actually on — see AGENTS.md, it is the single most
            common way a pill silently stops updating.

            null on a bundled pill, whose behaviour is haus's own plugin, and
            setting one there is an error rather than an override.
          '';
        };

        interval = lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          default = null;
          example = 300;
          description = ''
            How often to run `command`, in seconds. Works on the bundled pills
            too, where it retunes what that pill already polls at:

              haus.bar.widgets.weather.interval = 1800;

            null keeps the widget's own default — for a bundled pill the rate
            it ships with, for yours a 60-second tick. A few pills are
            push-driven rather than polled (`agents`, `page`) and a couple own
            their rate through an older option of their own
            (`haus.bar.calendar.refresh`); setting this on one of those is
            accepted and changes only the backstop tick, which is exactly what
            update_freq is on a pill that repaints on an event.
          '';
        };

        icon = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "󰁯";
          description = ''
            The glyph drawn to the left of the label, in the bar's own font
            (`haus.fonts.mono.name`), so any Nerd Font glyph works. Empty
            draws no icon and gives the label the whole pill.

            Ignored on a bundled pill: those set their own, and several change
            it to say something (the memory pill's pressure colour, the
            github pill's two-tone logo).
          '';
        };

        placement = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.enum ([ "menu-bar" ] ++ map (side: "bottom-${side}") sides ++ sides)
          );
          default = null;
          example = "bottom-left";
          description = ''
            Which bar this pill sits on, and where along it.

            `"menu-bar"` is the top bar, and is where every pill goes unless
            something says otherwise — it has one group to offer, because its
            left is the workspace pills and its centre is the notch.
            `"bottom-left"`, `"bottom-center"` and `"bottom-right"` are the
            second bar's three groups, and need `haus.bar.bottom.enable`.

            A bare `"left"` / `"center"` / `"right"` is the same three groups
            of the bottom bar, spelled the way `haus.bar.bottom.items` spells
            them — that option is sugar for this field, so both spellings
            reach the same place.

            null means "wherever the sugar put it", which on a machine that
            never mentions this pill is the menu bar.
          '';
        };

        permissions = lib.mkOption {
          type = lib.types.listOf (
            lib.types.enum [
              "accessibility"
              "automation"
              "calendar"
              "contacts"
              "full-disk-access"
              "location"
              "microphone"
              "network"
              "photos"
              "reminders"
              "screen-recording"
            ]
          );
          default = [ ];
          example = [ "full-disk-access" ];
          description = ''
            What macOS will ask this widget for the first time it runs.

            A DECLARATION and nothing more: haus requests none of these, and
            listing one neither grants it nor makes the pill wait for it. What
            it buys is a widget that can be READ for what it will reach for
            before you switch it on — the pill you installed from someone else
            most of all. That is the same shape nebelung's ports metadata
            uses, one room over: the declaration lives with the thing, the
            consumer reads it.

            `network` is not a macOS grant at all, and is here because "this
            pill talks to the internet" is the property people actually want
            to see on a widget they didn't write.
          '';
        };
      };
    };

  # A pill on the SECOND bar. Same table as `bar.items`, but each value also
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
    w:
    lib.mkOption {
      type = lib.types.either lib.types.bool (lib.types.enum sides);
      default = false;
      description = w.description;
    };

  # ---- one source of the github pill -----------------------------------------
  # Exactly one of `search`, `ci` and `command` per entry; modules/bar asserts
  # it by index rather than the type doing it, because "you set two of three on
  # sources[1]" is a sentence a type error cannot write.
  #
  # The kinds are separate fields rather than a `kind` enum plus a payload, so
  # the common case stays one line — `{ ci = true; }`, `{ search = "…"; }` — and
  # so the option reference documents each kind where it is declared instead of
  # in a paragraph under an enum.
  githubSource = {
    search = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "org:hausfold is:pr is:open";
      description = ''
        A GitHub issue/PR search filter, exactly as you would type it into
        github.com's search box. The count is the search's own hit total, which
        can be larger than the rows shown — the dropdown says how many it left
        out rather than letting a truncated list read as a complete one.

        Each row it draws carries its own MERGE VERDICT, from the same request
        that counted them: whether the pull request conflicts, what its head
        commit's checks came back as, and what the review landed on, folded into
        the one state GitHub's own merge box answers with. That is the row's
        glyph and colour, and the worst of them across every source is what
        tints the pill's logo. In precedence order: a draft is muted (its author
        already said "not ready", so its red checks are not news), then a
        conflict, then failed checks, then checks still running, then changes
        requested, then approved-and-green — which gets a glyph of its own,
        being the one row that means you can press the button. A mergeability
        GitHub has not computed yet reads as no verdict and resolves itself on
        the next refresh.

        The string is literal: nothing interpolates `haus.git.org` into it for
        you, because a machine that reads several owners is the reason that
        option is allowed to be empty. Write the `org:` in.
      '';
    };
    ci = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Every repo the owner has, its default branch, and whether that branch's
        head commit is green — one GraphQL query for the whole owner, counting
        the ones that came back FAILURE or ERROR. Archived repos are skipped; a
        repo with no checks at all is not a failure and is not counted.

        This is the source that exists because search cannot answer it. It is
        also why the pill is a pill: it is the one GitHub question with no
        `gh-dash` tab, since a dashboard section IS a search filter.
      '';
    };
    command = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "gh api /notifications --jq '.[] | \"warn\\t\" + .subject.title'";
      description = ''
        A command run through `bash -c`, printing one row per line as
        `<state>\t<text>` or `<state>\t<text>\t<url>`, where state is `ok`,
        `warn` or `bad`. The count is the number of rows; a line that doesn't
        match the shape is dropped rather than drawn mangled.

        It runs from the bar's detached fetch, i.e. under launchd's environment
        and not your interactive shell: name binaries by absolute path or expect
        them missing. Host-only — a desktop may not set it, since it is
        arbitrary code rather than data.
      '';
    };
    org = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "hausfold";
      description = ''
        Which owner the `ci` source asks about. Empty (the default) follows
        `haus.git.org`, which is where it should normally come from — an owner
        that renames is then one word for the whole machine. Set it only to
        point one source at a second owner.
      '';
    };
    title = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "red on main";
      description = ''
        The dropdown section's heading. Empty derives one: the owner and
        "default branches" for `ci`, the filter itself for `search`.
      '';
    };
    icon = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "";
      description = ''
        The glyph beside that section's heading, in the bar's Nerd Font. Empty
        takes a default for the kind.
      '';
    };
    severity = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "info"
          "warn"
          "bad"
        ]
      );
      default = null;
      defaultText = lib.literalMD "`bad` for a `ci` source, `info` for the others";
      example = "bad";
      description = ''
        How much this source's count matters, which decides both its colour
        (`info` neutral, `warn` peach, `bad` red) and which source the PILL
        speaks for when more than one has something to say — highest severity
        first, then list order.

        It is per-source rather than global because the same kind means
        different things in two entries: `is:pr is:open` is a work queue and
        `is:pr is:open status:failure` is an alarm, and both are searches.
      '';
    };
    limit = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 8;
      example = 5;
      description = ''
        How many rows this source may put in the dropdown. Also what a `search`
        asks GitHub for per page — there is no point paging in a hundred hits to
        draw eight of them. The count is unaffected: it is the real total, and
        the dropdown says how many rows it left out.
      '';
    };
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

        Off, `haus.bar.items.agents` draws nothing — a machine with no agent
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

    bar.enable = lib.mkOption {
      type = lib.types.bool;
      # Rooms are opt-in: the neutral catalogue selects none, and a desktop
      # (or a host) turns this one on. Everything BELOW this switch keeps its
      # tuned value — a bar that is drawn is drawn properly, which is the
      # "neutral, useful configuration when enabled" half of the room contract.
      default = false;
      description = ''
        The SketchyBar menu bar. When off, the native macOS menu bar is kept
        (hacker stops hiding it) and no bar is drawn.
      '';
    };

    bar.position = lib.mkOption {
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

    bar.logo.icon = lib.mkOption {
      type = lib.types.str;
      # The glyph, not a name: `haus.workspaces.<id>.icon` and
      # `haus.bar.media.icons` already take one, so this is the surface the
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
        until it was the hacker cat-ears mark. Any single character your bar
        font can draw; the default is Nerd Font's `nf-fa-home` (`U+F015`), a
        solid house.

        It has to hold up at 28pt with a pill's padding around it, which rules
        out more glyphs than you would expect. In particular **`⌂` (`U+2302`),
        the hausfold mark itself, is drawn hairline-thin in JetBrains Mono and
        does not gain weight at Bold or ExtraBold** — it is in the font, it is
        on the list below, and beside the workspace pills it reads as a much
        lighter object than everything around it. A taste call, not a bug: if
        you want the literal mark, take it and raise `haus.bar.logo.size`.

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
        cannot sweep on hover. haus drew this pill as a PNG for a while and
        every one of those was a real limitation of it.
      '';
    };

    # Documented once, here, because three of the four gestures below are
    # pounce's and the option page is where someone finds that out.
    bar.logo.gestures = lib.mkOption {
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
        `haus.launcher.enable` (which the hacker desktop turns on). With pounce
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

    bar.logo.size = lib.mkOption {
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

    bar.logo.color = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum accentNames);
      default = null;
      example = "teal";
      description = ''
        The logo's resting colour, by Catppuccin name. `null` (the default)
        follows `haus.theme.accent`, which is almost always what you want — the
        pill is haus's own mark, so it wearing haus's own accent is the
        point.

        This is only the RESTING colour. `haus.bar.logo.status` paints over it
        while something needs attention, and the hover sweep runs from it and
        returns to it.
      '';
    };

    bar.logo.status = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Let the logo's colour report the health of the machine, so the pill says
        something without being clicked:

        | colour | meaning |
        |---|---|
        | accent | everything haus runs is up |
        | `yellow` | a newer haus is pinned upstream (needs `haus.bar.logo.updateCheck`) |
        | `red` | something haus runs is enabled but not running |

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

    bar.logo.updateCheck = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Add the yellow "a newer haus is available" state to the logo pill. Off
        by default because it is the one part of the pill that leaves the
        machine: it asks GitHub for haus's current head (the same
        `git ls-remote` behind `haus status`) once every half hour, and a bar
        that phones home should be something you turned on.

        No effect unless `haus.bar.logo.status` is on.
      '';
    };

    bar.logo.sweep = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Sweep the logo through the six hausfold accents — mauve, teal, green,
        yellow, peach, pink, the order the site runs them (nebelung → holt →
        perch → trill → pounce → hacker) — while the pointer is over it,
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

    bar.battery.hideOver = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 80;
      description = ''
        Hide the battery pill when charge percentage is above this threshold
        (e.g., set to 80 to show the battery pill only when charge is at or below 80%).
      '';
    };

    bar.clock.mode = lib.mkOption {
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

    bar.clock.monoFont = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = ''
        Whether the clock pill's date and time use `haus.fonts.mono.name`, like
        the rest of Bar. Disable this to draw them in `haus.fonts.sans.name`
        instead — macOS's system UI font by default, whose zero has no dot and
        is easier to distinguish from an 8 at a glance. The calendar icon
        remains in the Nerd Font either way.

        This pill is the only place `haus.fonts.sans.name` is read, so the two
        options are really one switch: this one chooses the family, that one
        says which.
      '';
    };

    bar.aiUsage.provider = lib.mkOption {
      # The clients come from modules/lib/agents.nix — the same list
      # haus.ai.clients and .default read, so a fourth client is one
      # edit rather than one per room. `latest` is bar's own extra: it is a
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

    bar.github.sources = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule { options = githubSource; });
      default = [ ];
      defaultText = lib.literalMD ''
        the owner's red default branches, then its open PRs — but only when
        `haus.git.org` names an owner. Empty otherwise, since neither
        question can be asked without one.
      '';
      example = lib.literalExpression ''
        [
          { ci = true; }                                            # red default branches
          { search = "org:hausfold is:pr is:open"; }                 # the working queue
          {
            search = "org:hausfold is:pr is:open status:failure";    # …and the red half of it
            title = "red PRs";
            severity = "bad";
          }
        ]
      '';
      description = ''
        What the `github` pill counts, in the order it prefers to speak about
        them. Each entry names exactly ONE kind — `search`, `ci` or `command` —
        and the pill owns the query for that kind.

        It is typed rather than one free-form query string because the two
        questions have no common shape. A `search` is a GitHub search filter and
        comes back as a count plus rows with a title, a repo and a URL; the CI
        board does not exist in that index at all — GitHub's search carries no
        workflow runs — and is only reachable as the `statusCheckRollup` of a
        default branch's head commit, in GraphQL. Handing the option a raw
        GraphQL query instead would move the problem rather than solve it: the
        result is an arbitrary tree, so the pill would also need paired jq paths
        for the count, the rows and the state, and every one of them would fail
        at runtime inside a bar plugin, where the only symptom is a pill that
        draws nothing. `command` is the escape hatch, and it is a command rather
        than a query for the same reason: it can do the fetching AND the
        shaping, and you can run it in a terminal to see why it is wrong.
      '';
    };

    bar.github.refresh = lib.mkOption {
      type = lib.types.ints.between 60 3600;
      default = 300;
      example = 900;
      description = ''
        How often, in seconds, the `github` pill re-asks GitHub. The floor is
        60 and it is enforced by the type rather than written down: this is the
        first pill in the bar that crosses the network, and GitHub's authed
        budget is 30 search requests a minute and 5000 GraphQL points an hour —
        shared with every other `gh` on the machine, `gh-dash` included.

        The pill never fetches on the bar's tick. The tick renders a cache and,
        if it has gone stale, detaches the fetch; so this is how old a number
        may be, not how long anything waits.
      '';
    };

    bar.media.collapse = lib.mkOption {
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

    bar.media.width = lib.mkOption {
      type = lib.types.ints.positive;
      default = 32;
      example = 16;
      description = ''
        How wide the media pill's title is allowed to get, in CHARACTERS — not
        pixels. Anything longer is clipped to this and swept past instead, so
        this is the knob for how much of the bar the now-playing title may rent.

        Narrow it on a MacBook, where the bar's centre span sits under the notch
        and every character of title is paid for out of the room the workspace
        pills and the front-app name need. `haus.bar.media.collapse` is the
        harder version of the same trade: no title at all until you hover.

        It is a MAXIMUM, not a fixed size — the pill still shrinks to fit a
        short title, so a wide setting costs nothing until something long plays.
      '';
    };

    # The pill's only motion, and its own switch so
    # haus.appearance.reduceMotion has a leaf to set rather than reaching into
    # the plugin. Default true: this is what the pill does today, and a rice
    # that never asked for quiet keeps it byte for byte.
    bar.media.marquee = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = ''
        Sweep a long track title past while the pointer is on the media pill.

        Hover is the only thing that starts it — nothing here runs a marquee on
        a track change or on a timer — and one hover buys one full pass back to
        the start. Off, a title too long for `haus.bar.media.width` is simply
        clipped, and the dropdown still carries it in full, so nothing is lost
        but the movement.

        `haus.appearance.reduceMotion` turns this off as a default, along with
        the rest of the motion haus draws.
      '';
    };

    bar.media.artworkTint = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Colour the media pill's glyph from the current cover art instead of from
        what kind of thing is playing.

        The colour is the cover's average, SNAPPED to the nearest member of the
        Nebelung palette — so the pill picks up the mood of a record without ever
        drawing a colour that isn't in the theme. Off by default because it
        trades a stable meaning (pink is Music, green is Spotify, red is video)
        for a colour that changes every three minutes.

        Only sources that publish artwork can drive it, which is fewer than you
        would think: every Firefox-family browser publishes none at all, and the
        pill falls back to the kind colour for those.
      '';
    };

    bar.media.icons = lib.mkOption {
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

          haus.bar.media.icons."browser.video" = "󰗃";
      '';
    };

    bar.calendar.width = lib.mkOption {
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

    # Same shape as bar.media.marquee, same reason — see there.
    bar.calendar.marquee = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = ''
        Sweep a long event title past while the pointer is on the calendar pill.

        Hover only, exactly like the media pill's: the label is clipped to
        `haus.bar.calendar.width` and hovering shows the rest. Off, the clip is
        all you get on the pill and the timeline dropdown carries the full name,
        which is where a title you actually need to read belongs anyway.

        `haus.appearance.reduceMotion` turns this off as a default, along with
        the rest of the motion haus draws.
      '';
    };

    bar.calendar.refresh = lib.mkOption {
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

    bar.calendar.horizon = lib.mkOption {
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

    bar.calendar.preciseUnder = lib.mkOption {
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

    bar.calendar.imminent = lib.mkOption {
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

    bar.calendar.past = lib.mkOption {
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

    bar.calendar.upcoming = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      example = 3;
      description = ''
        How many future events the dropdown's `Next` band lists, at most. The
        first of them is the one the pill is about, and the one drawn in a box.
      '';
    };

    bar.calendar.me = lib.mkOption {
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

    bar.calendar.joinHosts = lib.mkOption {
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

    bar.elgato.host = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "elgato-key-light-mini-57a3.local";
      description = ''
        Which Elgato Key Light the `elgato` pill toggles — a hostname or IP,
        optionally with a `:port` (the light's HTTP API is on 9123).

        Empty (the default) means discover it: the pill browses mDNS for
        `_elg._tcp`, caches what it found in
        `~/.local/state/haus/elgato-host`, and re-browses at most once a
        minute whenever the light stops answering — so a light that took a new
        DHCP address comes back on its own, without a rebuild. Pin this when
        you have more than one light, when the light has a static lease, or
        when mDNS is unreliable on your network.
      '';
    };

    tour.enable = lib.mkOption {
      type = lib.types.bool;
      # A first-run tutor is an opinion about how a machine introduces itself,
      # not a property of the bar — hacker selects it in its desktop.
      default = false;
      description = ''
        The haus tour — a first-run tutor that walks the four moves (launch /
        navigate / resize / palette) as ONE quiet pill in the bar, advancing
        live as each move is detected. It never opens a window or steals
        focus: a fresh machine just shows a dormant "new here?" hint, clicking
        it (or `haus tour`, or ⌘Space → tour) starts the lap, right-click
        hides it forever. Detection reuses signals haus already fires (the
        leader-mode scripts) — no key logging, no Accessibility.

        Needs windows + bar (it silently stays out of the bar without them);
        the ⌘Space step is dropped when pounce is off. Progress lives in
        ~/.local/state/haus — `haus tour reset` re-arms a finished tour.
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
                  right keys on a machine that moved `keys.palette` or `keys.leader`.
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
                  The existing haus signal that completes this step: entering launch,
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
        hacker tour unchanged; supplying a list replaces it, so a shared desktop
        can teach its own workflow without shipping scripts or reaching outside the
        `haus.*` option surface.

        Detection reuses signals haus already emits. `launch`, `workspace`,
        `navigate` and `resize` need windows; `palette` needs Pounce and its palette
        binding. The module warns when a chosen detector's room is disabled.

        Authoring a tour is also the ONLY way to have one without windows: the
        built-in lap is three leader moves plus the palette, so `tour.enable` on a
        machine with `windows.enable = false` draws nothing at all.
        `desktops/everyday.nix` is the worked example — one step, the launcher.
      '';
    };

    # ---- the open form ---------------------------------------------------------
    bar.widgets = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule widgetModule);
      default = { };
      example = {
        backup = {
          command = "/etc/haus/backup-status.sh";
          interval = 300;
          icon = "󰁯";
          placement = "right";
          permissions = [ "full-disk-access" ];
        };
      };
      description = ''
        Every pill on the bar, including the bundled ones — the open form of
        `haus.bar.items`, and the only way to add a pill haus does not ship.

        A widget is one script, run on a timer, whose output is the pill's
        label. Nothing else is required:

          haus.bar.widgets.backup = {
            command = "/etc/haus/backup-status.sh";
            interval = 300;
            icon = "󰁯";
          };

        The sixteen bundled pills are already declared here, so
        `haus.bar.widgets.clock`, `.media`, `.agents` and the rest exist on
        every machine and can be retuned by name — `interval` and `placement`
        are the two fields that mean something on all of them:

          haus.bar.widgets.weather.interval = 1800;   # ask half as often
          haus.bar.widgets.cpu.placement = "left";    # only on the bottom bar

        A bundled widget's `command` is haus's own plugin and is read-only —
        setting one is refused by name rather than silently ignored, because a
        pill whose script you replaced but whose dropdown, click gestures and
        colour rules still belong to haus is not a pill either of us can
        reason about. Write your own widget under a new name instead.

        `haus.bar.items.<name>` is sugar for `haus.bar.widgets.<name>.enable`
        and `haus.bar.bottom.items.<name>` for `.placement`; both keep working
        exactly as they did, and either spelling may be used. Setting the same
        pill both ways is not an error — the open form is the more specific of
        the two and simply wins, so `haus.bar.items.cpu = false` alongside
        `haus.bar.widgets.cpu.enable = true` draws the pill.

        `permissions` is a DECLARATION, not a grant: it says what macOS will
        ask your widget for, so a widget can be read for what it reaches for
        before it is switched on. Nothing here requests anything, and a widget
        that lies about it merely describes itself badly.
      '';
    };

    bar.items = lib.mkOption {
      type = lib.types.submodule {
        options = lib.mapAttrs (_: mkItem) switchable;
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

          haus.bar.items = {
            weather = false;   # drop a default-on core pill
            cpu = true;        # add an off-by-default readout
            caffeinate = true; # add the keep-awake controller
          };

        A pill set false is never created (its update script doesn't run either).
        The focus (Do-Not-Disturb) pill is separate — it rides
        haus.focus.enable, not this set. It can still be moved to the second bar
        with `haus.bar.bottom.items.focus`.

        This is the MENU BAR's set, and it is one group: the movable pills all
        sit on the right, because its left is the workspace pills, the front app
        and the leader picker, and its center is kept clear — that is the one
        span a MacBook's notch covers when the bar is at the top, which is where
        it is by default. `haus.bar.bottom.items` mirrors these pills
        for the optional second bar, also accepts `focus`, and takes a side
        (`"left"` / `"center"` / `"right"`) rather than a bare bool; a pill named
        there moves down rather than being drawn twice.
      '';
    };

    bar.bottom.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Draw a SECOND bar along the bottom of the screen, at the same time as
        the menu bar one. `haus.bar.bottom.items` picks what goes on it and
        which of its three groups — left, center, right — each pill lands in; an
        empty set draws an empty strip, which the module warns about.

        SketchyBar has no two-bars-in-one-process mode — an instance is named
        after `basename(argv[0])` and keys both its lock file and its mach
        service on that name — so this is a second launchd agent running the
        SAME binary under a second name, `bar-bottom`. That name is also the
        CLI for it: `bar-bottom --set cpu label=…` talks to the bottom bar the
        way `sketchybar --set` talks to the menu bar one.

        Two things macOS does not do for you here. It reserves the top strip of
        every display for the menu bar but reserves NOTHING at the bottom, so
        windows would sit under this bar: windows carves the room out of its
        outer-bottom gap whenever this is on (with `haus.windows.enable = false`,
        nothing reserves it and your windows will run underneath). And the Dock,
        if you keep it at the bottom, shares that edge — move it to a side, or
        leave it hidden.
      '';
    };

    bar.bottom.items = lib.mkOption {
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
        bar and not on the menu bar, whatever `haus.bar.items` says about it —
        so there is one switch per pill per bar and never two copies of the
        same readout.

        Each value is `false` (not on this bar), one of `"left"`, `"center"`,
        `"right"` — the bar's three groups — or `true`, which is `"right"`:

          haus.bar.bottom.items = {
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
        `wifi`) plus the `haus.bar.items` extras (`cpu`, `memory`, `volume`,
        `calendar`, `caffeinate`, `agents`, `aiUsage`, `elgato`, `harvest`), plus
        the Focus pill when `haus.focus.enable` is on. The whole left side
        (workspace pills, front app, the leader picker) and the tour stay on the
        menu bar.

        Needs `haus.bar.bottom.enable`; without it nothing here is drawn.
      '';
    };
  };
}

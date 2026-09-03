# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# core's options — macOS defaults, fonts, Homebrew policy, and the two
# accessibility keys that actually apply on macOS 26.
{ lib, config, ... }:

let
  contrib = import ../lib/contrib.nix { inherit lib; };

  # §5.12's designation table — the same "read the fact, don't retype it" shape
  # the restart map already has. This file uses it for two things: the list of
  # keys `haus.accessibility` is allowed to expose (the `effective` class, and
  # nothing else), and the REACHABILITY paragraph every one of those options
  # carries, which is generated from the domain's entry rather than pasted.
  # An option can therefore not describe a reachability it doesn't have.
  reachability = import ../lib/reachability.nix;
  a11yDomain = "com.apple.universalaccess";
  a11yEntry = reachability.${a11yDomain};
  # Two classes may back an option, and the difference between them is about the
  # ORACLE, not about how sure we are: `effective` was confirmed by NSWorkspace
  # and can be re-confirmed on your Mac, `by-eye` was confirmed by a person on
  # real hardware and cannot be re-confirmed anywhere, because no API reports it.
  # Both are measured; only one is re-checkable. `mkA11y` says which in the
  # option's own description rather than flattening them here.
  a11yOptionClasses = [
    "effective"
    "by-eye"
  ];
  a11yEffectiveKeys = lib.attrNames (
    lib.filterAttrs (_: e: builtins.elem e a11yOptionClasses) a11yEntry.keys
  );

  # One table for the enum and for the path core/default.nix writes — see
  # alert-sounds.nix, the same shape hot-corners.nix uses.
  alertSoundNames = import ./alert-sounds.nix;
  alertSoundList = "  ${lib.concatStringsSep "  " alertSoundNames}\n";

  # ---- the logout note (§5.6's last blocker) ---------------------------------
  # `haus.lock.login.*` and `haus.security.guestAccount` write
  # com.apple.loginwindow, which macOS reads once when your session is created.
  # The process that would reread it is `loginwindow` itself, so the only
  # "restart" available is the one that ends your session — which is why haus
  # never fires it, and why this group sat unbuilt while the wait could only be
  # discovered AFTER a rebuild.
  #
  # ../lib/login-map.nix is the third table in the family (../lib/reachability.nix
  # says whether a write can land, ../lib/restart-map.nix says what makes it
  # felt, this says what to tell someone when the answer is "a logout"). It reads
  # the `logout` verb straight out of the restart map, so the sentence below and
  # the announcement core renders into the built activation script cannot
  # disagree: there is one fact and three renderings of it.
  loginMap = import ../lib/login-map.nix { inherit lib; };
  loginWindowDomain = "com.apple.loginwindow";
  loginWindowKeys = import ./loginwindow-keys.nix;

  # Every boolean option on that domain has the same shape, so the only per-option
  # content is prose and which plist key it is for. Naming the key here is what
  # makes ./loginwindow-keys.nix checkable in BOTH directions — an option for a
  # key the table lacks is refused right here, and a table entry with no option
  # is refused in ./default.nix, where the write is built by walking it.
  #
  # `haus.lock.login.message` does not use this: it is the domain's one string
  # key, and it interpolates `loginMap.note` itself.
  mkLoginWindow =
    {
      key,
      description,
    }:
    if !(loginWindowKeys ? ${key}) then
      throw ''
        haus: an option declares the plist key `${key}`, which
        ./loginwindow-keys.nix does not carry — so nothing would ever write it.

        That table is what ./default.nix walks to build the
        system.defaults.loginwindow block. Add the key there, with the option's
        path under `haus`, and the write follows.
      ''
    else
      lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = true;
        description = ''
          ${description}

          null (the default) writes nothing at all, which is not the same as
          "off" — and on this domain that matters more than most, because
          several of these keys are ON out of the box. Turning an option back to
          null STOPS writing rather than restoring: macOS keeps no memory of
          what the value was before haus set it.

          ${loginMap.note loginWindowDomain}
        '';
      };

  hotCornerActions = import ./hot-corners.nix;
  hotCornerNames = map (a: a.name) hotCornerActions;
  # The value list in the description comes from the same table the enum does,
  # so a new action is one edit and the docs can't describe a value the option
  # rejects. Padded to the longest name so the labels line up in the reference
  # page's <pre> block, the same shape displays.uiScale uses.
  hotCornerWidth = lib.foldl' (m: a: lib.max m (lib.stringLength a.name)) 0 hotCornerActions;
  hotCornerList = lib.concatMapStrings (
    a: "  ${lib.fixedWidthString hotCornerWidth " " a.name}  ${a.label}\n"
  ) hotCornerActions;

  mkHotCorner =
    corner:
    lib.mkOption {
      type = lib.types.nullOr (lib.types.enum hotCornerNames);
      default = null;
      example = "mission-control";
      description = ''
        What happens when the pointer reaches the ${corner} corner of the main
        display.

        ```
        ${hotCornerList}```

        null (the default) writes nothing at all, which is not the same as
        "disabled": corners are a setting people have usually already made by
        hand, and a desktop that names one it doesn't care about would silently
        erase it. Use `"disabled"` to explicitly claim a corner and make it inert.

        Setting a corner also clears its MODIFIER key. macOS stores "hold ⌘ for
        this corner" separately (`wvous-*-modifier`), and a leftover modifier from
        an earlier setup makes a corner you just declared look broken —
        nothing happens, because you weren't holding the key nobody told you
        about. Corners left at null keep whatever modifier they have.

        Worth knowing if you also run tiling: `mission-control` and `desktop` are
        macOS's own window and Space management, which the tiler replaces. They still
        work, they just show you a view of the windows the tiler is arranging.
      '';
    };
in

{
  options.haus = {
    # ---- core's extension point: the manual-click deck ------------------------
    # See ../lib/contrib.nix for the contract. Core is the RECEIVER: it renders
    # `haus permissions` (the wizard) and doctor's Permissions section from
    # whatever rooms wrote here, and knows nothing about any particular grant.
    #
    # Why a registry and not a hardcoded list in haus.sh: the list is a property
    # of the ROOMS this machine turned on, not of haus. A machine with no
    # launcher has nothing to say about pounce's Accessibility grant, and a
    # hardcoded deck would say it anyway — which is the exact failure mode the
    # wizard exists to remove, since a card you cannot act on trains people to
    # skip the ones they can.     # skip. On `blank` only core's own three are in the deck, each gated so
    # that a machine with nothing wrong shows none of them.
    #
    # Scope, decided deliberately: this is EVERY manual click a fresh machine
    # needs, not only the TCC grants. A logout macOS is waiting for and a theme
    # port that needs a click in an app's own preferences cost the same thing —
    # a person's attention, once, on a machine they just built — and splitting
    # them across three commands is why they got missed. What it must never
    # grow is anything haus can do ITSELF: if a rebuild can write it, it is a
    # setting and belongs in a room, not on a card.
    _contrib.permissions = contrib.mkExtensionRegistry {
      description = ''
        One manual step a fresh machine needs, contributed by the room that
        knows why. `haus permissions` walks the deck; `haus doctor` reports it
        without touching anything.
      '';
      options = {
        title = lib.mkOption {
          type = lib.types.str;
          description = "The card's heading. Lead with the grant or step, then the app: \"Accessibility — pounce\".";
        };

        order = lib.mkOption {
          type = lib.types.int;
          default = 50;
          description = ''
            Where the card sits in the deck, low first. Reserve the twenties for
            steps that make LATER cards easier — Full Disk Access on the running
            terminal is 10, because granting it is what lets the wizard read the
            system TCC database and confirm the rest by measurement instead of
            asking.
          '';
        };

        why = lib.mkOption {
          type = lib.types.str;
          description = ''
            One or two sentences: what this machine does with the grant. Written
            for somebody who has never heard of the room — "pounce types your
            clipboard into the app you were in" beats "pounce needs AX".
          '';
        };

        cost = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            What actually breaks without it, in the user's terms. Empty when the
            answer is simply "the feature is absent". This is the half that earns
            a skip: a card that cannot say what it costs is a card nobody should
            feel bad about skipping.
          '';
        };

        detail = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Shell whose stdout is printed under `why`, one indented line each.
            For the specifics only this Mac knows: which apps are affected,
            which entries are missing. A card whose subject is a LIST needs
            this — the deck is rendered at build time and cannot name at build
            time what only exists at runtime.
          '';
        };

        applies = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Shell, exit 0 = this card is relevant on THIS Mac right now. For the
            facts a build cannot know: the macOS version, whether an optional
            binary landed, whether anything is actually queued. `null` = always.
          '';
        };

        check = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Shell, exit 0 = already done. `null` means macOS exposes no way to
            ask, and the card can then only ever be taken on the user's word —
            which the wizard says out loud rather than drawing a green tick it
            has not earned. It must never PROMPT: a check that asks is a check
            that fires a permission dialog during `haus doctor`.
          '';
        };

        prompt = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Shell that makes macOS ASK — the real system dialog, so the whole
            grant is one click and no trip to System Settings. Only a handful of
            services have such an API (Accessibility does; Full Disk Access does
            not), so this is usually `null` and `pane` carries the card.
          '';
        };

        promptLabel = lib.mkOption {
          type = lib.types.str;
          default = "Ask macOS now";
          description = "The wizard's button text for `prompt`.";
        };

        pane = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            The exact System Settings pane, as an `x-apple.systempreferences:`
            URL. Deep-link the pane that grants THIS thing, never the top of
            Privacy & Security — a permission you cannot find is the same as a
            permission you do not have.
          '';
        };

        steps = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            The clicks, once the pane is open, when they are not obvious. One
            short imperative per entry. Skip it when the pane lands on a single
            toggle with the app already listed.
          '';
        };
      };
    };

    # ---- the background-jobs deck -------------------------------------------
    # One launchd job haus installs, contributed by the room that owns it.
    # `haus services` draws the table; `haus doctor` reports only what wants
    # attention. Same shape and same argument as the permissions deck above:
    # doctor can never fall behind a room that grew a job, and a rollback takes
    # a room's jobs with the room.
    #
    # The KEY is the launchd attribute name — `launchd.user.agents.<key>` or
    # `launchd.daemons.<key>` — and that is load-bearing rather than a
    # convention. It is what core looks the job up BY: everything mechanical
    # about a job (its label, where it logs, whether it is meant to be running
    # right now) is read back out of `config.launchd` at render time instead of
    # being copied here, so an entry cannot drift from the plist it describes
    # and a job behind a sub-room condition follows its own `lib.mkIf` for free
    # — five of them do (`bar-bottom`, `focus-auto`, `focus-watcher`,
    # `haus-agent-awake`, `haus-lidawake`), and a hand-copied entry would have
    # had to repeat every one of those gates or report a job that isn't there.
    #
    # Which makes this deck the exact opposite of the permissions one in what it
    # carries: cards there are almost entirely prose because macOS exposes no
    # facts, and entries here are almost entirely prose because launchd exposes
    # all of them. Write the half a person needs and nothing launchd already
    # knows.
    #
    # Reading `config.launchd` is not the `config.haus.<room>.*` read core is
    # forbidden: that rule is about one room reaching into another room's option
    # surface, and `launchd` is nix-darwin's own shared namespace — the same
    # direction rooms already contribute Homebrew casks in.
    _contrib.services = contrib.mkExtensionRegistry {
      description = ''
        One launchd job this machine runs, contributed by the room that owns
        it. Keyed by the launchd attribute name, so core can read the label,
        the log and the liveness class straight off `config.launchd`.
      '';
      options = {
        domain = lib.mkOption {
          type = lib.types.enum [
            "user"
            "system"
          ];
          default = "user";
          description = ''
            Which half of `config.launchd` declares it: `user` for
            `launchd.user.agents.<key>` (an agent in your login session),
            `system` for `launchd.daemons.<key>` (a root daemon). It is the
            other half of the lookup key, and it is also what a probe needs —
            the two live in different launchd domains (`gui/<uid>/` and
            `system/`) and a job asked for in the wrong one simply is not found.
          '';
        };

        title = lib.mkOption {
          type = lib.types.str;
          description = ''
            The job's heading. Lead with what it IS to a person, then the
            thing: "The tiler — AeroSpace". Never the launchd label, which the
            table already carries.
          '';
        };

        why = lib.mkOption {
          type = lib.types.str;
          description = ''
            One or two sentences: what this job does for the machine while
            nobody is looking. Written for somebody who has never heard of the
            room — "keeps your windows tiled and answers the leader key" beats
            "the AeroSpace agent".
          '';
        };

        cost = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            What actually breaks when it is dead, in the user's terms. Empty
            when the answer is simply "the feature is absent". This is the half
            that makes a red line worth reading: a job that cannot say what its
            death costs is one nobody should be woken up for.
          '';
        };

        order = lib.mkOption {
          type = lib.types.int;
          default = 50;
          description = ''
            Where the job sits in the table, low first. Reserve the low
            twenties for the ones a person notices missing within seconds — the
            tiler, the bar, the palette — so a broken desktop reads top-down.
          '';
        };
      };
    };

    # ---- accessibility ----
    # ../lib/reachability.nix's MEASURED classes, one option per key, and
    # deliberately NOTHING else: these are the keys in com.apple.universalaccess
    # somebody has watched actually take effect on macOS 26 — never a plist
    # read-back, which is the distinction the whole area turns on
    # (com.apple.Accessibility accepts writes and changes nothing, and
    # universalaccess's own FontSizeCategory writes without ever notifying a
    # running app). Everything else in that domain stays a System Settings job
    # until it's been measured the same way. The table GENERATES this surface
    # rather than being checked against it — `lib.genAttrs` over those keys — so
    # the two cannot disagree, in either direction: a key promoted with no
    # description here fails at eval saying so, and a description for a key the
    # table doesn't back is refused the same way. The one thing left by hand is
    # the prose, which is the one thing a table can't hold.
    #
    # "Measured" is TWO classes since 2026-08-14, and the split is about the
    # oracle rather than about confidence: `effective` was confirmed by
    # NSWorkspace and can be re-confirmed on your Mac, `by-eye` was confirmed by
    # a person on real hardware and can't be re-confirmed anywhere, because no
    # API reports it. Both back options; each option says which it has.
    #
    # It grew two → four → seven on purpose, and the reason is a safety one
    # rather than a completeness one. `reduceMotion` and `reduceTransparency`
    # are nix-darwin-TYPED, so before this the documented way to set them was
    # `system.defaults.universalaccess.*` — the unguarded route that aborts
    # activation partway through on any machine whose rebuilding app lacks Full
    # Disk Access. Every key that works now has a guarded option, so reaching for
    # the hazardous form is never the only way to say what you meant, and
    # `haus rebuild` can refuse it outright (see modules/core/haus.sh's guard).
    accessibility =
      let
        mkA11y =
          key: desc:
          let
            # Type and class both come from the table, so neither can be
            # contradicted here. Absent from `keyTypes` means bool, which is what
            # this domain mostly is; `mouseDriverCursorSize` is the exception.
            spec = a11yEntry.keyTypes.${key} or { type = "bool"; };
            isFloat = spec.type or "bool" == "float";
            byEye = a11yEntry.keys.${key} == "by-eye";
          in
          lib.mkOption {
            type =
              if isFloat then
                lib.types.nullOr (lib.types.numbers.between spec.range.min spec.range.max)
              else
                lib.types.nullOr lib.types.bool;
            default = null;
            example = if isFloat then spec.range.max else true;
            description = ''
              ${desc}

              null (the default) leaves whatever you have alone — this is a
              personal setting, so haus never picks a value for you.
              ${
                # Supplies the blank line before REACHABILITY whether or not it
                # has anything to say, so the four options that predate `by-eye`
                # keep byte-identical descriptions in the generated docs.
                lib.optionalString byEye ''

                  HOW THIS ONE WAS VERIFIED — by a person looking at the screen on
                  real hardware (macOS 26.6.1, 2026-08-14), because no API reports
                  it: `NSWorkspace` exposes no pointer size and no zoom state, so
                  `hausax` cannot read it back and `haus diff` will tell you it
                  compared the plist and nothing more. haus's other
                  accessibility options are checked against macOS's own answer on
                  YOUR Mac; this one carries evidence from one Mac. That is a real
                  difference and it is worth knowing which kind you are getting —
                  it is written here rather than in a changelog because the option
                  is where you will be standing when it matters.

                  NEEDS A DAEMON RESTART, which the rebuild does for you: the write
                  alone changes nothing on screen until `universalaccessd`
                  restarts, which is exactly why this key spent three weeks
                  looking dead. `haus rebuild` kills it whenever this option
                  family is set, so you should never meet the stale state; set the
                  key by hand with `defaults write` and you will, with
                  `killall universalaccessd` as the fix.
                ''
              }
              REACHABILITY — `${a11yDomain}` is TCC-protected, and this is
              the one property in the whole option surface that can differ
              between two machines running byte-identical config, so it is worth
              reading once. The write lands only when the app that runs the
              rebuild holds Full Disk Access (System Settings ▸ Privacy &
              Security ▸ Full Disk Access; on macOS 26 a stale grant often needs
              removing and re-adding with (+), then restarting the terminal).
              The grant follows the APP, not you and not root — so an
              agent-driven rebuild in a pane of a terminal that has it works
              fine, and the same agent under a different app does not.

              Without the grant haus warns and carries on: you lose this
              setting and nothing else. That containment is the whole reason
              `${a11yDomain}` has options here at all — written the
              other way, through `system.defaults.universalaccess.*`, a missing
              grant aborts the rest of activation and takes every background
              service haus installs with it.

              `haus plan` says up front when a rebuild needs the grant, and
              `haus doctor`'s Permissions section says whether this app has it.
            '';
          };
        # Prose only — the key names are the table's, above. Both directions are
        # errors on purpose: an `effective` key with nothing written about it is
        # an option nobody could use, and prose for a key the table doesn't back
        # is a description of a setting that would never be written.
        descriptions = {
          increaseContrast = ''
            macOS's "Increase contrast" — stronger borders and reduced use of
            colour alone to convey state, across native apps. This is the
            system-level companion to a high-contrast haus theme: the theme
            restyles the tools haus colours, this reaches everything else.
          '';
          differentiateWithoutColor = ''
            macOS's "Differentiate without colour" — native UI adds shapes and
            text where it would otherwise rely on hue alone. The setting to pair
            with a desktop built for colour-blind readability.
          '';
          reduceTransparency = ''
            macOS's "Reduce transparency" — the menu bar, Control Center, sheets
            and sidebars stop sampling what is behind them and go opaque. The
            setting to reach for if Liquid Glass costs you more legibility than
            it buys, and it pairs naturally with `increaseContrast`.

            Worth knowing if you run the bar: bar paints its own background, so
            its pills look the same either way — what changes is the macOS menu
            bar band behind them, which stops being translucent.
          '';
          reduceMotion = ''
            macOS's "Reduce motion" — Spaces cross-fade instead of sliding,
            Mission Control and the Dock drop their zoom animations, and window
            minimise/restore is stripped back.

            BIGGER THAN IT LOOKS, which is why it is here rather than inside
            `haus.animations`. This is the single flag every browser maps to the
            `prefers-reduced-motion: reduce` CSS media query, through
            `NSWorkspace.accessibilityDisplayShouldReduceMotion` — `hausax` reads
            that exact property, so `hausax | jq .reduceMotion` is how you check
            it landed. Turning it on rewrites the web: mostly for the better,
            except on sites whose scroll-reveal animation is what makes the
            content visible in the first place, which then never appears at all.

            If what you want is a snappier Dock and nothing else,
            `haus.animations = "fast"` is five plain timing keys in two ordinary
            domains, moves no accessibility flag, and needs no TCC grant.
          '';
          mouseDriverCursorSize = ''
            How big the mouse pointer is — 1.0 normal, 4.0 the biggest.
            That range is macOS's own, and the scale is linear: 2.0 is twice
            the normal pointer, 4.0 is the largest System Settings offers.

            The one accessibility key here that is useful with no accessibility
            need at all: on a 5K display, or from across a desk, or in a
            screen recording someone else has to follow, the default pointer is
            simply too small to find. Set it to 1.5 and you keep noticing you
            can see it.

            Deliberately NOT wired to `haus.ui.scale`, which would be the
            obvious thing and is the wrong thing. `ui.scale` is the foundation
            every machine gets; this domain needs Full Disk Access. Deriving
            one from the other would make `ui.scale = 1.4` start warning about
            a TCC grant on machines that never asked for a bigger pointer, for
            a write that would then be skipped. Reach for this key when you
            want it — it sharpens a large-text desktop, it does not underpin
            one.
          '';
          closeViewScrollWheelToggle = ''
            Hold ⌃ (Control) and scroll to magnify the whole display.
            macOS calls it "Use scroll gesture with modifier keys to zoom";
            scroll the other way to come back.

            The fastest zoom on the Mac and the one people forget exists. Worth
            having on a machine you demo, present or pair from, where the
            alternative is asking everyone to lean in.
          '';
          closeViewZoomFollowsFocus = ''
            Keep a zoomed display on whatever has keyboard focus.
            ⇥ into a field outside the magnified area and the view goes to it —
            KEYBOARD focus specifically, not the pointer.

            Needs a zoom to follow, so it does nothing on its own: pair it with
            `closeViewScrollWheelToggle` (or turn on Zoom in System Settings ▸
            Accessibility). nix-darwin's own option says the same, and it is the
            first thing to check if this appears to do nothing.

            Expect it to SNAP rather than glide — the view jumps to the focused
            control in one step. That is the feature behaving, not a rendering
            fault, and it is the first thing anyone reports as one. Note also
            that pushing the POINTER at a screen edge pans the zoomed view
            whether or not this is set: that behaviour is not this option, which
            matters if you are trying to tell whether it took.
          '';
        };

        undescribed = builtins.filter (k: !(descriptions ? ${k})) a11yEffectiveKeys;
        unbacked = builtins.filter (k: !(builtins.elem k a11yEffectiveKeys)) (lib.attrNames descriptions);
      in
      if undescribed != [ ] then
        throw ''
          haus.accessibility: ../lib/reachability.nix marks ${lib.concatStringsSep ", " undescribed}
          as ${lib.concatStringsSep " or " (map (c: "`${c}`") a11yOptionClasses)} in ${a11yDomain},
          but this file has no description for it.
          An option surface is generated from that table — write the prose here and
          the option appears. (If the key is not actually measured effective, it
          does not belong in the table.)
        ''
      else if unbacked != [ ] then
        throw ''
          haus.accessibility: this file describes ${lib.concatStringsSep ", " unbacked},
          which ../lib/reachability.nix does not mark
          ${lib.concatStringsSep " or " (map (c: "`${c}`") a11yOptionClasses)} in ${a11yDomain}.
          Only measured keys get options — everything else in that domain either
          persists unmeasured or writes and lies, and an option is not the place to
          find out which. Measure it first (an eyeball on real hardware counts, and
          is what `by-eye` is for), then promote it in the table.
        ''
      else
        lib.genAttrs a11yEffectiveKeys (k: mkA11y k descriptions.${k});

    # ---- animations ----
    # macOS's own motion: five keys that are just numbers and switches in a
    # plist. Deliberately NOT `com.apple.universalaccess reduceMotion`, which is
    # the setting anyone reaches for first and is a much wider blast radius than
    # it looks — the description says why, because that reasoning is the whole
    # point of the group existing separately. That switch now HAS an option
    # (`haus.accessibility.reduceMotion`, §5.12), which changes nothing here:
    # the point was never that it should be unreachable, it was that these five
    # timing keys are not it, and reaching one by asking for the other is the
    # mistake worth making impossible.
    #
    # Default "system" = write nothing, the same policy every other curated
    # macOS settings group follows ("a group is a place to make an opinion
    # available, not to impose one; a desktop is where an opinion belongs").
    # It was briefly drafted the other way
    # round, defaulting to "fast", and the argument against that is the one hot
    # corners already made: these keys land on machines that have been running
    # for years, macOS keeps no memory of a prior value, and a desktop that speeds
    # up a Dock nobody asked it about can't put it back. Opting in is one line.
    animations = lib.mkOption {
      type = lib.types.enum [
        "fast"
        "system"
      ];
      default = "system";
      example = "fast";
      description = ''
        How much motion macOS spends on its own Dock and windows — how long
        three animations run, and two it plays at all.

        `"system"` (the default) writes NOTHING — not the macOS values, nothing
        at all — so whatever your Dock does today, it keeps doing. Same policy
        as `haus.hotCorners`: haus doesn't overwrite a setting you didn't
        ask it about.

        `"fast"` writes five keys, all `mkDefault`, so any one of them can be
        overridden by name in your host file:

        ```
          com.apple.dock  autohide-time-modifier         0.15   Dock slide
          com.apple.dock  expose-animation-duration      0.1    Mission Control
          com.apple.dock  launchanim                     false  the bouncing icon
          com.apple.dock  mineffect                      scale  minimise (not genie)
          NSGlobalDomain  NSAutomaticWindowAnimationsEnabled  false  window open/close
        ```

        GOING BACK IS NOT AUTOMATIC, which is the one thing about this group
        that can surprise you and the reason it isn't on by default. Setting
        `"system"` again means STOP WRITING, not RESTORE: a `defaults` write is
        sticky and macOS keeps no memory of what was there before, so once
        you've rebuilt on `"fast"`, the five keys keep haus's numbers.
        Undoing it means naming the values you want back in your host file
        (they're `mkDefault`, so a plain value wins), or a `defaults delete`.
        Worth knowing before you try `"fast"` on a Dock you tuned by hand.

        WHY THIS ISN'T "REDUCE MOTION". macOS's accessibility switch of that
        name (`com.apple.universalaccess reduceMotion`) would cover all of this
        and more — but it is also the single flag every browser maps to the
        `prefers-reduced-motion: reduce` CSS media query, via
        `NSWorkspace.accessibilityDisplayShouldReduceMotion`. Turning it on
        rewrites the web: mostly for the better, except on sites whose
        scroll-reveal animation is what sets the content visible in the first
        place, which then never appears at all. These five keys are in two
        entirely different domains and move no accessibility flag — `hausax`
        reads that exact `NSWorkspace` property, so `hausax | jq .reduceMotion`
        stays `false` with this set to `"fast"` (on a machine that hasn't also
        set `haus.accessibility.reduceMotion`, which is the option that DOES move
        it) — that's the whole reason this
        group exists as five curated keys instead of one switch. If you DO want
        the accessibility switch, it is `haus.accessibility.reduceMotion`: a
        separate option, in a TCC-protected domain, with that blast radius spelled
        out on it. Setting both is coherent and neither implies the other.

        WHEN YOU'LL FEEL IT. The four Dock keys are live the moment activation
        finishes — nix-darwin restarts the Dock whenever anything in its domain
        is written, and haus always writes `autohide`. The NSGlobalDomain
        one is read by each app AT LAUNCH, so apps you already have open keep
        animating their windows until you relaunch them; `activateSettings`
        can't reach back into a running `NSApplication`.

        These are timings, not a state haus can prove from a plist — unlike
        the `haus.accessibility` keys, there's no oracle for "did the Dock
        slide faster". They're felt, not measured. The one measurable claim
        here is the negative one above.
      '';
    };

    # ---- fonts ----
    # Honest scope: this is haus's type FAMILY — Ghostty's, and (since the
    # bar stopped hardcoding one of its own) bar's. `size` is the terminal's
    # alone: the bar's sizes come from ui.scale against the menu-bar band's
    # ceiling, because its pill geometry is built around them (../lib/bar.nix).
    #
    # `sans` below is the proportional half, and it is no longer one label's
    # fallback: it reaches the clock pill AND pounce, perch and trill, each
    # through the config file its own room already generates. The asymmetry
    # that remains is what each family is FOR — `mono` is what this machine is
    # drawn in, `sans` is what it is written in — and the package arms differ
    # for the reason ../lib/sans-font.nix's header gives: the default family is
    # macOS's own, so the third answer there is null rather than a package.
    fonts.mono = {
      name = lib.mkOption {
        type = lib.types.str;
        # NOT carved out into the desktop, though the inventory lists it as an
        # opinion. Which patched family is taste; being a PATCHED family is a
        # requirement — starship, lsd, yazi and half the bar draw glyphs a stock
        # font renders as tofu (see below). A neutral "Menlo" would make the
        # bare terminal room actively broken rather than merely unopinionated,
        # which is the opposite of "a neutral, useful configuration when
        # enabled". So the layer keeps supplying one that works, and a desktop
        # that wants a different family names it and its package together.
        default = "JetBrainsMono Nerd Font Mono";
        example = "Berkeley Mono";
        description = ''
          haus's type family, as Ghostty's `font-family` names it.

          It reaches the terminal AND the menu bar: every pill label and icon
          the bar draws is in this family, at sizes of its own (see
          `haus.ui.scale`). The workspace-logo glyphs are the one exception
          — those are sketchybar-app-font, which the bar installs itself.

          This should be a NERD FONT patched build: starship's prompt, lsd's
          icons, yazi previews and half the bar's icons draw with glyphs a stock
          font renders as tofu. If you change this, set `package` (or
          `packageName`) too — haus can only install a font it's been given,
          and it warns when you name a family without one.

          The name is taken verbatim, so a "… Nerd Font Mono" family is drawn in
          the bar as well: the bar mixes icon glyphs into its labels, which is
          the same reason the terminal wants a patched font.
        '';
      };
      baseSize = lib.mkOption {
        type = lib.types.ints.positive;
        default = 13;
        example = 19;
        description = ''
          The terminal-font baseline, before `haus.ui.scale` multiplies it.
          The neutral room uses 13pt; hacker selects 19pt in its desktop.

          This exists so a desktop can carry that tuned baseline WITHOUT
          breaking the scale relationship. Setting `size` directly pins an
          absolute number, which would make `haus.ui.scale` (and
          `haus.appearance.largePrint`, built on it) stop moving the terminal font at
          all — a silent regression, since everything else would still grow.
          Say the baseline here; say the exception with `size`.
        '';
      };
      size = lib.mkOption {
        type = lib.types.ints.positive;
        default = builtins.floor (config.haus.fonts.mono.baseSize * config.haus.ui.scale + 0.5);
        # literalMD, not literalExpression: this SENTENCE describes the default,
        # it isn't Nix you could paste anywhere (`round` is not a builtin). The
        # distinction is load-bearing — host-template.jq copies a
        # literalExpression straight into the generated host file as the
        # option's value, and CI evaluates that file with every default
        # uncommented. Prose ⇒ literalMD. See haus.developer.languages in
        # modules/options.nix, which learned this the same way.
        defaultText = lib.literalMD "fonts.mono.baseSize, scaled by haus.ui.scale and rounded";
        example = 24;
        description = ''
          Terminal font size in points. The single most useful knob for a
          larger-text machine, since it moves everything haus actually
          lives in.

          hacker's 19pt baseline exists for a reason worth knowing: the Ghostty window is
          tiled to a fixed pixel height by windows, and sizes that don't divide
          that height evenly used to leave a gap along its bottom edge, under
          the multiplexer's status bar. That's since been fixed properly
          (`window-padding-balance`, which splits the leftover pixels evenly
          instead of dumping them all at the bottom), so any size is safe now —
          19 is simply the tuned starting point.
        '';
      };
      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        example = lib.literalExpression "pkgs.nerd-fonts.fira-code";
        description = ''
          The package providing `name`. null (the default) installs haus's
          own JetBrains Mono Nerd Font, which is what `name` defaults to.

          Set this whenever you change `name`, or the family simply won't exist
          on the machine and Ghostty will silently fall back — haus warns if
          it spots that combination.

          A shared desktop can't set this one — it needs `pkgs`, and a data-only
          desktop has no arguments. Use `packageName` there.
        '';
      };
      packageName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "nerd-fonts.fira-code";
        description = ''
          The same thing as `package`, NAMED rather than evaluated: an
          attribute path into nixpkgs, so "nerd-fonts.fira-code" means
          `pkgs.nerd-fonts.fira-code`.

          This exists so a data-only desktop can change the font FAMILY and not
          just its size — reaching `pkgs` is precisely what that format forbids,
          which made `fonts.mono.package` unreachable to every shared file. A
          name is data; a package is code.

          Set one or the other, never both. A name that resolves to nothing, or
          to a set of packages rather than a package, fails at eval with the
          spelling to try instead.
        '';
      };
    };

    # The PROPORTIONAL family. It reaches the clock pill (when
    # `haus.bar.clock.monoFont` is false) and the three apps this layer ships
    # that draw proportional text: pounce's launcher, perch's shelf and trill's
    # banners, each through the config file haus already generates for it.
    #
    # THAT IS ALL OF IT, and the boundary is worth knowing: macOS exposes no
    # supported knob for the system UI font, so menus, Finder and Safari keep
    # drawing in SF Pro whatever this says. Ghostty, the rest of the bar and the
    # wallpaper's debug band are mono on purpose and name `fonts.mono`.
    #
    # Deliberately no `size`: nothing here sizes proportional text by name
    # (`haus.ui.scale` and `haus.launcher.scale` do), and a field with no reader
    # is drift with a default value.
    fonts.sans = {
      name = lib.mkOption {
        type = lib.types.str;
        default = ".AppleSystemUIFont";
        example = "Atkinson Hyperlegible";
        description = ''
          The proportional family this layer's own surfaces draw in: the clock
          pill's date and time (when `haus.bar.clock.monoFont` is false), and
          the text in pounce, perch and trill — the launcher and its rows, the
          notch shelf, every notification banner and all three settings
          windows.

          The default is macOS's own system UI font, whose zero has no dot and
          is easier to tell from an 8 at a glance. That legibility is the
          entire reason the clock has an opt-out, so the default is also the
          answer for almost everybody.

          Two things this does NOT do, both worth knowing before you set it.
          It does not change the system UI font — macOS has no supported knob
          for that, so menus, Finder and Safari are unmoved. And it does not
          touch monospaced text anywhere: a keycap, a timestamp, a source slug
          and a code preview stay mono, because a column that shifts is harder
          to read rather than easier.

          Name a family the machine has — macOS ships plenty, and `haus.roster`
          installs more — or one `package` / `packageName` puts there. A family
          that isn't there falls back to the system font **silently**: there is
          no tofu to see, and every surface goes on looking exactly as it did,
          so a misspelling reads as "the option does nothing". Check the
          spelling against Font Book if nothing moves.
        '';
      };

      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        example = lib.literalExpression "pkgs.atkinson-hyperlegible";
        description = ''
          The package providing `name`. null (the default) installs nothing,
          which is correct for the default family: `.AppleSystemUIFont` is
          macOS's own and is on every Mac.

          Set this whenever you set `name` to something the machine doesn't
          already have, or the family simply won't exist and every surface
          falls back to the system font — which looks exactly like the setting
          not working. Unlike `fonts.mono`, haus does NOT warn about the
          combination: naming a proportional family the Mac already has is the
          ordinary case, so the warning would fire on correct configurations.

          A shared desktop can't set this one — it needs `pkgs`, and a
          data-only desktop has no arguments. Use `packageName` there.
        '';
      };

      packageName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "atkinson-hyperlegible";
        description = ''
          The same thing as `package`, NAMED rather than evaluated: an
          attribute path into nixpkgs, so "atkinson-hyperlegible" means
          `pkgs.atkinson-hyperlegible`.

          This exists so a data-only desktop can change the proportional family
          and not just name one it hopes is installed — reaching `pkgs` is
          precisely what that format forbids.

          Set one or the other, never both. A name that resolves to nothing, or
          to a set of packages rather than a package, fails at eval with the
          spelling to try instead.
        '';
      };
    };

    homebrew = {
      adopt = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether a cask haus declares that is already sitting in
          /Applications — installed by hand, the App Store, or anything
          other than Homebrew — gets adopted into Homebrew's bookkeeping
          instead of failing activation with "there is already an App at
          …". Nothing about the app itself changes; only whether Homebrew
          considers itself the owner.

          On by default: without it, the roster's whole "declare an app,
          haus makes sure it's there" promise breaks the moment that app
          happens to already be installed some other way — which is common
          for editors, browsers and other apps most people bring with them.

          Current Homebrew (`bundle/cask.rb`) adopts every such cask
          unconditionally on its own, with no supported flag left to opt
          out — `brew bundle install --adopt` was removed, and the only
          alternative, `--force`, overwrites instead of refusing. Setting
          this to `false` is a no-op until Homebrew grows a real way back
          to "fail loudly on conflict" for `brew bundle`.
        '';
      };

      cleanup = lib.mkOption {
        type = lib.types.enum [
          "none"
          "uninstall"
          "zap"
        ];
        default = "none";
        description = ''
          How `darwin-rebuild switch` treats Homebrew casks/brews that are
          installed but NOT declared anywhere in your config.

          - "none" (default, safe): leave undeclared formulae/casks alone.
            haus never deletes apps you installed yourself.
          - "uninstall": remove undeclared formulae/casks (keeps their data).
          - "zap": remove undeclared formulae/casks AND their app data. Fully
            declarative, but a stray cask you forgot to list is deleted — with
            no backup — on the very next rebuild. Only choose this once every
            app you keep is declared (bootstrap can adopt your current casks).
        '';
      };
      autoUpdate = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Run `brew update` before activating the Homebrew step on every
          rebuild. Off by default — reproducible rebuilds shouldn't silently
          pull newer formulae. Turn on if you want brew to track upstream.
        '';
      };
      upgrade = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Upgrade outdated Homebrew packages on every rebuild. Off by default
          for the same reproducibility reason as autoUpdate.
        '';
      };
    };

    # ---- hot corners ----
    # Four screen corners, each an action, by name rather than by the integer
    # macOS actually stores. Every value defaults to null (leave alone) because
    # the corners are one of the few macOS settings almost everyone has already
    # touched — see mkHotCorner's description for why that isn't "disabled".
    hotCorners = {
      topLeft = mkHotCorner "top-left";
      topRight = mkHotCorner "top-right";
      bottomLeft = mkHotCorner "bottom-left";
      bottomRight = mkHotCorner "bottom-right";
    };

    # ---- screenshots ----
    # com.apple.screencapture, which is one of the friendliest domains on the
    # Mac: writable without any TCC grant, needs no restart (screencapture reads
    # its preferences per capture), and every key here is typed by nix-darwin.
    # Same null-means-leave-alone rule as the corners above.
    screenshots = {
      location = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "~/Pictures/Screenshots";
        description = ''
          Where ⇧⌘3 / ⇧⌘4 / ⇧⌘5 write their files. null (the default) leaves
          macOS's own choice alone, which is the Desktop.

          Absolute, or starting with `~/` — haus expands the `~` for you and
          CREATES the directory during activation. Both halves matter: macOS
          stores this string verbatim and expands nothing, and if the path does
          not exist screencapture silently falls back to the Desktop, so a
          typo'd or not-yet-created folder looks exactly like the setting having
          been ignored.
        '';
      };
      format = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "png"
            "jpg"
            "pdf"
            "tiff"
            "heic"
            "gif"
          ]
        );
        default = null;
        example = "png";
        description = ''
          The image format new screenshots are saved in. null (the default)
          leaves macOS's own choice alone, which is png.

          png is lossless and the right default for UI and text — a jpg
          screenshot of a terminal has visible ringing around every glyph. jpg
          is worth choosing only when you screenshot photographs often enough
          for the file sizes to matter.
        '';
      };
      shadow = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = false;
        description = ''
          Whether a window capture (⇧⌘4 then Space) keeps macOS's big soft drop
          shadow. null (the default) leaves macOS's own choice alone, which is
          to include it.

          false is the setting to want if screenshots go into documentation: the
          shadow is transparent padding, so it adds a wide invisible margin that
          every layout then has to fight. Holding ⌥ while you click suppresses
          it for one capture either way.
        '';
      };
      thumbnail = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = false;
        description = ''
          Whether the floating preview thumbnail appears in the bottom-right
          corner after a capture. null (the default) leaves macOS's own choice
          alone, which is to show it.

          false writes the file immediately instead of after the ~5s the
          thumbnail waits around — the setting to want if you screenshot in
          quick succession, or if you script anything that reads the file. The
          cost is losing the markup/drag affordance the thumbnail offers.

          One room answers this for you: the shelf turns the thumbnail off at
          `mkDefault` while `haus.shelf.watchScreenshots` is on, because a
          capture macOS is still holding cannot reach the shelf. Naming this
          option in your host outranks that and puts the thumbnail back.
        '';
      };
      includeDate = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = true;
        description = ''
          Whether filenames carry the date and time ("Screenshot 2026-08-03 at
          13.37.20.png") or just a counter ("Screenshot 1.png"). null (the
          default) leaves macOS's own choice alone, which is to include it.
        '';
      };
    };

    # ---- lock ----
    # §5.6's "Lock / login / screensaver" group, now BOTH halves.
    #
    # The lock half (com.apple.screensaver) was always live: no persistent
    # process reads it, so the next lock picks it up. The LOGIN half
    # (com.apple.loginwindow) was deferred for a year because it is the opposite
    # — read once when the session is created, and the process that would reread
    # it is the one that owns your session, so the "restart" is a logout. §5.6
    # refused to ship a settings group whose keys SILENTLY need one.
    #
    # ../lib/login-map.nix is what removed the word "silently": `mkLoginWindow`
    # below stamps every option in this half with the domain's paragraph, from
    # the same `logout` verb in ../lib/restart-map.nix that already makes
    # activation announce it and `haus plan` report it. One fact, rendered where
    # each audience stands, and no copy anyone can edit out of step.
    lock = {
      requirePassword = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = true;
        description = ''
          Require a password to wake this Mac from sleep or the screen saver.
          null (the default) leaves macOS's own choice alone.

          The one setting in this group worth turning on for ANY shared or
          portable machine — a family Mac, a laptop that leaves the house.
        '';
      };
      requirePasswordDelay = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.unsigned;
        default = null;
        example = 5;
        description = ''
          Seconds to wait after sleep/screen-saver starts before
          `requirePassword` actually locks the screen — macOS's "grace period".
          null (the default) leaves macOS's own choice alone.

          0 locks instantly. Has no effect while `requirePassword` is null or
          false.
        '';
      };

      # ---- the login half (com.apple.loginwindow) ----------------------------
      # What you see BEFORE a session exists: the login window itself. Nested
      # under `lock` rather than given a room of its own because it is the same
      # question — who gets into this Mac — asked one step earlier, which is how
      # §5.6 grouped it in the first place ("Lock / login / screensaver").
      login = {
        showNameField = mkLoginWindow {
          key = "SHOWFULLNAME";
          description = ''
            Ask for a username AND a password, instead of showing a list of
            user pictures to click.

            The shoulder-surfing setting: with the list, half the credential is
            already on screen for anyone who walks past. Worth true on a laptop
            that leaves the house, and it is also the only way to log into an
            account the list deliberately hides.
          '';
        };
        message = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "If found, please call +1 555 0100.";
          description = ''
            A line of text under the password field on the login window.
            null (the default) leaves whatever is there alone.

            The one genuinely useful thing to put here is how to reach you if
            the machine is lost — it is visible to somebody who cannot log in,
            which is exactly the person you want reading it. Everything else it
            gets used for (a banner, a policy notice) is a workplace thing.

            Not a security boundary: anyone who can read this can also read it
            off the disk, and it is not a lock. Empty string clears the message
            rather than leaving it alone; that is `""`, not null.

            ${loginMap.note loginWindowDomain}
          '';
        };
        hideShutDown = mkLoginWindow {
          key = "ShutDownDisabled";
          description = ''
            Remove the Shut Down button from the login window.

            For a machine that should stay up and reachable — a Mac serving
            something on the desk in the corner — where the only person pressing
            it is someone who walked past. It does not stop a long press on the
            power button, and it is not a lock: it removes the easy way, not
            every way.
          '';
        };
        hideRestart = mkLoginWindow {
          key = "RestartDisabled";
          description = ''
            Remove the Restart button from the login window. Same reasoning as
            `hideShutDown`, and normally set with it — leaving one of the two
            buttons is a curious middle ground.
          '';
        };
        hideSleep = mkLoginWindow {
          key = "SleepDisabled";
          description = ''
            Remove the Sleep button from the login window. The mildest of the
            three, and the one with a real cost on a laptop: sleeping from the
            login window is how you put a machine away that you have already
            locked.
          '';
        };
      };
    };

    # ---- menu bar & control center ----
    # §5.6's "Menu bar & Control Center" group: the clock (com.apple.menuExtraClock)
    # and which Control Center glyphs sit in the menu bar (com.apple.controlcenter).
    # Both restart via a process kill (SystemUIServer / ControlCenter — see
    # modules/lib/restart-map.nix), the same live-reload shape as Finder, not a
    # TCC-gated or logout-only domain.
    menuBar = {
      clock = {
        format = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.enum [
              "12h"
              "24h"
            ]
          );
          default = null;
          example = "24h";
          description = ''
            12-hour or 24-hour menu bar clock. null (the default) leaves
            macOS's own choice alone (region-dependent, usually 12h in the US).
          '';
        };
        showSeconds = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          example = false;
          description = ''
            Show the clock to second precision instead of minutes. null (the
            default) leaves macOS's own choice alone.
          '';
        };
        showDate = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.enum [
              "when-space-allows"
              "always"
              "never"
            ]
          );
          default = null;
          example = "always";
          description = ''
            Whether the full date appears next to the time. null (the default)
            leaves macOS's own choice alone ("when-space-allows").
          '';
        };
        showDayOfWeek = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          example = true;
          description = ''
            Show the day of the week next to the clock. null (the default)
            leaves macOS's own choice alone.
          '';
        };
        analog = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          example = false;
          description = ''
            Draw an analog clock face instead of a digital readout. null (the
            default) leaves macOS's own choice alone (digital).
          '';
        };
      };
      controlCenter = {
        batteryPercentage = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          example = true;
          description = ''
            Show the battery percentage next to its menu bar icon. null (the
            default) leaves macOS's own choice alone.
          '';
        };
        sound = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          example = true;
          description = "Whether the Sound control has a menu bar icon of its own. null (the default) leaves macOS's own choice alone.";
        };
        bluetooth = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          example = true;
          description = "Whether the Bluetooth control has a menu bar icon of its own. null (the default) leaves macOS's own choice alone.";
        };
        airdrop = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          example = false;
          description = "Whether the AirDrop control has a menu bar icon of its own. null (the default) leaves macOS's own choice alone.";
        };
        displayBrightness = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          example = true;
          description = "Whether the Screen Brightness control has a menu bar icon of its own. null (the default) leaves macOS's own choice alone.";
        };
        focus = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          example = true;
          description = "Whether the Focus control has a menu bar icon of its own. null (the default) leaves macOS's own choice alone.";
        };
        nowPlaying = lib.mkOption {
          type = lib.types.nullOr lib.types.bool;
          default = null;
          example = false;
          description = "Whether the Now Playing control has a menu bar icon of its own. null (the default) leaves macOS's own choice alone.";
        };
      };
    };

    # ---- security ----
    # §5.6's "Security posture" group, now both of the halves that are reachable
    # at all.
    #
    # The firewall half is not a plist write: nix-darwin's
    # networking.applicationFirewall runs
    # `/usr/libexec/ApplicationFirewall/socketfilterfw` directly, in its own
    # unconditional activation script, every rebuild — a live command, so no
    # restart, no logout, no TCC grant, and no entry in
    # ../lib/restart-map.nix.
    #
    # `guestAccount` is the other half, and it was deferred for exactly as long
    # as `lock`'s login half and for the same reason: com.apple.loginwindow is
    # logout-only, and the group would not ship a key that silently waits. It
    # carries ../lib/login-map.nix's paragraph now, like every other option on
    # that domain.
    #
    # REMOTE LOGIN (sshd) is still not here, and this is the deliberate gap —
    # it isn't a `defaults` key at all. It's `systemsetup -setremotelogin` /
    # `launchctl enable system/com.openssh.sshd`, which needs a guarded
    # activation step of its own (the `haus.power` shape, not the
    # `system.defaults` one), and turning a machine's SSH server on is a
    # different class of decision from the rest of this group: it opens a port
    # to the network rather than changing what a local screen shows. It also
    # needs Full Disk Access to drive `systemsetup` on macOS 26. Worth building,
    # deliberately not smuggled in behind a logout-note PR.
    security.guestAccount = mkLoginWindow {
      key = "GuestEnabled";
      description = ''
        Whether anyone can log in as "Guest" without a password — a temporary
        session macOS wipes when they log out.

        Fresh Macs ship with this ON, which is the fact worth knowing: a
        machine you never configured lets a stranger who has it in their hands
        reach a browser, a network and any file share you are connected to.
        `false` is the setting almost every personal machine wants and almost
        no one has made.

        It is also the one key in this group that is genuinely a security
        boundary rather than a papercut, so it is worth setting explicitly even
        when you believe it is already off.
      '';
    };

    security.firewall = {
      enable = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = true;
        description = ''
          The built-in application firewall. null (the default) leaves
          macOS's own choice alone (off, on a fresh install).

          The "public Wi-Fi" setting: worth true for a laptop that leaves
          home, closer to unnecessary for a desktop that never does.
        '';
      };
      blockAllIncoming = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = false;
        description = ''
          Block ALL incoming connections, including ones apps ask for (AirDrop,
          screen sharing, a dev server on your LAN). null (the default) leaves
          macOS's own choice alone. Has no effect while `enable` is null or
          false.
        '';
      };
      allowSigned = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = true;
        description = ''
          Let built-in, Apple-signed software receive incoming connections
          without asking. null (the default) leaves macOS's own choice alone.
          Has no effect while `enable` is null or false.
        '';
      };
      allowSignedApp = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = true;
        description = ''
          Let downloaded, signed third-party software receive incoming
          connections without asking. null (the default) leaves macOS's own
          choice alone. Has no effect while `enable` is null or false.
        '';
      };
      stealthMode = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = true;
        description = ''
          Don't respond to network probes (ping, closed-port connection
          attempts) at all, instead of replying "connection refused". null
          (the default) leaves macOS's own choice alone. Has no effect while
          `enable` is null or false.
        '';
      };
    };

    # ---- sound ----
    # §5.6's "Sound" group, spiked 2026-08-08 (workshop
    # `docs/macos-settings.md`). Everything here writes live: no restart,
    # no logout, no Full Disk Access. Two keys are typed by nix-darwin
    # (beep.volume, beep.feedback), two go through CustomUserPreferences, and
    # the startup chime isn't a plist at all.
    #
    # The reason `alertVolume` is 0–100 rather than the raw float upstream
    # types: macOS stores the alert volume as `e^(fraction − 1)`, so 0.5 is 31%
    # and anything at or below e⁻¹ ≈ 0.368 is silence. A desktop that exposed the
    # float would ship a number that reads like a percentage and isn't.
    sound = {
      alertVolume = lib.mkOption {
        type = lib.types.nullOr (lib.types.ints.between 0 100);
        default = null;
        example = 50;
        description = ''
          How loud the alert beep is, 0–100, exactly as the slider in System
          Settings ▸ Sound reads. null (the default) leaves macOS's own choice
          alone.

          haus converts to the exponential value macOS actually stores
          (`e^(v/100 − 1)`, with 0 meaning silence), because that key is not a
          fraction: writing the obvious `0.5` gets you 31%.

          TWO WRITERS: the volume keys and the Sound pane write this same key.
          Declaring it means every rebuild reasserts your number over anything
          you changed by hand since — which is the point of declaring it, but
          leave it null if you'd rather the slider win.
        '';
      };
      alertSound = lib.mkOption {
        type = lib.types.nullOr (lib.types.enum alertSoundNames);
        default = null;
        example = "Submarine";
        description = ''
          Which sound the alert beep plays, by name:

          ```
          ${alertSoundList}```

          null (the default) leaves macOS's own choice alone.

          An enum rather than a path on purpose. macOS stores an absolute path
          here and validates nothing, and a path that doesn't resolve does not
          fall back to the default beep — it goes SILENT (measured by ear,
          2026-08-08), while the plist still reads like a working setting.
          haus builds the path from the name and skips the write with a warning
          if that file is missing, so a macOS release retiring a sound can't
          quietly mute you.
        '';
      };
      volumeFeedback = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = true;
        description = ''
          Play a sound when the volume keys change the volume. null (the
          default) leaves macOS's own choice alone.
        '';
      };
      uiSounds = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = false;
        description = ''
          Play user-interface sound effects — the Trash whoosh, the screenshot
          shutter, the Mail whoosh. null (the default) leaves macOS's own
          choice alone.
        '';
      };
      startupChime = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = false;
        description = ''
          The chime a Mac plays at boot. null (the default) leaves it alone.

          The odd one in this group: it is firmware state (`nvram StartupMute`),
          not a preference, so it survives an OS reinstall and a wiped home
          directory — and it is the only setting here that needs the rebuild to
          run as root, which activation already does.
        '';
      };
    };

    # ---- locale ----
    # §5.6's "Locale / input sources" group, spiked 2026-08-08.
    #
    # The finding that shapes this whole block: a `defaults write` here reaches
    # NEWLY LAUNCHED processes only. An app that is already running never sees
    # it — not even through Locale.autoupdatingCurrent, the API documented to
    # track changes — unless AppleDatePreferencesChangedNotification is posted
    # afterwards. That post is a distributed notification, not a killall and
    # not a logout, which is why modules/lib/restart-map.nix grew a third verb
    # (`notify:<name>`) for this group. See core/default.nix.
    #
    # `language` is the exception no notification can rescue: which .lproj a
    # bundle loads is decided when it launches, so the UI language of an app
    # you already have open changes when you relaunch it, and the login window
    # follows at next login.
    locale = {
      language = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        default = null;
        example = [
          "de-DE"
          "en-GB"
        ];
        description = ''
          Preferred languages, best first — the order System Settings ▸ General
          ▸ Language & Region shows. null (the default) leaves macOS's own list
          alone.

          Apps use the first entry they have a translation for, so a list is a
          fallback chain, not a single choice.

          TAKES EFFECT ON RELAUNCH: an app picks its language when it starts.
          Already-open apps keep the old one until you quit and reopen them,
          and the login window follows at next login. Nothing haus can post
          changes that — it is how bundle resources load.
        '';
      };
      region = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "de_DE";
        description = ''
          The region whose formats macOS uses — dates, number separators, paper
          size, the first day of the week. An ICU locale identifier
          (`de_DE`, `en_GB`, `fr_CA`). null (the default) leaves macOS's own
          choice alone.

          This is the lever with the most reach in the group: it moves the hour
          format, the measurement system and the first weekday together. Set it
          before reaching for the individual overrides below — and note there is
          deliberately no `firstWeekday` option, because macOS's own
          `AppleFirstWeekday` key is stored and then ignored (measured; it is
          the second dict-valued key in this domain found to do that). The
          region's own answer is the only one that applies.
        '';
      };
      metric = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        example = true;
        description = ''
          Use the metric system, overriding whatever `region` implies. null
          (the default) follows the region.

          Writes BOTH keys macOS keeps for this (`AppleMetricUnits` and
          `AppleMeasurementUnits`), because it writes both itself and only one
          of them is load-bearing — setting the friendlier-looking
          `AppleMeasurementUnits` alone leaves a plist that reads right and a
          machine that ignores it.
        '';
      };
      temperature = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "celsius"
            "fahrenheit"
          ]
        );
        default = null;
        example = "celsius";
        description = ''
          Temperature unit, overriding whatever `region` implies. null (the
          default) follows the region. Separate from `metric` because macOS
          keeps it separate — a metric machine reporting °F is a real
          combination, not a mistake.
        '';
      };
      hourFormat = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "12h"
            "24h"
          ]
        );
        default = null;
        example = "24h";
        description = ''
          Force 12- or 24-hour time everywhere, overriding whatever `region`
          implies. null (the default) follows the region.

          System-wide, unlike `haus.menuBar.clock.format`, which is only the
          menu bar clock's own key. Setting both is fine and normal; setting
          only this one still changes the menu bar, because the clock has no
          opinion of its own until you give it one.
        '';
      };
      inputSources = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        default = null;
        example = [
          "com.apple.keylayout.US"
          "com.apple.keylayout.German"
        ];
        description = ''
          The keyboard layouts available in the input menu, by input-source id
          (`com.apple.keylayout.*`). null (the default) leaves your layouts
          alone. List them with:

          ```
          hausax input-sources --all
          ```

          Choosing a non-QWERTY layout here does NOT move haus's own keys: a
          `haus.roster` letter, a workspace key and every launch-mode action
          name a physical position, so on AZERTY the key printed `A` still
          launches whatever sits on `q`. `haus.keys.layout` is the other half.

          THIS ONE OWNS THE LIST. Unlike every other option in §5.6's groups, a
          non-null value here is exhaustive: layouts you don't name get
          disabled, because "add these and keep whatever else was there" makes
          a machine that can never remove a layout it once added. Non-keyboard
          input methods (emoji picker, press-and-hold) are never touched.

          Applied through the documented Text Input Sources API rather than by
          writing `com.apple.HIToolbox` directly. The plist route does work, but
          it resolves a layout by an English display name (`Swiss French`, not
          `SwissFrench`) next to a numeric id that is required and never
          validated — a table haus would have to hardcode and would get
          wrong for exactly the layouts nobody here tests.
        '';
      };
    };

    # ---- power ----
    # §5.6's "Power" group, spiked 2026-08-08 — and deliberately NOT built on
    # nix-darwin's typed `power.sleep.*`, which shells out to `systemsetup`.
    # Measured on macOS 26.6.1: `systemsetup -setcomputersleep 17`, run while
    # the machine was on BATTERY, wrote the AC profile and left battery alone,
    # while nix-darwin discards its stderr. So those options configure a power
    # source the config never named. `pmset -b` / `-c` says which source it
    # means and is what this group uses.
    power =
      let
        mkTimer =
          what: source:
          lib.mkOption {
            type = lib.types.nullOr (lib.types.either lib.types.ints.positive (lib.types.enum [ "never" ]));
            default = null;
            example = 10;
            description = ''
              Minutes of idleness before ${what} while on ${source}, or
              `"never"`. null (the default) leaves macOS's own choice alone.

              A desktop Mac has no battery profile to write, so `pmset` warns
              and the rebuild carries on — set the `charger` half there.
            '';
          };
      in
      {
        displaySleep = {
          battery = mkTimer "the display sleeps" "battery";
          charger = mkTimer "the display sleeps" "the charger";
        };
        computerSleep = {
          battery = mkTimer "the Mac sleeps" "battery";
          charger = mkTimer "the Mac sleeps" "the charger";
        };
        diskSleep = {
          battery = mkTimer "the disk spins down" "battery";
          charger = mkTimer "the disk spins down" "the charger";
        };
        lowPowerMode = {
          battery = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            example = true;
            description = ''
              Low Power Mode while on battery. null (the default) leaves
              macOS's own choice alone.

              The setting with the clearest opinion in this group for a laptop:
              on for battery, off for the charger, is what most people want and
              almost nobody sets.
            '';
          };
          charger = lib.mkOption {
            type = lib.types.nullOr lib.types.bool;
            default = null;
            example = false;
            description = ''
              Low Power Mode while plugged in. null (the default) leaves
              macOS's own choice alone.
            '';
          };
        };

        # ---- the lid ----
        # The one thing in this room that is NOT a timer, and the one thing
        # `awake` cannot do: caffeinate does not cross a lid close (its own
        # usage text says so), because lid-close sleep is a separate path in
        # macOS. pmset's `disablesleep` is the only lever over it, it is
        # root-only, and it is all-or-nothing -- so haus wraps it in a daemon
        # that holds it for exactly as long as an agent is mid-turn. The
        # daemon is modules/core/lidawake.sh; the signal it reads is written
        # by modules/bar/sketchybar/plugins/agents-hook.sh, which is already
        # the single writer of agent state for every client.
        lidAwake = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            example = true;
            description = ''
              Let this Mac keep working with its lid shut.

              Off by default, and deliberately: closing the lid is the one
              gesture everybody reads as "stop", so haus will not quietly
              redefine it. Turn it on and a root daemon holds macOS's
              `disablesleep` -- the only lever over lid-close sleep, which
              `awake`'s caffeinate assertion cannot reach -- for as long as
              `while` says to.

              What it cannot save you from: with the lid shut and no external
              display there is no display at all, so an agent that takes
              screenshots or drives the UI goes blind. Work that has to SEE
              something belongs in a headless VM, whose display is virtual and
              never depended on this one.
            '';
          };

          while = lib.mkOption {
            type = lib.types.enum [
              "agents"
              "always"
            ];
            default = "agents";
            example = "always";
            description = ''
              When to hold the lid open, so to speak.

              `agents` (the default) holds only while an agent is actually
              mid-turn, and lets the Mac sleep once the last one stops -- the
              answer to "let them finish, then behave normally". The signal is
              the one the bar's agents pill already draws, reported by every
              client haus knows (Claude Code, Codex, OpenCode), so nothing has
              to be discovered or polled. An agent sitting at a permission
              prompt does NOT hold: it is blocked on a human who is not there.

              `always` is plain closed-display mode -- this Mac never sleeps on
              a lid close, agents or no agents.
            '';
          };

          requirePower = lib.mkOption {
            type = lib.types.bool;
            default = true;
            example = false;
            description = ''
              Only hold the lid awake while plugged in.

              On by default. A closed laptop on battery is the bad case and the
              invisible one: no screen to tell you it is still working, a
              battery going down, and in a bag nowhere for the heat to go. On
              means unplugging is also how you say stop -- the hold releases
              and the Mac sleeps normally.
            '';
          };

          linger = lib.mkOption {
            type = lib.types.ints.unsigned;
            default = 5;
            example = 1;
            description = ''
              Minutes to keep holding after the last agent stops.

              Only `while = "agents"` has anything to linger for. The gap
              between two turns is seconds, and sleeping inside it
              would end the run you were trying to protect. This only ever
              extends a hold that already exists; it never starts one. 0 sleeps
              the moment the last agent goes idle.
            '';
          };

          maxHold = lib.mkOption {
            type = lib.types.either lib.types.ints.positive (lib.types.enum [ "never" ]);
            default = 480;
            example = "never";
            description = ''
              Minutes one unbroken hold may last, or `"never"` for no cap.

              The failsafe. A client that dies without reporting leaves a hold
              behind, and without this the Mac would simply never sleep again
              with nothing on screen to say why. Past the cap the hold releases
              and stays off until either the holds clear or an agent starts a
              fresh turn -- so a stuck hold costs one window rather than
              forever, and a leaked one, which nothing will ever remove, still
              gets out of a real agent's way. 8 hours by default -- long enough
              for an overnight run.
            '';
          };
        };
      };
  };
}

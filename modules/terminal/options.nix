# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# terminal's options — git identity, the one editor, shell/terminal behaviour,
# Zen's extensions, and Claude Code's global memory file.
#
# `config` is in scope for one reason: `terminal.editor`'s default is read off
# `terminal.editorName` (see there), the same way `fonts.mono.size` is read off
# `fonts.mono.baseSize` in core's options.
{ lib, config, ... }:

let
  # Every Nebelung accent name, so floatBorder can take a colour of its own
  # rather than only "the accent" — the same courtesy haus.bar.logo.color pays.
  # Shared with theme's own option, one list, one place (modules/lib/accents.nix).
  accentNames = import ../lib/accents.nix;

  # The extensions haus knows the id of, so naming one in haus.zen.extensions is
  # enough. An id is unguessable, and a wrong one fails SILENTLY (the policy
  # just installs nothing), so this table only ever holds ids read off a real
  # installed add-on — never one inferred from a slug. Growing it is a favour to
  # the next person, not a requirement: anything absent still works with an
  # explicit `id`. Dark Reader, the browser-side Nebelung port nobody has wired,
  # is deliberately not here for that reason — nobody has read its id off a live
  # profile.
  #
  # Stylus is still here after the 2026-08-20 retirement, and the split is the
  # point: what was retired is haus THEMING through it — the stamped bundle, the
  # import nudge, the port claim, all of which haus.zen.userStyles does without a
  # click. Deploying it is a different job, this table is only ids, and this one
  # was read off a live profile. Dropping it would break the host files that
  # already name it (the `id` assertion below would fire) to delete a fact that
  # is expensive to recover and cheap to keep.
  knownZenExtensions = {
    stylus = {
      id = "{7a7a4a92-a2a0-41d1-9fd7-1e92480d612d}";
      slug = "styl-us";
    };
  };

  contrib = import ../lib/contrib.nix { inherit lib; };

  # The editors this room can install, and what each answers to on PATH.
  # modules/lib/editors.nix explains why the CHOICE is an enum while the
  # COMMAND stays a free string.
  editors = import ../lib/editors.nix;
in

{
  options.haus = {
    # ---- the Development room's extension points ------------------------------
    # Declared here because terminal is the terminal, which is what a contributed
    # binding lands in. See modules/lib/contrib.nix for the contract, and
    # modules/ai for today's only writer.
    _contrib.development.agents = contrib.mkExtensionPoint {
      description = ''
        The AI room's agent lifecycle bindings, as the terminal renders them:
        the `c` alias — the client, in the checkout the shell is already in —
        and the cheatsheet cards the launcher draws from the same table. The
        chord that spawns a fresh `scruff` worktree is not here — a lane is a
        window, so it is ⌘↵, a Ghostty-scoped launcher hotkey firing
        `cmd:lane-here`. There is no chord for the resident agent: ⌃⌥⇧A ran one
        until 2026-08-19, and `c` was always the shorter way to type it.

        Off leaves the terminal exactly as it is without agents — no dead chord
        teaching a client this machine never installed. It never installs an
        agent client itself: that is the AI room's own payload.
      '';
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether the terminal binds and teaches the agent chords.";
        };
        default = lib.mkOption {
          type = lib.types.str;
          default = "claude";
          description = "The client the chords spawn — `haus.ai.default`.";
        };
        namer = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            The scruff namer adapter id — `haus.ai.namer`. Rides this point
            rather than being read off `haus.ai.*` for the same reason
            `default` does: the AI room decides whether a lane gets named,
            this room decides how scruff's config spells it. Empty writes no
            key at all, which is scruff's own "no namer" default.
          '';
        };

        # No `clients` field on purpose. The list matters to what gets INSTALLED,
        # which is the AI room's own payload, not a contribution — a field here
        # that nothing reads would invite a future reader to trust it.
      };
    };

    git = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "Ada Lovelace";
        description = "Git user.name for commits (terminal wires it into home-manager).";
      };
      email = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "ada@example.com";
        description = "Git user.email for commits.";
      };
      signingKey = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "6F7BD6F43A7C1420";
        description = ''
          GPG key id for signing commits/tags. Empty disables commit signing.
          Key material + any YubiKey/smartcard setup live outside Nix
          (gpg-agent + pinentry-mac).
        '';
      };
      org = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "hausfold";
        description = ''
          The GitHub owner whose repos this machine works on. An organisation,
          or your own account: GitHub's issue search treats `org:<user>` the
          same as `user:<user>`, so one option covers both (measured against
          both qualifiers, 2026-08-08 — the counts match).

          It exists because a gh-dash PR section is a GitHub search filter
          scoped by `org:`. Set this **and** `haus.terminal.ghDash.enable` and
          Terminal renders four PR tabs for that owner — the open / green / red /
          just-shipped work. On its own it does nothing: it is the dashboard's
          scope, not a feature of its own.

          Leave it empty (the default) and Terminal writes no PR tabs at all, so
          gh-dash keeps its own and a host composing a queue in
          `programs.gh-dash.settings` never fights one. Empty is the right
          answer for a machine that reads several owners at once: there is no
          single owner to render. The issue and notification tabs are unaffected
          either way — they ask who you are (`@me`, `is:unread`) rather than
          where you work, so the dashboard ships them regardless.

          Where it earns its keep is a rename: an org that changes name, or a
          repo set that moves between orgs, is one word here rather than one per
          tab. A host's `repoPaths` can follow the same word instead of
          repeating it — read it as `config.haus.git.org` from a darwin-level
          module, or as `osConfig.haus.git.org` from inside
          `home-manager.users.<user>`, where `config` is home-manager's and
          carries no `haus.*` at all.
        '';
      };
      shellAliases = lib.mkOption {
        type = lib.types.attrsOf (lib.types.nullOr lib.types.str);
        default = { };
        example = lib.literalExpression ''
          {
            gst = "git status --short --branch"; # replace a built-in
            gsync = "git pull --rebase --autostash"; # add one
            gco = null; # remove one
          }
        '';
        description = ''
          Per-host additions and overrides for Terminal's built-in Git shell
          aliases. Values are shell command strings; null removes a built-in.
          Terminal deliberately owns a compact, framework-independent default
          set, so this changes only Git shortcuts and does not require a shell
          plugin manager.
        '';
      };
    };

    terminal.editorName = lib.mkOption {
      type = lib.types.enum (builtins.attrNames editors);
      # The desktop-safe half of the pair, and the one that actually INSTALLS
      # something. helix is the room's own default rather than a hacker
      # opinion carried in the desktop: a terminal room with no editor is not
      # unopinionated, it is broken — git alone would drop you into whatever
      # $EDITOR the machine happened to have. Same reasoning as
      # `fonts.mono.name`, which keeps supplying a patched family.
      default = "helix";
      example = "neovim";
      description = ''
        Which editor this room installs. `helix` (the default) is the one haus
        is themed around; `neovim`, `vim` and `nano` are installed as-is,
        with no Nebelung theme — Nebelung has a port for helix and not for
        them.

        Setting this also moves `haus.terminal.editor`, since that defaults to
        whatever the chosen editor answers to on PATH (`hx`, `nvim`, `vim`,
        `nano`). Choosing here is the whole gesture: the editor is installed
        AND every "open in an editor" action follows it.

        A desktop may set this. To point haus at an editor it does not
        install — a GUI one, or something from your own host file — leave this
        alone and set `haus.terminal.editor` instead.
      '';
    };

    terminal.editor = lib.mkOption {
      type = lib.types.str;
      # Host-only, and permanently so: this value is EXECUTED — baked into the
      # window opener, the palette command and the bar's nix-open item. That is
      # the reason a desktop chooses with `editorName` above rather than here.
      # It is still the last word, though: a host naming "code -w" beats the
      # enum's command, which is what makes the enum a closed set without
      # making it a cage.
      default = editors.${config.haus.terminal.editorName}.command;
      # literalMD, not literalExpression: host-template.jq copies a
      # literalExpression into the generated host file verbatim, and this is a
      # sentence rather than pasteable Nix (see fonts.mono.size, which learned
      # it the same way). No backticks and under 60 characters, for the two
      # things that read it after: hausfold.co's generator wraps the whole
      # string in a code span (nested backticks come out as broken markdown)
      # and moves anything longer into the body as "see below".
      defaultText = lib.literalMD "the command for haus.terminal.editorName — hx for helix";
      example = "code -w";
      description = ''
        The ONE editor command haus uses everywhere. It's the shell command
        for $EDITOR / $VISUAL (git, etc.) AND what every "open in an editor"
        action launches — the "Nix Config" palette command, the bar's nix-open
        item, and the file-association hijack. Those open the target in a new
        terminal WINDOW running this command, so a terminal editor is the
        natural fit for haus; a GUI editor's CLI works too (e.g. "code" or
        "code -w" to block).

        It defaults to the command for `haus.terminal.editorName`, so choosing an
        editor there is enough. Set this only for the case that option cannot
        express: pointing haus at something it does not install. Naming a
        command here does NOT install it — that machine has to already have it.
      '';
    };

    terminal.hijackFileAssociations = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        When true, build a small opener app and make it the default handler
        for ~80 text/code extensions (json, md, ts, nix, rs, go, kdl, …), so
        opening or clicking those files opens them in haus.terminal.editor in
        a terminal window. The app declares the types itself (not just `duti`) so
        extensions nothing else on the machine declares still bind. Off by
        default: silently rewriting your file associations is a jarring,
        hard-to-undo change, so it's strictly opt-in. (Extensionless executables
        like `bench` are NOT covered — macOS gates the public.unix-executable
        handler behind an interactive dialog; set it by hand once if wanted:
        `duti -s com.hausfold.editoropen public.unix-executable all`.)
      '';
    };

    terminal.restoreWindows = lib.mkOption {
      type = lib.types.bool;
      default = true;
      example = false;
      description = ''
        Put your terminal windows back when Ghostty starts.

        Closing a window does not end its shell — every window is a `zmx`
        session that outlives it, so a ⌘W, a ⌘Q or a crash leaves the shells
        (and any agents) running with nothing looking at them. On, the FIRST
        window of a Ghostty reopens one window per parked session, each attached
        to the session it belongs to, with lanes landing back on their own
        `T/<repo>` pages. Off, that first window is just a new shell and the
        parked sessions wait — the palette's **Restore Terminal Windows** does
        the same thing on demand either way, as does the `agents` pill, ⌘F's ⏎
        and the **Lanes** picker for one session at a time.

        Only the FIRST window restores, never a later one: ⌘N and ⌘⇧N always
        open a new shell in the directory you asked for, which is the only thing
        they promise. A shell you are finished with should be ended (⌃D, or
        `exit`) rather than closed, or it is a window that comes back.

        "First" means nothing is attached anywhere on the machine, which is a
        shade broader than "first window of this Ghostty": with a tiler, a lane
        runs as its own Ghostty instance, so quitting the main one while a lane
        window is still open leaves something attached and the automatic restore
        stays quiet. The palette row is the answer there, and is the answer
        whenever the automatic moment has passed.

        Needs `haus.ai.clients` — not for the lanes, but because `zmx` itself
        rides that switch, and with no zmx there are no sessions to park.
      '';
    };

    terminal.obsidianVaults = lib.mkOption {
      type = lib.types.listOf (
        lib.types.addCheck lib.types.str (
          path:
          path != ""
          && !(lib.hasPrefix "/" path)
          && !(lib.any (component: component == "..") (lib.splitString "/" path))
        )
      );
      default = [ ];
      apply = lib.unique;
      example = [
        "Library/Mobile Documents/iCloud~md~obsidian/Documents/notes"
      ];
      description = ''
        Home-relative paths to existing Obsidian vaults that should use the
        Nebelung theme. On each activation, Terminal copies the rendered
        theme.css + manifest.json into each vault's .obsidian/themes/Nebelung/
        directory, selects Nebelung's dark appearance in appearance.json, and
        removes the obsolete "nebelung" CSS snippet from the enabled list.

        Empty (the default) leaves every vault untouched. Paths must be
        relative to the user's home, may not contain "..", and are skipped
        with a warning unless their .obsidian directory already exists.

        A vault whose appearance.json iCloud has evicted, or that holds JSON
        Terminal cannot parse, gets the theme files but keeps its own
        appearance settings, with a warning naming the vault. Activation
        never fails over a vault.
      '';
    };

    terminal.floatBorder = lib.mkOption {
      type = lib.types.enum (
        [
          "accent"
          "grey"
          "off"
        ]
        ++ accentNames
      );
      # Follows haus.theme.accent, so it is already whatever the desktop chose
      # — neutralising it to "off" would make the bare room worse without
      # making it less opinionated.
      default = "accent";
      example = "grey";
      description = ''
        The outline drawn around every floating terminal `float-term.sh` spawns:
        the ⌘Y yazi peek panel, the bar's agent peek, and the palette's
        Rebuild System / Install App / Settings windows. They all land on top of
        a tiled desktop, where a dark terminal over a dark window behind it has
        no edge at all.

        - `accent` (the default) — `haus.theme.accent`, so a summoned window
          announces itself and the whole desktop keeps one accent.
        - `grey` — Nebelung's `surface0`, one step off the terminal's own
          background: the same relationship the bar's dropdowns wear
          (`popup.background.border_color` in modules/bar), for an edge that
          defines the window without drawing the eye.
        - `off` — no outline; the look before this option existed. It also keeps
          floatring out of the closure entirely, so nothing is compiled for it.
        - any Nebelung accent name (`lavender`, `sapphire`, …) — one colour for
          these popups that ISN'T `haus.theme.accent`, the same escape hatch
          `haus.bar.logo.color` offers.

        2pt, following the window's own corner curve. Drawn by a tiny overlay
        window (modules/terminal/floatring.swift) that lives and dies with the
        popup, because Ghostty has no border setting of its own and aerospace
        draws none — that file's header has the rest, including why it isn't
        JankyBorders. Switch it with
        `haus set terminal.floatBorder grey && haus rebuild`; to compare colours
        first, without a rebuild, outline any window by hand (the process name is
        lower-case — `pgrep -x Ghostty` matches nothing and rings nothing):
        `~/.config/haus/term/float-term.sh ring "$(pgrep -x ghostty | head -1)" '#cba6f7'`
      '';
    };

    terminal.ghDash.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Whether to enable the themed gh-dash GitHub dashboard and its ⌘G
        near-fullscreen floating window.

        Enabling it gets you the issue and notification tabs (yours, assigned,
        unread, participating). The four PR tabs — open / green / red /
        shipped — need `haus.git.org` as well, since a PR section is a search
        filter scoped to an owner. A host can compose or replace any of it
        through home-manager's `programs.gh-dash.settings`: every section list
        Terminal writes is a `mkDefault`, per list.

        Needs `haus.developer.git.enable` (an assertion enforces it): gh-dash
        authenticates out of `gh`'s own credentials, so the Git pack is where
        its login comes from.
      '';
    };

    zen.extensions = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, config, ... }:
          {
            options = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = "Whether to deploy this extension. Set false to remove one an imported desktop added.";
              };

              id = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = knownZenExtensions.${name}.id or null;
                example = "{7a7a4a92-a2a0-41d1-9fd7-1e92480d612d}";
                description = ''
                  The extension's own id — the key Firefox's policy engine
                  matches on, NOT its AMO slug. Usually a brace-wrapped UUID,
                  sometimes an email-shaped string (`addon@example.org`).

                  Find it by installing the add-on once and reading `Extension
                  ID` under about:debugging ▸ This Firefox, or from the
                  `browser_specific_settings` block of its source. Wrong id and
                  the policy silently installs nothing — which is why this has
                  no guessable default.
                '';
              };

              slug = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = knownZenExtensions.${name}.slug or null;
                example = "styl-us";
                description = ''
                  The add-on's AMO slug — the last path segment of its
                  addons.mozilla.org URL. Only used to build the default
                  `url`; set `url` directly and this is ignored.
                '';
              };

              url = lib.mkOption {
                type = lib.types.str;
                default =
                  if config.slug == null then
                    ""
                  else
                    "https://addons.mozilla.org/firefox/downloads/latest/${config.slug}/latest.xpi";
                description = ''
                  Where the .xpi comes from. Defaults to AMO's "latest" endpoint
                  for `slug`, so the add-on updates itself; point it at a pinned
                  version or a self-hosted file to freeze it.

                  A `file://` url has a second effect, and it is not local to
                  this extension: a file on disk cannot have been signed by
                  Mozilla, and Zen refuses an unsigned add-on
                  (`ERROR_SIGNEDSTATE_REQUIRED`) unless
                  `xpinstall.signatures.required` is off. So naming one makes
                  haus lock that pref off **for the whole browser** — the
                  same switch `haus.zen.tabBridge.enable` documents, since the
                  bridge is haus's own `file://` install. An `https://` AMO
                  url never turns it on.
                '';
              };

              mode = lib.mkOption {
                type = lib.types.enum [
                  "force_installed"
                  "normal_installed"
                  "allowed"
                  "blocked"
                ];
                default = "force_installed";
                description = ''
                  Firefox's `installation_mode`. `force_installed` installs it
                  and stops the user removing it (the point, for a desktop that
                  wants an extension present); `normal_installed` installs it
                  but leaves it removable.
                '';
              };
            };
          }
        )
      );
      default = { };
      example = lib.literalExpression ''
        {
          ublock-origin = {
            id = "uBlock0@raymondhill.net";
            slug = "ublock-origin";
          };
        }
      '';
      description = ''
        Browser extensions to deploy into Zen, by a stable id of your choosing.

        The mechanism is Firefox's enterprise policies — haus renders an
        `ExtensionSettings` block — so it reaches Zen the way an IT department
        reaches Firefox, without a profile to hand-edit. `haus.roster`
        deliberately cannot do this: a roster entry installs from a cask, a
        brew, a nixpkgs package or the App Store, and a browser add-on is none
        of those.

        Two consequences of HOW the policies are delivered, both visible.
        Firefox only ever looks for a `policies.json` inside the app bundle,
        which haus has no business writing into (it breaks the code signature
        and a cask upgrade wipes it), so haus uses the other route macOS
        offers: a managed preference at
        `/Library/Preferences/app.zen-browser.zen.plist`. That file is
        root-owned, so it's written during system activation and a `haus
        rebuild` that can't reach it warns instead of installing anything. And
        because enterprise policies are on, Zen will tell you it is "managed by
        your organization" — that organization is haus.

        Every entry needs an `id` — the key Firefox's policy engine matches
        on, unguessable and unreachable from the add-on's name. haus fills it in
        for the add-ons whose id it has read off a live profile
        (${lib.concatStringsSep ", " (builtins.attrNames knownZenExtensions)}),
        so those need only be named. Everything else brings its own — see the
        `id` option for where to read one off.

        This is deployment, not theming. haus themes Zen's own UI through
        `haus.theme.accent` and real websites through `haus.zen.userStyles`,
        which compiles the Nebelung userstyles straight into the profile's
        userContent.css. Stylus used to be the second half of that story — haus
        stamped your accent, flavor and contrast into a bundle and nudged you to
        import it — and that half was retired on 2026-08-20. Naming `stylus`
        here still deploys the extension; it just arrives unthemed now, so keep
        the sites you care about in `haus.zen.userStyles` instead.
      '';
    };

    zen.userStyles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "github"
        "youtube"
        "reddit"
      ];
      description = ''
        Nebelung userstyles to compile into Zen's `userContent.css`, by slug —
        the palette on real websites, with **no extension and no import click**.

        These are the 134 styles nebelung ships for the Stylus extension,
        taken the other way round. They are LESS source, which is why the
        accent could only ever reach the web through an import click: the
        extension compiled them in the browser. haus compiles the ones you name
        here at build time instead, stamping the same three axes
        (`haus.theme.accent`, and the flavor on both its light and dark vars),
        and appends the result to the stylesheet it already drops into every
        Zen profile. Nothing to re-import and no state to carry to the
        next machine — but a **restart of Zen** is what applies it: Firefox
        reads `userContent.css` once at startup, so a rebuild alone leaves an
        open browser on the previous colours.

        A slug is the style's own name in nebelung's bundle — `github`,
        `youtube`, `reddit`, `hacker-news`. Naming one that doesn't exist fails
        the build and lists every slug there is, so a typo costs a rebuild
        rather than a silently unthemed site.

        **Keep the list short.** A user stylesheet is parsed and applied to
        every document, and these are big: github and youtube together are
        ~320 KB, the whole set is 7 MB of CSS on every page load to theme sites
        you never open. This is for the handful you actually read.

        Code blocks are themed too, including on the couple of dozen styles
        that reach for them through a remote `@import url(...)` — mdn,
        wikipedia, stack-overflow and the nix docs among them. An `@import`
        inside an `@-moz-document` block is invalid CSS wherever it points, so
        haus vendors the four files those 29 styles share and pastes each one
        in where its `@import` was. A fifth URL appearing upstream fails the
        build naming it, rather than shipping a style whose code blocks are
        quietly stock.

        Every declaration is compiled to `!important`, and that is load-bearing
        rather than heavy-handed: a user stylesheet's normal declarations rank
        BELOW the page's own in the cascade, so an unstamped sheet matches the
        site and then loses every property to it. Most of these styles theme by
        redefining the site's own custom properties without `!important` —
        which is free for an extension, since it injects author-origin CSS —
        so without the stamp they render nothing. It was measured that way: this
        option shipped twice before anyone loaded a page instead of checking
        that the file was in the profile.

        The stamp is skipped exactly where `!important` would be invalid and
        the declaration would therefore be dropped: `@keyframes`, descriptor
        blocks like `@font-face`, and at-statements.

        This is now the only web-theming path haus ships. Until 2026-08-20 it
        also stamped an importable bundle for the Stylus extension; what that
        click bought — per-site toggles, styles that update themselves, adding
        one without a rebuild — is what a compiled sheet gives up, and none of
        it was being used. `haus.zen.extensions.stylus` still deploys the
        extension, unthemed, but keep a given site in one place or the other:
        they do not tie, and a user sheet's
        `!important` outranks every author sheet, so this one wins and the
        extension's copy of that site would be doing nothing.

        **Gecko only, and permanently so.** `@-moz-document` in a user sheet is
        what makes this possible; Chromium removed user stylesheets in Chrome 33
        and the Blink equivalent would be a self-built extension. Zen is where
        haus points it because Zen is the browser haus themes — the compiled
        sheet itself is engine-generic, so a second Gecko browser would only
        need its profile directory added.
      '';
    };

    zen.tabBridge.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Deploy haus's own tiny extension into Zen, so the bar can find and
        switch to the tab that is making noise.

        This is what makes the media pill's ⌘ click land on the **tab** rather
        than just bringing Zen forward. Safari and the Chromium browsers need
        nothing here — they hand their tab list to AppleScript and the pill uses
        that. Firefox and its forks hand out nothing at all, to AppleScript or
        to accessibility, so without this the pill falls back to driving
        Firefox's own address-bar tab search with synthetic keystrokes, which
        needs the Accessibility permission and is exactly as pleasant as it
        sounds.

        Off by default because it force-installs an add-on into your browser,
        which is not a thing haus should do to you unasked. Turning it on
        costs one derivation, a native-messaging manifest, and two keys in
        haus's root-owned policy plist — one of which is the signature switch
        below. Turning it back off stops haus deploying it — what Zen then
        does with the add-on already installed is Firefox's policy engine's
        business, not haus's, so check `about:addons` and remove it there if
        it outstays the option.

        **Zen only, and that's a signing constraint rather than a choice.**
        Release Firefox refuses an extension Mozilla hasn't signed, and it is
        built so that no pref and no policy can say otherwise. Zen is built the
        other way (`MOZ_REQUIRE_SIGNING = false`), which is the whole reason
        haus can build the `.xpi` itself and install it out of the nix store.

        It still costs a switch. Zen carries Firefox's own preference defaults,
        which turn signature enforcement back on, so turning this option on also
        makes haus lock `xpinstall.signatures.required = false` — for the
        browser, not just for its own add-on. Without it Zen refuses the bridge
        with `ERROR_SIGNEDSTATE_REQUIRED` and the option quietly does nothing;
        with it, an unsigned add-on from anywhere would also install if
        something asked. That is the second reason this is off by default.

        Firefox support would mean an AMO account and unlisted self-distribution
        signing — packaging, not a code change — and would drop the pref.
      '';
    };

    zen.extraPolicies = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      example = lib.literalExpression "{ DisableTelemetry = true; }";
      description = ''
        Anything else to put in Zen's policy set, merged beside the
        `ExtensionSettings` block `haus.zen.extensions` renders. haus OWNS
        the file these land in — `/Library/Preferences/app.zen-browser.zen.plist`,
        written as root — so this is the escape hatch for the rest of the policy
        surface rather than a reason to take the file back by hand. Keys here
        win over haus's on a collision.

        Write the policy names as Firefox documents them, nested: this becomes
        the top level of a plist beside `EnterprisePoliciesEnabled`, so
        `{ Extensions.Install = [ "…" ]; }` is an `Extensions` dict with an
        `Install` array in it, not a key called `Extensions.Install`. Setting
        every policy back to `{ }` (and naming no extensions) takes the file
        down again on the next rebuild.

        The merge is one level deep, so naming a policy takes that policy over
        WHOLE. Two of them haus writes itself: `ExtensionSettings` (from
        `haus.zen.extensions`) and `Preferences` (which is where the signature
        switch a `file://` install needs ends up). Restate what you still want
        if you set either — dropping the signature switch this way is invisible
        until you notice the add-on isn't there.

        Values are passed to a plist writer, so `null` is not a value: it
        renders as a key with nothing under it, which makes the whole file
        invalid and drops **every** policy, not just that one. Omit the key
        instead.
      '';
    };

  };
}

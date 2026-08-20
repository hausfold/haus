# Part of the haus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# theme's options — the accent colour and macOS's Light/Dark appearance. The
# desktop picture is its own room now: haus.wallpaper.* in ../wallpaper.
{ lib, ... }:

let
  # Shared with haus.bar.logo.color, which defaults to whatever this is set to
  # — see modules/lib/accents.nix for why the list isn't written out twice.
  accentNames = import ../lib/accents.nix;
in
{
  options.haus = {
    theme.flavor = lib.mkOption {
      type = lib.types.enum [
        "mocha"
        "latte"
      ];
      default = "mocha";
      example = "latte";
      description = ''
        Light or dark. "mocha" (the default) is the dark half of Nebelung,
        which is what haus has always shipped; "latte" is light mode.

        Not an inversion of the dark palette — a different SOURCE palette. Nebelung
        is "Catppuccin with the blue stripped out", and those rules say nothing
        about dark, so they apply to Catppuccin Latte just as well: same warm-grey
        neutral ramp, same calmed accents, the other polarity. Light mode lands at
        7.0:1 for body text on its own, so it's legible before you reach for
        contrast = "high" (which takes it to 9.9:1).

        It composes with `contrast`: the two axes give four palettes, and nebelung's
        CI measures each one's contrast ratio rather than eyeballing it.

        Honest scope, in two parts.

        What follows it: every tool haus injects colours into or points at a
        rendered theme — Ghostty, bat, delta, lsd, yazi, fzf, glow, starship,
        lazygit, opencode, the bar, Zen and Obsidian, plus helix
        whenever it is the editor `haus.terminal.editorName` selects (Nebelung
        has a port for helix and none for the alternatives).
        These are genuinely re-rendered for the flavor, not recoloured in place:
        whiskers takes different branches for a light flavor (terminal ANSI
        0/7/8/15 swap, Zen switches its prefers-color-scheme block, delta sets
        `light = true`).

        What does NOT follow it:

          - the launcher and the shelf, by default. Both read their palette at
            runtime and can pick per polarity, so haus.launcher.followSystemAppearance
            and haus.shelf.followSystemAppearance (default true) hand that
            choice to macOS Light/Dark instead: haus installs every rendered
            variant into ~/.config/{pounce,perch}/themes/ and writes the
            dark/light PAIR at your `contrast`. Set either option false to pin
            that app to this flavor like everything else.
          - macOS's own Light/Dark appearance, unless you opt in with
            haus.theme.systemAppearance = "flavor". Left at its default haus
            does not touch system appearance in either direction, so latte on
            a dark macOS looks half-done and that half is yours —
            except in the launcher and the shelf, which read it themselves.
          - three of the six desktops (haus.wallpaper.style). The hand-made
            "orbits", "constellation" and "flow" have the dark palette baked into
            their pixels; "bold" is generated but follows theme.accent rather
            than the flavor. "minimal" DOES follow it, in every part — field,
            mark, glow and debug band.
      '';
    };

    theme.systemAppearance = lib.mkOption {
      type = lib.types.enum [
        "unmanaged"
        "flavor"
        "light"
        "dark"
      ];
      default = "unmanaged";
      example = "flavor";
      description = ''
        Whether haus also sets macOS's OWN Light/Dark appearance — the one
        in System Settings ▸ Appearance, which paints Finder, the menu bar and
        every native app haus can't reach.

          unmanaged  (default) leave it alone, in both directions. Your Mac's
                     appearance stays yours; nothing about a rebuild moves it.
          flavor     follow haus.theme.flavor — latte sets Light, mocha
                     sets Dark. This is the one that makes light mode complete
                     rather than half-done.
          light      pin Light, whatever the flavor is.
          dark       pin Dark, whatever the flavor is.

        Default "unmanaged" on purpose: a managed default would silently revert
        an appearance you picked in System Settings on the next rebuild, which
        is a worse surprise than a half-light machine.

        How it is applied, and why it is not a `system.defaults` key. Measured
        on macOS 26.6 (2026-08-08), NOT recalled from docs:
        `NSGlobalDomain.AppleInterfaceStyle` is INERT in both directions. Writing
        "Dark" from a light session does nothing; deleting the key from a dark
        one does nothing; `activateSettings -u` does not help; a process launched
        fresh afterwards still reports the old appearance, and no
        AppleInterfaceThemeChangedNotification is posted. That key is a mirror
        the appearance system writes, not a lever. So haus drives appearance
        through System Events (AppleScript) at each home-manager activation,
        which does flip it live in ~0.3s — and confirms the result with `hausax`
        (AppKit's effective appearance), never by reading the key back.

        Reachability, the same shape as haus.accessibility.increaseContrast:
        driving System Events needs an Automation grant for whichever app runs
        the rebuild (System Settings ▸ Privacy & Security ▸ Automation). Without
        it macOS refuses, the rebuild says so in a named warning and carries on
        — the appearance just doesn't move, and nothing else is affected.

        One more thing macOS can undo: System Settings ▸ Appearance ▸ **Auto**
        switches polarity on its own schedule. haus sets the appearance at
        rebuild time and does not fight it afterwards, so on an Auto machine
        this option holds only until the next scheduled switch. Pick Light or
        Dark there if you want it to stick.

        Interaction worth knowing: haus.{launcher,shelf}.followSystemAppearance
        hand polarity to macOS. Set this to "flavor" and macOS's polarity is in
        turn haus's, so those two end up following `flavor` transitively —
        which is usually what you wanted, but it does mean `followSystemAppearance`
        stops being an independent axis on this machine.
      '';
    };

    theme.contrast = lib.mkOption {
      type = lib.types.enum [
        "normal"
        "high"
      ];
      default = "normal";
      example = "high";
      description = ''
        How far the interface separates from its background.

        "high" swaps in the Nebelung high-contrast palette: the same hues and
        the same accents, with the neutral ramp pulled apart in OKLCH so text
        and background separate further at every step. Measured rather than
        eyeballed — body text goes from 11.3:1 to 19.9:1 against the base,
        clearing WCAG AAA (nebelung's own CI asserts it).

        Composes with `flavor`, and the boost is tuned per flavor rather than
        shared: light mode has far less room above its background before the ramp
        clips to white, so latte goes 7.0:1 → 9.9:1 where mocha goes 11.3 → 19.9.
        Both keep all twelve ramp steps distinct, which is the property nebelung's
        tests actually assert.

        Honest scope. This recolours what haus injects colours into:
        Ghostty, bat, delta, lsd, yazi, glow, starship, lazygit, the
        bar, the launcher and the shelf (at runtime, via
        ~/.config/{pounce,perch}/themes/ — and unlike `flavor`, contrast reaches
        both on BOTH halves of their light/dark pair), Zen and Obsidian. It does NOT reach:

          - macOS itself. For system-wide contrast see
            haus.accessibility.increaseContrast — a separate, FDA-gated
            setting. The two are complementary, and a genuinely high-contrast
            machine wants both.
      '';
    };

    theme.accent = lib.mkOption {
      type = lib.types.enum accentNames;
      default = "mauve";
      example = "sapphire";
      description = ''
        The accent colour, by Catppuccin name (the Nebelung palette is a
        grey-tinted Catppuccin, so the fourteen names are the same in both
        flavors — the hue you pick follows haus.theme.flavor). It recolours
        the tools hacker injects colours into — lazygit, fzf, yazi (including
        glow-rendered Markdown headings), and the Zen browser — via the matching
        Nebelung per-accent ports.

        The shelf follows it too, and is the one surface handed the NAME rather than
        a hex: the shelf resolves it against whichever half of its dark/light
        pair macOS is showing, so the ember under the notch and a pinned tile
        wear this accent in both polarities from one key. Left at the shelf's
        default it accents with its own mark green.

        Three more things follow it: the generated desktop (the bloom behind
        the mark in `minimal`, and the whole sweep in `bold` — see
        haus.wallpaper.style), any roster app whose
        Nebelung port ships a per-accent matrix (zed, gh-dash, mpv), placed by
        haus.theme.ports, and the bar's far-left logo pill. Those ports name the
        theme file after the accent, so changing the accent renames the file the
        app's own `theme` key points at — re-pick it in the app, or it falls
        back to stock.

        The bar is the newest and the narrowest of the three: `haus.bar.logo`
        is the ONLY pill that follows this option. Every other colour on the bar
        is a fixed palette key, and the palette itself doesn't move — so a
        machine that changes its accent sees exactly one pill change hue, unless
        `haus.bar.logo.color` names one of its own.

        Honest scope: this moves the accent on those tools, NOT literally
        everything. Single-file dotfiles that bake the palette at their own
        theme slot (ghostty, starship, tmux, bat, …) keep their built-in
        colour and don't follow this option. The base palette stays the same
        Nebelung grey either way — only the accent hue changes.

        Zen means Zen's own UI, and the web is a second step. haus places the
        Nebelung userChrome/userContent pair, and nebelung's userContent styles
        `about:` pages only — github.com and youtube.com are Catppuccin-derived
        *userstyles*, LESS source compiled rather than copied, which is why no
        palette file haus writes reaches them on its own. One option does:
        `haus.zen.userStyles` names the sites you want and haus compiles them
        with this accent into that same userContent.css, so a rebuild (and a Zen
        restart) recolours them with nothing to import. Until 2026-08-20 there
        was a second way — haus deployed the Stylus extension and stamped this
        accent into a bundle you imported by hand — and it is retired; what the
        click bought (per-site toggles, self-updating styles, adding one without
        a rebuild) is what the compiled sheet gives up.

        That reach is pinned by the `accent-reach` flake check, which
        fingerprints every surface under three accents and fails if one starts
        or stops following the accent without anyone deciding it should.
      '';
    };

    theme.ports.enable = lib.mkOption {
      type = lib.types.bool;
      # Carved out, unlike the accent/flavor/contrast above it: those decide how
      # the rice draws ITSELF, while this one writes theme files into apps you
      # installed. A side effect reaching outside the layer is a choice a
      # desktop makes, not one the bare catalogue makes for you.
      default = false;
      description = ''
        Theme the apps in your roster (`haus.roster`) that Nebelung ships a
        port for, without wiring each one by hand.

        haus already themes every tool it installs itself — the shell, the
        terminal, the git stack, Zen, Obsidian. This covers the other direction:
        an app YOU added to the roster that Nebelung happens to have a theme for.
        Add `zed`, `warp` or `xcode` to `haus.roster` and its Nebelung theme
        lands where that app looks for themes, in the flavor and contrast you
        selected, following them on every rebuild. Matching is by roster id, so
        the entry has to be named after the port (`zed`, not `zed-editor`).

        Honest scope, and it is the whole point of the option: this drops the
        theme FILE. Whether that alone makes the theme *active* is the app's
        choice, not ours, and Nebelung records which is which per port. Ghostty
        reads a config key we own, so it just works. Xcode, Warp, OBS and friends
        offer no file interface for picking a theme — the file is put where they
        look, and the one click that selects it stays yours. `haus doctor` lists
        exactly which apps are waiting on that click, so the difference is
        visible rather than something you discover months later.

        Ports whose install is a merge into an existing config file, or that need
        a compile step first, are reported but never written: silently
        half-applying someone's config is worse than saying so.
      '';
    };

    theme.ports.handled = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      internal = true;
      description = ''
        Nebelung port ids haus already wires by hand, contributed by whichever
        room does the wiring (terminal themes the shell toolbelt; theme and bar read
        the palette directly). Rooms append to this the way they contribute Homebrew
        entries, so the roster pass leaves them alone rather than dropping a second,
        blunter copy of a theme a room has already integrated properly.

        An assertion checks every id here is a real port, so a rename in nebelung
        surfaces at eval rather than quietly re-enabling the roster pass for a tool
        that is already handled.
      '';
    };
  };
}

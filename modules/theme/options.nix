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
    # Two values, and a third that supplies its own hexes is deliberately not
    # coming, because it would only half work: nebelung renders each tool's port
    # in a derivation, so a hand-written palette would either have to re-render
    # all of them at rebuild time or reach only the tools haus injects colours
    # into directly — never the ones it points at a rendered theme file.
    #
    # Leaving it out is the safe half of the bet rather than a deferral: the
    # asymmetry runs one way. Adding a "custom" flavor later costs a release;
    # taking one away later is a deprecation on a desktop somebody is already
    # running, and a palette is the option they would have built the most on
    # top of.
    theme.flavor = lib.mkOption {
      type = lib.types.enum [
        "mocha"
        "latte"
      ];
      default = "mocha";
      example = "latte";
      description = ''
        Light or dark. "mocha" is the dark half of Nebelung, "latte" the light
        one, and latte is a real source palette rather than the dark one
        inverted: Catppuccin Latte put through Nebelung's "strip the blue out"
        rule, so it keeps the same warm-grey ramp and the same calmed accents
        the other way up. It reaches 7.0:1 for body text before you touch
        `contrast`. Together with `contrast` that is four palettes, and
        nebelung's CI measures each one rather than eyeballing it.

        What follows it: every tool haus themes itself. Ghostty, bat, delta,
        lsd, yazi, fzf, starship, lazygit, zsh-syntax-highlighting, opencode,
        the bar and Zen always, and three more that wait on something else:
        helix when `haus.terminal.editorName` picks it (Nebelung has a port for
        helix and none for the alternatives), gh-dash under
        `haus.terminal.ghDash.enable`, and Obsidian once
        `haus.terminal.obsidianVaults` names a vault. Each one is re-rendered
        for the flavor rather than recoloured in place.

        Three things it does not reach:

          - the launcher and the shelf, which read their palette at runtime and
            follow macOS Light/Dark instead. haus installs every rendered
            variant into ~/.config/{pounce,perch}/themes/ and writes the
            dark/light pair at your `contrast`. Set
            haus.launcher.followSystemAppearance or
            haus.shelf.followSystemAppearance false to pin one of them to this
            flavor like everything else.
          - macOS's own Light/Dark appearance, until you set
            haus.theme.systemAppearance = "flavor". Left alone haus touches it
            in neither direction, so latte on a dark macOS looks half-done and
            that half is yours.
          - the desktop picture, unless it is "minimal", which follows the
            flavor in every part: field, mark, glow and debug band. See
            haus.wallpaper.style for what the others do instead.
      '';
    };

    # No option points the other way, and that is a decision rather than a gap:
    # there is no desktop-wide "follow the system" that every themed tool obeys.
    # What CAN follow appearance is a tool that owns its whole window, which is
    # not the same set as "a tool" — a terminal that flipped on its own would
    # leave bat, delta, lsd and yazi rendering the other polarity inside it,
    # since those read their palette once at start and stay pinned to `flavor`.
    # One switch cannot say that, so following the system stays a per-tool
    # opt-in: one option on each tool that can honestly carry it.
    # modules/terminal/ghostty/config holds the mechanics where they bite.
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
        Whether haus also sets macOS's own Light/Dark appearance, the one in
        System Settings ▸ Appearance that paints Finder, the menu bar and every
        native app haus cannot reach.

          unmanaged  (default) leave it alone, in both directions. A managed
                     default would silently revert an appearance you picked in
                     System Settings on the next rebuild.
          flavor     follow haus.theme.flavor: latte sets Light, mocha Dark.
                     The one that makes light mode complete rather than
                     half-done.
          light      pin Light, whatever the flavor is.
          dark       pin Dark, whatever the flavor is.

        haus flips it through System Events at each home-manager activation and
        confirms the result with `hausax`, which reads AppKit's effective
        appearance. It never writes `NSGlobalDomain.AppleInterfaceStyle`: that
        key is inert in both directions on macOS 26 and mirrors the appearance
        back at you, so a plist read calls an inert write applied.
        docs/macos-settings.md has the measurement.

        Two things leave the appearance where it was. System Events needs an
        Automation grant for whichever app runs the rebuild (System Settings ▸
        Privacy & Security ▸ Automation); without it macOS refuses, the rebuild
        says so in a named warning and carries on with everything else. And
        System Settings ▸ Appearance ▸ Auto keeps switching polarity on its own
        schedule, which haus does not fight, so there this option holds only
        until the next scheduled switch. Pick Light or Dark in that panel if
        you want it to stick.

        Setting "flavor" settles the launcher and the shelf too:
        haus.{launcher,shelf}.followSystemAppearance hand polarity to macOS,
        and macOS's polarity is now haus's.
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
        Ghostty, bat, delta, lsd, yazi, starship, lazygit, the
        bar, the launcher and the shelf (at runtime, via
        ~/.config/{pounce,perch}/themes/ — and unlike `flavor`, contrast reaches
        both on BOTH halves of their light/dark pair), Zen, and Obsidian once
        `haus.terminal.obsidianVaults` names a vault. It does NOT reach:

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
        The accent colour, by Catppuccin name. The Nebelung palette is a
        grey-tinted Catppuccin, so the fourteen names are the same in both
        flavors and the hue you get follows haus.theme.flavor.

        What follows it: lazygit, fzf, yazi (including the glow-rendered
        Markdown in its preview pane), Zen's own UI, the generated desktop
        picture (the bloom behind the mark in "minimal", the whole sweep in
        "bold"), the bar's far-left logo pill, the shelf, and any roster app
        whose Nebelung port ships a per-accent matrix (zed, gh-dash, mpv) once
        haus.theme.ports places it. The `accent-reach` flake check fingerprints
        every one of those under three accents, so a surface cannot start or
        stop following the accent without someone deciding it should.

        The shelf is the one surface handed the name rather than a hex, so the
        ember under the notch and a pinned tile wear this accent in whichever
        half of its dark/light pair macOS is showing. Its own default is mark
        green.

        Three limits. A per-accent port names its theme file after the accent,
        so changing the accent renames the file the app's own `theme` key points
        at: re-pick it in the app, or it falls back to stock. Single-file
        dotfiles that bake the palette at their own theme slot (ghostty,
        starship, tmux, bat, …) keep their built-in colour, and the base palette
        stays the same Nebelung grey either way, so only the accent hue moves.
        And `haus.bar.logo` is the only pill this reaches; every other colour on
        the bar is a fixed palette key, unless `haus.bar.logo.color` names one
        of its own.

        Zen's own UI is not the web. The Nebelung userContent haus places styles
        `about:` pages only, so github.com and youtube.com need
        `haus.zen.userStyles`: name the sites and haus compiles their userstyles
        with this accent into that same userContent.css, which a rebuild and a
        Zen restart pick up with nothing to import by hand. No per-site toggle
        and nothing self-updates, so adding a site takes a rebuild.
      '';
    };

    theme.ports.enable = lib.mkOption {
      type = lib.types.bool;
      # Carved out, unlike the accent/flavor/contrast above it: those decide how
      # haus draws ITSELF, while this one writes theme files into apps you
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

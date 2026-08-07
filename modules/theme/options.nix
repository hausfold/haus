# Part of the nebelhaus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# theme's options — the accent colour and desktop wallpaper.
{ lib, ... }:

{
  options.nebelhaus = {
    theme.flavor = lib.mkOption {
      type = lib.types.enum [
        "mocha"
        "latte"
      ];
      default = "mocha";
      example = "latte";
      description = ''
        Light or dark. "mocha" (the default) is the rice as it has always been;
        "latte" is light mode.

        Not an inversion of the dark palette — a different SOURCE palette. Nebelung
        is "Catppuccin with the blue stripped out", and those rules say nothing
        about dark, so they apply to Catppuccin Latte just as well: same warm-grey
        neutral ramp, same calmed accents, the other polarity. Light mode lands at
        7.0:1 for body text on its own, so it's legible before you reach for
        contrast = "high" (which takes it to 9.9:1).

        It composes with `contrast`: the two axes give four palettes, and nebelung's
        CI measures each one's contrast ratio rather than eyeballing it.

        Honest scope, in two parts.

        What follows it: every tool the rice injects colours into or points at a
        rendered theme — Ghostty, bat, delta, lsd, yazi, fzf, glow, starship,
        lazygit, helix, zellij, opencode, the bar, Zen and Obsidian.
        These are genuinely re-rendered for the flavor, not recoloured in place:
        whiskers takes different branches for a light flavor (terminal ANSI
        0/7/8/15 swap, Zen switches its prefers-color-scheme block, delta sets
        `light = true`).

        What does NOT follow it:

          - pounce and perch, by default. Both read their palette at runtime and
            can pick per polarity, so nebelhaus.pounce.followSystemAppearance
            and nebelhaus.perch.followSystemAppearance (default true) hand that
            choice to macOS Light/Dark instead: the rice installs every rendered
            variant into ~/.config/{pounce,perch}/themes/ and writes the
            dark/light PAIR at your `contrast`. Set either option false to pin
            that app to this flavor like everything else.
          - macOS's own Light/Dark appearance. Turning ON dark mode is one typed
            setting, but turning it OFF means DELETING a default rather than
            writing one, which nix-darwin has no way to express — so the rice
            leaves system appearance alone in both directions and you set it in
            System Settings ▸ Appearance. A latte rice on a dark macOS looks
            half-done, and that half is currently yours — except in pounce and
            perch, which read the appearance themselves.
          - the desktop wallpaper (nebelhaus.theme.wallpaper). The three hand-made
            looks have the dark palette baked in; only "bold" is generated, and it
            follows theme.accent rather than the flavor.
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

        Honest scope. This recolours what the rice injects colours into:
        Ghostty, bat, delta, lsd, yazi, zellij, glow, starship, lazygit, the
        bar, pounce and perch (at runtime, via ~/.config/{pounce,perch}/themes/ —
        and unlike `flavor`, contrast reaches both on BOTH halves of their
        light/dark pair), Zen and Obsidian. It does NOT reach:

          - macOS itself. For system-wide contrast see
            nebelhaus.accessibility.increaseContrast — a separate, FDA-gated
            setting. The two are complementary, and a genuinely high-contrast
            machine wants both.
      '';
    };

    theme.accent = lib.mkOption {
      type = lib.types.enum [
        "rosewater"
        "flamingo"
        "pink"
        "mauve"
        "red"
        "maroon"
        "peach"
        "yellow"
        "green"
        "teal"
        "sky"
        "sapphire"
        "blue"
        "lavender"
      ];
      default = "mauve";
      example = "sapphire";
      description = ''
        The accent colour, by Catppuccin name (the Nebelung palette is a
        grey-tinted Catppuccin, so the fourteen names are the same in both
        flavors — the hue you pick follows nebelhaus.theme.flavor). It recolours
        the tools nebelhaus injects colours into — lazygit, fzf, yazi, and the Zen
        browser — via the matching Nebelung per-accent ports.

        perch follows it too, and is the one surface handed the NAME rather than
        a hex: the shelf resolves it against whichever half of its dark/light
        pair macOS is showing, so the ember under the notch and a pinned tile
        wear this accent in both polarities from one key. Left at perch's
        default it accents with its own mark green.

        Two more things follow it: the `bold` wallpaper (generated from the
        accent hex — see nebelhaus.theme.wallpaper), and any roster app whose
        Nebelung port ships a per-accent matrix (zed, gh-dash, mpv), placed by
        nebelhaus.theme.ports. Those ports name the theme file after the accent,
        so changing the accent renames the file the app's own `theme` key points
        at — re-pick it in the app, or it falls back to stock.

        Honest scope: this moves the accent on those tools, NOT literally
        everything. Single-file dotfiles that bake the palette at their own
        theme slot (ghostty, starship, tmux, bat, zellij, …) keep their built-in
        colour and don't follow this option. The base palette stays the same
        Nebelung grey either way — only the accent hue changes.

        Zen means Zen's own UI, and the web is a separate story. The rice places
        the Nebelung userChrome/userContent pair, but userContent only styles
        `about:` pages — github.com and youtube.com are themed by the Stylus
        extension, whose Catppuccin-derived styles carry their OWN `accentColor`
        var (default mauve) inside the extension's storage, where no stylesheet
        can reach it. Declare `nebelhaus.zen.extensions.stylus` and the rice
        stamps that var with this accent and tells you, once, when there's a new
        bundle to import; the import itself stays a click, because Stylus has no
        file interface. Until you make it, the web keeps the accent you last
        imported.

        Both halves of that are pinned by the `accent-reach` flake check, which
        fingerprints every surface under three accents and fails if one starts
        or stops following the accent without anyone deciding it should.
      '';
    };

    theme.wallpaper = lib.mkOption {
      type = lib.types.enum [
        "none"
        "orbits"
        "constellation"
        "flow"
        "bold"
      ];
      default = "none";
      example = "orbits";
      description = ''
        The desktop wallpaper, set at each home-manager activation (osascript,
        every desktop on the current Space). Four Nebelung looks:

          orbits · constellation · flow  hand-made, the palette baked in
          bold                           generated from theme.accent, so it
                                         follows the accent (a bold pink at
                                         accent = "pink")

        Default "none" leaves your current wallpaper alone — changing the
        desktop is visible and personal, so nothing moves unless you ask (the
        bootstrap interview offers the choice on a fresh install).
      '';
    };

    theme.ports.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Theme the apps in your roster (`nebelhaus.roster`) that Nebelung ships a
        port for, without wiring each one by hand.

        The rice already themes every tool it installs itself — the shell, the
        terminal, the git stack, Zen, Obsidian. This covers the other direction:
        an app YOU added to the roster that Nebelung happens to have a theme for.
        Add `zed`, `warp` or `xcode` to `nebelhaus.roster` and its Nebelung theme
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
        Nebelung port ids the rice already wires by hand, contributed by whichever
        room does the wiring (hearth themes the shell toolbelt; theme and sill read
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

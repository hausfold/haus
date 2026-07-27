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
        lazygit, helix, zellij, opencode, the bar, Zen and Obsidian. These are
        genuinely re-rendered for the flavor, not recoloured in place: whiskers
        takes different branches for a light flavor (terminal ANSI 0/7/8/15 swap,
        Zen switches its prefers-color-scheme block, delta sets `light = true`).

        What does NOT follow it:

          - macOS's own Light/Dark appearance. Turning ON dark mode is one typed
            setting, but turning it OFF means DELETING a default rather than
            writing one, which nix-darwin has no way to express — so the rice
            leaves system appearance alone in both directions and you set it in
            System Settings ▸ Appearance. A latte rice on a dark macOS looks
            half-done, and that half is currently yours.
          - pounce, which bakes the palette into its binary at build time, so its
            colours follow the pounce build rather than this option.
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
        bar, Zen and Obsidian. It does NOT reach:

          - pounce, which bakes the palette into its binary at build time, so
            its colours follow the pounce build rather than this option;
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

        Honest scope: this moves the accent on those tools, NOT literally
        everything. Single-file dotfiles that bake the palette at their own
        theme slot (ghostty, starship, tmux, bat, zellij, …) keep their built-in
        colour and don't follow this option. The base palette stays the same
        Nebelung grey either way — only the accent hue changes.
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
  };
}

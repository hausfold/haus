# Part of the nebelhaus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# theme's options — the accent colour and desktop wallpaper.
{ lib, ... }:

{
  options.nebelhaus = {
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
        is lighter and backgrounds darker at every step. Measured rather than
        eyeballed — body text goes from 11.3:1 to 19.9:1 against the base,
        clearing WCAG AAA (nebelung's own CI asserts it).

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
        The accent colour, a Catppuccin Mocha name (the Nebelung palette is a
        grey-tinted Mocha). It recolours the tools nebelhaus injects colours
        into — lazygit, fzf, yazi, and the Zen browser — via the matching
        Nebelung per-accent ports.

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

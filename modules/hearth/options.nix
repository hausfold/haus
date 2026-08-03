# Part of the nebelhaus option surface. Split per room so each room's public API
# lives next to the code that implements it; modules/default.nix imports them all.
# Cross-cutting options (the app roster) stay in modules/options.nix.
#
# hearth's options — git identity, the one editor, shell/terminal behaviour,
# and Claude Code's global memory file.
{ lib, ... }:

{
  options.nebelhaus = {
    git = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "Ada Lovelace";
        description = "Git user.name for commits (hearth wires it into home-manager).";
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
          Per-host additions and overrides for Hearth's built-in Git shell
          aliases. Values are shell command strings; null removes a built-in.
          Hearth deliberately owns a compact, framework-independent default
          set, so this changes only Git shortcuts and does not require a shell
          plugin manager.
        '';
      };
    };

    hearth.editor = lib.mkOption {
      type = lib.types.str;
      default = "hx";
      example = "nvim";
      description = ''
        The ONE editor the rice uses everywhere. It's the shell command for
        $EDITOR / $VISUAL (git, etc.) AND what every "open in an editor" action
        launches — the "Nix Config" palette command, the bar's nix-open item,
        and the file-association hijack. Those open the target in a new zellij
        tab running this command, so a terminal editor (hx, nvim, vim, nano) is
        the natural fit for the rice; a GUI editor's CLI works too (e.g. "code"
        or "code -w" to block).
      '';
    };

    hearth.hijackFileAssociations = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        When true, build a small opener app and make it the default handler
        for ~80 text/code extensions (json, md, ts, nix, rs, go, kdl, …), so
        opening or clicking those files opens them in nebelhaus.hearth.editor in
        a terminal tab. The app declares the types itself (not just `duti`) so
        extensions nothing else on the machine declares still bind. Off by
        default: silently rewriting your file associations is a jarring,
        hard-to-undo change, so it's strictly opt-in. (Extensionless executables
        like `bench` are NOT covered — macOS gates the public.unix-executable
        handler behind an interactive dialog; set it by hand once if wanted:
        `duti -s org.nebelhaus.editoropen public.unix-executable all`.)
      '';
    };

    hearth.obsidianVaults = lib.mkOption {
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
        Nebelung theme. On each activation, Hearth copies the rendered
        theme.css + manifest.json into each vault's .obsidian/themes/Nebelung/
        directory, selects Nebelung's dark appearance in appearance.json, and
        removes the obsolete "nebelung" CSS snippet from the enabled list.

        Empty (the default) leaves every vault untouched. Paths must be
        relative to the user's home, may not contain "..", and are skipped
        with a warning unless their .obsidian directory already exists.
      '';
    };

    hearth.zellijStartLocked = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        When true (the default), zellij boots into Locked input mode instead of
        Normal — its single-key submode leaders (pane, tab, resize, …) stay
        inert until you unlock with Ctrl-g, so a stray keystroke can't jump you
        into a submode. The `Super`-prefixed launchers (claude / pane / tab /
        yazi-peek / fullscreen) are bound in `shared` and keep working while
        locked, as do `Alt [` / `Alt ]` (cycle swap layouts) — the rest of
        zellij's `Alt` row stays inert while locked, since those keys are
        readline/vim word motions the pane's app wants. The bar's bottom-right
        quick-hint block only shows in Locked mode. Set false to start in Normal
        mode (zellij's own default).
      '';
    };

    claude.globalMd = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = ''
        # CLAUDE.md — global
        How I like to work across every repo…
      '';
      description = ''
        Contents of Claude Code's global memory file, written to
        ~/.claude/CLAUDE.md (hearth wires it into home-manager). This is your
        personal, cross-project operating context. When set, the rice prepends
        two short sections of its own — a note that the file is generated and
        where to actually edit it, and the `holt` worktree etiquette, since the
        rice ships `holt` and that rule is what keeps it working — then your
        text. Leave it empty to manage ~/.claude/CLAUDE.md fully by hand
        (nothing is written, so the rice never clobbers a by-hand file).
      '';
    };

    claude.skill = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install the `nebelhaus` Claude Code skill into
        ~/.claude/skills/nebelhaus, so an agent asked to "install Slack" or
        "make everything bigger" edits your host file and runs `haus rebuild`
        instead of guessing at dotfiles and `brew install`.

        The skill's option reference is GENERATED from the rice revision this
        machine is pinned to, so it can only ever describe options that
        actually exist here — and it is regenerated by `haus update`. It also
        carries this host's current state (which rooms are on, where the host
        file is) and a starter AGENTS.md + CLAUDE.md pair for your config repo —
        the rules in the first, a one-line import in the second, so a session
        opened there is oriented whichever client it runs.

        Unrelated to Claude Code's own settings, which follow
        nebelhaus.developer.agents.enable. This is a plain file drop: a machine
        that never runs an agent just carries an unread markdown file. Set
        false to leave ~/.claude/skills alone entirely.
      '';
    };
  };
}

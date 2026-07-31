# Hearth — the warm interior of the den. The terminal experience: zsh, a
# Nebelung-tinted starship prompt, git, and a themed CLI toolbelt (bat, delta,
# lazygit, lsd, yazi, zoxide, fzf), plus the ghostty / zellij / yazi dotfiles.
#
# Identity is NOT baked in: git name/email/signing come from `nebelhaus.git.*`
# (set in your host), and secrets stay out of the store — load them in your
# host's zsh initContent from ~/.secrets or similar.
{
  config,
  lib,
  pkgs,
  username,
  hostname,
  ...
}:

let
  gitCfg = config.nebelhaus.git;
  hearthCfg = config.nebelhaus.hearth;
  claudeCfg = config.nebelhaus.claude;
  accent = config.nebelhaus.theme.accent; # a Catppuccin accent name, e.g. "mauve"
  devCfg = config.nebelhaus.developer;
  agentDefault = config.nebelhaus.agents.default;
  fontsCfg = config.nebelhaus.fonts; # terminal font family/size (den installs the package)

  # `zreload` prepares a restart layout from inside zellij, then hands the
  # destructive half to a launchd-owned process. Keeping the package at module
  # scope lets both the user's PATH and that external agent run the exact same
  # implementation.
  zellijReload = pkgs.writeShellApplication {
    name = "zreload";
    runtimeInputs = [
      pkgs.jq
      pkgs.perl
      pkgs.zellij
    ];
    text = builtins.readFile ./zellij/reload.sh;
  };

  # Rice-owned preamble for ~/.claude/CLAUDE.md. The rice ships `wt` (den) on
  # PATH to every machine, and Claude Code agent worktrees live OUTSIDE the repo
  # tree (~/.cache/claude-worktrees/…), so a worktree agent's CLAUDE.md walk never
  # reaches the project/workshop CLAUDE.md — only THIS global memory + the repo's
  # own checked-out CLAUDE.md are guaranteed read. So the general `wt` etiquette
  # every agent needs travels HERE, in the global, WITH the tool — not just in the
  # workshop repo end users don't have. Prepended to the host's own globalMd.
  wtGuidance = ''
    # Agent worktrees & the `wt` tool

    `wt` (shipped by this rice, on PATH) manages Claude Code **agent worktrees**
    for any git repo. `Super c` (⌘C) spawns each agent into its own isolated
    checkout on a `worktree-<name>` branch, so parallel agents never fight over a
    single checkout. Closing a pane never loses work — uncommitted edits are
    parked as a `wip:` commit and only already-merged branches are reaped. Resume
    a parked session with `wt` (lists every worktree across all repos) or
    `wt <name>`; sweep landed ones on demand with `wt reap`.

    **Cross-repo work uses `wt child`, never a raw `git worktree add`.** To work
    on a DIFFERENT repo than the pane you're in (e.g. a parent pane editing a
    sub-repo), create the worktree with:

        cd "$(wt child /path/to/other/repo)"

    A raw `git worktree add` never touches `wt`'s registry, so the Claude Code
    statusline HUD never learns to query that repo's GitHub — the worktree and
    its PR go **invisible in the bar** (they only surface, unattributed with a
    `◇`, in the `~` home pane). `wt child` does the same worktree add but
    registers it under the spawning pane, so its PR shows as a child row where
    you're working.

    **Setting work aside uses `wt park`, never `git stash`.** The stash stack
    is NOT per-worktree — it lives in the shared `.git` dir, so every agent
    worktree of a repo and the main checkout push and pop the SAME stack, and
    parallel agents routinely pop each other's entries into a tree that never
    asked for them. `wt park [label]` instead commits the whole dirty tree as
    one `wip:` commit on the branch only this pane has checked out (the same
    thing the remove hook does on pane close); `wt unpark` rewinds it, putting
    those changes back uncommitted. It refuses to unpark a wip commit you've
    already pushed, so it can never turn into a force-push.

    Full guide: https://nebelhaus.com/guides/claude-agents/

  '';

  # ---- the nebelhaus skill: an agent that can change this machine safely -----
  # A Mac whose config is declarative is the one kind of machine an agent can
  # reconfigure without it being reckless: `haus rebuild` builds before it
  # switches, so a broken edit never reaches the running system, and `haus
  # rollback` undoes an applied one atomically. What was missing was the
  # knowledge — a model left to guess reaches for `brew install` and dotfiles,
  # both of which the next rebuild overwrites, or invents a `nebelhaus.*` option
  # that doesn't exist.
  #
  # So the rice ships the knowledge with itself. The option reference inside the
  # skill is RENDERED from this revision's module system (claude/skill.nix), and
  # `this-machine.md` below is rendered from this host's own evaluated config —
  # neither can drift, and `haus update` refreshes both along with the rice.
  claudeSkill = import ./claude/skill.nix { inherit pkgs; };

  onOff = b: if b then "on" else "off";

  # `toString 1.0` is "1.000000", which reads like a precision the option
  # doesn't have — and an agent copying it back into a host file writes noise.
  trimZeros = s: if lib.hasSuffix "0" s then trimZeros (lib.removeSuffix "0" s) else s;
  num = n: if lib.isFloat n then lib.removeSuffix "." (trimZeros (toString n)) else toString n;

  # Whichever TCC-protected universalaccess keys the host set directly. Named
  # here because it's the one thing that makes an AGENT's rebuild behave
  # differently from the user's own (see haus rebuild's guard), so the skill
  # should be able to see it without evaluating anything.
  rawUniversalaccess = lib.attrNames (
    lib.filterAttrs (_: v: v != null) config.system.defaults.universalaccess
  );

  roster = lib.sort (a: b: a.order < b.order) config.nebelhaus._apps;

  thisMachine = ''
    # This machine

    Rendered from `${hostname}`'s own evaluated configuration when the rice was
    built. Where this disagrees with something you remember, this file is right.

    | | |
    |---|---|
    | hostname | `${hostname}` |
    | user | `${username}` |
    | host file | `~/.config/nix/hosts/${hostname}/default.nix` |
    | config flake | `~/.config/nix` (unless `HAUS_CONSUMER` says otherwise) |
    | rice version | `${lib.fileContents ../../VERSION}` |

    Run `haus status` for the pinned revision and whether it's behind upstream.

    ## Rooms

    | room | what it is | state |
    |---|---|---|
    | prowl | window tiling | ${onOff config.nebelhaus.prowl.enable} |
    | sill | the menu bar | ${onOff config.nebelhaus.sill.enable} |
    | pounce | the command palette | ${onOff config.nebelhaus.pounce.enable} |
    | hush | Focus / Do Not Disturb | ${onOff config.nebelhaus.hush.enable} |
    | trill | the Messages client | ${onOff config.nebelhaus.trill.enable} |
    | perch | the notch file shelf | ${onOff config.nebelhaus.perch.enable} |
    | snippets | text expansion | ${onOff config.nebelhaus.snippets.enable} |
    | developer | the dev toolbelt | ${onOff config.nebelhaus.developer.enable} |

    A room that's off means its options do nothing until you turn it on — say so
    rather than silently enabling a room to satisfy a small request.

    ## Look

    - theme: `${config.nebelhaus.theme.flavor}` flavor, `${config.nebelhaus.theme.accent}` accent, `${config.nebelhaus.theme.contrast}` contrast
    - `nebelhaus.ui.scale` = `${num config.nebelhaus.ui.scale}`
    - terminal font: ${config.nebelhaus.fonts.mono.name} at ${toString config.nebelhaus.fonts.mono.size}pt

    ## Keys

    - leader: `${config.nebelhaus.keys.leader}`
    - palette: `${config.nebelhaus.keys.palette}`
    - window navigation: `${config.nebelhaus.keys.windowNav}`

    ## Apps on the roster

    Leader key → app. Taken keys are taken; pick an unused one when adding.

    ${
      if roster == [ ] then
        "*(none declared)*"
      else
        lib.concatMapStringsSep "\n" (
          a:
          "- `${a.key}` → ${a.name}"
          + (if a.workspace == null then " *(launcher-only)*" else " (workspace `${a.workspace}`)")
          + (if a.cask == null then "" else " · cask `${a.cask}`")
        ) roster
    }

    ## Rebuild hazards on this host

    ${
      if rawUniversalaccess == [ ] then
        "None. `haus rebuild` will run for you."
      else
        ''
          ⚠ This host sets `system.defaults.universalaccess` directly (${lib.concatStringsSep ", " rawUniversalaccess}).

          That domain is TCC-protected, nix-darwin writes it unguarded, and the
          write needs Full Disk Access on whichever app your session runs under.
          A failure there aborts activation partway and skips every background
          service the rice installs.

          So on this host `haus rebuild` checks first, and refuses if this
          session can't write that domain. If it refuses: make the edit, then
          ask the user to run `haus rebuild` in their own terminal. `haus doctor`
          reports whether the grant is present here.
        ''
    }
  '';
in
{
  # The nebelung ports this room wires itself, so the roster pass in
  # modules/theme/ports.nix leaves them alone instead of dropping a second,
  # blunter copy beside the integration below. Twelve are sourced from the
  # rendered theme tree; starship, fzf and lazygit take the palette as Nix
  # values instead (they want colours inline in a config this room already
  # owns, not a file to point at) — either way the tool is handled here.
  # An assertion in theme/ports.nix checks every name is still a real port.
  nebelhaus.theme.ports.handled = [
    "bat"
    "delta"
    "ghostty"
    "glow"
    "helix"
    "lsd"
    "obsidian"
    "opencode"
    "yazi"
    "zellij"
    "zen"
    "zsh-syntax-highlighting"
    "starship"
    "fzf"
    "lazygit"
  ];

  # The reload finisher must outlive both zellij and Ghostty. zreload writes the
  # complete recovery layout first, then kickstarts this otherwise-idle agent;
  # the agent gracefully quits Ghostty, deletes zellij's old server, and opens a
  # new Ghostty process whose launcher consumes that layout on startup.
  launchd.user.agents.zellij-reload = {
    serviceConfig = {
      Label = "org.nebelhaus.zellij-reload";
      ProgramArguments = [
        "${zellijReload}/bin/zreload"
        "_finish"
      ];
      ProcessType = "Interactive";
      StandardOutPath = "/tmp/zellij-reload.out.log";
      StandardErrorPath = "/tmp/zellij-reload.err.log";
      EnvironmentVariables = {
        HOME = "/Users/${username}";
        PATH = lib.concatStringsSep ":" [
          "/run/current-system/sw/bin"
          "/etc/profiles/per-user/${username}/bin"
          "/usr/bin"
          "/bin"
          "/usr/sbin"
          "/sbin"
        ];
      };
    };
  };

  home-manager.users.${username} =
    {
      config,
      lib,
      pkgs,
      osConfig,
      nebelung,
      ...
    }:
    let
      # nebelhaus.theme.{flavor,contrast} select which rendered variant everything
      # below reads — see ../lib/nebelung.nix, which owns that resolution for
      # hearth, sill and theme alike (it was duplicated in all three the moment
      # `contrast` landed; the `flavor` axis would have made that six blocks).
      #
      # nbFlavor is not decoration. whiskers names its output after the flavor it
      # rendered, so every path below that used to say "mocha" is now built from
      # nbFlavor and a latte rice resolves to catppuccin-latte.conf under the latte
      # root. Getting one wrong is invisible: the path just doesn't exist.
      nb = import ../lib/nebelung.nix {
        inherit lib nebelung;
        theme = osConfig.nebelhaus.theme;
      };
      nebelungRoot = nb.root;
      nebelungPalette = nb.palette;
      nbFlavor = nb.flavor; # "mocha" | "latte"
      # The bat theme's name AND its filename, which whiskers title-cases:
      # "Catppuccin Mocha" / "Catppuccin Mocha.tmTheme". Named once because three
      # places reference it — bat's own config, delta's syntax-theme (inside the
      # rendered gitconfig) and yazi's syntect_theme — and they must agree exactly.
      batTheme = "Catppuccin ${nb.title}";
      # Yazi preview: pipe code/text through bat (via piper) so previews match
      # the catppuccin-themed `cat` alias — colours + line numbers.
      batPreviewer = ''piper -- bat --color=always --paging=never --style=numbers --tabs=2 --terminal-width=$w "$1"'';

      # Nebelung glamour port (markdown styling for glow). glow ignores
      # $GLAMOUR_STYLE in its default "auto" mode (glow 2.x), so the style must
      # be passed explicitly with `-s`: baked into the yazi previewer plugin
      # (@glowStyle@ placeholder) and the `glow -p` opener below.
      glowStyle = "${nebelungRoot}/glow/catppuccin-${nbFlavor}.json";
      glowPlugin = pkgs.runCommand "glow.yazi" { } ''
        cp -r ${./yazi/plugins/glow.yazi} $out
        chmod -R +w $out
        substituteInPlace $out/main.lua --subst-var-by glowStyle ${glowStyle}
      '';

      # A deliberately finite Git vocabulary, using the names that recur most
      # often in Oh My Zsh and other common alias sets. Avoid the notoriously
      # ambiguous one- and two-letter collisions (`gl` is pull or log, `gr` is
      # remote or rebase, `gs` is status or stash depending on the framework).
      # Hosts can add/replace entries — or set one to null — through
      # nebelhaus.git.shellAliases, without loading a shell framework.
      defaultGitShellAliases = {
        g = "git";

        ga = "git add";
        gaa = "git add --all";
        gapa = "git add --patch";

        gb = "git branch";
        gba = "git branch --all";
        gbd = "git branch --delete";
        gbD = "git branch --delete --force";
        gbm = "git branch --move";

        gco = "git checkout";
        gcb = "git checkout -b";
        gcl = "git clone";
        gsw = "git switch";
        gswc = "git switch -c";

        gc = "git commit --verbose";
        gca = "git commit --verbose --all";
        gcam = "git commit --all --message";
        gcp = "git cherry-pick";
        gcpa = "git cherry-pick --abort";
        gcpc = "git cherry-pick --continue";
        gcmsg = "git commit --message";
        gcn = "git commit --verbose --no-edit";

        gd = "git diff";
        gds = "git diff --staged";
        gdw = "git diff --word-diff";

        gf = "git fetch";
        gfa = "git fetch --all --tags --prune";
        gfo = "git fetch origin";

        glo = "git log --oneline --decorate";
        glog = "git log --oneline --decorate --graph";
        gloga = "git log --oneline --decorate --graph --all";

        gm = "git merge";
        gma = "git merge --abort";
        gmc = "git merge --continue";
        gmff = "git merge --ff-only";

        gpl = "git pull";
        gpr = "git pull --rebase";
        gp = "git push";
        gpf = "git push --force-with-lease";
        gpsup = "git push --set-upstream origin HEAD";

        grb = "git rebase";
        grba = "git rebase --abort";
        grbc = "git rebase --continue";
        grbi = "git rebase --interactive";
        grbs = "git rebase --skip";
        grt = "cd \"$(git rev-parse --show-toplevel)\"";
        grv = "git remote --verbose";

        gst = "git status";
        gss = "git status --short";
        gsb = "git status --short --branch";

        gsta = "git stash push";
        gstl = "git stash list";
        gstp = "git stash pop";
        gsts = "git stash show --patch";

        gt = "git tag";

        gwt = "git worktree";
        gwta = "git worktree add";
        gwtl = "git worktree list";
        gwtr = "git worktree remove";
      };
      gitShellAliases = lib.filterAttrs (_name: command: command != null) (
        defaultGitShellAliases // gitCfg.shellAliases
      );

      # The accent colour (nebelhaus.theme.accent, default mauve) as the hex the
      # tools nebelhaus injects colours into use for their accent.
      accentColor = nebelungPalette.${accent};
      # Zen browser accent. The nebelung zen port renders every accent under
      # themes/<Flavor>/<Accent>/ (both capitalised); yazi uses lowercase for both.
      zenAccent = lib.toUpper (lib.substring 0 1 accent) + lib.substring 1 (lib.stringLength accent) accent;
      zenTheme = "${nebelungRoot}/zen/themes/${nb.title}/${zenAccent}";
      obsidianTheme = "${nebelungRoot}/obsidian/Nebelung";

      # The zellij custom layout, rendered from the in-repo template. Only two
      # tokens remain: the login name for the tab-bar's username pill, and
      # $HOME for the plugin paths. Bar/tab colours no longer ride in here —
      # our tab-bar + status-bar plugins read the zellij "nebelung" theme
      # directly (the old zjstatus couldn't, so its colours used to be injected
      # here). Shared by custom.kdl and its $HOME-pinned home.kdl variant below.
      zellijLayout =
        builtins.replaceStrings [ "@username@" "@HOME@" ]
          [
            (builtins.substring 0 6 username)
            config.home.homeDirectory
          ]
          (builtins.readFile ./zellij/custom.kdl);

      # Seeds a zellij plugin's grants into the permission cache (see the
      # home.activation entries near the end of this file for the why).
      seedZellijPluginPermissions =
        wasm: perms:
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          permissions="$HOME/Library/Caches/org.Zellij-Contributors.Zellij/permissions.kdl"
          plugin="$HOME/.config/zellij/plugins/${wasm}"
          run sh -c '
            permissions="$0" plugin="$1" tmp="$0.hm-seed"
            mkdir -p "''${permissions%/*}"
            if [ -f "$permissions" ]; then
              # /usr/bin path: home-manager activation runs with a bare PATH
              /usr/bin/awk -v open="\"$plugin\" {" \
                "\$0 == open { skip = 1; next } skip && \$0 == \"}\" { skip = 0; next } !skip" \
                "$permissions" > "$tmp"
            else
              : > "$tmp"
            fi
            printf "%s\n" \
              "\"$plugin\" {" \
              ${lib.concatMapStrings (p: "\"    ${p}\" \\\n              ") perms}"}" >> "$tmp"
            mv "$tmp" "$permissions"
          ' "$permissions" "$plugin"
        '';
    in
    {
      home.sessionVariables = {
        CLICOLOR = "1";
        HOMEBREW_NO_ENV_HINTS = "1";
        EDITOR = hearthCfg.editor;
        VISUAL = hearthCfg.editor;
        NEBELHAUS_AGENT_DEFAULT = agentDefault;
      };

      # A lean terminal/dev toolbelt, gated by the developer pack. Personal
      # choices (AI CLIs, orbstack, your language toolchains) belong in your
      # host file, not the public rice.
      home.packages =
        with pkgs;
        [
          # Not developer tools: iina plays video, duti is what
          # hearth.hijackFileAssociations drives.
          iina
          duti
          zellijReload
        ]
        ++ lib.optionals devCfg.toolbelt.enable [
          chafa # fast terminal image previewer / layout engine
          glow # markdown renderer; yazi's glow previewer shells out to it
          fd # fast finder; used by yazi/zoxide navigation
        ]
        # Editing the rice's own Nix is a developer activity; `haus edit` still
        # works without a formatter. `nixfmt`, not `nixfmt-rfc-style`: nixpkgs
        # aliased the latter to the former and now warns on every eval.
        ++ lib.optional devCfg.enable nixfmt
        ++ lib.optionals (builtins.elem "node" devCfg.languages) [
          bun
          fnm # node version manager (used by the initContent below)
        ]
        # opencode has no x86_64-darwin build, so guard on the package's own
        # platform list rather than hardcoding an arch — it self-heals the day
        # upstream adds Intel, and keeps the example-intel eval green meanwhile.
        ++ lib.optional (
          devCfg.agents.enable && lib.meta.availableOn pkgs.stdenv.hostPlatform pkgs.opencode
        ) pkgs.opencode;

      programs.zsh = {
        enable = true;
        enableCompletion = true;
        autosuggestion.enable = true;
        syntaxHighlighting.enable = true;

        # ~/.zshenv — sourced by EVERY zsh (interactive or not, login or not),
        # before zshrc and before home-manager's zoxide init. Keeping _ZO_DOCTOR
        # here rather than in initContent means non-interactive shells (Claude
        # agents, anything that shells out) also silence zoxide's false-positive
        # doctor warning — zshrc is interactive-only, so it never reached them.
        envExtra = ''
          export _ZO_DOCTOR=0
        '';

        # Each alias follows its own pack: aliasing `cat` to a bat that is not
        # installed would leave a shell that greets you with "command not found".
        shellAliases =
          lib.optionalAttrs devCfg.git.enable (gitShellAliases // { lg = "lazygit"; })
          // lib.optionalAttrs devCfg.agents.enable { c = "claude"; }
          // lib.optionalAttrs devCfg.toolbelt.enable {
            cat = "bat --style=header,grid --tabs=2";
            ls = "lsd";
          }
          // {
          # mdcat's replacement: the same themed glow yazi's previewer uses, so
          # a terminal `mdcat file.md` renders markdown identically to the yazi
          # right-pane preview (Nebelung glamour port, tables and all).
          mdcat = ''glow -s "${glowStyle}"'';
          # Pin the command just like the zellij keybind. This avoids a stale
          # system-profile binary during local rice development.
          zreload = "${zellijReload}/bin/zreload";
        };

        history = {
          size = 5000;
          save = 5000;
          ignoreDups = true;
          ignoreSpace = true;
          path = "$HOME/.zsh_history";
        };

        historySubstringSearch.enable = true;

        plugins = [
          {
            name = "fzf-tab";
            src = pkgs.zsh-fzf-tab;
            file = "share/fzf-tab/fzf-tab.plugin.zsh";
          }
        ];

        initContent = lib.mkMerge [
          (lib.mkBefore ''
            export GPG_TTY=$(tty)

            # zoxide's doctor wants its init to be the LAST thing in the zshrc,
            # but home-manager injects `zoxide init` early — and we deliberately
            # add chpwd hooks after it (fnm --use-on-cd, the zellij tab-namer).
            # Those coexist fine with zoxide's `cd` override (see programs.zoxide
            # below), so the doctor is a false positive; it's silenced via
            # _ZO_DOCTOR=0 in the envExtra above (~/.zshenv) so agent shells —
            # which never source the interactive-only zshrc — get it too.

            # Homebrew (Apple Silicon)
            eval "$(/opt/homebrew/bin/brew shellenv)"

            # Secrets: prefer secretspec (ships with the rice) — a project
            # declares its secrets in a committed secretspec.toml and
            # `secretspec run -- cmd` injects the values from your provider
            # (nebelhaus.secrets.provider) into just that process, nothing
            # plaintext on disk. Anything you truly need in EVERY shell,
            # export in your HOST file's initContent (this is the public rice).
          '')
          ''
            # Nebelung zsh-syntax-highlighting colours (replaces catppuccin's
            # port). Sourced before the plugin loads — like catppuccin did —
            # which is fine: ZSH_HIGHLIGHT_STYLES is read at highlight time.
            source ${nebelungRoot}/zsh-syntax-highlighting/themes/catppuccin_${nbFlavor}-zsh-syntax-highlighting.zsh

            # Custom completions
            fpath=(~/.zsh-completions $fpath)

            ${lib.optionalString (builtins.elem "node" devCfg.languages) ''
              # fnm (Node version manager)
              export PATH="$HOME/.fnm:$PATH"
              eval "$(fnm env --use-on-cd --shell zsh)"
            ''}

            bindkey -e

            setopt appendhistory
            setopt sharehistory
            setopt hist_ignore_space
            setopt hist_ignore_all_dups
            setopt hist_save_no_dups
            setopt hist_ignore_dups
            setopt hist_find_no_dups

            zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
            zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
            zstyle ':completion:*' menu no

            # Auto-name the current zellij tab after the repo whenever you cd.
            if [[ -n "$ZELLIJ" ]]; then
              # New panes inherit the focused pane's cwd (Super p), as do the
              # cwd-injecting new-tab spawns (Super Shift t, the peek Enter-on-dir
              # tab) — which, next to a claude --worktree pane, is the agent's
              # throwaway checkout under ~/.cache/claude-worktrees. A fresh
              # interactive shell has no business starting there: hop to the repo
              # the worktree belongs to (the parent of the shared .git).
              # $CLAUDECODE spares the agent's own subshells, and $ZJ_STAY spares
              # the deliberate "stay here" spawns (Super Shift p, and the peek
              # Enter-on-dir tab) — those must stay in the worktree. Both fire
              # once at shell birth, so unset ZJ_STAY afterward to keep it out of
              # child processes and later cd's.
              if [[ -z "$CLAUDECODE" && -z "$ZJ_STAY" && "$PWD" == "$HOME/.cache/claude-worktrees/"* ]]; then
                _wt_main="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
                [[ -n "$_wt_main" ]] && cd "''${_wt_main:h}"
                unset _wt_main
              fi
              unset ZJ_STAY

              # "~" is what fresh tabs are born as (custom.kdl) — cd-ing back
              # to ~ returns the tab to that name instead of the login name.
              _zj_name_tab() {
                local root name
                if [[ "$PWD" == "$HOME" ]]; then
                  name="~"
                else
                  root=$(git rev-parse --show-toplevel 2>/dev/null)
                  name=''${''${root:-$PWD}:t}
                fi
                command zellij action rename-tab "$name" 2>/dev/null
              }
              autoload -Uz add-zsh-hook
              add-zsh-hook chpwd _zj_name_tab
            fi
          ''
        ];
      };

      # Starship, tinted with the Nebelung palette instead of the stock flavor (the
      # whiskers starship port emits exactly this [palettes.catppuccin_<flavor>]
      # table; we inject the same name->#hex map so there's no duplication).
      programs.starship = {
        enable = true;
        enableZshIntegration = true;
        settings = {
          gcloud.disabled = true;
          palette = "catppuccin_${nbFlavor}";
          palettes."catppuccin_${nbFlavor}" = nebelungPalette;
        };
      };

      # Git — identity comes from nebelhaus.git.* (your host sets it).
      programs.git = {
        enable = devCfg.git.enable;

        # Nebelung delta theme: defines [delta "catppuccin-<flavor>"] (referenced
        # by programs.delta.options.features below). Rendered by whiskers in the
        # nebelung flake; replaces the catppuccin.delta module's include.
        #
        # Gotcha worth keeping: this ONE file carries a section for all four
        # catppuccin flavors, and only the flavor it was rendered as holds Nebelung
        # colours — the other three are stock upstream. So `features` below must
        # name the same flavor as the variant root this include came from, or delta
        # silently themes itself in stock Catppuccin. Both read nbFlavor, which is
        # what keeps them agreeing.
        includes = [ { path = "${nebelungRoot}/delta/catppuccin.gitconfig"; } ];
        signing = lib.mkIf (gitCfg.signingKey != "") {
          key = gitCfg.signingKey;
          signByDefault = true;
        };
        settings = {
          user.name = gitCfg.name;
          user.email = gitCfg.email;
          color.ui = "auto";
          push.autoSetupRemote = true;
          tag.gpgSign = gitCfg.signingKey != "";
        };
      };

      programs.delta = {
        enable = devCfg.git.enable;
        enableGitIntegration = true;
        options = {
          side-by-side = false;
          line-numbers = true;
          # Nebelung delta styles: the [delta "catppuccin-<flavor>"] feature is
          # defined in the whiskers-rendered gitconfig included via
          # programs.git.includes above (see the flavor gotcha there). Its
          # syntax-theme points at the matching bat theme, in Nebelung colours.
          features = "catppuccin-${nbFlavor}";
        };
      };

      # Nebelung theme (mauve accent) injected straight into settings from
      # nebelungPalette — mirrors catppuccin/lazygit's theme for the selected
      # flavor in Nebelung colours (see the lazygit port in the nebelung repo for
      # the file form). Injected rather than sourced, so it follows the palette
      # without needing the flavor in a path.
      programs.lazygit = {
        enable = devCfg.git.enable;
        settings.gui = {
          theme = {
            activeBorderColor = [
              accentColor
              "bold"
            ];
            inactiveBorderColor = [ nebelungPalette.subtext0 ];
            searchingActiveBorderColor = [ nebelungPalette.yellow ];
            optionsTextColor = [ nebelungPalette.blue ];
            selectedLineBgColor = [ nebelungPalette.surface0 ];
            inactiveViewSelectedLineBgColor = [ nebelungPalette.overlay0 ];
            cherryPickedCommitFgColor = [ accentColor ];
            cherryPickedCommitBgColor = [ nebelungPalette.surface1 ];
            markedBaseCommitFgColor = [ nebelungPalette.blue ];
            markedBaseCommitBgColor = [ nebelungPalette.yellow ];
            unstagedChangesColor = [ nebelungPalette.red ];
            defaultFgColor = [ nebelungPalette.text ];
          };
          authorColors."*" = nebelungPalette.lavender;
        };
      };

      programs.lsd.enable = devCfg.toolbelt.enable;
      programs.lsd.enableZshIntegration = false;

      # Theme is the Nebelung-coloured "Catppuccin <Flavor>" tmTheme from the
      # nebelung flake. The UPSTREAM name is kept (rather than renamed to
      # "Nebelung") because delta's syntax-theme and yazi's syntect_theme both
      # reference it by that name — and the whiskers-rendered files on the other end
      # of those references are flavor-named too, so all three move together.
      # programs.bat.themes rebuilds the bat cache on activation so it's picked up.
      programs.bat = {
        enable = devCfg.toolbelt.enable;
        config = {
          style = "header,grid";
          tabs = "2";
          theme = batTheme;
        };
        themes.${batTheme} = {
          src = "${nebelungRoot}/bat/themes";
          file = "${batTheme}.tmTheme";
        };
      };

      programs.yazi = {
        enable = devCfg.toolbelt.enable;
        enableZshIntegration = true;
        shellWrapperName = "yy";
        settings.mgr.show_hidden = true;
        settings.mgr.ratio = [
          1
          4
          4
        ];
        # Default preview caps (600×900 px) leave kitty-protocol previews soft
        # on a retina display; size them for the near-fullscreen peek window.
        settings.preview.max_width = 2400;
        settings.preview.max_height = 1800;
        plugins = {
          # Vendored: nixpkgs' glow plugin still uses the pre-26 Lua API and
          # crashes on yazi 26.x. This copy ports it to the current API, and
          # bakes the Nebelung glamour style path in (glowPlugin, see the let).
          glow = glowPlugin;
          piper = pkgs.yaziPlugins.piper;
          # Vendored (not in nixpkgs yet): copy the hovered/selected file(s)'
          # contents — not their path — to the clipboard. `setup` makes
          # home-manager emit the require(...):setup() call in init.lua;
          # notification = a toast on copy so there's UI feedback.
          copy-file-contents = {
            package = ./yazi/plugins/copy-file-contents.yazi;
            setup = true;
            settings = {
              append_char = "\n";
              notification = true;
            };
          };
          # peek-open: Enter inside the Super-y peek overlay. On a directory it
          # spawns a new zellij tab cwd'd there (the old browse-and-pick tab
          # picker, folded in here); on a file it pages as normal. Gated on
          # PEEK=1 (set only by
          # peek-run.sh), so in a plain `yy` session it's a no-op passthrough to
          # yazi's default Enter. See yazi/plugins/peek-open.yazi.
          peek-open.package = ./yazi/plugins/peek-open.yazi;
        };
        keymap.mgr.prepend_keymap = [
          {
            on = "<Esc>";
            run = "quit";
            desc = "Close the peek browser";
          }
          {
            # cmd+c can't reach a TUI (the terminal eats the Cmd modifier), so
            # copy-contents lives on Y. `desc` surfaces it in yazi's help (~).
            on = "Y";
            run = "plugin copy-file-contents";
            desc = "Copy file contents to clipboard";
          }
          {
            # Enter routes through peek-open: in the peek overlay a directory
            # opens a new zellij tab there, a file pages fullscreen; everywhere
            # else it's plain `open` (yazi's default Enter). See peek-open.yazi.
            on = "<Enter>";
            run = "plugin peek-open";
            desc = "Peek: open dir as tab / page file (else default open)";
          }
        ];
        settings.plugin.prepend_previewers = [
          {
            url = "*.md";
            run = "glow";
          }
          {
            url = "*.mdx";
            run = "glow";
          }
          {
            mime = "text/*";
            run = batPreviewer;
          }
          {
            mime = "*/{xml,javascript,x-wine-extension-ini}";
            run = batPreviewer;
          }
          {
            mime = "application/{json,ndjson}";
            run = batPreviewer;
          }
        ];
        settings.opener = {
          read = [
            {
              run = ''glow -s "${glowStyle}" -p "$@"'';
              block = true;
              desc = "glow";
            }
          ];
          pager = [
            {
              run = ''bat --style=full --paging=always "$@"'';
              block = true;
              desc = "bat";
            }
          ];
          image_preview = [
            {
              run = ''~/.config/zellij/image-preview.sh "$@"'';
              block = true;
              desc = "Preview";
            }
          ];
          open = [
            {
              run = ''open "$@"'';
              orphan = true;
              desc = "Open";
            }
          ];
        };
        settings.open.rules = [
          {
            mime = "image/*";
            use = "image_preview";
          }
          {
            mime = "video/*";
            use = "open";
          }
          {
            mime = "audio/*";
            use = "open";
          }
          {
            mime = "application/pdf";
            use = "open";
          }
          {
            url = "*.md";
            use = "read";
          }
          {
            url = "*.mdx";
            use = "read";
          }
          {
            url = "*";
            use = "pager";
          }
        ];
      };

      programs.zoxide = {
        enable = devCfg.toolbelt.enable;
        enableZshIntegration = true;
        # Let zoxide take over `cd`: `cd proj` jumps by frecency, `cdi` opens
        # the interactive fzf picker. The chpwd hooks below (zellij tab-naming)
        # still fire — zoxide's cd triggers the same chpwd event as builtin cd.
        options = [ "--cmd cd" ];
      };

      # Nebelung colours injected from nebelungPalette (matches catppuccin/fzf's
      # --color mapping for the selected flavor, blue muted out). home-manager turns
      # these into the --color flags in FZF_DEFAULT_OPTS.
      programs.fzf = {
        enable = devCfg.toolbelt.enable;
        enableZshIntegration = true;
        colors = {
          "bg+" = nebelungPalette.surface0;
          "bg" = nebelungPalette.base;
          "spinner" = nebelungPalette.rosewater;
          "hl" = nebelungPalette.red;
          "fg" = nebelungPalette.text;
          "header" = nebelungPalette.red;
          "info" = accentColor;
          "pointer" = nebelungPalette.rosewater;
          "marker" = nebelungPalette.lavender;
          "fg+" = nebelungPalette.text;
          "prompt" = accentColor;
          "hl+" = nebelungPalette.red;
          "selected-bg" = nebelungPalette.surface1;
          "border" = nebelungPalette.overlay0;
          "label" = nebelungPalette.text;
        };
      };

      programs.helix = {
        enable = true;
        settings = {
          theme = "nebelung";
          editor = {
            line-number = "relative";
            mouse = true;
            cursorline = true;
            color-modes = true;
            cursor-shape = {
              normal = "block";
              insert = "bar";
              select = "underline";
            };
            file-picker = {
              hidden = false;
            };
            lsp = {
              display-messages = true;
            };
            statusline = {
              left = [
                "mode"
                "spinner"
              ];
              center = [ "file-name" ];
              right = [
                "diagnostics"
                "selections"
                "position"
                "file-encoding"
                "file-line-ending"
                "file-type"
              ];
              separator = "│";
              mode = {
                normal = "NORMAL";
                insert = "INSERT";
                select = "SELECT";
              };
            };
          };
        };
      };

      programs.zellij.enable = true;

      # Catppuccin: `catppuccin.flavor` is the single source of truth — every
      # integration follows it. Raw dotfiles nix can't inject into (ghostty
      # config, zellij config.kdl) name the flavor manually; keep them in sync.
      # Every port here is themed by Nebelung instead of stock catppuccin —
      # either by pointing the program at a whiskers-rendered file from the
      # nebelung flake (bat/delta/lsd/yazi), or by injecting nebelungPalette
      # colours straight into the program's settings (starship/fzf/lazygit).
      # Each catppuccin integration is disabled so it doesn't clobber our wiring.
      # Colours are Nebelung; the upstream catppuccin *names* are kept (nebelung's
      # own convention — its ghostty output is literally catppuccin-<flavor>.conf),
      # which is why nbFlavor turns up in so many paths here.
      catppuccin.autoEnable = true;
      catppuccin.enable = true;
      catppuccin.flavor = nbFlavor;
      catppuccin.bat.enable = false;
      catppuccin.starship.enable = false;
      catppuccin.delta.enable = false;
      catppuccin.fzf.enable = false;
      catppuccin.glamour.enable = false; # GLAMOUR_STYLE wired to nebelung above
      catppuccin.helix.enable = false;
      catppuccin.lazygit.enable = false;
      catppuccin.lsd.enable = false;
      catppuccin.yazi.enable = false;
      catppuccin.zsh-syntax-highlighting.enable = false;
      catppuccin.zellij.enable = false; # managed as a raw dotfile below

      # nix-index + comma (`, foo` runs a program without installing it):
      # unambiguously developer tooling, and the index is not small, so a
      # machine with the pack off shouldn't carry it.
      programs.nix-index = {
        enable = devCfg.enable;
        enableZshIntegration = devCfg.enable;
      };
      programs.nix-index-database.comma.enable = devCfg.enable;

      programs.home-manager.enable = true;

      # Zen browser — drop the Nebelung userChrome/userContent into every Zen
      # profile. Zen's chrome lives INSIDE the (randomly-named) browser profile,
      # not under XDG, so home.file can't target it — we symlink into each
      # Profiles/*/chrome at activation instead. Symlinks (not copies) so a
      # palette rebuild propagates like every other port. Also flips on Firefox's
      # legacy userChrome/userContent stylesheets, which fresh profiles ship off.
      # Zen isn't installed here (themed-but-manual); the loop no-ops if absent.
      home.activation.zenNebelung = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        zenProfiles="$HOME/Library/Application Support/zen/Profiles"
        if [ -d "$zenProfiles" ]; then
          for prof in "$zenProfiles"/*/; do
            [ -d "$prof" ] || continue
            chrome="$prof"chrome
            $DRY_RUN_CMD mkdir -p "$chrome"
            $DRY_RUN_CMD ln -sf "${zenTheme}/userChrome.css" "$chrome/userChrome.css"
            $DRY_RUN_CMD ln -sf "${zenTheme}/userContent.css" "$chrome/userContent.css"
            userjs="$prof"user.js
            if [ ! -e "$userjs" ] || ! ${pkgs.gnugrep}/bin/grep -qF \
                'toolkit.legacyUserProfileCustomizations.stylesheets' "$userjs"; then
              printf '%s\n' 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' \
                | $DRY_RUN_CMD tee -a "$userjs" >/dev/null
            fi
          done
        fi
      '';

      # Obsidian stores theme choice inside each vault rather than in one app
      # config. Only touch explicitly listed, already-existing vaults: copy the
      # generated full theme from the store, then JSON-merge our two appearance
      # choices so Obsidian keeps ownership of every unrelated setting. Copies
      # are deliberate: these directories often sync through iCloud, where a
      # /nix/store symlink would be dangling on every other device.
      home.activation.obsidianNebelung = lib.mkIf (hearthCfg.obsidianVaults != [ ]) (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          installObsidianNebelung() {
            vaultRel="$1"
            vault="$HOME/$vaultRel"
            obsidian="$vault/.obsidian"

            if [ ! -d "$obsidian" ]; then
              echo "warning: Obsidian vault has no .obsidian directory; skipping: $vault" >&2
              return 0
            fi

            themeDir="$obsidian/themes/Nebelung"
            $DRY_RUN_CMD mkdir -p "$themeDir"
            $DRY_RUN_CMD install -m 0644 "${obsidianTheme}/theme.css" "$themeDir/theme.css"
            $DRY_RUN_CMD install -m 0644 "${obsidianTheme}/manifest.json" "$themeDir/manifest.json"

            run sh -c '
              appearance="$0"
              tmp="$appearance.hm-seed"
              base="$appearance"
              if [ ! -s "$appearance" ]; then
                base="$tmp.base"
                printf "{}\n" > "$base"
              fi
              if ! ${pkgs.jq}/bin/jq ".cssTheme = \"Nebelung\"
                | .theme = \"obsidian\"
                | .enabledCssSnippets = ((.enabledCssSnippets // []) | map(select(. != \"nebelung\")))" \
                "$base" > "$tmp"; then
                rm -f "$tmp" "$tmp.base"
                exit 1
              fi
              mv "$tmp" "$appearance"
              rm -f "$tmp.base"
            ' "$obsidian/appearance.json"
          }

          ${lib.concatMapStringsSep "\n" (
            vault: "installObsidianNebelung ${lib.escapeShellArg vault}"
          ) hearthCfg.obsidianVaults}
          unset -f installObsidianNebelung
        ''
      );

      # ---- dotfiles + Nebelung theme drops ----
      home.file = {
        # Claude Code global memory — cross-project operating context, supplied
        # by the host via nebelhaus.claude.globalMd, with the rice's own `wt`
        # worktree rule prepended (wtGuidance, see the let). Unset (option empty)
        # = no file written, so ~/.claude/CLAUDE.md stays hand-managed and the
        # rice never clobbers a by-hand file just to inject its note.
        ".claude/CLAUDE.md" = lib.mkIf (claudeCfg.globalMd != "") {
          text = wtGuidance + claudeCfg.globalMd;
        };
      }
      // lib.optionalAttrs claudeCfg.skill {
        # The nebelhaus skill (nebelhaus.claude.skill). Installed file-by-file
        # rather than as one directory symlink so this-machine.md — rendered
        # from THIS host, not from the rice — can sit inside the same skill
        # alongside the store-built parts.
        ".claude/skills/nebelhaus/SKILL.md".source = "${claudeSkill}/SKILL.md";
        ".claude/skills/nebelhaus/references/options.md".source = "${claudeSkill}/references/options.md";
        ".claude/skills/nebelhaus/references/recipes.md".source = "${claudeSkill}/references/recipes.md";
        ".claude/skills/nebelhaus/references/this-machine.md".text = thisMachine;

        # A starter CLAUDE.md for ~/.config/nix, parked in the skill rather than
        # written into that repo: it's the user's own git repo, and a read-only
        # store symlink inside it would be a thing they can't commit. `haus
        # doctor` points at this path, and the skill tells the agent to offer the
        # copy — so it lands as a real, editable file or not at all.
        ".claude/skills/nebelhaus/consumer-CLAUDE.md".source = "${claudeSkill}/consumer-CLAUDE.md";
      }
      // {

        # opencode
        ".config/opencode/themes/nebelung.json".source = "${nebelungRoot}/opencode/nebelung.json";
        ".config/opencode/tui.json".text = ''
          {
            "$schema": "https://opencode.ai/tui.json",
            "theme": "nebelung"
          }
        '';

        # Helix nebelung theme, from the nebelung flake. This used to be a
        # hand-written [palette] block inheriting helix's BUILT-IN
        # catppuccin_<flavor>; nebelung now carries the real catppuccin/helix
        # port, so the theme comes rendered like every other tool here and the
        # syntax scopes track upstream instead of whatever helix ships.
        # Kept under the `nebelung` name that programs.helix.settings.theme
        # points at (the port also renders a no_italics/ sibling).
        ".config/helix/themes/nebelung.toml".source =
          "${nebelungRoot}/helix/themes/default/catppuccin_${nbFlavor}.toml";

        # ghostty (config lives in Application Support; theme lookup is XDG)
        # ghostty's `command` runs the zellij launcher by absolute path; render
        # @HOME@ → the user's home so it isn't pinned to one account.
        "Library/Application Support/com.mitchellh.ghostty/config".text =
          builtins.replaceStrings
            [ "@HOME@" "@FONT_FAMILY@" "@FONT_SIZE@" ]
            [
              config.home.homeDirectory
              fontsCfg.mono.name
              (toString fontsCfg.mono.size)
            ]
            (builtins.readFile ./ghostty/config);
        ".config/ghostty/themes/nebelung".source =
          "${nebelungRoot}/ghostty/themes/catppuccin-${nbFlavor}.conf";

        # lsd colours (replaces catppuccin.lsd). lsd auto-reads this file.
        ".config/lsd/colors.yaml".source = "${nebelungRoot}/lsd/themes/catppuccin-${nbFlavor}/colors.yaml";

        # yazi theme (replaces catppuccin.yazi): mgr/status/mode palette (mauve
        # accent) plus the syntect theme its syntect_theme line points at —
        # reusing the Nebelung bat tmTheme so previews match bat.
        ".config/yazi/theme.toml".source =
          "${nebelungRoot}/yazi/themes/${nbFlavor}/catppuccin-${nbFlavor}-${accent}.toml";
        # This target's NAME is pinned by the rendered theme.toml above: its
        # syntect_theme line reads ~/.config/yazi/Catppuccin-<flavor>.tmTheme, so it
        # has to carry the flavor or yazi's code previews lose their colours.
        ".config/yazi/Catppuccin-${nbFlavor}.tmTheme".source =
          "${nebelungRoot}/bat/themes/${batTheme}.tmTheme";

        # zellij
        # config.kdl bakes absolute script paths (zellij doesn't expand $HOME in
        # copy_command / Run / layout), so render @HOME@ → the user's home.
        ".config/zellij/config.kdl".text =
          builtins.replaceStrings
            [ "@HOME@" "@DEFAULT_MODE@" "@ZRELOAD@" ]
            [
              config.home.homeDirectory
              (if hearthCfg.zellijStartLocked then "locked" else "normal")
              "${zellijReload}/bin/zreload"
            ]
            (builtins.readFile ./zellij/config.kdl);
        ".config/zellij/themes/nebelung.kdl".source = "${nebelungRoot}/zellij/themes/nebelung.kdl";
        # Custom layout, rendered from the in-repo template (see zellijLayout
        # in the let above).
        ".config/zellij/layouts/custom.kdl".text = zellijLayout;
        # The same layout with the content tab pinned to $HOME — the Super-t
        # NewTab bind opens tabs from this file, so a plain new tab always starts
        # at ~ no matter where the focused pane lives (Super-Shift-t is the "…at
        # the focused dir" variant — new-tab-here.sh). Tab-level cwd is the only
        # form zellij honors under a default_tab_template (peek-run.sh and
        # new-tab-here.sh pull the same trick per-pick); the assert trips at eval
        # time if custom.kdl's
        # content-tab line ever changes shape, instead of silently shipping a
        # layout that no-ops back to cwd inheritance.
        ".config/zellij/layouts/home.kdl".text =
          let
            pinned =
              builtins.replaceStrings
                [ "\n    tab name=\"~\" {\n" ]
                [ "\n    tab cwd=\"${config.home.homeDirectory}\" name=\"~\" {\n" ]
                zellijLayout;
          in
          assert pinned != zellijLayout;
          pinned;
        ".config/zellij/plugins/link-handler.wasm".source = ./zellij/plugins/zellij_link_handler.wasm;
        # tab-history (see zellij/tab-history/): background plugin that makes
        # Ctrl(+Shift)+Tab walk tabs in most-recently-used order (browser-style
        # back/forward) instead of by position. Loaded via config.kdl's
        # load_plugins; grants seeded below. Wasm vendored by its build.sh.
        ".config/zellij/plugins/tab-history.wasm".source = ./zellij/plugins/zellij_tab_history.wasm;
        # Our status-bar fork (see zellij/status-bar/): the bottom-right quick
        # hints are condensed to one flat "Super + <c,p,t,y,f>" block (claude,
        # pane, tab, yazi-peek, fullscreen — keys only, no labels/ribbons).
        # Wasm vendored by its build.sh.
        ".config/zellij/plugins/status-bar.wasm".source = ./zellij/plugins/zellij_status_bar.wasm;
        # Our tab-bar fork (see zellij/tab-bar/): the top bar, replacing the
        # third-party zjstatus that used to sit here. Same active-anchored tab
        # scroll viewport as upstream zellij:tab-bar (so tabs stay readable on a
        # thin pane instead of clipping under the right-hand widgets, which is
        # what zjstatus did), themed to nebelung, with a username pill + a
        # Ctrl+Tab / swap-layout right side. Wasm vendored by its build.sh.
        ".config/zellij/plugins/tab-bar.wasm".source = ./zellij/plugins/zellij_tab_bar.wasm;
        ".config/zellij/launch.sh" = {
          source = ./zellij/launch.sh;
          executable = true;
        };
        ".config/zellij/image-preview.sh" = {
          source = ./zellij/image-preview.sh;
          executable = true;
        };
        ".config/zellij/peek.sh" = {
          source = ./zellij/peek.sh;
          executable = true;
        };
        ".config/zellij/peek-run.sh" = {
          source = ./zellij/peek-run.sh;
          executable = true;
        };
        # Super-Shift-t: open a new tab cwd'd at the focused pane's dir (clones
        # the active layout + injects a tab-level cwd). See config.kdl's bind.
        ".config/zellij/new-tab-here.sh" = {
          source = ./zellij/new-tab-here.sh;
          executable = true;
        };
        # The one floating-Ghostty helper (geom + spawn); peek.sh, the Rebuild
        # System pounce command, and the agent-peek popup all route through it.
        ".config/zellij/float-term.sh" = {
          source = ./zellij/float-term.sh;
          executable = true;
        };
        # The one "open in the editor" launcher — a new zellij tab running
        # nebelhaus.hearth.editor (baked into @editor@). Shared by the "Nix
        # Config" palette/bar commands and the file-association hijack.
        ".config/zellij/editor-open-pane.sh" = {
          text = builtins.replaceStrings [ "@editor@" ] [ hearthCfg.editor ] (
            builtins.readFile ./zellij/editor-open-pane.sh
          );
          executable = true;
        };
        # pounce's terminal launcher (POUNCE_TERMINAL_LAUNCHER, wired in
        # modules/pounce) — opens `ssh <host>` etc. in a new `main`-session tab,
        # same flow as editor-open-pane.sh above.
        ".config/zellij/pounce-terminal.sh" = {
          source = ./zellij/pounce-terminal.sh;
          executable = true;
        };
        # The one "open the nix config" opener — resolves this host's
        # hosts/@hostname@/default.nix and hands it to the launcher above with
        # the flake root as cwd. The "Nix Config" palette command (pounce) and
        # the bar's nix pill (sill) both exec this.
        ".config/zellij/nix-config-open.sh" = {
          text = builtins.replaceStrings [ "@hostname@" ] [ hostname ] (
            builtins.readFile ./zellij/nix-config-open.sh
          );
          executable = true;
        };
        ".config/zellij/yazi-shell.sh" = {
          source = ./zellij/yazi-shell.sh;
          executable = true;
        };
        ".config/zellij/copy-clean.pl" = {
          source = ./zellij/copy-clean.pl;
          executable = true;
        };
      };

      # zellij grants plugin permissions through an interactive (y/n) prompt in
      # the plugin's pane — but none of our forks can answer it: link-handler is
      # a background plugin (load_plugins) with no pane, status-bar never calls
      # request_permission (built-ins don't need to, and we keep the fork diff
      # minimal), and tab-bar's "pane" is a 1-line borderless bar you can't
      # select — so its prompt renders in the bar but no keystroke ever reaches
      # it. An ungranted plugin therefore sits event-less forever (zellij only
      # auto-grants when EVERY requested permission is cached).
      # Seed the grants straight into zellij's permission cache instead (keyed
      # by the plugin's expanded path): replace our plugin's block wholesale so
      # permission-list changes propagate, but never own the file — zellij
      # rewrites it when other plugins are granted interactively, so those
      # entries must survive.
      #
      # OPERATIONAL GOTCHA — a live server can clobber a fresh seed, and only a
      # bounce fixes it. zellij re-reads this file whenever a plugin requests
      # permission, so a seed normally takes effect on the next plugin load. But
      # a running server also *rewrites* the file from its own in-memory
      # snapshot (whenever any plugin is granted), which can drop a grant this
      # activation just wrote. So when a rebuild changes a bar plugin's wasm,
      # the next new tab can surface the un-answerable prompt above even though
      # the seed ran — the seed and the running server race for the file. The
      # seed alone can't win that race (zellij owns the file at runtime); the
      # fix is to bounce the server so it reloads the seeded file cleanly:
      #     zellij kill-session <name> && zellij attach --create <name>
      # serialize_pane_viewport is on, so pane layouts + scrollback resurrect
      # (live processes don't — re-run them). `bench try switch` (or any
      # rebuild) re-runs this seed; the bounce is what makes an already-running
      # server honour it.
      home.activation.zellijLinkHandlerPermissions = seedZellijPluginPermissions "link-handler.wasm" [
        "ReadApplicationState"
        "ChangeApplicationState"
        "FullHdAccess"
        "RunCommands"
        "ReadSessionEnvironmentVariables"
      ];
      # ModeUpdate/TabUpdate/PaneUpdate — everything the bar renders from —
      # are gated on ReadApplicationState (zellij's check_event_permission).
      home.activation.zellijStatusBarPermissions = seedZellijPluginPermissions "status-bar.wasm" [
        "ReadApplicationState"
      ];
      # tab-history reads TabUpdate (ReadApplicationState) to track focus order
      # and calls go_to_tab (ChangeApplicationState) to switch tabs; both are
      # pre-seeded because it's a background plugin with no pane to prompt in.
      home.activation.zellijTabHistoryPermissions = seedZellijPluginPermissions "tab-history.wasm" [
        "ReadApplicationState"
        "ChangeApplicationState"
      ];
      # tab-bar renders from TabUpdate/ModeUpdate/PaneUpdate (ReadApplicationState)
      # and switches tabs on a mouse click via switch_tab_to
      # (ChangeApplicationState). ReadCliPipes is for the agent-status paw beside
      # a tab name: sill's agents-hook.sh broadcasts each agent pane's state over
      # `zellij pipe`, and without this permission that pipe never reaches the
      # plugin. NOTE it can't be treated as optional — zellij only auto-grants
      # when EVERY requested permission is cached, so if this list falls behind
      # the wasm's request_permission() the whole bar goes event-less, not just
      # the paws. It's the top bar, so its prompt would render in a 1-line
      # borderless pane you can't select — un-answerable (see the note above),
      # which is exactly why it must be seeded rather than left to prompt.
      home.activation.zellijTabBarPermissions = seedZellijPluginPermissions "tab-bar.wasm" [
        "ReadApplicationState"
        "ChangeApplicationState"
        "ReadCliPipes"
      ];

      # File-association hijack — opt-in (nebelhaus.hearth.hijackFileAssociations).
      # Off by default: silently making EditorOpen.app the handler for a dozen
      # extensions is a jarring, hard-to-undo surprise on someone else's machine.
      # It opens files in the rice editor (nebelhaus.hearth.editor) via the same
      # zellij launcher the palette/bar use.
      home.activation.editorOpenApp = lib.mkIf hearthCfg.hijackFileAssociations (
        lib.hm.dag.entryAfter [ "writeBoundary" ] (
          let
            # Extensions EditorOpen.app claims as an Editor (see the "declare in
            # the app" note in the script). Deliberately EXCLUDES web-content
            # types (html/htm/xhtml — browsers own public.html and won't yield,
            # and you want those in a browser anyway) and image types (handled by
            # the zellij link-handler's image preview).
            editorExts = [
              "json" "jsonc" "txt" "md" "mdx" "markdown" "rst" "adoc" "org"
              "ts" "tsx" "mts" "cts" "js" "jsx" "mjs" "cjs"
              "rs" "go" "py" "rb" "lua" "pl" "php" "java" "kt" "kts" "swift" "scala" "clj"
              "c" "h" "cc" "cpp" "hpp" "hh" "cs"
              "nix" "toml" "yaml" "yml" "kdl" "conf" "ini" "cfg" "properties" "env"
              "css" "scss" "sass" "less" "styl"
              "vue" "svelte" "astro"
              "sh" "bash" "zsh" "fish" "vim" "ps1"
              "sql" "graphql" "gql" "prisma" "proto"
              "xml" "csv" "tsv" "diff" "patch" "log" "lock" "tex" "bib"
              "editorconfig" "gitignore" "gitattributes" "dockerignore" "npmrc"
            ];
            # NOTE on extensionless executables (`bench` & friends): they're
            # typed public.unix-executable and RUN in Terminal on click. That one
            # can't be automated here — macOS gates changing the executable
            # handler behind an INTERACTIVE confirmation dialog that
            # `darwin-rebuild switch` can't answer (and neither declaration nor
            # lsregister overrides Terminal's claim). To send them to the editor,
            # run once by hand and click through the prompt:
            #   duti -s org.nebelhaus.editoropen public.unix-executable all
            plistBuddy = "/usr/libexec/PlistBuddy";
            lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister";
            # One PlistBuddy "Add …:CFBundleTypeExtensions:<i> string <ext>" per
            # extension, index-ordered.
            declareExts = lib.concatStringsSep "\n" (lib.imap0 (
              i: ext:
              ''$DRY_RUN_CMD ${plistBuddy} -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions:${toString i} string ${ext}" "$PL"''
            ) editorExts);
            dutiPins = lib.concatStringsSep "\n" (map (
              t: ''$DRY_RUN_CMD "${pkgs.duti}/bin/duti" -s org.nebelhaus.editoropen "${t}" all 2>/dev/null || true''
            ) editorExts);
          in
          ''
            appDir="$HOME/Applications"
            $DRY_RUN_CMD mkdir -p "$appDir"
            $DRY_RUN_CMD /usr/bin/osacompile -o "$appDir/EditorOpen.app" -e 'on open theFiles' -e 'repeat with theFile in theFiles' -e 'set file_path to POSIX path of theFile' -e 'do shell script "$HOME/.config/zellij/editor-open-pane.sh " & quoted form of file_path' -e 'end repeat' -e 'end open'
            PL="$appDir/EditorOpen.app/Contents/Info.plist"
            $DRY_RUN_CMD /usr/bin/plutil -replace CFBundleIdentifier -string "org.nebelhaus.editoropen" "$PL"

            # Declare the file types EditorOpen.app owns IN THE APP ITSELF — not
            # just via duti. This is load-bearing: `duti -s <ext>` can only bind an
            # extension whose UTI some installed app already declares; for a type
            # nothing else on the machine declares (rs, go, kdl, lua, fish, …) duti
            # hits a FATAL LaunchServices -50 and silently no-ops, so those files
            # keep opening in nothing/Terminal. Declaring the extension here
            # materializes its UTI and registers this app as the owner, and
            # `lsregister -f` makes it the default — even beating an existing owner
            # (a bare .py that would otherwise open in Xcode). Delete-first keeps
            # the block idempotent across re-activations.
            $DRY_RUN_CMD ${plistBuddy} -c "Delete :CFBundleDocumentTypes" "$PL" 2>/dev/null || true
            $DRY_RUN_CMD ${plistBuddy} -c "Add :CFBundleDocumentTypes array" "$PL"
            $DRY_RUN_CMD ${plistBuddy} -c "Add :CFBundleDocumentTypes:0 dict" "$PL"
            $DRY_RUN_CMD ${plistBuddy} -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string Source" "$PL"
            $DRY_RUN_CMD ${plistBuddy} -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Editor" "$PL"
            $DRY_RUN_CMD ${plistBuddy} -c "Add :CFBundleDocumentTypes:0:LSHandlerRank string Owner" "$PL"
            $DRY_RUN_CMD ${plistBuddy} -c "Add :CFBundleDocumentTypes:0:CFBundleTypeExtensions array" "$PL"
            ${declareExts}

            # Register the freshly-declared bundle so LaunchServices sees the new
            # types before we pin defaults against them.
            $DRY_RUN_CMD ${lsregister} -f "$appDir/EditorOpen.app" 2>/dev/null || true

            # Belt-and-suspenders: pin us as the *user default* for every type
            # where the UTI is bindable. duti prints (and this swallows) a benign
            # -50 on the pure-dynamic types the declaration above already handled;
            # a real failure isn't worth aborting activation over.
            if [ -x "${pkgs.duti}/bin/duti" ]; then
            ${dutiPins}
            fi
          ''
        )
      );

      # Claude Code — seed a couple of defaults into settings.json:
      #   permissions.defaultMode = "auto"  — pin the permission mode here
      #     instead of passing --dangerously-skip-permissions on the command
      #     line (the zellij binds above no longer do). "auto" runs agents
      #     unattended but keeps the background safety checks that block
      #     dangerous escalations, so it's safe on the host — unlike
      #     bypassPermissions, which is the flag's exact, check-free behaviour
      #     and wants a container.
      #   tui = "fullscreen"  — render Claude Code in the alt-screen (fullscreen)
      #     TUI rather than inline. `/tui fullscreen` sets this per-session and
      #     relaunches; seeding it makes fullscreen the default on every new
      #     machine. Highlight-to-copy through zellij still works, so there's no
      #     tradeoff to the classic inline renderer.
      #   disableAgentView = true  — turn off the built-in agent-manager view
      #     (`claude agents`, `--bg`, /background, its on-demand daemon) and the
      #     "← for agents" toolbar hint that advertises it. Undocumented key,
      #     equivalent to CLAUDE_CODE_DISABLE_AGENT_VIEW=1. Parallel Claude
      #     sessions here go through `wt` + zellij panes (den/hearth), not the
      #     in-app view, so the hint is pure noise — kill it at the rice level.
      #   statusLine  — point Claude Code's status bar at `claude-statusline`
      #     (den ships it on PATH). It renders THIS session's `wt` worktree +
      #     the sister worktrees in flight across every repo — the agent-worktree
      #     HUD the built-in bar can't give. refreshInterval keeps the sister
      #     list current while the main session sits idle watching other panes.
      #     It is also the ONLY feed behind sill's `claudeUsage` pill — Claude
      #     Code hands the statusline its rate-limit percentages and nothing
      #     else on this machine sees them — so unsetting this key freezes that
      #     pill (it greys itself out after 30 minutes rather than lying).
      #   spinnerTipsEnabled = false  — drop the rotating "Tip:" line under the
      #     spinner; the status bar already carries the context that matters.
      #     (The built-in mode/`esc to interrupt` footer badge has no such knob
      #     in Claude Code — statusLine renders above it and can't replace it.)
      #   footerLinksRegexes  — CC scans conversation output for these patterns
      #     and renders a native, clickable badge in the footer for each hit. We
      #     match GitHub `owner/repo#N` shorthand → the PR's github.com page, so
      #     a family PR reference anywhere in the transcript is one click away.
      #     This is the maintained clickable-PR path: CC 2.1.3+ STRIPS the OSC 8
      #     hyperlinks the statusline (den/statusline.sh) emits for its "#N" PR
      #     pills — colored but no longer ⌘-clickable (upstream regression,
      #     anthropics/claude-code#21586). footerLinksRegexes needs no OSC 8, so
      #     it survives that. Note it's a DIFFERENT surface (the footer, keyed
      #     off conversation text) — it doesn't restore clickability to the
      #     statusline pills themselves; those relight if/when CC stops filtering.
      #     Pattern uses char classes ([0-9], not \d) on purpose: a backslash
      #     would have to survive the nix'' → sh"" → jq"" escaping layers below.
      # Claude owns settings.json (it rewrites the file as plugins/statusline/
      # permission grants change), so we merge our keys in at activation and
      # never own it — every other key it holds must survive. jq is pinned from
      # the store because activation runs with a bare PATH.
      # Claude Code settings/hooks/statusline are agent tooling; a machine that
      # runs no agents should not have its ~/.claude/settings.json rewritten.
      home.activation.claudeCodeSettings = lib.mkIf devCfg.agents.enable (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run sh -c '
          settings="$0"
          mkdir -p "''${settings%/*}"
          tmp="$settings.hm-seed"
          if [ -s "$settings" ]; then base="$settings"; else base="$tmp.base"; printf "{}" > "$base"; fi
          ${pkgs.jq}/bin/jq ".permissions.defaultMode = \"auto\"
            | .tui = \"fullscreen\"
            | .disableAgentView = true
            | .spinnerTipsEnabled = false
            | .statusLine = {type: \"command\", command: \"/run/current-system/sw/bin/claude-statusline\", refreshInterval: 12}
            | .footerLinksRegexes = [{type: \"regex\", pattern: \"(?<owner>[A-Za-z0-9_.-]+)/(?<repo>[A-Za-z0-9_.-]+)#(?<pr>[0-9]+)\", url: \"https://github.com/{owner}/{repo}/pull/{pr}\", label: \"{repo}#{pr}\"}]" \
            "$base" > "$tmp"
          mv "$tmp" "$settings"
          rm -f "$tmp.base"
        ' "$HOME/.claude/settings.json"
      ''
      );
    };
}

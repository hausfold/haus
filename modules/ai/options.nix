# The AI room's option surface: `haus.ai.*`.
#
# These declarations lived in modules/options.nix — the file for what no single
# room owns — because the AI capability had no room to live in. It has one now
# (modules/ai), and the whole namespace moved with it: `haus.agents.*` became
# `haus.ai.*`, and the switch that sat outside it altogether
# (`haus.developer.agents.enable`) became `haus.ai.enable`. One room, one
# namespace, one on/off. No aliases — modules/moved.nix says why.
#
# The room is the first proof of the cross-room contract in
# `docs/model.md`: AI OWNS the capability, and the rooms that present it
# (Development's terminal binds, the Bar's pill, the Launcher's commands) own
# the extension points it writes to. See modules/ai/default.nix.
{ lib, config, ... }:

let
  # Every coding-agent client haus knows how to install, spawn and resume —
  # read by ai.clients, ai.default, and bar's aiUsage.provider, so none
  # of the three can drift apart. modules/lib/agents.nix says why it lives there
  # rather than here, and names the one copy that can't be folded in.
  agentClients = import ../lib/agents.nix;
in
{
  options.haus = {
    ai.enable = lib.mkOption {
      type = lib.types.bool;
      # Rooms are independent. hacker selects AI in its desktop; the neutral
      # room catalogue leaves it off until a desktop or host asks for it.
      default = false;
      defaultText = lib.literalExpression "false";
      description = ''
        The AI room: coding-agent *tooling*. `scruff` (agent worktrees),
        `factory` (merge the pull requests a filter you typed can vouch for,
        while nobody is watching — its policy and its merge lease are
        machine-local files, never options here),
        `agent-state` (the status writer behind the `agents` bar pill),
        the agent-worktree statusline, `tart` and the adapter that drives it
        (SPEC.md §5.5 — `scruff runtime up|enter|down --backend tart` stands a
        lane up in its own headless macOS, so an agent can feel-test a desktop
        change without touching the screen its user is sitting at; pulling a
        base image is still a manual, one-time step), and the client
        config the Terminal room writes (Claude Code's settings.json keys, opencode's
        agent-state plugin). Which clients get installed is `ai.clients`.

        On, this room brings its clients, `scruff` and the lifecycle wiring on its
        own. What it adds to OTHER rooms it adds only when they are present: the
        `c` alias arrives with the terminal, the
        `agents` pill with the bar, the agent commands with the launcher. None
        of those rooms is switched on by turning this one on.

        Off is right for any machine not running coding agents — it's a large
        surface a non-developer never sees. The neutral default installs no
        clients; a desktop that selects this room names both `ai.clients` and
        `ai.default`.

        Was `haus.developer.agents.enable`, and the rest of this namespace was
        `haus.agents.*`, until 2026-08-13. Neither spelling is aliased — see
        modules/moved.nix for why.
      '';
    };

    ai.clients = lib.mkOption {
      type = lib.types.listOf (lib.types.enum agentClients);
      default = [ ];
      defaultText = lib.literalExpression "[ ]";
      example = [
        "claude"
        "codex"
      ];
      description = ''
        Which coding-agent clients to install. `claude` is Claude Code, `codex`
        is OpenAI Codex, `opencode` is OpenCode, `pi` is pi. The ⌘↵ lane chord
        starts whichever one `ai.default` names, all of them through
        `scruff new`.

        `pi` brings one thing the other three don't: `ai.pi.packages`, the
        third-party resources it loads. See there before installing it.

        A list rather than one bool per client, matching `developer.languages`
        — a client added later doesn't change this option's shape.

        This is the option that makes `ai.default` honest. Naming a client
        you have not installed used to fail *at spawn time*, inside the pane,
        after the worktree already existed: a flash of
        `codex is unavailable`, and litter to reap. `ai.default` must now
        be a member of this list, so the same mistake fails the rebuild
        instead, with both values named.

        Override a client's package the usual Nix way — an overlay on
        `claude-code`, `codex`, `opencode` or `pi-coding-agent` — rather than
        dropping the client here and installing your own copy alongside; two
        derivations shipping the same `bin/` name collide in one profile.

        Two of them are held ahead of nixpkgs already, and an overlay of yours
        lands on top of that rather than beside it. `claude` is one: Claude
        Code gates models on the client version and nixpkgs trails the
        releases by weeks, so a stock pin means Fable 5.1 sits greyed out in
        `/model` for no visible reason. `pi` is the other: below 0.84.3 every
        lane spawned with a prompt dies. Both step aside once nixpkgs passes
        them. Your overlay sees the pinned build as `prev`, so patching it is
        the same one-liner it always was, though a wrapper that drops
        `version` and `meta` also drops the rebuild-time check that the floor
        is still met.

        Ignored entirely when `ai.enable` is off — see `haus._ai.clients`, the
        resolved list every room actually installs from. Before step 4 this was
        an assertion instead ("clients are set but the room is off"), which was
        right while the list defaulted from the room's own switch and wrong
        afterwards: a desktop names the clients, so a host turning the room off
        would have had to blank the desktop's list as well to get a rebuild at
        all. One switch now removes the room, which is what "clean removal when
        disabled" means.
      '';
    };

    # The list as the rest of haus must read it. `ai.clients` is what
    # somebody WROTE; this is what this machine actually installs, which is the
    # same thing gated on the room being on at all. Internal, because it is a
    # resolution rather than a setting — see modules/lib/contrib.nix for the
    # same reasoning applied to cross-room wiring.
    _ai.clients = lib.mkOption {
      internal = true;
      readOnly = true;
      type = lib.types.listOf (lib.types.enum agentClients);
      default = lib.optionals config.haus.ai.enable config.haus.ai.clients;
      description = "Resolved coding-agent clients: `ai.clients` when the AI room is on, else none.";
    };

    ai.default = lib.mkOption {
      type = lib.types.enum agentClients;
      default = "claude";
      example = "codex";
      description = ''
        The coding agent started by the ⌘↵ lane chord, by the palette's
        **Spawn Agent** command and by the `c` shell
        alias, and used to reopen worktrees with no client recorded yet. Each spawned worktree records its
        own client, so changing this affects new work but never reopens an
        existing Codex or OpenCode task in Claude.

        Must be one of `ai.clients` — see there.

        It is the DEFAULT, not the only answer, in one place: Spawn Agent's
        prompt box carries a `⇥` chip that cycles between the clients actually
        on `PATH`, so a single lane can open in another one without changing
        this. The chip is the exception that proves the rule — the lane still
        records what it was made with, and every other door uses this value.
        Naming a client this Mac does not have is not fatal there either: the
        command spawns with one it does have and puts a banner on screen saying
        which, rather than refusing.

        This option chooses the client and nothing else about how a lane opens.
        `claude` can make its own worktree (its native `--worktree` flag, which
        fires `scruff hook create`), but haus does not use it: that flag runs the
        client in the pane it was launched from and never asks scruff's `[hooks]
        open`, which is the seam a lane's own window arrives through. So every
        client goes through `scruff new`, producing the same checkout, branch and
        registry entry from the outside — and the lane stays resumable, because
        Claude keys a transcript to the directory it started in.
        Resuming follows the client too: `codex` reopens
        its cwd-filtered `codex resume` picker, `opencode` continues its latest
        session for that cwd, and `pi` continues the newest session in that
        checkout (`pi --continue`, with `pi --resume`'s picker behind it). They
        share one `scruff` branch/parking/reap
        lifecycle.

        All four light up the `agents` bar pill — the opencode plugin, the
        codex hooks and pi's extension are written for
        you; only Claude Code's stay yours to wire, because Claude owns its own
        settings.json (see `haus.bar.items.agents`). pi reports through an
        extension API rather than a hook file, so its wiring is a file
        (`~/.pi/agent/extensions/haus-agent-state.ts`) — and being pi's one
        seam it carries the trill lane banners as well, where the other clients
        get theirs from a second hook beside the state one. pi still reports no
        usage, so naming it in `haus.bar.aiUsage.provider` selects a row that
        never has a number.

        Two of them ask before reading a folder they have not seen, and a lane's
        checkout is always one — so `scruff` copies the decision you already made
        about the repo onto the worktree it just made: Claude Code's
        `hasTrustDialogAccepted`, and pi's `~/.pi/agent/trust.json`. It only
        ever propagates a yes; an untrusted repo still prompts, which is
        correct.
      '';
    };

    # pi's third-party resource list, under pi's own name for it. `packages`,
    # not `extensions`, because that is the key this ends up written to
    # (`~/.pi/agent/settings.json`) and an option that renamed it would be one
    # more thing to translate when reading pi's docs — the same reasoning as
    # `ai.namer` spelling scruff's id verbatim.
    #
    # This exists as an option, while every key haus merges into Claude Code's
    # settings.json is hardcoded, because of what the two do. Those are display
    # keys: a boolean changes how a pane draws. A pi package is npm or git
    # source that pi FETCHES on first start and then EXECUTES in-process — the
    # only leaf in this room that puts third-party code on the machine — so
    # there has to be a way to say no that isn't "don't install pi".
    ai.pi.packages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "npm:pi-web-access"
        "npm:pi-subagents"
        "npm:@juicesharp/rpiv-ask-user-question"
        "npm:@juicesharp/rpiv-todo"
      ];
      # One line, for ../host-template.jq — see `ai.repoRoots` for why a
      # multi-line default breaks the annotated host file's parse.
      defaultText = lib.literalExpression ''[ "npm:pi-web-access" "npm:pi-subagents" "npm:@juicesharp/rpiv-ask-user-question" "npm:@juicesharp/rpiv-todo" ]'';
      example = [ ];
      description = ''
        pi packages — extensions, skills, prompt templates and themes — merged
        into `packages` in `~/.pi/agent/settings.json` at every rebuild.

        The four in the default are what make pi comparable to the other
        clients in this room rather than a smaller thing beside them. pi ships
        deliberately without sub-agents, a todo list, a way to ask its user a
        question mid-turn, or web access, and says so: its answer is that you
        install a package or have it write you one. So a haus machine that
        installed pi and stopped would be handing you a client that visibly
        cannot do what the pane next to it does.

        - `pi-web-access` — fetch and read a URL.
        - `pi-subagents` — spawn sub-agents for fan-out work.
        - `@juicesharp/rpiv-ask-user-question` — a mid-turn question with
          options, instead of guessing.
        - `@juicesharp/rpiv-todo` — the visible task list a long turn needs.

        Set to `[ ]` for a pi with nothing but its own built-in tools. haus
        MERGES rather than owns: anything you added with `pi install` stays,
        and this list is added beside it, so the file is still yours. The
        consequence of merging is that removing an entry from this list does
        NOT uninstall it — run `pi remove <source>` once, and it will not come
        back.

        Cost, stated plainly: each entry is an npm fetch the first time pi
        starts after a rebuild, and pi runs an extension's code in its own
        process. That is the same trust you extend to the client itself, but it
        is a second decision and this option is where you make it.

        pi does that fetch itself, by spawning `npm` at startup — so haus puts
        one on pi's PATH (`modules/lib/agent-packages.nix`), taking it from the
        very node nixpkgs already runs pi with. Without it pi does not warn and
        carry on: it dies on an uncaught `spawn npm ENOENT` before drawing
        anything, which made these four defaults fatal on a machine that never
        had npm. None of it is a route to `pi install`, which stays imperative
        and outside nix.

        It is APPENDED to pi's PATH, not prefixed, and that is what keeps it
        safe to do. pi has a shell tool, so every command a pi lane runs
        inherits that PATH — prefixed, this node would shadow a homebrew, fnm
        or volta one, and an agent working in a repo pinned to another version
        would silently get haus's. Appended, it is a floor: it answers pi where
        nothing else would, and loses to your own toolchain wherever you have
        one. Your interactive shells are untouched either way.

        The fetch still needs network on that first start, and a source pi
        cannot install — a typo, a 404, an offline machine — is an uncaught
        error in pi rather than a skipped package. `PI_OFFLINE=1` in the
        environment is pi's own escape hatch: it makes a missing package a
        silently absent one instead of a dead client, at the price of never
        installing anything.

        Host-only, and this is the one leaf in the room where that matters
        most: a shared desktop naming a package here would be shipping code
        that runs on your machine inside a file you read as data.
      '';
    };

    # What NAMES a lane that arrives with a task but no name. scruff's own key,
    # spelled verbatim: it runs one argv from
    # `~/.config/scruff/adapters/namer/<id>.toml` and reads a word off stdout, so
    # haus only has to carry the id — the adapter file names the program, and
    # scruff never holds a key or knows a vendor.
    ai.namer = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "api";
      description = ''
        The scruff namer adapter that turns a lane's first-turn brief into the
        lane's name — `mobile-nav-jitter` instead of `cozy-otter`. Empty, the
        default, means no namer: an unnamed lane keeps taking a random word
        pair, which is what every install had before the key existed.

        `claude` is scruff's one built-in, and it costs 8-12s per lane — almost
        all of it the client's own start-up rather than the model. Any other id
        is a file you write: `~/.config/scruff/adapters/namer/<id>.toml`, naming
        a program that takes the brief on argv and prints one name. That file
        is the HOST's, not the layer's, because it is where the model, the key
        and its location get decided; haus deliberately carries only the id, so
        a machine that hasn't written the adapter degrades to random names
        rather than failing to build.

        It cannot cost you a lane. Every failure — no adapter file, a missing
        program, a timeout at scruff's 30s ceiling, prose instead of a name — is
        a warning and a fall back to the random pair.

        **The offline floor is the adapter's to honour.** The palette's Spawn
        Agent has always named the lane itself, from a stopword slug of your
        prompt, and it stops doing that when this is set — so it hands the slug
        down as `SCRUFF_NAMER_FALLBACK` and expects an adapter that cannot reach
        its model to print that instead of failing. scruff neither sets nor reads
        that variable; it only passes the environment through. An adapter that
        ignores it makes an offline spawn fall to the random pair, which is
        worse than the slug the palette would have used.

        ⚠️ **The DIRECTORY is exact.** scruff resolves adapters under
        `~/.config/scruff` and nowhere else, and haus writes
        `~/.config/scruff/config.toml`. An adapter file anywhere else is not
        found, and every lane silently takes a random word pair instead — the
        warning goes to a launchd stderr nobody reads.

        `claude` is excluded from the palette path for exactly that reason: its
        argv is fixed and reads no environment, so it cannot meet the contract —
        and at 8-12s it is asked before the worktree exists, so the whole wait
        lands between Return and the lane with nothing on screen.
        Set it and hand-run `scruff spawn` still asks it; Spawn Agent keeps its
        slug.
      '';
    };

    # Where the palette looks for something to spawn ON. It is an AI-room fact
    # rather than a launcher one — the same list would answer "which repos can
    # I lane into" for any surface that asked — so it lives here and reaches
    # the palette through `_contrib.launcher.agents`, which is also the only
    # way it can reach the pounce DAEMON at all: a launchd GUI agent inherits
    # nothing from your shell, so the `$HAUS_REPO_ROOTS` this used to be was
    # unsettable in the one process that reads it.
    # ---- keeping the Mac awake while agents work ----------------------------
    # A PROFILE, in the sense modules/appearance/default.nix uses the word: the
    # AI room owns the intent ("let my agents finish"), the power room owns the
    # machinery, and this option answers the first by writing the second at
    # `mkDefault`. The room boundary is what makes that the right shape --
    # `disablesleep` is nothing to do with coding agents, and `haus.ai` has no
    # business knowing what a pmset key is.
    ai.keepAwake = lib.mkOption {
      type = lib.types.enum [
        "off"
        "idle"
        "lid"
      ];
      default = "off";
      example = "idle";
      description = ''
        Let agents hold this Mac awake while they are mid-turn.

        Three stops, each one deeper than the last:

        `off` (the default) -- agents get no say. macOS sleeps on its own
        schedule and a run that was still going is simply over.

        `idle` -- a `caffeinate` assertion for exactly as long as an agent is
        working. This is the gap most people actually hit: with the lid OPEN
        and nobody at the keyboard, `haus.power.displaySleep` and
        `haus.power.computerSleep` end an overnight run without anything having
        closed. Needs no privilege, and works on battery, because closing the
        lid still sleeps the Mac, so the closed-laptop-cooking-in-a-bag case
        this stop cannot cause.

        `lid` -- the above, plus turning on `haus.power.lidAwake`, whose root
        daemon holds macOS's `disablesleep`. That is the only lever that
        crosses a lid close, and shutting the lid is the one gesture everybody
        reads as "stop", so it is the stop you have to name deliberately.

        The signal is the one the bar's agents pill already draws, reported by
        every client haus knows, and an agent parked at a permission prompt
        does NOT hold: it is blocked on a human who is not there.

        What this sets rather than owns: `lid` writes
        `haus.power.lidAwake.enable` at `mkDefault`, so a host that names that
        option itself always wins and is told, in a warning, that it did. How
        long a hold lingers past the last turn and how long one may last stay
        where the machinery is (`haus.power.lidAwake.linger` and `.maxHold`),
        and both stops read them -- this is a switch, not a second copy of the
        dial.

        Two knobs there do NOT reach this option. `requirePower` guards the
        **lid** hold only: its argument is that nothing can stop a closed
        laptop cooking in a bag, and at the `idle` stop the lid still sleeps
        the Mac, so an unplugged laptop sitting open on a desk is exactly the
        case worth protecting. And `while = "always"` -- plain closed-display
        mode -- shapes the lid daemon alone; this option means "while my agents
        work" at both stops and never turns into an unconditional hold.

        Host-only, so a shared desktop may not set it: `lid` reaches into
        `haus.power.*`, which is a namespace about one machine's hardware, and
        starts a root daemon there.

        Needs `ai.enable`: the hold signal is written by the agent hooks this
        room installs, so with the room off nothing would ever report a turn.
      '';
    };

    # ---- the merge runner, supervised ---------------------------------------
    # A switch about SUPERVISION, not about authority. What may merge lives in
    # `~/.config/factory/config.json` and in a lease file no pull request can
    # edit (see `ai.enable`'s description and the note beside `factory` in
    # default.nix); this option only decides whether launchd is the thing
    # keeping the runner that reads them alive.
    ai.factory.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.haus.ai.enable;
      defaultText = lib.literalExpression "config.haus.ai.enable";
      description = ''
        Let launchd own `factory watchdog run` — the loop that runs a merge
        shift on a cadence while a lease is live.

        **On its own this merges nothing.** With no lease the runner exits
        within a fifth of a second and launchd simply starts it again later, so
        a machine that has never run `factory lease grant` sees a job that does
        nothing at all. The lease is the switch; this is what stops a runner
        dying at 3 a.m. from being the end of the night.

        What it buys over `factory lease grant`'s own spawn: that one is a
        detached child of your shell, so a reboot, a panic or an out-of-memory
        kill takes it and nothing brings it back — the lease stands with
        nobody exercising it, and you find out in the morning. Under launchd
        the same death is a restart, and factory's own pidfile keeps the two
        from ever being two runners.

        On by default with the room, because the cost of the off state is a
        job that exits immediately and the cost of the on state is a night that
        silently stopped. Turn it off on a machine where `factory` is driven by
        hand and a runner appearing behind you would be a surprise.

        Needs `ai.enable`: `factory` is on PATH because that room put it there,
        so with the room off there is no binary for launchd to keep alive.
      '';
    };

    ai.repoRoots = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "~/code"
        "~/src"
        "~/Developer"
        "~/Projects"
        "~/.config/nix"
      ];
      # Spelled on ONE line for ../host-template.jq — the same escape hatch
      # `haus.wallpaper.debug.inputs` uses, and for the same reason: the
      # annotated host file comments each default with `  # `, and its "is this
      # still legal once uncommented" check un-comments only the line the option
      # NAME is on. A default rendered across several lines leaves the rest
      # commented, and the template stops parsing at the NEXT option — which is
      # how this one first showed up, as `haus.ai.skill = true;` failing to parse.
      defaultText = lib.literalExpression ''[ "~/code" "~/src" "~/Developer" "~/Projects" "~/.config/nix" ]'';
      example = [
        "~/code"
        "~/work/clients"
        "~/.config/nix"
      ];
      description = ''
        Where the palette's **Spawn Agent** finds repositories, most recently
        touched first. A leading `~/` is expanded; a path that does not exist is
        skipped in silence, so the default list can name four conventions and
        cost nothing for the three you don't use.

        Each entry is read TWO ways, and which one applies is decided by the
        path itself:

        - **a repo** (it has a `.git` directory) is offered as itself, and is
          not descended into — that is how `~/.config/nix`, the config flake
          this Mac is built from, is in the default list without `~/.config`
          being scanned.
        - **anything else** is scanned two levels deep for main checkouts, so
          both `~/code/thing` and a parent directory full of repos
          (`~/code/workshop/thing`) resolve.

        Repos `scruff` already knows are always offered too, whether or not they
        are under a root here — so a one-off repo you have agent'd before stays
        reachable, and this list is about the ones you have not.
      '';
    };

    # The two files haus ships into an agent's home, one option each. Both
    # were `haus.claude.*` until 2026-08-11 and wrote only Claude Code's copy —
    # which made `ai.default = "codex"` a half-truth: the client spawned,
    # with none of the operating context or the option knowledge the same
    # machine hands Claude. They are named for the ROOM, not the client, and
    # terminal writes one copy per entry in `ai.clients` (moved.nix keeps
    # the old names working, with a warning).
    ai.instructions = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = ''
        # How I work
        Ship small, verified changes; ask before anything hard to reverse…
      '';
      description = ''
        Your always-on, cross-project operating context — the "instructions"
        slot every client has under a different name. Written once per client
        in `ai.clients`, to the path that client actually reads:
        `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`,
        `~/.config/opencode/AGENTS.md`, `~/.pi/agent/AGENTS.md`.

        Write it client-neutrally: the same text reaches whichever agent the ⌘A
        pane spawns, so a line about a Claude-only skill or file path is noise
        to the others. When set, haus prepends three short sections of its
        own — a note that the file is generated and where to actually edit it
        (with THAT client's path), the `scruff` worktree etiquette, since haus
        ships `scruff` and that rule is what keeps it working, and the screen
        etiquette that pairs with `agent-desktop-guard` — then your text.

        Empty (the default) writes nothing at all, for any client, so a
        hand-managed instructions file is never clobbered just to inject
        haus's note. If you set it and one of those paths already holds a file
        you wrote by hand, home-manager moves yours aside as `<file>.backup`
        rather than refusing — quiet, so check for one before the first rebuild
        after setting this.

        With `ai.clients` empty (a machine haus installs no client on)
        every known client's path is written instead of none: the list being
        empty means haus installs none, not that no agent runs here.
      '';
    };

    # ---- the auto-mode classifier's picture of this machine -----------------
    #
    # Claude Code's `auto` permission mode (terminal sets
    # `permissions.defaultMode`) runs a safety classifier over every tool call
    # and judges it against an `autoMode` block in ~/.claude/settings.json: an
    # `environment` (what this machine and its repos are) and three rule lists
    # (`allow`, `soft_deny`, `hard_deny`), all prose. Without one it assumes a
    # stranger's laptop and prompts for the ordinary work of this one — on the
    # machine this was written for, two weeks of transcripts held 54 denials
    # for cross-repo commits, ssh into a lane's own VM and `gh pr merge` on a
    # solo-owned repo.
    #
    # Four lists and a switch. modules/terminal's claudeCodeSettings renders
    # them into that block, beside the hooks it already merges; all four lists
    # empty writes nothing at all, `ai.instructions`'s rule. Written whenever
    # the room is on rather than only when `claude` is in `ai.clients`, like
    # every other key that merge writes: a hand-installed Claude Code reads
    # the same file. Spelled camelCase here and snake_case in the file,
    # because the file's keys are Claude Code's.
    ai.autoMode.environment = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "**Organization**: a one-person org. Every repo under ~/code is owned solo; the user is the only committer and the only reviewer."
        "**Host containment**: this Mac is a personal single-user workstation. A lane may boot a disposable headless macOS VM with `tart` on 192.168.64.0/24; nothing there is production or shared."
      ];
      description = ''
        What Claude Code's auto-mode classifier is told about this machine.
        In `auto` permission mode, the one haus sets, a classifier judges
        every tool call before it runs, against this picture: one fact per
        string, in prose, the way you would describe the setup to a new
        engineer. Which repos are yours, where secrets live, which hosts are
        disposable, what counts as production. Without it the classifier
        assumes a stranger's laptop and asks about the ordinary work of this
        one.

        Written to the `autoMode.environment` key of `~/.claude/settings.json`
        on every rebuild, merged in beside everything else the file holds.
        Each of the four lists is owned per SECTION: a rebuild re-asserts the
        ones you set and leaves the rest of the block alone, so a host that
        names only `allow` never deletes a `hard_deny` written with `claude
        auto-mode`. Inside a section you do set, that CLI's edits and a hand
        edit last until the next rebuild. Empty (the default) means haus does
        not name the section at all, not that it writes an empty one.

        Only Claude Code reads this file, but haus writes it whenever the AI
        room is on rather than only when `claude` is in `ai.clients` — the
        same rule the hooks and the statusline beside it follow, because a
        hand-installed Claude Code reads it too.

        Claude Code's own default entries stay in front of yours while
        `ai.autoMode.keepDefaults` is on. `claude auto-mode config` prints the
        result, `claude auto-mode critique` reviews it.
      '';
    };

    ai.autoMode.allow = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "Lane VMs: anything sent over ssh to a tart guest on 192.168.64.0/24 is work on a disposable VM the lane created. sudo, killall, reboots and deleting the VM are all fine there."
      ];
      description = ''
        What is ordinary on this machine: exceptions to the classifier's own
        refusals, one per string, each opening with a short title. A rule
        here is what stops a lane being asked to confirm `gh pr merge` on a
        repo you own solo, or `rm -rf` inside a VM it booted itself. The
        user's own words in the conversation are the other thing that can
        lift a refusal; a rule here lifts it for every session.

        Written to `autoMode.allow`, with Claude Code's built-in allow rules in
        front of yours while `ai.autoMode.keepDefaults` is on. Same lifecycle
        as `ai.autoMode.environment`.
      '';
    };

    ai.autoMode.softDeny = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "NAS Volumes: writing to or deleting anything on the QNAP's data volumes, whatever the mount path."
      ];
      description = ''
        What the classifier should stop and ask about, unless the user's own
        words or an `ai.autoMode.allow` rule say otherwise. Claude Code ships
        its own list (force pushes, `curl | bash`, production deploys,
        reading secrets). Yours join it while `ai.autoMode.keepDefaults` is
        on; with that off, yours REPLACE it, and the built-in refusals are
        gone.

        Written to `autoMode.soft_deny`. Same lifecycle as
        `ai.autoMode.environment`.
      '';
    };

    ai.autoMode.hardDeny = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "Keychain Export: `security dump-keychain`, or copying any credential to a file, in any session, for any reason."
      ];
      description = ''
        Boundaries no rule and no instruction can cross: the classifier
        refuses these outright. Claude Code's own list is one entry,
        exfiltration to hosts it does not know. Same shape as
        `ai.autoMode.softDeny`, same `ai.autoMode.keepDefaults` rule, and the
        same warning with more weight behind it: a list written without the
        built-ins is a hard boundary that is gone.

        Written to `autoMode.hard_deny`. Same lifecycle as
        `ai.autoMode.environment`.
      '';
    };

    ai.autoMode.keepDefaults = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Keep Claude Code's own built-in entries in front of yours, in every
        `ai.autoMode` list you set. That is the `"$defaults"` marker Claude
        Code reads in each list: haus puts it first unless you wrote it
        yourself somewhere in that list, so a rule that should read before
        the built-ins can.

        Off, each list you set is written exactly as written, and a list
        without `"$defaults"` replaces Claude Code's own for that section
        entirely. For `ai.autoMode.softDeny` and `ai.autoMode.hardDeny` that
        means the built-in refusals are gone. Turn this off only when the
        effective config you want is yours alone, and read it back with
        `claude auto-mode config` before trusting it.
      '';
    };

    ai.skill = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install every hausfold tool's agent skill for each client in
        `ai.clients`, so an agent asked to "install Slack" or "make everything
        bigger" edits your host file and runs `haus rebuild` instead of guessing
        at dotfiles and `brew install` — and an agent asked "what worktrees do I
        have open?" or "hand this off to a fresh session" reaches for `scruff`
        rather than `git worktree`.

        Six skills on any machine. Two are haus's own: `haus` (this
        machine's setup) and `hausfold` (carrying a complaint about anything we
        make upstream — which repo owns the symptom, the `report` verb that
        fills its bug form's diagnostics field in, and the fork to a pull
        request; it files nothing without asking you first). Then scruff's
        own two — `scruff` (the lane lifecycle) and `handoff` (turning work into a
        brief a cold session can act on, ending on the clipboard or in a new
        lane) — factory's `factory` (the merge verbs; a live lease runs the
        shift itself, so the skill is what an agent does around it) — and `nebelung`
        (this machine's exact palette, rendered from the lock rather than
        remembered). A tool whose room is OPTIONAL adds its own only when that
        room is on: `trill` (sending a notification) with
        `haus.notifications.compositor`, `pounce` (driving the command palette)
        with `haus.launcher.enable`, `perch` (putting files on the notch shelf)
        with `haus.shelf.enable` — because a skill for an app this Mac doesn't
        have is worse than none.
        Those switches are about the ROOM, not about the app: `haus-notify` and
        the `trill` command find a hand-installed Trill.app at runtime whatever
        this option says, and a machine running a hand-installed pounce, perch
        or Trill.app with the room off gets no skill for it until the room is
        switched on.
        Each tool names its own skills; haus only decides that they are
        installed.

        One copy per skill per client, in the directory that client scans:
        `~/.claude/skills/haus`, `~/.codex/skills/haus`,
        `~/.config/opencode/skills/haus`, `~/.pi/agent/skills/haus`, and the
        same four directories again
        per skill. OpenCode also
        scans `~/.claude/skills`
        for Claude Code compatibility, and prefers its own copy when both
        exist — so a machine running both clients sees each skill once, not
        twice. pi reads `~/.agents/skills` on top of its own directory for the
        same reason, and deduplicates the same way.

        The skill's option reference is GENERATED from the haus revision this
        machine is pinned to, so it can only ever describe options that
        actually exist here — and it is regenerated by `haus update`. It also
        carries this host's current state (which rooms are on, where the host
        file is) and a starter AGENTS.md + CLAUDE.md pair for your config repo —
        the rules in the first, a one-line import in the second, so a session
        opened there is oriented whichever client it runs.

        Unrelated to the clients' own settings, which follow
        `haus.ai.enable`. This is a plain file drop: with
        `ai.clients` empty — a machine haus installs no client on, which
        can still have one from npm or Homebrew — every known client's directory
        gets a copy rather than none. Set false to leave every client's skills
        directory alone.
      '';
    };
  };
}

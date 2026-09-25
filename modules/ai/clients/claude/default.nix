# Claude Code. The record modules/ai/clients/default.nix describes; the AI room
# renders it.
{
  # A bare reference, and bare on purpose even though claude-code has a version
  # floor of its own: that pin sits one layer DOWN, in the overlay at
  # modules/lib/claude-code.nix. Written here it would be `.override { manifest
  # = …; }` applied to whatever a host's own `claude-code` overlay returned — a
  # wrapper taking no such argument — and the promise that this is the one
  # reference to the client would stop being true. Pinned underneath, a host's
  # patches ride on top of the pinned version and this goes on meaning one
  # thing.
  package = pkgs: pkgs.claude-code;

  # The Claude Code release that first offered Fable 5.1, and so the oldest
  # client haus is willing to hand someone. pi's floor is a crash; this one is
  # a model quietly missing from `/model`. Claude Code gates MODELS on the
  # client version, so an old build does not crash, it just serves a menu
  # missing something the user's plan includes, with a greyed "Update to
  # 2.1.255+ to use Fable 5.1" where the model should be. Nobody files that as a
  # haus bug, which is exactly why haus checks it rather than waiting to be
  # told.
  #
  # This passes today because modules/lib/claude-code.nix pins past it. It is
  # here for the day the pin is deleted: quiet once nixpkgs has caught up, a
  # named refusal while it has not.
  floor = {
    version = "2.1.255";
    message =
      built:
      "haus.ai.clients names claude, but this pkgs builds Claude Code ${built} "
      + "and haus will not ship older than 2.1.255: Claude Code gates models on "
      + "the client version, so below that Fable 5.1 is greyed out of `/model` with "
      + "nothing to explain why. Refresh the manifests with "
      + "modules/lib/claude-code-update.sh (the pin lives beside them in "
      + "modules/lib/claude-code.nix), or drop claude from ai.clients.";
  };

  home = {
    instructions = ".claude/CLAUDE.md";
    skills = ".claude/skills";
  };

  # `-p` is print mode. `--dangerously-skip-permissions` is the bypass that
  # needs no `--allow-dangerously-skip-permissions` beside it: that second
  # flag only ENABLES the first as an option, and passing the first alone
  # already turns it on. Verified against claude 2.x's `--help`, 2026-08-31.
  oneshot = [
    "claude"
    "-p"
    "--dangerously-skip-permissions"
    "--"
  ];

  scopeNote = "`settings.json` is Claude Code's own, and a host may wire individual skills as out-of-store symlinks";

  # Claude Code — seed a couple of defaults into settings.json:
  #   permissions.defaultMode = "auto"  — pin the permission mode here
  #     instead of passing --dangerously-skip-permissions on the command
  #     line (the lane spawner no longer does). "auto" runs agents
  #     unattended but keeps the background safety checks that block
  #     dangerous escalations, so it's safe on the host — unlike
  #     bypassPermissions, which is the flag's exact, check-free behaviour
  #     and wants a container.
  #   tui = "fullscreen"  — render Claude Code in the alt-screen (fullscreen)
  #     TUI rather than inline. `/tui fullscreen` sets this per-session and
  #     relaunches; seeding it makes fullscreen the default on every new
  #     machine. Ghostty's own ⇧-drag selection still reaches the
  #     alt-screen, so there's no tradeoff to the classic inline renderer.
  #   disableAgentView = true  — turn off the built-in agent-manager view
  #     (`claude agents`, `--bg`, /background, its on-demand daemon) and the
  #     "← for agents" toolbar hint that advertises it. Undocumented key,
  #     equivalent to CLAUDE_CODE_DISABLE_AGENT_VIEW=1. Parallel Claude
  #     sessions here go through `scruff` + zmx windows (core/terminal), not the
  #     in-app view, so the hint is pure noise — kill it at the haus level.
  #   statusLine  — point Claude Code's status bar at `claude-statusline`
  #     (core ships it on PATH). It renders THIS session's `scruff` worktree +
  #     the sister worktrees in flight across every repo — the agent-worktree
  #     HUD the built-in bar can't give. refreshInterval keeps the sister
  #     list current while the main session sits idle watching other panes.
  #     It is also the ONLY feed behind bar's `claudeUsage` pill — Claude
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
  #     hyperlinks the statusline (core/statusline.sh) emits for its "#N" PR
  #     pills — colored but no longer clickable at all (upstream regression,
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
  #
  # The two WorktreeCreate/WorktreeRemove hooks are set here, and that is a
  # change from how they used to live: hand-written, once, and hoped for.
  # The risk was never a rebuild clobbering them — this merge only touches
  # the keys it names — it was the sentence above. Claude REWRITES this file
  # on its own schedule, and a hand-edited hook it doesn't know about can go
  # with it; you would find out at pane-close, by losing a worktree's
  # parking. Declaring them makes them self-healing: every rebuild
  # re-asserts them, so the worst case is one `haus rebuild` rather than
  # silent data loss.
  #
  # Set as whole arrays, not merged into: these two events are haus plumbing
  # pointing at a haus-controlled /run/current-system path, and there is no
  # sensible second handler for "make me a worktree". Every other hook
  # ENTRY in the file survives: the four agent-state hooks stay yours (see
  # modules/bar/options.nix) — on Notification and Stop haus appends its own
  # entry beside yours, never in place of them.
  #
  # The `&& mv` is load-bearing: this program's PreToolUse filter is the
  # first one here that can ERROR on user-shaped data (`map` over a
  # non-array, if something writes `\"PreToolUse\": \"…\"`), and the `sh -c`
  # body has no `set -e` — an unconditional `mv` would install jq's empty
  # output as the user's whole settings.json and report success.
  #
  # PreToolUse is the exception, and is APPENDED rather than set: unlike the
  # worktree events it is a general-purpose event that Claude, a plugin or you
  # may well have opinions on too, so the merge drops any stale copy of our own
  # handler by command path and re-appends one, leaving every other entry in
  # place. The filter drops BOTH spellings of our own handler: the current
  # one, and `agent-desktop-ask` — the name this hook wore before #596
  # renamed it. A settings.json written while the old binary was live
  # still carries the old path, and without it in the filter that stale
  # entry survives every rebuild beside the fresh one — every Bash call
  # asked twice, forever. Dropping a dead spelling is safe exactly because
  # nothing re-inserts it: the append below is the only writer this filter
  # feeds, and it writes the new name only. It points at
  # `agent-desktop-guard` (modules/ai), which re-asks
  # before a tool call moves the pointer, takes focus or redraws the desktop —
  # the counterweight to the `defaultMode = "auto"` two lines below, which is
  # right for files and wrong for the screen. It refuses nothing.
  # FOUR events get `scruff hook notify` APPENDED the same way, and they are
  # two directions of one thing. Notification and Stop turn "this lane is
  # blocked on its user" / "this lane finished" into a trill banner — an ask
  # parked on trill's ledge, or a done. UserPromptSubmit and PostToolUse
  # take an answered ask back DOWN: the user typed, or a tool actually ran,
  # which is what approving a permission prompt leads to. Without those two
  # the ledge kept saying "waiting on you" while the agent was already ten
  # minutes into the work.
  #
  # The filter drops only what it is about to insert — the append's whole
  # safety is there (this is an append, not the assignment
  # WorktreeCreate/Remove use, which self-heal). It filters on the one
  # spelling of the command, which is only safe because every settings.json
  # on the machine has since been rewritten with it — dropping a spelling
  # from the filter while entries using it are still in the file leaves
  # them in place beside the new one: every agent pane firing two
  # notifications, forever.
  #
  # A third way down is not a hook at all and does not live here:
  # lanes/lane-seen.sh clears a lane's fin when you FOCUS its window, which
  # is the earlier signal — you can read a question and think for a minute
  # before typing, and the ledge should stop flagging it the moment you are
  # standing in front of it. These two stay because focus is not always
  # observable (no tiler, a lane answered from the Claude Code desktop app)
  # and because answering from somewhere else must still clear it.
  #
  # PostToolUse fires on every tool call in every pane, so the cost matters:
  # scruff gates the whole path behind one marker file per outstanding fin, so
  # an ordinary tool call reads one directory and stops — no registry read,
  # no launch of Trill.app's binary. Drop that event from the list if you
  # would rather pay nothing at all; the fin then clears at the end of the
  # turn instead, when Stop replaces it.
  #
  # Appended, never set: all four also carry the user's own agent-state
  # hooks (the bar's agents pill — see modules/bar), which must survive
  # every rebuild. The hook itself is scruff's and exits 0 no matter what — no
  # trill installed, daemon down, garbage payload — so wiring it on a
  # machine without trill is a silent no-op, never a broken session.
  # `.autoMode` is the classifier's picture of this machine
  # (`haus.ai.autoMode.*`), and it is owned per SECTION: while the option
  # names one, that section is haus's, and a rebuild puts back what
  # `claude auto-mode reset` or a hand edit changed. Stop naming it and
  # the next rebuild REMOVES it — which is why this block hands jq a
  # second file, the names haus wrote last time, kept in
  # ~/.local/state/haus/claude-auto-mode-sections. Without that record an
  # undeclared section and a section haus never touched are the same
  # thing from inside the program, and the safe reading left an `allow`
  # rule lifting refusals for a config that had stopped asking. A block
  # Claude Code wrote itself is still never touched. Both files arrive
  # through `--slurpfile` rather than inline, because the prose is KB of
  # quotes and dollar signs and the escaping stack here has bitten once
  # already (../pi's settings merge) — which is also why the program itself is
  # ./claude-settings.jq now and not a quoted argument.
  #
  # Claude Code settings/hooks/statusline are agent tooling; a machine that
  # runs no agents should not have its ~/.claude/settings.json rewritten.
  settings = {
    name = "claudeCodeSettings";
    onlyWhenInstalled = false;
    activation =
      {
        pkgs,
        lib,
        cfg,
      }:
      let
        # The auto-mode classifier's picture of this machine (`haus.ai.autoMode.*`,
        # modules/ai/options.nix), rendered into the `autoMode` block that
        # claudeCodeSettings below merges into ~/.claude/settings.json. Only the
        # lists that are SET become keys — Claude Code keeps its own defaults for a
        # section the file does not name — and each one gets the `"$defaults"`
        # marker in front while keepDefaults is on, unless the list already carries
        # it somewhere, which is how a rule is placed ahead of the built-ins. An
        # empty list is "haus does not name this section", not "write an empty one":
        # there is no way to spell an explicitly empty override here, and that is
        # the right default when the section it would empty is a list of refusals.
        #
        # Not gated on `claude` being in `ai.clients` (`onlyWhenInstalled = false`,
        # unlike codex's and pi's): the file is written whenever the room is on,
        # because a hand-installed Claude Code reads it too and a machine without
        # one pays nothing for a key it never opens. Gating here would be the worst
        # of both — the hooks and the statusline arrive, and the one thing that
        # stops that client asking about ordinary work does not.
        #
        # The merge itself is ./claude-settings.jq, with the per-section ownership
        # rule and the reason a section is DELETED when the host stops naming it
        # written out beside the code that does it. What this end owes that program
        # is two files:
        #
        #   autoModeFile          the sections declared now, `{}` when none are
        #   autoModeSectionNames  their names, which the activation leaves in
        #                         ~/.local/state/haus/claude-auto-mode-sections as
        #                         the record of what haus wrote — the one thing that
        #                         tells the next rebuild "haus has no opinion about
        #                         this section" from "haus has never had one"
        #
        # A store file and `--slurpfile`, not an `--argjson` argument: the
        # environment alone runs to several KB of prose full of quotes and dollar
        # signs, and a path is the one thing that survives the nix'' → sh'' → jq""
        # escaping layers untouched.
        autoModeCfg = cfg.autoMode;
        autoModeSections = lib.filterAttrs (_: v: v != [ ]) {
          environment = autoModeCfg.environment;
          allow = autoModeCfg.allow;
          soft_deny = autoModeCfg.softDeny;
          hard_deny = autoModeCfg.hardDeny;
        };
        autoModeWithDefaults =
          l: if autoModeCfg.keepDefaults && !(lib.elem "$defaults" l) then [ "$defaults" ] ++ l else l;
        autoModeFile = pkgs.writeText "claude-auto-mode.json" (
          builtins.toJSON (lib.mapAttrs (_: autoModeWithDefaults) autoModeSections)
        );
        autoModeSectionNames = builtins.toJSON (builtins.attrNames autoModeSections);
      in
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        run sh -c '
          settings="$0"
          state="$1"
          sections="$2"
          mkdir -p "''${settings%/*}"
          tmp="$settings.hm-seed"
          if [ -s "$settings" ]; then base="$settings"; else base="$tmp.base"; printf "{}" > "$base"; fi
          # The record of what haus wrote LAST time, seeded the same way the
          # base file is. Missing is the ordinary case on a machine that has
          # never named a section, and jq refuses a --slurpfile that is not
          # there, so an empty list stands in rather than a missing argument.
          #
          # Checked before it is used, and that is not belt and braces: a
          # --slurpfile jq cannot PARSE fails the whole run, which would leave
          # the hooks and the statusline unmerged too, on every rebuild, until
          # somebody deleted a file nothing has ever told them about. A
          # truncated record costs what it knows, never the merge.
          if [ -s "$state" ] && ${pkgs.jq}/bin/jq -e "type == \"array\"" "$state" > /dev/null 2>&1; then
            wrote="$state"
          else
            wrote="$tmp.wrote"; printf "[]" > "$wrote"
          fi
          merged=
          ${pkgs.jq}/bin/jq --slurpfile auto ${autoModeFile} --slurpfile prev "$wrote" \
            -f ${./claude-settings.jq} "$base" > "$tmp" && mv "$tmp" "$settings" && merged=yes
          # Only after the merge landed, or haus would claim a section it
          # never managed to write and delete it on the next rebuild. The
          # guard keeps the file off a machine that has never had one: the
          # list going empty still writes "[]" once, so the rebuild after a
          # reset knows there is nothing left to clear.
          if [ -n "''${merged:-}" ] && { [ "$sections" != "[]" ] || [ -s "$state" ]; }; then
            mkdir -p "''${state%/*}"
            printf "%s" "$sections" > "$state"
          fi
          # Both, not just the base — the reason the piSettings block below
          # spells out: when jq fails the `&& mv` short-circuits, and a
          # half-written "$tmp" would otherwise sit beside the real
          # settings file forever, looking like something Claude should read.
          rm -f "$tmp" "$tmp.base" "$tmp.wrote"
        ' "$HOME/.claude/settings.json" \
          "$HOME/.local/state/haus/claude-auto-mode-sections" \
          ${lib.escapeShellArg autoModeSectionNames}
      '';
  };
}

#compdef haus
#
# zsh completion for `haus`, installed at share/zsh/site-functions/_haus.
#
# Two things it knows: the subcommands (from haus.sh's own dispatch), and — for
# the four commands that name an option — every settable `haus.*` path on THIS
# machine's pinned haus, with one line of prose each.
#
# WHERE THE PATHS COME FROM, and where they emphatically don't. The authority on
# whether a path is settable is the module system, and asking it costs a full
# darwin evaluation (`settings_option_exists` in haus.sh, seconds per call). A
# completion that did that would hang the shell on every Tab, so this reads the
# static catalogue core installs beside the host template instead — the same file
# `haus set`'s picker reads, rendered from the revision this machine pinned.
# Nothing in here evaluates anything.
#
# A FLAT list of full dotted paths, deliberately. `_multi_parts` would complete
# the hierarchy one component at a time, which is worth doing when the terminal
# can only prefix-match — but terminal loads fzf-tab, so the whole list is already
# fuzzy-searchable and splitting it into levels just adds Tabs. The paths are
# offered in the relative form the docs and error messages use (`theme.flavor`);
# `compset -P` below makes the `haus.`-prefixed spelling complete too, since
# `haus set` accepts both.
#
# jq's store path is substituted in at build time (@jq@): it ships only with the
# developer toolbelt, and a completion that silently stopped working on a
# toolbelt-off machine would look like the option list being empty.
#
# The rendered agent skill (@skill@) is substituted for a different reason:
# `haus`'s wrapper sets HAUS_SKILL_DIR inside its OWN process, which a shell
# completing its arguments has never been in. So `haus skill <TAB>` reads the
# store path directly, and honours the variable only for someone who exported it
# on purpose to point at a working copy.

_haus_option_paths() {
  local catalogue=${HAUS_CATALOGUE:-/run/current-system/sw/share/haus/options.json}
  [[ -r $catalogue ]] || return 1

  # `haus.theme.flavor` and `theme.flavor` are the same option to haus set, so
  # let someone who typed the prefix keep completing.
  compset -P 'haus.'

  local -a paths
  paths=( ${(f)"$( @jq@ -r 'to_entries[] | "\(.key[5:]):\(.value.summary)"' \
                    -- $catalogue 2>/dev/null )"} )
  (( $#paths )) || return 1
  _describe -t haus-options 'haus option' paths
}

_haus() {
  local state
  local -a subcommands
  # One entry per arm of haus.sh's dispatch `case`. Keep them in step: an arm
  # missing here is a command nobody discovers, and one listed here that no
  # longer exists is a command that fails after you completed it.
  subcommands=(
    'rebuild:build + switch this machine from your config'
    'fix:hand the rebuild that just failed to a coding agent'
    'update:pull the latest haus + its apps, then rebuild'
    'rollback:go back a generation (or to generation N)'
    'generations:list the generations you can roll back to'
    'status:current generation + how old your pinned haus is'
    'edit:open your host config in $EDITOR'
    'options:refresh the annotated catalogue of every haus.* option'
    'set:write + apply haus.* options (with no arguments, pick one)'
    'get:print a declared value, or list the writable overlay'
    'unset:force nullable options to null'
    'reset:remove writable overrides and inherit the host/desktop/room value again'
    'plan:preview what a rebuild would change, without building it'
    'diff:declared config vs what macOS actually has right now'
    'capture:turn this Mac'\''s current settings into config lines'
    'revert-settings:put back a haus capture snapshot'
    'doctor:check the machine'\''s health (Nix, CLT, the GUI agents)'
    'report:file a bug, with this Mac'\''s haus doctor report already filled in'
    'skill:print haus'\''s own agent skill, or install it into an agent client'
    'permissions:walk every grant and click this Mac still needs a person for'
    'btm:check BTM daemon-gating (macOS 26 Tahoe+; no-op before)'
    'tour:take the guided haus tour'
    'show:inspect a desktop or room - a local file or a remote source - before you publish or trust it'
    'add:pin a desktop and select it, or a room with --room --namespace'
    'desktop:list every desktop this machine can select, or switch to one'
    'remove:unpin a desktop or room this machine added, and reselect'
    'help:list every command'
  )

  _arguments -C \
    '(-v --verbose)'{-v,--verbose}'[raw output instead of the folded summary]' \
    '1: :->command' \
    '*:: :->argument'

  case $state in
    command)
      _describe -t commands 'haus command' subcommands
      ;;
    argument)
      # How many POSITIONALS are already typed. Not `CURRENT`: haus.sh strips
      # -v/--verbose from anywhere in argv before it dispatches, so `haus set -v
      # theme.` is a path in the first slot — counting the flag would offer a
      # value there instead, and be off by one for every pair after it.
      #
      # `show`'s own flags are excluded for the same reason: they are not
      # positionals, and counting `--json` as one made `haus show --json <TAB>`
      # complete nothing at all. `--file` is the same bug twice over, because it
      # takes a VALUE: unlisted, the flag and its argument counted as two
      # positionals and `haus show --file x.nix <TAB>` completed nothing.
      local -i typed=0 i
      local -i skip=0
      for (( i = 2; i < CURRENT; i++ )); do
        if (( skip )); then skip=0; continue; fi
        case $words[i] in
          --file)   skip=1 ;;
          --file=*) ;;
          -v|--verbose|--json|--room|-h|--help) ;;
          *) (( typed++ )) ;;
        esac
      done

      case $words[1] in
        unset|reset)
          # Variadic: every slot is a path.
          _haus_option_paths
          ;;
        get)
          # Reads one path and ignores the rest, so offer it once. `--json` is
          # already excluded from the positional count above, so it may be typed
          # on either side of the path.
          if (( typed == 0 )); then
            _alternative \
              'flags:flag:((--json:"one {path,defined,value} object, or an array of them"))' \
              'options:haus option:_haus_option_paths'
          else
            _message 'no more arguments'
          fi
          ;;
        set)
          # PAIRS: path value path value…. An even number of positionals typed
          # means a path comes next; offering one where a value goes would be
          # suggesting an option name as its own value.
          if (( typed % 2 == 0 )); then _haus_option_paths; else _message 'value'; fi
          ;;
        tour)
          _values 'tour' 'reset[re-arm a finished tour]'
          ;;
        report)
          _arguments '--print[print the block and the link; open no browser]'
          ;;
        skill)
          # One positional: `install`, or the name of a page to print. The names
          # come from the rendered skill this machine actually has, so a machine
          # whose haus grew a reference page offers it without editing this file
          # — and one whose skill is missing offers `install` alone rather than
          # completing a page that would not print.
          if (( typed == 0 )); then
            local -a pages
            pages=( 'install:write the skill into every agent client that has not got it' )
            local skill=${HAUS_SKILL_DIR:-@skill@}
            if [[ -d $skill ]]; then
              local f
              for f in $skill/references/*.md(N); do
                pages+=( "${f:t:r}:the ${f:t:r} reference page" )
              done
            fi
            _describe -t haus-skills 'skill or reference' pages
          elif [[ $words[2] == install ]]; then
            _arguments \
              '--client[write into one client only]:client:(@skillClients@)' \
              '--dir[write into a directory of your own]:directory:_files -/'
          else
            _message 'one page at a time'
          fi
          ;;
        show)
          # The only verb whose argument is a PATH rather than an option name.
          # A local one is a file on disk, so the shell's own completion is the
          # right one; a remote source is a flakeref nothing here can enumerate,
          # which is why the file glob is offered rather than required.
          if (( typed == 0 )); then
            _arguments \
              '--json[the report as JSON on stdout, for CI and agents]' \
              '--room[this is CODE; print the trust warning, check nothing]' \
              '--file[which file inside a fetched repo to read]:path in the source:' \
              '*:desktop or room - a .nix file, or a source:_files -g "*.nix"'
          else
            _message 'one source at a time'
          fi
          ;;
      esac
      ;;
  esac
}

_haus "$@"

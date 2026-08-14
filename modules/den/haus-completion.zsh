#compdef haus
#
# zsh completion for `haus`, installed at share/zsh/site-functions/_haus.
#
# Two things it knows: the subcommands (from haus.sh's own dispatch), and — for
# the four commands that name an option — every settable `haus.*` path on THIS
# machine's pinned rice, with one line of prose each.
#
# WHERE THE PATHS COME FROM, and where they emphatically don't. The authority on
# whether a path is settable is the module system, and asking it costs a full
# darwin evaluation (`settings_option_exists` in haus.sh, seconds per call). A
# completion that did that would hang the shell on every Tab, so this reads the
# static catalogue den installs beside the host template instead — the same file
# `haus set`'s picker reads, rendered from the revision this machine pinned.
# Nothing in here evaluates anything.
#
# A FLAT list of full dotted paths, deliberately. `_multi_parts` would complete
# the hierarchy one component at a time, which is worth doing when the terminal
# can only prefix-match — but hearth loads fzf-tab, so the whole list is already
# fuzzy-searchable and splitting it into levels just adds Tabs. The paths are
# offered in the relative form the docs and error messages use (`theme.flavor`);
# `compset -P` below makes the `haus.`-prefixed spelling complete too, since
# `haus set` accepts both.
#
# jq's store path is substituted in at build time (@jq@): it ships only with the
# developer toolbelt, and a completion that silently stopped working on a
# toolbelt-off machine would look like the option list being empty.

_haus_option_paths() {
  local catalogue=${HAUS_CATALOGUE:-/run/current-system/sw/share/nebelhaus/options.json}
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
    'update:pull the latest rice + nebelhaus apps, then rebuild'
    'rollback:go back a generation (or to generation N)'
    'generations:list the generations you can roll back to'
    'status:current generation + how old your pinned rice is'
    'edit:open your host config in $EDITOR'
    'options:refresh the annotated catalogue of every haus.* option'
    'set:write + apply haus.* options (with no arguments, pick one)'
    'get:print a declared value, or list the writable overlay'
    'unset:force nullable options to null'
    'reset:remove writable overrides and inherit the host/rice value again'
    'plan:preview what a rebuild would change, without building it'
    'diff:declared config vs what macOS actually has right now'
    'capture:turn this Mac'\''s current settings into config lines'
    'revert-settings:put back a haus capture snapshot'
    'doctor:check the machine'\''s health (Nix, CLT, the GUI agents)'
    'btm:check BTM daemon-gating (macOS 26 Tahoe+; no-op before)'
    'tour:take the guided haus tour'
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
      local -i typed=0 i
      for (( i = 2; i < CURRENT; i++ )); do
        [[ $words[i] == (-v|--verbose) ]] || (( typed++ ))
      done

      case $words[1] in
        unset|reset)
          # Variadic: every slot is a path.
          _haus_option_paths
          ;;
        get)
          # Reads one path and ignores the rest, so offer it once.
          if (( typed == 0 )); then _haus_option_paths; else _message 'no more arguments'; fi
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
      esac
      ;;
  esac
}

_haus "$@"

#!/usr/bin/env bash
# zscratch — feel-test a candidate zellij config / layout / plugin.wasm in a
# throwaway zellij session in its OWN Ghostty window, WITHOUT a rebuild.
#
# The problem it kills: today the only way to try a zellij edit (a keybind, a
# theme colour, a freshly-built plugin .wasm) is `bench try switch` + restarting
# the `main` session — which nukes every tab you had open. zscratch moves the
# iterate-loop off that path: it renders your candidate into a temp config dir
# and launches a scratch session in a separate window, so the live session is
# untouched. You rebuild ONCE, at the end, already knowing it works.
#
#   zscratch                       just boot the CURRENTLY-INSTALLED config in a
#                                  scratch window (a sanity baseline)
#   zscratch --config  FILE        overlay a candidate config.kdl
#   zscratch --layout  FILE        overlay a candidate layout (→ layouts/custom.kdl)
#   zscratch --theme   FILE        overlay a candidate theme  (→ themes/nebelung.kdl)
#   zscratch --plugin  NAME=WASM   swap a plugin's wasm (NAME ∈ tab-bar,
#                                  status-bar, link-handler, tab-history);
#                                  repeatable
#   zscratch --locked              start the scratch session in locked mode
#   zscratch --name    N           scratch session/dir name (default: scratch)
#   zscratch --print               render the scratch dir, print its path, DON'T launch
#   zscratch clean [--name N]      kill the scratch session + delete its temp dir
#
# Candidate files may be the in-repo SOURCE (with @HOME@ / @username@ /
# @DEFAULT_MODE@ tokens) or an already-rendered file — tokens are expanded
# either way, so a repo edit and a ~/.config edit both Just Work. Everything you
# DON'T override is taken verbatim from the live ~/.config/zellij, so the scratch
# is a faithful copy of your machine with only your edit layered on top.
#
# Isolation: the scratch gets its own --config-dir (a temp dir), its own session
# name, and its own Ghostty WINDOW (not a pane) — so a wedging config can't take
# your working multiplexer down with it. A brand-new session name means a brand-
# new zellij *server*, which recompiles plugin wasm from disk (a running server
# caches it in memory for its lifetime — see the plugin notes below).
set -euo pipefail

# Resolve against the nix profile first (this may run from launchd's bare PATH
# or a plain shell), so the nix-managed zellij / open / osascript always win.
export PATH="/etc/profiles/per-user/$(id -un)/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/bin:/bin:${PATH:-}"

ZDIR="$HOME/.config/zellij"                       # the live, activated config
FLOAT="$ZDIR/float-term.sh"                        # the rice's ONE Ghostty spawner
PERMS="$HOME/Library/Caches/org.Zellij-Contributors.Zellij/permissions.kdl"

say() { printf '\033[38;5;103m🌫  %s\033[0m\n' "$*" >&2; }
die() { printf '\033[38;5;167m✗  %s\033[0m\n' "$*" >&2; exit 1; }

# The plugins we know how to swap, and the permission set each needs — mirrored
# from modules/hearth/default.nix's seedZellijPluginPermissions calls. A scratch
# plugin lives at a NEW path, so its grant isn't pre-seeded; we seed it here.
plugin_file() { # NAME -> the on-disk wasm basename hearth installs
  case "$1" in
    tab-bar)      echo "tab-bar.wasm" ;;
    status-bar)   echo "status-bar.wasm" ;;
    link-handler) echo "link-handler.wasm" ;;
    tab-history)  echo "tab-history.wasm" ;;
    *) return 1 ;;
  esac
}
plugin_perms() { # NAME -> space-separated permission list
  case "$1" in
    tab-bar)      echo "ReadApplicationState ChangeApplicationState" ;;
    status-bar)   echo "ReadApplicationState" ;;
    link-handler) echo "ReadApplicationState ChangeApplicationState FullHdAccess RunCommands ReadSessionEnvironmentVariables" ;;
    tab-history)  echo "ReadApplicationState ChangeApplicationState" ;;
    *) return 1 ;;
  esac
}

# Expand the rice's render tokens in-place. Harmless when the tokens are absent
# (an already-rendered file just passes through unchanged).
expand_tokens() { # <file>
  local f="$1" user6="${USER:0:6}" mode="$DEFAULT_MODE"
  # '|' delimiter: $HOME contains '/'. perl to avoid sed's in-place portability
  # warts and to keep all three replacements in one pass.
  HOME_="$HOME" U6="$user6" MODE="$mode" perl -0777 -i -pe '
    s/\@HOME\@/$ENV{HOME_}/g;
    s/\@username\@/$ENV{U6}/g;
    s/\@DEFAULT_MODE\@/$ENV{MODE}/g;
  ' "$f"
}

# Point every reference to plugin NAME (either ~/... or $HOME/... form) at the
# scratch copy, across the scratch config + layouts.
repoint_plugin() { # <scratch-dir> <NAME>
  local dir="$1" name="$2" wf; wf="$(plugin_file "$name")"
  local tgt="$dir/plugins/$wf"
  DIR_TGT="$tgt" HOME_="$HOME" WF="$wf" perl -0777 -i -pe '
    my $h = quotemeta($ENV{HOME_});
    my $w = quotemeta($ENV{WF});
    s{file:$h/\.config/zellij/plugins/$w}{file:$ENV{DIR_TGT}}g;
    s{file:~/\.config/zellij/plugins/$w}{file:$ENV{DIR_TGT}}g;
  ' "$dir"/config.kdl "$dir"/layouts/*.kdl 2>/dev/null || true
}

# Replace (or add) a plugin path's grant block in permissions.kdl. Idempotent:
# strips any existing block for that exact path first, then appends the fresh
# one. Keyed by the absolute path, so it never touches the installed plugins'
# grants (different keys). Mirrors the awk dance in hearth's seed helper.
seed_perms() { # <abs-wasm-path> <perm...>
  local path="$1"; shift
  mkdir -p "$(dirname "$PERMS")"
  local tmp="$PERMS.zscratch.$$"
  if [ -f "$PERMS" ]; then
    /usr/bin/awk -v open="\"$path\" {" \
      '$0 == open { skip = 1; next } skip && $0 == "}" { skip = 0; next } !skip' \
      "$PERMS" > "$tmp"
  else
    : > "$tmp"
  fi
  { printf '"%s" {\n' "$path"
    local p; for p in "$@"; do printf '    %s\n' "$p"; done
    printf '}\n'
  } >> "$tmp"
  mv "$tmp" "$PERMS"
}

# Drop every grant block whose path key lives under a scratch dir (…/zellij-
# scratch-…) — used by `clean` so stale scratch grants don't accumulate.
unseed_scratch_perms() {
  [ -f "$PERMS" ] || return 0
  local tmp="$PERMS.zscratch.$$"
  /usr/bin/awk '
    /^"[^"]*\/zellij-scratch-[^"]*" \{$/ { skip = 1; next }
    skip && $0 == "}" { skip = 0; next }
    !skip
  ' "$PERMS" > "$tmp"
  mv "$tmp" "$PERMS"
}

scratch_dir() { echo "${TMPDIR:-/tmp}/zellij-scratch-$1"; }

cmd_clean() {
  local dir; dir="$(scratch_dir "$NAME")"
  say "killing session '$NAME' and removing $dir"
  zellij delete-session --force "$NAME" >/dev/null 2>&1 || true
  rm -rf "$dir"
  unseed_scratch_perms
}

cmd_run() {
  [ -d "$ZDIR" ] || die "no live zellij config at $ZDIR — activate the rice first (this is a dev tool for an installed machine)"
  [ -x "$FLOAT" ] || [ "$PRINT" = 1 ] || die "missing $FLOAT — is the rice activated?"

  local dir; dir="$(scratch_dir "$NAME")"
  rm -rf "$dir"

  # Base = a faithful, deref'd copy of the working config (plain files, writable),
  # so anything we don't override is exactly what the machine runs today.
  cp -RL "$ZDIR" "$dir"
  chmod -R u+w "$dir"
  rm -f "$dir"/config.kdl.backup

  # Overlay the candidates, expanding render tokens on each.
  if [ -n "$CONFIG_SRC" ]; then cp "$CONFIG_SRC" "$dir/config.kdl"; expand_tokens "$dir/config.kdl"; fi
  if [ -n "$LAYOUT_SRC" ]; then
    cp "$LAYOUT_SRC" "$dir/layouts/custom.kdl"; expand_tokens "$dir/layouts/custom.kdl"
    # home.kdl is the Super-t "new tab at ~" variant: same layout, content tab
    # pinned to $HOME (mirrors hearth's replaceStrings). Keep it in step so a
    # scratch new-tab isn't testing a stale layout; harmless if the anchor line
    # isn't present.
    cp "$dir/layouts/custom.kdl" "$dir/layouts/home.kdl"
    HOME_="$HOME" perl -0777 -i -pe 's{\n    tab name="~" \{\n}{"\n    tab cwd=\"$ENV{HOME_}\" name=\"~\" {\n"}e' "$dir/layouts/home.kdl"
  fi
  if [ -n "$THEME_SRC" ]; then cp "$THEME_SRC" "$dir/themes/nebelung.kdl"; expand_tokens "$dir/themes/nebelung.kdl"; fi

  # If the candidate config still references @DEFAULT_MODE@'s neighbours via the
  # live copy, that copy is already rendered — nothing to do. But the base config
  # we copied has the *installed* default_mode baked in; honour --locked by
  # flipping it in the scratch config only.
  if [ "$LOCKED" = 1 ]; then
    perl -0777 -i -pe 's/default_mode\s+"[^"]*"/default_mode "locked"/' "$dir/config.kdl"
  fi

  # Swap any overridden plugin wasm, repoint the config/layouts at the scratch
  # copy, and seed its grant (a new path has no pre-seeded permission). Plugins
  # you DON'T override keep the installed path → they reuse the already-seeded
  # grant and the same wasm, no reseed needed.
  local spec name wasm
  for spec in "${PLUGINS[@]:-}"; do
    [ -n "$spec" ] || continue
    name="${spec%%=*}"; wasm="${spec#*=}"
    plugin_file "$name" >/dev/null || die "unknown plugin '$name' (want: tab-bar|status-bar|link-handler|tab-history)"
    [ -f "$wasm" ] || die "no such wasm: $wasm"
    cp "$wasm" "$dir/plugins/$(plugin_file "$name")"
    repoint_plugin "$dir" "$name"
    # shellcheck disable=SC2046
    seed_perms "$dir/plugins/$(plugin_file "$name")" $(plugin_perms "$name")
    say "swapped $name → $wasm"
  done

  if [ "$PRINT" = 1 ]; then
    say "rendered scratch config → $dir  (session '$NAME', not launched)"
    echo "$dir"
    return 0
  fi

  # A tiny launcher so the window survives the session ending, and so we get a
  # guaranteed-fresh server (delete any stale same-named session first → new
  # server → recompiled wasm). open -na spawns a clean env, but unset the ZELLIJ
  # vars defensively so a nested launch can never be refused.
  cat > "$dir/run.sh" <<RUN
#!/bin/zsh
export PATH="/etc/profiles/per-user/\$USER/bin:/run/current-system/sw/bin:\$PATH"
unset ZELLIJ ZELLIJ_SESSION_NAME ZELLIJ_PANE_ID
zellij delete-session --force "$NAME" >/dev/null 2>&1
zellij --config "$dir/config.kdl" --config-dir "$dir" -s "$NAME"
print -P '%F{244}── scratch session ended — close this window (⌘W) ──%f'
exec /bin/zsh -l
RUN
  chmod +x "$dir/run.sh"

  say "launching scratch session '$NAME' in a new window …"
  say "  config-dir: $dir"
  say "  clean up with:  zscratch clean${NAME:+ --name $NAME}"
  "$FLOAT" spawn --title "zellij ▸ $NAME" --pct 80 --pin --command "$dir/run.sh" >/dev/null
}

# ---- arg parsing ------------------------------------------------------------
NAME="scratch"; CONFIG_SRC=""; LAYOUT_SRC=""; THEME_SRC=""
DEFAULT_MODE="normal"; LOCKED=0; PRINT=0; ACTION="run"
PLUGINS=()

while [ $# -gt 0 ]; do
  case "$1" in
    clean)      ACTION="clean"; shift ;;
    # Spell out what's missing: a bare ${2:?} makes bash print its own
    # "line 229: 2: parameter null or not set", which names neither the flag
    # you typed nor what it wanted.
    --config)   CONFIG_SRC="${2:?--config needs a config.kdl (source or rendered)}"; shift 2 ;;
    --layout)   LAYOUT_SRC="${2:?--layout needs a layout .kdl}"; shift 2 ;;
    --theme)    THEME_SRC="${2:?--theme needs a theme .kdl}"; shift 2 ;;
    --plugin)   PLUGINS+=("${2:?--plugin needs NAME=path/to/plugin.wasm}"); shift 2 ;;
    --name)     NAME="${2:?--name needs a session name}"; shift 2 ;;
    --locked)   LOCKED=1; DEFAULT_MODE="locked"; shift ;;
    --print)    PRINT=1; shift ;;
    -h|--help)  sed -n '2,33p' "$0" | sed 's/^#\{0,1\} \{0,1\}//'; exit 0 ;;
    *)          die "unknown argument: $1 (try --help)" ;;
  esac
done

for f in "$CONFIG_SRC" "$LAYOUT_SRC" "$THEME_SRC"; do
  [ -z "$f" ] || [ -f "$f" ] || die "no such file: $f"
done

case "$ACTION" in
  clean) cmd_clean ;;
  run)   cmd_run ;;
esac

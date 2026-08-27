#!/bin/bash
# pounce: name = Install App
# pounce: description = Install from Homebrew, the Mac App Store, or Nixpkgs
# pounce: icon = square.and.arrow.down.on.square
# pounce: submenu = true
#
# App installer with a source picker:
#
#   • Homebrew       — fuzzy-searches the offline cask + formula catalog.
#   • Mac App Store  — searches with `mas`; `mas get` runs visibly so an account
#                       or Touch ID prompt can never wedge a rebuild.
#   • Nix packages   — searches the flake's pinned nixpkgs revision.
#
# Every selection becomes an ordinary Nix module under hosts/<host>/packages/,
# and always the SAME shape: one `haus.roster` entry naming its source
# (cask / brew / package / appStoreId). mkHaus auto-imports those files, so
# this command writes exactly what a person writes by hand.
#
# Mac App Store INSTALLATION stays imperative — `mas get` needs root (macOS 13+)
# and can't purchase a paid app or sign in at all, so it runs here, visibly,
# where a Touch ID/password prompt has a terminal to appear in. The declaration
# is still a native roster entry; a machine that opts into
# haus.appStore.install can then fetch it unattended.
#
# The flake lives at ~/.config/nix by convention (override with
# $HAUS_FLAKE or $HAUS_CONSUMER). The host is baked in by mkHaus and
# can be overridden with $HAUS_HOST.

# A launchd GUI agent's PATH is bare; resolve our tools (jq, brew, mas, nix,
# git, osascript, pounce) explicitly — same set windows bakes into AeroSpace.
export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/$USER/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

FLAKE_DIR="${HAUS_FLAKE:-${HAUS_CONSUMER:-$HOME/.config/nix}}"
HOST="${HAUS_HOST:-@hostname@}"
PACKAGES_DIR="$FLAKE_DIR/hosts/$HOST/packages"
CHEATSHEET="$HOME/.config/pounce/cheatsheet.json"
AEROSPACE_TOML="$HOME/.config/aerospace/aerospace.toml"
BREW_INDEX="$HOME/.cache/haus/brew-index.tsv"
BREW_API="$HOME/Library/Caches/Homebrew/api"
FLOAT_TERM="$HOME/.config/haus/term/float-term.sh"
APP_ICON_MAP="$(dirname "$0")/app-icon-map"
POPULAR_APPS="$(dirname "$0")/data/popular-apps.tsv"

field() { printf '%s' "$1" | cut -f"$2"; }
notice() {
  printf '%s\t%s\t%s\n' "$1" "$2" "${3:-exclamationmark.triangle}" \
    | pounce -p "Install App" -i "square.and.arrow.down.on.square" >/dev/null
}

nix_string() { jq -Rn --arg value "$1" '$value'; }
file_slug() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9._-]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

# ── which leader letters are already spoken for ───────────────────────────
# EVERY key launch mode binds, not just the roster's. The generated
# aerospace.toml's [mode.launch.binding] is the authority: roster launchers,
# their ⇧throws, the fixed built-ins (v clipboard, f Find Files, z reopen-last-app,
# `,` settings, `.` tiling cycle, ` resort, - / = resize) and any haus.keys.leaderExtras all
# land in that ONE table, which is exactly the set windows asserts against.
#
# Reading only the cheatsheet's Launch Mode rows was the bug: the built-ins
# render there as display glyphs ("v / f"), which never matched a bare-letter
# comparison — so "v" looked free, got offered, and the roster entry then
# collided with the clipboard binding at EVAL time (windows's
# rosterBuiltinCollisions assertion), failing the rebuild after the module was
# already written.
#
# `shift-x` counts as taking `x`: picking that letter generates both a launcher
# and a ⇧throw for it. The cheatsheet is still read as a second source so a
# missing/unreadable toml can only ever under-offer, never mis-offer.
launch_used_letters() {
  {
    awk '
      /^\[mode\.launch\.binding\]/ { in_block = 1; next }
      /^\[/                       { in_block = 0 }
      in_block && index($0, "=") {
        key = $0
        sub(/=.*/, "", key)
        gsub(/[[:space:]"'"'"']/, "", key)
        if (substr(key, 1, 1) == "#") next
        sub(/^shift-/, "", key)
        if (key ~ /^[a-z]$/) print key
      }
    ' "$AEROSPACE_TOML" 2>/dev/null

    # Split each cheatsheet key on non-letters and keep the single-letter
    # tokens, so "v / f" yields v and f while a legend row like "⇧ [Letter]"
    # yields the 6-letter word "letter" and is correctly ignored.
    jq -r '.[] | select(.title | test("Launch Mode")) | .items[].key // empty' \
      "$CHEATSHEET" 2>/dev/null \
      | tr -c 'a-zA-Z' '\n' \
      | tr '[:upper:]' '[:lower:]' \
      | awk 'length($0) == 1'
  } | sort -u
}

# ONE module shape, for every source and both lanes: a `haus.roster` entry,
# plus (when the app got its own workspace) a paired `haus.workspaces`
# entry naming it in `apps`. Which FIELDS the roster entry sets is what it
# means — a `key` puts it on the leader, neither makes it a plain install — so
# a cask, a formula, a Nixpkgs package and an App Store app all land in the
# same roster instead of half here and half in `homebrew.casks`. (Before the
# roster grew the brew/package/appStoreId fields this had to emit two
# different module shapes, which is exactly the split-brain the rice's
# modules/roster removed. Which WORKSPACE an app owns is a similar split now:
# the roster entry only ever names ITSELF, haus.workspaces.<id>.apps is
# what claims it.)
write_app_module() {
  local target="$1" resolved_app_id="${2:-$app_id}"
  local id_value id_lit key_lit name_lit app_id_lit icon_lit label_lit token_lit
  if [ "$type" = "mas" ]; then id_value="mas-$token"; else id_value="$token"; fi
  id_lit="$(nix_string "$id_value")"
  token_lit="$(nix_string "$token")"
  key_lit="$(nix_string "$key")"
  name_lit="$(nix_string "$appname")"
  label_lit="$(nix_string "$appname")"
  if [ -n "$resolved_app_id" ]; then app_id_lit="$(nix_string "$resolved_app_id")"; else app_id_lit="null"; fi
  if [ -n "$bar_icon" ]; then icon_lit="$(nix_string "$bar_icon")"; else icon_lit="null"; fi

  {
    printf '%s\n' '# Added by pounce "Install App". Safe to edit or remove.'
    if [ "$type" = "nixpkgs" ]; then
      printf '%s\n' '{ lib, pkgs, ... }:'
    else
      printf '%s\n' '{ lib, ... }:'
    fi
    printf '%s\n' '{'
    printf '  haus.roster.%s = {\n' "$id_lit"
    printf '    enable = lib.mkDefault true;\n'
    printf '    order = lib.mkDefault 1000;\n'
    if [ "$lane" = "Add to roster" ]; then
      printf '    key = lib.mkDefault %s;\n' "$key_lit"
      printf '    name = lib.mkDefault %s;\n' "$name_lit"
      printf '    appId = lib.mkDefault %s;\n' "$app_id_lit"
      printf '    label = lib.mkDefault %s;\n' "$label_lit"
    elif [ "$type" = "cask" ] || [ "$type" = "mas" ]; then
      # No leader key, but it IS a Mac app — record what `open -a` calls it.
      printf '    name = lib.mkDefault %s;\n' "$name_lit"
    fi
    case "$type" in
      cask) printf '    cask = lib.mkDefault %s;\n' "$token_lit" ;;
      brew) printf '    brew = lib.mkDefault %s;\n' "$token_lit" ;;
      mas) printf '    appStoreId = lib.mkDefault %s;\n' "$token" ;;
      nixpkgs)
        # Resolved from a dotted attr path so `python3Packages.foo` works, and
        # so a package that vanishes from nixpkgs fails by NAME rather than as
        # an "attribute missing" trace pointing into this generated file.
        # scope = "system" keeps pounce's long-standing behaviour: the old
        # install module wrote environment.systemPackages, which is also what
        # puts a GUI app in /Applications/Nix Apps.
        printf '    scope = lib.mkDefault "system";\n'
        printf '    package = lib.mkDefault (lib.attrByPath (lib.splitString "." %s)\n' "$token_lit"
        printf '      (throw ("pounce Install App: Nixpkgs package " + %s + " does not exist")) pkgs);\n' "$token_lit"
        ;;
    esac
    printf '%s\n' '  };'
    if [ -n "$workspace" ]; then
      printf '  haus.workspaces.%s = {\n' "$(nix_string "$workspace")"
      printf '    key = lib.mkDefault %s;\n' "$key_lit"
      printf '    icon = lib.mkDefault %s;\n' "$icon_lit"
      # A plain list, not lib.mkDefault: a fresh workspace this app owns
      # alone, so there's nothing to merge with — but a mkDefault list here
      # would still be the wrong habit to model (see the option's own docs).
      printf '    apps = [ %s ];\n' "$id_lit"
      printf '%s\n' '  };'
    fi
    printf '%s\n' '}'
  } >"$target"
}

# ── source ────────────────────────────────────────────────────────────────
# Popular is a rice-curated shelf, not another package-manager label. The
# backing casks stay private payload so this first step describes intent rather
# than exposing where an app happens to come from.
source_menu="$(printf '%s\t%s\t%s\t\t%s\n%s\t%s\t%s\t\t%s\n%s\t%s\t%s\t\t%s\n%s\t%s\t%s\t\t%s' \
  "Popular apps" "A curated shelf of useful Mac apps" "star" "Popular" \
  "Homebrew" "Apps (casks) and command-line tools (formulae)" "mug" "Browse by source" \
  "Mac App Store" "Search Apple's catalog; installs visibly with mas" "apple.logo" "Browse by source" \
  "Nix packages" "Packages from this flake's pinned Nixpkgs revision" "snowflake" "Browse by source")"
source_sel="$(printf '%s\n' "$source_menu" | pounce -p "Install App — from where?" -i "square.and.arrow.down.on.square")"
[ -z "$source_sel" ] && exit 0
source_name="$(field "$source_sel" 2)"

# Every result row has the same private payload after the five visible pounce
# fields: type, app name, package id, bundle id. Selection prepends the action,
# so those become fields 7–10 below.
list=""
query=""

# A search that misses used to be a dead end: the results list only offers its
# own rows, so the only way to try another word was Esc and start over. Every
# query-driven list therefore carries this escape hatch as its last row (and, on
# a miss, as its only one). `__again__` in the type slot means "ask me again".
#
# Its argument is display text, and this file quotes the user's words in it with
# curly quotes — so BRACE every expansion that touches one: `“${query}”`, never
# `“$query”`. In a UTF-8 locale (which is every real one here; LC_ALL=C is not
# affected) bash reads the closing ” as part of the identifier, looks up a
# variable named query”, and finds nothing — so the row loses the search term
# and emits the ”'s leftover bytes as invalid UTF-8 into pounce's TSV. Silent
# rather than fatal because this script has no `set -u`.
again_row() {
  printf '%s\t%s\t%s\t\t%s\t__again__\t\t\t' \
    "Search again" "$1" "magnifyingglass" "Search"
}

app_is_installed() {
  local token="$1" appname="$2" app_id="$3" path

  # This catches casks regardless of where their artifacts live, including
  # command-only or nested app installs. INSTALLED_CASKS is collected once for
  # the whole shelf; spawning Homebrew once per row makes opening it feel slow.
  if printf '%s\n' "$INSTALLED_CASKS" | grep -Fqx "$token"; then
    return 0
  fi

  # Also hide a matching app installed by hand, Setapp, or the App Store. The
  # direct paths are instant; Spotlight covers nested application bundles.
  for path in "/Applications/$appname.app" "$HOME/Applications/$appname.app"; do
    [ -d "$path" ] && return 0
  done
  if [ -n "$app_id" ] && command -v mdfind >/dev/null 2>&1; then
    {
      mdfind -onlyin /Applications "kMDItemCFBundleIdentifier == '$app_id'" 2>/dev/null
      [ -d "$HOME/Applications" ] \
        && mdfind -onlyin "$HOME/Applications" "kMDItemCFBundleIdentifier == '$app_id'" 2>/dev/null
    } | grep -q .
    [ "${PIPESTATUS[1]}" -eq 0 ] && return 0
  fi

  return 1
}

# ── Homebrew catalog ──────────────────────────────────────────────────────
# One TSV line per package: type \t token \t appname(open -a target) \t desc.
# Casks pull the app's real .app name from the cask's `app` artifact so the
# roster's `name` (and appId lookup) match what macOS actually installs.
#
# Homebrew 6 keeps ONE offline catalog for casks *and* formulae:
# api/internal/packages.<tag>.jws.json.payload — two concatenated JSON docs
# (a header, then the data), casks and formulae each an object keyed by token.
# The older split cask.jws.json / formula.jws.json is the fallback. Reading only
# those is what used to hide every GUI app: brew fetches formula.jws.json on any
# `brew update`, but cask.jws.json only when a cask command asks for it — so on
# a formula-only machine this index came out complete-looking and cask-free, and
# searching "discord" found nothing but CLI clients.
build_brew_index() {
  local tmp payload
  tmp="$(mktemp)" || return 1
  payload="$(ls -t "$BREW_API"/internal/packages.*.jws.json.payload 2>/dev/null | head -1)"
  if [ -n "$payload" ]; then
    jq -rn '
      inputs
      | select(has("casks") or has("formulae"))
      | ( (.casks // {}) | to_entries[]
          | [ "cask", .key,
              ((([ .value.raw_artifacts[]?
                   | select(type == "array" and .[0] == ":app")
                   | .[1] | if type == "array" then .[0] else . end ] | .[0])
                // .value.names[0] // .key) | sub("\\.app$"; "")),
              (.value.desc // "") ] | @tsv ),
        ( (.formulae // {}) | to_entries[]
          | [ "formula", .key, "", (.value.desc // "") ] | @tsv )
    ' "$payload" >"$tmp" 2>/dev/null
  fi
  if [ ! -s "$tmp" ]; then
    {
      jq -r '.payload | fromjson | .[] | try ([ "cask", .token,
          ((([.artifacts[]?.app? // empty] | flatten | .[0]) // .name[0] // .token) | sub("\\.app$"; "")),
          (.desc // "") ] | @tsv) catch empty' "$BREW_API/cask.jws.json" 2>/dev/null
      jq -r '.payload | fromjson | .[] | try ([ "formula", .name, "", (.desc // "") ] | @tsv) catch empty' \
        "$BREW_API/formula.jws.json" 2>/dev/null
    } >"$tmp"
  fi
  if [ -s "$tmp" ]; then
    mv "$tmp" "$BREW_INDEX"
  else
    rm -f "$tmp"
    return 1
  fi
}

while :; do
  list=""

  if [ "$source_name" = "Popular apps" ]; then
    INSTALLED_CASKS=""
    if command -v brew >/dev/null 2>&1; then
      INSTALLED_CASKS="$(brew list --cask 2>/dev/null || true)"
    fi
    while IFS=$'\t' read -r popular_token popular_name popular_desc popular_app_id; do
      [ -n "$popular_token" ] || continue
      app_is_installed "$popular_token" "$popular_name" "$popular_app_id" && continue
      printf -v popular_row '%s\t%s\t%s\t\t\tcask\t%s\t%s\t%s\n' \
        "$popular_name" "$popular_desc" "app.badge" \
        "$popular_name" "$popular_token" "$popular_app_id"
      list="$list$popular_row"
    done <"$POPULAR_APPS"

    if [ -z "$list" ]; then
      notice "You have all the popular picks" "Nothing from the curated shelf is missing" "checkmark.circle"
      exit 0
    fi
  fi

  if [ "$source_name" = "Homebrew" ]; then
    mkdir -p "$(dirname "$BREW_INDEX")"
    # A cask-free index is a stale one written before the fix above — rebuild it
    # rather than showing another GUI-app-less catalog.
    if [ ! -s "$BREW_INDEX" ] || ! grep -q '^cask	' "$BREW_INDEX"; then
      build_brew_index # first run (or cask-free): synchronous, one-time
    elif [ -n "$(find "$BREW_INDEX" -mtime +7 2>/dev/null)" ]; then
      (build_brew_index >/dev/null 2>&1 &) # stale: refresh in background, use current now
    fi

    if [ ! -s "$BREW_INDEX" ]; then
      notice "Run: brew update" "Homebrew catalog cache is empty — populate it, then retry"
      exit 0
    fi

    list="$(awk -F'\t' '{
      icon  = ($1 == "cask") ? "app.badge" : "terminal"
      group = ($1 == "cask") ? "Apps · Homebrew cask" : "CLI · Homebrew formula"
      printf "%s\t%s\t%s\t\t%s\t%s\t%s\t%s\t\n", $2, $4, icon, group, $1, $3, $2
    }' "$BREW_INDEX")"
  fi

  # ── Mac App Store catalog ───────────────────────────────────────────────
  if [ "$source_name" = "Mac App Store" ]; then
    if ! command -v mas >/dev/null 2>&1; then
      notice "mas is unavailable" "Rebuild haus to install its Mac App Store helper"
      exit 0
    fi
    # --chain: Enter here starts a network search, so pounce holds the window
    # with its loading skeleton instead of fading out and back in.
    if [ -z "$query" ]; then
      query_sel="$(printf '' | pounce --chain -p "Mac App Store — type a search, then Enter" -i "apple.logo")"
      [ -z "$query_sel" ] && exit 0
      query="$(field "$query_sel" 2)"
      [ -z "$query" ] && continue
    fi

    mas_results="$(mktemp)" || exit 1
    if ! mas search --json "$query" >"$mas_results" 2>/dev/null; then
      rm -f "$mas_results"
      notice "App Store search failed" "Check your connection, then try again"
      exit 0
    fi
    # mas emits one JSON object per line. Keep Mac-compatible apps and carry both
    # the numeric store id and bundle id into the selection payload. The order is
    # the App Store's own relevance ranking — pounce shows a piped list in the
    # order it was given, so don't re-sort it here.
    list="$(jq -rs '
      .[]
      | select(any(.supportedDevices[]?; startswith("Mac")))
      | [
          .name,
          ([.formattedPrice, .developerName, .primaryCategoryName] | map(select(. != null and . != "")) | join(" · ")),
          "apple.logo",
          "",
          "Apps · Mac App Store",
          "mas",
          .name,
          (.adamID | tostring),
          (.bundleID // "")
        ]
      | @tsv
    ' "$mas_results")"
    rm -f "$mas_results"
    if [ -z "$list" ]; then
      list="$(again_row "No Mac app matched “${query}” — try different words")"
    else
      list="$list
$(again_row "Not what you wanted? Search the App Store again")"
    fi
  fi

  # ── pinned Nixpkgs catalog ──────────────────────────────────────────────
  if [ "$source_name" = "Nix packages" ]; then
    if [ -z "$query" ]; then
      query_sel="$(printf '' | pounce --chain -p "Nixpkgs — type a search, then Enter" -i "snowflake")"
      [ -z "$query_sel" ] && exit 0
      query="$(field "$query_sel" 2)"
      [ -z "$query" ] && continue
    fi

    # Follow root → haus → nixpkgs in the consumer lock, then search that
    # exact revision. A direct root nixpkgs input is accepted as a fallback.
    #
    # The input NAME is the consumer's to choose; `bootstrap.sh` scaffolds
    # `haus`, which is what this looks for.
    nixpkgs_ref="$(jq -r '
      def node:
        if type == "array" then .[-1] else . end;
      . as $lock
      | (($lock.nodes[$lock.root].inputs.haus? // "") | node) as $haus
      | (
          if $haus == "" then
            ($lock.nodes[$lock.root].inputs.nixpkgs? // "" | node)
          else
            ($lock.nodes[$haus].inputs.nixpkgs? // "" | node)
          end
        ) as $nixpkgs
      | $lock.nodes[$nixpkgs].locked
      | if .type == "github" then
          "github:\(.owner)/\(.repo)/\(.rev)"
        elif .type == "tarball" then
          .url
        else
          empty
        end
    ' "$FLAKE_DIR/flake.lock" 2>/dev/null)"
    if [ -z "$nixpkgs_ref" ]; then
      notice "Pinned Nixpkgs not found" "The flake lock has no searchable nixpkgs input"
      exit 0
    fi

    # Treat the typed text literally even though `nix search` accepts regexes.
    query_regex="$(printf '%s' "$query" | sed 's/[][(){}.^$*+?|\\]/\\\\&/g')"
    nix_results="$(mktemp)" || exit 1
    nix_errors="$(mktemp)" || { rm -f "$nix_results"; exit 1; }
    if ! nix search "$nixpkgs_ref" "$query_regex" --json >"$nix_results" 2>"$nix_errors"; then
      detail="$(grep -m1 '^error:' "$nix_errors")"
      detail="${detail:-$(tail -n 1 "$nix_errors")}"
      rm -f "$nix_results" "$nix_errors"
      notice "Nixpkgs search failed" "${detail:-Check your connection, then try again}"
      exit 0
    fi
    rm -f "$nix_errors"
    # Strip Nix's system-qualified search prefix; the generated module resolves
    # the remaining attribute path against the host's already-overlaid `pkgs`.
    list="$(jq -r '
      to_entries[]
      | (.key | sub("^(legacyPackages|packages)\\.[^.]+\\."; "")) as $attr
      | [
          $attr,
          ([.value.pname, .value.version, .value.description] | map(select(. != null and . != "")) | join(" · ")),
          "snowflake",
          "",
          "Packages · pinned Nixpkgs",
          "nixpkgs",
          $attr,
          $attr,
          ""
        ]
      | @tsv
    ' "$nix_results")"
    rm -f "$nix_results"
    if [ -z "$list" ]; then
      list="$(again_row "No Nix package matched “${query}” — try different words")"
    else
      list="$list
$(again_row "Not what you wanted? Search Nixpkgs again")"
    fi
  fi

  # ── choose a result ─────────────────────────────────────────────────────
  # --chain again: typing words that match no row and pressing Enter is how you
  # re-search from here, and that too runs a search before the next pounce.
  if [ "$source_name" = "Popular apps" ]; then
    selected="$(printf '%s' "$list" | pounce -p "Install App — popular" -i "star")"
  else
    selected="$(printf '%s\n' "$list" | pounce --chain -p "Install App — search $source_name" -i "square.and.arrow.down.on.square")"
  fi
  [ -z "$selected" ] && exit 0

  type="$(field "$selected" 7)"
  appname="$(field "$selected" 8)"
  token="$(field "$selected" 9)"
  app_id="$(field "$selected" 10)"

  # The "Search again" row, or free text that matched no row (pounce hands it
  # back with an empty payload): both mean "search for this instead".
  if [ "$type" = "__again__" ]; then
    query=""
    continue
  fi
  if [ -z "$type" ]; then
    typed="$(field "$selected" 2)"
    if [ "$source_name" = "Homebrew" ]; then
      query=""     # the whole catalog is already here; just clear the filter
    else
      query="$typed"
    fi
    continue
  fi

  [ -z "$token" ] && exit 0
  [ -z "$appname" ] && appname="$token"
  break
done

# ── choose the lane ───────────────────────────────────────────────────────
if [ "$type" = "cask" ] || [ "$type" = "mas" ]; then
  lane_menu="$(printf '%s\t%s\t%s\n%s\t%s\t%s' \
    "Add to roster" "Install $appname + its own workspace and Caps-Lock leader key" "rectangle.3.group" \
    "Just install" "Install $appname only — no tiling, no hotkey" "square.and.arrow.down")"
  lane_sel="$(printf '%s\n' "$lane_menu" | pounce -p "$appname" -i "app.badge")"
  [ -z "$lane_sel" ] && exit 0
  lane="$(field "$lane_sel" 2)"
else
  lane="Just install"
fi

key=""
workspace=""
bar_icon=""

if [ "$lane" = "Add to roster" ]; then
  # ── pick a free leader letter ───────────────────────────────────────────
  # The live config already reflects hand-written and pounce-generated Nix
  # entries alike, including a module created by an earlier invocation.
  used="$(launch_used_letters)"
  key_list=""
  for L in a b c d e f g h i j k l m n o p q r s t u v w x y z; do
    printf '%s\n' "$used" | grep -qx "$L" && continue
    key_list="$key_list$L	Caps Lock then $L  →  launch $appname	keyboard
"
  done
  if [ -z "$key_list" ]; then
    printf 'No free leader letters left\tEvery a-z leader key is taken — free one first\texclamationmark.triangle\n' \
      | pounce -p "Install App" -i "keyboard" >/dev/null
    exit 0
  fi
  key_sel="$(printf '%s' "$key_list" | pounce -p "Leader key for $appname (Caps Lock + …)" -i "keyboard")"
  [ -z "$key_sel" ] && exit 0
  key="$(field "$key_sel" 2)"

  # ── workspace or launcher-only ──────────────────────────────────────────
  ws_menu="$(printf '%s\t%s\t%s\n%s\t%s\t%s' \
    "Own workspace" "Auto-move $appname to its own AeroSpace workspace + bar pill (leader ⇧$key throws to it)" "rectangle.split.3x1" \
    "Launcher-only" "Just the leader key — opens in the current workspace, no pill" "arrow.up.forward.app")"
  ws_sel="$(printf '%s\n' "$ws_menu" | pounce -p "$appname — workspace?" -i "rectangle.3.group")"
  [ -z "$ws_sel" ] && exit 0
  if [ "$(field "$ws_sel" 2)" = "Own workspace" ]; then
    # Workspace name = the leader letter, uppercased — the roster's convention
    # (t→T, b→B). Unique because leader keys are unique.
    workspace="$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"

    # sketchybar-app-font's own pinned map is the authority. Exact aliases and
    # upstream wildcard patterns resolve to a verified ligature; :default:
    # means "unknown", where keeping the workspace letter is more honest than
    # guessing an unrelated logo.
    if [ -x "$APP_ICON_MAP" ]; then
      candidate="$("$APP_ICON_MAP" "$appname" 2>/dev/null)"
      if [ -n "$candidate" ] && [ "$candidate" != ":default:" ]; then
        bar_icon="$candidate"
      fi
    fi
  fi
fi

# ── write one native Nix module ───────────────────────────────────────────
# Every path declares now, App Store installs included: `mas` still has to run
# imperatively (see below), but the ENTRY is a roster line like any other, so
# the app stops being invisible to the config just because Apple's installer
# can't be driven from Nix. File names are per-source so two sources shipping
# the same token can coexist.
slug="$(file_slug "$token")"
[ -n "$slug" ] || slug="package"
if [ "$lane" = "Add to roster" ]; then
  if [ "$type" = "mas" ]; then target_name="app-mas-$slug.nix"; else target_name="app-$slug.nix"; fi
else
  target_name="$type-$slug.nix"
fi
target_rel="hosts/$HOST/packages/$target_name"
target="$FLAKE_DIR/$target_rel"

if [ -e "$target" ]; then
  notice "Already declared" "$target_rel already manages $token — edit or remove that Nix module first" "checkmark.circle"
  exit 0
fi

mkdir -p "$PACKAGES_DIR"
write_app_module "$target.tmp"
mv "$target.tmp" "$target"

# ── install/rebuild in a floating terminal, rollback on failure ───────────
REBUILD_TMP="/tmp/haus-install-run.sh"
{
  printf 'FLAKE_DIR=%q\n' "$FLAKE_DIR"
  printf 'PACKAGES_DIR=%q\n' "$PACKAGES_DIR"
  printf 'TARGET=%q\n' "$target"
  printf 'TARGET_REL=%q\n' "$target_rel"
  printf 'LANE=%q\n' "$lane"
  printf 'APPNAME=%q\n' "$appname"
  printf 'WORKSPACE=%q\n' "$workspace"
  printf 'BAR_ICON=%q\n' "$bar_icon"
  printf 'TOKEN=%q\n' "$token"
  printf 'TYPE=%q\n' "$type"
  printf 'APP_ID=%q\n' "$app_id"
  cat <<'EOF'
export PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/$USER/bin:/opt/homebrew/bin:$PATH"
cd "$FLAKE_DIR" || exit 1

if [ "$TYPE" = "mas" ]; then
  echo "Getting $APPNAME from the Mac App Store…"
  echo "(App Store installs need root since macOS 13 — mas asks for your"
  echo " password or Touch ID here, which is why this runs in a terminal.)"
  echo
  if ! mas get "$TOKEN"; then
    echo
    echo "✗ The App Store could not install $APPNAME."
    echo "  Paid apps can't be bought from the command line, and mas has no"
    echo "  sign-in — both are finished in App Store.app, once."
    echo "  Opening its App Store page so you can do that there…"
    mas open "$TOKEN" 2>/dev/null || true
    [ -n "$TARGET" ] && rm -f "$TARGET" "$TARGET.tmp"
    [ -n "$TARGET_REL" ] && git add -A -- "$TARGET_REL" 2>/dev/null || true
    echo
    echo "Press any key to close…"
    read -n 1 -s
    rm -f "$0"
    exit 1
  fi

  echo
fi

# Flakes only read git-tracked files.
git add -- "$TARGET_REL"

if [ "$LANE" = "Add to roster" ]; then
  echo "Wiring $APPNAME — building & switching (haus rebuild)…"
  if [ -n "$BAR_ICON" ]; then
    echo "Verified SketchyBar icon: $BAR_ICON"
  elif [ -n "$WORKSPACE" ]; then
    echo "No SketchyBar App Font match — keeping workspace letter $WORKSPACE."
  fi
else
  echo "Installing $APPNAME — building & switching (haus rebuild)…"
fi
echo

if haus rebuild; then
  # A Homebrew cask may not expose its bundle id until the first activation.
  # Enrich the same generated module, then rebuild once for auto-herding.
  if [ "$LANE" = "Add to roster" ] && [ -n "$WORKSPACE" ] && [ -z "$APP_ID" ]; then
    appid="$(osascript -e "id of app \"$APPNAME\"" 2>/dev/null)"
    if [ -n "$appid" ]; then
      appid_lit="$(jq -Rn --arg value "$appid" '$value')"
      if sed "s/appId = lib.mkDefault null;/appId = lib.mkDefault $appid_lit;/" "$TARGET" >"$TARGET.tmp" \
        && mv "$TARGET.tmp" "$TARGET"; then
        git add -- "$TARGET_REL"
        echo
        echo "Resolved bundle id ($appid) — one more rebuild so windows auto-herd…"
        echo
        haus rebuild || true
      fi
    fi
  fi

  # No explicit bar/tiling reload here: the rebuild above already did both, via
  # the onChange hooks on the files it rewrites — bar's .haus-stamp (both bars,
  # modules/bar/default.nix) and windows's aerospace.toml (modules/windows). The
  # hand-rolled pair that used to live here predated those and had gone
  # asymmetric: it reloaded only the TOP bar, so on a machine running
  # haus.bar.bottom.enable an app added here left the bottom bar a generation
  # behind, silently.
  git commit -q -m "config: add $APPNAME via pounce Install App" -- "$TARGET_REL" 2>/dev/null || true
  echo
  if [ "$LANE" = "Add to roster" ]; then
    echo "✓ $APPNAME is installed and wired in $TARGET_REL."
  else
    echo "✓ $APPNAME is installed and declared in $TARGET_REL."
  fi
else
  echo
  echo "✗ Rebuild failed — removing the new Nix module."
  [ "$TYPE" = "mas" ] && echo "  $APPNAME remains installed from the Mac App Store."
  rm -f "$TARGET" "$TARGET.tmp"
  git add -A -- "$TARGET_REL" 2>/dev/null || true
fi
echo
echo "Press any key to close…"
read -n 1 -s
rm -f "$0"
EOF
} >"$REBUILD_TMP"

xattr -d com.apple.quarantine "$REBUILD_TMP" 2>/dev/null || true

if ! "$FLOAT_TERM" spawn \
  --title "quick-terminal-install" \
  --w 800 --h 480 --cols 84 --rows 24 \
  --pin \
  --command "bash $REBUILD_TMP" >/dev/null; then
  [ -n "$target" ] && rm -f "$target" "$target.tmp"
  rm -f "$REBUILD_TMP"
  rmdir "$PACKAGES_DIR" 2>/dev/null || true
  notice "Could not open installer" "The generated module was removed; your config is unchanged"
  exit 1
fi

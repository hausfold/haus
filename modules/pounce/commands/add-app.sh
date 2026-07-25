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
# Declarative selections become ordinary Nix modules under
# hosts/<host>/packages/. mkNebelhaus auto-imports those files, so this command
# uses the same nebelhaus.apps, Homebrew, and system-package options a person
# writes by hand. Mac App Store installation itself is necessarily imperative;
# an optional roster entry is still a native Nix module.
#
# The flake lives at ~/.config/nix by convention (override with
# $NEBELHAUS_FLAKE or $HAUS_CONSUMER). The host is baked in by mkNebelhaus and
# can be overridden with $HAUS_HOST.

# A launchd GUI agent's PATH is bare; resolve our tools (jq, brew, mas, nix,
# git, osascript, pounce) explicitly — same set prowl bakes into AeroSpace.
export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

FLAKE_DIR="${NEBELHAUS_FLAKE:-${HAUS_CONSUMER:-$HOME/.config/nix}}"
HOST="${HAUS_HOST:-@hostname@}"
PACKAGES_DIR="$FLAKE_DIR/hosts/$HOST/packages"
CHEATSHEET="$HOME/.config/pounce/cheatsheet.json"
BREW_INDEX="$HOME/.cache/nebelhaus/brew-index.tsv"
BREW_API="$HOME/Library/Caches/Homebrew/api"
FLOAT_TERM="$HOME/.config/zellij/float-term.sh"
APP_ICON_MAP="$(dirname "$0")/app-icon-map"

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

write_roster_module() {
  local target="$1" resolved_app_id="${2:-$app_id}"
  local id_value id_lit key_lit name_lit cask_lit app_id_lit icon_lit label_lit workspace_lit
  if [ "$type" = "mas" ]; then id_value="mas-$token"; else id_value="$token"; fi
  id_lit="$(nix_string "$id_value")"
  key_lit="$(nix_string "$key")"
  name_lit="$(nix_string "$appname")"
  label_lit="$(nix_string "$appname")"
  if [ "$type" = "cask" ]; then cask_lit="$(nix_string "$token")"; else cask_lit="null"; fi
  if [ -n "$resolved_app_id" ]; then app_id_lit="$(nix_string "$resolved_app_id")"; else app_id_lit="null"; fi
  if [ -n "$bar_icon" ]; then icon_lit="$(nix_string "$bar_icon")"; else icon_lit="null"; fi
  if [ -n "$workspace" ]; then workspace_lit="$(nix_string "$workspace")"; else workspace_lit="null"; fi

  {
    printf '%s\n' '# Added by pounce "Install App". Safe to edit or remove.'
    printf '%s\n' '{ lib, ... }:'
    printf '%s\n' '{'
    printf '  nebelhaus.apps.%s = {\n' "$id_lit"
    printf '    enable = lib.mkDefault true;\n'
    printf '    order = lib.mkDefault 1000;\n'
    printf '    key = lib.mkDefault %s;\n' "$key_lit"
    printf '    name = lib.mkDefault %s;\n' "$name_lit"
    printf '    workspace = lib.mkDefault %s;\n' "$workspace_lit"
    printf '    appId = lib.mkDefault %s;\n' "$app_id_lit"
    printf '    barIcon = lib.mkDefault %s;\n' "$icon_lit"
    printf '    label = lib.mkDefault %s;\n' "$label_lit"
    printf '    cask = lib.mkDefault %s;\n' "$cask_lit"
    printf '%s\n' '  };'
    printf '%s\n' '}'
  } >"$target"
}

write_install_module() {
  local target="$1" token_lit
  token_lit="$(nix_string "$token")"
  {
    printf '%s\n' '# Added by pounce "Install App". Safe to edit or remove.'
    if [ "$type" = "nixpkgs" ]; then
      printf '%s\n' '{ lib, pkgs, ... }:'
      printf '%s\n' '{'
      printf '%s\n' '  environment.systemPackages = ['
      printf '    (lib.attrByPath (lib.splitString "." %s)\n' "$token_lit"
      printf '      (throw ("pounce Install App: Nixpkgs package " + %s + " does not exist")) pkgs)\n' "$token_lit"
      printf '%s\n' '  ];'
    else
      printf '%s\n' '{'
      if [ "$type" = "cask" ]; then
        printf '  homebrew.casks = [ %s ];\n' "$token_lit"
      else
        printf '  homebrew.brews = [ %s ];\n' "$token_lit"
      fi
    fi
    printf '%s\n' '}'
  } >"$target"
}

# ── source ────────────────────────────────────────────────────────────────
source_menu="$(printf '%s\t%s\t%s\n%s\t%s\t%s\n%s\t%s\t%s' \
  "Homebrew" "Apps (casks) and command-line tools (formulae)" "mug" \
  "Mac App Store" "Search Apple's catalog; installs visibly with mas" "apple.logo" \
  "Nix packages" "Packages from this flake's pinned Nixpkgs revision" "snowflake")"
source_sel="$(printf '%s\n' "$source_menu" | pounce -p "Install App — from where?" -i "square.and.arrow.down.on.square")"
[ -z "$source_sel" ] && exit 0
source_name="$(field "$source_sel" 2)"

# Every result row has the same private payload after the five visible pounce
# fields: type, app name, package id, bundle id. Selection prepends the action,
# so those become fields 7–10 below.
list=""

# ── Homebrew catalog ──────────────────────────────────────────────────────
# One TSV line per package: type \t token \t appname(open -a target) \t desc.
# Casks pull the app's real .app name from the cask's `app` artifact so the
# roster's `name` (and appId lookup) match what macOS actually installs.
build_brew_index() {
  local tmp
  tmp="$(mktemp)" || return 1
  {
    jq -r '.payload | fromjson | .[] | try ([ "cask", .token,
        ((([.artifacts[]?.app? // empty] | flatten | .[0]) // .name[0] // .token) | sub("\\.app$"; "")),
        (.desc // "") ] | @tsv) catch empty' "$BREW_API/cask.jws.json" 2>/dev/null
    jq -r '.payload | fromjson | .[] | try ([ "formula", .name, "", (.desc // "") ] | @tsv) catch empty' \
      "$BREW_API/formula.jws.json" 2>/dev/null
  } >"$tmp"
  if [ -s "$tmp" ]; then
    mv "$tmp" "$BREW_INDEX"
  else
    rm -f "$tmp"
    return 1
  fi
}

if [ "$source_name" = "Homebrew" ]; then
  mkdir -p "$(dirname "$BREW_INDEX")"
  if [ ! -s "$BREW_INDEX" ]; then
    build_brew_index # first run: synchronous (one-time)
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

# ── Mac App Store catalog ─────────────────────────────────────────────────
if [ "$source_name" = "Mac App Store" ]; then
  if ! command -v mas >/dev/null 2>&1; then
    notice "mas is unavailable" "Rebuild nebelhaus to install its Mac App Store helper"
    exit 0
  fi
  query_sel="$(printf '' | pounce -p "Mac App Store — type a search, then Enter" -i "apple.logo")"
  [ -z "$query_sel" ] && exit 0
  query="$(field "$query_sel" 2)"
  [ -z "$query" ] && exit 0

  mas_results="$(mktemp)" || exit 1
  if ! mas search --json "$query" >"$mas_results" 2>/dev/null; then
    rm -f "$mas_results"
    notice "App Store search failed" "Check your connection, then try again"
    exit 0
  fi
  # mas emits one JSON object per line. Keep Mac-compatible apps and carry both
  # the numeric store id and bundle id into the selection payload.
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
    notice "No Mac apps found" "Try a broader App Store search"
    exit 0
  fi
fi

# ── pinned Nixpkgs catalog ────────────────────────────────────────────────
if [ "$source_name" = "Nix packages" ]; then
  query_sel="$(printf '' | pounce -p "Nixpkgs — type a search, then Enter" -i "snowflake")"
  [ -z "$query_sel" ] && exit 0
  query="$(field "$query_sel" 2)"
  [ -z "$query" ] && exit 0

  # Follow root → nebelhaus → nixpkgs in the consumer lock, then search that
  # exact revision. A direct root nixpkgs input is accepted as a fallback.
  nixpkgs_ref="$(jq -r '
    def node:
      if type == "array" then .[-1] else . end;
    . as $lock
    | ($lock.nodes[$lock.root].inputs.nebelhaus? // "" | node) as $haus
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
    detail="$(tail -n 1 "$nix_errors")"
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
    notice "No Nix packages found" "Try a broader package search"
    exit 0
  fi
fi

# ── choose a result ───────────────────────────────────────────────────────
selected="$(printf '%s\n' "$list" | pounce -p "Install App — search $source_name" -i "square.and.arrow.down.on.square")"
[ -z "$selected" ] && exit 0

type="$(field "$selected" 7)"
appname="$(field "$selected" 8)"
token="$(field "$selected" 9)"
app_id="$(field "$selected" 10)"
[ -z "$token" ] && exit 0
[ -z "$appname" ] && appname="$token"

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
  # The live cheatsheet already reflects hand-written and pounce-generated Nix
  # entries alike, including a module created by an earlier invocation.
  used="$(jq -r '.[] | select(.title | test("Launch Mode")) | .items[].key' "$CHEATSHEET" 2>/dev/null)"
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
    "Own workspace" "Auto-move $appname to its own AeroSpace workspace + bar pill (⌥⇧$key throws to it)" "rectangle.split.3x1" \
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
target=""
target_rel=""
if [ "$lane" = "Add to roster" ] || [ "$type" != "mas" ]; then
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
  if [ "$lane" = "Add to roster" ]; then
    write_roster_module "$target.tmp"
  else
    write_install_module "$target.tmp"
  fi
  mv "$target.tmp" "$target"
fi

# ── install/rebuild in a floating terminal, rollback on failure ───────────
REBUILD_TMP="/tmp/nebelhaus-install-run.sh"
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
  echo
  if ! mas get "$TOKEN"; then
    echo
    echo "✗ The App Store could not install $APPNAME."
    echo "  Opening its App Store page so you can finish there…"
    mas open "$TOKEN" 2>/dev/null || true
    [ -n "$TARGET" ] && rm -f "$TARGET" "$TARGET.tmp"
    [ -n "$TARGET_REL" ] && git add -A -- "$TARGET_REL" 2>/dev/null || true
    echo
    echo "Press any key to close…"
    read -n 1 -s
    rm -f "$0"
    exit 1
  fi

  if [ "$LANE" = "Just install" ]; then
    echo
    echo "✓ $APPNAME is installed."
    echo
    echo "Press any key to close…"
    read -n 1 -s
    rm -f "$0"
    exit 0
  fi
  echo
fi

# Flakes only read git-tracked files. The MAS install-only path above has no
# declaration and deliberately never touches the Git index.
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

  sketchybar --reload 2>/dev/null || true
  aerospace reload-config 2>/dev/null || true
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

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
#   • Nix packages   — searches the flake's pinned nixpkgs and appends the chosen
#                       attribute path to installs.json's nixpkgs[] list.
#
# Homebrew and Nix installs are declarative: the command appends structured data
# to files the flake reads (nebelhaus.prowl.rosterFile /
# nebelhaus.homebrew.installsFile), then runs `haus rebuild` in a floating
# terminal and rolls the append back if the build fails. Mac App Store installs
# are necessarily imperative (`mas get`); they run before any optional roster
# rebuild, in the same visible terminal.
#
# Host-agnostic: the flake lives at ~/.config/nix by convention (override with
# $NEBELHAUS_FLAKE), and the rebuild reuses `haus rebuild`, which resolves this
# machine's host attr + does the passwordless switch itself.

# A launchd GUI agent's PATH is bare; resolve our tools (jq, brew, mas, nix,
# git, osascript, pounce) explicitly — same set prowl bakes into AeroSpace.
export PATH="/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

FLAKE_DIR="${NEBELHAUS_FLAKE:-$HOME/.config/nix}"
ROSTER_JSON="$FLAKE_DIR/roster.json"
INSTALLS_JSON="$FLAKE_DIR/installs.json"
CHEATSHEET="$HOME/.config/pounce/cheatsheet.json"
BREW_INDEX="$HOME/.cache/nebelhaus/brew-index.tsv"
BREW_API="$HOME/Library/Caches/Homebrew/api"
FLOAT_TERM="$HOME/.config/zellij/float-term.sh"

field() { printf '%s' "$1" | cut -f"$2"; }
notice() {
  printf '%s\t%s\t%s\n' "$1" "$2" "${3:-exclamationmark.triangle}" \
    | pounce -p "Install App" -i "square.and.arrow.down.on.square" >/dev/null
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
  # Strip Nix's system-qualified search prefix; installsFile resolves the
  # remaining attribute path against the host's already-overlaid `pkgs`.
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

if [ "$lane" = "Add to roster" ]; then
  # ── pick a free leader letter ───────────────────────────────────────────
  # Taken letters = the live cheatsheet's Launch Mode page (the built roster,
  # host list included) plus anything already queued in roster.json.
  used="$(
    jq -r '.[] | select(.title | test("Launch Mode")) | .items[].key' "$CHEATSHEET" 2>/dev/null
    jq -r '.[].key' "$ROSTER_JSON" 2>/dev/null
  )"
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
  fi
fi

# ── stage the declarative edit (append + backup for rollback) ─────────────
if [ "$lane" = "Add to roster" ]; then
  [ -s "$ROSTER_JSON" ] || echo '[]' >"$ROSTER_JSON"
  cask=""
  [ "$type" = "cask" ] && cask="$token"
  entry="$(jq -n --arg key "$key" --arg name "$appname" --arg cask "$cask" --arg appId "$app_id" --arg label "$appname" --arg ws "$workspace" \
    '{ key: $key, name: $name, label: $label }
     + (if $cask == "" then {} else { cask: $cask } end)
     + (if $appId == "" then {} else { appId: $appId } end)
     + (if $ws == "" then {} else { workspace: $ws } end)')"
  cp "$ROSTER_JSON" "$ROSTER_JSON.bak"
  jq --argjson e "$entry" '. + [$e]' "$ROSTER_JSON.bak" >"$ROSTER_JSON" || { mv "$ROSTER_JSON.bak" "$ROSTER_JSON"; exit 1; }
elif [ "$type" != "mas" ]; then
  [ -s "$INSTALLS_JSON" ] || echo '{"casks":[],"brews":[],"nixpkgs":[]}' >"$INSTALLS_JSON"
  cp "$INSTALLS_JSON" "$INSTALLS_JSON.bak"
  if [ "$type" = "cask" ]; then
    jq --arg t "$token" '.casks = ((.casks // []) + [$t] | unique)' "$INSTALLS_JSON.bak" >"$INSTALLS_JSON" \
      || { mv "$INSTALLS_JSON.bak" "$INSTALLS_JSON"; exit 1; }
  elif [ "$type" = "formula" ]; then
    jq --arg t "$token" '.brews = ((.brews // []) + [$t] | unique)' "$INSTALLS_JSON.bak" >"$INSTALLS_JSON" \
      || { mv "$INSTALLS_JSON.bak" "$INSTALLS_JSON"; exit 1; }
  else
    jq --arg t "$token" '.nixpkgs = ((.nixpkgs // []) + [$t] | unique)' "$INSTALLS_JSON.bak" >"$INSTALLS_JSON" \
      || { mv "$INSTALLS_JSON.bak" "$INSTALLS_JSON"; exit 1; }
  fi
fi

# ── rebuild in a floating terminal, with rollback on failure ──────────────
# Reuses the shared float-term helper (same as rebuild.sh). Baked values are
# quoted with %q; the logic body is a literal (single-quoted) heredoc.
REBUILD_TMP="/tmp/nebelhaus-install-run.sh"
{
  printf 'FLAKE_DIR=%q\n' "$FLAKE_DIR"
  printf 'ROSTER_JSON=%q\n' "$ROSTER_JSON"
  printf 'INSTALLS_JSON=%q\n' "$INSTALLS_JSON"
  printf 'LANE=%q\n' "$lane"
  printf 'KEY=%q\n' "$key"
  printf 'APPNAME=%q\n' "$appname"
  printf 'WORKSPACE=%q\n' "$workspace"
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
    [ -f "$ROSTER_JSON.bak" ] && mv "$ROSTER_JSON.bak" "$ROSTER_JSON"
    git add roster.json 2>/dev/null || true
    echo
    echo "Press any key to close…"
    read -n 1 -s
    exit 1
  fi

  if [ "$LANE" = "Just install" ]; then
    echo
    echo "✓ $APPNAME is installed."
    echo
    echo "Press any key to close…"
    read -n 1 -s
    exit 0
  fi
  echo
fi

# Flakes only read git-tracked files — stage the data files before building.
# This deliberately happens after MAS's install-only fast path, which changes
# no config and must not touch the caller's Git index.
git add roster.json installs.json 2>/dev/null || true

if [ "$LANE" = "Add to roster" ]; then
  echo "Wiring $APPNAME — building & switching (haus rebuild)…"
else
  echo "Installing $APPNAME — building & switching (haus rebuild)…"
fi
echo
if haus rebuild; then
  # For a roster app with a workspace, the on-window-detected auto-herd rule
  # needs the bundle id, which only exists once the cask is installed. Resolve
  # it now and, if we didn't have it, patch the entry and rebuild once more so
  # the app's windows land on their workspace automatically.
  if [ "$LANE" = "Add to roster" ] && [ -n "$WORKSPACE" ]; then
    appid="$(osascript -e "id of app \"$APPNAME\"" 2>/dev/null)"
    have="$(jq -r --arg k "$KEY" '.[] | select(.key == $k) | .appId // ""' "$ROSTER_JSON" 2>/dev/null)"
    if [ -n "$appid" ] && [ -z "$have" ]; then
      jq --arg k "$KEY" --arg id "$appid" '(.[] | select(.key == $k) | .appId) |= $id' "$ROSTER_JSON" >"$ROSTER_JSON.tmp" \
        && mv "$ROSTER_JSON.tmp" "$ROSTER_JSON" && git add roster.json 2>/dev/null
      echo
      echo "Resolved bundle id ($appid) — one more rebuild so windows auto-herd…"
      echo
      haus rebuild || true
    fi
  fi
  # The rebuild rewrote the bar's workspace config + aerospace.toml, but the live
  # daemons keep their old state — a newly added workspace pill / launcher binding
  # won't show until they reload. Nudge both so the change is visible immediately.
  sketchybar --reload 2>/dev/null || true
  aerospace reload-config 2>/dev/null || true
  # Commit the change so the host tree stays clean (an uncommitted roster.json
  # otherwise blocks the next `bench ship`). Path-scoped, so nothing else you have
  # in flight is touched; push stays your call.
  git commit -q -m "config: add $APPNAME via pounce Install App" -- \
    "$(basename "$ROSTER_JSON")" "$(basename "$INSTALLS_JSON")" 2>/dev/null || true
  echo
  if [ "$LANE" = "Add to roster" ]; then
    echo "✓ $APPNAME is installed and wired."
  else
    echo "✓ $APPNAME is installed."
  fi
  rm -f "$ROSTER_JSON.bak" "$INSTALLS_JSON.bak"
else
  echo
  echo "✗ Rebuild failed — rolling back the declarative change."
  [ "$TYPE" = "mas" ] && echo "  $APPNAME remains installed from the Mac App Store."
  [ -f "$ROSTER_JSON.bak" ] && mv "$ROSTER_JSON.bak" "$ROSTER_JSON"
  [ -f "$INSTALLS_JSON.bak" ] && mv "$INSTALLS_JSON.bak" "$INSTALLS_JSON"
  git add roster.json installs.json 2>/dev/null || true
fi
echo
echo "Press any key to close…"
read -n 1 -s
EOF
} >"$REBUILD_TMP"

xattr -d com.apple.quarantine "$REBUILD_TMP" 2>/dev/null || true

"$FLOAT_TERM" spawn \
  --title "quick-terminal-install" \
  --w 800 --h 480 --cols 84 --rows 24 \
  --pin \
  --command "bash $REBUILD_TMP" >/dev/null

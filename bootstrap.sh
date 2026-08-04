#!/usr/bin/env bash
# nebelhaus bootstrap — raise the house on a fresh Mac.
#
#   curl -fsSL https://nebelhaus.com/init.sh | bash        (or the github raw URL)
#   nix run github:nebelhaus/nebelhaus#bootstrap           (once nix exists)
#
# It installs the prerequisites (Xcode CLT, Determinate Nix), runs a short
# interview, and scaffolds a THIN PERSONAL CONFIG at ~/.config/nix — a tiny flake
# of your own that consumes the nebelhaus rice as an input. You never edit (or
# even clone) the rice itself: your machine's identity, apps, and secrets live in
# your config; the rice stays upstream where `nix flake update nebelhaus` pulls it.
#
# Flags / env:
#   --defaults, NEBELHAUS_NONINTERACTIVE=1   skip the interview, take smart defaults
#   --from <url>, NEBELHAUS_FROM=<url>       RESTORE a config you already have in
#                                            git (a new/wiped Mac) instead of
#                                            scaffolding a fresh one — clones it,
#                                            skips the interview, prints the build
#   NEBELHAUS_DRY_RUN=1                       touch nothing: write the generated
#                                            config to a scratch dir and echo every
#                                            mutating step (for developing this script)
#   NEBELHAUS_DIR=<path>                      where the config lands (default ~/.config/nix)
#
# Idempotent: safe to re-run; it leaves an existing config alone.
set -euo pipefail

say()  { printf '\033[38;5;103m🌫  %s\033[0m\n' "$*"; }
warn() { printf '\033[38;5;179m⚠  %s\033[0m\n' "$*"; }
die()  { printf '\033[38;5;167m✗  %s\033[0m\n' "$*" >&2; exit 1; }

# run — do a MUTATING thing, or just show it under dry-run.
run() { if [ -n "$DRY_RUN" ]; then printf '\033[2m   [dry-run] %s\033[0m\n' "$*"; else "$@"; fi; }

# ---- config + flags -------------------------------------------------------
USERNAME="$(id -un)"
HOSTNAME="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"

NONINTERACTIVE="${NEBELHAUS_NONINTERACTIVE:-}"
DRY_RUN="${NEBELHAUS_DRY_RUN:-}"

# --from <url> / NEBELHAUS_FROM restores an existing config instead of scaffolding
# (see Phase 1b). Parse args here so --defaults still gates INTERACTIVE below.
FROM_URL="${NEBELHAUS_FROM:-}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --defaults) NONINTERACTIVE=1 ;;
    --from)     shift; FROM_URL="${1:-}"; [ -n "$FROM_URL" ] || die "--from needs a git URL (e.g. --from https://github.com/you/nix-config)" ;;
    --from=*)   FROM_URL="${1#--from=}" ;;
    *)          : ;;
  esac
  shift
done

# Dry-run can't prompt and mustn't touch the real config, so it's non-interactive
# and writes to a scratch dir.
if [ -n "$DRY_RUN" ]; then
  NONINTERACTIVE=1
  DEST="${NEBELHAUS_DIR:-$(mktemp -d)/nix}"
else
  DEST="${NEBELHAUS_DIR:-$HOME/.config/nix}"
fi

# Interactive only with a real TTY and no "stay quiet" flag — otherwise a piped
# `curl | bash` would hang waiting on stdin.
INTERACTIVE=1
{ [ -n "$NONINTERACTIVE" ] || [ ! -t 0 ]; } && INTERACTIVE=

# dflt — read a macOS default (read-only), or "unset" if it has no value yet.
dflt() { /usr/bin/defaults read "$1" "$2" 2>/dev/null || echo "unset"; }

# nix_default DOMAIN KEY TYPE [FALLBACK] — read a macOS default and print it as a
# nix literal for the host file. TYPE is bool|int|str. If the key is unset, print
# FALLBACK (itself a nix literal, e.g. false or '"bottom"') when given, else print
# nothing — so the rice's own default (a lib.mkDefault in modules/den) stays. This
# is how "keep my settings" turns your live macOS state into declarative config.
nix_default() {
  local raw
  if raw="$(/usr/bin/defaults read "$1" "$2" 2>/dev/null)"; then
    case "$3" in
      bool) case "$raw" in 1) echo true ;; 0) echo false ;; *) echo "${4:-}" ;; esac ;;
      int)  case "$raw" in '' | *[!0-9-]*) echo "${4:-}" ;; *) echo "$raw" ;; esac ;;
      str)  printf '"%s"' "$raw" ;;
    esac
  else
    echo "${4:-}"
  fi
}

# nix_float DOMAIN KEY FALLBACK — nix_default for a real. macOS stores these as
# reals but `defaults read` prints a whole one as "1", which `types.float` in
# nix-darwin rejects — so re-add the ".0" it dropped.
nix_float() {
  local raw
  raw="$(/usr/bin/defaults read "$1" "$2" 2>/dev/null)" || { echo "$3"; return; }
  case "$raw" in
    '' | *[!0-9.]*) echo "$3" ;;
    *.*) echo "$raw" ;;
    *) echo "$raw.0" ;;
  esac
}

# emit one host-file line, only when the value is non-empty (unset + no fallback).
emit() { [ -n "$2" ] && printf '  system.defaults.%s = %s;\n' "$1" "$2"; }

# settings_overrides — assemble the system.defaults block for the categories the
# user chose to KEEP (KEEP_DOCK / KEEP_KBD / KEEP_FINDER). Bool/string keys carry
# the macOS stock default as a fallback so an untouched knob is still captured
# faithfully; integer repeat rates fall back to the rice's default when unset
# (no reliable stock value to assume). AppleShowAllExtensions lives in both the
# finder and NSGlobalDomain option sets in the rice, so pin both to one read.
settings_overrides() {
  if [ -n "$KEEP_DOCK" ]; then
    emit dock.autohide     "$(nix_default com.apple.dock autohide bool false)"
    emit dock.orientation  "$(nix_default com.apple.dock orientation str '"bottom"')"
    emit dock.show-recents "$(nix_default com.apple.dock show-recents bool true)"
    emit dock.mru-spaces   "$(nix_default com.apple.dock mru-spaces bool true)"
  fi
  if [ -n "$KEEP_KBD" ]; then
    emit NSGlobalDomain.KeyRepeat                "$(nix_default -g KeyRepeat int)"
    emit NSGlobalDomain.InitialKeyRepeat         "$(nix_default -g InitialKeyRepeat int)"
    emit NSGlobalDomain.ApplePressAndHoldEnabled "$(nix_default -g ApplePressAndHoldEnabled bool true)"
    # Full keyboard access. The nix option is an enum (0/2/3), so anything else
    # macOS may have stored falls back to Apple's 0 rather than failing eval.
    local kbdui
    kbdui="$(nix_default -g AppleKeyboardUIMode int 0)"
    case "$kbdui" in 0 | 2 | 3) ;; *) kbdui=0 ;; esac
    emit NSGlobalDomain.AppleKeyboardUIMode "$kbdui"
  fi
  if [ -n "$KEEP_FINDER" ]; then
    local ext
    ext="$(nix_default -g AppleShowAllExtensions bool false)"
    emit finder.AppleShowAllExtensions         "$ext"
    emit NSGlobalDomain.AppleShowAllExtensions "$ext"
    emit finder.AppleShowAllFiles    "$(nix_default com.apple.finder AppleShowAllFiles bool false)"
    emit finder.FXPreferredViewStyle "$(nix_default com.apple.finder FXPreferredViewStyle str '"icnv"')"
    emit finder.ShowPathbar          "$(nix_default com.apple.finder ShowPathbar bool false)"
    emit finder.ShowStatusBar        "$(nix_default com.apple.finder ShowStatusBar bool false)"
    emit finder._FXSortFoldersFirst            "$(nix_default com.apple.finder _FXSortFoldersFirst bool false)"
    emit finder._FXSortFoldersFirstOnDesktop   "$(nix_default com.apple.finder _FXSortFoldersFirstOnDesktop bool false)"
    emit finder._FXShowPosixPathInTitle        "$(nix_default com.apple.finder _FXShowPosixPathInTitle bool false)"
    emit finder._FXEnableColumnAutoSizing      "$(nix_default com.apple.finder _FXEnableColumnAutoSizing bool true)"
    emit finder.FXDefaultSearchScope           "$(nix_default com.apple.finder FXDefaultSearchScope str '"SCev"')"
    emit finder.FXEnableExtensionChangeWarning "$(nix_default com.apple.finder FXEnableExtensionChangeWarning bool true)"
    emit finder.QuitMenuItem                   "$(nix_default com.apple.finder QuitMenuItem bool false)"
    emit finder.ShowHardDrivesOnDesktop         "$(nix_default com.apple.finder ShowHardDrivesOnDesktop bool false)"
    emit finder.ShowExternalHardDrivesOnDesktop "$(nix_default com.apple.finder ShowExternalHardDrivesOnDesktop bool true)"
    emit finder.ShowMountedServersOnDesktop     "$(nix_default com.apple.finder ShowMountedServersOnDesktop bool false)"
    emit finder.ShowRemovableMediaOnDesktop     "$(nix_default com.apple.finder ShowRemovableMediaOnDesktop bool true)"
    # NewWindowTarget is the one key whose nix option takes a friendly name
    # while macOS stores a four-letter code, so map it back. Unset means
    # Apple's "Recents".
    local nwt
    case "$(dflt com.apple.finder NewWindowTarget)" in
      PfCm) nwt='"Computer"'    ;; PfVo) nwt='"OS volume"' ;;
      PfHm) nwt='"Home"'        ;; PfDe) nwt='"Desktop"'   ;;
      PfDo) nwt='"Documents"'   ;; PfID) nwt='"iCloud Drive"' ;;
      PfLo) nwt=                ;; # "Other" needs NewWindowTargetPath too — leave both to the rice
      *)    nwt='"Recents"'     ;;
    esac
    emit finder.NewWindowTarget "$nwt"
    # The Finder-shaped half of NSGlobalDomain (see modules/den). Not captured:
    # the .DS_Store and empty-trash keys the rice sets through
    # CustomUserPreferences — those are litter/nag policy, not how Finder looks.
    emit NSGlobalDomain.NSTableViewDefaultSizeMode          "$(nix_default -g NSTableViewDefaultSizeMode int 3)"
    emit NSGlobalDomain.NSNavPanelExpandedStateForSaveMode  "$(nix_default -g NSNavPanelExpandedStateForSaveMode bool false)"
    emit NSGlobalDomain.NSNavPanelExpandedStateForSaveMode2 "$(nix_default -g NSNavPanelExpandedStateForSaveMode2 bool false)"
    emit NSGlobalDomain.NSDocumentSaveNewDocumentsToCloud   "$(nix_default -g NSDocumentSaveNewDocumentsToCloud bool true)"
    emit 'NSGlobalDomain."com.apple.springing.enabled"'     "$(nix_default -g com.apple.springing.enabled bool false)"
    emit 'NSGlobalDomain."com.apple.springing.delay"'       "$(nix_float -g com.apple.springing.delay 0.5)"
  fi
}

[ "$(uname)" = "Darwin" ] || die "nebelhaus is macOS-only."

# ---- Phase 0: prerequisites ----------------------------------------------

# A local APFS snapshot BEFORE anything mutates — the only coarse rewind point
# for the imperative layer (macOS defaults, ~/Library) that Nix generations
# cannot restore. Best-effort: warn, don't fail, if Time Machine isn't set up.
if [ -n "$DRY_RUN" ]; then
  run "tmutil localsnapshot"
elif tmutil localsnapshot >/dev/null 2>&1; then
  say "Took a local snapshot — a coarse pre-install rewind point."
else
  warn "Couldn't take a local snapshot (Time Machine not configured?). Continuing."
fi

# Xcode Command Line Tools (pounce compiles against system Swift; git lives here).
# Its installer is a GUI dialog — the one unavoidable two-step.
if ! /usr/bin/xcode-select -p >/dev/null 2>&1; then
  say "Installing Xcode Command Line Tools — approve the dialog, then re-run this."
  run /usr/bin/xcode-select --install
  [ -n "$DRY_RUN" ] || exit 0
fi

# Nix. den sets nix.enable=false and assumes Determinate owns /nix, so refuse a
# stock/Lix daemon rather than silently conflict with it.
if command -v nix >/dev/null 2>&1 || [ -x /nix/var/nix/profiles/default/bin/nix ]; then
  { [ -e /nix ] && [ ! -e /nix/receipt.json ] && [ -z "$DRY_RUN" ]; } \
    && die "Found a Nix at /nix that isn't Determinate (no /nix/receipt.json). nebelhaus expects the Determinate installer to own the daemon — uninstall the existing Nix first, then re-run."
  say "Nix already installed."
elif [ -e /nix ] && [ ! -e /nix/receipt.json ] && [ -z "$DRY_RUN" ]; then
  die "Found /nix without a Determinate receipt — uninstall the existing Nix first, then re-run."
else
  say "Installing Determinate Nix…"
  run sh -c 'curl -fsSL https://install.determinate.systems/nix | sh -s -- install --determinate'
  # shellcheck disable=SC1091
  [ -n "$DRY_RUN" ] || . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# ---- Phase 1b: restore an existing config (--from) ------------------------
# A new or wiped Mac converging on the machine you already described in git.
# The prerequisites above still ran; we clone your config and skip the interview
# and scaffold entirely — the opposite direction from a fresh install.
if [ -n "$FROM_URL" ]; then
  if [ -e "$DEST/flake.nix" ]; then
    say "You already have a config at $DEST — leaving it alone (pull it: git -C $DEST pull)."
  else
    say "Restoring your config from $FROM_URL → $DEST"
    run git clone "$FROM_URL" "$DEST"
  fi
  cat <<EOF

$(say "Your config is in place. Raise the house:")

    cd $DEST
    nix build .#darwinConfigurations.$HOSTNAME.system \\
      && sudo ./result/sw/bin/darwin-rebuild switch --flake .#$HOSTNAME

  If this Mac's hostname isn't a host in your config, pass the right one:
    --flake .#<hostname>   (list them:  nix eval $DEST#darwinConfigurations --apply builtins.attrNames)
  That first switch puts \`haus\` on your PATH; after it, a rebuild is: haus rebuild
EOF
  exit 0
fi

# ---- already have a config? leave it alone -------------------------------
if [ -e "$DEST/flake.nix" ]; then
  say "You already have a config at $DEST — leaving it alone."
  exit 0
fi

# ---- Phase 1: interview ---------------------------------------------------
# Defaults double as the non-interactive answers, and each is env-overridable so
# an unattended install can be scripted (and so --dry-run can exercise every
# branch): NEBELHAUS_GIT_NAME / _GIT_EMAIL / _ACCENT / _EDITOR / _ROOMS /
# _WALLPAPER.
GIT_NAME="${NEBELHAUS_GIT_NAME:-$(git config --global user.name  2>/dev/null || true)}"
GIT_EMAIL="${NEBELHAUS_GIT_EMAIL:-$(git config --global user.email 2>/dev/null || true)}"
GIT_SIGNING=""
ACCENT="${NEBELHAUS_ACCENT:-mauve}"
EDITOR_CHOICE="${NEBELHAUS_EDITOR:-hx}"
# Wallpaper: none (default — leave it alone) or orbits/constellation/flow/bold.
WALLPAPER="${NEBELHAUS_WALLPAPER:-none}"
ADOPT_CASKS=""
# Rooms: a comma list of the ones ON (default all three); omit one to disable it.
ROOMS="${NEBELHAUS_ROOMS:-sill,prowl,pounce}"
# Which named preset the generated config imports. A preset is a data-only rice
# (see the rice's presets/README.md) — the SAME mechanism a community rice uses,
# which is the point: the installer isn't a privileged path. Empty = none, which
# is what "Custom" picks, since a hand-chosen room set isn't a named thing.
PRESET_NAME="${NEBELHAUS_PRESET:-full}"
case ",$ROOMS," in *,sill,*)   ROOM_SILL=1   ;; *) ROOM_SILL=   ;; esac
case ",$ROOMS," in *,prowl,*)  ROOM_PROWL=1  ;; *) ROOM_PROWL=  ;; esac
case ",$ROOMS," in *,pounce,*) ROOM_POUNCE=1 ;; *) ROOM_POUNCE= ;; esac

# macOS settings to KEEP as your own instead of letting the rice restyle them —
# a comma list of dock,keyboard,finder. Empty (the default) means the rice sets
# all of them, exactly as before. Each kept category has its current values read
# and pinned into your host config (see settings_overrides above).
KEEP="${NEBELHAUS_KEEP:-}"
case ",$KEEP," in *,dock,*)     KEEP_DOCK=1   ;; *) KEEP_DOCK=   ;; esac
case ",$KEEP," in *,keyboard,*) KEEP_KBD=1    ;; *) KEEP_KBD=    ;; esac
case ",$KEEP," in *,finder,*)   KEEP_FINDER=1 ;; *) KEEP_FINDER= ;; esac

if [ -n "$INTERACTIVE" ]; then
  say "Fetching the interview UI (gum)…"
  GUM="$(nix build --no-link --print-out-paths nixpkgs#gum 2>/dev/null)/bin/gum" || GUM=""
  [ -x "$GUM" ] || { warn "couldn't fetch gum — falling back to defaults."; GUM=""; }
  if [ -n "$GUM" ]; then
    printf '\n'; say "A few questions to make it yours (Enter takes the default):"

    GIT_NAME="$("$GUM"  input --prompt "Git name › "  --value "$GIT_NAME"  --placeholder "Ada Lovelace")"
    GIT_EMAIL="$("$GUM" input --prompt "Git email › " --value "$GIT_EMAIL" --placeholder "ada@example.com")"

    # A preset seeds the optional rooms; only "Custom" opens the per-room
    # picker. It's pure sugar over the same ROOM_* toggles the NEBELHAUS_ROOMS
    # env var drives, so a scripted install stays a one-liner.
    PRESET="$(printf '%s\n%s\n%s\n%s' \
      'Full rice — menu bar, tiling, and the ⌘Space palette' \
      'Everyday — the same Mac without the developer tooling' \
      'Minimal — just the themed shell (add rooms later)' \
      'Custom — choose each room yourself' \
      | "$GUM" choose --header 'How much of the rice do you want?')"
    case "${PRESET:-Full}" in
      Everyday*)
        PRESET_NAME=everyday
        ;;
      Minimal*)
        PRESET_NAME=minimal
        ROOM_SILL=; ROOM_PROWL=; ROOM_POUNCE=
        ;;
      Custom*)
        PRESET_NAME=
        SELECTED="$(printf 'sill\nprowl\npounce' | "$GUM" choose --no-limit \
          --selected sill,prowl,pounce \
          --header 'Optional rooms (space toggles) — sill=menu bar · prowl=tiling · pounce=⌘Space palette:')"
        echo "$SELECTED" | grep -qx sill   || ROOM_SILL=
        echo "$SELECTED" | grep -qx prowl  || ROOM_PROWL=
        echo "$SELECTED" | grep -qx pounce || ROOM_POUNCE=
        ;;
      *)  # Full rice — every optional room on.
        PRESET_NAME=full
        ROOM_SILL=1; ROOM_PROWL=1; ROOM_POUNCE=1
        ;;
    esac

    ACCENT="$(printf 'mauve\nblue\nsapphire\nsky\nteal\ngreen\nyellow\npeach\nmaroon\nred\npink\nflamingo\nrosewater\nlavender' \
      | "$GUM" choose --header 'Accent colour:')"; ACCENT="${ACCENT:-mauve}"

    # Enter takes the shown default (orbits); Esc/skip keeps your wallpaper.
    WALLPAPER="$(printf 'orbits\nconstellation\nflow\nbold\nnone' \
      | "$GUM" choose --header 'Desktop wallpaper — Nebelung looks · bold follows your accent · none keeps yours:')"
    WALLPAPER="${WALLPAPER:-none}"

    EDITOR_CHOICE="$(printf 'hx\nnvim\nvim\nnano' | "$GUM" choose --header 'Default $EDITOR:')"
    EDITOR_CHOICE="${EDITOR_CHOICE:-hx}"

    # macOS settings: keep your own, or let the rice restyle them. Nothing
    # selected (the default) = the rice sets its tidy defaults, as before.
    # Selected = your current values are read now and pinned into your config,
    # overriding the rice — so your feel carries over to a fresh install.
    # The ’ below is a deliberate curly apostrophe: a plain ' would close the
    # single-quoted --header string. shellcheck SC1112 flags it either way.
    # shellcheck disable=SC1112
    KEPT="$(printf 'dock\nkeyboard\nfinder' | "$GUM" choose --no-limit \
      --header 'Keep your CURRENT macOS settings for (space toggles; none = use the rice’s):')"
    echo "$KEPT" | grep -qx dock     && KEEP_DOCK=1
    echo "$KEPT" | grep -qx keyboard && KEEP_KBD=1
    echo "$KEPT" | grep -qx finder   && KEEP_FINDER=1

    # Adopt existing casks so a future declarative rebuild never deletes them.
    if command -v brew >/dev/null 2>&1; then
      CASKS="$(brew list --cask 2>/dev/null | tr '\n' ' ')"
      if [ -n "${CASKS// /}" ] \
        && "$GUM" confirm "Adopt your $(echo "$CASKS" | wc -w | tr -d ' ') existing Homebrew casks into the config?"; then
        ADOPT_CASKS="$CASKS"
      fi
    fi
  fi
fi

# ---- Phase 1.5: preflight audit ------------------------------------------
# Read-only. Before writing anything, show what's already on this Mac and what
# the pending config will (and won't) change — so nothing is a surprise. Never
# deletes or modifies anything here; it only looks and reports.
preflight_audit() {
  printf '\n'; say "Preflight — what's already here, and what changes:"

  # Apps — nothing is ever removed (homebrew cleanup defaults to "none").
  if command -v brew >/dev/null 2>&1; then
    printf '  apps      %s Homebrew cask(s) installed — NONE removed (cleanup = none).\n' \
      "$(brew list --cask 2>/dev/null | wc -l | tr -d ' ')"
    [ -n "$ADOPT_CASKS" ] && printf '            %s adopted into your config so a rebuild keeps them.\n' \
      "$(echo "$ADOPT_CASKS" | wc -w | tr -d ' ')"
  else
    printf '  apps      no Homebrew yet — the rice installs it; nothing to remove.\n'
  fi

  # Dotfiles — the rice writes these as single files; an existing REAL one is
  # renamed to <file>.backup on the first switch (kept, never deleted). Files
  # already symlinked into the Nix store are managed, so they don't count. (The
  # rice's directory-based configs — zellij, sketchybar, … — are managed
  # per-file, so only a conflicting file *inside* them is ever backed up.)
  local managed=(
    "$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.config/starship.toml" "$HOME/.config/git/config"
  )
  local hits=() p link
  for p in "${managed[@]}"; do
    [ -e "$p" ] || continue
    link="$(readlink "$p" 2>/dev/null || true)"
    case "$link" in */nix/store/*) : ;; *) hits+=("${p/#$HOME/~}") ;; esac
  done
  if [ "${#hits[@]}" -gt 0 ]; then
    printf '  dotfiles  these already exist and will be saved as <file>.backup (kept, not deleted):\n'
    printf '              %s\n' "${hits[@]}"
  else
    printf '  dotfiles  no conflicting single-file dotfiles — nothing to back up.\n'
  fi

  # macOS settings the chosen rooms will change (current -> new), or that you
  # chose to KEEP (your current value pinned into the config). Read-only.
  printf '  settings  the rice will set these macOS defaults (reversible via the snapshot):\n'
  if [ -n "$KEEP_DOCK" ]; then
    printf '              Dock:                 kept as yours (autohide/orientation/recents pinned)\n'
  else
    printf '              Dock autohide:        %s -> true\n'          "$(dflt com.apple.dock autohide)"
  fi
  if [ -n "$KEEP_KBD" ]; then
    printf '              Keyboard:             kept as yours (repeat rate + press-and-hold pinned)\n'
  else
    printf '              Key repeat (fast):    KeyRepeat %s -> 2\n'   "$(dflt -g KeyRepeat)"
  fi
  if [ -n "$KEEP_FINDER" ]; then
    printf '              Finder:               kept as yours (extensions/view/bars pinned)\n'
  else
    printf '              Show file extensions: %s -> true\n'          "$(dflt -g AppleShowAllExtensions)"
  fi
  [ -n "$ROOM_SILL" ]   && printf '              Hide native menu bar: %s -> true (Sill draws its own)\n' "$(dflt -g _HIHideMenuBar)"
  [ -n "$ROOM_PROWL" ]  && printf '              Caps Lock -> a leader key for tiling + the app launcher\n'
  [ -n "$ROOM_POUNCE" ] && printf '              ⌘Space   -> the pounce palette (disabled for Spotlight)\n'
  [ "$WALLPAPER" != "none" ] && printf '              Desktop wallpaper:    set to the Nebelung "%s" look (your current one is not deleted)\n' "$WALLPAPER"

  printf '  undo      nothing is switched until you run the build below; the snapshot\n'
  printf '            taken above + `darwin-rebuild --rollback` revert it.\n'
}
preflight_audit

# Nothing has been written yet — this is the last read-only moment. Require an
# explicit yes before scaffolding (interactive only; --defaults just proceeds).
if [ -n "$INTERACTIVE" ] && [ -n "${GUM:-}" ] && ! "$GUM" confirm "Write this config to $DEST and continue?"; then
  printf '\n'; say "OK — nothing was written. Re-run any time."
  exit 0
fi

# ---- Phase 2: scaffold ----------------------------------------------------
say "Scaffolding your config at $DEST"
run mkdir -p "$DEST/hosts/$HOSTNAME"
mkdir -p "$DEST/hosts/$HOSTNAME"   # for real even in dry-run, so we can write into it

# A named preset is imported as an ordinary extra module — exactly how someone
# would import a rice they found online. Import order carries no priority, so an
# option the preset SETS is a conflict until the host says `lib.mkForce`; an
# option it leaves alone the host sets outright (presets/README.md).
PRESET_LINE=""
[ -n "$PRESET_NAME" ] && PRESET_LINE="
        extraModules = [ nebelhaus.presets.$PRESET_NAME ];"

cat >"$DEST/flake.nix" <<EOF
{
  description = "$USERNAME's machine — a nebelhaus";

  # The whole rice (system + shell + pounce + nebelung) comes from the public
  # nebelhaus flake. This config holds only what's personal: the host.
  # Update everything with:  nix flake update nebelhaus
  inputs.nebelhaus.url = "github:nebelhaus/nebelhaus";

  outputs =
    { nebelhaus, ... }:
    {
      darwinConfigurations.$HOSTNAME = nebelhaus.mkNebelhaus {
        username = "$USERNAME";
        hostname = "$HOSTNAME";
        host = ./hosts/$HOSTNAME;$PRESET_LINE
      };
    };
}
EOF

# Assemble the optional host lines (omit anything left at the rice default).
opt_lines=""
[ -z "$ROOM_SILL" ]   && opt_lines+="  nebelhaus.sill.enable = false;"$'\n'
[ -z "$ROOM_PROWL" ]  && opt_lines+="  nebelhaus.prowl.enable = false;"$'\n'
[ -z "$ROOM_POUNCE" ] && opt_lines+="  nebelhaus.pounce.enable = false;"$'\n'
[ "$ACCENT" != "mauve" ] && opt_lines+="  nebelhaus.theme.accent = \"$ACCENT\";"$'\n'
[ "$WALLPAPER" != "none" ] && opt_lines+="  nebelhaus.theme.wallpaper = \"$WALLPAPER\";"$'\n'
[ "$EDITOR_CHOICE" != "hx" ] && opt_lines+="  nebelhaus.hearth.editor = \"$EDITOR_CHOICE\";"$'\n'
[ -n "$opt_lines" ] && opt_lines=$'\n'"$opt_lines"
cask_lines=""
for c in $ADOPT_CASKS; do cask_lines+="    \"$c\""$'\n'; done

# Kept macOS settings — your current values, read now (read-only) and pinned so
# they win over the rice's lib.mkDefault opinions. Empty unless you chose to keep
# a category, so a default install writes no system.defaults and behaves as before.
settings_lines="$(settings_overrides)"
settings_block=""
[ -n "$settings_lines" ] && settings_block=$'\n'"  # ---- macOS settings kept as yours (read at install) ----"$'\n'"$settings_lines"

# ---- the annotated option catalogue ---------------------------------------
# hosts/<host>/options.nix: every nebelhaus.* option at its default, described,
# docs-linked, and commented out. It's how you find out an option exists without
# leaving your editor — read it, uncomment what you want, delete the rest.
#
# Rendered from the rice's own module system (`nix build .#host-template`), so
# it lists the options that exist at the revision you're about to pin, not
# upstream's latest. That's a real flake fetch, so it's best-effort: a machine
# that's offline, or pinning a rice older than the output, gets a config that
# works exactly as before and a pointer to `haus options`.
say "Rendering the option catalogue (every nebelhaus.* option, annotated)"
IMPORTS_LINE=""
if tmpl="$(nix build --no-link --print-out-paths \
             "${NEBELHAUS_FLAKE:-github:nebelhaus/nebelhaus}#host-template" 2>/dev/null)" \
   && [ -f "$tmpl/share/nebelhaus/host-options.nix" ]; then
  cp -f "$tmpl/share/nebelhaus/host-options.nix" "$DEST/hosts/$HOSTNAME/options.nix"
  chmod u+w "$DEST/hosts/$HOSTNAME/options.nix"   # it comes out of the store read-only
  IMPORTS_LINE="  imports = [ ./options.nix ]; # every nebelhaus.* option, annotated — read it
"
else
  warn "couldn't render the option catalogue (offline?) — run 'haus options' after your first rebuild."
fi

cat >"$DEST/hosts/$HOSTNAME/default.nix" <<EOF
# $HOSTNAME — your machine. The personal layer on top of the nebelhaus rice:
# identity, apps, secrets. A plain nix-darwin module; everything else is the rice.
{ ... }:

{
$IMPORTS_LINE
  # ---- identity ----
  nebelhaus.git.name = "$GIT_NAME";
  nebelhaus.git.email = "$GIT_EMAIL";
  nebelhaus.git.signingKey = "$GIT_SIGNING"; # GPG key id; "" disables signing.

  # pounce code-signing identity (SHA-1 from: security find-identity -v -p codesigning).
  # "" runs pounce unsigned — the palette works, Accessibility features stay off.
  nebelhaus.pounce.signingIdentity = "";
$opt_lines$settings_block
  # Homebrew never deletes an undeclared cask by default (cleanup = "none"); set
  # nebelhaus.homebrew.cleanup = "zap" only once every app you keep is listed.
  # Your apps — merged with what the rooms install (ghostty, aerospace):
  homebrew.casks = [
$cask_lines  ];
}
EOF

printf 'result\nresult-*\n' >"$DEST/.gitignore"

if [ ! -d "$DEST/.git" ]; then
  run git -C "$DEST" init -q -b main
  run git -C "$DEST" add -A
  run git -C "$DEST" commit -qm "Scaffold a nebelhaus consumer for $HOSTNAME"
fi

# ---- closing: how to raise it, and the honest undo card -------------------
cat <<EOF

$(say "Your config is written. Review it, then raise the house:")

    cd $DEST
    nix build .#darwinConfigurations.$HOSTNAME.system \\
      && sudo ./result/sw/bin/darwin-rebuild switch --flake .#$HOSTNAME

  Build first, switch second — a failed build never touches a running system.
  That first switch puts \`haus\` on your PATH; after it, a rebuild is: haus rebuild
  and \`haus doctor\` confirms everything came up.
EOF

[ -f "$DEST/hosts/$HOSTNAME/options.nix" ] && cat <<EOF

$(say "Two files are yours to edit:")

    hosts/$HOSTNAME/default.nix   who you are, and your apps — short on purpose
    hosts/$HOSTNAME/options.nix   EVERY nebelhaus.* option, at its default,
                                  described, docs-linked, and commented out

  Read the second one to learn what exists; uncomment a line to change it, and
  delete every line you never touched. \`haus options\` refreshes it after an
  update. Everything in it is inert until you uncomment something.
EOF

cat <<EOF

$(say "Before you switch — what nebelhaus can and can't undo:")

  CAN undo     everything Nix manages (packages, agents, shell config, PATH):
                 sudo darwin-rebuild --rollback        instant, atomic
               Nix itself, entirely (daemon, /nix volume):
                 sudo /nix/nix-installer uninstall      Determinate, clean
               a dotfile it replaced:  restore the .backup it saved (once)

  CANNOT undo  macOS system settings it changed (Dock, keyboard) — these persist
               after a rollback; use the local snapshot taken above, or revert by
               hand in System Settings.
               Homebrew casks/brews — left in place; remove with brew uninstall --zap.

$(say "Later: push $DEST to a private repo of your own — it's your machine in text.")
EOF

# Dry-run: show what got generated so the run is inspectable end to end.
if [ -n "$DRY_RUN" ]; then
  echo; say "[dry-run] generated $DEST/hosts/$HOSTNAME/default.nix:"
  sed 's/^/    /' "$DEST/hosts/$HOSTNAME/default.nix"
  # Not dumped — it's ~1000 lines. The count is the useful signal: it proves the
  # render ran and how much of the surface it covered.
  [ -f "$DEST/hosts/$HOSTNAME/options.nix" ] && say "[dry-run] generated $DEST/hosts/$HOSTNAME/options.nix: $(grep -c '^  # nebelhaus\.' "$DEST/hosts/$HOSTNAME/options.nix") options"
fi

# ---- optional: raise it right now ------------------------------------------
# One more consent gate turns the two-command install into one. Interactive
# only — scripted/--defaults runs keep the old contract (scaffold, print the
# command, stop), and declining changes nothing: the command is already on
# screen above. Build first; a failed build activates nothing.
if [ -n "$INTERACTIVE" ] && [ -z "$DRY_RUN" ] && [ -n "${GUM:-}" ] \
  && "$GUM" confirm "Raise the house now? (build first — nothing activates if the build fails)"; then
  say "Building $HOSTNAME — the first build downloads the world; later ones are fast…"
  if (cd "$DEST" && nix build ".#darwinConfigurations.$HOSTNAME.system"); then
    say "Build OK — switching (sudo will ask once)…"
    if (cd "$DEST" && sudo ./result/sw/bin/darwin-rebuild switch --flake ".#$HOSTNAME"); then
      printf '\n'; say "The house stands. A quick health check:"
      /run/current-system/sw/bin/haus doctor || true
      printf '\n'; say "From here: haus edit · haus rebuild · haus doctor — the haus tour is waiting in the bar (or type: haus tour), and ⇪ then / opens the cheatsheet."
    else
      warn "Switch failed — the build is intact; re-run the switch command above once you've fixed the error."
    fi
  else
    warn "Build failed — nothing was activated. Fix the error above, then re-run the build command."
  fi
fi

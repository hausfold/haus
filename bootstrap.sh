#!/usr/bin/env bash
# haus bootstrap — raise the house on a fresh Mac.
#
#   curl -fsSL https://hausfold.co/hacker.sh | bash        (or the github raw URL)
#   nix run github:hausfold/haus#bootstrap             (once nix exists)
#
# It installs the prerequisites (Xcode CLT, Determinate Nix), runs a short
# interview, and scaffolds a THIN PERSONAL CONFIG at ~/.config/nix — a tiny flake
# of your own that consumes haus as an input. You never edit (or even clone)
# haus itself: your machine's identity, apps and secrets live in your config;
# haus stays upstream, where `nix flake update haus` pulls it.
#
# Flags / env:
#   --defaults, HAUS_NONINTERACTIVE=1   skip the interview, take smart defaults —
#                                       including Determinate's own confirmation
#                                       of the Nix install, which an unattended
#                                       run has no terminal to answer
#   --desktop <name>, HAUS_DESKTOP=<name>    pick the desktop up front — one of
#                                            hacker, everyday, minimal, blank
#                                            — and SKIP that question, in an
#                                            interactive run too. This is what
#                                            hausfold.co/<name>.sh sets for you:
#                                            typing the URL is answering the
#                                            question, so being asked it again
#                                            reads as the installer not
#                                            listening. Every other answer is
#                                            still asked for.
#   --from <url>, HAUS_FROM=<url>       RESTORE a config you already have in
#                                            git (a new/wiped Mac) instead of
#                                            scaffolding a fresh one — clones it,
#                                            skips the interview, prints the build
#   HAUS_DRY_RUN=1                       touch nothing: write the generated
#                                            config to a scratch dir and echo every
#                                            mutating step (for developing this
#                                            script). Still interviews you when
#                                            there's a terminal — add --defaults
#                                            for a silent one.
#   HAUS_DIR=<path>                      where the config lands (default ~/.config/nix)
#
# Idempotent: safe to re-run; it leaves an existing config alone.
set -euo pipefail

# ── nebelung, inlined ────────────────────────────────────────────────────────
# This script and `modules/core/haus-activate.sh` are the only two places in the
# family that spell a colour NUMBER instead of naming a role, and this comment
# is the whole of the exemption: both run before snug is reachable. This one is
# a standalone `curl … | bash` on a Mac with no nix at all, so there is no
# `share/ui.sh` to source and no `snug` to drive — but "cannot source it" was
# never a licence to pick a hue by eye, which is how `say` ended up on index 103
# (a BLUE) on the one screen a new user sees before anything else.
#
# So the numbers are COPIED, never chosen. Every one is snug's generated
# `share/ui.sh` for the `nebelung` variant — the variant ui.sh itself resolves
# to when nothing has written ~/.config/snug/variant, which is exactly this
# machine — and `test/installer-palette.bats` diffs all of them against that
# file, so a nebelung that moves reds the suite instead of drifting quietly.
# Never hand-pick an index here; take it from the generated tables.
#
#   role    token     hex      x256  ansi16   what it says
#   accent  mauve     c9a8f1   183   95       the fog — ordinary narration
#   warn    peach     f5b58e   216   93       wants attention
#   err     red       ed8fa9   211   91       failure
#   muted   overlay1  858585   102   90       secondary detail (the dry-run echo)
UI_HEX_ACCENT=c9a8f1; UI_X256_ACCENT=183; UI_ANSI_ACCENT=95
UI_HEX_WARN=f5b58e;   UI_X256_WARN=216;   UI_ANSI_WARN=93
UI_HEX_ERR=ed8fa9;    UI_X256_ERR=211;    UI_ANSI_ERR=91
UI_HEX_MUTED=858585;  UI_X256_MUTED=102;  UI_ANSI_MUTED=90

# ui.sh's own precedence, ported rather than re-derived: NO_COLOR beats
# everything except CLICOLOR_FORCE, a non-TTY is colourless unless forced, and
# `dumb` means it under CLICOLOR_FORCE too — there is no escape a dumb terminal
# will not print at you literally. Bash 3.2 clean, because `curl … | bash` on a
# fresh Mac IS /bin/bash 3.2: no associative arrays, no `${v,,}`.
ui_profile() { # ui_profile <non-empty if that stream is a tty> -> none|16|256|truecolor
  local forced=''
  case "${CLICOLOR_FORCE:-}" in '' | 0) ;; *) forced=1 ;; esac
  if [ -n "${NO_COLOR+set}" ] && [ -z "$forced" ]; then printf none; return 0; fi
  if [ -z "$1" ] && [ -z "$forced" ]; then printf none; return 0; fi
  if [ "${TERM:-}" = dumb ]; then printf none; return 0; fi
  case "${COLORTERM:-}" in
    truecolor | 24bit | TRUECOLOR | 24BIT) printf truecolor; return 0 ;;
  esac
  case "${TERM:-}" in
    *truecolor* | *direct*) printf truecolor ;;
    *256*)                  printf 256 ;;
    # Forced with nothing to go on — a CI log renderer, usually. 256 is the safe
    # middle: universally understood, and a small step from the hex.
    '')                     printf 256 ;;
    *)                      printf 16 ;;
  esac
  return 0
}

ui_sgr() { # ui_sgr <profile> <accent|warn|err|muted>
  # Emptied, and with a default arm below: an unknown role must return NO
  # colour, never die. `${hex:0:2}` on an unset name is fatal under `set -u`,
  # and in bootstrap.sh that is an installer that aborts on a fresh Mac over a
  # caller's typo — the one failure mode a painter must never have.
  local hex='' x256='' ansi=''
  case "$2" in
    accent) hex=$UI_HEX_ACCENT; x256=$UI_X256_ACCENT; ansi=$UI_ANSI_ACCENT ;;
    warn)   hex=$UI_HEX_WARN;   x256=$UI_X256_WARN;   ansi=$UI_ANSI_WARN ;;
    err)    hex=$UI_HEX_ERR;    x256=$UI_X256_ERR;    ansi=$UI_ANSI_ERR ;;
    muted)  hex=$UI_HEX_MUTED;  x256=$UI_X256_MUTED;  ansi=$UI_ANSI_MUTED ;;
    *)      return 0 ;;
  esac
  case "$1" in
    truecolor) printf '\033[38;2;%s;%s;%sm' \
                 "$((16#${hex:0:2}))" "$((16#${hex:2:2}))" "$((16#${hex:4:2}))" ;;
    256)       printf '\033[38;5;%sm' "$x256" ;;
    16)        printf '\033[%sm' "$ansi" ;;
  esac
  return 0
}

# TWO gates, because which stream a line lands on is a property of the LINE
# here. Unlike every other family CLI this script is a report that also mutates:
# the whole preflight — the audit, the settings table, the undo note — is plain
# stdout prose, so `say`/`warn`/`run` are gated on fd 1 alongside it, and only
# `die` draws on fd 2. Asking one gate about both streams is what makes
# `bootstrap.sh | tee log` either escape-littered or silently monochrome.
_tty1=; [ -t 1 ] && _tty1=1
_tty2=; [ -t 2 ] && _tty2=1
_prof1="$(ui_profile "$_tty1")"
_prof2="$(ui_profile "$_tty2")"
C_OFF=; C_ACCENT=; C_WARN=; C_MUT=; E_OFF=; E_ERR=
[ "$_prof1" != none ] && {
  C_OFF=$'\033[0m'
  C_ACCENT="$(ui_sgr "$_prof1" accent)"
  C_WARN="$(ui_sgr "$_prof1" warn)"
  C_MUT="$(ui_sgr "$_prof1" muted)"
}
[ "$_prof2" != none ] && { E_OFF=$'\033[0m'; E_ERR="$(ui_sgr "$_prof2" err)"; }
unset _tty1 _tty2 _prof1 _prof2

say()  { printf '%s≋  %s%s\n' "$C_ACCENT" "$*" "$C_OFF"; }
warn() { printf '%s⚠  %s%s\n' "$C_WARN" "$*" "$C_OFF"; }
die()  { printf '%s✗  %s%s\n' "$E_ERR" "$*" "$E_OFF" >&2; exit 1; }

# run — do a MUTATING thing, or just show it under dry-run.
run() { if [ -n "$DRY_RUN" ]; then printf '%s   [dry-run] %s%s\n' "$C_MUT" "$*" "$C_OFF"; else "$@"; fi; }

# ---- config + flags -------------------------------------------------------
USERNAME="$(id -un)"
HOSTNAME="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"

# Homebrew, found by PATH *or* by path. Its shellenv is installed into
# ~/.zprofile, and `curl … | bash` is a non-login bash that never sources it —
# so `command -v brew` misses an installed Homebrew, the audit says "no
# Homebrew yet" on a Mac full of casks, and the adopt-your-casks question is
# never asked. Both prefixes: Apple silicon and Intel.
BREW="$(command -v brew 2>/dev/null || true)"
if [ -z "$BREW" ]; then
  for c in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$c" ] && { BREW="$c"; break; }
  done
fi

NONINTERACTIVE="${HAUS_NONINTERACTIVE:-}"
DRY_RUN="${HAUS_DRY_RUN:-}"

# --from <url> / HAUS_FROM restores an existing config instead of scaffolding
# (see Phase 1b). Parse args here so --defaults still gates INTERACTIVE below.
FROM_URL="${HAUS_FROM:-}"
# --desktop <name> picks the desktop up front. Parsed here rather than beside
# DESKTOP_NAME below because the flag has to be seen before the interview is
# assembled, and because "was it given at all?" is the thing we need to know —
# DESKTOP_NAME defaults to `hacker`, so its value alone can't distinguish a
# choice from a default.
DESKTOP_ARG="${HAUS_DESKTOP:-${HAUS_PRESET:-}}"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --defaults)  NONINTERACTIVE=1 ;;
    --from)      shift; FROM_URL="${1:-}"; [ -n "$FROM_URL" ] || die "--from needs a git URL (e.g. --from https://github.com/you/nix-config)" ;;
    --from=*)    FROM_URL="${1#--from=}" ;;
    --desktop)   shift; DESKTOP_ARG="${1:-}"; [ -n "$DESKTOP_ARG" ] || die "--desktop needs a name (hacker, everyday, minimal or blank)" ;;
    --desktop=*) DESKTOP_ARG="${1#--desktop=}" ;;
    *)           : ;;
  esac
  shift
done

# Dry-run mustn't touch the real config, so it writes to a scratch dir. It DOES
# still interview you when there's a terminal — that's the only way to exercise
# the interview without a real install, and it's how this script gets tested.
if [ -n "$DRY_RUN" ]; then
  DEST="${HAUS_DIR:-$(mktemp -d)/nix}"
else
  DEST="${HAUS_DIR:-$HOME/.config/nix}"
fi

# fd 3 is the QUESTION channel — the terminal itself, kept apart from stdin.
#
# Under the documented one-liner — `curl … | bash` — bash is reading THIS SCRIPT on
# stdin, which has two consequences that have to be handled separately:
#
#   * `[ -t 0 ]` is false for every normal install, so testing stdin to decide
#     whether to interview skipped the interview for everyone. The terminal is
#     still there; /dev/tty is how you reach it.
#   * fd 0 must keep pointing at the script. Hand a prompt fd 0 — or redirect the
#     shell's own stdin to the tty — and gum reads the remaining bytes of this
#     file as keystrokes; the install then just stops, silently, mid-run.
#
# So: open the terminal once, on a spare descriptor, and point each prompt at it
# (`<&3`). A run with no controlling terminal at all — CI, a container,
# `< /dev/null` — can't open /dev/tty, gets /dev/null instead, and takes the
# defaults rather than hanging on a prompt, which is what the old stdin test was
# really protecting.
#
# The output test matters as much as the tty one: gum draws on STDERR, so a run
# whose output is captured (`curl … | bash > install.log 2>&1`, a provisioning
# wrapper, `| tee`) still has a terminal to read from but no terminal to draw on
# — it would sit at an invisible prompt forever. Under the plain one-liner fd 1
# and fd 2 are both still the terminal; only fd 0 is the pipe. If NEITHER is,
# nobody is watching, so take the defaults.
#
# The probe runs in a subshell on purpose: `set -e` makes a failed redirection on
# the `exec` builtin exit a non-interactive shell outright, so the one-line
# `exec 3</dev/tty || exec 3</dev/null` never reaches its fallback.
if { [ -t 1 ] || [ -t 2 ]; } && (exec 3</dev/tty) 2>/dev/null; then
  exec 3</dev/tty
  HAVE_TTY=1
else
  exec 3</dev/null
  HAVE_TTY=
fi

INTERACTIVE=1
if [ -n "$NONINTERACTIVE" ] || [ -z "$HAVE_TTY" ]; then INTERACTIVE=; fi

# dflt — read a macOS default (read-only), or "unset" if it has no value yet.
dflt() { /usr/bin/defaults read "$1" "$2" 2>/dev/null || echo "unset"; }

# nix_default DOMAIN KEY TYPE [FALLBACK] — read a macOS default and print it as a
# nix literal for the host file. TYPE is bool|int|str. If the key is unset, print
# FALLBACK (itself a nix literal, e.g. false or '"bottom"') when given, else print
# nothing — so haus's own default (a lib.mkDefault in modules/core) stays. This
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
# faithfully; integer repeat rates fall back to haus's default when unset
# (no reliable stock value to assume). AppleShowAllExtensions lives in both the
# finder and NSGlobalDomain option sets in haus, so pin both to one read.
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
      PfLo) nwt=                ;; # "Other" needs NewWindowTargetPath too — leave both to haus
      *)    nwt='"Recents"'     ;;
    esac
    emit finder.NewWindowTarget "$nwt"
    # The Finder-shaped half of NSGlobalDomain (see modules/core). Not captured:
    # the .DS_Store and empty-trash keys haus sets through
    # CustomUserPreferences — those are litter/nag policy, not how Finder looks.
    emit NSGlobalDomain.NSTableViewDefaultSizeMode          "$(nix_default -g NSTableViewDefaultSizeMode int 3)"
    emit NSGlobalDomain.NSNavPanelExpandedStateForSaveMode  "$(nix_default -g NSNavPanelExpandedStateForSaveMode bool false)"
    emit NSGlobalDomain.NSNavPanelExpandedStateForSaveMode2 "$(nix_default -g NSNavPanelExpandedStateForSaveMode2 bool false)"
    emit NSGlobalDomain.NSDocumentSaveNewDocumentsToCloud   "$(nix_default -g NSDocumentSaveNewDocumentsToCloud bool true)"
    emit 'NSGlobalDomain."com.apple.springing.enabled"'     "$(nix_default -g com.apple.springing.enabled bool false)"
    emit 'NSGlobalDomain."com.apple.springing.delay"'       "$(nix_float -g com.apple.springing.delay 0.5)"
  fi
}

[ "$(uname)" = "Darwin" ] || die "haus is macOS-only."

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

# Nix. core sets nix.enable=false and assumes Determinate owns /nix, so refuse a
# stock/Lix daemon rather than silently conflict with it.
if command -v nix >/dev/null 2>&1 || [ -x /nix/var/nix/profiles/default/bin/nix ]; then
  { [ -e /nix ] && [ ! -e /nix/receipt.json ] && [ -z "$DRY_RUN" ]; } \
    && die "Found a Nix at /nix that isn't Determinate (no /nix/receipt.json). haus expects the Determinate installer to own the daemon — uninstall the existing Nix first, then re-run."
  say "Nix already installed."
elif [ -e /nix ] && [ ! -e /nix/receipt.json ] && [ -z "$DRY_RUN" ]; then
  die "Found /nix without a Determinate receipt — uninstall the existing Nix first, then re-run."
else
  say "Installing Determinate Nix…"
  # Their installer confirms before it touches anything, and reaches for
  # /dev/tty to ask when stdin is a pipe — which it always is under the
  # one-liner, so a person at a terminal gets the question and it works. A run
  # with NO controlling terminal (--defaults over ssh, CI, a provisioning
  # wrapper) has no /dev/tty to reach, and it exits with "Unable to run
  # interactively" instead of taking the defaults we already promised. So an
  # unattended install has to say --no-confirm on its own behalf; asking to be
  # asked is the one thing --defaults means it won't do.
  if [ -n "$INTERACTIVE" ]; then
    run sh -c 'curl -fsSL https://install.determinate.systems/nix | sh -s -- install --determinate'
  else
    run sh -c 'curl -fsSL https://install.determinate.systems/nix | sh -s -- install --determinate --no-confirm'
  fi
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
# branch): HAUS_GIT_NAME / _GIT_EMAIL / _ACCENT / _EDITOR / _GUI_EDITOR /
# _GUI_EDITOR_APP / _ROOMS / _WALLPAPER.
GIT_NAME="${HAUS_GIT_NAME:-$(git config --global user.name  2>/dev/null || true)}"
GIT_EMAIL="${HAUS_GIT_EMAIL:-$(git config --global user.email 2>/dev/null || true)}"
GIT_SIGNING=""
ACCENT="${HAUS_ACCENT:-mauve}"
# An editor NAME (helix, neovim, vim, nano), not a command — see the prompt
# below and modules/lib/editors.nix.
EDITOR_CHOICE="${HAUS_EDITOR:-helix}"
# A GUI editor's CLI command (e.g. "code -w"), or empty to use the terminal
# editor above for $EDITOR/$VISUAL and every "open in an editor" action.
# Installs nothing on its own — see the prompt below and
# haus.terminal.editor's own doc.
GUI_EDITOR_CMD="${HAUS_GUI_EDITOR:-}"
# The matching `haus.apps.<name>.enable` to flip on, for the three GUI
# editors haus knows how to install (vscode/cursor/zed) — empty for "Other"
# or "none", where haus doesn't know what app the command even points at.
GUI_EDITOR_APP="${HAUS_GUI_EDITOR_APP:-}"
# Wallpaper: the generated `minimal` haus look (default, matching the desktop's own
# haus.wallpaper.style), one of the inherited Nebelung ones, or `none` to leave
# whatever you already have exactly where it is.
WALLPAPER="${HAUS_WALLPAPER:-minimal}"
ADOPT_CASKS=""
# Rooms: a comma list of the ones ON (default all three); omit one to disable it.
ROOMS="${HAUS_ROOMS:-bar,windows,launcher}"
# Which DESKTOP the generated config selects — the one complete answer to "what
# should this Mac feel like?", chosen exactly once and overridable line by line
# from your host. The same mechanism a published desktop uses, which is the
# point: the installer isn't a privileged path. Empty selects none explicitly,
# which is what "Custom" picks (a hand-chosen room set isn't a named thing) and
# leaves the builder's own default, the hacker desktop, in place.
#
# `HAUS_PRESET` is the pre-rooms name for the same thing and still read: `full`
# names the hacker desktop now, and `everyday`/`minimal` are desktops of their
# own.
# All of those spellings, plus `--desktop`, land in DESKTOP_ARG up in the flag
# block; DESKTOP_EXPLICIT is the bit that matters here, because it is what lets
# the interview below skip a question it already has the answer to.
DESKTOP_EXPLICIT=""
DESKTOP_NAME="${DESKTOP_ARG:-hacker}"
# `full` is the pre-rooms spelling of this same desktop. It resolves here rather
# than in the case below, so the name stays out of the desktop list.
if [ "$DESKTOP_NAME" = "full" ]; then DESKTOP_NAME=hacker; fi
if [ -n "$DESKTOP_ARG" ]; then
  DESKTOP_EXPLICIT=1
  # Checked against a list rather than against the repo, because nothing is
  # cloned yet at this point. A typo has to fail HERE, loudly: an unknown name
  # would otherwise reach the generated flake as
  # `desktop = haus.desktops.<typo>;` and surface as a Nix eval error
  # after the download, which is a long way to walk to be told you misspelled
  # a word.
  case "$DESKTOP_NAME" in
    hacker|everyday|minimal|blank) : ;;
    *) die "unknown desktop '$DESKTOP_NAME' — pick one of: hacker, everyday, minimal, blank" ;;
  esac
fi
# Every token has to BE a room. The case tests below only ever look for a name
# they know, so an unrecognised one reads as "that room is off" — which is how
# a stale `HAUS_ROOMS=sill,prowl,pounce` would quietly build a machine with no
# bar and no tiling rather than say the names had moved.
for _room in $(printf '%s' "$ROOMS" | tr ',' ' '); do
  case "$_room" in
    bar | windows | launcher) : ;;
    *) die "unknown room '$_room' in HAUS_ROOMS — pick from: bar, windows, launcher" ;;
  esac
done
case ",$ROOMS," in *,bar,*)      ROOM_BAR=1      ;; *) ROOM_BAR=      ;; esac
case ",$ROOMS," in *,windows,*)  ROOM_WINDOWS=1  ;; *) ROOM_WINDOWS=  ;; esac
case ",$ROOMS," in *,launcher,*) ROOM_LAUNCHER=1 ;; *) ROOM_LAUNCHER= ;; esac

# macOS settings to KEEP as your own instead of letting haus restyle them —
# a comma list of dock,keyboard,finder. Empty (the default) means haus sets
# all of them, exactly as before. Each kept category has its current values read
# and pinned into your host config (see settings_overrides above).
KEEP="${HAUS_KEEP:-}"
case ",$KEEP," in *,dock,*)     KEEP_DOCK=1   ;; *) KEEP_DOCK=   ;; esac
case ",$KEEP," in *,keyboard,*) KEEP_KBD=1    ;; *) KEEP_KBD=    ;; esac
case ",$KEEP," in *,finder,*)   KEEP_FINDER=1 ;; *) KEEP_FINDER= ;; esac

if [ -n "$INTERACTIVE" ]; then
  say "Fetching the interview UI (gum)…"
  GUM="$(nix build --no-link --print-out-paths nixpkgs#gum 2>/dev/null)/bin/gum" || GUM=""
  [ -x "$GUM" ] || { warn "couldn't fetch gum — falling back to defaults."; GUM=""; }
  if [ -n "$GUM" ]; then
    printf '\n'; say "A few questions to make it yours (Enter takes the default):"

    # `<&3` on every prompt that doesn't already have its own stdin: fd 0 is the
    # script under `curl | bash`, and gum would eat it. The `choose` calls below
    # take their ITEMS on stdin, so they keep the pipe and reach the terminal
    # themselves — leave those alone or they lose their list.
    GIT_NAME="$("$GUM"  input --prompt "Git name › "  --value "$GIT_NAME"  --placeholder "Ada Lovelace" <&3)"
    GIT_EMAIL="$("$GUM" input --prompt "Git email › " --value "$GIT_EMAIL" --placeholder "ada@example.com" <&3)"

    # Already answered — by `--desktop`, by HAUS_DESKTOP, or by the URL the
    # person typed, which is how hausfold.co/minimal.sh works. Say what was
    # chosen and how to change it, then move on. Asking anyway would read as
    # the installer not listening, and it is the one question here whose
    # answer arrives before the interview starts.
    #
    # The rooms are deliberately NOT seeded on this path, unlike the branches
    # below. ROOM_* only ever writes `haus.<room>.enable = false;` into the
    # HOST file, which sits above the desktop in the priority ladder — so
    # seeding them here would hard-code a subtraction the desktop already
    # makes, and freeze this machine's answer to a question the desktop should
    # keep owning. Leaving them alone lets `desktops/<name>.nix` decide, which
    # is the whole point of selecting one.
    if [ -n "$DESKTOP_EXPLICIT" ]; then
      say "Desktop: $DESKTOP_NAME (you asked for this one — change it any time in your host file)"
    else
    # A desktop seeds the optional rooms; only "Custom" opens the per-room
    # picker. It's pure sugar over the same ROOM_* toggles the HAUS_ROOMS
    # env var drives, so a scripted install stays a one-liner.
    DESKTOP="$(printf '%s\n%s\n%s\n%s' \
      'Hacker — the full desktop: menu bar, tiling, and the ⌘Space palette' \
      'Everyday — the same Mac without the developer tooling' \
      'Minimal — just the themed shell (add rooms later)' \
      'Custom — choose each room yourself' \
      | "$GUM" choose --header 'Which desktop do you want?')"
    case "${DESKTOP:-Hacker}" in
      Everyday*)
        DESKTOP_NAME=everyday
        ROOM_WINDOWS=
        ;;
      Minimal*)
        DESKTOP_NAME=minimal
        ROOM_BAR=; ROOM_WINDOWS=; ROOM_LAUNCHER=
        ;;
      Custom*)
        DESKTOP_NAME=
        SELECTED="$(printf 'bar\nwindows\nlauncher' | "$GUM" choose --no-limit \
          --selected bar,windows,launcher \
          --header 'Optional rooms (space toggles) — bar=menu bar · windows=tiling · launcher=⌘Space palette:')"
        echo "$SELECTED" | grep -qx bar      || ROOM_BAR=
        echo "$SELECTED" | grep -qx windows  || ROOM_WINDOWS=
        echo "$SELECTED" | grep -qx launcher || ROOM_LAUNCHER=
        ;;
      *)  # The hacker desktop — every optional room on.
        DESKTOP_NAME=hacker
        ROOM_BAR=1; ROOM_WINDOWS=1; ROOM_LAUNCHER=1
        ;;
    esac
    fi

    ACCENT="$(printf 'mauve\nblue\nsapphire\nsky\nteal\ngreen\nyellow\npeach\nmaroon\nred\npink\nflamingo\nrosewater\nlavender' \
      | "$GUM" choose --header 'Accent colour:')"; ACCENT="${ACCENT:-mauve}"

    # Enter and Esc/skip both take the shown default (minimal), like every other
    # question here; `none` is the explicit choice that keeps your wallpaper, and
    # the preflight audit below names whichever one you land on before anything
    # is written.
    WALLPAPER="$(printf 'minimal\norbits\nconstellation\nflow\nbold\nnone' \
      | "$GUM" choose --header 'Desktop wallpaper — minimal is the haus mark on your palette · bold follows your accent · none keeps yours:')"
    WALLPAPER="${WALLPAPER:-minimal}"

    # The editors haus can INSTALL, spelled the way `haus.terminal.editorName`
    # takes them (modules/lib/editors.nix). This used to offer COMMANDS —
    # hx/nvim/vim/nano — and write the answer into `haus.terminal.editor`, which
    # only ever pointed at a binary: answering `nvim` gave a fresh machine
    # $EDITOR=nvim and no neovim. Name the editor and the room installs it.
    EDITOR_CHOICE="$(printf 'helix\nneovim\nvim\nnano' | "$GUM" choose --header 'Editor:')"
    EDITOR_CHOICE="${EDITOR_CHOICE:-helix}"

    # Prefer a GUI editor? For the three haus knows (VS Code/Cursor/Zed) this
    # both installs it (a roster cask — `haus.homebrew.adopt`, on by default,
    # adopts an existing install instead of duplicating it) AND points
    # `haus.terminal.editor` ($EDITOR/$VISUAL, every "open in an editor"
    # action) at its CLI. "Other" only sets the command — haus doesn't know
    # what app it names, so there's nothing to install. Either way this is
    # additive to the terminal editor above, which still installs as the
    # room's own fallback.
    GUI_EDITOR_PICK="$(printf 'none\nVS Code\nCursor\nZed\nOther' \
      | "$GUM" choose --header 'Prefer a GUI editor for $EDITOR?')"
    case "$GUI_EDITOR_PICK" in
      "VS Code") GUI_EDITOR_CMD="code -w";     GUI_EDITOR_APP="vscode" ;;
      Cursor)    GUI_EDITOR_CMD="cursor -w";   GUI_EDITOR_APP="cursor" ;;
      Zed)       GUI_EDITOR_CMD="zed --wait";  GUI_EDITOR_APP="zed" ;;
      Other)
        GUI_EDITOR_CMD="$("$GUM" input --prompt "Editor command › " --placeholder "subl -w" <&3)"
        GUI_EDITOR_APP=""
        ;;
      *) GUI_EDITOR_CMD=""; GUI_EDITOR_APP="" ;;
    esac

    # macOS settings: keep your own, or let haus restyle them. Nothing
    # selected (the default) = haus sets its tidy defaults, as before.
    # Selected = your current values are read now and pinned into your config,
    # overriding haus — so your feel carries over to a fresh install.
    # The ’ below is a deliberate curly apostrophe: a plain ' would close the
    # single-quoted --header string. shellcheck SC1112 flags it either way.
    # shellcheck disable=SC1112
    KEPT="$(printf 'dock\nkeyboard\nfinder' | "$GUM" choose --no-limit \
      --header 'Keep your CURRENT macOS settings for (space toggles; none = use haus’s):')"
    echo "$KEPT" | grep -qx dock     && KEEP_DOCK=1
    echo "$KEPT" | grep -qx keyboard && KEEP_KBD=1
    echo "$KEPT" | grep -qx finder   && KEEP_FINDER=1

    # Adopt existing casks so a future declarative rebuild never deletes them.
    if [ -n "$BREW" ]; then
      CASKS="$("$BREW" list --cask 2>/dev/null | tr '\n' ' ')"
      if [ -n "${CASKS// /}" ] \
        && "$GUM" confirm "Adopt your $(echo "$CASKS" | wc -w | tr -d ' ') existing Homebrew casks into the config?" <&3; then
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
  if [ -n "$BREW" ]; then
    printf '  apps      %s Homebrew cask(s) installed — NONE removed (cleanup = none).\n' \
      "$("$BREW" list --cask 2>/dev/null | wc -l | tr -d ' ')"
    [ -n "$ADOPT_CASKS" ] && printf '            %s adopted into your config so a rebuild keeps them.\n' \
      "$(echo "$ADOPT_CASKS" | wc -w | tr -d ' ')"
  else
    printf '  apps      no Homebrew yet — haus installs it; nothing to remove.\n'
  fi

  # Dotfiles — haus writes these as single files; an existing REAL one is
  # renamed to <file>.backup on the first switch (kept, never deleted). Files
  # already symlinked into the Nix store are managed, so they don't count.
  # (haus's directory-based configs — sketchybar, yazi, … — are managed
  # per-file, so only a conflicting file *inside* them is ever backed up.)
  #
  # Two of these are NOT backed up but COLLIDE, and home-manager stops the
  # activation dead when it meets one (`would be clobbered`) — after the whole
  # first build, and after Homebrew has already installed its casks:
  #
  #   * a SYMLINK that isn't ours (a dotfiles repo, stow, chezmoi, or a base
  #     image that points ~/.profile at ~/.zprofile). backupFileExtension moves
  #     regular files; it refuses links, on purpose — silently deleting a link
  #     into someone's dotfiles repo is the worse failure.
  #   * a path that already has BOTH <file> and <file>.backup, so the backup
  #     name it wants is taken.
  #
  # This is the last moment either costs nothing to fix, so they get their own
  # line rather than being folded in with the backups. `.profile` is on the
  # list because haus owns it (modules/terminal) — leaving it off is how a run
  # got told "nothing to back up" and then died on it 40 minutes later.
  local managed=(
    "$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.profile"
    "$HOME/.config/starship.toml" "$HOME/.config/git/config"
    "$HOME/.config/aerospace/aerospace.toml" "$HOME/.config/bat/config"
    "$HOME/Library/Application Support/com.mitchellh.ghostty/config"
  )
  local hits=() blockers=() p link
  for p in "${managed[@]}"; do
    # -L as well as -e, so a symlink is seen before its target is followed.
    { [ -e "$p" ] || [ -L "$p" ]; } || continue
    link="$(readlink "$p" 2>/dev/null || true)"
    case "$link" in
      # home-manager's own exemption is this narrow: it recognises only ITS
      # generation's files as already-managed. A hand-made link into the store,
      # or one another Nix tool wrote, is a collision to it — so a broader glob
      # here would pass exactly the file it then dies on.
      */nix/store/*-home-manager-files/*) continue ;;
      ?*)
        # A link whose target is GONE is not in the way: home-manager gates the
        # whole collision check on the target existing, and replaces a dangling
        # link without comment. Warning about it would stop a run that works.
        [ -e "$p" ] || continue
        blockers+=("${p/#$HOME/~} -> ${link/#$HOME/~} (symlink)")
        continue
        ;;
    esac
    if [ -e "$p.backup" ]; then
      blockers+=("${p/#$HOME/~} (its .backup name is taken)")
    else
      hits+=("${p/#$HOME/~}")
    fi
  done
  if [ "${#hits[@]}" -gt 0 ]; then
    printf '  dotfiles  these already exist and will be saved as <file>.backup (kept, not deleted):\n'
    printf '              %s\n' "${hits[@]}"
  elif [ "${#blockers[@]}" -eq 0 ]; then
    printf '  dotfiles  no conflicting single-file dotfiles — nothing to back up.\n'
  fi
  if [ "${#blockers[@]}" -gt 0 ]; then
    warn "These stop the FIRST switch — home-manager backs up files, not links:"
    printf '              %s\n' "${blockers[@]}"
    printf '            Clear each one before you build (mv ~/.profile ~/.profile.mine),\n'
    printf '            or keep yours and tell haus to skip that file, in your host file:\n'
    printf '              home.file.".profile".enable = false;           # a $HOME dotfile\n'
    printf '              xdg.configFile."starship.toml".enable = false; # one under ~/.config\n'
  fi

  # macOS settings the chosen rooms will change (current -> new), or that you
  # chose to KEEP (your current value pinned into the config). Read-only.
  printf '  settings  haus will set these macOS defaults (reversible via the snapshot):\n'
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
  [ -n "$ROOM_BAR" ]   && printf '              Hide native menu bar: %s -> true (Bar draws its own)\n' "$(dflt -g _HIHideMenuBar)"
  [ -n "$ROOM_WINDOWS" ]  && printf '              Caps Lock -> a leader key for tiling + the app launcher\n'
  [ -n "$ROOM_LAUNCHER" ] && printf '              ⌘Space   -> the pounce palette (disabled for Spotlight)\n'
  # Both branches print. Now that `minimal` is the default, "keep mine" is the
  # answer that needs echoing back — silence there would read as "nothing will
  # touch my desktop" whichever way you answered.
  if [ "$WALLPAPER" = "none" ]; then
    printf '              Desktop wallpaper:    left as yours (haus.wallpaper.style = "none")\n'
  else
    printf '              Desktop wallpaper:    set to the "%s" look (your current one is not deleted, but macOS keeps no record of it — re-pick it by hand if you go back)\n' "$WALLPAPER"
  fi

  printf '  undo      nothing is switched until you run the build below; the snapshot\n'
  printf '            taken above + `darwin-rebuild --rollback` revert it.\n'
}
preflight_audit

# Nothing has been written yet — this is the last read-only moment. Require an
# explicit yes before scaffolding (interactive only; --defaults just proceeds).
if [ -n "$INTERACTIVE" ] && [ -n "${GUM:-}" ] && ! "$GUM" confirm "Write this config to $DEST and continue?" <&3; then
  printf '\n'; say "OK — nothing was written. Re-run any time."
  exit 0
fi

# ---- Phase 2: scaffold ----------------------------------------------------
say "Scaffolding your config at $DEST"
run mkdir -p "$DEST/hosts/$HOSTNAME"
mkdir -p "$DEST/hosts/$HOSTNAME"   # for real even in dry-run, so we can write into it

# A named desktop is SELECTED, not imported — exactly how someone would select a
# desktop they found online. Exactly one per host, and it sits between the rooms
# and you in the priority ladder: an option the desktop sets, your host file
# overrides with a plain assignment, no `lib.mkForce` anywhere.
DESKTOP_LINE=""
if [ -n "$DESKTOP_NAME" ]; then
  DESKTOP_LINE="
        desktop = haus.desktops.$DESKTOP_NAME;"
fi

cat >"$DEST/flake.nix" <<EOF
{
  description = "$USERNAME's machine — a haus";

  # The whole of haus (system + shell + pounce + nebelung) comes from the public
  # haus flake. This config holds only what's personal: the host.
  # Update everything with:  nix flake update haus
  inputs.haus.url = "github:hausfold/haus";

  outputs =
    { haus, ... }:
    {
      darwinConfigurations.$HOSTNAME = haus.mkHaus {
        username = "$USERNAME";
        hostname = "$HOSTNAME";
        host = ./hosts/$HOSTNAME;$DESKTOP_LINE
      };
    };
}
EOF

# Assemble the optional host lines (omit anything left at the desktop default).
opt_lines=""
[ -z "$ROOM_BAR" ]   && opt_lines+="  haus.bar.enable = false;"$'\n'
[ -z "$ROOM_WINDOWS" ]  && opt_lines+="  haus.windows.enable = false;"$'\n'
[ -z "$ROOM_LAUNCHER" ] && opt_lines+="  haus.launcher.enable = false;"$'\n'
[ "$ACCENT" != "mauve" ] && opt_lines+="  haus.theme.accent = \"$ACCENT\";"$'\n'
# `minimal` is the desktop default now, so it's `none` that has to be written out —
# omitting the line on a "keep mine" answer would hand that machine the generated
# desktop, which is the opposite of what was asked for.
[ "$WALLPAPER" != "minimal" ] && opt_lines+="  haus.wallpaper.style = \"$WALLPAPER\";"$'\n'
# `editorName`, not `editor`: the first names an editor the room then installs,
# the second is a command it merely points at. A generated host must always
# write the installing one.
[ "$EDITOR_CHOICE" != "helix" ] && opt_lines+="  haus.terminal.editorName = \"$EDITOR_CHOICE\";"$'\n'
# A GUI editor pick overrides `editor` alone — the terminal editor above still
# installs and still owns `editorName`, this only redirects $EDITOR/$VISUAL and
# the "open in an editor" actions at a command haus never installs.
[ -n "$GUI_EDITOR_CMD" ] && opt_lines+="  haus.terminal.editor = \"$GUI_EDITOR_CMD\";"$'\n'
# The GUI editor itself, for the three haus can actually install. Duplicate
# installs are handled downstream by `haus.homebrew.adopt`, not here — this
# stays a plain static enable regardless of what's already on the machine.
[ -n "$GUI_EDITOR_APP" ] && opt_lines+="  haus.apps.$GUI_EDITOR_APP.enable = true;"$'\n'
[ -n "$opt_lines" ] && opt_lines=$'\n'"$opt_lines"
cask_lines=""
for c in $ADOPT_CASKS; do cask_lines+="    \"$c\""$'\n'; done

# Kept macOS settings — your current values, read now (read-only) and pinned so
# they win over haus's lib.mkDefault opinions. Empty unless you chose to keep
# a category, so a default install writes no system.defaults and behaves as before.
settings_lines="$(settings_overrides)"
settings_block=""
[ -n "$settings_lines" ] && settings_block=$'\n'"  # ---- macOS settings kept as yours (read at install) ----"$'\n'"$settings_lines"

# ---- the annotated option catalogue ---------------------------------------
# hosts/<host>/options.nix: every haus.* option at its default, described,
# docs-linked, and commented out. It's how you find out an option exists without
# leaving your editor — read it, uncomment what you want, delete the rest.
#
# Rendered from haus's own module system (`nix build .#host-template`), so
# it lists the options that exist at the revision you're about to pin, not
# upstream's latest. That's a real flake fetch, so it's best-effort: a machine
# that's offline, or pinning a haus older than the output, gets a config that
# works exactly as before and a pointer to `haus options`.
say "Rendering the option catalogue (every haus.* option, annotated)"
IMPORTS_LINE=""
if tmpl="$(nix build --no-link --print-out-paths \
             "${HAUS_FLAKE:-github:hausfold/haus}#host-template" 2>/dev/null)" \
   && [ -f "$tmpl/share/haus/host-options.nix" ]; then
  cp -f "$tmpl/share/haus/host-options.nix" "$DEST/hosts/$HOSTNAME/options.nix"
  chmod u+w "$DEST/hosts/$HOSTNAME/options.nix"   # it comes out of the store read-only
  IMPORTS_LINE="  imports = [ ./options.nix ]; # every haus.* option, annotated — read it
"
else
  warn "couldn't render the option catalogue (offline?) — run 'haus options' after your first rebuild."
fi

cat >"$DEST/hosts/$HOSTNAME/default.nix" <<EOF
# $HOSTNAME — your machine. The personal layer on top of haus:
# identity, apps, secrets. A plain nix-darwin module; everything else is haus.
{ ... }:

{
$IMPORTS_LINE
  # ---- identity ----
  haus.git.name = "$GIT_NAME";
  haus.git.email = "$GIT_EMAIL";
  haus.git.signingKey = "$GIT_SIGNING"; # GPG key id; "" disables signing.

  # pounce code-signing identity (SHA-1 from: security find-identity -v -p codesigning).
  # "" runs pounce unsigned — the palette works, Accessibility features stay off.
  haus.launcher.signingIdentity = "";
$opt_lines$settings_block
  # Homebrew never deletes an undeclared cask by default (cleanup = "none"); set
  # haus.homebrew.cleanup = "zap" only once every app you keep is listed.
  # Your apps — merged with what the rooms install (ghostty, aerospace):
  homebrew.casks = [
$cask_lines  ];
}
EOF

printf 'result\nresult-*\n' >"$DEST/.gitignore"

if [ ! -d "$DEST/.git" ]; then
  run git -C "$DEST" init -q -b main
  run git -C "$DEST" add -A
  run git -C "$DEST" commit -qm "Scaffold a haus consumer for $HOSTNAME"
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
    hosts/$HOSTNAME/options.nix   EVERY haus.* option, at its default,
                                  described, docs-linked, and commented out

  Read the second one to learn what exists; uncomment a line to change it, and
  delete every line you never touched. \`haus options\` refreshes it after an
  update. Everything in it is inert until you uncomment something.
EOF

cat <<EOF

$(say "Before you switch — what haus can and can't undo:")

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
  [ -f "$DEST/hosts/$HOSTNAME/options.nix" ] && say "[dry-run] generated $DEST/hosts/$HOSTNAME/options.nix: $(grep -c '^  # haus\.' "$DEST/hosts/$HOSTNAME/options.nix") options"
fi

# ---- optional: raise it right now ------------------------------------------
# One more consent gate turns the two-command install into one. Asked only when
# there's a terminal to ask on — scripted/--defaults runs keep the old contract
# (scaffold, print the command, stop), and declining changes nothing: the command
# is already on screen above. Build first; a failed build activates nothing.
RAISE=
if [ -n "$INTERACTIVE" ] && [ -z "$DRY_RUN" ] && [ -n "${GUM:-}" ] \
  && "$GUM" confirm "Raise the house now? (build first — nothing activates if the build fails)" <&3; then
  RAISE=1
fi
# Last question asked — close the terminal channel before the long-running
# children below, so `nix build` and `darwin-rebuild switch` don't inherit an
# open read handle on it.
exec 3<&-

if [ -n "$RAISE" ]; then
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

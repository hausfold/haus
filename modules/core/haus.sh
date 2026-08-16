#!/usr/bin/env bash
# haus — the everyday CLI for a haus machine, so you never memorise the Nix
# incantations. This is the END-USER CLI haus ships (core puts it on
# PATH). It drives your OWN machine only — it knows nothing about the workshop
# family repos or agent worktrees (that's the workshop's developer CLI, `bench`).
#
#   haus rebuild        build + switch this machine from your config  (-v for raw output) (the usual day)
#   haus update         pull the latest haus + its apps, then rebuild
#   haus rollback [N]    go back a generation (or to generation N)
#   haus generations     list the generations you can roll back to
#   haus status          current generation + how old your pinned haus is
#   haus edit            open your host config (identity, apps) in $EDITOR
#   haus options         refresh hosts/<host>/options.nix — every haus.* option, annotated
#   haus set             write + apply haus.* options in the machine overlay (pairs; bare = pick one)
#   haus get             read one option, or list the machine overlay
#   haus unset           force nullable options to null (variadic)
#   haus reset           remove machine overrides and inherit config again (variadic)
#   haus plan            preview what 'haus rebuild' would change — packages, settings, files, launchd jobs, casks — read-only
#   haus diff            declared config vs what macOS actually has right now — read-only
#   haus capture         turn this Mac's current settings into config lines + a snapshot
#   haus revert-settings put back a 'haus capture' snapshot (Nix rollback can't touch macOS defaults)
#   haus doctor          check the machine's health (Nix, CLT, the GUI agents)
#   haus btm             check BTM daemon-gating (macOS 26 Tahoe+; no-op before)
#   haus tour            take the guided haus tour (it lives in the bar)
set -euo pipefail

# A bare/sudo/login-item shell may have almost nothing on PATH; make sure the
# tools we call (nix, darwin-rebuild, jq, git) resolve wherever we're invoked.
PATH="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/$(id -un)/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export PATH

# Your config flake — the thin consumer with your host file, scaffolded by the
# bootstrap. Override with HAUS_CONSUMER if it lives elsewhere.
CONSUMER="${HAUS_CONSUMER:-$HOME/.config/nix}"

say()  { printf '\033[38;5;103m🌫  %s\033[0m\n' "$*"; }
warn() { printf '\033[38;5;179m⚠  %s\033[0m\n' "$*"; }
die()  { printf '\033[38;5;167m✗  %s\033[0m\n' "$*" >&2; exit 1; }
ok()   { printf '  \033[38;5;108m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[38;5;167m✗\033[0m %s\n' "$*"; }
info() { printf '  \033[38;5;103mⓘ\033[0m %s\n' "$*"; }

[ -e "$CONSUMER/flake.nix" ] || die "no config flake at $CONSUMER — set HAUS_CONSUMER, or run the bootstrap first."

SYSPROFILES=/nix/var/nix/profiles

# ---- the rebuild front end --------------------------------------------------
# A rebuild's own tools narrate ~100 lines, and ~95 of them are identical every
# single time: nix-darwin's activate script alone echoes 62 (18 of which are one
# `reloading service <x>` per launchd job), and home-manager adds ~39 more. None
# of it is ours to delete — it comes out of upstream's scripts — but it IS ours
# to fold. So the phases whose output we hide are the phases we log, and the
# summary is rendered from that log.
#
# The rule, so nothing important can go missing: we only hide what we WRITE
# DOWN, we hide nothing on failure, and anything that isn't a human watching a
# terminal (an agent pane, CI, a pipe) gets the raw stream instead.
HAUS_LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/haus"
HAUS_LOG="$HAUS_LOG_DIR/rebuild.log"

# Verbose = raw, unsummarised, exactly what the old haus printed. Deliberately
# NOT "quiet output plus filtering": a filter that drops a line you didn't
# expect is how a warning disappears, so verbose is a passthrough, full stop.
VERBOSE="${HAUS_VERBOSE:-}"
[ -t 1 ] || VERBOSE=1

phase_start() { [ -n "$VERBOSE" ] || printf '  \033[38;5;103m·\033[0m %-9s ' "$1"; }
phase_ok()    { printf '\r  \033[38;5;108m✓\033[0m %-9s %6s  \033[38;5;103m%s\033[0m\n' "$1" "$2" "${3:-}"; }
phase_bad()   { printf '\r  \033[38;5;167m✗\033[0m %-9s %6s\n' "$1" "$2"; }
secs()        { printf '%d.%01ds' $(( $1 / 10 )) $(( $1 % 10 )); }
# Deciseconds, from bash's own clock. NOT `date +%s%N`: that's a GNU extension,
# and BSD date prints a literal "N" — which only shows up as broken arithmetic
# on the one platform this script is FOR. The character class covers locales
# where $EPOCHREALTIME's separator is a comma.
now_ds() {
  local t="${EPOCHREALTIME:-}"
  [ -n "$t" ] || { echo $(( SECONDS * 10 )); return; }
  t="${t//[.,]/}"
  echo $(( 10#${t:0:11} ))
}

# Run one phase. Quiet mode appends everything to the log and shows a single
# line; verbose mode streams. On failure BOTH modes show the tail of what the
# phase actually said, plus where the whole thing was written.
# One log per rebuild, previous one kept. Fresh each time so "the log" always
# means this rebuild, and so the byte offsets run_phase slices by stay cheap.
log_open() {
  mkdir -p "$HAUS_LOG_DIR"
  [ -f "$HAUS_LOG" ] && mv -f "$HAUS_LOG" "$HAUS_LOG.prev" 2>/dev/null
  printf '=== %s · %s ===\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >"$HAUS_LOG"
}

HAUS_PHASE_SLICE=""   # this phase's own log slice, for the summary line
run_phase() {
  local label="$1"; shift
  local t0 rc=0 off=0
  mkdir -p "$HAUS_LOG_DIR"
  : >>"$HAUS_LOG"
  off="$(wc -c <"$HAUS_LOG" | tr -d ' ')"
  t0="$(now_ds)"
  phase_start "$label"
  if [ -n "$VERBOSE" ]; then
    "$@" 2>&1 | tee -a "$HAUS_LOG"
    rc="${PIPESTATUS[0]}"
  else
    "$@" >>"$HAUS_LOG" 2>&1 || rc=$?
  fi
  HAUS_PHASE_ELAPSED="$(secs $(( $(now_ds) - t0 )) )"
  HAUS_PHASE_SLICE="$(tail -c "+$((off + 1))" "$HAUS_LOG")"
  if [ "$rc" -ne 0 ]; then
    phase_bad "$label" "$HAUS_PHASE_ELAPSED"
    [ -n "$VERBOSE" ] || printf '%s\n' "$HAUS_PHASE_SLICE" | tail -n 25 | sed 's/^/      /'
    warn "full log: $HAUS_LOG"
  fi
  return "$rc"
}

# What actually happened during activation, from the lines we just hid.
activation_summary() {
  local services brewline=""
  services="$(printf '%s\n' "$HAUS_PHASE_SLICE" | grep -cE '^(reloading|creating) (user )?service ' || true)"
  if printf '%s\n' "$HAUS_PHASE_SLICE" | grep -qE '^(Installing|Upgrading|Uninstalling) '; then
    brewline=" · homebrew changed"
  elif printf '%s\n' "$HAUS_PHASE_SLICE" | grep -q 'Homebrew bundle'; then
    brewline=" · homebrew ok"
  fi
  printf '%s service%s%s' "$services" "$([ "$services" = 1 ] || echo s)" "$brewline"
}

# ---- doing two things at once -----------------------------------------------
# A rebuild is two independent pipelines that we ran back to back for no reason:
# nix (evaluate, substitute, build) and Homebrew (update taps, download casks).
# They share no state — different caches, different stores — so the brew half
# belongs alongside the build, not after it.
#
# The one ordering that IS load-bearing: activation runs `brew bundle` itself,
# and two brew processes fight over the same lock, so every brew job must be
# joined BEFORE we activate. Hence one registry and one `bg_wait` at the gate.
BG_PIDS=()
bg() { ( "$@" ) >>"$HAUS_LOG" 2>&1 & BG_PIDS+=("$!"); }
bg_wait() {
  local pid rc=0
  for pid in ${BG_PIDS[@]+"${BG_PIDS[@]}"}; do wait "$pid" || rc=1; done
  BG_PIDS=()
  return "$rc"
}

# Download (don't install) whatever activation is about to upgrade, while the
# nix build runs. `brew fetch` only fills brew's download cache — it touches no
# installed app — so this keeps haus's promise that a FAILED BUILD CHANGES
# NOTHING, while moving the part that actually takes minutes (a 200 MB Chrome
# or Zen update) off the critical path. Worst case on a failed build: a cached
# download nobody asked for yet.
#
# Gated on the running system's activate script, because a host with
# `haus.homebrew.upgrade = false` will never install what we'd fetch:
# nix-darwin passes `--no-upgrade` to `brew bundle` exactly then.
brew_prefetch() {
  command -v brew >/dev/null 2>&1 || return 0
  grep -q 'brew bundle .*--no-upgrade' /run/current-system/activate 2>/dev/null && return 0
  local outdated
  outdated="$(brew outdated --cask --quiet 2>/dev/null || true)"
  [ -n "$outdated" ] || return 0
  # shellcheck disable=SC2086
  brew fetch --cask $outdated || true
}

usage() {
  cat <<'EOF'
haus — the everyday CLI for a haus machine.

  haus rebuild        build + switch this machine from your config  (-v for raw output)
  haus update         pull the latest haus + its apps, then rebuild
  haus rollback [N]   go back a generation (or to generation N)
  haus generations    list the generations you can roll back to
  haus status         current generation + how old your pinned haus is
  haus edit           open your host config in $EDITOR
  haus options        refresh the annotated catalogue of every haus.* option
                      (--force replaces your copy instead of writing options.nix.new)
  haus set <path> <value> [<path> <value>…]
                      write hosts/<host>/settings/<path>.nix, type-check it, and
                      rebuild (theme.accent and haus.theme.accent both work).
                      Several pairs land in ONE rebuild, all-or-nothing — which is
                      what an intent spanning two options needs (light mode is
                      theme.flavor + theme.systemAppearance)
  haus set            with no arguments: search every option this machine has, then
                      pick or type the value — the list of values comes from the
                      option's own type
  haus get [path]     print a declared value, or list values in the writable overlay
  haus unset <path> [<path>…]
                      force nullable options to null
  haus reset <path> [<path>…]
                      remove writable overrides and inherit the host/desktop/room value.
                      unset and reset take a LIST the way set takes pairs: several
                      paths land in ONE rebuild, all-or-nothing, so an intent that
                      took two options to make takes one command to undo
  haus plan           preview what 'haus rebuild' would change — packages, macOS
                      settings, the files home-manager writes into your home,
                      launchd jobs, casks — without building anything into place
  haus diff           the config currently active on this machine vs what macOS
                      actually has right now (effective state, not just the plist)
  haus capture [cat…] turn this Mac's current settings into config lines, and
                      snapshot them (default: dock keyboard finder; or a literal
                      plist domain, e.g. com.apple.Terminal)
  haus revert-settings [snapshot|list]
                      put back a 'haus capture' snapshot — Nix rollback rewinds
                      packages and agents, never macOS's own preferences
  haus doctor         check the machine's health (Nix, CLT, the GUI agents)
  haus btm            check BTM daemon-gating (macOS 26 Tahoe+; no-op before)
  haus tour           take the guided haus tour (haus tour reset re-arms it)
EOF
}

# The running system's generation number — read from the profile symlink so it
# needs no sudo (darwin-rebuild --list-generations write-locks the profile).
current_gen() {
  local link
  link="$(readlink "$SYSPROFILES/system" 2>/dev/null)" || return 1
  link="${link#system-}"
  echo "${link%-link}"
}
gen_date() { date -r "$(stat -f %m "$SYSPROFILES/system-$1-link" 2>/dev/null || echo 0)" "${2:-+%Y-%m-%d}" 2>/dev/null || echo '?'; }

host_name() { # the darwinConfiguration to build — the one host in your flake
  if [ -n "${HAUS_HOST:-}" ]; then echo "$HAUS_HOST"; return; fi
  nix eval --json "$CONSUMER#darwinConfigurations" --apply builtins.attrNames 2>/dev/null \
    | jq -r '.[0]' 2>/dev/null \
    | grep . \
    || { scutil --get LocalHostName 2>/dev/null || hostname -s; }
}

# Nix's lazy-tree fetcher occasionally leaves a *partial* tree in its cache: the
# commit→tree mapping gets recorded, but a blob never finishes landing (an
# interrupted fetch, a laptop that slept mid-build, two nix runs racing the same
# cache). Every later eval that needs that blob then dies with the cryptic libgit2
# message "object not found - no match for id …", and nothing but clearing the
# cache fixes it. The tarball-/fetcher-caches are pure and regenerable, so on that
# exact signature we wipe them and retry once — a one-time re-fetch, not a rebuild.
NIX_CACHE_CORRUPT_SIG='no match for id'

nix_cache_wipe() { # drop the regenerable fetch caches for both the user and root nix stores
  warn "corrupt nix fetch cache — clearing it and retrying once (a one-time re-fetch) …"
  rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}"/nix/tarball-cache* \
         "${XDG_CACHE_HOME:-$HOME/.cache}"/nix/fetcher-cache*.sqlite 2>/dev/null || true
  # `darwin-rebuild switch` evaluates as root, so its cache is a separate store
  # under /var/root — needs sudo to clear (creds are usually still warm from the
  # switch we just ran; worst case it's one password prompt on the recovery path).
  sudo rm -rf /var/root/.cache/nix/tarball-cache* \
              /var/root/.cache/nix/fetcher-cache*.sqlite 2>/dev/null || true
}

heal() { # run "$@"; on the cache-corruption signature, wipe the caches and retry once
  local log rc
  log="$(mktemp)"
  if "$@" 2>&1 | tee "$log"; then rc=0; else rc=${PIPESTATUS[0]}; fi
  if [ "$rc" -ne 0 ] && grep -qF "$NIX_CACHE_CORRUPT_SIG" "$log"; then
    rm -f "$log"
    nix_cache_wipe
    "$@"; return $?
  fi
  rm -f "$log"
  return "$rc"
}

# ---- the Full Disk Access guard ---------------------------------------------
# §5.12 of the workshop's notes/options-roadmap.md, and the sharpest edge in the
# whole option surface: `system.defaults.universalaccess.*` is TCC-protected, and
# the write succeeds only if the app RESPONSIBLE for the rebuild holds Full Disk
# Access. nix-darwin emits it unguarded into an activation script running under
# `set -e`, two thirds of the way in — so without the grant activation aborts
# there and skips everything after it, including every launchd daemon and agent
# haus installs. The machine comes back with no bar, no tiling, no palette,
# and a symptom nowhere near its cause.
#
# THIS GUARD USED TO ASK THE WRONG QUESTION. It began with `under_agent ||
# return 0` — refuse an agent, wave a human through — and that is wrong in both
# directions, which is precisely what "must be impossible to hit by accident"
# rules out:
#
#   - It let two of the three clients through. `under_agent` tested CLAUDECODE,
#     and ⌘A spawns whichever client haus.ai.default names: Codex and OpenCode
#     set no such variable, so the one config shape that breaks a machine sailed
#     past the check written to catch it.
#   - It waved through the human it was protecting. A person in a terminal
#     nobody has granted FDA to hits the identical abort, and got no warning at
#     all — while a Claude pane INSIDE an FDA-holding terminal, which was always
#     going to work, was the case it stopped.
#
# The predicate that actually matters names no client and no persona: does this
# configuration write an unguarded TCC-protected domain, and can this process
# write it? Agent or human, terminal or .app, the answer is the same one, and
# it is the same answer the machine is about to give. `has_fda` tests the
# capability rather than guessing from who's driving — a Claude Code pane inside
# a terminal that holds the grant inherits it and rebuilds perfectly well, while
# the same agent under Claude.app, a cloud session, or a fresh terminal cannot.
#
# What makes strictness affordable is the other half of §5.12: every key in that
# domain measured to work now has a guarded `haus.accessibility.*` option, so
# refusing the raw form never refuses a setting that had no safer way to be
# said. Before that it would have.
#
# `under_agent()` lived here and is gone with the condition it served. Nothing
# else in this script needs to know who is driving, and leaving a
# who-is-driving predicate lying about is how the next guard gets written the
# same wrong way.
#
# Full Disk Access, for whichever app is responsible for THIS process. It must
# be a strict read of a protected file: the containing directory lists fine
# without the grant, so an `ls`-shaped test reports success on a machine that
# has no access at all.
has_fda() {
  head -c1 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" >/dev/null 2>&1
}

# The TCC-protected keys this config actually sets, comma-separated (empty when
# there are none). It costs an evaluation of the darwin system, so it runs only
# on the guard's slow path — which, since the guard stopped short-circuiting on
# "is this an agent", is every `haus rebuild` from an app WITHOUT the grant. On
# a machine whose terminal holds FDA (the common case, and the one haus's own
# installer steers you to) it never runs at all. It can't be read out of the
# built script the way `haus plan`'s verdicts are: the guard has to answer
# before anything is built.
#
# The raw typed opt-ins ONLY — not haus.accessibility's, which reach the same
# domain through core's guarded writer and cost nothing worse than a skipped
# setting. This is the list of writes that would take the machine down with them.
universalaccess_keys() {
  ( cd "$CONSUMER" && nix eval --raw \
      ".#darwinConfigurations.$1.config.system.defaults.universalaccess" \
      --apply 'a: builtins.concatStringsSep ", " (builtins.filter (n: a.${n} != null) (builtins.attrNames a))' \
      2>/dev/null ) || true
}

guard_unguarded_fda() {
  local keys
  # Escape hatch: you said go. HAUS_AGENT_REBUILD is the name this had while the
  # guard was about agents — still honoured, since anything scripted against it
  # meant exactly this, and a silently-ignored override is the one failure an
  # escape hatch cannot have.
  [ -n "${HAUS_FDA_ANYWAY:-}${HAUS_AGENT_REBUILD:-}" ] && return 0
  has_fda && return 0                            # this app can write the domain
  keys="$(universalaccess_keys "$1")"
  [ -n "$keys" ] || return 0

  warn "refusing to rebuild — this config needs Full Disk Access and this app hasn't got it."
  cat >&2 <<EOF

  This config sets system.defaults.universalaccess:

      $keys

  macOS only lets an app holding Full Disk Access write that domain. The failure
  would not be contained: nix-darwin runs the write unguarded partway through
  activation, so it would abort there and skip every background service haus
  installs — the bar, the tiling, the palette.

  The grant follows the APP, not you and not root, so this is not about who is
  typing: an agent pane inside a terminal that has it rebuilds fine, and a human
  in a terminal that hasn't hits this same wall.

  Nothing has been changed. Any edit already made is still on disk. Two ways on:

    1. Move those keys to haus.accessibility.* — it reaches every key in that
       domain MEASURED to take effect, through a guarded write that degrades to
       "setting skipped" instead of a half-activated Mac, and it rebuilds from
       anywhere. This is the fix; the option exists for exactly this. Since
       2026-08-14 it covers ALL FIVE keys nix-darwin types here, cursor size and
       the closeView pair included, so there is nothing left that only route 2
       can say.

    2. Rebuild from an app that holds the grant (System Settings ▸ Privacy &
       Security ▸ Full Disk Access — on macOS 26 a stale entry often needs
       removing and re-adding with (+), then restarting the terminal):

           haus rebuild

  'haus doctor' reports whether this app has it. (Really meant it, and want the
  abort? HAUS_FDA_ANYWAY=1 haus rebuild.)
EOF
  exit 1
}

# Evaluate only — the .drv, not the build. Split from the build so the build's
# stderr can stay a terminal (see cmd_rebuild), and so evaluation's warnings are
# said once, into the log, instead of on your screen: nixpkgs' nixosOptionsDoc
# trips a `builtins.derivation … without a proper context` warning on every eval
# of any config that installs the agent skill, and it is not ours to fix.
resolve_drv() { ( cd "$CONSUMER" && nix eval --raw ".#darwinConfigurations.$1.system.drvPath" >"$2" ); }

closure_diff() { nix store diff-closures "$1" "$2" >"$3" 2>/dev/null || true; }

# The pre-haus-activate route, kept whole for the one rebuild that needs it.
legacy_switch() { ( cd "$CONSUMER" && sudo /run/current-system/sw/bin/darwin-rebuild switch --flake ".#$1" ); }

# ---- reversibility: plan / diff / capture / revert-settings ----------------
# §5.11 of the workshop's notes/options-roadmap.md. A shared engine, because
# `haus plan` (what WOULD change) and `haus diff` (what's declared vs what
# macOS actually has right now) are the same comparison run against two
# different activation scripts — a fresh build for plan, the running system
# for diff.
#
# Ground truth is the BUILT activation script, not a hand-maintained map of
# nix-darwin's ~193 typed keys to plist domains: nix-darwin's own generator
# emits a uniform `defaults write DOMAIN KEY '<xml…>'` per key (verified
# against a real activate script, every one of the 47 this machine currently
# writes matches), so parsing that is ground truth that can't drift out from
# under an upstream change the way a hand-copied table would.

# TSV domain\tkey\tvalue for every `defaults write DOMAIN KEY '<?xml…'` block a
# built activation script contains. `-g` is normalised to `NSGlobalDomain` so
# callers never special-case it. `value` is plutil's rendering of the plist
# block, with any embedded newline (a dict/array value, e.g. Finder's
# FXInfoPanesExpanded) escaped to a literal `\n` — so this always emits exactly
# one TSV row per declared key, never a multi-line one a `read` loop would
# silently misparse into extra, bogus rows.
# `|| true` throughout: a key that isn't set, a domain with zero declared
# writes, a value plutil can't render — every one of these is a normal
# outcome, not a script error, and this runs (like the rest of haus.sh) under
# `set -euo pipefail`, which would otherwise abort the whole comparison on the
# first machine that doesn't happen to set every key this parses.
declared_defaults() {
  local f="$1" lineno rest domain key endline val
  grep -n -- "-- defaults write .* '<?xml" "$f" 2>/dev/null | while IFS=: read -r lineno rest; do
    domain="$(printf '%s' "$rest" | sed -E "s/.*-- defaults write (-g|[^ ]+) ([^ ]+) .*/\\1/")"
    key="$(printf '%s' "$rest" | sed -E "s/.*-- defaults write (-g|[^ ]+) ([^ ]+) .*/\\2/")"
    [ "$domain" = "-g" ] && domain="NSGlobalDomain"
    endline="$(awk -v s="$lineno" 'NR>=s && /<\/plist>/ {print NR; exit}' "$f")"
    [ -n "$endline" ] || continue
    val="$(
      sed -n "${lineno},${endline}p" "$f" \
        | sed -E "1s/^.*'(<\\?xml)/\\1/" \
        | sed -E "\$s/<\\/plist>'\$/<\\/plist>/" \
        | plutil -p - 2>/dev/null
    )" || true
    val="${val//$'\n'/\\n}"
    printf '%s\t%s\t%s\n' "$domain" "$key" "$val"
  done || true
}

# TSV domain\tkey\tvalue for core's own guarded accessibility writer (see
# modules/core/default.nix's `hausAccessibility` postActivation block) — a
# raw `defaults write` shell call carrying its own type flag, not the typed
# XML-plist shape declared_defaults parses, so it needs its own extraction.
declared_a11y_calls() {
  grep -E '^[[:space:]]*hausAccessibility [A-Za-z]+ -(bool|float) [^[:space:]]+[[:space:]]*$' "$1" 2>/dev/null \
    | while read -r _ key flag value; do
        # The writer carries `defaults write`'s own type flag since this domain
        # stopped being all-booleans (mouseDriverCursorSize, 2026-08-14). Only
        # -float needs anything doing to it: Nix stringifies 3.0 as "3.000000"
        # and `defaults read` prints "3", so canonicalise here rather than
        # letting a diff report a key as changed on every run forever. %g drops
        # the trailing zeros the same way macOS does — under LC_ALL=C, because
        # %g reads the decimal separator from the locale and a comma-separator
        # LC_NUMERIC would stop at the dot and turn 1.500000 into 1, causing
        # exactly the forever-changed diff this line exists to prevent.
        if [ "$flag" = -float ]; then
          value="$(LC_ALL=C printf '%g' "$value")"
        fi
        printf 'com.apple.universalaccess\t%s\t%s\n' "$key" "$value"
      done || true
}

# TSV for core's other guarded writer: haus.sound.alertSound. Same reason as
# the block above — it is a raw `defaults write … -string` call rather than the
# typed XML shape, because the write has to be skipped when the sound file is
# missing (an unresolvable path SILENCES the alert instead of falling back, and
# a pure-eval `builtins.pathExists` can't tell). Without this line `haus diff`
# would report a declared key as undeclared.
declared_alert_sound() {
  grep -E '^[[:space:]]*defaults write -g com\.apple\.sound\.beep\.sound -string ' "$1" 2>/dev/null \
    | sed -E 's/.*-string ([^ \\]+).*/NSGlobalDomain\tcom.apple.sound.beep.sound\t\1/' || true
}

# plutil's rendering → the same textual shape `defaults read` prints, so the
# two sides of a comparison need no further massaging. A value with an escaped
# `\n` (a dict/array — declared_defaults's escape marker, see above) is flagged
# rather than compared, since neither side of that comparison is a scalar.
normalize_declared() {
  case "$1" in
    *'\n'*) printf '%s' "__COMPLEX__" ;;
    true) echo 1 ;;
    false) echo 0 ;;
    \"*) local v="${1#\"}"; printf '%s\n' "${v%\"}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

live_value() { # <domain> <key> -> `defaults read`'s raw output, empty if unset
  # `|| true`: an unset key is the common case, not a script error — `defaults
  # read` exits non-zero for it, and this runs under `set -e`.
  if [ "$1" = "NSGlobalDomain" ]; then defaults read -g "$2" 2>/dev/null || true
  else defaults read "$1" "$2" 2>/dev/null || true; fi
}

# How to verify a declared key, per §4/§8's finding: some domains write and
# silently no-op, so a plist-only diff would call them "applied" when they
# aren't.
#   effective    — compare against hausax's NSWorkspace read, not the plist
#                  (the four universalaccess keys measured to write AND work)
#   noop         — com.apple.Accessibility: writes, changes nothing, ever
#   appearance   — NSGlobalDomain AppleInterfaceStyle: inert in BOTH directions
#                  (measured 2026-08-08 on 26.6), and worse than `noop` to diff,
#                  because the key IS where macOS mirrors the appearance it's
#                  showing — so a plist comparison would read back the write
#                  that did nothing and call it applied. There is a working
#                  lever; it just isn't this one. See modules/theme.
#   by-eye       — measured effective by a HUMAN on real hardware, with no API
#                  that can re-check it here (NSWorkspace reports no pointer size
#                  and no zoom state). Diffed against the plist like `plain`, and
#                  SAYS SO — the one thing it must never do is print the same
#                  confident line `effective` prints, because that line means
#                  "macOS itself agrees" and here nothing asked macOS.
#   unconfirmed  — other universalaccess keys: persist, effect never measured
#   plain        — everything else: the matrix's control group, plist is fine
classify_key() {
  case "$1" in
    com.apple.Accessibility) echo noop ;;
    NSGlobalDomain)
      case "$2" in
        AppleInterfaceStyle) echo appearance ;;
        *) echo plain ;;
      esac
      ;;
    com.apple.universalaccess)
      case "$2" in
        reduceMotion | reduceTransparency | increaseContrast | differentiateWithoutColor) echo effective ;;
        mouseDriverCursorSize | closeViewScrollWheelToggle | closeViewZoomFollowsFocus) echo by-eye ;;
        *) echo unconfirmed ;;
      esac
      ;;
    *) echo plain ;;
  esac
}

# The comparison itself: every declared key against what macOS actually has.
# Read-only, always — callers decide which activation script (a running system
# for `diff`, a freshly built one for `plan`) but this never writes anything.
settings_diff() {
  local script="$1" domain key declared_raw declared kind live
  local changed=0 matched=0 flagged=0
  local ax_json; ax_json="$(hausax 2>/dev/null || true)"

  while IFS=$'\t' read -r domain key declared_raw; do
    [ -n "$domain" ] || continue
    declared="$(normalize_declared "$declared_raw")"
    kind="$(classify_key "$domain" "$key")"

    case "$kind" in
      effective)
        if [ -z "$ax_json" ]; then
          warn "$domain $key: declared $declared — can't verify (hausax unavailable)"
          flagged=$((flagged + 1))
          continue
        fi
        live="$(printf '%s' "$ax_json" | jq -r --arg k "$key" '.[$k]')" || true
        case "$live" in true) live=1 ;; false) live=0 ;; esac
        if [ "$declared" = "$live" ]; then
          matched=$((matched + 1))
        else
          bad "$domain $key: declared $declared, macOS effectively reports $live (NSWorkspace, not the plist)"
          changed=$((changed + 1))
        fi
        ;;
      noop)
        warn "$domain $key: declared $declared — this domain is a KNOWN SILENT NO-OP on macOS 26 (writes, no effect; see notes/macos-settings-matrix.md)"
        flagged=$((flagged + 1))
        ;;
      appearance)
        # Deliberately not diffed against the plist: this key is where macOS
        # MIRRORS the appearance it is showing, so reading it back reports the
        # inert write rather than the effect. hausax has the real answer.
        live=unknown
        if [ -n "$ax_json" ]; then
          live="$(printf '%s' "$ax_json" | jq -r '.appearance // "unknown"')" || live=unknown
        fi
        warn "$domain $key: declared $declared — writing this key is a KNOWN NO-OP in BOTH directions on macOS 26 (measured; the appearance system only mirrors it). macOS is effectively showing $live. Use haus.theme.systemAppearance instead."
        flagged=$((flagged + 1))
        ;;
      by-eye | unconfirmed | plain)
        if [ "$declared" = "__COMPLEX__" ]; then
          info "$domain $key: dict/array value — not diffed automatically"
          flagged=$((flagged + 1))
          continue
        fi
        live="$(live_value "$domain" "$key")"
        if [ "$declared" = "${live:-}" ]; then
          matched=$((matched + 1))
          [ "$kind" = unconfirmed ] && flagged=$((flagged + 1)) # matches, but a match here isn't proof it works
          if [ "$kind" = by-eye ]; then
            # Not flagged — this key backs a supported option and the plist
            # agreeing is the most any tool can establish for it. Said out loud
            # anyway: the `effective` arm above means "macOS itself agrees", and
            # a reader skimming a column of ticks would otherwise read this one
            # as the same claim.
            info "$domain $key: plist matches — nothing on this Mac can confirm the effect, so that is all this checked (measured by eye, macOS 26.6.1)"
          fi
        else
          if [ "$kind" = unconfirmed ]; then
            warn "$domain $key: declared $declared, plist shows ${live:-unset} (persists only — effect unconfirmed on this macOS)"
            flagged=$((flagged + 1))
          elif [ "$kind" = by-eye ]; then
            printf '  %-28s %-26s %-14s -> %s  (plist-only check)\n' "$domain" "$key" "${live:-unset}" "$declared"
          else
            printf '  %-28s %-26s %-14s -> %s\n' "$domain" "$key" "${live:-unset}" "$declared"
          fi
          changed=$((changed + 1))
        fi
        ;;
    esac
  done < <(declared_defaults "$script"; declared_a11y_calls "$script"; declared_alert_sound "$script")

  echo
  if [ "$changed" = 0 ]; then
    info "settings: live matches declared ($matched key(s))"
  else
    info "settings: $changed key(s) differ from live, $matched already match"
  fi
  [ "$flagged" -gt 0 ] && info "$flagged key(s) flagged above — unconfirmed effect, known no-op, or a value diff can't compare automatically"
}

# What a rebuild's Brewfile would newly install — the forward-looking half of
# cmd_doctor's declared-vs-installed check. Never removes anything to report:
# cleanup defaults to "none", so an uninstall is never silent either way.
plan_homebrew() {
  command -v brew >/dev/null 2>&1 || {
    info "no Homebrew on this machine yet — haus installs it on first activation"
    return 0
  }
  local sys="$1" brewfile declared installed toinstall
  # `|| true`: matches cmd_doctor's identical extraction below — a build with
  # no Brewfile line at all is a zero-match grep, not a script error.
  brewfile="$(grep -oE "brew bundle --file='[^']+'" "$sys/activate" 2>/dev/null | sed "s/.*--file='//;s/'\$//" || true)"
  if [ -z "$brewfile" ] || [ ! -f "$brewfile" ]; then
    info "no Brewfile in the new build"
    return 0
  fi
  declared="$(sed -nE 's/^cask "([^"]+)".*/\1/p' "$brewfile" | sed -E 's#.*/##')"
  installed="$(brew list --cask 2>/dev/null || true)"
  toinstall="$(comm -23 <(printf '%s\n' "$declared" | sort -u) <(printf '%s\n' "$installed" | sort -u) | grep . || true)"
  if [ -n "$toinstall" ]; then
    printf '  will install: %s\n' "$(printf '%s' "$toinstall" | paste -sd', ' -)"
  else
    info "no new casks to install"
  fi
  info "cleanup=none means nothing is ever removed automatically — 'haus doctor' flags undeclared casks"
}

# ---- which config did we just read? -----------------------------------------
# `haus` always evaluates $CONSUMER, never the directory you happen to be
# standing in. That is right for the everyday case (any pane, any cwd, one
# machine config) and silently wrong in exactly one: a LINKED GIT WORKTREE of
# the config itself, which is how an agent lane edits a host file. From in
# there, `haus plan` builds MAIN's config and then truthfully reports "nothing
# was changed" about a branch it never read — and `haus rebuild` would activate
# main while you believed you were feeling your branch. Nothing in the worktree
# is reachable from $CONSUMER, so the honest fix is to say which tree was read
# and name the way to point at this one.
consumer_worktree_warning() {
  local top common consumer ours
  command -v git >/dev/null 2>&1 || return 0
  # Every path here is resolved with cd+pwd -P before being compared. git reports
  # physical paths, $CONSUMER is whatever the environment said, and one symlinked
  # component anywhere in $HOME (or a /var → /private/var temp dir) is enough to
  # make two spellings of the same directory look like two directories — which
  # would silently switch this warning off in exactly the case it exists for.
  consumer="$(cd "${CONSUMER%/}" 2>/dev/null && pwd -P || true)"
  [ -n "$consumer" ] || return 0
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$top" ] || return 0
  top="$(cd "$top" 2>/dev/null && pwd -P || true)"
  [ -n "$top" ] || return 0
  [ "$top" != "$consumer" ] || return 0
  # The SHARED .git dir is what makes this another checkout of the config, rather
  # than an unrelated repo you happen to be sitting in. Asked of BOTH sides
  # rather than built as "$consumer/.git": a config that is a subdirectory of a
  # bigger dotfiles repo has its common dir at that repo's root, and comparing
  # against a constructed path would switch this warning off for exactly the
  # setup it exists for. It also covers $CONSUMER itself being a worktree.
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [ -n "$common" ] || return 0
  common="$(cd "${common%/}" 2>/dev/null && pwd -P || true)"
  [ -n "$common" ] || return 0
  ours="$(git -C "$consumer" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  [ -n "$ours" ] || return 0
  ours="$(cd "${ours%/}" 2>/dev/null && pwd -P || true)"
  [ "$common" = "$ours" ] || return 0
  warn "this is a worktree of your config ($top), but haus reads \$CONSUMER — so it is reading $consumer, not the branch checked out here."
  info "to read THIS tree instead: HAUS_CONSUMER=$top haus <command>"
}

# ---- what a rebuild would write into $HOME ----------------------------------
# The other half of a haus rebuild, and the half `plan` was blind to until
# workshop#307: every file home-manager manages — the bar's items and plugins,
# the shell, the tiling config, the agent skills. None of it is a
# `system.defaults` key, so settings_diff cannot see it, and `nix store
# diff-closures` does not report it either: the whole tree lands under ONE
# store path whose name carries no version, and diff-closures only prints a
# same-name entry once its size has moved enough to notice. Switching on seven
# bar pills moved it 272 bytes, so `haus plan` said "nothing was changed"
# about a bar that was about to grow seven pills.
#
# Ground truth is the built tree, the same discipline declared_defaults uses on
# the activation script: walk home-files with the same `-type f -or -type l`
# find home-manager's own linkGeneration walks, so the set compared here is
# exactly the set that gets installed.

# <activate script> -> TSV user \t home-manager-generation store path.
# The chain nix-darwin emits per user, followed one hop at a time:
#   activate → …-activation-<user> → …-home-manager-generation/activate
# Read out of the script rather than picked out of the closure, because the
# closure knows nothing about WHICH user a generation belongs to — a Mac with
# two managed users would otherwise be compared against itself.
# Both paths are matched by SHAPE — a 32-character store hash plus the suffix
# nix-darwin/home-manager give it — rather than by a literal /nix/store prefix.
# The store dir is configurable, and matching the shape is also what lets
# test/haus-plan.sh check this against fixture scripts in a temp dir instead of
# needing a real built system, which no CI runner has.
hm_generations() {
  local wrapper user gen
  grep -oE '/[^ ]*/[a-z0-9]{32}-activation-[A-Za-z0-9_.-]+' "$1" 2>/dev/null | LC_ALL=C sort -u \
    | while read -r wrapper; do
        [ -f "$wrapper" ] || continue
        user="${wrapper##*-activation-}"
        gen="$(grep -oE '/[^ ]*/[a-z0-9]{32}-home-manager-generation' "$wrapper" 2>/dev/null | head -1 || true)"
        [ -n "$gen" ] || continue
        [ -d "$gen/home-files" ] || continue
        printf '%s\t%s\n' "$user" "$gen"
      done || true
}

# A content hash for the few entries in a home-files tree that are real files
# rather than symlinks into the store. Three spellings because this script is
# linted and tested on Linux and runs on macOS; `cksum` is the last resort and
# is only ever a weaker hash, never a wrong answer.
hash_file() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 -- "$1" | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum -- "$1" | cut -d' ' -f1
  else cksum -- "$1" | cut -d' ' -f1
  fi
}

# TSV relpath \t l|f \t identity, for every file home-manager installs from one
# home-files tree. `find` is deliberately NOT given -L: a symlink to a store
# DIRECTORY (the sketchybar plugins dir, a Claude skill) is ONE managed entry,
# and descending into it would compare files home-manager never links
# individually — the same choice home-manager's own find makes. Identity is the
# symlink target, which is content-addressed, so a differing target is a
# differing file with no hashing needed for the 90% case.
hm_file_list() {
  local root p rel
  # Resolved with cd+pwd -P, because `home-files` is ITSELF a symlink into the
  # store: `find` without -L would stop at that one link and report a tree of
  # exactly one entry. Not `readlink -f`, which is a GNU extension this script
  # avoids everywhere else for the same reason (see now_ds).
  root="$(cd "${1%/}" 2>/dev/null && pwd -P || true)"
  [ -n "$root" ] || return 0
  find "$root" \( -type f -o -type l \) -print 2>/dev/null | while IFS= read -r p; do
    rel="${p#"$root"/}"
    if [ -L "$p" ]; then printf '%s\tl\t%s\n' "$rel" "$(readlink "$p" || true)"
    else printf '%s\tf\t%s\n' "$rel" "$(hash_file "$p" || true)"
    fi
  done || true
}

# The relative paths that carry an onChange hook, out of the BUILT home-manager
# activation script, which emits one `echo "Running onChange hook for" <path>`
# per hook. So this needs no table of which file reloads which daemon: bar
# hashes its whole bar config into one stamp file precisely so ONE hook fires
# when any of ~20 files move, and this reports that hook because the stamp is
# in the changed set — not because anything here knows what bar is.
hm_onchange_paths() {
  grep -oE 'Running onChange hook for" .+' "$1/activate" 2>/dev/null \
    | sed 's/^Running onChange hook for" //' || true
}

# The commands one hook runs, tidied for reading. home-manager wraps them in an
# `if [[ ! -v DRY_RUN ]]` inside the hook's own `if (( ${changedFiles[<path>]}
# == 1 ))` block, so the block is bounded by the path itself. The `== 1` is
# part of the match on purpose: the same subscript also appears earlier in the
# script, on the `_cmp` line that COMPUTES changedFiles, and matching that
# would print the comparison instead of the hook. Store paths are shortened to
# the binary's name and redirections dropped — this is a preview, not a script.
hm_onchange_cmds() {
  awk -v key="$2" '
    /== 1 \)\)/ && index($0, "changedFiles[" key "]") { inblock = 1; next }
    inblock && /^fi$/ { exit }
    inblock && /^[[:space:]]*(if|fi|echo)/ { next }
    inblock && NF {
      # A trailing backslash continues the command, so join before tidying —
      # home-managers font hook is a four-line rsync, and printing its lines
      # separately renders half an invocation as if it were the whole hook.
      line = line $0
      if (sub(/\\[[:space:]]*$/, "", line)) next
      print line; line = ""
    }
    END { if (line != "") print line }
  ' "$1/activate" 2>/dev/null \
    | sed -E 's#^[[:space:]]*##; s#^(run|\$DRY_RUN_CMD)[[:space:]]+##; s#^[^ ]*/##; s#[[:space:]]*(2>|>|\|\|).*$##' \
    | awk 'NR <= 2 { print (length > 72 ? substr($0, 1, 71) "…" : $0) } NR == 3 { print "…" }' || true
}

# How many changed files to name before summarising. A nixpkgs bump can move
# hundreds of managed files at once, and a preview that scrolls off the screen
# is the same as no preview.
FILE_CAP=25

plan_files_user() { # <user> <new home-manager-generation> <old generation or empty>
  local user="$1" newgen="$2" oldgen="$3"
  local newlist oldlist touched hooks mark rel cmds
  local added=0 removed=0 changed=0 shown=0 hooked=0

  if [ -z "$oldgen" ]; then
    info "$user: no home-manager generation in the running system — every managed file would be new"
    return 0
  fi

  newlist="$(mktemp)"; oldlist="$(mktemp)"; touched="$(mktemp)"; hooks="$(mktemp)"
  hm_file_list "$newgen/home-files" >"$newlist"
  hm_file_list "$oldgen/home-files" >"$oldlist"

  # FILENAME rather than the usual NR==FNR: an empty old list would make the
  # whole new list look like the first file and report every change as nothing.
  while IFS=$'\t' read -r mark rel; do
    [ -n "$rel" ] || continue
    case "$mark" in
      +) added=$((added + 1)) ;;
      -) removed=$((removed + 1)) ;;
      '~') changed=$((changed + 1)) ;;
    esac
    [ "$mark" = "-" ] || printf '%s\n' "$rel" >>"$touched"
    if [ "$shown" -lt "$FILE_CAP" ]; then
      printf '  %s %s\n' "$mark" "$rel"
      shown=$((shown + 1))
    fi
  done < <(
    awk -F'\t' -v OFS='\t' -v oldfile="$oldlist" '
      FILENAME == oldfile { kind[$1] = $2; id[$1] = $3; old[$1] = 1; next }
      {
        if (!($1 in old)) { print "+", $1; next }
        delete old[$1]
        if ($2 != kind[$1] || $3 != id[$1]) print "~", $1
      }
      END { for (p in old) print "-", p }
    ' "$oldlist" "$newlist" | LC_ALL=C sort -t"$(printf '\t')" -k2,2
  )

  if [ "$((added + changed + removed))" -gt "$shown" ]; then
    info "… and $((added + changed + removed - shown)) more"
  fi

  # Which onChange hooks that set would fire — the answer to "it landed on disk,
  # but will anything notice?" A KeepAlive daemon that read its config once at
  # boot (sketchybar, AeroSpace) keeps the old one in memory until its hook runs.
  hm_onchange_paths "$newgen" | LC_ALL=C sort -u >"$hooks"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    cmds="$(hm_onchange_cmds "$newgen" "$rel" | awk '{ printf "%s%s", sep, $0; sep = " · " } END { print "" }' || true)"
    info "onChange: $rel → ${cmds:-a hook with no visible command}"
    hooked=$((hooked + 1))
  done < <(LC_ALL=C comm -12 "$hooks" <(LC_ALL=C sort -u "$touched"))

  if [ "$((added + changed + removed))" = 0 ]; then
    info "$user: no managed file would change ($(wc -l <"$newlist" | tr -d ' ') file(s) checked)"
  else
    info "$user: $changed changed, $added new, $removed removed — $hooked onChange hook(s) would fire"
  fi
  rm -f "$newlist" "$oldlist" "$touched" "$hooks"
}

plan_files() { # <new activate script> <the running system's activate script>
  local newgens oldgens user newgen oldgen
  newgens="$(hm_generations "$1")"
  if [ -z "$newgens" ]; then
    # Deliberately hedged rather than stated: a configuration genuinely without
    # home-manager and a chain this failed to follow (an upstream rename of the
    # `activation-<user>` wrapper, say) are indistinguishable from here, and
    # "there are none" would be a verdict where only one of the two is true.
    info "no home-manager generation found in this build — nothing to compare, or the activation chain has changed shape"
    return 0
  fi
  oldgens="$(hm_generations "$2")"
  while IFS=$'\t' read -r user newgen; do
    [ -n "$user" ] || continue
    oldgen="$(printf '%s\n' "$oldgens" | awk -F'\t' -v u="$user" '$1 == u { print $2; exit }')"
    plan_files_user "$user" "$newgen" "$oldgen"
  done < <(printf '%s\n' "$newgens")
}

# ---- which launchd jobs a rebuild would bounce ------------------------------
# Not a table of services: nix-darwin emits, per job,
#   if ! diff <the new plist in the store> <the installed plist>; then … reload
# so this runs that exact comparison read-only, one step early. A job whose
# plist is byte-identical is left alone by activation and reported unchanged
# here — which is precisely why a bar config change alone never restarts the
# bar (the plist didn't move), and why the onChange hook above is what makes it
# live. `~user/…` is expanded from the user database rather than by the shell:
# these paths come out of a generated script, and `eval`ing them to get a tilde
# expanded would be a needless hole.
expand_tilde() {
  local rest user tail home
  case "$1" in
    "~"*)
      rest="${1#\~}"; user="${rest%%/*}"; tail="${rest#*/}"
      home=""
      if command -v dscl >/dev/null 2>&1; then
        # Not `awk '{print $2}'`: a home directory containing a space would be
        # truncated at the first one, and every one of that user's agents would
        # then report "will create" against a path that isn't theirs.
        home="$(dscl . -read "/Users/$user" NFSHomeDirectory 2>/dev/null | sed -n 's/^NFSHomeDirectory: //p' | head -1 || true)"
      fi
      [ -n "$home" ] || home="$HOME"
      printf '%s/%s\n' "${home%/}" "$tail"
      ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# TSV job name \t new plist \t installed plist, for every launchd job an
# activation script guards with its own diff.
launchd_pairs() {
  sed -nE "s@^if ! diff '?([^' ]+)'? '?([^' ]+)'? &> /dev/null; then\$@\1\t\2@p" "$1" 2>/dev/null || true
}

plan_services() { # <new activate script> <the running system's activate script>
  local new inst name installed
  local reload="" create="" remove="" unchanged=0
  local newnames oldnames

  # A parse miss must never look like an answer. nix-darwin always ships at
  # least one daemon (org.nixos.activate-system), so zero guards means the shape
  # this reads has drifted — a bumped nix-darwin quoting that `if ! diff` line
  # differently. Without this the removal set below would be `comm -13 <empty>
  # <every running job>`, and plan would calmly announce that a rebuild is about
  # to unload the bar, the tiling and the palette. Saying "I could not read it"
  # is the only honest output there; silence that reads as a verdict is the
  # exact failure this whole section was added to end.
  if [ -z "$(launchd_pairs "$1")" ]; then
    warn "could not read any launchd guard out of this build — skipping the services preview (the activation script's shape has changed; this is a haus bug, not a machine problem)."
    return 0
  fi

  newnames="$(mktemp)"; oldnames="$(mktemp)"

  while IFS=$'\t' read -r new inst; do
    [ -n "$new" ] || continue
    name="$(basename "$new" .plist)"
    printf '%s\n' "$name" >>"$newnames"
    installed="$(expand_tilde "$inst")"
    if [ ! -e "$installed" ]; then
      create="$create${create:+, }$name"
    elif ! diff -q "$new" "$installed" >/dev/null 2>&1; then
      reload="$reload${reload:+, }$name"
    else
      unchanged=$((unchanged + 1))
    fi
  done < <(launchd_pairs "$1")

  # A job the new build no longer declares: activation unloads it. Read from the
  # OLD script's job list, since the new one has no line left to parse. Skipped
  # when the OLD script parses to nothing, for the mirror of the reason above: a
  # running system whose guards this cannot read would otherwise contribute no
  # names and quietly under-report a real removal.
  if [ -n "${2:-}" ] && [ -r "$2" ] && [ -n "$(launchd_pairs "$2")" ]; then
    launchd_pairs "$2" | cut -f1 | while IFS= read -r new; do basename "$new" .plist; done >"$oldnames"
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      remove="$remove${remove:+, }$name"
    done < <(LC_ALL=C comm -13 <(LC_ALL=C sort -u "$newnames") <(LC_ALL=C sort -u "$oldnames"))
  fi

  [ -z "$reload" ] || printf '  will reload: %s\n' "$reload"
  [ -z "$create" ] || printf '  will create: %s\n' "$create"
  [ -z "$remove" ] || printf '  will remove: %s\n' "$remove"
  if [ -z "$reload$create$remove" ]; then
    info "no launchd job would change ($unchanged checked)"
  else
    info "$unchanged other job(s) unchanged"
  fi
  rm -f "$newnames" "$oldnames"
}

# How activation makes the settings above live — read out of the built script
# rather than re-derived from modules/lib/restart-map.nix, so it cannot drift
# from what a rebuild actually runs (core renders that table into these exact
# calls). Unconditional by design, which is why this says "every rebuild"
# rather than "because a key changed": it is also the answer to why your Finder
# windows close.
plan_restarts() {
  local procs posts waits bits=""
  procs="$(grep -oE '^killall -qu [^ ]+ [A-Za-z]+' "$1" 2>/dev/null | awk '{ print $4 }' | LC_ALL=C sort -u | paste -sd, - || true)"
  posts="$(grep -oE "post-notification '?[A-Za-z0-9._-]+'?" "$1" 2>/dev/null | sed -E "s/post-notification '?//; s/'\$//" | LC_ALL=C sort -u | paste -sd, - || true)"
  [ -z "$procs" ] || bits="restarts ${procs//,/, }"
  if grep -q '"\$activateSettings" -u' "$1" 2>/dev/null; then
    bits="$bits${bits:+ · }broadcasts activateSettings"
  fi
  [ -z "$posts" ] || bits="$bits${bits:+ · }posts ${posts//,/, }"
  [ -z "$bits" ] || info "every rebuild also $bits"

  # And the half a restart CANNOT cover. core emits this line for any domain the
  # built configuration writes that macOS re-reads only at login, so the reader
  # stays "grep the built script" rather than a second copy of restart-map.nix.
  # Its own warning, not appended to the line above, because it is the opposite
  # kind of news: that one says what will happen, this one says what won't.
  waits="$(grep -oE 'haus: waits-for-logout [^"]+' "$1" 2>/dev/null | sed -E 's/^haus: waits-for-logout //' | tr ' ' '\n' | grep . | LC_ALL=C sort -u | paste -sd, - || true)"
  [ -z "$waits" ] || warn "waits for a logout — no live-reload path on macOS 26: ${waits//,/, }"
}

# The announcement core renders from modules/lib/reachability.nix — read the same
# way plan_restarts reads the restart map's, out of the BUILT script rather than
# from a second copy of the table.
#
# This is the front door §5.12 asked for. Full Disk Access is the one property
# that makes byte-identical config behave differently on two machines, and the
# only honest moment to say so is BEFORE the rebuild: `haus plan` never runs the
# script it greps, so it can report a grant this app hasn't got without paying
# for finding out the hard way. Each verdict is a different kind of news, so each
# gets its own line and its own severity.
plan_permissions() {
  local guarded unguarded noop
  guarded="$(_haus_verdict needs-full-disk-access "$1")"
  unguarded="$(_haus_verdict aborts-without-full-disk-access "$1")"
  noop="$(_haus_verdict writes-but-does-nothing "$1")"

  if [ -n "$unguarded" ]; then
    # The only one that can break the machine rather than the setting, so it
    # says which way it goes on THIS app rather than describing the hazard in
    # the abstract. `haus rebuild` refuses this combination outright.
    if has_fda; then
      info "needs Full Disk Access, unguarded — this app has it, so it will apply: ${unguarded//,/, }"
    else
      bad "would ABORT activation — ${unguarded//,/, } is written unguarded and this app has no Full Disk Access; every service after it would be skipped. Move those keys to haus.accessibility.*, or rebuild from an app that holds the grant."
    fi
  fi

  if [ -n "$guarded" ]; then
    if has_fda; then
      info "needs Full Disk Access — this app has it: ${guarded//,/, }"
    else
      warn "needs Full Disk Access, which this app hasn't got — these settings will be skipped and nothing else is affected: ${guarded//,/, }"
    fi
  fi

  [ -z "$noop" ] || warn "writes and changes nothing on macOS 26 — the plist will read back correct anyway: ${noop//,/, }"
}

# One `haus: <verdict> <domain>…` line out of a built activation script, as a
# comma-separated list. Shared by plan_permissions and doctor so the grep shape
# is written once; `|| true` throughout because a configuration with no such
# line is the common case, not an error, under this script's `set -e`.
_haus_verdict() {
  grep -oE "haus: $1 [^\"]+" "$2" 2>/dev/null \
    | sed -E "s/^haus: $1 //" | tr ' ' '\n' | grep . | LC_ALL=C sort -u | paste -sd, - || true
}

cmd_plan() {
  local host drvfile drvpath sysfile sys difffile
  host="$(host_name)"
  say "$host · plan — a preview of 'haus rebuild' (read-only; nothing is built into place)"
  info "from $CONSUMER"
  consumer_worktree_warning
  [ -n "$VERBOSE" ] || echo
  log_open "plan $host from $CONSUMER"

  drvfile="$(mktemp)"
  run_phase resolve heal resolve_drv "$host" "$drvfile" || die "evaluation failed — nothing was changed."
  drvpath="$(cat "$drvfile")"
  rm -f "$drvfile"
  phase_ok resolve "$HAUS_PHASE_ELAPSED"

  sysfile="$(mktemp)"
  if ! (cd "$CONSUMER" && nix build --no-link --print-out-paths "$drvpath^*") >"$sysfile"; then
    rm -f "$sysfile"
    die "build failed — plan needs a successful build to know what would change."
  fi
  sys="$(cat "$sysfile")"
  rm -f "$sysfile"

  echo
  say "packages"
  difffile="$(mktemp)"
  closure_diff /run/current-system "$sys" "$difffile"
  if [ -s "$difffile" ]; then sed 's/^/  /' "$difffile"; else info "no package changes"; fi
  rm -f "$difffile"

  echo
  say "settings"
  settings_diff "$sys/activate"
  plan_restarts "$sys/activate"
  plan_permissions "$sys/activate"

  # Everything home-manager writes into $HOME, which is most of haus and
  # none of the two sections above. See plan_files's header for why neither the
  # closure diff nor the settings diff can see a bar pill being switched on.
  echo
  say "files"
  plan_files "$sys/activate" /run/current-system/activate

  echo
  say "services"
  plan_services "$sys/activate" /run/current-system/activate

  echo
  say "homebrew"
  plan_homebrew "$sys"

  echo
  # NOT "nothing was changed", which is what this said until workshop#307: read
  # directly under a files section listing ten changed files, that sentence
  # reads as "your edit does nothing" rather than "this command changed
  # nothing", and it was the line that made a real change look like a no-op.
  info "this was a preview — nothing on this machine was touched. Apply it with: haus rebuild"
}

cmd_diff() {
  say "declared vs live — the config currently ACTIVE on this machine against what macOS actually has"
  [ -x /run/current-system/activate ] || die "no running system to compare against — haus rebuild first."
  echo
  settings_diff /run/current-system/activate
}

# ---- haus capture ------------------------------------------------------------
# Turn THIS Mac's current settings into pasteable haus host-config lines —
# the general form of bootstrap.sh's HAUS_KEEP (which only ever runs once,
# at install). bootstrap.sh keeps its own copy of this logic rather than
# depending on `haus`: it runs before the first switch, when `haus` isn't on
# PATH yet.
#
# Every domain this reads is ALSO snapshotted raw (`defaults export`), so a
# later `haus revert-settings` can put the exact bytes back — this is the
# "pre-activation preference snapshot" §5.11 asks for: run `haus capture`
# before a rebuild that's about to change settings you might want to keep.
SNAP_BASE="${XDG_STATE_HOME:-$HOME/.local/state}/haus/settings-snapshots"

cap_bool() { case "$(defaults read "$1" "$2" 2>/dev/null || true)" in 1) echo true ;; 0) echo false ;; esac; }
cap_int() {
  local v
  v="$(defaults read "$1" "$2" 2>/dev/null || true)"
  case "$v" in '' | *[!0-9-]*) : ;; *) echo "$v" ;; esac
}
cap_str() {
  local v
  v="$(defaults read "$1" "$2" 2>/dev/null || true)"
  [ -n "$v" ] && printf '"%s"' "$v"
}
cap_emit() { [ -n "${2:-}" ] && printf '  system.defaults.%s = %s;\n' "$1" "$2"; }

capture_dock() {
  cap_emit dock.autohide "$(cap_bool com.apple.dock autohide)"
  cap_emit dock.orientation "$(cap_str com.apple.dock orientation)"
  cap_emit dock.show-recents "$(cap_bool com.apple.dock show-recents)"
  cap_emit dock.mru-spaces "$(cap_bool com.apple.dock mru-spaces)"
}

capture_keyboard() {
  cap_emit NSGlobalDomain.KeyRepeat "$(cap_int NSGlobalDomain KeyRepeat)"
  cap_emit NSGlobalDomain.InitialKeyRepeat "$(cap_int NSGlobalDomain InitialKeyRepeat)"
  cap_emit NSGlobalDomain.ApplePressAndHoldEnabled "$(cap_bool NSGlobalDomain ApplePressAndHoldEnabled)"
  local kbdui; kbdui="$(cap_int NSGlobalDomain AppleKeyboardUIMode)"
  case "$kbdui" in 0 | 2 | 3) cap_emit NSGlobalDomain.AppleKeyboardUIMode "$kbdui" ;; esac
}

capture_finder() {
  local ext; ext="$(cap_bool NSGlobalDomain AppleShowAllExtensions)"
  cap_emit finder.AppleShowAllExtensions "$ext"
  cap_emit NSGlobalDomain.AppleShowAllExtensions "$ext"
  cap_emit finder.AppleShowAllFiles "$(cap_bool com.apple.finder AppleShowAllFiles)"
  cap_emit finder.FXPreferredViewStyle "$(cap_str com.apple.finder FXPreferredViewStyle)"
  cap_emit finder.ShowPathbar "$(cap_bool com.apple.finder ShowPathbar)"
  cap_emit finder.ShowStatusBar "$(cap_bool com.apple.finder ShowStatusBar)"
  cap_emit finder._FXSortFoldersFirst "$(cap_bool com.apple.finder _FXSortFoldersFirst)"
  cap_emit finder._FXSortFoldersFirstOnDesktop "$(cap_bool com.apple.finder _FXSortFoldersFirstOnDesktop)"
  cap_emit finder._FXShowPosixPathInTitle "$(cap_bool com.apple.finder _FXShowPosixPathInTitle)"
  cap_emit finder._FXEnableColumnAutoSizing "$(cap_bool com.apple.finder _FXEnableColumnAutoSizing)"
  cap_emit finder.FXDefaultSearchScope "$(cap_str com.apple.finder FXDefaultSearchScope)"
  cap_emit finder.FXEnableExtensionChangeWarning "$(cap_bool com.apple.finder FXEnableExtensionChangeWarning)"
  cap_emit finder.QuitMenuItem "$(cap_bool com.apple.finder QuitMenuItem)"
  cap_emit finder.ShowHardDrivesOnDesktop "$(cap_bool com.apple.finder ShowHardDrivesOnDesktop)"
  cap_emit finder.ShowExternalHardDrivesOnDesktop "$(cap_bool com.apple.finder ShowExternalHardDrivesOnDesktop)"
  cap_emit finder.ShowMountedServersOnDesktop "$(cap_bool com.apple.finder ShowMountedServersOnDesktop)"
  cap_emit finder.ShowRemovableMediaOnDesktop "$(cap_bool com.apple.finder ShowRemovableMediaOnDesktop)"
  local nwt=""
  case "$(defaults read com.apple.finder NewWindowTarget 2>/dev/null || true)" in
    PfCm) nwt='"Computer"' ;; PfVo) nwt='"OS volume"' ;;
    PfHm) nwt='"Home"' ;; PfDe) nwt='"Desktop"' ;;
    PfDo) nwt='"Documents"' ;; PfID) nwt='"iCloud Drive"' ;;
    PfLo) : ;; # "Other" needs NewWindowTargetPath too — leave both to haus
    Recents | "") : ;;
    *) nwt='"Recents"' ;;
  esac
  cap_emit finder.NewWindowTarget "$nwt"
  cap_emit NSGlobalDomain.NSTableViewDefaultSizeMode "$(cap_int NSGlobalDomain NSTableViewDefaultSizeMode)"
  cap_emit NSGlobalDomain.NSNavPanelExpandedStateForSaveMode "$(cap_bool NSGlobalDomain NSNavPanelExpandedStateForSaveMode)"
  cap_emit NSGlobalDomain.NSNavPanelExpandedStateForSaveMode2 "$(cap_bool NSGlobalDomain NSNavPanelExpandedStateForSaveMode2)"
  cap_emit NSGlobalDomain.NSDocumentSaveNewDocumentsToCloud "$(cap_bool NSGlobalDomain NSDocumentSaveNewDocumentsToCloud)"
}

# Any other domain: not a friendly category, so there's no known nix-darwin
# attribute path for it — but system.defaults.CustomUserPreferences takes a
# raw plist domain directly, which is exactly what this is. Nested (array or
# dict) values are called out rather than emitted, since JSON's `[a, b]` isn't
# valid nix list syntax (`[ a b ]`) and silently emitting it would be a nix
# file that doesn't evaluate.
capture_domain_block() {
  local domain="$1" json body
  json="$(defaults export "$domain" - 2>/dev/null | plutil -convert json -o - - 2>/dev/null)" || return 0
  [ -n "$json" ] && [ "$json" != "null" ] && [ "$json" != "{}" ] || return 0
  # Rendered into a variable first, not streamed straight to stdout: a jq
  # failure must skip the WHOLE domain, not print an opening `= {` with no
  # closing `};` (a truncated block would be worse than the domain missing).
  body="$(
    printf '%s\n' "$json" | jq -r '
      to_entries[] |
      if (.value | type) == "array" or (.value | type) == "object"
      then "    # " + .key + " — nested value, add it by hand if you need it"
      else "    " + (.key | @json) + " = " + (.value | tojson) + ";"
      end
    '
  )" || return 0
  printf '  system.defaults.CustomUserPreferences."%s" = {\n%s\n  };\n' "$domain" "$body"
}

cmd_capture() {
  local cats=("$@") cat lines="" domains=() cats_used=()
  [ "${#cats[@]}" -gt 0 ] || cats=(dock keyboard finder)

  for cat in "${cats[@]}"; do
    case "$cat" in
      dock) lines+="$(capture_dock)"$'\n'; domains+=(com.apple.dock); cats_used+=("$cat") ;;
      keyboard) lines+="$(capture_keyboard)"$'\n'; domains+=(NSGlobalDomain); cats_used+=("$cat") ;;
      finder) lines+="$(capture_finder)"$'\n'; domains+=(com.apple.finder NSGlobalDomain); cats_used+=("$cat") ;;
      *.*) lines+="$(capture_domain_block "$cat")"$'\n'; domains+=("$cat"); cats_used+=("$cat") ;;
      *) die "unknown capture category '$cat' — try: dock keyboard finder, or a literal domain like com.apple.Terminal" ;;
    esac
  done

  # De-dupe (finder and keyboard both touch NSGlobalDomain).
  local uniq_domains=() d s seen
  for d in "${domains[@]}"; do
    seen=""
    for s in ${uniq_domains[@]+"${uniq_domains[@]}"}; do [ "$s" = "$d" ] && seen=1; done
    [ -n "$seen" ] || uniq_domains+=("$d")
  done

  local ts snapdir
  ts="$(date -u '+%Y%m%dT%H%M%SZ')"
  snapdir="$SNAP_BASE/$ts"
  mkdir -p "$snapdir"
  : >"$snapdir/manifest.tsv"
  for d in "${uniq_domains[@]}"; do
    if defaults export "$d" "$snapdir/$(printf '%s' "$d" | tr '/' '_').plist" 2>/dev/null; then
      printf '%s\t%s\n' "$d" "$snapdir/$(printf '%s' "$d" | tr '/' '_').plist" >>"$snapdir/manifest.tsv"
    else
      warn "couldn't export $d (empty or unreadable domain) — not in the snapshot"
    fi
  done
  ln -sfn "$ts" "$SNAP_BASE/latest"

  say "captured $(IFS=,; echo "${cats_used[*]}") — snapshot: $snapdir"
  echo
  printf '%s' "$lines"
  echo
  info "paste what you want into your host file — a line you don't paste means 'use haus's default'."
  info "the snapshot above is what 'haus revert-settings' puts back if you don't like where a rebuild takes this."
}

# ---- haus revert-settings ----------------------------------------------------
# The installer already admits Nix rollback doesn't undo macOS defaults —
# `haus rollback` rewinds every package and launchd agent, atomically, but a
# Dock or Finder preference just sits there. This is the other half: restore
# the exact snapshot `haus capture` took, byte for byte (`defaults import`,
# not a replay of individual key writes), then make it live the same way core's
# own postActivation does — a Dock/Finder/universalaccessd restart plus
# activateSettings, so nothing waits for a logout.
cmd_revert_settings() {
  local which="${1:-latest}" snapdir domain file rc=0 touched_dock="" touched_finder="" touched_ua=""

  if [ "$which" = "list" ]; then
    if [ ! -d "$SNAP_BASE" ]; then
      info "no snapshots yet — run 'haus capture' first."
      return 0
    fi
    say "settings snapshots ($SNAP_BASE):"
    local latest d name
    latest="$(readlink "$SNAP_BASE/latest" 2>/dev/null || true)"
    for d in "$SNAP_BASE"/*/; do
      [ -d "$d" ] || continue
      name="$(basename "$d")"
      [ "$name" = latest ] && continue # the symlink alias, not a snapshot of its own
      printf '  %s%s\n' "$name" "$([ "$name" = "$latest" ] && echo '  (latest)' || echo '')"
    done
    return 0
  fi

  snapdir="$SNAP_BASE/$which"
  [ -d "$snapdir" ] || die "no snapshot '$which' — try 'haus revert-settings list'."
  [ -f "$snapdir/manifest.tsv" ] || die "$snapdir has no manifest.tsv — was it written by 'haus capture'?"

  say "restoring settings from $snapdir"
  while IFS=$'\t' read -r domain file; do
    [ -n "$domain" ] || continue
    if { [ "$domain" = com.apple.universalaccess ] || [ "$domain" = com.apple.Accessibility ]; } && ! has_fda; then
      warn "$domain needs Full Disk Access on this app to restore — skipped (run from a terminal that has it)"
      continue
    fi
    if defaults import "$domain" "$file" 2>/dev/null; then
      ok "$domain restored"
      [ "$domain" = com.apple.dock ] && touched_dock=1
      [ "$domain" = com.apple.finder ] && touched_finder=1
      [ "$domain" = com.apple.universalaccess ] && touched_ua=1
    else
      bad "$domain: restore failed"
      rc=1
    fi
  done <"$snapdir/manifest.tsv"

  # `|| true` on every one of these: a `defaults write`-triggered restart is
  # allowed to no-op (Dock/Finder not running, activateSettings missing on a
  # future macOS) without aborting the rest of this command under `set -e` —
  # same convention modules/core/default.nix uses for the identical calls.
  [ -n "$touched_dock" ] && { killall -qu "$(id -un)" Dock 2>/dev/null || true; }
  [ -n "$touched_finder" ] && { killall -qu "$(id -un)" Finder 2>/dev/null || true; }
  # universalaccessd for the same reason as the two above, added 2026-08-14:
  # cursor size and the closeView pair are invisible until this daemon rereads
  # the domain, so a restore without it puts the bytes back and shows the user
  # nothing until their next logout — the failure this whole command exists to
  # avoid. Unconditional on the domain rather than per-key: `defaults import`
  # replaces the whole plist, so which keys moved isn't knowable here.
  [ -n "$touched_ua" ] && { killall -qu "$(id -un)" universalaccessd 2>/dev/null || true; }

  # Same broadcast core's postActivation makes after writing preferences — run
  # as ourselves (not root, so no launchctl-asuser wrapping needed here).
  local activateSettings=/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings
  [ -x "$activateSettings" ] && { "$activateSettings" -u 2>/dev/null || true; }

  if [ "$rc" = 0 ]; then say "restored."; else warn "some domains failed to restore — see above."; fi
  return "$rc"
}

cmd_rebuild() {
  local host drv sys old gen_before drvfile outfile difffile bt0
  host="$(host_name)"
  guard_unguarded_fda "$host"

  old="$(cd /run/current-system 2>/dev/null && pwd -P || true)"
  gen_before="$(current_gen || echo '?')"
  drvfile="$(mktemp)"; outfile="$(mktemp)"; difffile="$(mktemp)"
  log_open "rebuild $host from $CONSUMER"

  say "$host · rebuild"
  consumer_worktree_warning
  [ -n "$VERBOSE" ] || echo

  run_phase resolve heal resolve_drv "$host" "$drvfile" \
    || die "evaluation failed — nothing was changed."
  drv="$(cat "$drvfile")"; rm -f "$drvfile"
  phase_ok resolve "$HAUS_PHASE_ELAPSED"

  # Homebrew's half of the rebuild, alongside nix's rather than after it. Joined
  # at bg_wait below, before anything activates.
  bg "${BREW_JOB:-brew_prefetch}"

  # Build. Deliberately neither hidden nor logged: nix draws its progress bar
  # only when stderr is a terminal, and a rebuild with gigabytes to fetch should
  # be able to say so. We only hide what we write down — this is the one phase
  # that narrates itself, so it keeps the terminal.
  bt0="$(now_ds)"
  ( cd "$CONSUMER" && nix build --print-out-paths --out-link "$CONSUMER/result" "$drv^*" ) >"$outfile" \
    || die "build failed — nothing was changed."
  sys="$(cat "$outfile")"; rm -f "$outfile"
  phase_ok build "$(secs $(( $(now_ds) - bt0 )) )"

  # The one thing a rebuild never used to tell you: what actually changed.
  # Backgrounded so it costs nothing — it reads the OLD system, which is still
  # current until the activation below swaps it.
  [ -n "$old" ] && bg closure_diff "$old" "$sys" "$difffile"
  bg_wait || warn "a background job failed — see $HAUS_LOG (continuing)"

  # Activate exactly what we just built. The old route here was
  # `darwin-rebuild switch --flake`, which BUILDS again as root — a second
  # evaluation against root's separate caches, costing ~3 s after a host edit
  # and ~15 s whenever a flake input moved (root re-unpacks nixpkgs into its
  # own lazy-trees cache). `haus-activate` does only the privileged half; see
  # modules/core/haus-activate.sh. No `heal`: nothing here evaluates or fetches,
  # so the corrupt-fetch-cache signature can't arise past the build above.
  #
  # Both paths go through a stable /run/current-system path, never ./result or
  # a store path: security's passwordless-sudo rule matches the literal path,
  # because sudo no longer follows the command symlink.
  #
  # Quiet mode redirects this phase's stdout+stderr, which is safe for the one
  # thing that must never be swallowed here: sudo writes its password prompt to
  # /dev/tty, not to either stream (and where there's no tty, VERBOSE is already
  # on). A Touch ID prompt is a GUI dialog, so it's unaffected either way.
  if [ -x /run/current-system/sw/bin/haus-activate ]; then
    run_phase activate sudo /run/current-system/sw/bin/haus-activate "$CONSUMER/result"
  else
    # The running system predates haus-activate — take the old, slower route
    # once; the switch it performs is what installs the fast one.
    run_phase activate heal legacy_switch "$host"
  fi || die "activation failed partway — generation $gen_before is still on disk (haus rollback), and the log above says where it stopped."
  phase_ok activate "$HAUS_PHASE_ELAPSED" "$(activation_summary)"

  # Generation + closure diff: the two lines that are actually about YOUR
  # machine rather than about the tools that rebuilt it.
  if [ -n "$VERBOSE" ]; then
    say "the house stands."
  else
    local gen_after changed n
    gen_after="$(current_gen || echo '?')"
    printf '  \033[38;5;108m✓\033[0m %-9s %6s  \033[38;5;103m%s\033[0m\n' generation '' \
      "$([ "$gen_before" = "$gen_after" ] && echo "$gen_after (unchanged)" || echo "$gen_before → $gen_after")"
    n="$(wc -l <"$difffile" 2>/dev/null | tr -d ' ')"; n="${n:-0}"
    echo
    if [ "$n" = "0" ]; then
      info "nothing changed in the closure"
    else
      changed="$(sed 's/^ *//' "$difffile" | head -3 | paste -sd', ' -)"
      [ "$n" -gt 3 ] && changed="$changed, +$((n - 3)) more"
      info "$changed"
    fi
    say "the house stands."
  fi
  rm -f "$difffile"
}

# Family apps (pounce, perch…) ship as CI-published casks/formulae in
# hausfold/tap, released on their OWN cadence — a haus flake bump never carries
# them. Worse, activation's `brew bundle` leans on Homebrew's auto-update, which
# is THROTTLED: a rebuild can run against a stale tap clone and never see a fresh
# release (the "released but not installed" trap). So do an explicit, unthrottled
# `brew update` + a targeted upgrade of just the hausfold/tap packages here —
# third-party casks keep whatever upgrade policy the host set (autoUpdate/upgrade).
#
# Both tap directories are probed: the tap was `nebelhaus/tap` until the org
# migration, and a machine that tapped it before then still has the old dir on
# disk. Homebrew keys a tap by the directory, not by where it redirects to, so
# looking only at the new path would turn this into a silent no-op — which is
# indistinguishable from "nothing to upgrade", the exact trap above.
refresh_family_apps() {
  command -v brew >/dev/null 2>&1 || return 0
  local root tap="" cand
  root="$(brew --repository 2>/dev/null)" || return 0
  for cand in "$root/Library/Taps/hausfold/homebrew-tap" \
              "$root/Library/Taps/nebelhaus/homebrew-tap"; do
    [ -d "$cand" ] && { tap="$cand"; break; }
  done
  [ -n "$tap" ] || return 0
  brew update --quiet >/dev/null 2>&1 || warn "brew update failed — family apps may be stale"
  local kind dir f name
  for kind in Casks Formula; do
    dir="$tap/$kind"; [ -d "$dir" ] || continue
    for f in "$dir"/*.rb; do
      [ -e "$f" ] || continue
      name="$(basename "$f" .rb)"
      if [ "$kind" = Casks ]; then
        brew list --cask "$name" >/dev/null 2>&1 || continue
        brew upgrade --cask "$name" || warn "  $name: upgrade failed"
      else
        brew list --formula "$name" >/dev/null 2>&1 || continue
        brew upgrade --formula "$name" || warn "  $name: upgrade failed"
      fi
    done
  done
}

# The changelog fetch and the family-app refresh, so cmd_update can start them
# and walk away. Both are network-bound and neither gates the build.
fetch_changelog() { # <owner> <repo> <old> <new> <outfile>
  curl -fsSL --max-time 5 \
    -H 'accept: application/vnd.github+json' \
    "https://api.github.com/repos/$1/$2/compare/$3...$4" 2>/dev/null \
    | jq -r '.commits[]?.commit.message | split("\n")[0]' 2>/dev/null | head -15 >"$5" || true
}

# The whole brew half of an update, as ONE job — family apps first, then a
# prefetch of whatever else activation will upgrade. One job and not two
# because brew takes a global lock: two of these in parallel would serialise
# anyway, badly, on a lock timeout rather than on the work.
update_brew_job() { refresh_family_apps; brew_prefetch; }

cmd_update() {
  local old new owner repo logfile input
  old="$(jq -r '(.nodes.haus // .nodes.nebelhaus).locked.rev // ""' "$CONSUMER/flake.lock" 2>/dev/null || true)"
  # 🚨 The input NAME belongs to the consumer's flake, not to us — and
  # `nix flake update <name that isn't in the lock>` WARNS AND EXITS 0 without
  # touching anything. So a hardcoded name here doesn't fail loudly, it turns
  # `haus update` into a permanent no-op that then reports "already at the
  # latest". Scaffolded configs said `nebelhaus` until 2026-08-14 and say `haus`
  # since (rename note §11.2), so read the name back out of the lock.
  input="$(jq -r 'if (.nodes[.root].inputs.haus? // null) != null then "haus"
                  elif (.nodes[.root].inputs.nebelhaus? // null) != null then "nebelhaus"
                  else "" end' "$CONSUMER/flake.lock" 2>/dev/null || true)"
  [ -n "$input" ] || input=haus
  say "pulling the latest haus …"
  ( cd "$CONSUMER" && heal nix flake update "$input" )
  new="$(jq -r '(.nodes.haus // .nodes.nebelhaus).locked.rev // ""' "$CONSUMER/flake.lock" 2>/dev/null || true)"
  if [ -n "$old" ] && [ "$old" = "$new" ]; then
    say "already at the latest haus (${new:0:12}) — rebuilding anyway."
  elif [ -n "$old" ] && [ -n "$new" ]; then
    # What's about to land. Best-effort via the GitHub compare API — offline,
    # rate-limited, or non-GitHub upstreams just skip the list. Fetched in the
    # background: it's a 5-second timeout on a network you may not have, and
    # nothing downstream waits on it.
    owner="$(jq -r '(.nodes.haus // .nodes.nebelhaus).original.owner // "hausfold"' "$CONSUMER/flake.lock")"
    repo="$(jq -r '(.nodes.haus // .nodes.nebelhaus).original.repo // "haus"' "$CONSUMER/flake.lock")"
    logfile="$(mktemp)"
    bg fetch_changelog "$owner" "$repo" "$old" "$new" "$logfile"
  fi
  # The rebuild's own bg_wait joins this before anything activates.
  BREW_JOB=update_brew_job
  cmd_rebuild
  if [ -n "${logfile:-}" ]; then
    if [ -s "$logfile" ]; then
      echo
      say "new in haus (${old:0:7} → ${new:0:7}):"
      sed 's/^/  · /' "$logfile"
    fi
    rm -f "$logfile"
  fi
}

cmd_rollback() {
  if [ -n "${1:-}" ]; then
    say "switching to generation $1 …"
    sudo darwin-rebuild --switch-generation "$1"
  else
    say "rolling back to the previous generation …"
    sudo darwin-rebuild --rollback
  fi
  say "rolled back. (Nix reverts everything IT manages; macOS system settings and"
  warn "Homebrew apps are not rewound — see haus status / your notes.)"
}

cmd_generations() {
  local cur link num nums total show; cur="$(current_gen || echo '')"
  nums="$(for link in "$SYSPROFILES"/system-*-link; do
    [ -e "$link" ] || continue
    num="$(basename "$link")"; num="${num#system-}"; echo "${num%-link}"
  done | sort -rn)"
  total="$(echo "$nums" | grep -c .)"
  show=20
  # Newest first, capped — the recent ones are what you roll back to.
  echo "$nums" | head -n "$show" | while read -r num; do
    printf '%s %5s   %s\n' "$([ "$num" = "$cur" ] && echo '→' || echo ' ')" "$num" "$(gen_date "$num" '+%Y-%m-%d %H:%M')"
  done
  [ "$total" -gt "$show" ] && say "… and $((total - show)) older (roll back to any with: haus rollback <N>)"
  return 0
}

cmd_status() {
  local host lockrev lockdate url owner repo ref remoterev
  host="$(host_name)"
  say "this machine: $host"

  echo
  say "current generation"
  local cur; cur="$(current_gen || echo '')"
  if [ -n "$cur" ]; then printf '  %s  (%s)\n' "$cur" "$(gen_date "$cur")"
  else warn "  (none yet — haus rebuild)"; fi

  echo
  say "pinned haus"
  if [ -f "$CONSUMER/flake.lock" ]; then
    lockrev="$(jq -r '(.nodes.haus // .nodes.nebelhaus).locked.rev // "?"' "$CONSUMER/flake.lock")"
    lockdate="$(jq -r '(.nodes.haus // .nodes.nebelhaus).locked.lastModified // 0' "$CONSUMER/flake.lock")"
    if [ "$lockdate" != "0" ]; then
      printf '  %s  (%s)\n' "${lockrev:0:12}" "$(date -r "$lockdate" '+%Y-%m-%d' 2>/dev/null || echo '?')"
    else
      printf '  %s\n' "${lockrev:0:12}"
    fi
    # Is upstream haus ahead of what you've pinned? Best-effort, offline-safe.
    owner="$(jq -r '(.nodes.haus // .nodes.nebelhaus).original.owner // "hausfold"' "$CONSUMER/flake.lock")"
    repo="$(jq -r '(.nodes.haus // .nodes.nebelhaus).original.repo // "haus"' "$CONSUMER/flake.lock")"
    ref="$(jq -r '(.nodes.haus // .nodes.nebelhaus).original.ref // "HEAD"' "$CONSUMER/flake.lock")"
    url="https://github.com/$owner/$repo.git"
    remoterev="$(git ls-remote "$url" "$ref" 2>/dev/null | awk 'NR==1{print $1}')"
    if [ -n "$remoterev" ] && [ "$remoterev" != "$lockrev" ]; then
      warn "  a newer haus is available upstream (${remoterev:0:12}) — haus update"
    elif [ -n "$remoterev" ]; then
      ok "up to date with upstream"
    fi
  else
    warn "  no flake.lock yet"
  fi
}

cmd_edit() {
  local host f
  host="$(host_name)"
  f="$CONSUMER/hosts/$host/default.nix"
  [ -f "$f" ] || die "no host file at $f"
  exec "${EDITOR:-hx}" "$f"
}

# ---- haus set / get / unset / reset ----------------------------------------
# The machine-writable overlay is deliberately ordinary Nix: one tiny module
# per option under hosts/<host>/settings/, auto-imported by mkHaus beside
# Pounce's packages/ modules. There is no second settings database to drift.
#
# These files use mkForce because this layer is the machine owner's explicit
# answer and must be able to override its desktop. `haus reset` removes that answer
# entirely, revealing the host/desktop/room value underneath. `haus unset` is a
# different operation: it explicitly writes null, and therefore only succeeds
# for nullable options.
settings_path() {
  local raw="$1" path
  [ -n "$raw" ] || die "an option path is required (for example: theme.accent)"
  # `nebelhaus.` is accepted as the pre-rename spelling of the same namespace
  # (modules/renamed.nix), but the canonical prefix is what gets WRITTEN — an
  # overlay file is regenerated on every `haus set`, so this upgrades old ones
  # in place without a migration.
  case "$raw" in
    haus.*) path="$raw" ;;
    nebelhaus.*) path="haus.${raw#nebelhaus.}" ;;
    *) path="haus.$raw" ;;
  esac
  # A component may start with a digit: the keys of an `attrsOf` option are the
  # user's, not haus's, and `haus.displays.<uuid>.uiScale` is the worked
  # example — display UUIDs begin with a hex digit as often as not.
  [[ "$path" =~ ^haus(\.[A-Za-z0-9_][A-Za-z0-9_-]*)+$ ]] \
    || die "only haus.* option paths are writable (got '$raw')"
  printf '%s\n' "$path"
}

# `haus.displays."37D8832A-…".uiScale` — a component that isn't a bare Nix
# identifier gets quoted, and only then, so the common file still reads as the
# plain attrpath a human would have typed.
settings_attrpath() {
  local out="" c
  local IFS=.
  # Deliberate word splitting on '.' — that is what makes this a path walk.
  # shellcheck disable=SC2086
  for c in $1; do
    case "$c" in
      # A Nix keyword is all letters and still not an identifier, so it needs the
      # quotes as much as a UUID does — `haus.displays.if.uiScale` is a syntax
      # error otherwise, and an attrsOf key can be any word the user likes.
      assert | else | if | in | inherit | let | or | rec | then | with) c="\"$c\"" ;;
      [A-Za-z_]*) ;;
      *) c="\"$c\"" ;;
    esac
    out="${out:+$out.}$c"
  done
  printf '%s' "$out"
}

settings_host_dir() {
  printf '%s/hosts/%s/settings\n' "$CONSUMER" "$(host_name)"
}

settings_file() {
  local path="$1"
  printf '%s/%s.nix\n' "$(settings_host_dir)" "${path#haus.}"
}

# Does this path name something settable? `options.<path>` alone can't answer
# that, and that was the old guard's bug: the module system's options tree stops
# at an option, so `options.haus.bar.items` exists but `options.haus.bar.items.
# aiUsage` does not — a submodule's sub-options live behind `type.getSubOptions`,
# and an `attrsOf`'s keys aren't in the tree at all because they're the user's to
# invent. Both are perfectly ordinary definition sites, so both were being
# refused, leaving the whole-attrset form (`haus set bar.items '{"cpu":true}'`)
# as the only way in — which silently resets every key you didn't name.
#
# So walk it instead, one component at a time:
#   - a plain attrset of options: index into it (`bar` → `bar.bottom`)
#   - an option whose type is attrsOf/lazyAttrsOf: the next component is a KEY,
#     free-form by definition, so consume it without checking
#   - an option with sub-options (submodule, or nullOr/attrsOf of one): descend
#     into getSubOptions, which is where a submodule's declared options live
#   - anything left over with nowhere to go is a typo, and is still refused
# A leaf reached this way is settable exactly when the module system would accept
# a definition there, which is the property this guard is trying to have.
#
# Running OUT of components has to land on an option, not merely somewhere: the
# old guard refused `haus set theme '{…}'` because a namespace has no `.type`,
# and it was right to. A whole-room mkForce evaluates fine and then quietly
# scatters over every option in the room — and, now, collides with the overlap
# guard, so one of those would lock every leaf under it out of `haus set`.
settings_option_exists() {
  local host="$1" path="$2" parts result err
  # Every component is [A-Za-z0-9_-]+ by now (settings_path), so this is safe to
  # interpolate into Nix string literals.
  parts="$(printf '%s' "${path#haus.}" | tr '.' '\n' | sed 's/.*/"&"/' | tr '\n' ' ')"
  err="$(mktemp)"
  result="$(
    cd "$CONSUMER" && nix eval --json ".#darwinConfigurations.$host" --apply "cfg:
      let
        isOption = x: (x._type or null) == \"option\";
        descend = node: ps:
          if ps == [ ] then isOption node
          else if isOption node then
            (let
              rest = if node.type.name == \"attrsOf\" || node.type.name == \"lazyAttrsOf\"
                     then builtins.tail ps else ps;
              subs = node.type.getSubOptions [ ];
            in if rest == [ ] then true
               else if subs == { } then false
               else into subs rest)
          else into node ps;
        into = attrs: ps:
          let h = builtins.head ps; in
          if !builtins.isAttrs attrs then false
          else if !(attrs ? \${h}) then false
          else descend attrs.\${h} (builtins.tail ps);
      in descend cfg.options.haus [ $parts ]" 2>"$err"
  )" || {
    # A failure here is the host file or the pinned haus not evaluating at all,
    # never this walk — so show nix's own words rather than a shrug.
    warn "could not evaluate this machine's option surface:"
    tail -n 12 "$err" >&2
    rm -f "$err"
    die "'$path' could not be checked (try: haus doctor)"
  }
  rm -f "$err"
  [ "$result" = "true" ] \
    || die "'$path' is not a settable option on this machine's pinned haus"
}

# One override per path is the model, and a path plus one of its ancestors is
# not one override — `bar.items` written whole and `bar.items.cpu` written on
# its own are two mkForce definitions of the same leaf the moment they name the
# same key, and the module system reports that from inside the submodule, as a
# conflict between two anonymous definitions the caller can't trace back to
# either file. So refuse the overlap here, where both file names are in hand.
# Prints the offending path and returns 0 when there is one.
settings_overlap() {
  local path="$1" p f
  shift
  p="$path"
  while [ "${p%.*}" != "$p" ] && [ "${p%.*}" != "haus" ]; do
    p="${p%.*}"
    [ -e "$(settings_file "$p")" ] && { printf '%s\n' "$p"; return 0; }
    for f in "$@"; do [ "$f" = "$p" ] && { printf '%s\n' "$p"; return 0; }; done
  done
  for f in "$(settings_host_dir)/${path#haus.}."*.nix; do
    [ -e "$f" ] || continue
    printf 'haus.%s\n' "$(basename "$f" .nix)"
    return 0
  done
  for f in "$@"; do
    case "$f" in "$path".*) printf '%s\n' "$f"; return 0 ;; esac
  done
  return 1
}

settings_stage() {
  local target="$1" rel
  rel="${target#"$CONSUMER"/}"
  if git -C "$CONSUMER" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$CONSUMER" add -A -- "$rel"
  fi
}

settings_eval_json() {
  local host="$1" path="$2"
  ( cd "$CONSUMER" && nix eval --json ".#darwinConfigurations.$host.config.$path" )
}

settings_print_json() {
  jq -r 'if type == "string" then . else tojson end'
}

# True when a path is GONE rather than broken. An `attrsOf` key exists only
# because something defined it, so withdrawing the last definition of
# `displays.<uuid>.uiScale` takes the key away instead of revealing a value
# underneath — the reset working, but failing to evaluate exactly like a real
# conflict does. The nearest ancestor that still evaluates tells them apart: a
# conflict takes the tree above it down too, a vanished key doesn't.
settings_path_vanished() {
  local host="$1" p="$2"
  while [ "${p%.*}" != "$p" ]; do
    p="${p%.*}"
    settings_eval_json "$host" "$p" >/dev/null 2>&1 && return 0
  done
  return 1
}

settings_literal() {
  local raw="$1" parsed lines
  # JSON covers booleans, numbers, null, lists and attrsets. A bare token is the
  # ergonomic string form (`haus set theme.accent teal`). Quoted strings also
  # work when a caller wants to distinguish "true" from the boolean true.
  if parsed="$(printf '%s' "$raw" | jq -c '.' 2>/dev/null)"; then
    lines="$(printf '%s\n' "$parsed" | wc -l | tr -d ' ')"
  else
    lines=0
  fi
  if [ "$lines" = 1 ]; then
    printf 'builtins.fromJSON %s' "$(jq -Rn --arg value "$parsed" '$value')"
  else
    jq -Rn --arg value "$raw" '$value'
  fi
}

settings_restore() {
  local target="$1" backup="$2"
  if [ -n "$backup" ]; then cp -p "$backup" "$target"; else rm -f "$target"; fi
  settings_stage "$target"
}

settings_apply() {
  if [ -n "${HAUS_NO_REBUILD:-}" ]; then
    info "not rebuilding (HAUS_NO_REBUILD is set)"
  else
    cmd_rebuild
  fi
}

# `rm -f ""` is not portably a no-op, and an override that had no previous file
# is recorded as an empty backup path, so drop them one at a time.
settings_drop_backups() {
  local b
  for b in "$@"; do [ -n "$b" ] && rm -f "$b"; done
  return 0
}

# Write ONE override file. No validation, no rebuild — cmd_set owns both,
# because with several pairs neither can be per-file (see its header).
settings_write() {
  local path="$1" value="$2" dir="$3" target="$4" tmp literal attrpath
  literal="$(settings_literal "$value")"
  attrpath="$(settings_attrpath "$path")"
  tmp="$(mktemp "$dir/.haus-set.XXXXXX")"
  {
    printf '%s\n' '# Managed by haus set. Ordinary Nix: safe to inspect or edit.'
    printf '# Remove this override with: haus reset %s\n' "${path#haus.}"
    # One arg per %s: `printf FMT a b` reuses FMT, so a shared '%s\n\n' here
    # would put a blank line after the opening brace as well as before it.
    printf '%s\n\n' '{ lib, ... }:'
    printf '%s\n' '{'
    printf '  %s = lib.mkForce (%s);\n' "$attrpath" "$literal"
    printf '%s\n' '}'
  } >"$tmp"
  mv "$tmp" "$target"
  settings_stage "$target"
}

# The rollback half of the set/reset transaction, kept out of the trap body so
# the trap is one line. Reads the TX_* globals the command fills in; deliberately
# NOT `local` there, because a trap reaching into another frame's locals is the
# kind of thing that works until someone refactors. Shared by cmd_set and
# cmd_reset — restoring a backup and un-removing a file are the same operation,
# and settings_restore already treats an empty backup as "there was no file".
settings_tx_rollback() {
  local k
  for k in ${TX_TARGETS[@]+"${!TX_TARGETS[@]}"}; do
    [ "${TX_BACKUPS[$k]+set}" = set ] || continue # never got as far as touching this one
    settings_restore "${TX_TARGETS[$k]}" "${TX_BACKUPS[$k]}" || true
  done
  settings_drop_backups ${TX_BACKUPS[@]+"${TX_BACKUPS[@]}"}
}

# The offline options catalogue — every settable `haus.*` path with its type,
# its default and one line of prose, rendered from THIS machine's pinned haus by
# the same derivation as the annotated host file (modules/options-catalogue.jq).
#
# It is READ, never evaluated, and that is the whole point. `settings_option_
# exists` answers "is this settable?" by evaluating the entire darwin config,
# which is seconds — right for accepting a value, hopeless for drawing a menu of
# 200 rows or answering a Tab. So the picker and the zsh completion read this
# file and leave cmd_set's eval as the one authority on what is actually legal.
HAUS_CATALOGUE="${HAUS_CATALOGUE:-/run/current-system/sw/share/haus/options.json}"

# The value prompt's shape, read off the module system's own type prose.
#
# A type names a CLOSED set exactly when, after peeling a leading `null or ` and
# a leading `boolean or `, what's left is `boolean` or an `one of "…"` list. That
# peeling is not pedantry — it is what keeps the three real shapes apart:
#
#   boolean                                    → true / false
#   null or one of "12h", "24h"                → null / 12h / 24h
#   boolean or one of "left", "center", …      → true / false / left / center / …
#   null or positive integer, …, or value "never"
#                                              → OPEN. Has quoted tokens and is
#                                                still mostly a number, so a list
#                                                would take away every value the
#                                                option is mainly for.
#
# Prints one candidate per line, nothing at all when the set is open.
settings_type_choices() {
  local type="$1" rest
  rest="${type#null or }"
  rest="${rest#boolean or }"
  case "$rest" in
    boolean | 'one of "'*) ;;
    *) return 0 ;;
  esac
  case "$type" in "null or"*) printf 'null\n' ;; esac
  case "$type" in *boolean*) printf 'true\nfalse\n' ;; esac
  # Quotes exist in these type strings only around enum members, and `haus set`
  # takes a bare token as the string form, so strip them. A plain `boolean` has
  # none, and grep finding nothing is not a failure here.
  case "$type" in
    *'one of "'*) printf '%s' "$type" | grep -o '"[^"]*"' | tr -d '"' ;;
  esac
}

# `haus set` with nothing to set: pick the option, then the value. Fills PICK
# with the pair; returns non-zero when the user backs out of either prompt.
#
# Two prompts, and the second one's shape comes from the type — a closed set is a
# list you arrow through, everything else a text box holding the current default.
# Nothing here validates. It hands a pair to cmd_set, which owns the write, the
# type-check, the backups and the rollback; a picker that pre-judged any of that
# would be a second, weaker authority that disagrees with the first one on
# exactly the machines where it matters.
settings_pick() {
  local usage="$1" sel path type default literal prefill value line
  local -a choices=()
  PICK=()

  [ -t 0 ] && [ -t 1 ] || die "$usage"
  command -v gum >/dev/null 2>&1 || die "picking an option needs gum — $usage"
  [ -r "$HAUS_CATALOGUE" ] \
    || die "no options catalogue at $HAUS_CATALOGUE (haus rebuild installs it) — $usage"

  # Path AND prose in the row, because the filter matches the whole line: you
  # can search for `flavor` or for `light mode` and land on the same option.
  sel="$(
    jq -r 'to_entries[] | "\(.key[5:])\t\(.value.summary)"' "$HAUS_CATALOGUE" \
      | awk -F'\t' '{ printf "%-38s %s\n", $1, $2 }' \
      | gum filter --height 20 --placeholder 'which option?' --prompt 'haus set '
  )" || return 1
  # Padded columns, and no `haus.*` path contains a space — so the first field
  # is the path however long it ran.
  path="${sel%% *}"
  [ -n "$path" ] || return 1

  type="$(jq -r --arg p "haus.$path" '.[$p].type' "$HAUS_CATALOGUE")"
  default="$(jq -r --arg p "haus.$path" '.[$p].default // ""' "$HAUS_CATALOGUE")"
  literal="$(jq -r --arg p "haus.$path" '.[$p].literal' "$HAUS_CATALOGUE")"
  say "$path"
  info "type: $type"
  [ -n "$default" ] && info "default: $default"

  while IFS= read -r line; do choices+=("$line"); done < <(settings_type_choices "$type")

  if [ "${#choices[@]}" -gt 0 ]; then
    # --selected puts the cursor on the current default rather than the top of
    # the list, so the first thing you see is what the machine does today. Only
    # when the default is actually one of the choices, though: gum takes it as a
    # comma-separated list of items to pre-select, and rather than find out per
    # gum release what an unknown one does, don't hand it one. Every option's
    # default type-checks, so this holds for all of today's; it's the option with
    # no default at all that this is here for.
    local bare
    local -a selected=()
    bare="$(printf '%s' "$default" | tr -d '"')"
    for line in "${choices[@]}"; do
      if [ "$line" = "$bare" ]; then selected=(--selected "$line"); fi
    done
    value="$(printf '%s\n' "${choices[@]}" | gum choose ${selected[@]+"${selected[@]}"})" \
      || return 1
  else
    # Prefill only a default that would round-trip. `haus set` reads its value as
    # JSON (settings_literal), and a Nix-only default like `[ "self" "nebelung" ]`
    # is not JSON — handing it back as the starting text would quietly turn the
    # whole list into one string the moment someone pressed Enter. Those get an
    # empty box, with the default still on screen above it.
    prefill=""
    if [ "$literal" = true ] && printf '%s' "$default" | jq . >/dev/null 2>&1; then
      prefill="$default"
    fi
    value="$(gum input --value "$prefill" --placeholder "${default:-value}" \
                       --prompt "$path = ")" || return 1
  fi
  # Every way out of here says so. Backing out of a prompt is a perfectly normal
  # thing to do, and the alternative — cmd_set exiting 0 with nothing printed —
  # is indistinguishable from the command having quietly failed. An empty text
  # box counts as backing out: pressing Enter on nothing is how people leave a
  # prompt they opened by accident, and the empty STRING is still reachable as
  # `""`, which is also how you write it on the command line.
  if [ -z "$value" ]; then
    info "nothing entered — $path is unchanged"
    return 1
  fi
  if ! gum confirm "set $path = $value, then rebuild?"; then
    info "left $path alone"
    return 1
  fi
  PICK=("$path" "$value")
}

# `haus set` takes PAIRS: `haus set theme.flavor latte theme.systemAppearance flavor`.
#
# Not ergonomics — arithmetic. settings_apply is a full rebuild, so N calls is N
# rebuilds, and the intents that genuinely need more than one option (pounce's
# "Switch to light mode", which is theme.flavor AND theme.systemAppearance) would
# otherwise rebuild twice AND leave the machine sitting in the half-done state in
# between. One call, one validation, one rebuild.
#
# Every file is written BEFORE anything is validated, and ANY failure between the
# first write and the last type-check restores ALL of them — via an EXIT trap, not
# just the explicit rejection path. That distinction is the whole safety property
# and it was found by the pre-PR assurance pass: `set -e` has plenty of other ways
# out of here (a stale `.git/index.lock` making `settings_stage` fail is the
# realistic one), and with a single pair those aborted before anything else was on
# disk. With pairs they'd leave file 1 written, staged, unvalidated and un-restored
# — precisely the half-done machine this command exists to prevent, with no error
# the user can act on. (`ERR` would not do: the script has `set -e` but not `set -E`,
# so an ERR trap isn't inherited into settings_write/settings_stage.)
#
# Validating each pair as it lands is the other tempting shape and it is worse: it
# leaves pairs 1..n-1 applied when pair n is refused, which is the same partial
# write, arrived at deliberately.
cmd_set() {
  # cmd_unset delegates here, and quoting `haus set`'s pair syntax at someone who
  # typed `haus unset` names a command they didn't run — so it may override this.
  local usage="${TX_USAGE:-usage: haus set <haus.path|relative.path> <value> [<path> <value>…]}"
  # No arguments is not a usage error any more — it's the picker. `haus unset`
  # can't land here with none (it dies on its own usage first), so TX_USAGE
  # being set is enough to keep this out of a delegated call's way.
  if [ "$#" -eq 0 ] && [ -z "${TX_USAGE:-}" ]; then
    settings_pick "$usage" || exit 0
    set -- "${PICK[@]}"
  fi
  [ "$#" -ge 2 ] && [ $(( $# % 2 )) -eq 0 ] || die "$usage"
  local host dir path target backup clash seen="" i err
  local -a paths=() values=() results=()
  TX_TARGETS=() TX_BACKUPS=()
  host="$(host_name)"
  dir="$(settings_host_dir)"

  # Phase 1 — resolve every pair and refuse anything we can't own, before a
  # single byte is written. A path named twice is an error rather than
  # last-one-wins: the second write's "backup" would be the first write's file,
  # so a restore would leave the first value in place and report failure.
  while [ "$#" -gt 0 ]; do
    path="$(settings_path "$1")"
    settings_option_exists "$host" "$path"
    case "$seen" in *"|$path|"*) die "$usage — ${path#haus.} named twice" ;; esac
    seen="$seen|$path|"
    target="$(settings_file "$path")"
    if [ -e "$target" ] && ! grep -q '^# Managed by haus set\.' "$target"; then
      die "$target already exists and is not managed by haus; edit it by hand"
    fi
    if clash="$(settings_overlap "$path" ${paths[@]+"${paths[@]}"})"; then
      die "${path#haus.} overlaps ${clash#haus.}, which is already set — \
reset one of them first (haus reset ${clash#haus.})"
    fi
    paths+=("$path"); values+=("$2"); TX_TARGETS+=("$target")
    shift 2
  done

  # Phase 2 — from here until phase 3 succeeds, ANY exit rolls everything back.
  mkdir -p "$dir"
  trap 'settings_tx_rollback' EXIT
  for i in "${!paths[@]}"; do
    # Register the backup only once the copy is IN it. Appending first and
    # filling it after would, on a failed `cp`, leave the rollback restoring an
    # empty file over the user's previous override — a worse outcome than the
    # failure itself. An unregistered temp file is the cheap side of that trade.
    if [ -e "${TX_TARGETS[$i]}" ]; then
      backup="$(mktemp)"; cp -p "${TX_TARGETS[$i]}" "$backup"; TX_BACKUPS+=("$backup")
    else
      TX_BACKUPS+=("")
    fi
    settings_write "${paths[$i]}" "${values[$i]}" "$dir" "${TX_TARGETS[$i]}"
  done

  # Phase 3 — one evaluation per path, keeping the value so phase 4 needn't
  # re-evaluate. The first rejection reports and lets the trap do the restoring.
  err="$(mktemp)"
  for i in "${!paths[@]}"; do
    if results+=("$(settings_eval_json "$host" "${paths[$i]}" 2>"$err")"); then continue; fi
    warn "the generated override did not type-check; restored the previous file(s)."
    tail -n 12 "$err" >&2
    rm -f "$err"
    die "'${paths[$i]}' rejected that value — no config change remains"
  done
  rm -f "$err"
  trap - EXIT
  settings_drop_backups ${TX_BACKUPS[@]+"${TX_BACKUPS[@]}"}

  # Phase 4 — report everything, then rebuild ONCE.
  for i in "${!paths[@]}"; do
    say "set ${paths[$i]#haus.} = $(printf '%s' "${results[$i]}" | settings_print_json)"
    info "${TX_TARGETS[$i]} (staged as ordinary Nix)"
  done
  settings_apply
}

cmd_get() {
  local path host dir f json found=""
  host="$(host_name)"
  if [ -n "${1:-}" ]; then
    path="$(settings_path "$1")"
    settings_option_exists "$host" "$path"
    # A settable path need not be a defined one: nothing has to have named this
    # `attrsOf` key yet. Saying so beats printing a blank line — on stderr, so
    # `$(haus get …)` stays the value alone and this doesn't become one.
    if json="$(settings_eval_json "$host" "$path" 2>/dev/null)"; then
      printf '%s' "$json" | settings_print_json
    else
      info "${path#haus.} is settable, but nothing defines it yet" >&2
    fi
    return
  fi

  dir="$(settings_host_dir)"
  [ -d "$dir" ] || { info "no machine-writable settings; use: haus set <path> <value>"; return; }
  for f in "$dir"/*.nix; do
    [ -e "$f" ] || continue
    grep -q '^# Managed by haus set\.' "$f" || continue
    path="haus.$(basename "$f" .nix)"
    json="$(settings_eval_json "$host" "$path" 2>/dev/null)" || continue
    printf '%-38s %s\n' "${path#haus.}" "$(printf '%s' "$json" | settings_print_json)"
    found=1
  done
  [ -n "$found" ] || info "no machine-writable settings; use: haus set <path> <value>"
}

# Variadic for the same arithmetic as cmd_set, which does the actual work: every
# path becomes a `<path> null` pair, so N paths are one validation and one
# rebuild, all-or-nothing, and an option whose type has no null takes the whole
# call down rather than leaving the others applied.
cmd_unset() {
  # Bash's dynamic scope makes this local visible inside cmd_set, so a rejection
  # from down there quotes the invocation the user actually typed rather than
  # `haus set`'s pair syntax.
  local TX_USAGE="usage: haus unset <haus.path|relative.path> [<path>…]"
  [ "$#" -ge 1 ] || die "$TX_USAGE"
  local p
  local -a pairs=()
  for p in "$@"; do pairs+=("$p" null); done
  # Validation after writing is intentional: the module system is the one
  # authority on whether this option's type admits null.
  cmd_set "${pairs[@]}"
}

# The mirror image of cmd_set, phase for phase, and variadic for the same reason:
# an intent that took two options to express takes two files to withdraw, and
# doing that as two calls is two rebuilds with a half-undone machine in between
# (`haus set theme.flavor latte theme.systemAppearance flavor` is light mode; one
# `haus reset theme.flavor theme.systemAppearance` is the way back).
#
# Removing a file can fail validation exactly like writing one — not because
# some other option breaks (nix is lazy; phase 3 only forces the path being
# withdrawn, so it would never see that), but because the definition underneath
# is the one the override was masking: two host/desktop modules that conflict on
# this option evaluate fine while mkForce sits on top of them and stop doing so
# the moment it is removed. So the removals are a transaction too, under the same
# EXIT trap — settings_restore puts a backed-up file back, which is all
# "un-remove" means here.
cmd_reset() {
  local usage="usage: haus reset <haus.path|relative.path> [<path>…]"
  [ "$#" -ge 1 ] || die "$usage"
  local host path target backup seen="" i err
  local -a paths=() results=() inherited=()
  TX_TARGETS=() TX_BACKUPS=()
  host="$(host_name)"

  # Phase 1 — resolve every path and refuse anything we can't own, before a
  # single file is removed. A path that has no override is noted and dropped
  # rather than fatal: the caller asked for it to inherit, and it already does,
  # so `haus reset a b` still withdraws b. Noted, not said — a later path can
  # still take the whole call down, and a transcript that reported success for
  # one path before dying reads as if something happened.
  while [ "$#" -gt 0 ]; do
    path="$(settings_path "$1")"
    settings_option_exists "$host" "$path"
    case "$seen" in *"|$path|"*) die "$usage — ${path#haus.} named twice" ;; esac
    seen="$seen|$path|"
    target="$(settings_file "$path")"
    if [ ! -e "$target" ]; then
      inherited+=("${path#haus.} already inherits the host/desktop/room value ($(settings_eval_json "$host" "$path" 2>/dev/null | settings_print_json))")
      shift; continue
    fi
    grep -q '^# Managed by haus set\.' "$target" \
      || die "$target is not managed by haus; refusing to remove it"
    paths+=("$path"); TX_TARGETS+=("$target")
    shift
  done
  # Nothing was overridden, so nothing changed — say so, but don't spend a
  # rebuild on it.
  if [ "${#paths[@]}" -eq 0 ]; then
    for i in ${inherited[@]+"${!inherited[@]}"}; do say "${inherited[$i]}"; done
    return 0
  fi

  # Phase 2 — from here until phase 3 succeeds, ANY exit puts every file back.
  trap 'settings_tx_rollback' EXIT
  for i in "${!paths[@]}"; do
    # Register the backup only once the copy is IN it — see cmd_set's phase 2.
    backup="$(mktemp)"; cp -p "${TX_TARGETS[$i]}" "$backup"; TX_BACKUPS+=("$backup")
    rm -f "${TX_TARGETS[$i]}"
    settings_stage "${TX_TARGETS[$i]}"
  done

  # Phase 3 — one evaluation per path, keeping the inherited value for phase 4.
  err="$(mktemp)"
  for i in "${!paths[@]}"; do
    if results+=("$(settings_eval_json "$host" "${paths[$i]}" 2>"$err")"); then continue; fi
    # The failed substitution already appended "", which phase 4 reads as "gone".
    if settings_path_vanished "$host" "${paths[$i]}"; then continue; fi
    warn "removing the override did not type-check; restored the previous file(s)."
    tail -n 12 "$err" >&2
    rm -f "$err"
    die "'${paths[$i]}' cannot inherit its underlying value — no config change remains"
  done
  rm -f "$err"
  trap - EXIT
  settings_drop_backups ${TX_BACKUPS[@]+"${TX_BACKUPS[@]}"}
  rmdir "$(settings_host_dir)" 2>/dev/null || true

  # Phase 4 — report everything, then rebuild ONCE.
  for i in ${inherited[@]+"${!inherited[@]}"}; do say "${inherited[$i]}"; done
  for i in "${!paths[@]}"; do
    if [ -n "${results[$i]}" ]; then
      say "reset ${paths[$i]#haus.}; now inherits $(printf '%s' "${results[$i]}" | settings_print_json)"
    else
      say "reset ${paths[$i]#haus.}; nothing defines it now"
    fi
  done
  settings_apply
}

# ---- haus options -----------------------------------------------------------
# Refresh hosts/<host>/options.nix — the annotated catalogue of every
# haus.* option at its default, all commented out. The bootstrap writes it
# once at install; this is how it gets refreshed when `haus update` moves the
# pin and haus grows options that weren't in your copy.
#
# Read from the SYSTEM PROFILE, not built on demand: core ships it (see
# core/default.nix), so what you get is exactly the option surface this machine
# is pinned to. Nothing here evaluates or fetches anything.
#
# It never silently overwrites. Once you've uncommented lines in your copy that
# file is yours, so a re-run writes options.nix.new beside it and shows the
# diff — you merge what you want. --force is the "I never edited it" shortcut.
HOST_TEMPLATE="${HAUS_HOST_TEMPLATE:-/run/current-system/sw/share/haus/host-options.nix}"

cmd_options() {
  local force="" host dir dest
  [ "${1:-}" = "--force" ] && force=1

  [ -f "$HOST_TEMPLATE" ] \
    || die "no option template at $HOST_TEMPLATE — this machine's haus predates it; run 'haus update' first."

  host="$(host_name)"
  dir="$CONSUMER/hosts/$host"
  dest="$dir/options.nix"
  [ -d "$dir" ] || die "no host directory at $dir"

  if [ ! -e "$dest" ] || [ -n "$force" ]; then
    cp -f "$HOST_TEMPLATE" "$dest"
    chmod u+w "$dest"   # it comes out of the store read-only
    say "wrote $dest ($(grep -c '^  # haus\.' "$dest") options, all commented out)"
  elif cmp -s "$HOST_TEMPLATE" "$dest"; then
    say "$dest is already current."
    return 0
  else
    cp -f "$HOST_TEMPLATE" "$dest.new"
    chmod u+w "$dest.new"
    say "your options.nix differs from this pin's — wrote $dest.new instead."
    diff -u "$dest" "$dest.new" | sed -n '1,40p' | sed 's/^/  /' || true
    info "merge what you want, then: rm $dest.new   (or: haus options --force to replace)"
  fi

  # The catalogue only does anything if the host file imports it. Say so rather
  # than editing default.nix behind their back — that file is hand-written.
  if ! grep -q '\./options\.nix' "$dir/default.nix" 2>/dev/null; then
    printf '\n'
    warn "$dir/default.nix doesn't import it yet. Add this line inside the { … } block:"
    printf '\n      imports = [ ./options.nix ];\n\n'
  fi
}

cmd_doctor() {
  local uid; uid="$(id -u)"
  say "haus doctor"

  # On macOS 26 Tahoe+, a "stopped agent" is often BTM gating the /bin/sh-invoked
  # nix login item rather than a cold-boot wedge — point at `haus btm` when so.
  local osver osmajor btmhint=""
  osver="$(sw_vers -productVersion 2>/dev/null || echo 0)"; osmajor="${osver%%.*}"
  [ "${osmajor:-0}" -ge 26 ] && btmhint=" · on Tahoe+ this is often BTM: haus btm"

  # Determinate Nix (core assumes it owns the daemon: nix.enable = false).
  if [ -f /nix/receipt.json ]; then ok "Determinate Nix installed"
  elif [ -d /nix ]; then bad "/nix exists but not Determinate — haus expects the Determinate installer"
  else bad "Nix not installed"; fi
  pgrep -qx nix-daemon && ok "nix-daemon running" || bad "nix-daemon not running"

  # Xcode CLT (pounce compiles against system Swift; git comes from here too).
  /usr/bin/xcode-select -p >/dev/null 2>&1 && ok "Xcode Command Line Tools" || bad "Xcode CLT missing — xcode-select --install"

  command -v darwin-rebuild >/dev/null 2>&1 && ok "darwin-rebuild on PATH" || bad "darwin-rebuild missing — has this machine switched yet?"

  # GUI agents — only report on the ones whose launchd plist exists (i.e. the
  # rooms you enabled). Running is good; stopped may just mean the room is off.
  echo
  say "GUI agents"
  local label name
  for pair in "org.nixos.aerospace:AeroSpace" "org.nixos.sketchybar:sketchybar" "com.hausfold.pounce:pounce"; do
    label="${pair%%:*}"; name="${pair##*:}"
    if launchctl print "gui/$uid/$label" >/dev/null 2>&1; then
      if pgrep -qx "$name"; then ok "$name running"
      else bad "$name enabled but not running — check /tmp/$name.err.log (a wedged cold-boot agent: launchctl kickstart -k gui/$uid/$label)$btmhint"; fi
    fi
  done

  # Every TCC grant haus actually depends on, in ONE place, each with the
  # System Settings pane that grants it. It was three grants reported in three
  # different sections before, none of them linked — and a permission you can't
  # find the pane for is the same as a permission you don't have.
  #
  # macOS has no API to ask "is <grant> given to <app>" for most of these, and
  # the ones that exist answer only for the CALLING app. So this reports what it
  # can measure, says plainly when it can't, and links the pane either way. The
  # links are `x-apple.systempreferences:` URLs — not http, so `open` is the only
  # thing that follows them, which is why they're printed as a command.
  #
  # Every row is per-APP, not per-machine: the answer legitimately differs
  # between your terminal, an agent's pane and a shipped .app, and that
  # asymmetry is itself the bug people hit (an agent-driven rebuild refusing
  # where a hand-run one succeeds).
  echo
  say "Permissions"
  local pane="x-apple.systempreferences:com.apple.preference.security"

  # Accessibility — pounce's auto-paste and emoji insertion (the #1 "why won't
  # paste work" gotcha), bar's popover monitor, and the media pill's tab reach
  # on Firefox forks, which expose no scriptable tab list at all.
  if launchctl print "gui/$uid/com.hausfold.pounce" >/dev/null 2>&1; then
    if command -v pounce >/dev/null 2>&1 && [ "$(pounce --check-accessibility 2>/dev/null)" = "true" ]; then
      ok "Accessibility — pounce has it (auto-paste + emoji work)"
    else
      bad "Accessibility — pounce is missing it. Grant once: pounce --request-accessibility"
      info "  or by hand: open '$pane?Privacy_Accessibility'"
    fi
  else
    info "Accessibility — nothing here asks for it yet (pounce is off): open '$pane?Privacy_Accessibility'"
  fi

  # Full Disk Access — reported for the app running THIS command, because that is
  # the identity `haus rebuild` writes TCC-protected domains under.
  #
  # The grant alone was never the actionable half: on a machine that declares
  # nothing in a protected domain it costs nothing to lack it, and on one that
  # declares an UNGUARDED key it costs the whole activation. So this crosses the
  # capability with what the RUNNING system actually asks for, read out of the
  # same announcement `haus plan` reads (core renders it from
  # modules/lib/reachability.nix). A checklist that knows both can say which of
  # the four combinations you are in instead of leaving you to work it out.
  local fda_guarded fda_unguarded fda_all
  fda_guarded="$(_haus_verdict needs-full-disk-access /run/current-system/activate)"
  fda_unguarded="$(_haus_verdict aborts-without-full-disk-access /run/current-system/activate)"
  # `paste -sd,` and not `-sd', '`: -d takes a LIST of delimiters and cycles
  # through it, so a two-character one joins three items as "a,b c". Only one
  # domain can appear today, which is exactly why this would have gone unseen.
  fda_all="$(printf '%s\n%s\n' "$fda_unguarded" "$fda_guarded" | tr ',' '\n' | grep . | LC_ALL=C sort -u | paste -sd, - || true)"
  if has_fda; then
    if [ -n "$fda_all" ]; then
      ok "Full Disk Access — this app has it, and this config needs it (${fda_all//,/, })"
    else
      ok "Full Disk Access — this app has it (nothing in this config needs it today)"
    fi
  elif [ -n "$fda_unguarded" ]; then
    bad "Full Disk Access — this app hasn't got it and this config writes ${fda_unguarded//,/, } UNGUARDED, so 'haus rebuild' refuses rather than half-activate. Move those keys to haus.accessibility.*, or rebuild from an app that holds the grant: open '$pane?Privacy_AllFiles'"
  elif [ -n "$fda_guarded" ]; then
    warn "Full Disk Access — this app hasn't got it, so ${fda_guarded//,/, } is skipped on every rebuild from here (nothing else is affected; a rebuild from an app that has it applies them): open '$pane?Privacy_AllFiles'"
  else
    info "Full Disk Access — this app has none, and nothing in this config needs it. It is what haus.accessibility.* wants; without it those settings are skipped and nothing else: open '$pane?Privacy_AllFiles'"
  fi

  # Automation — the one grant with NO readable state: every API for it prompts,
  # and prompting from a health check is worse than not knowing. So this reports
  # whether anything on this machine will ask, which is the actionable half.
  # haus.theme.systemAppearance drives System Events, and the media pill drives
  # the scriptable browsers; both degrade to a warning rather than failing.
  local hmgen appearance=""
  hmgen="$(hm_generations /run/current-system/activate | head -1 | cut -f2 || true)"
  # `|| true` because this whole `&&` chain IS the statement: under this script's
  # `set -euo pipefail` a chain that ends false aborts doctor partway through,
  # printing nothing after it — the same trap `settings_diff` hit, and the common
  # case here (appearance unmanaged) is the false one.
  if [ -n "$hmgen" ] && [ -f "$hmgen/activate" ] &&
    grep -q 'hausSystemAppearance' "$hmgen/activate" 2>/dev/null; then
    appearance=1
  fi
  if [ -n "$appearance" ]; then
    info "Automation — haus.theme.systemAppearance drives System Events on every rebuild; without the grant the appearance silently stays put (the rebuild still succeeds): open '$pane?Privacy_Automation'"
  else
    info "Automation — nothing needs it unless you set haus.theme.systemAppearance, or ⌘-click the media pill to reach a browser tab: open '$pane?Privacy_Automation'"
  fi

  # Homebrew casks are declared in nix (homebrew.casks) but live OUTSIDE Nix
  # generations: `haus rollback` swaps the system profile without re-running
  # `brew bundle`, so casks never rewind with the generation — that's a
  # permanent, by-design caveat, not a fault (hence a plain note). The real
  # fault worth a ⚠ is drift: a cask installed but NOT in the declared Brewfile
  # (only possible when cleanup ≠ "zap"), which no rebuild will manage. Detect
  # it by diffing `brew list --cask` against the current system's Brewfile —
  # the one nix-darwin's activate script feeds to `brew bundle --file=`.
  if command -v brew >/dev/null 2>&1; then
    echo
    say "Homebrew"
    local installed brewfile declared undeclared count
    installed="$(brew list --cask 2>/dev/null || true)"
    count="$(printf '%s\n' "$installed" | grep -c . || true)"
    brewfile="$(grep -oE "brew bundle --file='[^']+'" /run/current-system/activate 2>/dev/null | sed "s/.*--file='//;s/'\$//" || true)"
    if [ -n "$brewfile" ] && [ -f "$brewfile" ]; then
      # Declared cask tokens, minus any tap prefix (pear-devs/pear/foo → foo),
      # so they line up with the bare names `brew list --cask` prints.
      declared="$(sed -nE 's/^cask "([^"]+)".*/\1/p' "$brewfile" | sed -E 's#.*/##')"
      undeclared="$(comm -13 <(printf '%s\n' "$declared" | sort -u) <(printf '%s\n' "$installed" | sort -u) | grep . || true)"
      if [ -z "$undeclared" ]; then
        ok "brew on PATH ($count casks, all declared)"
      else
        ok "brew on PATH ($count casks installed)"
        warn "$(printf '%s' "$undeclared" | grep -c .) undeclared cask(s) no rebuild will manage: $(printf '%s' "$undeclared" | paste -sd, - ) — declare them or 'brew uninstall --zap <cask>'"
      fi
    else
      # No readable Brewfile (unswitched machine, or path moved) — can't diff, so
      # just report the count without claiming everything is or isn't declared.
      ok "brew on PATH ($count casks installed)"
    fi
    info "casks live outside Nix generations — 'haus rollback' won't rewind them (that's by design)"
  fi

  # Nebelung ports for roster apps. modules/theme/ports.nix drops each themeable
  # roster app's theme file where that app looks for it and writes what it could
  # NOT finish here — because a file on disk only makes a theme active for apps
  # that read a fixed path. The ones needing a click are exactly what a health
  # check is for: they look like "the theme didn't work" and are otherwise
  # invisible. Absent file = the room is off (or predates this), so stay quiet.
  local portsreport="$HOME/.config/haus/nebelung-ports.tsv"
  if [ -s "$portsreport" ]; then
    echo
    say "Nebelung theme"
    local status title detail
    while IFS=$'\t' read -r status title detail; do
      [ -n "$status" ] || continue
      case "$status" in
        done)          ok   "$title — themed ($detail)" ;;
        step|manual)   info "$title — $detail" ;;
      esac
    done < "$portsreport"
  fi

  # Agents — whether an AI agent can usefully and safely drive this machine.
  # Three separate questions, all of which have bitten someone: does it have the
  # knowledge (the skill), does the config repo orient it (an AGENTS.md), and can
  # a rebuild from an agent pane actually complete — that third one is Full Disk
  # Access, and it moved to the Permissions section above with the other grants.
  #
  # AGENTS.md is the file that matters: Codex, OpenCode, Cursor, Copilot and
  # anything else that speaks agents.md read it, while Claude Code reads only
  # CLAUDE.md. So a repo with just a CLAUDE.md orients exactly one client — worth
  # saying out loud, since the agent keybind can spawn any of the three.
  echo
  say "Agents"
  # The skill lands once per installed client, each in the directory that client
  # scans (terminal's agentHomes). Report the first one found rather than the
  # Claude path alone: on a codex-only machine that path is legitimately absent,
  # and saying "no skill" there sent people to set an option already true.
  local skilldir=""
  local d
  for d in "$HOME/.claude/skills/haus" "$HOME/.codex/skills/haus" "$HOME/.config/opencode/skills/haus"; do
    if [ -f "$d/SKILL.md" ]; then
      skilldir="$d"
      break
    fi
  done
  if [ -n "$skilldir" ]; then
    ok "the haus skill is installed ($skilldir)"
  else
    info "no haus skill — set haus.ai.skill = true to let an agent change this machine"
  fi
  if [ -f "$CONSUMER/AGENTS.md" ] && [ -f "$CONSUMER/CLAUDE.md" ]; then
    ok "$CONSUMER/AGENTS.md orients any agent opened there (+ CLAUDE.md imports it)"
  elif [ -f "$CONSUMER/AGENTS.md" ]; then
    info "$CONSUMER/AGENTS.md orients most agents, but Claude Code reads only CLAUDE.md — add one holding '@AGENTS.md'"
  elif [ -f "$CONSUMER/CLAUDE.md" ]; then
    info "$CONSUMER/CLAUDE.md orients Claude Code only — Codex and OpenCode read AGENTS.md; move the rules there and leave '@AGENTS.md' behind"
  elif [ -f "$skilldir/consumer-AGENTS.md" ]; then
    # `install -m 644`, never `cp`: the starter pair are symlinks into the Nix
    # store, whose files are r--r--r--. A plain `cp` preserves that mode, so the
    # user lands on an AGENTS.md their editor refuses to save — on the one file
    # the whole point of copying is to then edit.
    info "nothing orients an agent opened in your config — start from haus's pair: install -m 644 $skilldir/consumer-AGENTS.md $CONSUMER/AGENTS.md && install -m 644 $skilldir/consumer-CLAUDE.md $CONSUMER/CLAUDE.md"
  else
    info "nothing orients an agent opened in your config, and the starter pair isn't here to copy — set haus.ai.skill = true, rebuild, then re-run 'haus doctor'"
  fi
  # The third agent question — can a rebuild from an agent pane complete? — is
  # Full Disk Access, and it is reported once, under Permissions above, rather
  # than a second time here: a grant stated in two sections is two places to
  # correct when the wording is wrong.

  # Secrets — the declaration (secretspec.toml) rebuilds with Nix, but the
  # VALUES live in the provider and may need entering once per machine.
  echo
  say "Secrets"
  if command -v secretspec >/dev/null 2>&1; then
    local provider
    provider="$(sed -n 's/^provider *= *"\(.*\)"/\1/p' "$HOME/.config/secretspec/config.toml" 2>/dev/null | head -1)"
    if [ -n "$provider" ]; then ok "secretspec on PATH (default provider: $provider)"
    else warn "no default provider — set haus.secrets.provider, or run: secretspec config init"; fi
    # If your config flake declares secrets, verify their values are present.
    # </dev/null keeps check from prompting; missing values are for `set`.
    if [ -f "$CONSUMER/secretspec.toml" ]; then
      if (cd "$CONSUMER" && secretspec check </dev/null >/dev/null 2>&1); then
        ok "all secrets in $CONSUMER/secretspec.toml have values"
      else
        bad "missing secret values — run: cd $CONSUMER && secretspec check"
      fi
    fi
  else
    bad "secretspec missing — 'haus rebuild' installs it (the secrets room)"
  fi
}

# macOS 26 Tahoe and later gate LaunchDaemons/Agents whose executable isn't
# Apple-signed, via Background Task Management (BTM). Every nix login item runs
# through `/bin/sh -c "…"`, which BTM flags as "unidentified developer" and can
# silently refuse to launch at login — the agent registers but never starts, so
# your bar/tiling/palette come up dead after the upgrade. There is NO declarative
# fix: the remedy is a toggle in the BTM store, which is GUI-only (sfltool can
# dump it but not set it). So this DETECTS the condition and prints the one-time
# manual fix. A pure no-op before Tahoe — nothing to gate there.
cmd_btm() {
  local ver major
  ver="$(sw_vers -productVersion 2>/dev/null || echo 0)"; major="${ver%%.*}"
  say "Background Task Management (BTM)"

  if [ "${major:-0}" -lt 26 ]; then
    ok "macOS $ver — pre-Tahoe; BTM doesn't gate nix daemons here. Nothing to do."
    return 0
  fi

  warn "macOS $ver: Tahoe+ can block nix login items (they run via /bin/sh) from starting."

  # The BTM store is root-only. Try passwordlessly first, then a plain sudo
  # (security's Touch ID prompts here); degrade gracefully if we can read neither.
  local dump="" blocked=""
  if dump="$(sudo -n sfltool dumpbtm 2>/dev/null)"; then :
  elif dump="$(sudo sfltool dumpbtm 2>/dev/null)"; then :
  else dump=""; fi

  if [ -n "$dump" ]; then
    # The needle has to cover every naming the family's login items use, not
    # just the org.nixos.* one nix-darwin gives an agent by default. pounce
    # carries AssociatedBundleIdentifiers = com.hausfold.pounce (modules/launcher),
    # and that key is precisely what BTM reads to attribute the item — so a
    # nixos-only grep reports "no nix items in the BTM store yet" on a machine
    # where the launcher is the one thing BTM disallowed.
    local stanzas
    stanzas="$(printf '%s\n' "$dump" | grep -A8 -iE 'nixos|hausfold|darwin-store' 2>/dev/null || true)"
    if [ -z "$stanzas" ]; then
      warn "no nix items in the BTM store yet — they appear after the first post-upgrade login."
    elif printf '%s\n' "$stanzas" | grep -qi 'disallowed'; then
      bad "nix background items are DISALLOWED by BTM — that's why daemons won't start."
      blocked=1
    else
      ok "nix background items are allowed by BTM — daemons aren't being gated."
    fi
  else
    warn "couldn't read the BTM store (needs sudo). Inspect it by hand:"
    printf '     sudo sfltool dumpbtm | grep -B2 -A8 -iE "nixos|hausfold|darwin-store"\n'
    blocked=1
  fi

  if [ -n "$blocked" ]; then
    echo
    say "one-time fix (GUI-only — BTM has no CLI to set it):"
    cat <<'EOF'
     1. System Settings → General → Login Items & Extensions
     2. Scroll to "Allow in the Background"
     3. Find the entries named "sh" — subtitle "Item from unidentified developer"
     4. Toggle them ON, then reboot
        (already ON but still blocked? flip OFF then ON to force a DB write)
EOF
  fi
}

# The tour itself is the bar's tour.sh (bar ships it; see modules/bar) —
# haus is just the terminal-shaped door to it, for the user who read the
# bootstrap's closing line instead of spotting the pill.
cmd_tour() {
  local plugin="$HOME/.config/sketchybar/plugins/tour.sh"
  [ -x "$plugin" ] || die "the tour lives in the bar — it needs the bar + windows rooms enabled."
  case "${1:-start}" in
    start) "$plugin" start && say "the tour is in the bar — follow the paw, top right." ;;
    reset) "$plugin" reset && say "tour re-armed — the dormant hint is back in the bar." ;;
    *)     die "unknown tour subcommand '$1' — try: haus tour [start|reset]" ;;
  esac
}

# Sourced, not run: test/haus-plan.sh exercises the parsers above directly (they
# are pure text-and-tree functions, so CI can run them on Linux even though a
# real `haus plan` needs a Mac with a built system). Everything above this line
# is definitions; everything below is the CLI, so stopping here is the whole
# library.
#
# Gated on ACTUALLY BEING SOURCED as well as on the variable, because `return`
# outside a sourced script is a fatal error, not a no-op: keyed on HAUS_LIB
# alone, one exported variable left in a shell would turn every later `haus` in
# it into `can only 'return' from a function or sourced script`, exit 2, with no
# other output. The subshell `return` is the standard probe — it succeeds only
# when this file is being sourced.
if [ -n "${HAUS_LIB:-}" ] && (return 0 2>/dev/null); then return 0; fi

# -v anywhere turns the summary back into the raw stream (same as HAUS_VERBOSE=1).
HAUS_ARGS=()
for a in "$@"; do
  case "$a" in
    -v|--verbose) VERBOSE=1 ;;
    *)            HAUS_ARGS+=("$a") ;;
  esac
done
set -- ${HAUS_ARGS[@]+"${HAUS_ARGS[@]}"}

case "${1:-status}" in
  rebuild)     cmd_rebuild ;;
  update)      cmd_update ;;
  rollback)    cmd_rollback "${2:-}" ;;
  generations) cmd_generations ;;
  status)      cmd_status ;;
  edit)        cmd_edit ;;
  options)     cmd_options "${2:-}" ;;
  set)         shift; cmd_set "$@" ;;
  get)         cmd_get "${2:-}" ;;
  unset)       shift; cmd_unset "$@" ;;
  reset)       shift; cmd_reset "$@" ;;
  plan)        cmd_plan ;;
  diff)        cmd_diff ;;
  capture)     shift; cmd_capture "$@" ;;
  revert-settings) cmd_revert_settings "${2:-latest}" ;;
  doctor)      cmd_doctor ;;
  btm)         cmd_btm ;;
  tour)        cmd_tour "${2:-}" ;;
  -h|--help|help) usage ;;
  *)           die "unknown command '$1' — try: rebuild update rollback generations status edit options set get unset reset plan diff capture revert-settings doctor btm tour" ;;
esac

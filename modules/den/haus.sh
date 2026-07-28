#!/usr/bin/env bash
# haus — the everyday CLI for a nebelhaus machine, so you never memorise the Nix
# incantations. This is the END-USER haus that ships in the rice (den puts it on
# PATH). It drives your OWN machine only — it knows nothing about the workshop
# family repos or agent worktrees (that's the workshop's developer CLI, `bench`).
#
#   haus rebuild        build + switch this machine from your config (the usual day)
#   haus update         pull the latest rice + nebelhaus apps, then rebuild
#   haus rollback [N]    go back a generation (or to generation N)
#   haus generations     list the generations you can roll back to
#   haus status          current generation + how old your pinned rice is
#   haus edit            open your host config (identity, apps) in $EDITOR
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

usage() {
  cat <<'EOF'
haus — the everyday CLI for a nebelhaus machine.

  haus rebuild        build + switch this machine from your config
  haus update         pull the latest rice + nebelhaus apps, then rebuild
  haus rollback [N]   go back a generation (or to generation N)
  haus generations    list the generations you can roll back to
  haus status         current generation + how old your pinned rice is
  haus edit           open your host config in $EDITOR
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

# ---- the agent guard --------------------------------------------------------
# An agent can drive this CLI — that's the point of the nebelhaus skill, and a
# declarative machine is exactly the kind an agent may safely reconfigure: the
# build gates the switch, and a bad switch rolls back atomically.
#
# One config shape breaks that promise. `system.defaults.universalaccess.*` is
# TCC-protected: the write succeeds only if the app RESPONSIBLE for the rebuild
# holds Full Disk Access. nix-darwin emits it unguarded into an activation
# script running under `set -e`, two thirds of the way in — so without the grant
# activation aborts there and skips everything after it, including every launchd
# daemon and agent the rice installs. The machine comes back with no bar, no
# tiling, no palette, and a symptom nowhere near its cause.
#
# The grant belongs to the RESPONSIBLE APP, which is why this tests the
# capability rather than guessing from who's driving: a Claude Code pane running
# inside a terminal that holds Full Disk Access inherits that grant and can
# rebuild perfectly well, while the same agent under Claude.app — or a cloud
# session, or a fresh terminal nobody has granted — cannot. Assuming "agent
# means no access" would refuse rebuilds that were always going to work; testing
# the read means we only ever refuse the combination that actually breaks, and
# hand it back to a human who can run the very same command. Everything else an
# agent asks for goes straight through.

# Claude Code exports CLAUDECODE=1 into the shells it runs.
under_agent() { [ -n "${CLAUDECODE:-}" ]; }

# Full Disk Access, for whichever app is responsible for THIS process. It must
# be a strict read of a protected file: the containing directory lists fine
# without the grant, so an `ls`-shaped test reports success on a machine that
# has no access at all.
has_fda() {
  head -c1 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" >/dev/null 2>&1
}

# The TCC-protected keys this config actually sets, comma-separated (empty when
# there are none). Only ever called on the guard's slow path, since it costs an
# evaluation of the darwin system.
universalaccess_keys() {
  ( cd "$CONSUMER" && nix eval --raw \
      ".#darwinConfigurations.$1.config.system.defaults.universalaccess" \
      --apply 'a: builtins.concatStringsSep ", " (builtins.filter (n: a.${n} != null) (builtins.attrNames a))' \
      2>/dev/null ) || true
}

guard_agent_rebuild() {
  local keys
  under_agent || return 0
  [ -n "${HAUS_AGENT_REBUILD:-}" ] && return 0   # escape hatch: the human said go
  has_fda && return 0                            # this pane can write the domain
  keys="$(universalaccess_keys "$1")"
  [ -n "$keys" ] || return 0

  warn "refusing to rebuild from an agent session."
  cat >&2 <<EOF

  This config sets system.defaults.universalaccess:

      $keys

  macOS only lets an app holding Full Disk Access write that domain, and this
  session doesn't have it. The failure would not be contained: nix-darwin runs
  the write unguarded partway through activation, so it would abort there and
  skip every background service the rice installs — the bar, the tiling, the
  palette.

  Nothing has been changed. Any edit already made is still on disk. Run the
  rebuild yourself, from a terminal that holds Full Disk Access:

      haus rebuild

  For contrast or reduced motion, nebelhaus.accessibility.* reaches the useful
  keys in that domain with a guarded write, and works from anywhere.
  (Really meant it? HAUS_AGENT_REBUILD=1 haus rebuild.)
EOF
  exit 1
}

cmd_rebuild() {
  local host; host="$(host_name)"
  guard_agent_rebuild "$host"
  say "building $host from $CONSUMER …"
  # Build first, switch second: a failed build never touches a running system.
  ( cd "$CONSUMER" && heal nix build ".#darwinConfigurations.$host.system" ) \
    || die "build failed — nothing was changed."
  say "switching …"
  # Stable /run/current-system path (not ./result): collar's passwordless-sudo
  # rule matches that literal path — sudo no longer follows the command symlink.
  ( cd "$CONSUMER" && heal sudo /run/current-system/sw/bin/darwin-rebuild switch --flake ".#$host" )
  say "the house stands."
}

# Family apps (trill, pounce…) ship as CI-published casks/formulae in
# nebelhaus/tap, released on their OWN cadence — a rice flake bump never carries
# them. Worse, activation's `brew bundle` leans on Homebrew's auto-update, which
# is THROTTLED: a rebuild can run against a stale tap clone and never see a fresh
# release (the "released but not installed" trap). So do an explicit, unthrottled
# `brew update` + a targeted upgrade of just the nebelhaus/tap packages here —
# third-party casks keep whatever upgrade policy the host set (autoUpdate/upgrade).
refresh_family_apps() {
  command -v brew >/dev/null 2>&1 || return 0
  local tap; tap="$(brew --repository 2>/dev/null)/Library/Taps/nebelhaus/homebrew-tap"
  [ -d "$tap" ] || return 0
  say "refreshing nebelhaus apps (trill, pounce …) …"
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

cmd_update() {
  local old new owner repo subjects
  old="$(jq -r '.nodes.nebelhaus.locked.rev // ""' "$CONSUMER/flake.lock" 2>/dev/null || true)"
  say "pulling the latest nebelhaus rice …"
  ( cd "$CONSUMER" && heal nix flake update nebelhaus )
  new="$(jq -r '.nodes.nebelhaus.locked.rev // ""' "$CONSUMER/flake.lock" 2>/dev/null || true)"
  if [ -n "$old" ] && [ "$old" = "$new" ]; then
    say "already at the latest rice (${new:0:12}) — rebuilding anyway."
  elif [ -n "$old" ] && [ -n "$new" ]; then
    # Show what's about to land. Best-effort via the GitHub compare API —
    # offline, rate-limited, or non-GitHub upstreams just skip the list.
    owner="$(jq -r '.nodes.nebelhaus.original.owner // "nebelhaus"' "$CONSUMER/flake.lock")"
    repo="$(jq -r '.nodes.nebelhaus.original.repo // "nebelhaus"' "$CONSUMER/flake.lock")"
    subjects="$(curl -fsSL --max-time 5 \
      -H 'accept: application/vnd.github+json' \
      "https://api.github.com/repos/$owner/$repo/compare/$old...$new" 2>/dev/null \
      | jq -r '.commits[]?.commit.message | split("\n")[0]' 2>/dev/null | head -15 || true)"
    if [ -n "$subjects" ]; then
      say "new in the rice (${old:0:7} → ${new:0:7}):"
      printf '%s\n' "$subjects" | sed 's/^/  · /'
    fi
  fi
  refresh_family_apps
  cmd_rebuild
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
  say "pinned nebelhaus rice"
  if [ -f "$CONSUMER/flake.lock" ]; then
    lockrev="$(jq -r '.nodes.nebelhaus.locked.rev // "?"' "$CONSUMER/flake.lock")"
    lockdate="$(jq -r '.nodes.nebelhaus.locked.lastModified // 0' "$CONSUMER/flake.lock")"
    if [ "$lockdate" != "0" ]; then
      printf '  %s  (%s)\n' "${lockrev:0:12}" "$(date -r "$lockdate" '+%Y-%m-%d' 2>/dev/null || echo '?')"
    else
      printf '  %s\n' "${lockrev:0:12}"
    fi
    # Is the upstream rice ahead of what you've pinned? Best-effort, offline-safe.
    owner="$(jq -r '.nodes.nebelhaus.original.owner // "nebelhaus"' "$CONSUMER/flake.lock")"
    repo="$(jq -r '.nodes.nebelhaus.original.repo // "nebelhaus"' "$CONSUMER/flake.lock")"
    ref="$(jq -r '.nodes.nebelhaus.original.ref // "HEAD"' "$CONSUMER/flake.lock")"
    url="https://github.com/$owner/$repo.git"
    remoterev="$(git ls-remote "$url" "$ref" 2>/dev/null | awk 'NR==1{print $1}')"
    if [ -n "$remoterev" ] && [ "$remoterev" != "$lockrev" ]; then
      warn "  a newer rice is available upstream (${remoterev:0:12}) — haus update"
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

cmd_doctor() {
  local uid; uid="$(id -u)"
  say "nebelhaus doctor"

  # On macOS 26 Tahoe+, a "stopped agent" is often BTM gating the /bin/sh-invoked
  # nix login item rather than a cold-boot wedge — point at `haus btm` when so.
  local osver osmajor btmhint=""
  osver="$(sw_vers -productVersion 2>/dev/null || echo 0)"; osmajor="${osver%%.*}"
  [ "${osmajor:-0}" -ge 26 ] && btmhint=" · on Tahoe+ this is often BTM: haus btm"

  # Determinate Nix (den assumes it owns the daemon: nix.enable = false).
  if [ -f /nix/receipt.json ]; then ok "Determinate Nix installed"
  elif [ -d /nix ]; then bad "/nix exists but not Determinate — nebelhaus expects the Determinate installer"
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
  for pair in "org.nixos.aerospace:AeroSpace" "org.nixos.sketchybar:sketchybar" "org.nixos.pounce:pounce"; do
    label="${pair%%:*}"; name="${pair##*:}"
    if launchctl print "gui/$uid/$label" >/dev/null 2>&1; then
      if pgrep -qx "$name"; then ok "$name running"
      else bad "$name enabled but not running — check /tmp/$name.err.log (a wedged cold-boot agent: launchctl kickstart -k gui/$uid/$label)$btmhint"; fi
    fi
  done

  # Accessibility grant — pounce's auto-paste and emoji insertion need it, and a
  # missing grant is the #1 "why won't paste work" gotcha. Only meaningful when
  # pounce is enabled (its launchd plist exists).
  if launchctl print "gui/$uid/org.nixos.pounce" >/dev/null 2>&1; then
    echo
    say "Accessibility"
    if command -v pounce >/dev/null 2>&1 && [ "$(pounce --check-accessibility 2>/dev/null)" = "true" ]; then
      ok "pounce has Accessibility (auto-paste + emoji work)"
    else
      bad "pounce is missing Accessibility — grant once: pounce --request-accessibility"
    fi
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

  # Agents — whether an AI agent can usefully and safely drive this machine.
  # Three separate questions, all of which have bitten someone: does it have the
  # knowledge (the skill), does the config repo orient it (a CLAUDE.md), and can
  # a rebuild from an agent pane actually complete (Full Disk Access vs the
  # universalaccess trap that `haus rebuild` guards).
  echo
  say "Agents"
  local skilldir="$HOME/.claude/skills/nebelhaus"
  if [ -f "$skilldir/SKILL.md" ]; then
    ok "the nebelhaus skill is installed ($skilldir)"
  else
    info "no nebelhaus skill — set nebelhaus.claude.skill = true to let an agent change this machine"
  fi
  if [ -f "$CONSUMER/CLAUDE.md" ]; then
    ok "$CONSUMER/CLAUDE.md orients an agent opened there"
  elif [ -f "$skilldir/consumer-CLAUDE.md" ]; then
    info "no CLAUDE.md in your config — start from the rice's: cp $skilldir/consumer-CLAUDE.md $CONSUMER/CLAUDE.md"
  fi
  # Reported for the app running THIS command — the grant is per-app, so the
  # answer legitimately differs between your terminal and an agent's pane.
  if has_fda; then
    ok "this app has Full Disk Access (system.defaults.universalaccess.* can be written from here)"
  else
    info "this app has no Full Disk Access — system.defaults.universalaccess.* can't be written from here, and 'haus rebuild' will refuse rather than half-activate (nebelhaus.accessibility.* is the safe route)"
  fi

  # Secrets — the declaration (secretspec.toml) rebuilds with Nix, but the
  # VALUES live in the provider and may need entering once per machine.
  echo
  say "Secrets"
  if command -v secretspec >/dev/null 2>&1; then
    local provider
    provider="$(sed -n 's/^provider *= *"\(.*\)"/\1/p' "$HOME/.config/secretspec/config.toml" 2>/dev/null | head -1)"
    if [ -n "$provider" ]; then ok "secretspec on PATH (default provider: $provider)"
    else warn "no default provider — set nebelhaus.secrets.provider, or run: secretspec config init"; fi
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
  # (collar's Touch ID prompts here); degrade gracefully if we can read neither.
  local dump="" blocked=""
  if dump="$(sudo -n sfltool dumpbtm 2>/dev/null)"; then :
  elif dump="$(sudo sfltool dumpbtm 2>/dev/null)"; then :
  else dump=""; fi

  if [ -n "$dump" ]; then
    local stanzas
    stanzas="$(printf '%s\n' "$dump" | grep -A8 -iE 'nixos|darwin-store' 2>/dev/null || true)"
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
    printf '     sudo sfltool dumpbtm | grep -B2 -A8 -iE "nixos|darwin-store"\n'
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

# The tour itself is the bar's tour.sh (sill ships it; see modules/sill) —
# haus is just the terminal-shaped door to it, for the user who read the
# bootstrap's closing line instead of spotting the pill.
cmd_tour() {
  local plugin="$HOME/.config/sketchybar/plugins/tour.sh"
  [ -x "$plugin" ] || die "the tour lives in the bar — it needs the sill + prowl rooms enabled."
  case "${1:-start}" in
    start) "$plugin" start && say "the tour is in the bar — follow the paw, top right." ;;
    reset) "$plugin" reset && say "tour re-armed — the dormant hint is back in the bar." ;;
    *)     die "unknown tour subcommand '$1' — try: haus tour [start|reset]" ;;
  esac
}

case "${1:-status}" in
  rebuild)     cmd_rebuild ;;
  update)      cmd_update ;;
  rollback)    cmd_rollback "${2:-}" ;;
  generations) cmd_generations ;;
  status)      cmd_status ;;
  edit)        cmd_edit ;;
  doctor)      cmd_doctor ;;
  btm)         cmd_btm ;;
  tour)        cmd_tour "${2:-}" ;;
  -h|--help|help) usage ;;
  *)           die "unknown command '$1' — try: rebuild update rollback generations status edit doctor btm tour" ;;
esac

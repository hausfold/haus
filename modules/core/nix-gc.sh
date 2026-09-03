#!/usr/bin/env bash
# haus-nix-gc — the weekly store cleanup, and the one macOS refusal it has to
# survive.
#
# THE BUG THIS EXISTS FOR. `nix-collect-garbage` deletes a store path by making
# it writable first, and macOS refuses that chmod on an app bundle the user has
# actually launched. Root is refused. The nix daemon is refused:
#
#   error: chmod ".../orbstack-2.2.1-20628/Applications/OrbStack.app": Operation not permitted
#
# ONE refusal aborts the WHOLE collection: every path nix had not reached yet
# stays until next week, and next week it dies on the same bundle at the same
# point. The machine this was written on has eight runs on record and THREE of
# them aborted, on a different app each time — KeyCastr, then OrbStack, then
# tart. The five that finished freed 20 to 72 GiB apiece; the aborted ones
# stopped at 8.2 GiB and 2.6. So what is lost is a week's garbage at a time
# rather than the whole store, and it recurs for as long as any launched
# bundle is sitting in the collection's path, which is indefinitely.
#
# It is also invisible. The failure is one line at the end of a log nobody
# reads, and a weekly job that quietly stopped finishing looks exactly like one
# that simply is not Sunday.
#
# WHAT THIS DOES INSTEAD. Run the collection; when it dies on a path macOS will
# not let go of, PIN that path as a GC root and go round again. A pinned path
# is live by definition, so nix stops trying to delete it and gets on with the
# rest of the store. The cost is that path AND ITS CLOSURE staying on disk — a
# root roots everything reachable from it — but only DEAD paths ever get here,
# since a launched app's current version is live and was never a collection
# candidate. Six of the 216 app bundles in this store carry the stamp; the
# superseded copies among those are all this can ever pin.
#
# WHY IT UNPINS FIRST, EVERY RUN. The pins work around a permission state that
# can change: the user grants App Management, macOS drops the stamp, the app
# leaves /Applications. So each run clears every pin it owns and lets the
# collection re-discover what is still stuck. Nothing accumulates, and the day
# the permission changes the space comes back on its own, with no verb for
# anyone to remember. It also means the pin set is never read as history — what
# is in that directory is what failed THIS week.
#
# WHY IT TRIES TO UNSTICK BEFORE PINNING. `com.apple.macl` is the stamp macOS
# writes when a user grants an app access to something, and it is the one thing
# these paths carry that the other 210 app bundles in this store do not.
# Whether root may strip it is version-dependent and undocumented, so this
# tries exactly once per path and the log says which way it went. A pin is the
# fallback, not the plan — and the path is garbage by the time we touch it, so
# clearing its attributes can cost nothing that was still wanted.
#
# WHY THE OUTPUT IS SUMMARISED. A stuck store turns one weekly collection into
# a dozen, each printing every path it deleted, into a log nothing rotates.
# That log was already 3.9 MB of `deleting '...'` before this wrapper existed.
# So each attempt's chatter goes to a temp file and only its verdict — one line
# per attempt, plus what got pinned — reaches the daemon's log.
#
# NOT A `haus` VERB, and no option gates it. There is nothing here for a person
# to run: the schedule is the feature and the pins are self-clearing.
#
# THE MISSING HALF, deliberately missing. Nothing reads the pin directory yet —
# not doctor, not the manual-click deck — so a pinned path is invisible until
# somebody opens this log. The card that would belong in
# `haus._contrib.permissions` is the App Management grant, and it is not
# written because nobody has yet confirmed that granting it to anything frees
# these paths: the collector is a root LaunchDaemon whose binary is a store
# path that moves on every rebuild, which is the worst possible subject for a
# TCC grant keyed on an executable. A deck card whose click does nothing is
# worse than no card, so this stays a log line until the grant is measured
# against a real stuck path.

set -uo pipefail

gc_bin=${HAUS_NIX_GC_BIN:-/nix/var/nix/profiles/default/bin/nix-collect-garbage}
roots_dir=${HAUS_NIX_GC_ROOTS:-/nix/var/nix/gcroots/haus-stuck}
xattr_bin=${HAUS_NIX_GC_XATTR:-/usr/bin/xattr}
# Two attempts per stuck path (strip, then pin) plus the one that succeeds.
# Forty is far past any plausible number of launched app bundles and still
# bounded, which is the only property that matters: the loop's exit condition
# is "nix stopped complaining", and a wrapper that trusted that alone would
# spin forever the first time nix reported a refusal it did not name a path in.
max_attempts=${HAUS_NIX_GC_MAX_ATTEMPTS:-40}
age=${1:-30d}

log() { printf '%s\n' "$*"; }

# The store path an error line choked on, trimmed to its top level. nix names
# the FILE it could not chmod (.../Applications/Foo.app); what has to be pinned
# is the store path that contains it, because that is the unit nix collects.
stuck_path() {
  line=$(grep -a 'Operation not permitted' "$1" | tail -n 1)
  [ -n "$line" ] || return 1
  # nix quotes with " here and with ' elsewhere; take whichever matched first.
  path=$(printf '%s\n' "$line" |
    sed -n -e 's|.*"\(/nix/store/[^"]*\)".*|\1|p' \
      -e "s|.*'\\(/nix/store/[^']*\\)'.*|\\1|p" |
    head -n 1)
  [ -n "$path" ] || return 1
  path=${path#/nix/store/}
  top=${path%%/*}
  # Only a real store path is pinnable. /nix/store/trash is nix's own staging
  # directory — a root pointing into it is a root nix cannot resolve, and would
  # turn a survivable failure into a broken store.
  [[ $top =~ ^[0-9a-z]{32}- ]] || return 1
  printf '/nix/store/%s\n' "$top"
}

# Membership in one of the newline-separated lists this keeps. An array would
# want bash 4; the store paths in play here cannot contain a newline.
listed() { printf '%s\n' "$2" | grep -Fxq "$1"; }

pin() { ln -sfn "$1" "$roots_dir/${1#/nix/store/}"; }

if ! mkdir -p "$roots_dir"; then
  log "cannot write $roots_dir — nothing can be pinned, so a stuck path would abort the collection"
  exit 1
fi

unpinned=0
for link in "$roots_dir"/*; do
  [ -L "$link" ] || continue
  rm -f "$link" && unpinned=$((unpinned + 1))
done
[ "$unpinned" -gt 0 ] && log "cleared $unpinned pin(s) from the last run — re-testing them"

out=$(mktemp "${TMPDIR:-/tmp}/haus-nix-gc.XXXXXX") || exit 1
trap 'rm -f "$out"' EXIT

tried=""
pinned=""
attempt=0
status=0

while :; do
  attempt=$((attempt + 1))
  if [ "$attempt" -gt "$max_attempts" ]; then
    log "gave up after $max_attempts attempts — the store is not settling"
    status=1
    break
  fi

  "$gc_bin" --delete-older-than "$age" >"$out" 2>&1
  status=$?
  total=$(grep -a 'store paths deleted' "$out" | tail -n 1)
  log "attempt $attempt: ${total:-collection reported no total}"
  [ "$status" -eq 0 ] && break

  if ! path=$(stuck_path "$out"); then
    log "collection failed for a reason this wrapper does not handle:"
    grep -a '^error:' "$out" | tail -n 5
    break
  fi

  # One strip attempt per path, then a pin. Both, in that order, because the
  # strip is the one that actually reclaims the disk when it works.
  if ! listed "$path" "$tried"; then
    tried="$tried
$path"
    if "$xattr_bin" -c -r "$path" 2>/dev/null; then
      # `xattr` can exit 0 without having removed a protected attribute, so this
      # says what was attempted, not what was achieved. A path that comes back
      # is already in $tried and gets pinned on the next pass.
      log "  tried clearing the extended attributes on $path — retrying it"
      continue
    fi
    log "  macOS will not let go of $path, and refused to drop its attributes"
  fi

  if ! pin "$path"; then
    log "could not pin $path — the collection cannot get past it"
    status=1
    break
  fi
  # Only once. A path re-appearing after it was pinned means the pin did not
  # take, and the summary must not read as two stuck paths when it is one.
  listed "$path" "$pinned" || pinned="$pinned
$path"
done

if [ -n "$pinned" ]; then
  log "pinned as un-collectable; these and their closures stay on disk until"
  log "macOS stops protecting them. Re-tested at the start of the next run."
  printf '%s\n' "$pinned" | sed '/^$/d; s|^|  |'
fi

exit "$status"

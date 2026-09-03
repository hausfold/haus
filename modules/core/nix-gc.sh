#!/usr/bin/env bash
# haus-nix-gc — the weekly store cleanup, and the one macOS refusal it has to
# survive.
#
# THE BUG THIS EXISTS FOR. `nix-collect-garbage` deletes a store path by making
# it writable first, and macOS refuses that chmod on an app bundle the user has
# launched. Root is refused. The nix daemon is refused:
#
#   error: chmod ".../orbstack-2.2.1-20628/Applications/OrbStack.app": Operation not permitted
#
# ONE refusal aborts the WHOLE collection: every path nix had not reached yet
# stays until next week, and next week it dies on the same bundle at the same
# point. The machine this was written on has eight runs on record and THREE of
# them aborted, on a different app each time — KeyCastr, then OrbStack, then
# tart. The five that finished freed 20 to 72 GiB apiece; the aborted ones
# stopped at 8.2 GiB and 2.6.
#
# It is also invisible. The failure is one line at the end of a log nobody
# reads, and a weekly job that quietly stopped finishing looks exactly like one
# that simply is not Sunday.
#
# WHAT MAKES A PATH STICK, measured rather than guessed. The gate is macOS's
# App Management (`kTCCServiceSystemPolicyAppBundles`), and it is scoped to the
# process RESPONSIBLE for the work, not to the uid: on this machine Ghostty
# holds the grant, and `sudo nix-store --delete` from a Ghostty pane removed a
# bundle this daemon had been refused minutes earlier. A LaunchDaemon has no
# responsible app and therefore no grant, and cannot usefully be given one —
# TCC keys a non-app grant on the executable's path, and this daemon's is a
# store path that moves on every rebuild.
#
# WHY THE PINS GO IN BEFORE THE COLLECTION, WHICH IS THE WHOLE DESIGN. The
# obvious shape — run it, see what it chokes on, pin that, go round again —
# does not work, and it fails in a way worth writing down because it looks like
# it does. `deleteFromStore` INVALIDATES a path's database entry and then
# deletes the files, in that order. So a refused delete leaves a directory the
# store no longer knows about, and nix says so if you try to root it:
#
#   skipping invalid root from '/nix/var/nix/gcroots/…' to '/nix/store/…'
#
# A GC root has to point at a VALID path. Pin one after the fact and you have
# pinned nothing: the next pass tries the same directory again, and the loop
# burns forty full collections discovering that. So this pins FIRST. It scans
# the store for app bundles carrying `com.apple.macl` — the stamp macOS writes
# when a user grants an app access, and the one thing the failures had that the
# other 169 bundles in this store did not — and roots each one that is still
# valid before nix is ever asked to delete it. The collection then skips them
# and finishes in a single pass.
#
# THE REACTIVE LOOP IS THE SAFETY NET, not the plan. `com.apple.macl` is a
# predicate that fits every refusal seen so far, not a documented contract, so
# whatever the scan misses is still pinned and retried. What it cannot do is
# rescue a path that is ALREADY invalid — an orphan left by a run from before
# this wrapper existed. Those are moved out of the store instead, which is the
# one thing that stops nix reconsidering them every week.
#
# WHY IT UNPINS FIRST, EVERY RUN. The pins work around a permission state that
# can change: the user grants App Management, macOS drops the stamp, the app
# leaves /Applications. So each run clears every pin it owns and re-derives the
# set from the store as it is today. Nothing accumulates, and the day a bundle
# stops being protected its path is collected with everything else.
#
# WHY THE OUTPUT IS SUMMARISED. A stuck store turns one weekly collection into
# several, each printing every path it deleted, into a log nothing rotates.
# That log was already 3.9 MB of `deleting '...'` before this wrapper existed.
# So each attempt's chatter goes to a temp file and only its verdict — one line
# per attempt, plus what got pinned — reaches the daemon's log.
#
# NOT A `haus` VERB, and no option gates it. There is nothing here for a person
# to run: the schedule is the feature and the pins are self-clearing. The one
# thing a person can do that this cannot is delete a pinned path, from a
# terminal that holds App Management — `nix-store --delete` ignores GC roots,
# so a pin never puts a path out of their reach. Nothing reads the pin
# directory yet, not doctor and not the manual-click deck, so until something
# does, this log is where a pinned path is visible.

set -uo pipefail

gc_bin=${HAUS_NIX_GC_BIN:-/nix/var/nix/profiles/default/bin/nix-collect-garbage}
store_bin=${HAUS_NIX_STORE_BIN:-/nix/var/nix/profiles/default/bin/nix-store}
store_dir=${HAUS_NIX_STORE_DIR:-/nix/store}
roots_dir=${HAUS_NIX_GC_ROOTS:-/nix/var/nix/gcroots/haus-stuck}
orphan_dir=${HAUS_NIX_GC_ORPHANS:-/nix/var/nix/haus-stuck-orphans}
xattr_bin=${HAUS_NIX_GC_XATTR:-/usr/bin/xattr}
# Two attempts per stuck path the pre-pin scan missed, plus the one that
# succeeds. Forty is far past any plausible number and still bounded, which is
# the only property that matters: the loop's exit condition is "nix stopped
# complaining", and a wrapper that trusted that alone would spin forever the
# first time nix reported a refusal it did not name a path in.
max_attempts=${HAUS_NIX_GC_MAX_ATTEMPTS:-40}
age=${1:-30d}

log() { printf '%s\n' "$*"; }

# Is this a path the store still knows about? Only a valid path can be rooted.
valid_path() { "$store_bin" --query --hash "$1" >/dev/null 2>&1; }

# /nix/store/<hash>-<name>/a/b -> /nix/store/<hash>-<name>, or nothing if the
# first component is not a store path. /nix/store/trash is nix's own staging
# directory — a root pointing into it is a root nix cannot resolve, and would
# turn a survivable failure into a broken store.
top_level() {
  rest=${1#"$store_dir"/}
  top=${rest%%/*}
  [[ $top =~ ^[0-9a-z]{32}- ]] || return 1
  printf '%s/%s\n' "$store_dir" "$top"
}

# The store path an error line choked on. nix names the FILE it could not chmod
# (.../Applications/Foo.app); what has to be pinned is the store path that
# contains it, because that is the unit nix collects.
stuck_path() {
  line=$(grep -a 'Operation not permitted' "$1" | tail -n 1)
  [ -n "$line" ] || return 1
  # nix quotes with " here and with ' elsewhere; take whichever matched first.
  path=$(printf '%s\n' "$line" |
    sed -n -e "s|.*\"\\($store_dir/[^\"]*\\)\".*|\\1|p" \
      -e "s|.*'\\($store_dir/[^']*\\)'.*|\\1|p" |
    head -n 1)
  [ -n "$path" ] || return 1
  top_level "$path"
}

listed() { printf '%s\n' "$2" | grep -Fxq "$1"; }

pin() { ln -sfn "$1" "$roots_dir/${1#"$store_dir"/}"; }

if ! mkdir -p "$roots_dir"; then
  log "cannot write $roots_dir — nothing can be pinned, so a stuck path would abort the collection"
  exit 1
fi

unpinned=0
for link in "$roots_dir"/*; do
  [ -L "$link" ] || continue
  rm -f "$link" && unpinned=$((unpinned + 1))
done
[ "$unpinned" -gt 0 ] && log "cleared $unpinned pin(s) from the last run — re-deriving from the store"

# ---- the pre-pin scan -------------------------------------------------------
# Every app bundle macOS has stamped, rooted before the collection can reach it.
# The `find` over the whole store costs about a second and a half here.
pinned=""
prepinned=0
while IFS= read -r app; do
  "$xattr_bin" "$app" 2>/dev/null | grep -qx 'com.apple.macl' || continue
  sp=$(top_level "$app") || continue
  listed "$sp" "$pinned" && continue
  valid_path "$sp" || continue
  if pin "$sp"; then
    pinned="$pinned
$sp"
    prepinned=$((prepinned + 1))
  fi
done < <(find "$store_dir" -maxdepth 4 -name '*.app' -type d 2>/dev/null)
[ "$prepinned" -gt 0 ] && log "pinned $prepinned stamped app bundle(s) before collecting"

out=$(mktemp "${TMPDIR:-/tmp}/haus-nix-gc.XXXXXX") || exit 1
trap 'rm -f "$out"' EXIT

tried=""
moved=""
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

  # One strip attempt per path, first, because it is the only branch that
  # actually reclaims the disk. `xattr` can exit 0 without having removed a
  # protected attribute, so this says what was attempted, not what was
  # achieved; a path that comes back is already in $tried and falls through.
  if ! listed "$path" "$tried"; then
    tried="$tried
$path"
    if "$xattr_bin" -c -r "$path" 2>/dev/null; then
      log "  tried clearing the extended attributes on $path — retrying it"
      continue
    fi
    log "  macOS will not let go of $path, and refused to drop its attributes"
  fi

  if valid_path "$path"; then
    if ! pin "$path"; then
      log "  could not pin $path — the collection cannot get past it"
      status=1
      break
    fi
    listed "$path" "$pinned" || pinned="$pinned
$path"
    continue
  fi

  # An orphan: nix invalidated it before a delete that then failed, so it is a
  # directory the store no longer knows about, and a root pointing at it is
  # skipped as invalid. Pinning cannot help. Getting it out of the store is the
  # only thing that stops every future collection reconsidering it, and the
  # rename touches the store directory rather than the protected bundle inside
  # it, which is why it can succeed where the delete could not.
  if mkdir -p "$orphan_dir" && mv "$path" "$orphan_dir/"; then
    log "  moved $path aside — it was already invalid, so nothing could root it"
    moved="$moved
$path"
    continue
  fi
  log "  $path is no longer a valid store path and could not be moved aside."
  log "  Nothing here can pin it or delete it. From a terminal that holds App"
  log "  Management: sudo rm -rf $path"
  status=1
  break
done

if [ -n "$pinned" ]; then
  log "pinned as un-collectable; these and their closures stay on disk until"
  log "macOS stops protecting them. Re-derived at the start of the next run:"
  printf '%s\n' "$pinned" | sed '/^$/d; s|^|  |'
fi

if [ -n "$moved" ]; then
  log "moved out of the store into $orphan_dir. Delete that directory from a"
  log "terminal that holds App Management to get the disk back:"
  printf '%s\n' "$moved" | sed '/^$/d; s|^|  |'
fi

exit "$status"

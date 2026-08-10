#!/usr/bin/env bash
# What `haus plan` can actually SEE — the regression suite for the day it
# reported "nothing was changed" about a rebuild that was about to add seven
# pills to the bar. Two blind spots caused that: plan reads $CONSUMER while the
# edit sat in a linked worktree of it, and its only file-level oracle was `nix
# store diff-closures`, which never reports a same-name store path whose size
# barely moved (the whole home-files tree moved 272 bytes).
#
# Everything exercised here is pure text-and-tree parsing, so this runs on
# LINUX in CI even though a real `haus plan` needs a Mac with a built system.
# The fixtures are hand-written activation scripts in exactly the shape
# nix-darwin and home-manager generate — which is the point: the parsers are
# supposed to read the built artifact rather than a hand-kept table, so the
# thing worth pinning is that they still read that shape correctly.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
# Physical path: on macOS mktemp hands back /var/folders/… while git reports
# /private/var/folders/…, and every comparison below would be against two
# spellings of one directory.
tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
has() { printf '%s\n' "$2" | grep -qF -- "$1" || fail "expected to find: $1"; }
lacks() { printf '%s\n' "$2" | grep -qF -- "$1" && fail "expected NOT to find: $1"; return 0; }

# haus.sh refuses to load without a config flake, and HAUS_LIB stops it before
# the CLI dispatch so the library alone is in scope.
mkdir -p "$tmp/consumer"
printf '{ }\n' >"$tmp/consumer/flake.nix"
export HAUS_CONSUMER="$tmp/consumer" HAUS_LIB=1
# shellcheck disable=SC1090,SC1091
source "$repo/modules/den/haus.sh"

# ---- fixtures ----------------------------------------------------------------
# Store paths are matched by SHAPE (a 32-char hash plus a known suffix), not by
# a /nix/store prefix, which is exactly what lets this run hermetically.
h_new_gen=aaaaaaaaaaaaaaaaaaaaaaaaaaaa0001
h_old_gen=aaaaaaaaaaaaaaaaaaaaaaaaaaaa0002
h_new_act=aaaaaaaaaaaaaaaaaaaaaaaaaaaa0003
h_old_act=aaaaaaaaaaaaaaaaaaaaaaaaaaaa0004
store="$tmp/store"
newgen="$store/$h_new_gen-home-manager-generation"
oldgen="$store/$h_old_gen-home-manager-generation"
mkdir -p "$store" "$newgen/home-files" "$oldgen/home-files"

# Content-addressed leaves the trees symlink at, the way home-manager links
# every managed file into the store.
for f in newitems olditems newstamp oldstamp keep added gone; do
  printf '%s\n' "$f" >"$store/$f"
done

mkdir -p "$newgen/home-files/.config/bar" "$oldgen/home-files/.config/bar"
ln -s "$store/newitems" "$newgen/home-files/.config/bar/items.sh"
ln -s "$store/olditems" "$oldgen/home-files/.config/bar/items.sh"
ln -s "$store/newstamp" "$newgen/home-files/.config/bar/.stamp"
ln -s "$store/oldstamp" "$oldgen/home-files/.config/bar/.stamp"
ln -s "$store/keep" "$newgen/home-files/.config/keep.txt"
ln -s "$store/keep" "$oldgen/home-files/.config/keep.txt"
ln -s "$store/added" "$newgen/home-files/.config/added.sh"
ln -s "$store/gone" "$oldgen/home-files/.config/gone.sh"
# One REAL file on each side, differing — the entries `home.file` produces that
# aren't symlinks, and the only reason hash_file exists.
printf 'after\n' >"$newgen/home-files/real.txt"
printf 'before\n' >"$oldgen/home-files/real.txt"

# home-manager's activation script: a `_cmp` line that COMPUTES changedFiles for
# the stamp, then the hook keyed on the same subscript. Both are in the fixture
# on purpose — matching the first would print the comparison, not the hook.
cat >"$newgen/activate" <<'EOF'
_iNote "Activating %s" "checkLinkTargets"
_cmp /nix/store/cccccccccccccccccccccccccccc0001-hm_stamp /home/fakeuser/.config/bar/.stamp \
  && changedFiles[.config/bar/.stamp]=0 \
  || changedFiles[.config/bar/.stamp]=1
_iNote "Activating %s" "onFilesChange"
if (( ${changedFiles[.config/bar/.stamp]} == 1 )); then
  if [[ -v DRY_RUN || -v VERBOSE ]]; then
    echo "Running onChange hook for" .config/bar/.stamp
  fi
  if [[ ! -v DRY_RUN ]]; then
    /nix/store/cccccccccccccccccccccccccccc0002-bar/bin/bar --reload 2>/dev/null || true
  fi
fi
if (( ${changedFiles[.config/never.conf]} == 1 )); then
  if [[ -v DRY_RUN || -v VERBOSE ]]; then
    echo "Running onChange hook for" .config/never.conf
  fi
  if [[ ! -v DRY_RUN ]]; then
    /nix/store/cccccccccccccccccccccccccccc0003-other/bin/other reload || true
  fi
fi
if (( ${changedFiles[real.txt]} == 1 )); then
  if [[ -v DRY_RUN || -v VERBOSE ]]; then
    echo "Running onChange hook for" real.txt
  fi
  if [[ ! -v DRY_RUN ]]; then
    run /nix/store/cccccccccccccccccccccccccccc0004-rsync/bin/rsync $VERBOSE_ARG -acL \
      --delete \
      /nix/store/cccccccccccccccccccccccccccc0005-src/ \
      /home/fakeuser/dst
  fi
fi
EOF
cp "$newgen/activate" "$oldgen/activate"

# The per-user wrapper nix-darwin puts between its activate script and
# home-manager's, and which is the only place the USER is named.
printf 'exec %s/activate --driver-version 1 >&2\n' "$newgen" >"$store/$h_new_act-activation-fakeuser"
printf 'exec %s/activate --driver-version 1 >&2\n' "$oldgen" >"$store/$h_old_act-activation-fakeuser"

# ---- launchd fixtures --------------------------------------------------------
mkdir -p "$tmp/installed"
printf 'same\n' >"$store/job-same.plist"
printf 'same\n' >"$tmp/installed/job-same.plist"
printf 'new-body\n' >"$store/job-moved.plist"
printf 'old-body\n' >"$tmp/installed/job-moved.plist"
printf 'fresh\n' >"$store/job-fresh.plist" # nothing installed → create
printf 'dropped\n' >"$store/job-dropped.plist"
printf 'dropped\n' >"$tmp/installed/job-dropped.plist"

# The darwin activate scripts themselves: the launchd guards, the restart-map
# calls den renders, and the hop to the per-user wrapper.
{
  printf 'if ! diff %s/job-same.plist %s/installed/job-same.plist &> /dev/null; then\n' "$store" "$tmp"
  printf 'fi\n'
  printf "if ! diff '%s/job-moved.plist' '%s/installed/job-moved.plist' &> /dev/null; then\n" "$store" "$tmp"
  printf 'fi\n'
  printf "if ! diff '%s/job-fresh.plist' '%s/installed/job-fresh.plist' &> /dev/null; then\n" "$store" "$tmp"
  printf 'fi\n'
  printf 'killall -qu fakeuser Finder || true\n'
  printf 'killall -qu fakeuser SystemUIServer || true\n'
  printf 'if [ -x "$activateSettings" ]; then\n'
  printf '  "$activateSettings" -u || true\n'
  printf 'fi\n'
  printf "hausax post-notification 'AppleDatePreferencesChangedNotification' || true\n"
  printf 'launchctl asuser "$(id -u fakeuser)" sudo -u fakeuser --set-home %s\n' \
    "$store/$h_new_act-activation-fakeuser"
} >"$tmp/new-activate"
{
  printf 'if ! diff %s/job-same.plist %s/installed/job-same.plist &> /dev/null; then\n' "$store" "$tmp"
  printf 'fi\n'
  printf "if ! diff '%s/job-dropped.plist' '%s/installed/job-dropped.plist' &> /dev/null; then\n" "$store" "$tmp"
  printf 'fi\n'
  printf 'launchctl asuser "$(id -u fakeuser)" sudo -u fakeuser --set-home %s\n' \
    "$store/$h_old_act-activation-fakeuser"
} >"$tmp/old-activate"

# ---- the generation chain ----------------------------------------------------
gens="$(hm_generations "$tmp/new-activate")"
test "$gens" = "$(printf 'fakeuser\t%s' "$newgen")" \
  || fail "hm_generations followed the wrong chain: $gens"
test -z "$(hm_generations "$tmp/installed/job-same.plist")" \
  || fail "hm_generations invented a generation from a file with no wrapper in it"

# ---- the file diff -----------------------------------------------------------
out="$(plan_files "$tmp/new-activate" "$tmp/old-activate")"
has '~ .config/bar/items.sh' "$out"
has '~ .config/bar/.stamp' "$out"
has '~ real.txt' "$out"          # a real file, compared by content hash
has '+ .config/added.sh' "$out"
has '- .config/gone.sh' "$out"
lacks '.config/keep.txt' "$out"  # same store target on both sides
has '3 changed, 1 new, 1 removed' "$out"

# The hook that makes a change LIVE — reported because its file is in the
# changed set, and reported with the command it will actually run.
has 'onChange: .config/bar/.stamp → bar --reload' "$out"
has '2 onChange hook(s) would fire' "$out"

# A multi-line hook: home-manager's font hook is a `run`-wrapped rsync split
# over four backslash-continued lines, and rendering those as separate commands
# prints half an invocation as though it were the whole hook. The `run` wrapper
# and the store path are both stripped, and the continuation is joined.
has 'onChange: real.txt → rsync $VERBOSE_ARG -acL' "$out"
lacks 'onChange: real.txt → run ' "$out"
# A hook whose file did not change must stay silent, or the section becomes a
# list of every hook the configuration has.
lacks '.config/never.conf' "$out"

# Nothing moved: same generation on both sides.
same="$(plan_files "$tmp/new-activate" "$tmp/new-activate")"
has 'no managed file would change' "$same"
lacks 'onChange' "$same"

# A machine with no home-manager at all is a clean skip, not an error — and the
# message hedges on purpose, because a genuinely absent generation and a chain
# this failed to follow look identical from in here.
printf 'echo nothing here\n' >"$tmp/bare-activate"
bare="$(plan_files "$tmp/bare-activate" "$tmp/old-activate")"
has 'no home-manager generation found in this build' "$bare"
has 'or the activation chain has changed shape' "$bare"

# A first-ever rebuild: the new side has a generation, the running one doesn't.
has 'every managed file would be new' "$(plan_files "$tmp/new-activate" "$tmp/bare-activate")"

# ---- launchd jobs ------------------------------------------------------------
svc="$(plan_services "$tmp/new-activate" "$tmp/old-activate")"
has 'will reload: job-moved' "$svc"
has 'will create: job-fresh' "$svc"
has 'will remove: job-dropped' "$svc"
has '1 other job(s) unchanged' "$svc" # job-same
lacks 'job-same' "${svc/1 other job(s) unchanged/}"

quiet="$(plan_services "$tmp/old-activate" "$tmp/old-activate")"
has 'no launchd job would change' "$quiet"

# The failure that must NEVER read as an answer: an upstream nix-darwin that
# quotes or redirects its guard differently parses to zero jobs, and the removal
# set would then be "every job in the running system". Plan announcing that a
# rebuild is about to unload the bar, the tiling and the palette is worse than
# plan saying nothing, so a parse miss is reported AS a parse miss.
sed 's#&> /dev/null#>/dev/null 2>\&1#' "$tmp/new-activate" >"$tmp/drifted-activate"
drift="$(plan_services "$tmp/drifted-activate" "$tmp/old-activate")"
has 'could not read any launchd guard' "$drift"
lacks 'will remove' "$drift"

# ~user is expanded from the user database, never by eval'ing a generated path.
# There is no dscl on Linux, so the fallback (this user's own home) is what CI
# asserts; either way the point is that a tilde never reaches `diff` unexpanded.
case "$(expand_tilde '~someone/Library/LaunchAgents/x.plist')" in
  /*/Library/LaunchAgents/x.plist) : ;;
  *) fail "expand_tilde left a tilde in place" ;;
esac
test "$(expand_tilde /already/absolute)" = /already/absolute || fail "expand_tilde mangled an absolute path"

# ---- what makes the settings live -------------------------------------------
res="$(plan_restarts "$tmp/new-activate")"
has 'restarts Finder, SystemUIServer' "$res"
has 'broadcasts activateSettings' "$res"
has 'posts AppleDatePreferencesChangedNotification' "$res"
test -z "$(plan_restarts "$tmp/bare-activate")" \
  || fail "plan_restarts announced restarts for a script that has none"

# ---- the worktree it was reading all along ----------------------------------
# The original bug: `haus plan` run from an agent lane previewed main, silently.
git init -q "$tmp/cfg"
git -C "$tmp/cfg" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
printf '{ }\n' >"$tmp/cfg/flake.nix"
git -C "$tmp/cfg" add flake.nix
git -C "$tmp/cfg" -c user.email=t@t -c user.name=t commit -q -m flake
git -C "$tmp/cfg" worktree add -q -b lane "$tmp/lane"

# The function reads $CONSUMER live, which haus.sh resolved from HAUS_CONSUMER
# once at load — so driving it means setting CONSUMER itself.
# shellcheck disable=SC2034
CONSUMER="$tmp/cfg"
warned="$(cd "$tmp/lane" && consumer_worktree_warning)"
has 'this is a worktree of your config' "$warned"
has "HAUS_CONSUMER=$tmp/lane" "$warned"

test -z "$(cd "$tmp/cfg" && consumer_worktree_warning)" \
  || fail "the main checkout of the config warned about itself"
test -z "$(cd "$tmp" && consumer_worktree_warning)" \
  || fail "a directory outside any repo warned"
# Pointed AT the lane, there is nothing to warn about — that IS the escape hatch.
# shellcheck disable=SC2034
CONSUMER="$tmp/lane"
test -z "$(cd "$tmp/lane" && consumer_worktree_warning)" \
  || fail "HAUS_CONSUMER pointing at this very tree still warned"

# A config that is a SUBDIRECTORY of a bigger dotfiles repo. The worktree's
# common dir is then the outer repo's, which never equals "$CONSUMER/.git" — so
# a constructed-path comparison would switch the warning off for exactly the
# layout that needs it.
mkdir -p "$tmp/dots/nix"
git init -q "$tmp/dots"
printf '{ }\n' >"$tmp/dots/nix/flake.nix"
git -C "$tmp/dots" add nix/flake.nix
git -C "$tmp/dots" -c user.email=t@t -c user.name=t commit -q -m init
git -C "$tmp/dots" worktree add -q -b outer-lane "$tmp/dots-lane"
# shellcheck disable=SC2034
CONSUMER="$tmp/dots/nix"
has 'this is a worktree of your config' "$(cd "$tmp/dots-lane/nix" && consumer_worktree_warning)"

# The library hook must not brick a normally-executed haus: `return` outside a
# sourced script is fatal, so keying only on the variable would make one
# exported HAUS_LIB turn every later `haus` in that shell into exit 2.
HAUS_LIB=1 bash "$repo/modules/den/haus.sh" --help >"$tmp/help.out" 2>&1 \
  || fail "HAUS_LIB in the environment broke a normally-run haus"
grep -q 'haus plan' "$tmp/help.out" || fail "haus --help printed no usage under HAUS_LIB"

printf 'all haus plan tests passed\n'

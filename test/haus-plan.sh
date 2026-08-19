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
source "$repo/modules/core/haus.sh"

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
# calls core renders, and the hop to the per-user wrapper.
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
# The fixture above sets no logout-only domain, so the OTHER half of
# plan_restarts must stay silent. Worth asserting rather than assuming: the
# warning is the one line in this function that fires on a minority of machines,
# which makes "it always prints" the failure nobody would notice.
lacks 'waits for a logout' "$res"
test -z "$(plan_restarts "$tmp/bare-activate")" \
  || fail "plan_restarts announced restarts for a script that has none"

# The logout half, on a script that DOES declare one. Both real domains, because
# the line core emits carries them space-separated on one line and the reader has
# to split them — a parser that took the whole tail as a single name would print
# "com.apple.WindowManager com.apple.loginwindow" as one item and still look
# plausible. Kept as a fixture rather than derived from restart-map.nix, for the
# same reason the rest of this file greps the built script: the point is what a
# rebuild actually contains, not a second copy of the table.
printf 'echo "haus: waits-for-logout com.apple.loginwindow com.apple.WindowManager" >&2\n' \
  >"$tmp/logout-activate"
res="$(plan_restarts "$tmp/logout-activate")"
has 'waits for a logout' "$res"
# Sorted, and `LC_ALL=C` means ASCII order rather than dictionary order — so
# `com.apple.WindowManager` comes FIRST, because uppercase W sorts before
# lowercase l. Written out the way it actually prints rather than the way it
# reads: this is the same collation the reader uses everywhere else in haus.sh,
# and asserting the pretty order would be asserting a bug.
has 'com.apple.WindowManager, com.apple.loginwindow' "$res"
# It is a WARNING and its own line, never folded into the "every rebuild also…"
# sentence: that one says what will happen, this says what won't.
lacks 'every rebuild also' "$res"

# ---- which declared plist keys the checker can SEE ---------------------------
# `declared_defaults` is what `haus diff` and `haus plan` compare the live
# machine against, so a key it cannot parse is a key haus silently has no
# opinion about — indistinguishable, from the outside, from a key that agrees.
#
# nix-darwin emits TWO shapes and this pins both, because for a while it only
# read one. A USER default arrives through the `launchctl asuser … sudo … --`
# wrapper; a SYSTEM default (system.defaults.loginwindow.*) is written bare, as
# root, to an absolute /Library/Preferences/<domain>. Matching only the wrapped
# shape is how six shipped options were invisible to the checker on day one.
plistfix() { # <domain-or-path> <key> <value-xml>
  printf "%s '<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" "defaults write $1 $2"
  printf '<plist version="1.0"><%s/></plist>'"'"'\n' "$3"
}
{
  # wrapped: how every user-level domain arrives
  printf 'launchctl asuser 501 sudo --user=fakeuser -- '
  plistfix com.apple.dock autohide true
  # bare + absolute: how a system-level domain arrives
  plistfix /Library/Preferences/com.apple.loginwindow GuestEnabled false
  # -g is spelled that way on the command line and NSGlobalDomain everywhere else
  printf 'launchctl asuser 501 sudo --user=fakeuser -- '
  plistfix -g InitialKeyRepeat integer
} >"$tmp/defaults-activate"
res="$(declared_defaults "$tmp/defaults-activate" | cut -f1,2)"
has 'com.apple.dock	autohide' "$res"
has 'NSGlobalDomain	InitialKeyRepeat' "$res"
# The regression this section exists for. Note the domain is reported WITHOUT
# the /Library/Preferences prefix: one domain must never be two rows, or
# classify_key and the restart/reachability tables — all keyed by the bare
# spelling — would miss it while the diff still printed something plausible.
has 'com.apple.loginwindow	GuestEnabled' "$res"
lacks '/Library/Preferences' "$res"

# ---- what the settings NEED before they can land (§5.12) --------------------
# The reachability announcement core renders beside the restart calls. Same
# discipline as above — the parser reads the built script, so what's worth
# pinning is that it still reads the shape core emits.
#
# `has_fda` is redefined per case rather than mocked through a flag, because the
# whole point of these four lines is that the verdict is the SAME table read
# crossed with a per-app capability: the fixtures below are one configuration
# seen from two apps, which is exactly the asymmetry §5.12 exists to make
# visible. (Redefining it is also what keeps this hermetic — a real read would
# answer differently on CI's Linux and on a granted Mac.)
{
  printf 'echo "haus: needs-full-disk-access com.apple.universalaccess" >&2\n'
  printf 'echo "haus: writes-but-does-nothing com.apple.Accessibility" >&2\n'
} >"$tmp/fda-guarded-activate"
printf 'echo "haus: aborts-without-full-disk-access com.apple.universalaccess" >&2\n' \
  >"$tmp/fda-unguarded-activate"

eval "real_has_fda() $(declare -f has_fda | tail -n +2)"   # put it back afterwards
has_fda() { return 1; }
res="$(plan_permissions "$tmp/fda-guarded-activate" 2>&1)"
has 'com.apple.universalaccess' "$res"
has 'will be skipped' "$res"
has 'writes and changes nothing' "$res"
res="$(plan_permissions "$tmp/fda-unguarded-activate" 2>&1)"
has 'would ABORT activation' "$res"

has_fda() { return 0; }
res="$(plan_permissions "$tmp/fda-guarded-activate" 2>&1)"
has 'this app has it' "$res"
lacks 'will be skipped' "$res"
res="$(plan_permissions "$tmp/fda-unguarded-activate" 2>&1)"
lacks 'would ABORT activation' "$res"

# The common case: a configuration that declares nothing protected says nothing
# at all. A permission line on every rebuild of every machine is noise, and
# noise is what makes the one that matters unreadable.
test -z "$(plan_permissions "$tmp/bare-activate" 2>&1)" \
  || fail "plan_permissions announced a grant for a script that needs none"

# ---- the guard the announcement is the front door for -----------------------
# `guard_unguarded_fda` is what stops the one failure that costs the machine
# rather than the setting, and its whole history is having asked the wrong
# question: it used to begin `under_agent || return 0`, which let every non-Claude
# agent through and refused an FDA-holding Claude pane that was always going to
# work. So the cases worth pinning are the ones that shape has no answer for —
# a HUMAN without the grant must be refused, and an agent WITH it must not be.
# There is deliberately no client/persona input to assert about.
#
# `universalaccess_keys` is stubbed because the real one evaluates a darwin
# system; what's under test is the decision, not the query.
guard_says() { # <fda: yes|no> <raw keys> [VAR=VAL…] -> "refused" | "proceeded"
  # `stub_keys`, not `keys`: bash scopes dynamically, and the function under test
  # declares `local keys` of its own — a stub reading `$keys` would see THAT one,
  # empty, and every case would come back "proceeded" for the wrong reason.
  local fda="$1" stub_keys="$2" kv
  shift 2
  ( set +e
    if [ "$fda" = yes ]; then has_fda() { return 0; }; else has_fda() { return 1; }; fi
    universalaccess_keys() { printf '%s' "$stub_keys"; }
    for kv in "$@"; do export "${kv?}"; done
    # One more subshell: the refusal path is `exit 1`, which would take this
    # whole helper with it rather than becoming a status to report.
    ( guard_unguarded_fda probe ) >/dev/null 2>&1
    if [ $? = 0 ]; then echo proceeded; else echo refused; fi
  )
}

test "$(guard_says no reduceTransparency)" = refused \
  || fail "guard let an unguarded universalaccess write through without the grant"
test "$(guard_says yes reduceTransparency)" = proceeded \
  || fail "guard refused a rebuild the app could actually complete"
test "$(guard_says no '')" = proceeded \
  || fail "guard refused a config that writes nothing TCC-protected"
test "$(guard_says no reduceTransparency HAUS_FDA_ANYWAY=1)" = proceeded \
  || fail "guard ignored its escape hatch"
test "$(guard_says no reduceTransparency HAUS_AGENT_REBUILD=1)" = proceeded \
  || fail "guard dropped the escape hatch's previous name"

eval "has_fda() $(declare -f real_has_fda | tail -n +2)"

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

# ---- the guarded accessibility writer ----------------------------------------
# core emits `haus.accessibility.*` as its OWN shell calls rather than as typed
# `defaults write` lines (the write has to survive a missing FDA grant), so
# `haus diff` can only see those keys through this parser. Its failure mode is
# silence: a declared key it can't match is reported as undeclared, which reads
# exactly like a key nobody set.
#
# Two shapes, one of which is new as of 2026-08-14: the call carries `defaults
# write`'s type flag now, because `mouseDriverCursorSize` is a float and every
# other key here is a bool. The float also needs canonicalising — Nix stringifies
# 3.0 as "3.000000" while `defaults read` prints "3", and without %g every diff
# would report that key as changed forever, on a machine where it is correct.
{
  printf 'hausAccessibility reduceMotion -bool true\n'
  printf 'hausAccessibility mouseDriverCursorSize -float 3.000000\n'
  printf 'hausAccessibility closeViewScrollWheelToggle -bool false\n'
  # Not a call core generates — the function DEFINITION, which contains the same
  # word and must not be parsed as a declared key.
  printf 'hausAccessibility() {\n'
} >"$tmp/a11y-activate"
#
# Compared WHOLE and exactly, not with `has`: a substring assertion for
# "mouseDriverCursorSize<TAB>3" passes on the un-canonicalised "3.000000" too,
# so the only check that can actually see the %g is an equality one. (Found by
# mutating the parser and watching the substring version stay green.)
a11y="$(declared_a11y_calls "$tmp/a11y-activate")"
test "$a11y" = "$(printf 'com.apple.universalaccess\treduceMotion\ttrue
com.apple.universalaccess\tmouseDriverCursorSize\t3
com.apple.universalaccess\tcloseViewScrollWheelToggle\tfalse')" \
  || fail "declared_a11y_calls read the writer's calls wrong: $a11y"

# The library hook must not brick a normally-executed haus: `return` outside a
# sourced script is fatal, so keying only on the variable would make one
# exported HAUS_LIB turn every later `haus` in that shell into exit 2.
HAUS_LIB=1 bash "$repo/modules/core/haus.sh" --help >"$tmp/help.out" 2>&1 \
  || fail "HAUS_LIB in the environment broke a normally-run haus"
grep -q 'haus plan' "$tmp/help.out" || fail "haus --help printed no usage under HAUS_LIB"

printf 'all haus plan tests passed\n'

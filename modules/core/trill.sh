#!/bin/sh
# `trill` — reach the notification compositor from a shell, wherever it was
# installed.
#
# Trill.app IS the CLI: one signed executable inside the bundle serves both the
# daemon and every verb (`send`, `ask`, `resolve`, `doctor`, `ping`). What it
# has never had is a name a shell can find. trill itself now places a link for
# the install sources it controls, but that link only lands in a directory the
# login shell's PATH already names — and on a nix-managed Mac there usually
# isn't one: every writable directory on PATH here belongs to a profile, which
# is a symlink chain into the read-only store. Measured on mbp 2026-08-25: the
# whole login PATH, and not one home-owned writable entry in it.
#
# So the desktop puts the name on PATH, the way it already does for perch
# (modules/shelf's `perch-cli-link`). A WRAPPER rather than a symlink, and the
# difference is the whole point: nix has to decide at build time, and whether
# Trill.app exists is a runtime fact. A symlink into a bundle that isn't there
# is a `trill` that `command -v` finds and every call fails on — strictly worse
# than no `trill` at all. This resolves each time it runs, and when there is
# nothing to resolve it says so in one line instead of a bare 127.
#
# Kept deliberately dumb — resolve, exec, or explain. Every verb, flag and exit
# code is trill's, and this must never grow an opinion about any of them: the
# process it execs IS trill, so `trill ask`'s pill indices and `trill doctor`'s
# exit 5 come back untouched.
#
# ⚠️ This shadows a `trill` from anywhere later on PATH, and it must stay the
# ONLY `bin/trill` haus ships — two packages putting that name in
# /run/current-system/sw/bin is a file collision the system build refuses, not a
# harmless duplicate.
#
# This comment used to say the room that made trill a flake input would REPLACE
# this file. It doesn't, and shouldn't: ../trill (haus.trill.enable) places the
# bundle at /Applications/Trill.app — the second candidate below — and puts
# nothing on PATH. The room is also off by default and there is no cask, so on
# most machines Trill.app is somewhere this file has to go looking for. Build
# time cannot answer a runtime question; that is the whole argument, and having
# a room does not change it.

set -u

# $TRILL_APP first, so a person testing a branch build can point at it without
# touching the desktop. Then the two places every install source puts a bundle.
#
# Both are `:-` guarded. `set -u` plus a bare `$HOME` exits **1**, and 1 is a
# code the caller reads as "trill ran and rejected the call" rather than "no
# Trill.app" — a launchd context with no HOME would be misdiagnosed as a bug in
# whatever asked for the banner.
for candidate in \
    "${TRILL_APP:-}" \
    "${HOME:-}/Applications/Trill.app" \
    "/Applications/Trill.app"
do
    [ -n "$candidate" ] || continue
    binary="$candidate/Contents/MacOS/Trill"
    if [ -x "$binary" ]; then
        exec "$binary" "$@"
    fi
done

# 127 is the shell's own "command not found", which is the honest code: from
# the caller's side the command genuinely isn't there. It is NOT one of trill's
# — its 1/2/3/4/5 all mean the CLI ran and had something to say — so a caller
# checking for "daemon down" (2) can't mistake this for it.
cat >&2 <<'MESSAGE'
trill: Trill.app isn't installed on this Mac.

  Looked in ~/Applications and /Applications (set TRILL_APP to point elsewhere).
  Get it from https://github.com/hausfold/trill — the app is its own CLI, so
  installing the bundle is the whole install.
MESSAGE
exit 127
